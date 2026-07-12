const std = @import("std");
const log = @import("std").debug.print;

// @TODO(Renzix): Move these types to their own file
pub const TokenType = enum {
    NONE,
    WORD,
    ASSIGNMENT_WORD,
    NAME,
    CONTROL_OPERATOR,
    NEWLINE,
    IO_NUMBER,
    IO_LOCATION,
};

const Quoted = enum {
    QUOTED_NONE,
    QUOTED_DOUBLE,
    QUOTED_SINGLE,
};

fn Charset(comptime chars: []const u8) [256]bool {
    var table = [_]bool{false} ** 256;
    for (chars) |c| table[c] = true;
    return table;
}

const WordChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "_${}\"'");

const AssignmentChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "_${}\"'" ++ "=");

// we parse and lex at the same time for shell!!!
pub const Parser = struct {
    code: []const u8,
    quoted: Quoted,
    token: TokenType,
    content: [100]u8, // make bigger if you make a string that is longer the 100 lines this will crash!
    content_len: usize,
    i: usize,
    start: usize,
    first_token: bool,
    // AST = std.ArrayList,
    const allocator = std.heap.c_allocator;

    pub fn init() Parser {
        return Parser{
            .code = undefined,
            .quoted = Quoted.QUOTED_NONE,
            .token = TokenType.NONE,
            .i = 0,
            .start = 0,
            .content = undefined,
            .content_len = 0,
            .first_token = false,
        };
    }
    pub fn run(self: *Parser, str: []const u8) void {
        self.code = str;
        // log("str: {}, content: {}\n", .{str.len, self.content.len});
        // std.debug.assert(self.content_len == str.len);
        var foundToken = (self.code.len != 0);
        while (self.code.len > self.i) {
            foundToken = self.lexToken();
        }
    }
    fn lexToken(self: *Parser) bool {
        var ch = self.code[self.i];

        while (self.i < self.code.len) {
            ch = self.code[self.i];
            switch (ch) {
                'a'...'z', 'A'...'Z' => {
                    if(self.lexWord()) return true;
                    if(self.lexAssignment()) return true;
                },
                else => {
                    log("Unknown char {c}\n", .{ch});
                },
            }
            self.i+=1;
        }
        return false;
    }
    fn lexWord(self: *Parser) bool {
        self.start = self.i;
        while(self.i < self.code.len and WordChars[self.code[self.i]]) {
            self.i += 1;
        }
        const len = self.i - self.start;
        @memcpy(self.content[0..len], self.code[self.start..self.i]);
        self.content_len = len;
        if (self.i < self.code.len and self.code[self.i]=='=') {
            return false;
        }
        log("Found Word\n", .{});
        self.token = TokenType.WORD;
        return true;
    }
    fn lexAssignment(self: *Parser) bool {
        self.start = self.i;
        while(self.i < self.code.len and AssignmentChars[self.code[self.i]]) {
            self.i += 1;
        }
        const len = self.i - self.start;
        @memcpy(self.content[0..len], self.code[self.start..self.i]);
        self.content_len = len;
        if (self.i < self.code.len and self.code[self.i]=='=') {
            return false;
        }
        log("Found Assignment\n", .{});
        self.token = TokenType.ASSIGNMENT_WORD;
        return true;
    }

};


// test "Basic Lexer" {
//     var rzx = Lexer.init();
//     // defer rzx.deinit();
//     var token_list: std.ArrayList(Token) = .empty;

//     try rzx.run("ls", &token_list);
//     try rzx.run("ls -l", &token_list);
//     try rzx.run("ls -l /home/user", &token_list);
//     try rzx.run("cd ..", &token_list);
// }

// test "String Run" {
//     var rzx = Lexer.init();
//     // defer rzx.deinit();
//     var token_list: std.ArrayList(Token) = .empty;
//     try rzx.run("echo \"hello world\"", &token_list);
//     try rzx.run("echo 'hello world'", &token_list);
//     try rzx.run("echo \"a string with 'single' quotes\"", &token_list);
//     try rzx.run("echo 'a string with \"double\" quotes'", &token_list);
//     try rzx.run("ls \"my report.txt\"", &token_list);
//     try rzx.run("echo \"   spaces  leading and trailing   \"", &token_list);
// }
// test "Variable Run" {
//     var rzx = Lexer.init();
//     // defer rzx.deinit();
//     var token_list: std.ArrayList(Token) = .empty;
//     try rzx.run("echo $VAR", &token_list);
//     try rzx.run("echo \"value: $HOME\"", &token_list);
//     try rzx.run("myvar=hello", &token_list);
//     try rzx.run("PATH=$PATH:/usr/bin", &token_list);
//     try rzx.run("echo ${BRACES}", &token_list);
//     try rzx.run("echo ${BRACES:-test}", &token_list);
// }

// test "Random Run" {
//     var rzx = Lexer.init();
//     // defer rzx.deinit();
//     var token_list: std.ArrayList(Token) = .empty;
//     try rzx.run("", &token_list);
//     try rzx.run("   ls   -l   ", &token_list);
//     try rzx.run("cmd | grep \"foo\"", &token_list);
//     try rzx.run("ls -a -l -h", &token_list);
// }
