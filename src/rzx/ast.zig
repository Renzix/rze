const std = @import("std");
const Quoted = @import("token.zig").Quoted;

pub const Program = struct {
    andors: std.ArrayList(AndOr),
    background: std.ArrayList(bool),
};

pub const AndOrIf = enum { and_if, or_if, end };
pub const AndOr = struct {
    pipelines: std.ArrayList(Pipeline),
    and_or_list: std.ArrayList(AndOrIf),
};

pub const Pipeline = struct {
    bang: bool,
    cmds: std.ArrayList(Command),
};

pub const CommandTypes = enum { simple_command, compound_command, function_definition };
pub const Command = union(CommandTypes) {
    simple_command: SimpleCommand,
    compound_command: CompoundCommand,
    function_definition: FunctionDefinition,
};

pub const SimpleCommand = struct {
    assignments: std.ArrayList(AssignmentWord),
    cmd: ?std.ArrayList(Word),
    args: std.ArrayList(std.ArrayList(Word)),
    redirects: std.ArrayList(IoRedirection),
};

pub const CompoundCommandTypes = enum {
    brace_group, subshell, for_clause, case_clause,
    if_clause, while_clause, until_clause,
};
pub const CompoundCommand = union(CompoundCommandTypes) {
    brace_group: BraceGroup,
    subshell: Subshell,
    for_clause: ForClause,
    case_clause: CaseClause,
    if_clause: IfClause,
    while_clause: WhileClause,
    until_clause: UntilClause,
};

pub const CompoundList = struct {
    andors: std.ArrayList(AndOr),
};

pub const BraceGroup = struct {
    group: CompoundList,
};
pub const Subshell = struct {
    // @TODO(Renzix): Implement
};
pub const ForClause = struct {
    // @TODO(Renzix): Implement
};
pub const CaseClause = struct {
    // @TODO(Renzix): Implement
};
pub const IfClause = struct {
    checks: std.ArrayList(CompoundList),
    bodies: std.ArrayList(CompoundList),
    else_: ?CompoundList,
};
pub const WhileClause = struct {
    check: CompoundList,
    body: CompoundList,
};
pub const UntilClause = struct {
    check: CompoundList,
    body: CompoundList,
};

pub const FunctionDefinition = struct {
    //@TODO(Renzix): Implement
};

pub const AssignmentWord = struct {
    name: []const u8,
    value: ?std.ArrayList(Word),
};

pub const Redirect = enum {
    LESS,           // <
    LESS_LESS,      // <<
    LESS_LESS_DASH, // <<-
    LESS_AMP,       // <&
    LESS_GREAT,     // <>
    GREAT,          // >
    GREAT_GREAT,    // >>
    GREAT_PIPE,     // >|
    GREAT_AMP,      // >&
};

pub const TargetTypes = enum { filename, fd };
pub const Target = union(TargetTypes) {
    filename: std.ArrayList(Word),
    fd: u8,
};
pub const IoRedirection = struct {
    typ: Redirect,
    target: Target,
    fd: ?u8,
};

pub const ExpandTypes = enum { variable, variable_bracket, command };
pub const WordTypes = enum { literal, expand };
pub const Word = union(WordTypes) {
    literal: struct { text: []const u8, quoted: Quoted },
    expand: struct { name: []const u8, quoted: Quoted, typ: ExpandTypes },
};
