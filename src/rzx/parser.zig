const std = @import("std");
const log = @import("std").log.debug;

const TokenType = @import("token.zig").TokenType;
const Quoted = @import("token.zig").Quoted;
const ast = @import("ast.zig");

const helper = @import("token.zig");

// @TODO(Renzix): Command subsitution and backtick
// @TODO(Renzix): Run() verify everything was consumed
// @TODO(Renzix): Redirection consumed but discarded, need to add more redirection
// @TODO(Renzix): !foo is a command but being parsed as a pipeline
// @TODO(Renzix): Comments
// @TODO(Renzix): Actual memory management
// @TODO(Renzix): Readable Errors?
// @TODO(Renzix): && value is parsed as valid syntax (should error)
// @TODO(Renzix): Testing for "${var}", "pre${var}post", echo "x$HOME.y"z, a\ b
// @TODO(Renzix): Testing for ls -l, echo $, echo "", !foo
// @TODO(Renzix): Globbing \* is different from *
// @TODO(Renzix): ${Parameter:-Expansions}
// @TODO(Renzix): $(()) arithmatic (wtf... a parser within a parser????)

// we parse and lex at the same time for shell!!!
// Heavily based off of the grammar rules
// HERE https://pubs.opengroup.org/onlinepubs/9799919799/
pub const Parser = struct {
    code: []const u8,
    i: usize,

    const allocator = std.heap.c_allocator;

    pub fn init() Parser {
        return Parser{
            .code = undefined,
            .i = 0,
        };
    }
    pub fn run(self: *Parser, str: []const u8) ?ast.Program {
        self.code = str;

        const program = self.parseCompleteCommandList();
        return program;
    }

    // complete command and list
    fn parseCompleteCommandList(self: *Parser) ?ast.Program {
        var program: ast.Program = .{ .andors = .empty, .background = .empty };
        while (true) {
            if(self.parseAndOr()) |andor| {
                program.andors.append(allocator, andor) catch @panic("oom");
            } else {
                break;
            }
            if (self.lexChar('&')) {
                program.background.append(allocator, true) catch @panic("oom");
                continue;
            } else {
                program.background.append(allocator, false) catch @panic("oom");
            }
            if (self.lexChar(';')) {
                continue;
            }
            break;
        }
        std.debug.assert(program.andors.items.len == program.background.items.len);
        if (program.andors.items.len > 0) return program else return null;
    }

    fn parseAndOr(self: *Parser) ?ast.AndOr {
        var andor: ast.AndOr = .{ .pipelines = .empty, .and_or_list = .empty };
        while (true) {
            if (self.parsePipeline()) |p| {
                andor.pipelines.append(allocator, p) catch @panic("oom");
            }
            _ = self.skipWhitespace();
            if (self.lexString("&&")) {
                andor.and_or_list.append(allocator, ast.AndOrIf.and_if) catch @panic("oom");
                _ = self.skipWhitespace();
                _ = self.skipNewlines();
                continue;
            }
            if (self.lexString("||")) {
                andor.and_or_list.append(allocator, ast.AndOrIf.or_if) catch @panic("oom");
                _ = self.skipWhitespace();
                _ = self.skipNewlines();
                continue;
            }
            break;
        }
        if (andor.pipelines.items.len>0) return andor else return null;
    }

    // Pipeline and pipeline sequence
    fn parsePipeline(self: *Parser) ?ast.Pipeline {
        var pipeline: ast.Pipeline = .{ .bang = false, .cmds = .empty };
        _ = self.skipWhitespace();
        if(self.lexChar('!')) pipeline.bang = true;
        while(true) {
            if (self.parseCommand()) |cmd| {
                pipeline.cmds.append(allocator, cmd) catch @panic("oom");
            }
            _ = self.skipWhitespace();
            if (self.lexChar('|')) {
                _ = self.skipWhitespace();
                _ = self.skipNewlines();
                continue;
            }
            break;
        }
        // if we have no commands then we failed to parse...
        if (pipeline.cmds.items.len>0 or pipeline.bang == true)
            return pipeline
        else
            return null;
    }

    fn parseCommand(self: *Parser) ?ast.Command {
        // function command
        // compound command and optional redirect
        if (self.parseSimpleCommand()) |sc| {
            return .{ .simple_command = sc };
        }
        return null;
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
        if (found) return sc else return null;
    }

    fn parseCmdPrefix(self: *Parser, sc: *ast.SimpleCommand) bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            if (self.lexAssignment()) |assign| {
                log("Variable Name: {s}",.{assign.name});
                log("Variable Value: {any}",.{assign.value});
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
                            log("Found GREATTHAN: >", .{});
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
                            log("Found LESSTHAN: <", .{});
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

    fn lexWord(self: *Parser) ?std.ArrayList(ast.Word) {
        var w: std.ArrayList(ast.Word) = .empty;
        const start = self.i;
        while (self.i < self.code.len) {
            const ok = switch (self.code[self.i]) {
                '\'' => self.lexSingleQuote(&w),
                '"' => self.lexDoubleQuote(&w),
                '$' => ret: {
                    if (self.i+1 >= self.code.len) break :ret false;
                    if (self.code[self.i+1] == ' ') { self.i += 1; break :ret true; } // if $ is alone then continue
                    break :ret self.lexExpansion(&w);
                },
                else => if(helper.WordChars[self.code[self.i]])
                            self.lexLiterals(&w)
                        else break,
            };
            if (!ok) { self.i = start; return null; }
        }
        if (self.i == start) return null;
        return w;
    }

    fn lexSingleQuote(self: *Parser, w: *std.ArrayList(ast.Word)) bool {
        // parse single quotes AS IS, everything should be literal and ignore quotes
        const start = self.i;
        if (self.code[self.i]=='\'') { self.i += 1; } else { return false; }
        while(self.i < self.code.len) {
            switch (self.code[self.i]) {
                '\'' => break,
                else => {},
            }
            self.i += 1;
        }
        const lit: ast.Word = .{
            .literal = .{
                .text = self.code[start+1..self.i],
                .quoted = Quoted.SINGLE,
            },
        };
        std.debug.assert(self.code[self.i]=='\'');
        self.i += 1;
        w.append(allocator, lit) catch @panic("oom");
        log("Found Single Quote: {s}", .{lit.literal.text});
        return true;
    }

    fn lexDoubleQuote(self: *Parser, w: *std.ArrayList(ast.Word)) bool {
        // parse double quotes, should also handle var expansion @TODO(Renzix)
        var start = self.i+1;
        if (self.code[self.i]=='"') { self.i += 1; } else { return false; }
        while(self.i < self.code.len) {
            switch (self.code[self.i]) {
                '"' => break,
                '$' => { // apply the current double quote values and come back
                    if (self.i > start) {
                        const lit: ast.Word = .{
                            .literal = .{
                                .text = self.code[start..self.i],
                                .quoted = Quoted.DOUBLE,
                            }
                        };
                        w.append(allocator, lit) catch @panic("oom");
                        log("Found Double Quote: \"{s}\"", .{lit.literal.text});
                    }
                    if (!self.lexExpansion(w)) return false;
                    start = self.i;
                    continue;
                },
                '\\' => {
                    if ((self.i+1) >= self.code.len) return false;
                    // treated as a normal \ unless one of the special cases
                    switch(self.code[self.i+1]) {
                        '$', '`', '"', '\\', '\n' => |ch| {
                            // flush the current buffer
                            if (self.i > start) {
                                const lit: ast.Word = .{
                                    .literal = .{
                                        .text = self.code[start..self.i],
                                        .quoted = Quoted.DOUBLE,
                                    }
                                };
                                w.append(allocator, lit) catch @panic("oom");
                                log("Found Double Quote: \"{s}\"", .{lit.literal.text});
                            }
                            if(!self.nextChar()) return false;
                            if (ch!='\n') start = self.i;
                            if(!self.nextChar()) return false;
                            if (ch=='\n') start = self.i;
                            continue;

                        },
                        else => {},
                    }
                },
                else => {},
            }
            self.i += 1;
        }
        // in the case of expand this can end up producing "" followed by $var
        // followed by "", lets ignore the ""
        if (self.i > start) {
            const lit: ast.Word = .{
                .literal = .{
                    .text = self.code[start..self.i],
                    .quoted = Quoted.DOUBLE,
                },
            };
            std.debug.assert(self.code[self.i]=='"');
            w.append(allocator, lit) catch @panic("oom");
            log("Found Double Quote: \"{s}\"", .{lit.literal.text});
        }
        if (self.i >= self.code.len) return false;
        self.i += 1;
        return true;
    }


    fn lexExpansion(self: *Parser, w: *std.ArrayList(ast.Word)) bool {
        // this should always result in a expand str
        if (self.code[self.i]=='$') { self.i += 1; } else { return false; }
        const typ = switch (self.code[self.i]) {
            '(' => ast.ExpandTypes.command,
            '{' => ast.ExpandTypes.variable_bracket,
            else => ast.ExpandTypes.variable,
        };
        const delim = @intFromBool(typ != ast.ExpandTypes.variable);
        self.i += delim;
        const start = self.i;
        while(self.i < self.code.len) {
            if(helper.VariableChars[self.code[self.i]]) {
                switch (self.code[self.i]) {
                    '}' => if (typ == ast.ExpandTypes.variable_bracket) break,
                    else => {},
                }
                self.i += 1;
            } else {
                break;
            }
        }
        const exp: ast.Word = .{
            .expand = .{
                .name = self.code[start..self.i],
                .typ  = typ,
            },
        };
        self.i += delim;
        w.append(allocator, exp) catch @panic("oom");
        log("Found Expandable Word: {s}", .{exp.expand.name});
        return true;
    }
    fn lexLiterals(self: *Parser, w: *std.ArrayList(ast.Word)) bool {
        // can be a expand string or may not be
        var start = self.i;
        while(self.i < self.code.len) {
            if(helper.WordChars[self.code[self.i]]) {
                switch (self.code[self.i]) {
                    '"', '\'', '$', '\\' => |ch| {
                        if (self.i > start) {
                            const lit: ast.Word = .{
                                .literal = .{
                                    .text = self.code[start..self.i],
                                    .quoted = Quoted.NONE,
                                }
                            };
                            w.append(allocator, lit) catch @panic("oom");
                            log("Found Unquoted: |{s}|", .{lit.literal.text});
                        }
                        // @TODO(Renzix): Handle "echo $ ", in this case $ should be literal
                        const ok = switch (ch) {
                            '"' => self.lexDoubleQuote(w),
                            '\'' => self.lexSingleQuote(w),
                            '$' => ret: {
                                if (self.i+1 >= self.code.len) break :ret false;
                                if (self.code[self.i+1] == ' ') { self.i += 1; break :ret true; } // if $ is alone then continue
                                break :ret self.lexExpansion(w);
                            },
                            '\\' => ret: { // @TODO(Renzix): This could probably not be its own function
                                if ((self.i+1) >= self.code.len) return false;
                                switch (self.code[self.i+1]) {
                                    '\\', ' ', '$', '\n',
                                    '`', '"', '\'' => ch = {
                                        if(!self.nextChar()) return false;
                                        if (ch!='\n') start = self.i;
                                        if(!self.nextChar()) return false;
                                        if (ch=='\n') start = self.i;
                                        continue;
                                    },
                                    // for * make a new Word specifically for glob???
                                    else => break :ret self.nextChar(),
                                }
                            },
                            else => unreachable,
                        };
                        if(!ok) return false;
                        start = self.i;
                        continue;
                    },
                    else => {},
                }
                self.i += 1;
            } else {
                break;
            }
        }
        if (self.i > start) {
            const lit: ast.Word = .{
                .literal = .{
                    .text = self.code[start..self.i],
                    .quoted = Quoted.NONE,
                },
            };
            w.append(allocator, lit) catch @panic("oom");
            log("Found unquoted Word: |{s}|", .{lit.literal.text});
        }
        return true;
    }

    fn lexAssignment(self: *Parser) ?ast.AssignmentWord {
        // parse the until =, if you dont hit = return FALSE because this isnt a
        // assignment!!1! WOW
        var start = self.i;
        {
            const ok = while (self.i < self.code.len) : (self.i += 1) {
                switch (self.code[self.i]) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    '=' => break true,
                    else => break false,
                }
            } else false;
            if (!ok) { self.i = start; return null; }
        }
        const name = self.code[start..self.i];
        if(!self.nextChar()) return null; // get rid of the =

        var w: std.ArrayList(ast.Word) = .empty;
        start = self.i;
        while (self.i < self.code.len) {
            const ok = switch (self.code[self.i]) {
                '\'' => self.lexSingleQuote(&w),
                '"' => self.lexDoubleQuote(&w),
                '$' => ret: {
                    if (self.i+1 >= self.code.len) break :ret false;
                    if (self.code[self.i+1] == ' ') { self.i += 1; break :ret true; } // if $ is alone then continue
                    break :ret self.lexExpansion(&w);
                },
                else => if(helper.WordChars[self.code[self.i]])
                            self.lexLiterals(&w)
                        else break,
            };
            if (!ok) { self.i = start; return null; }
        }
        return .{ .name = name, .value = if (w.items.len != 0) w else null };
    }

    fn lexString(self: *Parser, comptime str: []const u8) bool {
        const start = self.i;
        for (str) |char| {
            if(self.i >= self.code.len or self.code[self.i]!=char) {
                self.i=start;
                return false;
            }
            self.i+=1;
        }
        log("Found String: {s}", .{str});
        return true;
    }

    fn lexChar(self: *Parser, comptime char: u8) bool {
        if(self.i < self.code.len and self.code[self.i]==char) {
            log("Found Char: {c}", .{self.code[self.i]});
            self.i+=1;
            return true;
        } else {
            return false;
        }
    }

    // function to safely go to the next char without crashing
    fn nextChar(self: *Parser) bool {
        if (self.i<self.code.len) {
            self.i+=1;
            return true;
        }
        else return false;
    }

    // skips " " and "\t" not newline, use skipNewlines for that
    fn skipWhitespace(self: *Parser) usize {
        const start = self.i;
        while (self.i<self.code.len and helper.WhitespaceChars[self.code[self.i]]) self.i+=1;
        return self.i - start;
    }

    fn skipNewlines(self: *Parser) usize {
        const start = self.i;
        while (self.i<self.code.len and self.code[self.i]=='\n') self.i+=1;
        return self.i - start;
    }
};

