const std = @import("std");
const rzval = @import("rzvalue.zig");

// opcodes!!!
const opcodes = enum(u8) {
    INVALID = 0,
    EXIT = 1,
    PUSH = 2,
    POP = 3,
    ADD = 4,
};

const vmerror = error{
    INVALID_OPCODE,
};

pub const rzvm = struct {
    stack: [10000]u64,
    sp: u24,
    pc: u16,
    pub fn init() rzvm {
        return rzvm{
            .pc = 0,
            .sp = 0,
            .stack = comptime ([_]u64{0} ** 10000),
        };
    }
    pub fn reset(self: *rzvm) void {
        self.sp = 0;
        self.pc = 0;
    }
    pub inline fn run(self: *rzvm, program: []u8) vmerror!void {
        self.pc = 0;
        while (true) {
            const code: opcodes = @enumFromInt(program[self.pc]);
            switch (code) {
                opcodes.EXIT => {
                    // std.debug.print("EXIT\n", .{});
                    break;
                },
                opcodes.PUSH => {
                    // Direct memory reinterpretation without memcpy overhead
                    const val_ptr: *const rzval.RzValue = @ptrCast(@alignCast(&program[self.pc + 1]));
                    self.push(val_ptr.*);
                    self.pc += 8;
                },
                opcodes.POP => {
                    _ = self.pop();
                },
                opcodes.ADD => {
                    var var1 = self.pop();
                    var var2 = self.pop();
                    // 3 possibilities
                    // if its int + int or float + float then its easy just cast
                    // need to implement ptrs
                    // if its float + int then convert the int to a float then add
                    if (var1.type_info == var2.type_info) {
                        std.debug.assert(var1.type_info != rzval.TypeInfo.function);
                        std.debug.assert(var1.type_info != rzval.TypeInfo.map); // maybe remove???
                        // @TODO(Renzix): Implement concating array
                        // @TODO(Renzix): Implement ptr addditions
                        if ((var1.nullable | var2.nullable) != 0) {
                            var2.err = 1;
                            var2.data = @intFromEnum(rzval.vmerr.ADD_NULL);
                        } else if ((var1.err | var2.err) != 0) {
                            var2.err = 1;
                            var2.data = @intFromEnum(rzval.vmerr.ADD_ERROR);
                        } else if (var2.type_info == rzval.TypeInfo.int) {
                            const val, const overflow = @addWithOverflow(@as(i48, @bitCast(var2.data)), @as(i48, @bitCast(var1.data)));
                            if (overflow == 0) {
                                var2.data = @bitCast(val);
                            } else {
                                var2.err = 1;
                                var2.data = @intFromEnum(rzval.vmerr.ADD_OVERFLOW);
                            }
                        } else if (var2.type_info == rzval.TypeInfo.float) {
                            var2.f32ToData(var2.dataToF32() + var1.dataToF32());
                        }
                        self.push(var2);
                    } else if (((var1.type_info == rzval.TypeInfo.int) and
                        (var2.type_info == rzval.TypeInfo.float)) or
                        (((var1.type_info == rzval.TypeInfo.float) and
                            (var2.type_info == rzval.TypeInfo.int))))
                    {
                        if ((var1.nullable | var2.nullable) != 0) {
                            var2.err = 1;
                            var2.data = @intFromEnum(rzval.vmerr.ADD_NULL);
                        } else if ((var1.err | var2.err) != 0) {
                            var2.err = 1;
                            var2.data = @intFromEnum(rzval.vmerr.ADD_ERROR);
                        } else if (var2.type_info == rzval.TypeInfo.float) {
                            var1.convertIntToFloat();
                            var2.f32ToData(var2.dataToF32() + var1.dataToF32());
                        } else {
                            var2.convertIntToFloat();
                            var2.f32ToData(var2.dataToF32() + var1.dataToF32());
                        }
                        self.push(var2);
                    } else {
                        unreachable;
                    }
                },
                else => {
                    std.debug.print("UNKNOWN OPCODE\n", .{});
                    return vmerror.INVALID_OPCODE;
                },
            }
            self.pc += 1;
        }
    }
    pub fn push(self: *rzvm, val: rzval.RzValue) void {
        self.stack[self.sp] = @bitCast(val);
        self.sp += 1;
    }

    pub fn peek(self: *rzvm) rzval.RzValue {
        return @bitCast(self.stack[self.sp]);
    }
    pub fn pop(self: *rzvm) rzval.RzValue {
        self.sp -= 1;
        return @bitCast(self.stack[self.sp]);
    }
    pub fn printstack(self: *rzvm) void {
        if (self.sp == 0) {
            std.debug.print("__STACK_EMPTY__\n", .{});
            return;
        }
        std.debug.print("___STACK___\n", .{});
        for (self.stack, 0..) |raw, i| {
            const val: rzval.RzValue = @bitCast(raw);

            if (self.sp <= i)
                break;
            switch (val.type_info) {
                rzval.TypeInfo.int => {
                    const int: i48 = @bitCast(val.data);
                    std.debug.print("{}. {:<16} {}\n", .{ i, int, val.type_info });
                },
                rzval.TypeInfo.float => {
                    const trund: u32 = @truncate(val.data);
                    const float: f32 = @bitCast(trund);
                    std.debug.print("{}. {:<16}\n", .{ i, float });
                },
                else => unreachable,
            }
        }
        std.debug.print("___________\n", .{});
    }
};

