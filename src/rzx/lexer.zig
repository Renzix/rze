const std = @import("std");

// @TODO(Renzix): Move these types to their own file
pub const TokenType = enum {
    WORD,
    ASSIGNMENT_WORD,
    NAME,
    CONTROL_OPERATOR,
    NEWLINE,
    IO_NUMBER,
    IO_LOCATION,
};

pub const TokenSubType = enum {
    UNKNOWN,
    IDENTIFIER,
    RESERVED_IF,
    RESERVED_THEN,
    RESERVED_ELSE,
    RESERVED_ELIF,
    RESERVED_FI,
    RESERVED_DO,
    RESERVED_DONE,
    RESERVED_CASE,
    RESERVED_ESAC,
    RESERVED_WHILE,
    RESERVED_UNTIL,
    RESERVED_FOR,
    RESERVED_CURLY_BRACKET,
    RESERVED_EXCLAIMATION,
    RESERVED_IN,
    OPERATOR_PIPE,
};

pub const Token = struct {
    token_type: TokenType,
    sub_type: TokenSubType,
    contents: []const u8,
};

const Quoted = enum {
    QUOTED_NONE,
    QUOTED_DOUBLE,
    QUOTED_SINGLE,
};

pub const Cons = struct {
    car: *const SExpr,
    cdr: *const SExpr,
};
pub const AtomType = enum { symbol, string, integer, double, boolean };
pub const Atom = union(AtomType) {
    symbol: []const u8,
    string: []const u8,
    integer: i64,
    double: f64,
    boolean: bool,
};
pub const SExprType = enum { atom, nil, cons };
pub const SExpr = union(SExprType) {
    atom: Atom,
    nil: void,
    cons: Cons,
};
const reserved = [_][]const u8{
    "if",   "then", "else", "elif",  "fi",    "do",
    "done", "case", "esac", "while", "until", "for",
    "{",    "}",    "!",    "in",
};
const operators = [_][]const u8{
    "&&", "||", ";;", "<<",  ">>",
    "<&", ">&", "<>", "<<-", ">|",
};

