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
};

pub const GcBit = enum(u2) {
    White = 0b00,
    Grey = 0b01,
    Black = 0b10,
    Static = 0b11,
};

pub const vmerr = enum(u48) {
    UNKNOWN = 0,
    ADD_OVERFLOW = 1,
    ADD_ERROR = 2,
    ADD_NULL = 3,
};

// packed 64 bit struct for "common types"
pub const RzValue = packed struct(u64) {
    type_info: TypeInfo, // u8
    ptr: u1,
    mutable: u1,
    nullable: u1,
    err: u1,
    gc: GcBit, // u2
    reserved: u2,
    data: u48,

    pub inline fn toBytes(self: RzValue) [8]u8 {
        // std.debug.print("rzvalue: {}\n", .{self.data});
        return std.mem.toBytes(@as(u64, @bitCast(self)));
    }
    pub inline fn toU64(self: RzValue) u64 {
        return @bitCast(self);
    }

    pub fn init(type_info: TypeInfo, ptr: u1, mutable: u1, nullable: u1, err: u1, gc: GcBit, val: u48) RzValue {
        return .{
            .type_info = type_info,
            .ptr = ptr,
            .mutable = mutable,
            .nullable = nullable,
            .err = err,
            .gc = gc,
            .reserved = undefined,
            .data = val,
        };
    }

    pub fn initInt(val: i48) RzValue {
        const raw: u48 = @bitCast(val);
        return init(TypeInfo.int, 0, 0, 0, 0, GcBit.White, raw);
    }

    // @TODO(Renzix): Switch to f64 and cut off the percision maybe?
    pub fn initFloat(val: f32) RzValue {
        const raw: u32 = @bitCast(val);
        return init(TypeInfo.float, 0, 0, 0, 0, GcBit.White, raw);
    }

    pub inline fn convertIntToFloat(self: *RzValue) void {
        const floatval: f32 = @floatFromInt(self.data);
        const temp: u32 = @bitCast(floatval);
        self.type_info = TypeInfo.float;
        self.data = @as(u48, @intCast(temp));
    }

    pub inline fn dataToF32(self: RzValue) f32 {
        return @bitCast(@as(u32, @intCast(self.data)));
    }
    pub inline fn f32ToData(self: *RzValue, val: f32) void {
        self.data = @as(u48, @intCast(@as(u32, @bitCast(val))));
    }
};
