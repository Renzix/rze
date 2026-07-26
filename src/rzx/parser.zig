const std = @import("std");
const log = @import("std").log.debug;

const TokenType = @import("token.zig").TokenType;
const Quoted = @import("token.zig").Quoted;
const Keyword = @import("token.zig").Keyword;
const KeywordSet = @import("token.zig").KeywordSet;
const ControlOperator = @import("token.zig").ControlOperator;
const ControlOperatorSet = @import("token.zig").ControlOperatorSet;
const RedirectOperator = @import("token.zig").RedirectOperator;
const RedirectOperatorSet = @import("token.zig").RedirectOperatorSet;
const ast = @import("ast.zig");

const helper = @import("token.zig");

// @TODO(Renzix): Complex commands (if, for, while etc)
// @TODO(Renzix): function definitions
// @TODO(Renzix): Command subsitution and backtick $() ``
// @TODO(Renzix): Heredocs <<<
// @TODO(Renzix): Redirection consumed but discarded, need to add more redirection
// @TODO(Renzix): Comments
// @TODO(Renzix): Store current program state in error
// @TODO(Renzix): Testing for "${var}", "pre${var}post", echo "x$HOME.y"z, a\ b,
//                ls -l, echo $, echo "", !foo
// @TODO(Renzix): Globbing \* is different from *
// @TODO(Renzix): ${Parameter:-Expansions}
// @TODO(Renzix): $(()) arithmatic (wtf... a parser within a parser????)

const ParseErr = error{
    Unimplemented,
    SyntaxError,
    OutOfMemory,
};

const ParseDiagnostics = struct {
    tag: Tag,
    pos: usize,
    pub const Tag = enum {
        expected_filename,
        expected_command,
        unexpected_token,
        unclosed_quote,
    };
};

