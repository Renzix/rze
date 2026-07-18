const log = @import("std").log.debug;
const ast = @import("ast.zig");
const vm  = @import("../rzvm/bytecode.zig");

pub const Compiler = struct{
    prog: ast.Program,
    i: usize,
    pub fn init() ?Compiler {
        return .{ .prog = undefined, .i = 0 };
    }
    // returns bytecode
    pub fn run(self: *Compiler, prog: ast.Program) []const u8 {
        self.prog = prog;
        self.i = 0;
        // Compile the AST to buyecode
        return "";
    }
};
