const std = @import("std");

const tok = @import("token.zig");
const ast = @import("ast.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    token_list: std.ArrayList(tok.Token),
    ast: std.ArrayList(ast.SExpr),
    index: u32,
    pub fn init() Parser {
        return .{
            .allocator = std.heap.c_allocator,
            .token_list = .empty,
            .index = 0,
            .ast = .empty,
        };
    }
    pub fn deinit(_: *Parser) void {
        //
    }
    pub fn run(self: *Parser, token_list: std.ArrayList(tok.Token)) !*ast.SExpr {
        self.token_list = token_list;
        std.debug.print("token_list: {}\n", .{token_list});
        const sexp = self.parseSExpr();
        // const tempsexp = sexp catch unreachable();
        // printSExpr(tempsexp);
        // std.debug.print("\n", .{});
        return sexp;
    }
    pub fn parseSExpr(self: *Parser) !*ast.SExpr {
        if (self.index >= self.token_list.items.len) {
            return self.createNode(.{ .atom = .{ .nil = {} } });
        }

        if (self.acceptToken(tok.TokenType.L_PAREN)) {
            if (self.acceptToken(tok.TokenType.R_PAREN)) {
                return self.createNode(.{ .atom = .{ .nil = {} } });
            }
            const body = self.parseSExprBody();
            _ = try self.expectToken(tok.TokenType.R_PAREN);
            return body;
        }
        if (self.peekToken(tok.TokenType.INTEGER)) {
            const token = try self.expectToken(tok.TokenType.INTEGER);
            const val = try std.fmt.parseInt(i64, token.contents, 10);
            return try self.createNode(.{ .atom = .{ .integer = val } });
        }

        const token = try self.expectToken(tok.TokenType.SYMBOL);
        return self.createNode(.{ .atom = .{ .symbol = token.contents } });
    }
    fn parseSExprBody(self: *Parser) anyerror!*ast.SExpr {
        if (self.peekToken(tok.TokenType.R_PAREN)) {
            return try self.createNode(.{ .atom = .{ .nil = {} } });
        }

        const car = try self.parseSExpr();
        const cdr = try self.parseSExprBody();

        return try self.createNode(.{
            .cons = .{
                .car = car,
                .cdr = cdr,
            },
        });
    }

    // ai generated print
    pub fn printSExpr(expr: *const ast.SExpr) void {
        switch (expr.*) {
            .atom => |atom| switch (atom) {
                .symbol => |sym| std.debug.print("{s}", .{sym}),
                .string => |str| std.debug.print("\"{s}\"", .{str}),
                .integer => |val| std.debug.print("{}", .{val}),
                .double => |val| std.debug.print("{d}", .{val}),
                .boolean => |val| std.debug.print("{}", .{val}),
                .nil => std.debug.print("()", .{}),
            },
            .cons => |cell| {
                std.debug.print("(", .{});
                printListElements(&cell);
                std.debug.print(")", .{});
            },
        }
    }

    // ai generated print
    fn printListElements(cell: *const ast.Cons) void {
        // 1. Print the current item (car)
        printSExpr(cell.car);

        // 2. Look ahead at the rest of the list (cdr)
        switch (cell.cdr.*) {
            .atom => |atom| switch (atom) {
                // If the next element is nil, we reached the end of the list cleanly
                .nil => return,

                // If it's any other atom, this is a dotted pair: (a . b)
                else => {
                    std.debug.print(" . ", .{});
                    printSExpr(cell.cdr);
                },
            },
            // If the next element is another cons cell, print a space and continue down the chain
            .cons => |next_cell| {
                std.debug.print(" ", .{});
                printListElements(&next_cell);
            },
        }
    }

    fn createNode(self: *Parser, expr: ast.SExpr) !*ast.SExpr {
        const ptr = try self.allocator.create(ast.SExpr);
        ptr.* = expr;
        return ptr;
    }
    fn expectToken(self: *Parser, token_type: tok.TokenType) anyerror!tok.Token {
        if (self.index >= self.token_list.items.len) return error.UnexpectedEOF;
        const current = self.token_list.items[self.index];
        if (current.token_type == token_type) {
            self.index += 1;
            return current;
        }
        return error.UnexpectedToken;
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
        if (self.index >= self.token_list.items.len) return false;
        const ret = (self.token_list.items[self.index].token_type == token_type);
        if (ret) {
            self.index += 1;
            std.debug.print("Found Symbol!\n", .{});
        }
        return ret;
    }
};
