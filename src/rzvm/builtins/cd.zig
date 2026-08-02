const rzvm = @import("../vm.zig").rzvm;
const std = @import("std");

pub fn cd(vm: *rzvm, argv: []const []const u8) u8 {
    switch (argv.len) {
        1 => {
            if (vm.runtime.getGlobal("HOME")) |dir| {
                std.process.setCurrentPath(vm.io, dir.asStringHeader().slice()) catch return 1;
            }
            return 0;
        },
        2 => {
            std.process.setCurrentPath(vm.io, argv[1]) catch return 1;
            return 0;
        },
        else => return 1,
    }
    unreachable;
}
