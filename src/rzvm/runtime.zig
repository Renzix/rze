const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;
const StringHeader = @import("datatypes/string.zig").StringHeader;

pub const Proto = struct {
    argcount: u8,
    flags: u8,
    impl: union(enum) {
        bytecode: struct {
            startpc: u16,
            framesize: u8,
        },
        // native: *const NativeFn,
        exec: *StringHeader,
    },
};
pub const Runtime = struct {
    fi: u16,
    vi: u16,
    global: [std.math.maxInt(u16)+1]RzValue,
    functions: [1024]Proto, // replace with closures???
    symbol: std.StringHashMap(u16),
    const allocator = std.heap.c_allocator;

    pub fn init() Runtime {
        return .{
            .fi = 0,
            .vi = 0,
            .global = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** (std.math.maxInt(u16) + 1),
            .symbol = .init(allocator),
            .functions = undefined,
        };
    }

    pub fn setVariable(self: *Runtime, name: []const u8, value: RzValue) u16 {
        self.symbol.put(name, self.vi) catch @panic("oom, no space for symbol");
        self.global[self.vi] = value;
        self.vi += 1;
        return self.vi-1;
    }

    pub fn getVariable(self: *Runtime, name: []const u8) ?RzValue {
        if (self.symbol.get(name)) |loc| {
            return self.global[loc];
        }
        return null;
    }

    pub fn setFunction(self: *Runtime, startpc: u16, argcount: u8, framesize: u8, flags: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .bytecode = .{ .startpc = startpc, .framesize = framesize} },
            .argcount = argcount,
            .flags = flags };
        self.fi += 1;
        return self.fi-1;
    }
    pub fn setExecFunction(self: *Runtime, bin: *StringHeader, argcount: u8, flags: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .exec = bin },
            .argcount = argcount,
            .flags = flags };
        self.fi += 1;
        return self.fi-1;
    }
};