test "parse simple command with a single word" {
    var parser = Parser.init();
    const program = parser.run("ls") orelse return error.TestExpectedProgram;

    try std.testing.expectEqual(@as(usize, 1), program.andors.items.len);
    const andor = program.andors.items[0];
    try std.testing.expectEqual(@as(usize, 1), andor.pipelines.items.len);
    const pipeline = andor.pipelines.items[0];
    try std.testing.expectEqual(@as(usize, 1), pipeline.cmds.items.len);
    const sc = pipeline.cmds.items[0].simple_command;
    try std.testing.expect(sc.cmd != null);
    const ls = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text, sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted, sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 0), sc.args.items.len);
    try std.testing.expectEqual(@as(usize, 0), sc.assignments.items.len);
}

test "parse simple command with arguments" {
    var parser = Parser.init();
    const program = parser.run("echo hello world") orelse return error.TestExpectedProgram;

    const echo: ast.Word = .{ .literal = .{ .text = "echo", .quoted = Quoted.NONE } };
    const hello: ast.Word = .{ .literal = .{ .text = "hello", .quoted = Quoted.NONE } };
    const world: ast.Word = .{ .literal = .{ .text = "world", .quoted = Quoted.NONE } };

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings(echo.literal.text, sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(echo.literal.quoted, sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 2), sc.args.items.len);

    try std.testing.expectEqualStrings(hello.literal.text, sc.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(hello.literal.quoted, sc.args.items[0].items[0].literal.quoted);
    try std.testing.expectEqualStrings(world.literal.text, sc.args.items[1].items[0].literal.text);
    try std.testing.expectEqual(world.literal.quoted, sc.args.items[1].items[0].literal.quoted);
}

// test "parse a bare variable assignment" {
//     var parser = Parser.init();
//     const program = parser.run("FOO=bar") orelse return error.TestExpectedProgram;

//     const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
//     try std.testing.expectEqual(@as(?[]const u8, null), sc.cmd);
//     try std.testing.expectEqual(@as(usize, 1), sc.assignments.items.len);

//     const FOO: ast.Word = .{ .literal = .{ .text = "FOO", .quoted = false } };
//     const bar: ast.Word = .{ .literal = .{ .text = "bar", .quoted = false } };

//     // try std.testing.expectEqualStrings(FOO, sc.assignments.items[0].name);
//     try std.testing.expectEqualStrings(FOO.literal.text, sc.args.items[0].items[0].literal.text);
//     try std.testing.expectEqualStrings(bar.literal.text, sc.args.items[0].items[0].literal.text);
//     // try std.testing.expectEqualStrings(bar, sc.assignments.items[0].value);
// }

test "parse a two-stage pipeline" {
    var parser = Parser.init();
    const program = parser.run("ls | grep foo") orelse return error.TestExpectedProgram;

    const pipeline = program.andors.items[0].pipelines.items[0];
    try std.testing.expectEqual(@as(usize, 2), pipeline.cmds.items.len);

    const first = pipeline.cmds.items[0].simple_command;
    const ls: ast.Word = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text, first.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted, first.cmd.?.items[0].literal.quoted);

    const second = pipeline.cmds.items[1].simple_command;
    const grep: ast.Word = .{ .literal = .{ .text = "grep", .quoted = Quoted.NONE } };
    const foo: ast.Word = .{ .literal = .{ .text = "foo", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(grep.literal.text, second.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(grep.literal.quoted, second.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqualStrings(foo.literal.text, second.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(foo.literal.quoted, second.args.items[0].items[0].literal.quoted);
}

test "parse a list with a separator and a backgrounded command" {
    var parser = Parser.init();
    const program = parser.run("ls; sleep 1 &") orelse return error.TestExpectedProgram;

    try std.testing.expectEqual(@as(usize, 2), program.andors.items.len);

    const first = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    const ls: ast.Word = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text, first.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted, first.cmd.?.items[0].literal.quoted);

    const second = program.andors.items[1].pipelines.items[0].cmds.items[0].simple_command;
    const sleep: ast.Word = .{ .literal = .{ .text = "sleep", .quoted = Quoted.NONE } };
    const one: ast.Word = .{ .literal = .{ .text = "1", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(sleep.literal.text, second.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(sleep.literal.quoted, second.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqualStrings(one.literal.text, second.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(one.literal.quoted, second.args.items[0].items[0].literal.quoted);

    try std.testing.expectEqual(@as(usize, 2), program.background.items.len);
    try std.testing.expectEqual(false, program.background.items[0]);
    try std.testing.expectEqual(true, program.background.items[1]);
}

test "parse a basic print string" {
    var parser = Parser.init();
    const program = parser.run("echo \"Hello World!!!\"") orelse return error.TestExpectedProgram;

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    const echo: ast.Word = .{ .literal = .{ .text = "echo", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(echo.literal.text, sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(echo.literal.quoted, sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 1), sc.args.items.len);
    const hello_world: ast.Word = .{ .literal = .{ .text = "Hello World!!!", .quoted = Quoted.DOUBLE } };
    try std.testing.expectEqualStrings(hello_world.literal.text, sc.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(hello_world.literal.quoted, sc.args.items[0].items[0].literal.quoted);
}
