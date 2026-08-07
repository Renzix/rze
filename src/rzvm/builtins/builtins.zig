const std = @import("std");
const cd = @import("cd.zig").cd;
const test_ = @import("test.zig").test_;
const printf = @import("printf.zig").printf;
const exit = @import("exit.zig").exit;
const rzvm = @import("../vm.zig").rzvm;

pub const NativeFn = fn (*rzvm, []const []const u8) u8;

pub const table = std.StaticStringMap(*const NativeFn).initComptime(.{
    .{ "cd", &cd },
    .{ "exit", &exit },
    .{ "printf", &printf },
    .{ "test", &test_ },
    .{ "[", &test_ },
});
