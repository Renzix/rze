const std = @import("std");

pub const Program = struct {
    andors: std.ArrayList(AndOr),
    background: std.ArrayList(bool),
};

pub const AndOrIf = enum { and_if, or_if };
pub const AndOr = struct {
    pipelines: std.ArrayList(Pipeline),
    and_or_list: std.ArrayList(AndOrIf),
};

pub const Pipeline = struct {
    bang: bool,
    cmds: std.ArrayList(Command),
};

pub const CommandTypes = enum { simple_command, complex_command, function_definition };
pub const Command = union(CommandTypes) {
    simple_command: SimpleCommand,
    complex_command: ComplexCommand,
    function_definition: FunctionDefinition,
};

pub const SimpleCommand = struct {
    assignments: std.ArrayList(AssignmentWords),
    cmd: ?[]const u8,
    args: std.ArrayList([]const u8),
    redirects: std.ArrayList(IoRedirection),
};

pub const ComplexCommand = struct {
    //@TODO(Renzix): Implement
};
pub const FunctionDefinition = struct {
    //@TODO(Renzix): Implement
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

pub const WordTypes = enum { literal, expand };
pub const Word = union(WordTypes) {
    literal: []const u8,
    expand: []const u8,
};
