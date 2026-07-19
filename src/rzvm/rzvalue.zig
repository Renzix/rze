const std = @import("std");

const str = @import("datatypes/string.zig");

// reorder these
pub const TypeInfo = enum(u8) {
    int = 0b0000,
    float = 0b0001,
    type_ = 0b0010,
    function = 0b0101,
    string = 0b0110,
    array = 0b0111,
    map = 0b1000,
    struct_ = 0b1001,
    // native_function = 0b1010,
    err = 0b1011,
    boolean = 0b1100,
    // exec_function = 0b1101,
    frame = 0b1110,
};

pub const GcBit = enum(u2) {
    white = 0b00,
    grey = 0b01,
    black = 0b10,
    static = 0b11,
};

pub const RzErr = enum(u48) {
    unknown = 0,
    overflow = 1,
    type_mismatch = 2,
    null_operand = 3,
    name_not_found = 4,
};

// packed 64 bit struct for "common types"
pub const RzValue = packed struct(u64) {
    type_info: TypeInfo, // u8
    ptr: bool,
    mutable: bool,
    nullable: bool,
    gc: GcBit, // u2
    reserved: u3,
    data: u48,

    pub inline fn toBytes(self: RzValue) [8]u8 {
        // std.debug.print("rzvalue: {}\n", .{self.data});
        return std.mem.toBytes(@as(u64, @bitCast(self)));
    }
    pub inline fn toU64(self: RzValue) u64 {
        return @bitCast(self);
    }

    pub fn init(type_info: TypeInfo, ptr: bool, mutable: bool, nullable: bool, gc: GcBit, val: u48) RzValue {
        return .{
            .type_info = type_info,
            .ptr = ptr,
            .mutable = mutable,
            .nullable = nullable,
            .gc = gc,
            .reserved = 0,
            .data = val,
        };
    }

    pub fn initInt(val: i48) RzValue {
        const raw: u48 = @bitCast(val);
        return init(TypeInfo.int, false, false, false, GcBit.white, raw);
    }

    // @TODO(Renzix): Switch to f64 and cut off the percision maybe?
    pub fn initFloat(val: f32) RzValue {
        const raw: u32 = @bitCast(val);
        return init(TypeInfo.float, false, false, false, GcBit.white, raw);
    }

    // static strings are always ptrs for now
    pub fn initString(val: *const str.StringHeader) RzValue {
        const raw: u48 = @intCast(@intFromPtr(val));
        return init(TypeInfo.string, true, false, false, GcBit.white, raw);
    }

    pub fn initErr(err: RzErr) RzValue {
        const raw: u48 = @intFromEnum(err);
        return init(TypeInfo.err, false, false, false, GcBit.white, raw);
    }

    pub fn initErrCode(val: u8) RzValue {
        const raw: u48 = @as(u48, val);
        return init(TypeInfo.err, false, false, false, GcBit.static, raw);
    }

    pub fn initFunction(index: u16) RzValue {
        const raw: u48 = index;
        return init(TypeInfo.function, false, false, false, GcBit.static, raw);
    }

    pub fn initFrame(pc: u16, fp: u16) RzValue {
        const raw = @as(u48, pc) << 16 | fp;
        return init(TypeInfo.frame, false, false, false, GcBit.static, raw);
    }

    pub inline fn asI48(self: RzValue) i48 {
        return switch (self.type_info) {
            TypeInfo.int => @bitCast(self.data),
            TypeInfo.float => blk: {
                // @TODO(Renzix): This is probably stupid and not working properly
                const f: f32 = @bitCast(@as(u32, @truncate(self.data)));
                break :blk @intFromFloat(f);
            },
            else => @panic("Turning type into int is not defined yet"),
        };
    }

    pub inline fn asF32(self: RzValue) f32 {
        return switch (self.type_info) {
            TypeInfo.int => blk: {
                const int: i48 = @bitCast(self.data);
                break :blk @floatFromInt(int);
            },
            TypeInfo.float => @bitCast(@as(u32, @truncate(self.data))),
            else => @panic("Turning type into float is not defined yet"),
        };
    }
    pub inline fn setf32(self: *RzValue, val: f32) void {
        self.data = @as(u48, @intCast(@as(u32, @bitCast(val))));
    }
};

