const std = @import("std");
const rzval = @import("rzvalue.zig");

// opcodes!!!
pub const opcodes = enum(u8) {
    INVALID = 0,
    EXIT = 1, // exits the program
    LOAD_REG = 2, // Loads a Register
    // POP = 3, // grabs the last value on the stack and deletes it
    // DUP = 4, // duplicate last stack value
    MOV = 5, // Moves one register to another
    ADD = 6, // addition
    SUB = 7, // subtract
    MUL = 8, // multiply
    DIV = 9, // divide
    // Comparison
    EQL = 10, // equal
    NEQ = 11, // not equal
    LTN = 12, // less than
    GTN = 13, // greater than
    NOT = 14, // not
    // Control Flow
    JMP = 15, // jump to stack loc
    JNZ = 16, // jump if not 0
    CALL = 17, // jump to function
    RET = 18, // returns from function
};

const vmerror = error{
    INVALID_OPCODE,
};

pub const rzvm = struct {
    registers: [256]u64,
    fp: u16,
    pc: u16,
    pub fn init() rzvm {
        return rzvm{
            .pc = 0,
            .fp = 0,
            .registers = comptime ([_]u64{0} ** 256),
        };
    }
    pub fn reset(self: *rzvm) void {
        self.fp = 0;
        self.pc = 0;
    }
    pub inline fn run(self: *rzvm, program: []u8) vmerror!void {
        self.pc = 0;
        while (true) {
            const code: opcodes = @enumFromInt(program[self.pc]);
            switch (code) {
                opcodes.EXIT => {
                    // std.debug.print("EXIT\n", .{});
                    // std.debug.print("{}", .{self.registers[0x01]});
                    break;
                },
                opcodes.LOAD_REG => {
                    // determine how many bytes
                    // const val = std.mem.bytesToValue(rzval.RzValue, program[self.pc + 1 .. self.pc + 9]);
                    const loc = program[self.pc + 1];
                    const ptr = &program[self.pc + 2];
                    const val = @as(*align(1) const rzval.RzValue, @ptrCast(ptr)).*;
                    self.load_reg(val, loc);
                    self.pc += 10; // opcode(u8) + loc(u8) + value(u64)
                },
                opcodes.ADD => {
                    const loc1 = program[self.pc + 1];
                    const loc2 = program[self.pc + 2];
                    var var1 = self.peek_reg(loc1);
                    var var2 = self.peek_reg(loc2);
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
                    } else {
                        unreachable;
                    }
                    self.pc += 3; // opcode(u8) + loc1(u8) + loc2(u8)
                },
                else => {
                    std.debug.print("UNKNOWN OPCODE: {}\n", .{program[self.pc]});
                    self.pc += 1; // opcode (u8)
                    return vmerror.INVALID_OPCODE;
                },
            }
        }
    }
    pub fn load_reg(self: *rzvm, val: rzval.RzValue, loc: u8) void {
        self.registers[loc] = @bitCast(val);
    }

    pub fn peek_reg(self: *rzvm, loc: u8) rzval.RzValue {
        const ptr = &self.registers[loc];
        return @as(*align(1) const rzval.RzValue, @ptrCast(ptr)).*;
    }

    pub fn dump(self: *rzvm) void {
        std.debug.print("\n=== [VM STATE DUMP] ===\n", .{});
        std.debug.print("Program Count (PC): {}\n", .{self.pc});
        std.debug.print("Function Pointer (FP): {}\n", .{self.fp});
        std.debug.print("--- Registers ---\n", .{});

        for (self.registers, 0..) |reg, i| {
            const raw_val = @as(u64, @bitCast(reg));
            std.debug.print("r{:0>3}: 0x{x:0>016}    ", .{ i, raw_val });
            if ((i + 1) % 4 == 0) {
                std.debug.print("\n", .{});
            }
        }

        std.debug.print("=======================\n\n", .{});
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
}

