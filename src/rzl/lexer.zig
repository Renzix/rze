const std = @import("std");

const tok = @import("token.zig");

pub fn isSymbolChar(ch: u8) bool {
    return switch (ch) {
        'a'...'z', 'A'...'Z' => true,
        '0'...'9' => true,
        '+', '-', '*', '/', '=', '<', '>', '!', '?', '$', '%', '&', '~', '_' => true,
        else => false,
    };
}

pub const Lexer = struct {
    token_list: std.ArrayList(tok.Token),
    allocator: std.mem.Allocator,

    pub fn init() Lexer {
        return Lexer{ .token_list = .empty, .allocator = std.heap.c_allocator };
    }
    pub fn deinit(self: *Lexer) void {
        self.token_list.deinit();
    }
    pub fn run(self: *Lexer, code: []u8) !std.ArrayList(tok.Token) {
        var index: u64 = 0;
        while (index < code.len) : (index += 1) {
            switch (code[index]) {
                '(' => {
                    const token = tok.Token{ .token_type = tok.TokenType.L_PAREN, .contents = "(" };
                    try self.token_list.append(self.allocator, token);
                },
                ')' => {
                    const token = tok.Token{ .token_type = tok.TokenType.R_PAREN, .contents = ")" };
                    try self.token_list.append(self.allocator, token);
                },
                'a'...'z', 'A'...'Z' => {
                    const start = index;
                    while (index < code.len and isSymbolChar(code[index])) {
                        index += 1;
                    }
                    const symbol = code[start..index];
                    const token = tok.Token{ .token_type = tok.TokenType.SYMBOL, .contents = symbol };
                    try self.token_list.append(self.allocator, token);
                    index -= 1;
                },
                '+' => {
                    // append OPERATOR
                },
                else => {
                    std.debug.print("Unknown char {}\n", .{code[index]});
                },
            }
        }
        return self.token_list;
    }
};