test "Exit" {
    std.debug.print("1. TEST_EXIT\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    var bytecode = [_]u8{
        @intFromEnum(opcodes.EXIT),
    };
    try vm.run(&bytecode);
    // vm.printstack();
    std.debug.assert(vm.pc == 0);
    std.debug.assert(vm.sp == 0);
}

test "Push int" {
    std.debug.print("2. TEST PUSH\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    var bytecode =
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initInt(1234567890).toBytes() ++
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initInt(-5).toBytes() ++
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initInt(-140737488355328).toBytes() ++
        [_]u8{@intFromEnum(opcodes.EXIT)};
    // for (bytecode) |val| {
    //     std.debug.print("program: {b:0>8}\n", .{val});
    // }

    try vm.run(&bytecode);
    // vm.printstack();
    std.debug.assert(vm.sp == 3);
}

test "Push Pop float" {
    std.debug.print("3. PUSH POP FLOAT\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    var bytecode =
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initFloat(3.141595653589).toBytes() ++
        [_]u8{
            @intFromEnum(opcodes.POP),
        } ++
        [_]u8{@intFromEnum(opcodes.EXIT)};
    // for (bytecode) |val| {
    // std.debug.print("program: {b:0>8}\n", .{val});
    // }

    try vm.run(&bytecode);
    // vm.printstack();
    // std.debug.assert(vm.pc == 0);
    std.debug.assert(vm.sp == 0);
}

test "Adding" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    // integer overflow on loop 3
    const arr1 = [_]i48{ 5, 2, 140737488355327 };
    const arr2 = [_]i48{ 8, -2, 1 };
    for (arr1, arr2, 0..) |i, j, k| {
        var bytecode =
            [_]u8{
                @intFromEnum(opcodes.PUSH),
            } ++ rzval.RzValue.initInt(i).toBytes() ++
            [_]u8{
                @intFromEnum(opcodes.PUSH),
            } ++ rzval.RzValue.initInt(j).toBytes() ++
            [_]u8{
                @intFromEnum(opcodes.ADD),
            } ++
            [_]u8{@intFromEnum(opcodes.EXIT)};
        // for (bytecode, 0..) |val, i| {
        //     std.debug.print("{:<3}: {b:0>8}\n", .{ i, val });
        // }

        try vm.run(&bytecode);
        const ret = vm.pop();
        std.debug.print("k: {}\n", .{k});
        if (k == 2) {
            std.debug.assert(ret.err == 1 and
                @as(rzval.vmerr, @enumFromInt(ret.data)) == rzval.vmerr.ADD_OVERFLOW);
        } else {
            std.debug.print("({} + {}) == {}\n", .{ arr1[k], arr2[k], ret.data });
            std.debug.assert((arr1[k] + arr2[k]) == ret.data);
        }
        vm.reset();
    }
    const arr3 = [_]f32{ 3.14, 4, -0.0, std.math.inf(f32) };
    const arr4 = [_]f32{ 0.1, 0.4, 0.0, 5 };
    for (arr3, arr4, 0..) |i, j, k| {
        var bytecode =
            [_]u8{
                @intFromEnum(opcodes.PUSH),
            } ++ rzval.RzValue.initFloat(i).toBytes() ++
            [_]u8{
                @intFromEnum(opcodes.PUSH),
            } ++ rzval.RzValue.initFloat(j).toBytes() ++
            [_]u8{
                @intFromEnum(opcodes.ADD),
            } ++
            [_]u8{@intFromEnum(opcodes.EXIT)};
        // for (bytecode, 0..) |val, i| {
        //     std.debug.print("{:<3}: {b:0>8}\n", .{ i, val });
        // }

        try vm.run(&bytecode);
        const ret = vm.pop();
        const retdata: f32 = @bitCast(@as(u32, @intCast(ret.data)));
        std.debug.print("({} + {}) == {}\n", .{ arr3[k], arr4[k], retdata });
        std.debug.assert((arr3[k] + arr4[k]) == retdata);
        vm.reset();
    }
    var bytecode =
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initFloat(3.1415).toBytes() ++
        [_]u8{
            @intFromEnum(opcodes.PUSH),
        } ++ rzval.RzValue.initInt(42).toBytes() ++
        [_]u8{
            @intFromEnum(opcodes.ADD),
        } ++
        [_]u8{@intFromEnum(opcodes.EXIT)};

    try vm.run(&bytecode);
    const ret = vm.pop();
    const retdata: f32 = @bitCast(@as(u32, @intCast(ret.data)));
    std.debug.assert((3.1415 + 42.0) == retdata);
}
