pub const AtomType = enum { symbol, string, integer, double, boolean, nil };
pub const Atom = union(AtomType) {
    symbol: []const u8,
    string: []const u8,
    integer: i64,
    double: f64,
    boolean: bool,
    nil: void,
};
pub const SExprType = enum { atom, cons };
pub const SExpr = union(SExprType) {
    atom: Atom,
    cons: Cons,
};
pub const Cons = struct {
    car: *const SExpr,
    cdr: *const SExpr,
};
