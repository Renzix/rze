const std = @import("std");
const log = @import("std").debug.print;

const rzval = @import("rzvalue.zig").RzValue;
const typeinfo = @import("rzvalue.zig").TypeInfo;

const opcodes = @import("bytecode.zig").opcodes;
const VmErr = @import("rzvalue.zig").VmErr;
const GcBit = @import("rzvalue.zig").GcBit;

const fatalerr = error{
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
    pub inline fn run(self: *rzvm, program: []u8) fatalerr!void {
        self.pc = 0;
        while (true) {
            const code: opcodes = @enumFromInt(program[self.pc]);
            switch (code) {
                opcodes.EXIT => {
                    break;
                },
                opcodes.LOAD_REG => {
                    defer self.pc += (1+1+8); // opcode(u8) + loc(u8) + value(u64)
                    const loc = program[self.pc + 1];
                    const ptr = &program[self.pc + 2];
                    const val = @as(*align(1) const rzval, @ptrCast(ptr)).*;
                    self.loadReg(val, loc);
                },
                opcodes.ADD => {
                    defer self.pc += 4; // opcode(u8) + loc(u8) + loc(u8) + loc(u8)
                    const loc1 = program[self.pc + 1];
                    const loc2 = program[self.pc + 2];
                    const loc3 = program[self.pc + 3];
                    var a = self.peekReg(loc1);
                    var b = self.peekReg(loc2);

                    const c = blk: {
                        if (a.nullable or b.nullable) {
                            break :blk rzval.initErr(VmErr.add_null);
                        }
                        break :blk switch (a.type_info) {
                            typeinfo.int => switch (b.type_info) {
                                typeinfo.int => {
                                    const val, const overflow = @addWithOverflow(@as(i48, @bitCast(b.data)), @as(i48, @bitCast(a.data)));
                                    if (overflow == 0)
                                        break :blk rzval.initInt(val)
                                    else
                                        break :blk rzval.initErr(VmErr.add_overflow);
                                },
                                typeinfo.float => {
                                    break :blk rzval.initFloat(a.asF32()+b.asF32());
                                },
                                else => rzval.initErr(VmErr.add_error),
                            },
                            typeinfo.float => switch (b.type_info) {
                                typeinfo.int => {
                                    break :blk rzval.initFloat(a.asF32()+b.asF32());
                                },
                                typeinfo.float => {
                                    break :blk rzval.initFloat(a.asF32()+b.asF32());
                                },
                                else => rzval.initErr(VmErr.add_error),
                            },
                            else => rzval.initErr(VmErr.add_error),
                        };
                    };
                    self.loadReg(c, loc3);
                },
                else => {
                    defer self.pc += 1; // opcode (u8)
                    log("UNKNOWN OPCODE: {}\n", .{program[self.pc]});
                    return fatalerr.INVALID_OPCODE;
                },
            }
        }
    }
    pub fn loadReg(self: *rzvm, val: rzval, loc: u8) void {
        self.registers[loc] = @bitCast(val);
    }

    pub fn peekReg(self: *rzvm, loc: u8) rzval {
        const ptr = &self.registers[loc];
        return @as(*align(1) const rzval, @ptrCast(ptr)).*;
    }

    pub fn dump(self: *rzvm) void {
        log("\n=== VM STATE DUMP ===\n", .{});
        log("Program Count (PC): {}\n", .{self.pc});
        log("Function Pointer (FP): {}\n", .{self.fp});
        log("=== Registers ===\n", .{});

        for (self.registers, 0..) |reg, i| {
            const raw_val = @as(u64, @bitCast(reg));
            log("r{:0>3}: 0x{x:0>016}    ", .{ i, raw_val });
            if ((i + 1) % 4 == 0) {
                log("\n", .{});
            }
        }

        log("=======================\n\n", .{});
    }
};

test "Exit" {
    log("1. TEST_EXIT\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    var bytecode = [_]u8{
        @intFromEnum(opcodes.EXIT),
    };
    try vm.run(&bytecode);
    // vm.printstack();
    std.debug.assert(vm.pc == 0);
}

test "LOAD_REG + ADD" {
    log("2. TEST LOAD_REG\n", .{});
    var vm = rzvm.init();
    // defer rzvm.deinit();
    const val0 = 1012;
    const val1 = -5;
    const val2 = -140737488355328;
    const val3: f32 = 3.141595653589;
    var bytecode =
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x00 } ++ rzval.initInt(val0).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x01 } ++ rzval.initInt(val1).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x02 } ++ rzval.initInt(val2).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.LOAD_REG), 0x03 } ++ rzval.initFloat(val3).toBytes() ++
        [_]u8{ @intFromEnum(opcodes.ADD), 0x00, 0x01, 0x04 } ++
        [_]u8{ @intFromEnum(opcodes.ADD), 0x01, 0x02, 0x05 } ++
        [_]u8{ @intFromEnum(opcodes.ADD), 0x03, 0x03, 0x06 } ++
        [_]u8{@intFromEnum(opcodes.EXIT)};
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(val0 + val1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initErr(VmErr.add_overflow).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initFloat(val3 + val3).toU64(), vm.registers[6]);
    // vm.dump();
}
