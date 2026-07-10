const std = @import("std");

const tok = @import("token.zig");
const ast = @import("ast.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    pub fn init() Parser {
        return .{ .allocator = std.heap.c_allocator };
    }
    pub fn deinit(_: *Parser) void {
        //
    }

    pub fn run(self: *Parser, token_list: std.ArrayList(tok.Token)) void {
        self.parseSExpr();
    }
    fn expectChar(_: Parser, token: tok.Token, char: u8) void {
        if (token.contents[0] != char)
            unreachable();
    }
};
