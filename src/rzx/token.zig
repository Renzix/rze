
const std = @import("std");

pub const TokenType = enum {
    NONE,
    WORD,
    ASSIGNMENT_WORD,
    NAME,
    NEWLINE,
    IO_NUMBER,
    IO_LOCATION,
};

pub const Quoted = enum {
    NONE,
    DOUBLE,
    SINGLE,
};

pub const Keyword = enum {
    BANG,
    LBRACE, RBRACE,
    CASE, ESAC,
    IN,
    IF, ELIF, FI,
};

pub const KeywordSet: []const []const u8 = &.{
    "!",
    "{", "}",
    "case", "esac",
    "in",
    "if", "elif", "fi",
};

pub const ControlOperator = enum {
    AMP, AMP_AMP, LPAREN, RPAREN,
    SEMI, SEMI_SEMI, NEWLINE,
    PIPE, PIPE_PIPE,
};

pub const ControlOperatorSet: []const []const u8 = &.{
    "&", "&&", "(", ")",
    ";", ";;", "\n",
    "|", "||"
};

pub const RedirectOperator = enum {
    LESS, LESS_LESS, LESS_LESS_DASH,
    LESS_AMP, LESS_GREAT,
    GREAT, GREAT_GREAT, GREAT_AMP, GREAT_PIPE,
};

pub const RedirectOperatorSet: []const []const u8 = &.{
    "<", "<<", "<<-",
    "<&", "<>",
    ">", ">>", ">&", ">|",
};

// static assert bc every keyword should be in both keyword and keywordset
comptime {
    std.debug.assert(KeywordSet.len == @typeInfo(Keyword).@"enum".fields.len);
    std.debug.assert(ControlOperatorSet.len == @typeInfo(ControlOperator).@"enum".fields.len);
    std.debug.assert(RedirectOperatorSet.len == @typeInfo(RedirectOperator).@"enum".fields.len);
}

fn CharsetFrom(comptime words: []const []const u8) [256]bool {
    var table = [_]bool{false} ** 256;
    for (words) |w| for (w) |c| { table[c] = true; };
    return table;
}

// used to generate a array of stuff we DONT want
pub fn ControlOperatorNextCharset(comptime oper: ControlOperator) [256]bool {
    var table = [_]bool{false} ** 256;
    const text = ControlOperatorSet[@intFromEnum(oper)];
    for (ControlOperatorSet) |other| {
        if (other.len > text.len and std.mem.startsWith(u8, other, text)) {
            table[other[text.len]] = true;
        }
    }
    return table;
}

fn Charset(comptime chars: []const u8) [256]bool {
    var table = [_]bool{false} ** 256;
    for (chars) |c| table[c] = true;
    return table;
}

pub const WordChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "!_${}\"'.\\-/*?[]=:~+,@%#");

pub const AssignmentChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "_${}\"'" ++ "=");

pub const WhitespaceChars = Charset(" \t");

pub const DelimChars = Charset(" \t\n;&|()<>");

pub const VariableChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "{}_");

pub const KeywordChars = CharsetFrom(KeywordSet);
