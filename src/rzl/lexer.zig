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
pub fn isIntegerChar(ch: u8) bool {
    return switch (ch) {
        '0'...'9' => true,
        else => false,
    };
}

pub fn isWhiteSpaceChar(ch: u8) bool {
    return switch (ch) {
        ' ', '\n', '\r' => true,
        else => false,
    };
}

pub const Lexer = struct {
    token_list: std.ArrayList(tok.Token),
    allocator: std.mem.Allocator,
    code: []u8,
    index: u64,

    pub fn init() Lexer {
        return Lexer{
            .token_list = .empty,
            .allocator = std.heap.c_allocator,
            .code = undefined,
            .index = undefined,
        };
    }
    pub fn deinit(self: *Lexer) void {
        self.token_list.deinit();
    }
    pub fn run(self: *Lexer, code: []u8) !std.ArrayList(tok.Token) {
        self.code = code;
        self.index = 0;
        while (self.index < self.code.len) {
            switch (self.code[self.index]) {
                '(' => {
                    const token = tok.Token{ .token_type = tok.TokenType.L_PAREN, .contents = "(" };
                    try self.token_list.append(self.allocator, token);
                    self.index += 1;
                },
                ')' => {
                    const token = tok.Token{ .token_type = tok.TokenType.R_PAREN, .contents = ")" };
                    try self.token_list.append(self.allocator, token);
                    self.index += 1;
                },
                'a'...'z', 'A'...'Z', '0'...'9', '+', '-', '*', '/' => {
                    std.debug.print("Generic loop...\n", .{});
                    const isInteger = try self.tryInteger();
                    if (isInteger) continue;
                    std.debug.print("Didnt find int, looking for symbol\n", .{});
                    try self.trySymbol();
                },
                ' ', '\n', '\r' => {
                    self.index += 1;
                },
                else => {
                    std.debug.print("Unknown char {}\n", .{self.code[self.index]});
                    self.index += 1;
                },
            }
        }
        return self.token_list;
    }
    fn tryInteger(self: *Lexer) !bool {
        const start = self.index;
        while (self.index < self.code.len and isIntegerChar(self.code[self.index])) {
            self.index += 1;
        }
        if (!isWhiteSpaceChar(self.code[self.index]) and self.code[self.index] != ')') {
            std.debug.print("Found: THIS {}!\n", .{self.code[self.index]});
            self.index = start;
            return false;
        }
        const integer = self.code[start..self.index];
        const token = tok.Token{ .token_type = tok.TokenType.INTEGER, .contents = integer };
        try self.token_list.append(self.allocator, token);
        std.debug.print("Found Int \"{s}\"\n", .{integer});
        return true;
    }
    // fn tryDouble(_: *Lexer) !bool {
    //     return false;
    // }
    fn trySymbol(self: *Lexer) !void {
        const start = self.index;
        while (self.index < self.code.len and isSymbolChar(self.code[self.index])) {
            self.index += 1;
        }
        const symbol = self.code[start..self.index];
        const token = tok.Token{ .token_type = tok.TokenType.SYMBOL, .contents = symbol };
        std.debug.print("Found Symbol \"{s}\"\n", .{symbol});
        try self.token_list.append(self.allocator, token);
    }
};
