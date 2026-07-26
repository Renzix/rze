const std = @import("std");
const print = @import("std").debug.print;

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
            .parser = undefined,
            .compiler = undefined,
            .vm = undefined,
        };
        var runtime = Runtime.init(self.allocator, self.proc);
        self.parser = p.Parser.init(self.allocator);
        self.compiler = c.Compiler.init(self.allocator, &runtime);
        self.vm = v.rzvm.init(self.allocator, self.proc.io, &runtime);
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
            // @TODO(Renzix): Move all this terminal stuff to a seperate file and probably write a
            // smaller version for the repl specifically
            print("\x1b[91m\x1b[1m--------- PARSER ERROR --------\n", .{});
            print("error: {t}\n", .{err});
            switch (err) {
                error.SyntaxError => {
                    const code       = self.parser.code;
                    const pos        = self.parser.diag.pos;
                    const code_start = if (std.mem.lastIndexOfScalar(u8, code[0..pos], '\n')) |n| n + 1 else 0;
                    const code_end   = std.mem.indexOfScalarPos(u8, code, pos, '\n') orelse code.len;
                    const code_str   = code[code_start..code_end];
                    const column     = pos - code_start;
                    const lineno     = std.mem.count(u8, code[0..code_start], "\n") + 1;
                    print("line:  {}\n", .{lineno});
                    print("code:  {s}\n", .{code_str});
                    print("       ", .{});
                    for (code_str[0..column]) |col| {
                        print("{c}", .{@as(u8, if (col == '\t') '\t' else ' ')});
                    }
                    print("^\n", .{});
                },
                error.Unimplemented => {
                    print("Send patches\n", .{});
                },
                else => {},
            }
            print("-------------------------------\n\x1b[0m", .{});
            return;
        };

        const bytecode = self.compiler.run(ast.?);

        _ = self.vm.run(bytecode.items) catch {
            self.vm.dump(0, 12);
            @panic("AAAAAHHHH");
        };
    }
};
