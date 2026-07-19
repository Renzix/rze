const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;

pub const Runtime = struct {
    i: u16,
    global: [std.math.maxInt(u16)+1]RzValue,
    symbol: std.StringHashMap(u16),
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    pub fn init() Runtime {
        return .{
            .i = 0,
            .global = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** (std.math.maxInt(u16) + 1),
            .symbol = .init(arena.allocator()),
        };
    }

    pub fn setVariable(self: *Runtime, name: []const u8, value: RzValue) u16 {
        self.symbol.put(name, self.i) catch @panic("oom, no space for symbol");
        self.global[self.i] = value;
        self.i += 1;
        return self.i-1;
    }

    pub fn getVariable(self: *Runtime, name: []const u8) ?RzValue {
        if (self.symbol.get(name)) |loc| {
            return self.global[loc];
        }
        return null;
    }
};
