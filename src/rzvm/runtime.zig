const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;

pub const Proto = struct {
    startpc: u16,
    argcount: u8,
    framesize: u8,
    flags: u8, // reserved, for $@ maybe???
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
            .startpc = startpc,
            .argcount = argcount,
            .framesize = framesize,
            .flags = flags };
        self.fi += 1;
        return self.fi-1;
    }
};
