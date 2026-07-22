const std = @import("std");
const log = @import("std").log.debug;
const ast = @import("ast.zig");

const inst  = @import("../rzvm/bytecode.zig").instruction;
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
    const allocator = std.heap.c_allocator;
    pub fn init() ?Compiler {
        const rt = Runtime.init();
        return .{
            .prog = undefined,
            .i = 0,
            .bytecode = .empty,
            .runtime = rt,
            .reg = 0,
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
        return self.bytecode;
    }

    pub fn compileAndOr(self: *Compiler, andor: ast.AndOr) void {
        self.compilePipeline(andor.pipelines.items[0]);
        // @TODO(Renzix): for each andor
    }

    pub fn compilePipeline(self: *Compiler, pipeline: ast.Pipeline) void {
        self.compileCommand(pipeline.cmds.items[0]);
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
            self.compileExecutable(sc.cmd.?);
            for (sc.args.items) |arg| {
                self.compileWord(arg);
            }
            self.emit(inst.iABC(.call, 0x00, 0x01, @intCast(sc.args.items.len)));
        } else {
            // @TODO(Renzix): assignments
        }
    }

    pub fn compileExecutable(self: *Compiler, words: std.ArrayList(ast.Word)) void {
        for (words.items) |word| {
            var s0 = str.CreateAllocatedStr(word.literal.text, allocator);
            const r0 = self.runtime.setExecFunction(&s0.header, 2);
            const vr0 = self.runtime.intern(rzval.initFunction(r0));
            self.emit(inst.iABx(.loadg, self.newReg(), vr0));
        }
    }

    pub fn compileWord(self: *Compiler, words: std.ArrayList(ast.Word)) void {
        for (words.items) |word| {
            var sx = str.CreateAllocatedStr(word.literal.text, allocator);
            const vrx = self.runtime.intern(rzval.initString(&sx.header));
            self.emit(inst.iABx(.loadg, self.newReg(), vrx));
        }
    }

    pub fn emit(self: *Compiler, ins: inst) void {
        self.bytecode.append(allocator, ins) catch @panic("oom");
    }

    pub fn newReg(self: *Compiler) u8 {
        self.reg += 1;
        return self.reg-1;
    }
};
