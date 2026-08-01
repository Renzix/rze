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
    runtime: *Runtime,
    reg: u8,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, rt: *Runtime) Compiler {
        return .{
            .prog = undefined,
            .i = 0,
            .bytecode = .empty,
            .runtime = rt,
            .reg = 0,
            .allocator = alloc,
        };
    }

    pub fn reset(self: *Compiler) void {
        self.i = 0;
        self.bytecode.clearRetainingCapacity();
        self.reg = 0;
    }

    pub fn run(self: *Compiler, prog: ast.Program) std.ArrayList(inst) {
        self.reset();
        self.prog = prog;
        // Compile the AST to bytecode
        for (prog.andors.items, prog.background.items) |andor, _| {
            // log("line {}, contents: {any}, background: {}", .{index, andor,background});
            self.compileAndOr(andor); // @TODO(Renzix): Handle background
        }
        log("{}", .{self.bytecode});
        self.emit(inst.exit());
        bc.prettydump(self.bytecode, self.runtime);
        return self.bytecode;
    }

    pub fn compileAndOr(self: *Compiler, andor: ast.AndOr) void {
        const reg = self.reg;
        var lastjump: ?usize = null;
        var lastjumpop: bc.opcode = .invalid;
        for (andor.pipelines.items, andor.and_or_list.items) |pipe, op| {
            self.compilePipeline(pipe);
            if (lastjump) |lj|
                self.emitReplace(lj, inst.iAsBx(lastjumpop, reg, @intCast(self.bytecode.items.len - lj - 1)));
            lastjumpop = switch (op) {
                .and_if => .jnz,
                .or_if  => .jz,
                .end    => break,
            };
            lastjump = self.reserve();
        }
    }

    pub fn compilePipeline(self: *Compiler, pipeline: ast.Pipeline) void {
        // This is so i can have infinite pipes =) (not that the OS will let me)
        var pipein: u8 = undefined;
        var pipeout: u8 = undefined;
        var prevpipein: u8 = undefined;
        var prevpipeout: u8 = undefined;
        const initReg = self.reg;
        // toggle between the first and last 2 registers
        const pipeRegs = [4]u8{ self.newReg(), self.newReg(), self.newReg(), self.newReg() };
        for (pipeline.cmds.items, 0..) |pl, pindex| {
            const fds: [2]u8 = blk: {
                if (pipeline.cmds.items.len==1) {  // real real
                    const loop = (pindex % 2) * 2;
                    const stdinreg = pipeRegs[loop];
                    const stdinfd = self.runtime.stdinfd;
                    self.emit(inst.iABx(.loadc, stdinreg, stdinfd));
                    const stdoutreg = pipeRegs[loop+1];
                    const stdoutfd = self.runtime.stdoutfd;
                    self.emit(inst.iABx(.loadc, stdoutreg, stdoutfd));
                    break :blk .{ stdinreg, stdoutreg };
                } else if((pipeline.cmds.items.len-1)==pindex) { // pipe real
                    const loop = (pindex % 2) * 2;
                    const stdoutreg = pipeRegs[loop];
                    const stdoutfd = self.runtime.stdoutfd;
                    self.emit(inst.iABx(.loadc, stdoutreg, stdoutfd));
                    break :blk .{ pipein, stdoutreg };
                } else if(pindex==0) { // real pipe
                    const loop = (pindex % 2) * 2;
                    pipein = pipeRegs[loop]; // pass to next?
                    pipeout = pipeRegs[loop+1];
                    self.emit(inst.iABC(.mkpipe, pipein, pipeout, undefined));
                    const stdinreg = self.newReg();
                    const stdinfd = self.runtime.stdinfd;
                    self.emit(inst.iABx(.loadc, stdinreg, stdinfd));
                    break :blk .{ stdinreg, pipeout };
                } else { // pipe pipe
                    const loop = (pindex % 2) * 2;
                    pipein = pipeRegs[loop]; // pass to next?
                    pipeout = pipeRegs[loop+1];
                    self.emit(inst.iABC(.mkpipe, pipein, pipeout, undefined));
                    break :blk .{ prevpipein, pipeout };
                }
            };
            self.emit(inst.iABC(.setio, fds[0], 0x00, undefined)); // stdin
            self.emit(inst.iABC(.setio, fds[1], 0x01, undefined)); // stdout
            self.compileCommand(pl);
            if (pindex > 0) {
                self.emit(inst.iABC(.pipeclose, prevpipein, prevpipeout, undefined));
            }
            prevpipein = pipein;
            prevpipeout = pipeout;
        }

        self.reg = initReg;
        self.emit(inst.iABC(.wait, self.reg, undefined, undefined));
        if (pipeline.bang)
            self.emit(inst.iABC(.not, self.reg, undefined, undefined));
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
            const initReg = self.reg;
            const exec = self.compileExecutable(sc.cmd.?);
            for (sc.args.items) |arg| {
                _ = self.compileWord(arg);
            }
            self.emit(inst.iABC(.call, exec, 0x01, @intCast(sc.args.items.len)));
            self.reg = initReg;
            // @TODO(Renzix): Redirection
        } else {
            for (sc.assignments.items) |assign| {
                log("name: {s}", .{assign.name});
                var reg = self.reg;
                if (assign.value) |val| {
                    _ = self.compileWord(val);
                } else {
                    // var=
                    var sX = str.CreateAllocatedStr("", self.allocator);
                    var rzv = rzval.initString(&sX.header);
                    rzv.nullable = true;
                    const rX = self.runtime.addStringConstant(rzv);
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
        // @TODO(Renzix): if too big then use a array or maybe varargs?
        const initReg = self.reg;
        for (words.items) |word| {
            switch (word) {
                .literal => {
                    var sX = str.CreateAllocatedStr(word.literal.text, self.allocator);
                    const rX = self.runtime.addStringConstant(rzval.initString(&sX.header));
                    const reg = self.newReg();
                    self.emit(inst.iABx(.loadc, reg, rX));
                },
                .expand => {
                    const reg = self.newReg();
                    if(self.runtime.findGlobal(word.expand.name)) |slot| {
                        self.emit(inst.iABx(.loadg, reg, slot));
                    } else {
                        var sX = str.CreateAllocatedStr("", self.allocator);
                        var rzv = rzval.initString(&sX.header);
                        rzv.nullable = true;
                        const rX = self.runtime.addStringConstant(rzv);
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
        self.bytecode.append(self.allocator, ins) catch @panic("oom");
    }

    pub fn emitReplace(self: *Compiler, loc: usize, ins: inst) void {
        self.bytecode.items[loc]=ins;
    }

    pub fn reserve(self: *Compiler) usize {
        self.bytecode.append(self.allocator, inst.iABC(.invalid, undefined, undefined, undefined)) catch @panic("oom");
        return self.bytecode.items.len-1;
    }

    pub fn newReg(self: *Compiler) u8 {
        self.reg += 1;
        return self.reg-1;
    }
};
