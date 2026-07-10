const std = @import("std");

const tok = @import("token.zig");
const ast = @import("ast.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    token_list: std.ArrayList(tok.Token),
    index: u32,
    pub fn init() Parser {
        return .{ .allocator = std.heap.c_allocator, .token_list = .empty, .index = 0 };
    }
    pub fn deinit(_: *Parser) void {
        //
    }
    pub fn run(self: *Parser, token_list: std.ArrayList(tok.Token)) void {
        self.token_list = token_list;
        std.debug.print("token_list: {}\n", .{token_list});
        self.parseSExpr();
    }
    pub fn parseSExpr(self: *Parser) !*const ast.SExpr {
        self.expectToken(tok.TokenType.L_PAREN);
        if (self.peekChar('(')) {
            self.parseSExpr();
        } else if (self.acceptToken(tok.TokenType.SYMBOL)) {
            // TODO(Renzix): Add other types
            var end = true;
            while (end) {
                if (self.acceptToken(tok.TokenType.SYMBOL)) {} //
                else if (self.peekChar('(')) {
                    self.parseSExpr();
                } else if (self.acceptToken(tok.TokenType.INTEGER)) {} //
                else {
                    end = false;
                }
            }
        } else {
            unreachable();
        }
        self.expectToken(tok.TokenType.R_PAREN);
    }
    fn expectToken(self: *Parser, token_type: tok.TokenType) void {
        if (self.token_list.items[self.index].token_type == token_type) {
            self.index += 1;
            std.debug.print("Found Symbol!\n", .{});
        } else {
            unreachable();
        }
    }
    fn expectChar(self: *Parser, char: u8) void {
        if (self.token_list.items[self.index].contents[0] == char) {
            self.index += 1;
            std.debug.print("Found char: {}\n", .{char});
        } else {
            unreachable();
        }
    }
    fn peekChar(self: *Parser, char: u8) bool {
        return (self.token_list.items[self.index].contents[0] == char);
    }
    fn peekToken(self: *Parser, token_type: tok.TokenType) bool {
        return (self.token_list.items[self.index].token_type == token_type);
    }
    fn acceptToken(self: *Parser, token_type: tok.TokenType) bool {
        const ret = (self.token_list.items[self.index].token_type == token_type);
        if (ret) {
            self.index += 1;
            std.debug.print("Found Symbol!\n", .{});
        }
        return ret;
    }
};