pub const Lexer = struct {
    const allocator = std.heap.c_allocator;
    pub fn init() Lexer {
        return Lexer{};
    }
    pub fn run(_: *Lexer, str: []const u8, token_list: *std.ArrayList(Token)) !void {
        // "" edge case
        if (str.len == 0) {
            return;
        }
        var i: usize = 0;
        var ch = str[i];

        while (i < str.len) {
            ch = str[i];
            switch (ch) {
                ' ', '\t', '\n' => {
                    i += 1;
                },
                '|' => {
                    // pipe
                    std.debug.print("Found Pipe: |\n", .{});
                    const token = Token{
                        .token_type = TokenType.CONTROL_OPERATOR, // @TODO(Renzix): put in WORD section
                        .sub_type = TokenSubType.OPERATOR_PIPE,
                        .contents = "=",
                    };
                    try token_list.append(allocator, token);
                    i += 1;
                },
                // @TODO(Renzix): This needs to be rewritten to be not awful
                'a'...'z', 'A'...'Z', '_', '-', '$', '/', '.', '"', '\'', ':' => {
                    var in_quote = Quoted.QUOTED_NONE;
                    var backslash = false; // true if previous char is backslash
                    var in_assignment = false;

                    const start = i;
                    while (i < str.len) {
                        if ((in_quote == Quoted.QUOTED_NONE) and (str[i] == '"')) {
                            in_quote = Quoted.QUOTED_DOUBLE;
                        } else if ((in_quote == Quoted.QUOTED_NONE) and (str[i] == '\'')) {
                            in_quote = Quoted.QUOTED_SINGLE;
                        } else {
                            if (in_quote == Quoted.QUOTED_NONE) {
                                if (backslash) {
                                    backslash = false;
                                } else if (str[i] == '\\') {
                                    backslash = true;
                                } else if (str[i] == '=') {
                                    in_assignment = true;
                                } else {
                                    const valid = switch (str[i]) {
                                        '0'...'9',
                                        'A'...'Z',
                                        'a'...'z',
                                        '_',
                                        '-',
                                        '$',
                                        '/',
                                        '.',
                                        ':',
                                        '{',
                                        '}',
                                        => true,
                                        else => false,
                                    };
                                    if (!valid) {
                                        break;
                                    }
                                }
                            } else {
                                if ((in_quote == Quoted.QUOTED_SINGLE) and ('\'' == str[i])) {
                                    in_quote = Quoted.QUOTED_NONE;
                                } else if (backslash) {
                                    backslash = false;
                                } else if ((in_quote == Quoted.QUOTED_DOUBLE) and ('"' == str[i])) {
                                    // there might be a better way but we run
                                    // the double quote after checking for
                                    // backslash so we can escape certain characters
                                    in_quote = Quoted.QUOTED_NONE;
                                } else if (str[i] == '\\') {
                                    backslash = true;
                                }
                            }
                        }
                        i += 1;
                    }
                    const word = str[start..i];
                    std.debug.print("Found Word: {s}\n", .{word});
                    const current_token_type = if (in_assignment)
                        TokenType.ASSIGNMENT_WORD
                    else
                        TokenType.WORD;

                    // @TODO(Renzix): Determine if NAME, WORD or ASSIGNMENT_WORD
                    const token = Token{
                        .token_type = current_token_type,
                        .sub_type = TokenSubType.UNKNOWN,
                        .contents = word,
                    };
                    try token_list.append(allocator, token);
                },
                else => {
                    std.debug.print("Unknown char {c}\n", .{ch});
                    i += 1;
                },
            }
        }
    }
    // pub fn expander(_: *Rzx) !void {
    //     //
    // }
    // pub fn executor(tokens: std.ArrayList([]const u8)) !void {
    //     const args = tokens.items;
    //     if (args.len == 0) return;

    //     // Use std.process.Child to run the command
    //     var child = std.process.Child.init(args, allocator);
    //     _ = try child.spawnAndWait();
    // }

    // pub fn run(self: *Rzx, str: []const u8) !void {
    //     try self.lexer(str);
    //     const ast = try parser(self.token_list);
    //     try self.expander();
    //     _ = ast;
    //     // try executor
    // }
};

test "Basic Lexer" {
    var rzx = Lexer.init();
    // defer rzx.deinit();
    var token_list: std.ArrayList(Token) = .empty;

    try rzx.run("ls", &token_list);
    try rzx.run("ls -l", &token_list);
    try rzx.run("ls -l /home/user", &token_list);
    try rzx.run("cd ..", &token_list);
}

test "String Run" {
    var rzx = Lexer.init();
    // defer rzx.deinit();
    var token_list: std.ArrayList(Token) = .empty;
    try rzx.run("echo \"hello world\"", &token_list);
    try rzx.run("echo 'hello world'", &token_list);
    try rzx.run("echo \"a string with 'single' quotes\"", &token_list);
    try rzx.run("echo 'a string with \"double\" quotes'", &token_list);
    try rzx.run("ls \"my report.txt\"", &token_list);
    try rzx.run("echo \"   spaces  leading and trailing   \"", &token_list);
}
test "Variable Run" {
    var rzx = Lexer.init();
    // defer rzx.deinit();
    var token_list: std.ArrayList(Token) = .empty;
    try rzx.run("echo $VAR", &token_list);
    try rzx.run("echo \"value: $HOME\"", &token_list);
    try rzx.run("myvar=hello", &token_list);
    try rzx.run("PATH=$PATH:/usr/bin", &token_list);
    try rzx.run("echo ${BRACES}", &token_list);
    try rzx.run("echo ${BRACES:-test}", &token_list);
}

test "Random Run" {
    var rzx = Lexer.init();
    // defer rzx.deinit();
    var token_list: std.ArrayList(Token) = .empty;
    try rzx.run("", &token_list);
    try rzx.run("   ls   -l   ", &token_list);
    try rzx.run("cmd | grep \"foo\"", &token_list);
    try rzx.run("ls -a -l -h", &token_list);
}
