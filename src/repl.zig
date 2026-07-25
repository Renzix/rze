const std = @import("std");

// const l = @import("rzl/lexer.zig");
// const p = @import("rzl/parser.zig");
// const c = @import("rzl/compiler.zig");
const p = @import("rzx/parser.zig");
const c = @import("rzx/compiler.zig");
const v = @import("rzvm/vm.zig");
const Runtime  = @import("rzvm/runtime.zig").Runtime;

// In src/repl.zig
pub const repl = struct {
    code: [10240]u8,
    code_len: usize,
    proc: std.process.Init,
    stdout_buf: [4096]u8,
    stdin_buf: [4096]u8,
    writer: std.Io.File.Writer,
    reader: std.Io.File.Reader,
    allocator: std.mem.Allocator,
    runtime: Runtime,
    parser: p.Parser,
    compiler: c.Compiler,
    vm: v.rzvm,

    pub fn init(proc: std.process.Init) repl {
        var debug_alloc: std.heap.DebugAllocator(.{}) =.init;

        var self = repl{
            .code = std.mem.zeroes([10240]u8),
            .code_len = 0,
            .proc = proc,
            .stdout_buf = undefined,
            .stdin_buf = undefined,
            .writer = undefined,
            .reader = undefined,
            .allocator = debug_alloc.allocator(),
            // .allocator = std.heap.c_allocator,
            .runtime = undefined,
            .parser = undefined,
            .compiler = undefined,
            .vm = undefined,
        };
        self.runtime = Runtime.init(self.allocator);
        self.parser = p.Parser.init(self.allocator);
        self.compiler = c.Compiler.init(self.allocator, &self.runtime);
        self.vm = v.rzvm.init(self.allocator, self.proc.io, &self.runtime);
        return self;
    }
    pub fn run(self: *repl) void {
        self.writer = std.Io.File.stdout().writer(self.proc.io, &self.stdout_buf);
        self.reader = std.Io.File.stdin().reader(self.proc.io, &self.stdin_buf);
        while (true) {
            self.read() catch break; // @TODO(Renzix): Make better
            self.eval();
        }
    }

    // I copy/pasted this, need to figure out how this works
    // and if this is horrible
    pub fn read(self: *repl) !void {
        const out = &self.writer.interface;
        try out.writeAll("rzx> ");
        try out.flush();

        const in = &self.reader.interface;
        const bare = (try in.takeDelimiter('\n')) orelse return error.Eof;
        const line = std.mem.trim(u8, bare, " \t\r\n");

        const n = @min(line.len, self.code.len);
        @memcpy(self.code[0..n], line[0..n]);
        self.code_len = n;
    }

    pub fn eval(self: *repl) void {
        if (self.code_len == 0) return;
        const prog = self.code[0..self.code_len];

        const ast = self.parser.run(prog) catch |err| {
            // @TODO(Renzix): Move all this terminal stuff to a seperate file
            std.debug.print("\x1b[91m\x1b[1m--------- PARSER ERROR --------\n", .{});
            std.debug.print("err: {any}\n", .{err});
            std.debug.print("-------------------------------\n\x1b[0m", .{});
            return;
        };

        const bytecode = self.compiler.run(ast.?);

        _ = self.vm.run(bytecode.items) catch {
            self.vm.dump(0, 12);
            @panic("AAAAAHHHH");
        };
    }
};