// we parse and lex at the same time for shell!!!
// Heavily based off of the grammar rules
// HERE https://pubs.opengroup.org/onlinepubs/9799919799/
pub const Parser = struct {
    code: []const u8,
    i: usize,
    allocator: std.mem.Allocator,
    diag: ParseDiagnostics,

    pub fn init(alloc: std.mem.Allocator) Parser {
        return Parser{
            .code = undefined,
            .i = 0,
            .allocator = alloc,
            .diag = undefined,
        };
    }

    pub fn reset(self: *Parser) void { self.i = 0; }

    pub fn run(self: *Parser, str: []const u8) !?ast.Program {
        self.code = str;
        self.reset();

        const program = try self.parseCompleteCommandList();
        return program;
    }

    // complete command and list
    fn parseCompleteCommandList(self: *Parser) !?ast.Program {
        var program: ast.Program = .{ .andors = .empty, .background = .empty };
        while (true) {
            const andor = try self.parseAndOr() orelse break;
            try program.andors.append(self.allocator, andor);

            const start = self.i;
            const oper = (try self.lexControlOperator());
            try program.background.append(self.allocator, oper==.AMP);
            switch (oper orelse break) {
                .AMP, .SEMI, .NEWLINE => {},
                else => {
                    self.i = start;
                    break;
                },
            }
        }
        _ = self.skipWhitespace();
        _ = self.skipNewlines();
        if (self.i < self.code.len) return self.fail(.unexpected_token, self.i); // make better
        std.debug.assert(program.andors.items.len == program.background.items.len);
        if (program.andors.items.len > 0) return program else return null;
    }

    fn parseAndOr(self: *Parser) !?ast.AndOr {
        var andor: ast.AndOr = .{ .pipelines = .empty, .and_or_list = .empty };
        while (true) {
            const p = try self.parsePipeline() orelse break;
            try andor.pipelines.append(self.allocator, p);

            _ = self.skipWhitespace();
            const start = self.i;
            const oper = (try self.lexControlOperator()) orelse break;
            const a = switch (oper) {
                .AMP_AMP => ast.AndOrIf.and_if,
                .PIPE_PIPE => ast.AndOrIf.or_if,
                else => {
                    self.i = start;
                    break;
                },
            };
            try andor.and_or_list.append(self.allocator, a);
            _ = self.skipWhitespace();
            _ = self.skipNewlines();
        }
        if (andor.pipelines.items.len>0) return andor else return null;
    }

    // Pipeline and pipeline sequence
    fn parsePipeline(self: *Parser) !?ast.Pipeline {
        var pipeline: ast.Pipeline = .{ .bang = false, .cmds = .empty };
        _ = self.skipWhitespace();
        if (self.lexKeyword(Keyword.BANG)) {
            pipeline.bang = true;
            _ = self.skipWhitespace();
        }
        while(true) {
            if (try self.parseCommand()) |cmd| {
                try pipeline.cmds.append(self.allocator, cmd);
            }
            _ = self.skipWhitespace();
            if (self.lexComptimeControlOperator(ControlOperator.PIPE)) {
                _ = self.skipWhitespace();
                _ = self.skipNewlines();
                continue;
            }
            break;
        }
        // if we have no commands then we failed to parse...
        if (pipeline.cmds.items.len>0)
            return pipeline
        else
            return null;
    }

    fn parseCommand(self: *Parser) !?ast.Command {
        // function command
        // compound command and optional redirect
        if (try self.parseSimpleCommand()) |sc| {
            return .{ .simple_command = sc };
        } else {
            // return ParseErr.Unimplemented;
            return null;
        }
    }
    fn parseSimpleCommand(self: *Parser) !?ast.SimpleCommand {
        var sc: ast.SimpleCommand = .{
            .assignments = .empty,
            .cmd = null,
            .args = .empty,
            .redirects = .empty,
        };
        var found = false;
        const prefix = try self.parseCmdPrefix(&sc);
        if(prefix) {
            found = true;
        }
        const cmd = try self.parseCmdName(&sc);
        if(cmd) {
            found = true;
        }
        _ = try self.parseCmdSuffix(&sc);
        if (found) return sc else return null;
    }

    fn parseCmdPrefix(self: *Parser, sc: *ast.SimpleCommand) !bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            const ass = try self.lexAssignment();
            if (ass) |assign| {
                log("Variable Name: {s}",.{assign.name});
                log("Variable Value: {any}",.{assign.value});
                try sc.assignments.append(self.allocator, assign);
                found=true; continue;
            }
            const ioredir = try self.parseIoRedirect();
            if (ioredir) { found=true; continue; }

            break;
        }
        return found;
    }

    fn parseCmdName(self: *Parser, sc: *ast.SimpleCommand) !bool {
        const cmd_name = try self.lexWord();
        sc.cmd = cmd_name;
        return cmd_name!=null;
    }

    fn parseCmdSuffix(self: *Parser, sc: *ast.SimpleCommand) !bool {
        var found = false;
        while(true) {
            _ = self.skipWhitespace();
            const w = try self.lexWord();
            if (w) |arg| {
                try sc.args.append(self.allocator, arg);
                found=true;
                continue;
            }
            const ioredir = try self.parseIoRedirect();
            if (ioredir) { found=true; continue; }
            break;
        }
        return found;
    }

    // @TODO(Renzix): Add io_here and maybe io_location
    fn parseIoRedirect(self: *Parser) !bool {
        const start=self.i;
        _ = self.skipWhitespace();
        // self.lexIoNumber();
        const io = try self.parseIoFile();
        if (io!=null) {
            return true;
        } else{
            self.i = start;
            return false;
        }
    }

    fn parseIoFile(self: *Parser) !?ast.IoRedirection {
        if (self.i >= self.code.len) return null;
        const redir = try self.lexRedirectOperator() orelse return null;
        switch(redir){
            .LESS => {
                log("Found LESSTHAN: <", .{});
                _ = self.skipWhitespace();
                // expected filename, io_rediect with no filename
                const file = try self.lexWord() orelse {
                    log("io_redirect < failed with no/invalid filename", .{});
                    return self.fail(ParseDiagnostics.Tag.expected_filename ,self.i);
                };
                return .{
                    .typ = ast.Redirect.LESS,
                    .filename = file
                };
            },
            .LESS_LESS => {
                // @TODO(Renzix): Implement
                log("LESS_LESS << is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
            .LESS_LESS_DASH => {
                // @TODO(Renzix): Implement
                log("LESS_LESS_DASH <<- is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
            .LESS_AMP => {
                // @TODO(Renzix): Implement
                log("LESS_AMP <& is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
            .LESS_GREAT => {
                // @TODO(Renzix): Implement
                log("LESS_GREAT <> is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
            inline .GREAT, .GREAT_GREAT => |g| {
                log("Found GREAT: >", .{});
                _ = self.skipWhitespace();

                const file = try self.lexWord() orelse {
                    log("io_redirect > failed with no/invalid filename", .{});
                    return self.fail(ParseDiagnostics.Tag.expected_filename ,self.i);
                };
                const t = switch(g) {
                    .GREAT => ast.Redirect.GREAT,
                    .GREAT_GREAT => ast.Redirect.GREAT_GREAT,
                    else => unreachable,
                };
                return .{
                    .typ = t,
                    .filename = file
                };
            },
            .GREAT_AMP => {
                // @TODO(Renzix): Implement
                log("GREAT_AMP >& is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
            .GREAT_PIPE => {
                // @TODO(Renzix): Implement
                log("GREAT_PIPE >| is unimplemented", .{});
                return ParseErr.Unimplemented;
            },
        }
        unreachable;
    }

    fn lexWord(self: *Parser) !?std.ArrayList(ast.Word) {
        var w: std.ArrayList(ast.Word) = .empty;
        const start = self.i;
        while (self.i < self.code.len) {
            const ok = switch (self.code[self.i]) {
                '\'' => try self.lexSingleQuote(&w),
                '"' => try self.lexDoubleQuote(&w),
                '$' => try self.lexDollar(&w, Quoted.NONE),
                else => if(helper.WordChars[self.code[self.i]])
                            try self.lexLiterals(&w)
                        else break,
            };
            if (!ok) { self.i = start; return null; }
        }
        if (self.i == start) return null;
        return w;
    }

    fn lexSingleQuote(self: *Parser, w: *std.ArrayList(ast.Word)) !bool {
        // parse single quotes AS IS,
        // everything should be literal and ignore quotes
        const start = self.i;
        if (self.code[self.i]=='\'') { self.i += 1; } else { return false; }
        while(self.i < self.code.len) {
            switch (self.code[self.i]) {
                '\'' => break,
                else => {},
            }
            self.i += 1;
        } else return self.fail(ParseDiagnostics.Tag.unclosed_quote ,self.i-1);
        const lit: ast.Word = .{
            .literal = .{
                .text = self.code[start+1..self.i],
                .quoted = Quoted.SINGLE,
            },
        };
        std.debug.assert(self.code[self.i]=='\'');
        self.i += 1;
        try w.append(self.allocator, lit);
        log("Found Single Quote: {s}", .{lit.literal.text});
        return true;
    }

    fn lexDoubleQuote(self: *Parser, w: *std.ArrayList(ast.Word)) !bool {
        // parse double quotes, should also handle var expansion
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
                        try w.append(self.allocator, lit);
                        log("Found Double Quote: \"{s}\"", .{lit.literal.text});
                    }
                    // @TODO(Renzix): if "$ " then ignore
                    const d = try self.lexDollar(w, Quoted.DOUBLE);
                    if (!d) return false;
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
                                try w.append(self.allocator, lit);
                                log("Found Double Quote: \"{s}\"",
                                    .{lit.literal.text});
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
        } else return self.fail(ParseDiagnostics.Tag.unclosed_quote ,self.i-1);
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
            try w.append(self.allocator, lit);
            log("Found Double Quote: \"{s}\"", .{lit.literal.text});
        }
        if (self.i >= self.code.len) return false;
        self.i += 1;
        return true;
    }

    fn lexDollar(self: *Parser, w: *std.ArrayList(ast.Word), q: Quoted) !bool {
        if (!self.nextChar()) return false;
        // this ch thing is for the edge case of "echo $"
        // so i dont go out of bounds
        const ch: u8 = if (self.i < self.code.len) self.code[self.i] else ' ';
        return blk: {
            switch (ch) {
                'a'...'z', 'A'...'Z',
                '_' => {
                    break :blk self.lexExpansion(w, q, ast.ExpandTypes.variable);
                },
                '0'...'9', '@', '*', '#',
                '?', '-', '$', '!' => {
                    break :blk self.lexSpecial(w, q);
                },
                '(' => {
                    unreachable; // @TODO(Renzix): Command Subsitution
                },
                '{' => {
                    if (!self.nextChar()) return false;
                    break :blk self.lexExpansion(w, q,
                                                 ast.ExpandTypes.variable_bracket);
                },
                else => {
                    const lit: ast.Word = .{
                        .literal = .{
                            .text = self.code[self.i-1..self.i],
                            .quoted = q,
                        },
                    };
                    try w.append(self.allocator, lit);
                    log("Lone $: |{s}|", .{lit.literal.text});
                    break :blk true;
                },
            }
        };
    }

    fn lexSpecial(self: *Parser, w: *std.ArrayList(ast.Word), q: Quoted) !bool {
        if(!self.nextChar()) @panic("Tried to parse special $ but got EOF");
        // ensure that self.i is actually a special character???
        const exp: ast.Word = .{
            .expand = .{
                .name = self.code[self.i-1..self.i],
                .quoted = q,
                .typ = ast.ExpandTypes.variable,
            },
        };
        try w.append(self.allocator, exp);
        log("Special Variable: ${s}", .{exp.expand.name});
        return true;
    }

    fn lexExpansion(self: *Parser, w: *std.ArrayList(ast.Word),
                    q: Quoted, typ: ast.ExpandTypes) !bool {
        // this should always result in a expand str
        const delim = @intFromBool(typ != ast.ExpandTypes.variable);
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
                .quoted = q,
            },
        };
        self.i += delim;
        try w.append(self.allocator, exp);
        if (exp.expand.quoted == Quoted.DOUBLE)
            log("Found Expandable Word: \"{s}\"", .{exp.expand.name})
        else
            log("Found Expandable Word: {s}", .{exp.expand.name});
        return true;
    }

    fn lexLiterals(self: *Parser, w: *std.ArrayList(ast.Word)) !bool {
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
                            try w.append(self.allocator, lit);
                            log("Found Unquoted: |{s}|", .{lit.literal.text});
                        }
                        const ok = switch (ch) {
                            '"' => try self.lexDoubleQuote(w),
                            '\'' => try self.lexSingleQuote(w),
                            '$' => try self.lexDollar(w, Quoted.NONE),
                            '\\' => ret: {
                                // @TODO(Renzix): This could probably not be its
                                // own function
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
                                    // for * make a new Word specifically for
                                    // glob???
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
            try w.append(self.allocator, lit);
            log("Found unquoted Word: |{s}|", .{lit.literal.text});
        }
        return true;
    }

    fn lexAssignment(self: *Parser) !?ast.AssignmentWord {
        // parse the until =, if you dont hit = return FALSE because this isnt a
        // assignment!!1! WOW
        const start = self.i;
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
        while (self.i < self.code.len) {
            const ok = switch (self.code[self.i]) {
                '\'' => try self.lexSingleQuote(&w),
                '"' => try self.lexDoubleQuote(&w),
                '$' => try self.lexDollar(&w, Quoted.NONE),
                else => if(helper.WordChars[self.code[self.i]])
                            try self.lexLiterals(&w)
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

    fn lexKeyword(self: *Parser, comptime kw: Keyword) bool {
        const start = self.i;
        for (KeywordSet[@intFromEnum(kw)]) |char| {
            if(self.i >= self.code.len or self.code[self.i]!=char) {
                self.i=start;
                return false;
            }
            self.i+=1;
        }
        // keywords require a delim after it
        if (self.i < self.code.len and !helper.DelimChars[self.code[self.i]]) {
            self.i=start;
            return false;
        }
        log("Found Keyword: {s}", .{KeywordSet[@intFromEnum(kw)]});
        return true;
    }

    fn lexControlOperator(self: *Parser) !?ControlOperator {
        if (self.i < self.code.len) {
            switch(self.code[self.i]) {
                '&' => {
                    self.i += 1;
                    if (self.i < self.code.len and self.code[self.i] == '&') {
                        self.i += 1;
                        return .AMP_AMP;
                    } else {
                        return .AMP;
                    }
                },
                '(' => {
                    self.i += 1;
                    return .LPAREN;
                },
                ')' => {
                    self.i += 1;
                    return .RPAREN;
                },
                ';' => {
                    self.i += 1;
                    if (self.i < self.code.len and self.code[self.i] == ';') {
                        self.i += 1;
                        return .SEMI_SEMI;
                    } else {
                        return .SEMI;
                    }
                },
                '\n' => {
                    self.i += 1;
                    return .NEWLINE;
                },
                '|' => {
                    self.i += 1;
                    if (self.i < self.code.len and self.code[self.i] == '|') {
                        self.i += 1;
                        return .PIPE_PIPE;
                    } else {
                        return .PIPE;
                    }
                },
                else => {
                    return null;
                },
            }
        } else {
            return null;
        }
        unreachable;
    }

    fn lexRedirectOperator(self: *Parser) !?RedirectOperator {
        if (self.i < self.code.len) {
            switch(self.code[self.i]) {
                '>' => {
                    self.i += 1;
                    if (self.i >= self.code.len)
                        return .GREAT;
                    switch(self.code[self.i]) {
                        '>' => {
                            self.i += 1;
                            return .GREAT_GREAT;
                        },
                        '&' => {
                            self.i += 1;
                            return .GREAT_AMP;
                        },
                        '|' => {
                            self.i += 1;
                            return .GREAT_PIPE;
                        },
                        else => return .GREAT,
                    }
                },
                '<' => {
                    self.i += 1;
                    if (self.i >= self.code.len)
                        return .LESS;
                    switch(self.code[self.i]) {
                        '<' => {
                            self.i += 1;
                            if (self.i < self.code.len and self.code[self.i] == '-') {
                                self.i += 1;
                                return .LESS_LESS_DASH;
                            } else {
                                return .LESS_LESS;
                            }
                        },
                        '&' => {
                            self.i += 1;
                            return .LESS_AMP;
                        },
                        '>' => {
                            self.i += 1;
                            return .LESS_GREAT;
                        },
                        else => return .LESS,
                    }
                },
                else => {
                    return null;
                },
            }
        } else {
            return null;
        }
        unreachable;
    }

    // if you want a specific operator then use this, else use the other one
    fn lexComptimeControlOperator(self: *Parser, comptime oper: ControlOperator) bool {
        const start = self.i;
        for (ControlOperatorSet[@intFromEnum(oper)]) |char| {
            if(self.i >= self.code.len or self.code[self.i]!=char) {
                self.i=start;
                return false;
            }
            self.i+=1;
        }
        // control operators require the next char to NOT be another control operator
        // ie if i want PIPE then i need to ensure the next char after PIPE is not
        // another PIPE (so echo `abc || cat` doesnt turn into `echo abc | | cat`)
        // we generate the possible char array at comptime
        if (self.i < self.code.len and helper.ControlOperatorNextCharset(oper)[self.code[self.i]]) {
            self.i = start;
            return false;
        }
        log("Found Operator: {s}", .{ControlOperatorSet[@intFromEnum(oper)]});
        return true;
    }

    // if you want a specific operator then use this, else use the other one
    fn lexComptimeRedirectOperator(self: *Parser, comptime oper: RedirectOperator) bool {
        const start = self.i;
        for (RedirectOperatorSet[@intFromEnum(oper)]) |char| {
            if(self.i >= self.code.len or self.code[self.i]!=char) {
                self.i=start;
                return false;
            }
            self.i+=1;
        }
        // control operators require the next char to NOT be another control operator
        // ie if i want PIPE then i need to ensure the next char after PIPE is not
        // another PIPE (so echo `abc || cat` doesnt turn into `echo abc | | cat`)
        // we generate the possible char array at comptime
        if (self.i < self.code.len and helper.RedirectOperatorNextCharset(oper)[self.code[self.i]]) {
            self.i = start;
            return false;
        }
        log("Found Operator: {s}", .{RedirectOperatorSet[@intFromEnum(oper)]});
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
        while (self.i<self.code.len and
                   helper.WhitespaceChars[self.code[self.i]]) self.i+=1;
        return self.i - start;
    }

    fn skipNewlines(self: *Parser) usize {
        const start = self.i;
        while (self.i<self.code.len and self.code[self.i]=='\n') self.i+=1;
        return self.i - start;
    }

    fn fail(self: *Parser, tag: ParseDiagnostics.Tag, pos: usize) ParseErr {
        self.diag = .{ .tag = tag, .pos = pos };
        return error.SyntaxError;
    }
};

test "parse simple command with a single word" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var parser = Parser.init(allocator);
    const program = try parser.run("ls") orelse return error.TestExpectedProgram;

    try std.testing.expectEqual(@as(usize, 1), program.andors.items.len);
    const andor = program.andors.items[0];
    try std.testing.expectEqual(@as(usize, 1), andor.pipelines.items.len);
    const pipeline = andor.pipelines.items[0];
    try std.testing.expectEqual(@as(usize, 1), pipeline.cmds.items.len);
    const sc = pipeline.cmds.items[0].simple_command;
    try std.testing.expect(sc.cmd != null);
    const ls = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text,
                                       sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted,
                                sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 0), sc.args.items.len);
    try std.testing.expectEqual(@as(usize, 0), sc.assignments.items.len);
}

test "parse simple command with arguments" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var parser = Parser.init(allocator);
    const program = try parser.run("echo hello world")
        orelse return error.TestExpectedProgram;

    const echo: ast.Word = .{ .literal =
                                 .{ .text = "echo", .quoted = Quoted.NONE } };
    const hello: ast.Word = .{ .literal =
                                  .{ .text = "hello", .quoted = Quoted.NONE } };
    const world: ast.Word = .{ .literal =
                                  .{ .text = "world", .quoted = Quoted.NONE } };

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    try std.testing.expectEqualStrings(echo.literal.text,
                                       sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(echo.literal.quoted,
                                sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 2), sc.args.items.len);

    try std.testing.expectEqualStrings(hello.literal.text,
                                       sc.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(hello.literal.quoted,
                                sc.args.items[0].items[0].literal.quoted);
    try std.testing.expectEqualStrings(world.literal.text,
                                       sc.args.items[1].items[0].literal.text);
    try std.testing.expectEqual(world.literal.quoted,
                                sc.args.items[1].items[0].literal.quoted);
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
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var parser = Parser.init(allocator);
    const program = try parser.run("ls | grep foo")
        orelse return error.TestExpectedProgram;

    const pipeline = program.andors.items[0].pipelines.items[0];
    try std.testing.expectEqual(@as(usize, 2), pipeline.cmds.items.len);

    const first = pipeline.cmds.items[0].simple_command;
    const ls: ast.Word = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text,
                                       first.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted,
                                first.cmd.?.items[0].literal.quoted);

    const second = pipeline.cmds.items[1].simple_command;
    const grep: ast.Word = .{ .literal = .{ .text = "grep", .quoted = Quoted.NONE } };
    const foo: ast.Word = .{ .literal = .{ .text = "foo", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(grep.literal.text,
                                       second.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(grep.literal.quoted,
                                second.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqualStrings(foo.literal.text,
                                       second.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(foo.literal.quoted,
                                second.args.items[0].items[0].literal.quoted);
}

test "parse a list with a separator and a backgrounded command" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var parser = Parser.init(allocator);
    const program = try parser.run("ls; sleep 1 &")
        orelse return error.TestExpectedProgram;

    try std.testing.expectEqual(@as(usize, 2), program.andors.items.len);

    const first = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    const ls: ast.Word = .{ .literal = .{ .text = "ls", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(ls.literal.text,
                                       first.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(ls.literal.quoted,
                                first.cmd.?.items[0].literal.quoted);

    const second = program.andors.items[1].pipelines.items[0].cmds.items[0].simple_command;
    const sleep: ast.Word = .{ .literal = .{ .text = "sleep", .quoted = Quoted.NONE } };
    const one: ast.Word = .{ .literal = .{ .text = "1", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(sleep.literal.text,
                                       second.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(sleep.literal.quoted,
                                second.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqualStrings(one.literal.text,
                                       second.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(one.literal.quoted,
                                second.args.items[0].items[0].literal.quoted);

    try std.testing.expectEqual(@as(usize, 2), program.background.items.len);
    try std.testing.expectEqual(false, program.background.items[0]);
    try std.testing.expectEqual(true, program.background.items[1]);
}

test "parse a basic print string" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var parser = Parser.init(allocator);
    const program = try parser.run("echo \"Hello World!!!\"")
        orelse return error.TestExpectedProgram;

    const sc = program.andors.items[0].pipelines.items[0].cmds.items[0].simple_command;
    const echo: ast.Word = .{ .literal = .{ .text = "echo", .quoted = Quoted.NONE } };
    try std.testing.expectEqualStrings(echo.literal.text, sc.cmd.?.items[0].literal.text);
    try std.testing.expectEqual(echo.literal.quoted, sc.cmd.?.items[0].literal.quoted);
    try std.testing.expectEqual(@as(usize, 1), sc.args.items.len);
    const hello_world: ast.Word = .{
        .literal = .{
            .text = "Hello World!!!",
            .quoted = Quoted.DOUBLE
        }
    };
    try std.testing.expectEqualStrings(hello_world.literal.text,
                                       sc.args.items[0].items[0].literal.text);
    try std.testing.expectEqual(hello_world.literal.quoted,
                                sc.args.items[0].items[0].literal.quoted);
}
