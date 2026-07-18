const std = @import("std");

pub const TypeInfo = enum(u8) {
    int = 0b0000,
    float = 0b0001,
    type_ = 0b0010,
    function = 0b0101,
    string = 0b0110,
    array = 0b0111,
    map = 0b1000,
    struct_ = 0b1001,
    native_function = 0b1010,
    err = 0b1011,
};

pub const GcBit = enum(u2) {
    white = 0b00,
    grey = 0b01,
    black = 0b10,
    static = 0b11,
};

pub const VmErr = enum(u48) {
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

    pub fn initErr(err: VmErr) RzValue {
        const raw: u48 = @intFromEnum(err);
        return init(TypeInfo.err, false, false, false, GcBit.white, raw);
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
            break :blk RzValue.initErr(VmErr.null_operand);
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
                        break :blk RzValue.initErr(VmErr.overflow);
                },
                .float => {
                    break :blk switch (op) {
                        .add => RzValue.initFloat(a.asF32()+b.asF32()),
                        .sub => RzValue.initFloat(a.asF32()-b.asF32()),
                        .mul => RzValue.initFloat(a.asF32()*b.asF32()),
                    };
                },
                else => RzValue.initErr(VmErr.type_mismatch),
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
                else => RzValue.initErr(VmErr.type_mismatch),
            },
            else => RzValue.initErr(VmErr.type_mismatch),
        };
    };
}