// @TODO(Renzix): Entirely seperate helper function for div?
pub fn binOp(a: RzValue, b: RzValue, comptime op: enum { add, sub, mul }) RzValue {
    return blk: {
        if (a.type_info == .err) break :blk a;
        if (b.type_info == .err) break :blk b;
        if (a.nullable or b.nullable) {
            break :blk RzValue.initErr(RzErr.null_operand);
        }
        break :blk switch (a.type_info) {
            .int => switch (b.type_info) {
                .int => {
                    const val, const overflow = switch (op) {
                        .add => @addWithOverflow(@as(i48, @bitCast(a.data)),
                                                 @as(i48, @bitCast(b.data))),
                        .sub => @subWithOverflow(@as(i48, @bitCast(a.data)),
                                                 @as(i48, @bitCast(b.data))),
                        .mul => @mulWithOverflow(@as(i48, @bitCast(a.data)),
                                                 @as(i48, @bitCast(b.data))),
                    };
                    if (overflow == 0)
                        break :blk RzValue.initInt(val)
                    else
                        break :blk RzValue.initErr(RzErr.overflow);
                },
                .float => {
                    break :blk switch (op) {
                        .add => RzValue.initFloat(a.asF32()+b.asF32()),
                        .sub => RzValue.initFloat(a.asF32()-b.asF32()),
                        .mul => RzValue.initFloat(a.asF32()*b.asF32()),
                    };
                },
                else => RzValue.initErr(RzErr.type_mismatch),
            },
            .float => switch (b.type_info) {
                .int => {
                    break :blk switch (op) {
                        .add => RzValue.initFloat(a.asF32()+b.asF32()),
                        .sub => RzValue.initFloat(a.asF32()-b.asF32()),
                        .mul => RzValue.initFloat(a.asF32()*b.asF32()),
                    };
                },
                .float => {
                    break :blk switch (op) {
                        .add => RzValue.initFloat(a.asF32()+b.asF32()),
                        .sub => RzValue.initFloat(a.asF32()-b.asF32()),
                        .mul => RzValue.initFloat(a.asF32()*b.asF32()),
                    };
                },
                else => RzValue.initErr(RzErr.type_mismatch),
            },
            else => RzValue.initErr(RzErr.type_mismatch),
        };
    };
}

pub fn compare(a: RzValue, b: RzValue,
               comptime op: enum { lessthan, greaterthan, lessthaneql,
                                  greaterthaneql, equal, notequal }) bool {
    return blk: {
        if (a.type_info == .err) break :blk false;
        if (b.type_info == .err) break :blk false;
        if (a.nullable or b.nullable) {
            break :blk false;
        }
        break :blk switch (a.type_info) {
            .int => switch (b.type_info) {
                .int => {
                    switch (op) {
                        .lessthan => break :blk a.asI48() < b.asI48(),
                        .greaterthan => break :blk a.asI48() > b.asI48(),
                        .lessthaneql => break :blk a.asI48() <= b.asI48(),
                        .greaterthaneql => break :blk a.asI48() >= b.asI48(),
                        .equal => break :blk a.asI48() == b.asI48(),
                        .notequal => break :blk a.asI48() != b.asI48(),
                    }
                },
                .float => {
                    break :blk switch (op) {
                        .lessthan => break :blk a.asF32() < b.asF32(),
                        .greaterthan => break :blk a.asF32() > b.asF32(),
                        .lessthaneql => break :blk a.asF32() <= b.asF32(),
                        .greaterthaneql => break :blk a.asF32() >= b.asF32(),
                        .equal => break :blk a.asF32() == b.asF32(),
                        .notequal => break :blk a.asF32() != b.asF32(),
                    };
                },
                else => false,
            },
            .float => switch (b.type_info) {
                .int => {
                    break :blk switch (op) {
                        .lessthan => break :blk a.asF32() < b.asF32(),
                        .greaterthan => break :blk a.asF32() > b.asF32(),
                        .lessthaneql => break :blk a.asF32() <= b.asF32(),
                        .greaterthaneql => break :blk a.asF32() >= b.asF32(),
                        .equal => break :blk a.asF32() == b.asF32(),
                        .notequal => break :blk a.asF32() != b.asF32(),
                    };
                },
                .float => {
                    break :blk switch (op) {
                        .lessthan => break :blk a.asF32() < b.asF32(),
                        .greaterthan => break :blk a.asF32() > b.asF32(),
                        .lessthaneql => break :blk a.asF32() <= b.asF32(),
                        .greaterthaneql => break :blk a.asF32() >= b.asF32(),
                        .equal => break :blk a.asF32() == b.asF32(),
                        .notequal => break :blk a.asF32() != b.asF32(),
                    };
                },
                else => false,
            },
            else => false,
        };
    };
}
