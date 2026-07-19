const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;

pub const runtime = struct {
    var i: u16 = 0;
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    pub var global = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** (std.math.maxInt(u16) + 1);
    pub var symbol: std.StringHashMap(u16) = .init(arena.allocator());

    pub fn setVariable(name: []const u8, value: RzValue) u16 {
        symbol.put(name, i) catch @panic("oom, no space for symbol");
        global[i] = value;
        i += 1;
        return i-1;
    }

    pub fn getVariable(name: []const u8) ?RzValue {
        if (symbol.get(name)) |loc| {
            return global[loc];
        }
        return null;
    }
};
