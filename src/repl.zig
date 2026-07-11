const std = @import("std");

const l = @import("rzl/lexer.zig");
const p = @import("rzl/parser.zig");
const c = @import("rzl/compiler.zig");

// In src/repl.zig
pub const repl = struct {
    code: [1024]u8,
    code_len: usize,
    stdout_buf: [2048]u8,
    stdin_buf: [2048]u8,
    stdout: *std.Io.Writer,
    stdin: *std.Io.Reader,
    writer: std.Io.File.Writer,
    reader: std.Io.File.Reader,

    pub fn init(proc: std.process.Init) repl {
        var self = repl{
            .code = std.mem.zeroes([1024]u8),
            .code_len = 0,
            .stdout_buf = undefined,
            .stdin_buf = undefined,
            .writer = undefined,
            .reader = undefined,
            .stdout = undefined,
            .stdin = undefined,
        };

        self.writer = std.Io.File.stdout().writer(proc.io, &self.stdout_buf);
        self.stdout = &self.writer.interface;

        self.reader = std.Io.File.stdin().reader(proc.io, &self.stdin_buf);
        self.stdin = &self.reader.interface;

        return self;
    }
    pub fn run(self: *repl) void {
        while (true) {
            self.read() catch unreachable; // @TODO(Renzix): Make better
            self.eval();
        }
    }

    pub fn read(self: *repl) !void {
        try self.stdout.writeAll("rzx> ");
        try self.stdout.flush();
        const bare_line = try self.stdin.takeDelimiter('\n') orelse std.process.exit(0);
        const line = std.mem.trim(u8, bare_line, "\r");
        // try self.stdout.print("Got {any}\n", .{line});
        // try self.stdout.flush();
        self.code_len = line.len;
        @memcpy(self.code[0..line.len], line);
    }
    pub fn eval(self: *repl) void {
        var lexer = l.Lexer.init();
        const token_list = lexer.run(self.code[0..self.code_len]) catch unreachable;
        for (token_list.items) |token| {
            std.debug.print("token: {}, content: {s}\n", .{ token.token_type, token.contents });
        }
        var parser = p.Parser.init();
        const ast = parser.run(token_list) catch unreachable;

        var compiler = c.Compiler.init();
        _ = compiler.run(ast) catch unreachable;

        // var vm = v.Rzvm.init();
        // const ret = vm.run(bytecode);
    }
};