test "load int" {
    std.debug.print("2. TEST LOAD_REG\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    var bytecode =
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x00 } ++ rzval.RzValue.initInt(1012).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x01 } ++ rzval.RzValue.initInt(-5).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x02 } ++ rzval.RzValue.initInt(-140737488355328).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x03 } ++ rzval.RzValue.initFloat(3.141595653589).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.ADD), 0x00, 0x01 } ++
        [_]u8{@intFromEnum(opcodes.EXIT)};
    // for (bytecode) |val| {
    //     std.debug.print("program: {b:0>8}\n", .{val});
    // }

    try vm.run(&bytecode);
    // vm.printstack();
    vm.dump();
}

// test "Adding" {
//     var vm = rzvm.init();
//     // defer rzvm.deinit();
//     // integer overflow on loop 3
//     const arr1 = [_]i48{ 5, 2, 140737488355327 };
//     const arr2 = [_]i48{ 8, -2, 1 };
//     for (arr1, arr2, 0..) |i, j, k| {
//         var bytecode =
//             [_]u8{
//                 @intFromEnum(opcodes.PUSH),
//             } ++ rzval.RzValue.initInt(i).toBytes() ++
//             [_]u8{
//                 @intFromEnum(opcodes.PUSH),
//             } ++ rzval.RzValue.initInt(j).toBytes() ++
//             [_]u8{
//                 @intFromEnum(opcodes.ADD),
//             } ++
//             [_]u8{@intFromEnum(opcodes.EXIT)};
//         // for (bytecode, 0..) |val, i| {
//         //     std.debug.print("{:<3}: {b:0>8}\n", .{ i, val });
//         // }

//         try vm.run(&bytecode);
//         const ret = vm.pop();
//         std.debug.print("k: {}\n", .{k});
//         if (k == 2) {
//             std.debug.assert(ret.err == 1 and
//                 @as(rzval.vmerr, @enumFromInt(ret.data)) == rzval.vmerr.ADD_OVERFLOW);
//         } else {
//             std.debug.print("({} + {}) == {}\n", .{ arr1[k], arr2[k], ret.data });
//             std.debug.assert((arr1[k] + arr2[k]) == ret.data);
//         }
//         vm.reset();
//     }
//     const arr3 = [_]f32{ 3.14, 4, -0.0, std.math.inf(f32) };
//     const arr4 = [_]f32{ 0.1, 0.4, 0.0, 5 };
//     for (arr3, arr4, 0..) |i, j, k| {
//         var bytecode =
//             [_]u8{
//                 @intFromEnum(opcodes.PUSH),
//             } ++ rzval.RzValue.initFloat(i).toBytes() ++
//             [_]u8{
//                 @intFromEnum(opcodes.PUSH),
//             } ++ rzval.RzValue.initFloat(j).toBytes() ++
//             [_]u8{
//                 @intFromEnum(opcodes.ADD),
//             } ++
//             [_]u8{@intFromEnum(opcodes.EXIT)};
//         // for (bytecode, 0..) |val, i| {
//         //     std.debug.print("{:<3}: {b:0>8}\n", .{ i, val });
//         // }

//         try vm.run(&bytecode);
//         const ret = vm.pop();
//         const retdata: f32 = @bitCast(@as(u32, @intCast(ret.data)));
//         std.debug.print("({} + {}) == {}\n", .{ arr3[k], arr4[k], retdata });
//         std.debug.assert((arr3[k] + arr4[k]) == retdata);
//         vm.reset();
//     }
//     var bytecode =
//         [_]u8{
//             @intFromEnum(opcodes.PUSH),
//         } ++ rzval.RzValue.initFloat(3.1415).toBytes() ++
//         [_]u8{
//             @intFromEnum(opcodes.PUSH),
//         } ++ rzval.RzValue.initInt(42).toBytes() ++
//         [_]u8{
//             @intFromEnum(opcodes.ADD),
//         } ++
//         [_]u8{@intFromEnum(opcodes.EXIT)};

//     try vm.run(&bytecode);
//     const ret = vm.pop();
//     const retdata: f32 = @bitCast(@as(u32, @intCast(ret.data)));
//     std.debug.assert((3.1415 + 42.0) == retdata);
// }
