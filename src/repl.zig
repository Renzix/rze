const std = @import("std");
const print = @import("std").debug.print;

// const l = @import("rzl/lexer.zig");
// const p = @import("rzl/parser.zig");
// const c = @import("rzl/compiler.zig");
const p = @import("rzx/parser.zig");
const c = @import("rzx/compiler.zig");
const v = @import("rzvm/vm.zig");
const Runtime  = @import("rzvm/runtime.zig").Runtime;
const term = @cImport({
    @cInclude("io.h");
});

// In src/repl.zig
pub const repl = struct {
    code: [10240]u8,
    code_len: usize,
    proc: std.process.Init,
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
            .allocator = debug_alloc.allocator(),
            // .allocator = std.heap.c_allocator,
            .parser = undefined,
            .compiler = undefined,
            .vm = undefined,
        };
        const prompt = "rze> ";
        term.rzterm_init(prompt.ptr, prompt.len);
        var runtime = Runtime.init(self.allocator);
        runtime.setEnv(proc.environ_map);
        self.parser = p.Parser.init(self.allocator);
        self.compiler = c.Compiler.init(self.allocator, &runtime);
        self.vm = v.rzvm.init(self.allocator, self.proc.io, &runtime);
        return self;
    }
    pub fn run(self: *repl) u8 {
        while (self.vm.halt==null) {
            self.read() catch break; // @TODO(Renzix): Make better
            self.eval();
        }
        return self.vm.halt orelse 0;
    }

    pub fn read(self: *repl) !void {
        const n = term.rzterm_getline(&self.code, self.code.len);
        if (n < 0) return error.Eof;
        self.code_len = @intCast(n);
    }

    pub fn eval(self: *repl) void {
        if (self.code_len == 0) return;
        const prog = self.code[0..self.code_len];
        if (prog.len > 0 and prog[0] == ':') {
            self.replcommand(prog[1..]);
            return;
        }

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

    fn replcommand(self: *repl, line: []const u8) void {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const name = it.next() orelse return;

        if (std.mem.eql(u8, name, "regs")) {
            const start = nextint(&it, 0);
            const end = nextint(&it, 12);
            self.vm.dump(start, end);
        } else if (std.mem.eql(u8, name, "r")) {
            const r = nextint(&it, 0);
            self.vm.regprint(@intCast(r));
        } else if (std.mem.eql(u8, name, "constants")) {
            self.vm.runtime.printConstants();
        } else if (std.mem.eql(u8, name, "c")) {
            const constant = nextint(&it, 0);
            self.vm.runtime.printConstant(@intCast(constant));
        } else {
            print("unknown command: {s}\n", .{name});
        }
    }

    fn nextint(it: *std.mem.TokenIterator(u8, .any), default: usize) usize {
        const tok = it.next() orelse return default;
        return std.fmt.parseInt(usize, tok, 10) catch default;
    }
};
