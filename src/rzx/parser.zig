const std = @import("std");
const log = @import("std").debug.print;

// @TODO(Renzix): Move these types to their own file
pub const TokenType = enum {
    NONE,
    WORD,
    ASSIGNMENT_WORD,
    NAME,
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
    ++ "0123456789" ++ "_${}\"'.");

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
        // var foundToken = (self.code.len != 0);

        _ = self.parseSimpleCommand();
        // while (self.code.len > self.i) {
        //     foundToken = self.lexToken();
        // }
    }
    fn parseSimpleCommand(self: *Parser) bool {
        self.first_token = true;
        if(self.parseCmdPrefix()) {
            self.first_token = false;
        }
        if(self.parseCmdName()) {
            self.first_token = false;
        }
        if(self.parseCmdSuffix()) {}
        return !self.first_token;
        // switch (ch) {
        //     '|', '>', '<'
        //     'a'...'z', 'A'...'Z' => {
        //         if(self.lexWord()) {
        //             // if first then set to cmd_name
        //             // else set to cmd suffex
        //         }
        //         if(self.lexAssignment()) return true;
        //     },
        //     else => {
        //         log("Unknown char {c}\n", .{ch});
        //     },
        // }
    }

    fn parseCmdPrefix(self: *Parser) bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            if (self.lexAssignment()) { found=true; continue; }
            if (self.parseIoRedirect()) { found=true; continue; }
            break;
        }
        return found;
    }

    fn parseCmdSuffix(self: *Parser) bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            if (self.lexWord()) { found=true; continue; }
            if (self.parseIoRedirect()) { found=true; continue; }
            break;
        }
        return found;
    }

    // @TODO(DeBruno): Add io_here and maybe io_location
    fn parseIoRedirect(self: *Parser) bool {
        // var found = false;
        _ = self.skipWhitespace();
        // self.lexIoNumber();
        _ = self.lexIoFile();
        return false;
    }

    fn lexIoFile(self: *Parser) bool {
        self.start = self.i;
        if (self.i >= self.code.len) return false;
        switch(self.code[self.i]) {
            '>' => {
                if (self.i+1 < self.code.len) {
                    switch (self.code[self.i+1]) {
                        '&' => { // GREATAND >&
                            // @TODO(Renzix): Implement
                            @panic("GREATAND");
                        },
                        '>' => { // DGREAT >>
                            // @TODO(Renzix): Implement
                            @panic("DGREAT");
                        },
                        '|' => { // CLOBBER >|
                            // @TODO(Renzix): Implement
                            @panic("Clobber");
                        },
                        else => { // '>' or invalid
                            log("Found >: >\n", .{});
                            self.i += 1;
                            _ = self.skipWhitespace();
                            // expected filename, io_rediect with no filename
                            if(!self.lexWord())
                                @panic("expected filename, io_redirect with no filename");
                            return true;
                        }
                    }
                } else {
                    // parse error, io_redirect with no filename
                    // log("index: {}\n",.{self.i});
                    // log("code.len: {}\n",.{self.code.len});
                    @panic("parse error, io_redirect with no filename");
                }
            },
            '<' => {
                if (self.i+1 < self.code.len) {
                    switch (self.code[self.i+1]) {
                        '&' => { // LESSAND <&
                            @panic("LESSAND");
                        },
                        '>' => { // LESSGREAT <>
                            @panic("LESSGREAT");
                        },
                        else => { // '<' or invalid
                            log("Found <: <\n", .{});
                            self.i += 1;
                            _ = self.skipWhitespace();
                            // expected filename, io_rediect with no filename
                            if(!self.lexWord())
                                @panic("expected filename, io_redirect with no filename");
                            return true;
                        }
                    }
                }
            },
            else => {
                return false;
            },
        }
        return false;
    }

    fn parseCmdName(self: *Parser) bool {
        return self.lexWord();
    }

    fn lexWord(self: *Parser) bool {
        self.start = self.i;
        var found=false;
        while(self.i < self.code.len and WordChars[self.code[self.i]]) {
            self.i += 1;
            found=true;
        }
        if(!found) {
            self.i = self.start;
            return false;
        }
        if (self.i < self.code.len and self.code[self.i]=='=') {
            self.i = self.start;
            return false;
        }

        const len = self.i - self.start;
        @memcpy(self.content[0..len], self.code[self.start..self.i]);
        self.content_len = len;
        log("Found Word: {s}\n", .{self.content[0..len]});
        self.token = TokenType.WORD;
        return true;
    }
    fn lexAssignment(self: *Parser) bool {
        self.start = self.i;
        var found=false;
        var eql_index: ?usize = null;
        while(self.i < self.code.len and AssignmentChars[self.code[self.i]]) {
            if (eql_index==null and self.code[self.i]=='=') eql_index=self.i;
            self.i += 1;
            found=true;
        }
        if(!found) {
            self.i = self.start;
            return false; // no characters
        }
        if (eql_index==null) {
            self.i = self.start;
            return false; // couldnt find = sign
        }
        const len = self.i - self.start;
        @memcpy(self.content[0..len], self.code[self.start..self.i]);
        self.content_len = len;
        log("Found Assignment: {s}\n", .{self.content[0..len]});
        self.token = TokenType.ASSIGNMENT_WORD;
        return true;
    }
    fn contentClear(self: *Parser) void {
        @memset(&self.content, 0);
        self.content_len = 0;
    }
    fn skipWhitespace(self: *Parser) usize {
        std.debug.assert(self.quoted==Quoted.QUOTED_NONE);
        const start = self.i;
        while (self.i<self.code.len and self.code[self.i]==' ') self.i+=1;
        return self.i - start;
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
