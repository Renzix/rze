const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;
const StringHeader = @import("datatypes/string.zig").StringHeader;

pub const Proto = struct {
    argcount: u8,
    impl: union(enum) {
        bytecode: struct {
            startpc: u16,
            framesize: u8,
        },
        // native: *const NativeFn,
        exec: *StringHeader, // @TODO(Renzix): Remove now that string is callable??
    },
};
pub const Runtime = struct {
    stdinfd: u8,
    stdoutfd: u8,
    stderrfd: u8,
    fi: u16,
    gi: u16,
    ci: u16,
    constants: [10000]RzValue,
    variables: [std.math.maxInt(u16)+1]RzValue,
    symbol: std.StringHashMap(u16),
    functions: [1024]Proto, // replace with closures???
    const allocator = std.heap.c_allocator;

    pub fn init() Runtime {
        var self = Runtime{
            .stdinfd = 0,
            .stdoutfd = 0,
            .stderrfd = 0,
            .fi = 0,
            .gi = 0,
            .ci = 0,
            .constants = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** 10000,
            .variables = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** (std.math.maxInt(u16) + 1),
            .symbol = .init(allocator),
            .functions = undefined,
        };

        // some init stuff
        self.stdinfd = @intCast(self.addConstant(RzValue.initFd(0)));
        self.stdoutfd = @intCast(self.addConstant(RzValue.initFd(1)));
        self.stderrfd = @intCast(self.addConstant(RzValue.initFd(2)));

        return self;
    }

    pub fn addGlobal(self: *Runtime, name: []const u8, value: RzValue) u16 {
        if (self.symbol.get(name)) |gi| {
            return gi;
        }
        self.symbol.put(name, self.gi) catch @panic("oom, no space for symbol");
        self.variables[self.gi] = value;
        self.gi += 1;
        return self.gi-1;
    }

    pub fn getGlobal(self: *Runtime, name: []const u8) ?RzValue {
        if (self.symbol.get(name)) |loc| {
            return self.variables[loc];
        }
        return null;
    }

    pub fn findGlobal(self: *Runtime, name: []const u8) ?u16 {
        if (self.symbol.get(name)) |loc| {
            return loc;
        }
        return null;
    }

    pub fn reserveGlobal(self: *Runtime, name: []const u8) u16 {
        if (self.symbol.get(name)) |gi| {
            return gi;
        }
        self.symbol.put(name, self.gi) catch @panic("oom, no space for symbol");
        self.gi += 1;
        return self.gi-1;
    }

    pub fn addConstant(self: *Runtime, value: RzValue) u16 {
        self.constants[self.ci] = value;
        self.ci += 1;
        return self.ci-1;
    }

    pub fn getConstant(self: *Runtime, loc: u16) RzValue {
        return self.constants[loc];
    }

    pub fn setFunction(self: *Runtime, startpc: u16, argcount: u8, framesize: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .bytecode = .{ .startpc = startpc, .framesize = framesize} },
            .argcount = argcount,
        };
        self.fi += 1;
        return self.fi-1;
    }
    pub fn setExecFunction(self: *Runtime, bin: *StringHeader, argcount: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .exec = bin },
            .argcount = argcount,
        };
        self.fi += 1;
        return self.fi-1;
    }
};
