
pub const StringKind = enum(u8) {
    // inlineStr,  // max size of u64 for small strings, not here bc its in rzval
    staticStr,    // predefined constant strings
    allocatedStr, // raw allocated strings
    ropeStr,       // String datatype for editing
};
pub const StringHeader = struct {
    kind: StringKind,
    len: u32,

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

pub const StaticStr = struct {
    header: StringHeader,
    str: [*]const u8,
};

pub inline fn CreateStaticStr(comptime str: []const u8) StaticStr {
    return .{
        .header = .{ .kind = .staticStr, .len = str.len },
        .str = str.ptr
    };
}

// @TODO(Renzix): Rope String
