const rzvm = @import("../vm.zig").rzvm;
const std = @import("std");

pub fn exit(vm: *rzvm, argv: []const []const u8) u8 {
    const code = switch (argv.len) {
        1 => vm.runtime.getGlobal("?").?.asU8(),
        2 => std.fmt.parseInt(u8, argv[1], 10) catch unreachable,
        else => 1,
    };
    vm.halt = code;
    return code;
}
