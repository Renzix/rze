const std = @import("std");
const log = @import("std").debug.print;

const rzval = @import("rzvalue.zig").RzValue;
const rzhelper = @import("rzvalue.zig");
const typeinfo = @import("rzvalue.zig").TypeInfo;

const opcode = @import("bytecode.zig").opcode;
const instruction = @import("bytecode.zig").instruction;
const VmErr = @import("rzvalue.zig").VmErr;

const runtime = @import("runtime.zig").runtime;

const FatalErr = error{
    InvalidOpcode,
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
    pub fn run(self: *rzvm, program: []const instruction) FatalErr!void {
        self.pc = 0;
        while (true) {
            const code: opcode = program[self.pc].op;
            switch (code) {
                opcode.exit => {
                    break;
                },
                opcode.loadg => {
                    defer self.pc += 1;
                    const args = program[self.pc].args.abx;
                    const loc = args.a;
                    const index = args.bx;
                    const val = runtime.global[index];
                    self.loadReg(val, loc);
                },
                opcode.loadb => {
                    defer self.pc += 1; // opcode(u8) + loc(u8) + value(u16)
                    const args = program[self.pc].args.abx;
                    const loc = args.a;
                    const data = args.bx;
                    const val = rzval.initInt(@as(i48, data));
                    self.loadReg(val, loc);
                },
                opcode.mov => {
                    defer self.pc += 1; // opcode(u8) + loc1(u8) + loc2(u8)
                    const args = program[self.pc].args.abc;
                    const loc1 = args.a;
                    const loc2 = args.b;
                    self.registers[loc2] = self.registers[loc1];
                },
                opcode.add => {
                    defer self.pc += 1; // opcode(u8) + loc(u8) + loc(u8) + loc(u8)
                    const args = program[self.pc].args.abc;
                    const a = self.peekReg(args.a);
                    const b = self.peekReg(args.b);

                    const c = rzhelper.binOp(a, b, .add);
                    const loc3 = args.c;
                    self.loadReg(c, loc3);
                },
                // opcode.sub => {
                //     defer self.pc += 1; // opcode(u8) + loc(u8) + loc(u8) + loc(u8)
                //     const loc1 = program[self.pc + 1];
                //     const loc2 = program[self.pc + 2];
                //     const loc3 = program[self.pc + 3];
                //     const a = self.peekReg(loc1);
                //     const b = self.peekReg(loc2);

                //     const c = rzhelper.binOp(a, b, .sub);
                //     self.loadReg(c, loc3);
                // },
                // opcode.mul => {
                //     defer self.pc += 1; // opcode(u8) + loc(u8) + loc(u8) + loc(u8)
                //     const loc1 = program[self.pc + 1];
                //     const loc2 = program[self.pc + 2];
                //     const loc3 = program[self.pc + 3];
                //     const a = self.peekReg(loc1);
                //     const b = self.peekReg(loc2);

                //     const c = rzhelper.binOp(a, b, .mul);
                //     self.loadReg(c, loc3);
                // },

                else => {
                    log("UNKNOWN OPCODE: {}\n", .{program[self.pc]});
                    self.pc += 1; // opcode (u8)
                    return FatalErr.InvalidOpcode;
                },
            }
        }
    }
    pub fn loadReg(self: *rzvm, val: rzval, loc: u8) void {
        self.registers[loc] = @bitCast(val);
    }

    pub fn peekReg(self: *rzvm, loc: u8) rzval {
        return @bitCast(self.registers[loc]);
    }

    pub fn dump(self: rzvm) void {
        log("\n=== VM STATE DUMP ===\n", .{});
        log("Program Count (PC): {}\n", .{self.pc});
        log("Function Pointer (FP): {}\n", .{self.fp});
        log("=== Registers ===\n", .{});

        for (self.registers, 0..) |reg, i| {
            log("r{:0>3}: 0x{x:0>016}    ", .{ i, reg });
            if ((i + 1) % 4 == 0) {
                log("\n", .{});
            }
        }

        log("=======================\n\n", .{});
    }
};

test "Exit" {
    log("1. TEST exit\n", .{});
    var vm = rzvm.init();
    errdefer vm.dump();
    // defer rzvm.deinit();
    const bytecode = [_]instruction{
        instruction.iABC(.exit, 0, 0, 0),
    };
    try vm.run(&bytecode);
    std.debug.assert(vm.pc == 0);
}

test "load and mov" {
    log("2. TEST mov\n", .{});
    var vm = rzvm.init();
    errdefer vm.dump();
    const r0 = 1001;
    const myconst = runtime.setVariable("Test", rzval.initInt(r0));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, myconst),
        instruction.iABC(.mov, 0x00, 0x01, 0),
        instruction.iABC(.exit, 0, 0, 0),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0).toU64(), vm.registers[1]);
}

