const std = @import("std");
const Quoted = @import("token.zig").Quoted;

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
    cmd: ?std.ArrayList(Word),
    args: std.ArrayList(std.ArrayList(Word)),
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
    filename: std.ArrayList(Word),
};

pub const ExpandTypes = enum { variable, variable_bracket, command };
pub const WordTypes = enum { literal, expand };
pub const Word = union(WordTypes) {
    literal: struct { text: []const u8, quoted: Quoted },
    expand: struct { name: []const u8, typ: ExpandTypes },
};
