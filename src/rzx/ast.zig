const std = @import("std");

pub const Program = struct {
    simple_command: SimpleCommand,
};

pub const SimpleCommand = struct {
    assignments: std.ArrayList(AssignmentWords),
    cmd: ?[]const u8,
    args: std.ArrayList([]const u8),
    redirects: std.ArrayList(IoRedirection),
};

pub const AssignmentWords = struct {
    name: []const u8,
    value: []const u8,
};

pub const Redirect = enum {
    INVALID,   // invalid
    LESSTHAN,  // <
    LESSAND,   // <&
    GREATTHAN, // >
    DGREAT,    // >>
    LESSGREAT, // <>
    CLOBBER,   // >|
};

pub const IoRedirection = struct {
    typ: Redirect,
    filename: []const u8,
};
