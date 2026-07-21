
const std = @import("std");

pub const StringKind = enum(u8) {
    // inlineStr,  // max size of u64 for small strings, not here bc its in rzval
    staticStr,    // predefined constant strings
    allocatedStr, // raw allocated strings
    ropeStr,       // String datatype for editing
};
pub const StringHeader = struct {
    kind: StringKind,
    len: usize, // switch back to u32 for performance reasons

    pub fn slice(header: *const StringHeader) []const u8 {
        switch (header.kind) {
            .staticStr => {
                const s: *const StaticStr = @alignCast(@fieldParentPtr("header", header));
                return s.str[0..header.len];
            },
            .allocatedStr => {
                const s: *const AllocatedStr = @fieldParentPtr("header", header);
                const base: [*]const u8 = @ptrCast(s);
                return base[@sizeOf(AllocatedStr)..][0..header.len];
            },
            .ropeStr => @panic("ropes not implemented"),
        }
    }
};

// allocatedStr is handled by allocating more then enough stuff in StringHeader
pub const AllocatedStr = struct {
    header: StringHeader,
};

pub fn CreateAllocatedStr(str: []const u8, allocator: std.mem.Allocator) *AllocatedStr {
    // zig specific thing bc zig doesnt like when you alloc more then the type needs
    // and we align for performance reasons
    const raw = allocator.alignedAlloc(u8, .of(AllocatedStr),
                                       @sizeOf(StringHeader)+str.len) catch @panic("oom");
    const ret: *AllocatedStr = @ptrCast(raw);
    ret.header = .{ .kind = .allocatedStr, .len = str.len };
    // copy the string to the memory AFTER the AllocatedStr header.
    // We do this so we can define our own string
    @memcpy(raw[@sizeOf(AllocatedStr)..], str[0..str.len]);
    return ret;
}

pub fn DestroyAllocatedStr(str: *AllocatedStr, allocator: std.mem.Allocator) void {
    const total = @sizeOf(AllocatedStr) + str.header.len;
    // u apparently need align bc C malloc stores the amount of bytes it handed
    // you but zig doesnt and infers from the type.
    const raw: [*]align(@alignOf(AllocatedStr)) u8 = @ptrCast(str);
    allocator.free(raw[0..total]);
}


pub const StaticStr = struct {
    header: StringHeader,
    str: [*]const u8,
};

pub inline fn CreateStaticStr(comptime str: []const u8) StaticStr {
    return .{
        .header = .{ .kind = .staticStr, .len = str.len },
        .str = str.ptr,
    };
}

// @TODO(Renzix): Rope String
