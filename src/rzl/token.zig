pub const TokenType = enum {
    L_PAREN,
    R_PAREN,
    SYMBOL,
    STRING,
};

pub const Token = struct {
    token_type: TokenType,
    contents: []const u8,
};