// test "addition" {
//     log("3. TEST add\n", .{});
//     var vm = rzvm.init();
//     errdefer vm.dump();
//     // defer rzvm.deinit();
//     const r0 = 1012;
//     const r1 = -5;
//     const r2 = -140737488355328;
//     const r3: f32 = 3.141595653589;
//     const bytecode =
//         [_]u8{ @intFromEnum(opcode.load), 0x00 } ++ rzval.initInt(r0).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x01 } ++ rzval.initInt(r1).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x02 } ++ rzval.initInt(r2).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x03 } ++ rzval.initFloat(r3).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.add), 0x00, 0x01, 0x04 } ++
//         [_]u8{ @intFromEnum(opcode.add), 0x01, 0x02, 0x05 } ++
//         [_]u8{ @intFromEnum(opcode.add), 0x03, 0x03, 0x06 } ++
//         [_]u8{ @intFromEnum(opcode.exit)};
//     try vm.run(&bytecode);
//     try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[4]);
//     try std.testing.expectEqual(rzval.initErr(VmErr.overflow).toU64(), vm.registers[5]);
//     try std.testing.expectEqual(rzval.initFloat(r3 + r3).toU64(), vm.registers[6]);
// }

// test "subtraction" {
//     log("4. TEST sub\n", .{});
//     var vm = rzvm.init();
//     errdefer vm.dump();
//     // defer rzvm.deinit();
//     const r0 = 1000;
//     const r1 = 7;
//     const r2 = -140737488355328;
//     const r3: f32 = 2.5;
//     const bytecode =
//         [_]u8{ @intFromEnum(opcode.load), 0x00 } ++ rzval.initInt(r0).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x01 } ++ rzval.initInt(r1).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x02 } ++ rzval.initInt(r2).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x03 } ++ rzval.initFloat(r3).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.sub), 0x00, 0x01, 0x04 } ++
//         [_]u8{ @intFromEnum(opcode.sub), 0x01, 0x00, 0x05 } ++
//         [_]u8{ @intFromEnum(opcode.sub), 0x02, 0x01, 0x06 } ++
//         [_]u8{ @intFromEnum(opcode.sub), 0x00, 0x03, 0x07 } ++
//         [_]u8{ @intFromEnum(opcode.sub), 0x03, 0x03, 0x08 } ++
//         [_]u8{ @intFromEnum(opcode.exit)};
//     try vm.run(&bytecode);
//     try std.testing.expectEqual(rzval.initInt(r0 - r1).toU64(), vm.registers[4]);
//     try std.testing.expectEqual(rzval.initInt(r1 - r0).toU64(), vm.registers[5]);
//     try std.testing.expectEqual(rzval.initErr(VmErr.overflow).toU64(), vm.registers[6]);
//     try std.testing.expectEqual(rzval.initFloat(r0 - r3).toU64(), vm.registers[7]);
//     try std.testing.expectEqual(rzval.initFloat(r3 - r3).toU64(), vm.registers[8]);
// }

// test "multiplication" {
//     log("5. TEST mul\n", .{});
//     var vm = rzvm.init();
//     // defer rzvm.deinit();
//     const r0 = 1000;
//     const r1 = 7;
//     const r2 = 1 << 24;
//     const r3: f32 = 2.5;
//     const bytecode =
//         [_]u8{ @intFromEnum(opcode.load), 0x00 } ++ rzval.initInt(r0).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x01 } ++ rzval.initInt(r1).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x02 } ++ rzval.initInt(r2).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x03 } ++ rzval.initFloat(r3).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.mul), 0x00, 0x01, 0x04 } ++
//         [_]u8{ @intFromEnum(opcode.mul), 0x02, 0x02, 0x05 } ++
//         [_]u8{ @intFromEnum(opcode.mul), 0x00, 0x03, 0x06 } ++
//         [_]u8{ @intFromEnum(opcode.mul), 0x01, 0x03, 0x07 } ++
//         [_]u8{ @intFromEnum(opcode.mul), 0x03, 0x03, 0x08 } ++
//         [_]u8{ @intFromEnum(opcode.exit)};
//     try vm.run(&bytecode);
//     try std.testing.expectEqual(rzval.initInt(r0 * r1).toU64(), vm.registers[4]);
//     try std.testing.expectEqual(rzval.initErr(VmErr.overflow).toU64(), vm.registers[5]);
//     try std.testing.expectEqual(rzval.initFloat(r0 * r3).toU64(), vm.registers[6]);
//     try std.testing.expectEqual(rzval.initFloat(r1 * r3).toU64(), vm.registers[7]);
//     try std.testing.expectEqual(rzval.initFloat(r3 * r3).toU64(), vm.registers[8]);
// }

// test "jmp" {
//     log("6. TEST jmp\n", .{});
//     var vm = rzvm.init();
//     // defer rzvm.deinit();
//     const r0 = 100;
//     const r1 = 200;
//     const r2 = 300;
//     const bytecode =
//         [_]u8{ @intFromEnum(opcode.load), 0x00 } ++ rzval.initInt(r0).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x01 } ++ rzval.initInt(r1).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.load), 0x02 } ++ rzval.initInt(r2).toBytes() ++
//         [_]u8{ @intFromEnum(opcode.add), 0x01, 0x01, 0x04 } ++
//         [_]u8{ @intFromEnum(opcode.jmp), 0x04 } ++
//         [_]u8{ @intFromEnum(opcode.exit)};
//     try vm.run(&bytecode);
//     try std.testing.expectEqual(rzval.initInt(r0 * r1).toU64(), vm.registers[4]);
// }
