const std = @import("std");
const log = @import("std").log.debug;
const ast = @import("ast.zig");

const inst  = @import("../rzvm/bytecode.zig").instruction;
const bc  = @import("../rzvm/bytecode.zig");
const str  = @import("../rzvm/datatypes/string.zig");
const Runtime  = @import("../rzvm/runtime.zig").Runtime;
const rzval = @import("../rzvm/rzvalue.zig").RzValue;

// @TODO(Renzix): Remove @intCast()

pub const Compiler = struct{
    prog: ast.Program,
    i: usize,
    bytecode: std.ArrayList(inst),
    runtime: Runtime,
    reg: u8,
    variableindex: u16,
    const allocator = std.heap.c_allocator;
    pub fn init() ?Compiler {
        const rt = Runtime.init();
        return .{
            .prog = undefined,
            .i = 0,
            .bytecode = .empty,
            .runtime = rt,
            .reg = 0,
            .variableindex = 0,
        };
    }

    pub fn run(self: *Compiler, prog: ast.Program) std.ArrayList(inst) {
        self.prog = prog;
        self.i = 0;
        // Compile the AST to bytecode
        for (prog.andors.items, prog.background.items) |andor, _| {
            // log("line {}, contents: {any}, background: {}", .{index, andor,background});
            self.compileAndOr(andor); // @TODO(Renzix): Handle background
        }
        log("{}", .{self.bytecode});
        self.emit(inst.exit());
        bc.dump(self.bytecode);
        return self.bytecode;
    }

    pub fn compileAndOr(self: *Compiler, andor: ast.AndOr) void {
        self.compilePipeline(andor.pipelines.items[0]);
        // @TODO(Renzix): for each andor
    }

    pub fn compilePipeline(self: *Compiler, pipeline: ast.Pipeline) void {
        var pipefds: [128]u8 = undefined;
        var pipefdcount: u16 = 0;
        var pipein: u8 = undefined;
        const initReg = self.reg;
        for (pipeline.cmds.items, 0..) |pl, pindex| {
            // create fd for stdin and stdout?
            const fds: [2]u8 = blk: {
                if (pipeline.cmds.items.len==1) {  // real real
                    const stdinreg = self.newReg();
                    const stdinfd = self.runtime.stdinfd;
                    self.emit(inst.iABx(.loadc, stdinreg, stdinfd));
                    const stdoutreg = self.newReg();
                    const stdoutfd = self.runtime.stdoutfd;
                    self.emit(inst.iABx(.loadc, stdoutreg, stdoutfd));
                    break :blk .{ stdinreg, stdoutreg };
                }
                else if((pipeline.cmds.items.len-1)==pindex) { // pipe real
                    const stdoutreg = self.newReg();
                    const stdoutfd = self.runtime.stdoutfd;
                    self.emit(inst.iABx(.loadc, stdoutreg, stdoutfd));
                    break :blk .{ pipein, stdoutreg };
                } else if(pindex==0) { // real pipe
                    pipein = self.newReg(); // pass to next?
                    const pipeout = self.newReg();
                    self.emit(inst.iABC(.mkpipe, pipein, pipeout, undefined));
                    pipefds[pipefdcount] = pipein;
                    pipefdcount += 1;
                    pipefds[pipefdcount] = pipeout;
                    pipefdcount += 1;
                    const stdinreg = self.newReg();
                    const stdinfd = self.runtime.stdinfd;
                    self.emit(inst.iABx(.loadc, stdinreg, stdinfd));
                    break :blk .{ stdinreg, pipeout };
                } else { // pipe pipe
                    const lastpipein = pipein;
                    pipein = self.newReg(); // pass to next?
                    const pipeout = self.newReg();
                    self.emit(inst.iABC(.mkpipe, pipein, pipeout, undefined));
                    pipefds[pipefdcount] = pipein;
                    pipefdcount += 1;
                    pipefds[pipefdcount] = pipeout;
                    pipefdcount += 1;
                    break :blk .{ lastpipein, pipeout };
                }
            };
            self.emit(inst.iABC(.setio, fds[0], 0x00, undefined)); // stdin
            self.emit(inst.iABC(.setio, fds[1], 0x01, undefined)); // stdout
            self.compileCommand(pl);
        }

        // @TODO(Renzix): close 3 at a time
        for (0..pipefdcount) |pipeindex| {
            self.emit(inst.iABC(.pipeclose, pipefds[pipeindex], undefined, undefined));
        }

        self.emit(inst.iABC(.wait, undefined, undefined, undefined));
        self.reg = initReg;
    }

    pub fn compileCommand(self: *Compiler, cmd: ast.Command) void {
        switch (cmd) {
            .simple_command => |sc| self.compileSimpleCommand(sc),
            .complex_command => @panic("Complex Command not currently supported"),
            .function_definition => @panic("Function definition not currently supported"),
        }
    }

    pub fn compileSimpleCommand(self: *Compiler, sc: ast.SimpleCommand) void {
        if (sc.cmd!=null) {
            const exec = self.compileExecutable(sc.cmd.?);
            for (sc.args.items) |arg| {
                _ = self.compileWord(arg);
            }
            self.emit(inst.iABC(.call, exec, 0x01, @intCast(sc.args.items.len)));
            // @TODO(Renzix): Redirection
        } else {
            for (sc.assignments.items) |assign| {
                log("name: {s}", .{assign.name});
                var reg = self.reg;
                if (assign.value) |val| {
                    _ = self.compileWord(val);
                } else {
                    // var=
                    var sX = str.CreateAllocatedStr("", allocator);
                    var rzv = rzval.initString(&sX.header);
                    rzv.nullable = true;
                    const rX = self.runtime.addConstant(rzv);
                    reg = self.newReg();
                    self.emit(inst.iABx(.loadc, reg, rX));
                }
                const v = self.runtime.reserveGlobal(assign.name);
                self.emit(inst.iABx(.storeg, reg, v));
            }
        }
    }

    pub fn compileExecutable(self: *Compiler, words: std.ArrayList(ast.Word)) u8 {
        const reg = self.compileWord(words);
        self.emit(inst.resolve(reg, .function));
        return reg;
    }

    pub fn compileWord(self: *Compiler, words: std.ArrayList(ast.Word)) u8 {
        // only use 1 reg by the end
        const initReg = self.reg;
        for (words.items) |word| {
            switch (word) {
                .literal => {
                    //@TODO(Renzix): if 2 of these happen in a row you can combine them
                    var sX = str.CreateAllocatedStr(word.literal.text, allocator);
                    const rX = self.runtime.addConstant(rzval.initString(&sX.header));
                    const reg = self.newReg();
                    self.emit(inst.iABx(.loadc, reg, rX));
                },
                .expand => {
                    const reg = self.newReg();
                    if(self.runtime.findGlobal(word.expand.name)) |slot| {
                        self.emit(inst.iABx(.loadg, reg, slot));
                    } else {
                        var sX = str.CreateAllocatedStr("", allocator);
                        var rzv = rzval.initString(&sX.header);
                        rzv.nullable = true;
                        const rX = self.runtime.addConstant(rzv);
                        self.emit(inst.iABx(.loadc, reg, rX));
                    }
                },
            }
        }
        if (words.items.len > 1)
            self.emit(inst.iABC(.concat, initReg, @as(u8, @intCast(words.items.len)), initReg));
        self.reg = initReg+1;
        return self.reg-1;
    }

    pub fn emit(self: *Compiler, ins: inst) void {
        self.bytecode.append(allocator, ins) catch @panic("oom");
    }

    pub fn newReg(self: *Compiler) u8 {
        self.reg += 1;
        return self.reg-1;
    }

    pub fn newVariable(self: *Compiler) u16 {
        self.variableindex += 1;
        return self.variableindex-1;
    }
};
