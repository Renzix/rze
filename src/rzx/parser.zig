const std = @import("std");
const lexer = @import("lexer.zig");

pub const Parser = struct {
    const allocator = std.heap.c_allocator;
    pub fn init() Parser {
        return Parser{};
    }
    pub fn parser_rec(self: *Parser, token_list: std.ArrayList(lexer.Token), index: u64) !lexer.SExpr {
        if (index >= token_list.items.len) {
            return lexer.SExpr.nil;
        }
        const token = token_list.items[index];
        std.debug.print("TOKEN: {s}\n", .{token.contents});

        const atom = try allocator.create(lexer.SExpr);
        // @TODO(Renzix): parse the token and determine lexer.SExpr
        // if (token.token_type == )
        atom.* = lexer.SExpr{ .atom = .{ .string = token.contents } };

        const next_node = try self.parser_rec(token_list, index + 1);
        const rest = try allocator.create(lexer.SExpr);
        rest.* = next_node;

        return lexer.SExpr{
            .cons = lexer.Cons{
                .car = atom,
                .cdr = rest,
            },
        };
    }
    pub fn parser(self: *Parser, token_list: std.ArrayList(lexer.Token)) !lexer.SExpr {
        const ast = try parser_rec(self, token_list, 0);
        return ast;
    }
    pub fn printSExpr(self: *Parser, expr: lexer.SExpr) void {
        switch (expr) {
            .atom => |a| {
                switch (a) {
                    .string => |s| std.debug.print("\"{s}\"", .{s}),
                    .symbol => |sym| std.debug.print("{s}", .{sym}),
                    .integer => |integer| std.debug.print("{}", .{integer}),
                    .boolean => |boolean| std.debug.print("{}", .{boolean}),
                    .double => |double| std.debug.print("{d}", .{double}),
                }
            },

            .cons => |cell| {
                std.debug.print("(", .{});
                printCons(self, cell);
                std.debug.print(")", .{});
            },
            .nil => {},
        }
    }
    pub fn printCons(self: *Parser, cell: lexer.Cons) void {
        printSExpr(self, cell.car.*);
        switch (cell.cdr.*) {
            .nil => {},
            .cons => |next| {
                std.debug.print(" ", .{});
                printCons(self, next);
            },
            else => {},
        }
    }
};

test "Basic Parser" {
    var rzx = Parser.init();
    // defer rzx.deinit();
    var token_list: std.ArrayList(lexer.Token) = .empty;
    defer token_list.deinit(std.heap.c_allocator);
    const token = lexer.Token{
        .token_type = lexer.TokenType.ASSIGNMENT_WORD,
        .sub_type = lexer.TokenSubType.UNKNOWN,
        .contents = "TEST=123",
    };
    try token_list.append(std.heap.c_allocator, token);
    const token2 = lexer.Token{
        .token_type = lexer.TokenType.WORD,
        .sub_type = lexer.TokenSubType.UNKNOWN,
        .contents = "ls",
    };
    try token_list.append(std.heap.c_allocator, token2);
    const ast = try rzx.parser(token_list);
    rzx.printSExpr(ast);
    std.debug.print("\n", .{});
}
