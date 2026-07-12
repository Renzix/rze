const std = @import("std");
const log = @import("std").debug.print;

const TokenType = @import("token.zig").TokenType;
const Quoted = @import("token.zig").Quoted;
const ast = @import("ast.zig");

const helper = @import("token.zig");

// we parse and lex at the same time for shell!!!
pub const Parser = struct {
    code: []const u8,
    quoted: Quoted,
    token: TokenType,
    content: [100]u8, // make bigger if you make a string that is longer the 100 lines this will crash!
    content_len: usize,
    i: usize,
    start: usize,
    ast: ast.Program,

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
            .ast = .{ .simple_command = undefined },
        };
    }
    pub fn run(self: *Parser, str: []const u8) void {
        self.code = str;
        // log("str: {}, content: {}\n", .{str.len, self.content.len});
        // std.debug.assert(self.content_len == str.len);
        // var foundToken = (self.code.len != 0);

        _ = self.parseCompleteCommandList();
        // while (self.code.len > self.i) {
        //     foundToken = self.lexToken();
        // }
    }

    fn parseCompleteCommandList(self: *Parser) bool {
        while (true) {
            _ = self.parseAndOr();
            if (self.lexChar('&')) {
                continue;
            }
            if (self.lexChar(';')) {
                continue;
            }
            break;
        }
        return true;
    }

    fn parseAndOr(self: *Parser) bool {
        while (true) {
            _ = self.parsePipeline();
            _ = self.skipWhitespace();
            if (self.lexString("&&")) {
                _ = self.skipWhitespace();
                continue;
            }
            break;
        }
        return true;
    }

    fn parsePipeline(self: *Parser) bool {
        _ = self.skipWhitespace();
        _ = self.lexChar('!'); // handle this
        const ret = self.parsePipeSequence();
        return ret;
    }

    fn parsePipeSequence(self: *Parser) bool {
        while(true) {
            _ = self.parseCommand();
            _ = self.skipWhitespace();
            if (self.lexChar('|')) {
                // self.i+=1;
                _ = self.skipWhitespace();
                continue;
            }
            break;
        }
        return true;
    }
    fn parseCommand(self: *Parser) bool {
        // function
        // compound command and optional redirect
        _ = self.parseSimpleCommand();
        return false;
    }
    fn parseSimpleCommand(self: *Parser) ?ast.SimpleCommand {
        var sc: ast.SimpleCommand = .{
            .assignments = .empty,
            .cmd = null,
            .args = .empty,
            .redirects = undefined,
        };
        var found = false;
        if(self.parseCmdPrefix(&sc)) {
            found = true;
        }
        if(self.parseCmdName(&sc)) {
            found = true;
        }
        if(self.parseCmdSuffix(&sc)) {}
        if (found) return null else return sc;
    }

    fn parseCmdPrefix(self: *Parser, sc: *ast.SimpleCommand) bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            if (self.lexAssignment()) |assign| {
                log("variable name: {s}\n",.{assign.name});
                log("variable value: {s}\n",.{assign.value});
                sc.assignments.append(allocator, assign) catch @panic("oom");
                found=true; continue;
            }
            if (self.parseIoRedirect()) { found=true; continue; }
            break;
        }
        return found;
    }

    fn parseCmdName(self: *Parser, sc: *ast.SimpleCommand) bool {
        const cmd_name = self.lexWord();
        sc.cmd = cmd_name;
        return cmd_name!=null;
    }

    fn parseCmdSuffix(self: *Parser, sc: *ast.SimpleCommand) bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            if (self.lexWord()) |arg| {
                sc.args.append(allocator, arg) catch @panic("oom");
                found=true; continue;
            }
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

    fn lexIoFile(self: *Parser) ?ast.IoRedirection {
        self.start = self.i;
        if (self.i >= self.code.len) return null;
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
                        else => { // GREATTHAN '>' or invalid
                            log("Found GREATTHAN: >\n", .{});
                            self.i += 1;
                            _ = self.skipWhitespace();
                            // expected filename, io_rediect with no filename
                            const file = self.lexWord();
                            if(file==null)
                                @panic("expected filename, io_redirect with no filename");
                            return .{ .typ = ast.Redirect.GREATTHAN, .filename = file.? };
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
                        else => { // LESSTHAN '<' or invalid
                            log("Found LESSTHAN: <\n", .{});
                            self.i += 1;
                            _ = self.skipWhitespace();
                            // expected filename, io_rediect with no filename
                            const file = self.lexWord();
                            if(file==null)
                                @panic("expected filename, io_redirect with no filename");
                            return .{ .typ = ast.Redirect.LESSTHAN, .filename = file.? };
                        }
                    }
                }
            },
            else => {
                return null;
            },
        }
        return null;
    }

    fn lexWord(self: *Parser) ?[]const u8 {
        self.start = self.i;
        var found=false;
        while(self.i < self.code.len and helper.WordChars[self.code[self.i]]) {
            self.i += 1;
            found=true;
        }
        if(!found) {
            self.i = self.start;
            return null;
        }
        if (self.i < self.code.len and self.code[self.i]=='=') {
            self.i = self.start;
            return null;
        }

        // const len = self.i - self.start;
        // @memcpy(self.content[0..len], self.code[self.start..self.i]);
        // self.content_len = len;
        log("Found Word: {s}\n", .{self.code[self.start..self.i]});
        // self.token = TokenType.WORD;
        return self.code[self.start..self.i];
    }
    fn lexAssignment(self: *Parser) ?ast.AssignmentWords {
        self.start = self.i;
        var found=false;
        var eql_index: ?usize = null;
        while(self.i < self.code.len and helper.AssignmentChars[self.code[self.i]]) {
            if (eql_index==null and self.code[self.i]=='=') eql_index=self.i;
            self.i += 1;
            found=true;
        }
        if(!found) {
            self.i = self.start;
            return null; // no characters
        }
        if (eql_index==null) {
            self.i = self.start;
            return null; // couldnt find = sign
        }
        // const len = self.i - self.start;
        // @memcpy(self.content[0..len], self.code[self.start..self.i]);
        // self.content_len = len;
        log("Found Assignment Word: {s}\n", .{self.code[self.start..self.i]});
        // self.token = TokenType.ASSIGNMENT_WORD;
        // return self.code[self.start..self.i];
        return .{
            .name = self.code[self.start..eql_index.?],
            .value = self.code[eql_index.?+1..self.i]
        };
    }

    fn lexString(self: *Parser, comptime str: []const u8) bool {
        self.start = self.i;
        for (str) |char| {
            if(self.i >= self.code.len or self.code[self.i]!=char) {
                self.i=self.start;
                return false;
            }
            self.i+=1;
        }
        log("Found String: {s}\n", .{str});
        return true;
    }

    fn lexChar(self: *Parser, comptime char: u8) bool {
        if(self.i < self.code.len and self.code[self.i]==char) {
            log("Found Char: {c}\n", .{self.code[self.i]});
            self.i+=1;
            return true;
        } else {
            return false;
        }
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
