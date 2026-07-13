const std = @import("std");
const log = @import("std").debug.print;

const TokenType = @import("token.zig").TokenType;
const Quoted = @import("token.zig").Quoted;
const ast = @import("ast.zig");

const helper = @import("token.zig");

// we parse and lex at the same time for shell!!!
// Heavily based off of the grammar rules
// HERE https://pubs.opengroup.org/onlinepubs/9799919799/
pub const Parser = struct {
    code: []const u8,
    i: usize,
    start: usize,

    const allocator = std.heap.c_allocator;

    pub fn init() Parser {
        return Parser{
            .code = undefined,
            .i = 0,
            .start = 0,
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
        // var w = std.ArrayList(ast.Word);
        self.start = self.i;
        var quoted = Quoted.NONE;
        // this can be much much better
        // const found = if (self.i<self.code.len) helper.WordChars[self.code[self.i]] else false;
        var found = false;
        while(self.i < self.code.len) {
            switch (quoted) {
                Quoted.NONE => {
                    if(helper.WordChars[self.code[self.i]]) {
                        switch (self.code[self.i]) {
                            '"' => quoted = Quoted.DOUBLE,
                            '\'' => quoted = Quoted.SINGLE,
                            else => {},
                        }
                        self.i += 1;
                        found = true;
                    } else break;
                },
                Quoted.DOUBLE => {
                    switch (self.code[self.i]) {
                        '"' => quoted = Quoted.NONE,
                        else => {},
                    }
                    self.i += 1;
                    found = true;
                },
                Quoted.SINGLE => {
                    switch (self.code[self.i]) {
                        '\'' => quoted = Quoted.NONE,
                        else => {},
                    }
                    self.i += 1;
                    found = true;
                },
            }
        }
        if(!found or quoted != Quoted.NONE) {
            self.i = self.start;
            return null;
        }
        if (self.i < self.code.len and self.code[self.i]=='=') {
            self.i = self.start;
            return null;
        }

        log("Found Word: {s}\n", .{self.code[self.start..self.i]});
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
        log("Found Assignment Word: {s}\n", .{self.code[self.start..self.i]});
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
    try std.testing.expectEqualStrings("ls", sc.cmd.?);
    try std.testing.expectEqual(@as(usize, 0), sc.args.items.len);
    try std.testing.expectEqual(@as(usize, 0), sc.assignments.items.len);
}

test "parse simple command with arguments" {
    var parser = Parser.init();
    const program = parser.run("echo hello world") orelse return error.TestExpectedProgram;

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings("echo", sc.cmd.?);
    try std.testing.expectEqual(@as(usize, 2), sc.args.items.len);
    try std.testing.expectEqualStrings("hello", sc.args.items[0]);
    try std.testing.expectEqualStrings("world", sc.args.items[1]);
}

test "parse a bare variable assignment" {
    var parser = Parser.init();
    const program = parser.run("FOO=bar") orelse return error.TestExpectedProgram;

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqual(@as(?[]const u8, null), sc.cmd);
    try std.testing.expectEqual(@as(usize, 1), sc.assignments.items.len);
    try std.testing.expectEqualStrings("FOO", sc.assignments.items[0].name);
    try std.testing.expectEqualStrings("bar", sc.assignments.items[0].value);
}

test "parse a two-stage pipeline" {
    var parser = Parser.init();
    const program = parser.run("ls | grep foo") orelse return error.TestExpectedProgram;

    const pipeline = program.andors.items[0].pipelines.items[0];
    try std.testing.expectEqual(@as(usize, 2), pipeline.cmds.items.len);

    const first = pipeline.cmds.items[0].simple_command;
    try std.testing.expectEqualStrings("ls", first.cmd.?);

    const second = pipeline.cmds.items[1].simple_command;
    try std.testing.expectEqualStrings("grep", second.cmd.?);
    try std.testing.expectEqualStrings("foo", second.args.items[0]);
}

test "parse a list with a separator and a backgrounded command" {
    var parser = Parser.init();
    const program = parser.run("ls; sleep 1 &") orelse return error.TestExpectedProgram;

    try std.testing.expectEqual(@as(usize, 2), program.andors.items.len);

    const first_cmd = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings("ls", first_cmd.cmd.?);

    const second_cmd = program.andors.items[1].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings("sleep", second_cmd.cmd.?);
    try std.testing.expectEqualStrings("1", second_cmd.args.items[0]);

    try std.testing.expectEqual(@as(usize, 2), program.background.items.len);
    try std.testing.expectEqual(false, program.background.items[0]);
    try std.testing.expectEqual(true, program.background.items[1]);
}

test "parse a basic print string" {
    var parser = Parser.init();
    const program = parser.run("echo \"Hello World!!!\"") orelse return error.TestExpectedProgram;

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings("echo", sc.cmd.?);
    try std.testing.expectEqual(@as(usize, 1), sc.args.items.len);
    try std.testing.expectEqualStrings("\"Hello World!!!\"", sc.args.items[0]);
}
