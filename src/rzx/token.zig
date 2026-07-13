
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
    QUOTED_NONE,
    QUOTED_DOUBLE,
    QUOTED_SINGLE,
};

fn Charset(comptime chars: []const u8) [256]bool {
    var table = [_]bool{false} ** 256;
    for (chars) |c| table[c] = true;
    return table;
}

pub const WordChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "_${}\"'.");

pub const AssignmentChars = Charset("abcdefghijklmnopqrstuvwxyz"
    ++ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ++ "0123456789" ++ "_${}\"'" ++ "=");

pub const WhitespaceChars = Charset(" \t");
