const std = @import("std");

pub const Program = struct {
    simple_command: SimpleCommand,
};

pub const SimpleCommand = struct {
    assignments: std.ArrayList(AssignmentWords),
    cmd: ?[]const u8,
    args: [][]const u8,
    redirects: IoRedirection,
};

pub const AssignmentWords = struct {
    name: []const u8,
    value: []const u8,
};

pub const IoRedirection = struct {
    // input redirect?
    // output redirect?
};
