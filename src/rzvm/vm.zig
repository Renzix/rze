const std = @import("std");
const log = @import("std").debug.print;

const rzval = @import("rzvalue.zig").RzValue;
const rzhelper = @import("rzvalue.zig");
const typeinfo = @import("rzvalue.zig").TypeInfo;

const opcode = @import("bytecode.zig").opcode;
const instruction = @import("bytecode.zig").instruction;
const RzErr = @import("rzvalue.zig").RzErr;

const Runtime = @import("runtime.zig").Runtime;

const VmErr = error{
    InvalidOpcode,
    Arity,
    StackOverflow,
    CallingUncallable,
    ExpectedFrame,
};

// @TODO(Renzix): we need to check at LOAD TIME if args.sbx is out of bounds for jmps
// @TODO(Renzix): Dynamic registers/globals/functions

pub const rzvm = struct {
    registers: [1024]u64,
    runtime: Runtime,
    pc: u16,
    fp: u16,
    pub fn init() rzvm {
        const rt = Runtime.init();
        return rzvm{
            .registers = comptime ([_]u64{0} ** 1024),
            .runtime = rt,
            .pc = 0,
            .fp = 0,
        };
    }
    pub fn reset(self: *rzvm) void {
        self.pc = 0;
        self.fp = 0;
    }
    pub fn run(self: *rzvm, program: []const instruction) VmErr!void {
        var inst = program[0];
        self.pc = 1;
        vm: switch (inst.op) {
            .exit => {
                return;
            },
            .loadg => {
                const args = inst.args.abx;
                const loc = args.a;
                const index = args.bx;
                const val = self.runtime.global[index];
                self.loadReg(val, loc);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .loadb => {
                const args = inst.args.abx;
                const val = rzval.initInt(@as(i48, args.bx));
                self.loadReg(val, args.a);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .mov => {
                const args = inst.args.abc;
                self.registers[args.b+self.fp] = self.registers[args.a+self.fp];

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            // @TODO(Renzix): Collapse add/sub/mul into one comptime value
            .add => {
                const args = inst.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .add);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .sub => {
                const args = inst.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .sub);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .mul => {
                const args = inst.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .mul);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            // @TODO(Renzix): Collapse jmp/jz/jnz into one comptime value
            .jmp => {
                const args = inst.args.asbx;
                self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .jz => {
                const args = inst.args.asbx;
                const a = self.peekReg(args.a);
                if ((a.nullable==true) or (a.data==0))
                    self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .jnz => {
                const args = inst.args.asbx;
                const a = self.peekReg(args.a);
                if (!((a.nullable==true) or (a.data==0)))
                    self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .call => {
                const args = inst.args.abc;
                const func = self.peekReg(args.a);
                // @TODO(Renzix): Dont ignore args.b (this is # of return values)
                if (func.type_info != typeinfo.function)
                    return VmErr.CallingUncallable;
                const funcindex: usize = func.data;
                if (funcindex >= self.runtime.functions.len)
                    return VmErr.CallingUncallable;
                const proto = self.runtime.functions[funcindex];

                const newfp: u16 = self.fp + args.a + 1;

                if (args.c != proto.argcount)
                    return VmErr.Arity;
                if ((newfp + proto.framesize) > self.registers.len)
                    return VmErr.StackOverflow;

                self.registers[newfp-1] = rzval.initFrame(self.pc, self.fp).toU64();

                self.fp = newfp;
                self.pc = proto.startpc;

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            .ret => {
                const args = inst.args.abc;
                if (self.fp == 0) return; // if you return

                const frame: rzval = @bitCast(self.registers[self.fp - 1]);
                if (frame.type_info != .frame)
                    return VmErr.ExpectedFrame;

                for (0..args.b) |i| {
                    self.registers[self.fp - 1 + i] = self.registers[self.fp + args.a + i];
                }

                self.pc = @truncate(frame.data >> 16);
                self.fp = @truncate(frame.data >>  0);

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            inline .ltn, .gtn, .gtne,
                   .ltne, .eql, .neq => |op| {
                const args = inst.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                // compile time func call
                const myop = switch (op) {
                    .ltn => .lessthan, .gtn => .greaterthan,
                    .gtne => .greaterthaneql, .ltne => .lessthaneql,
                    .eql => .equal, .neq => .notequal,
                    else => unreachable,
                };
                const ok = rzhelper.compare(a, b, myop);
                if (ok) {
                    self.pc += 1;
                }

                inst = program[self.pc];
                self.pc += 1;
                continue :vm inst.op;
            },
            else => {
                log("UNKNOWN OPCODE: {}\n", .{inst});
                self.pc += 1; // opcode (u8)
                return VmErr.InvalidOpcode;
            },
        }
    }
    pub fn loadReg(self: *rzvm, val: rzval, loc: u8) void {
        self.registers[self.fp + loc] = @bitCast(val);
    }

    pub fn peekReg(self: *rzvm, loc: u8) rzval {
        return @bitCast(self.registers[self.fp + loc]);
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
    var vm = rzvm.init();
    errdefer vm.dump();
    // defer rzvm.deinit();
    const bytecode = [_]instruction{
        instruction.exit(),
    };
    try vm.run(&bytecode);
    std.debug.assert(vm.pc == 1);
}

test "load and mov" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = 1001;
    const vr0 = vm.runtime.setVariable("Test", rzval.initInt(r0));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABC(.mov, 0x00, 0x01, 0),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0).toU64(), vm.registers[1]);
}

test "addition" {
    var vm = rzvm.init();
    errdefer vm.dump();
    // defer rzvm.deinit();
    const r0 = 1012;
    const vr0 = vm.runtime.setVariable("Var0", rzval.initInt(r0));
    const r1 = -5;
    const vr1 = vm.runtime.setVariable("Var1", rzval.initInt(r1));
    const r2 = -140737488355328;
    const vr2 = vm.runtime.setVariable("Var2", rzval.initInt(r2));
    const r3: f32 = 3.141595653589;
    const vr3 = vm.runtime.setVariable("Var3", rzval.initFloat(r3));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iABx(.loadg, 0x02, vr2),
        instruction.iABx(.loadg, 0x03, vr3),
        instruction.iABC(.add, 0x00, 0x01, 0x04),
        instruction.iABC(.add, 0x01, 0x02, 0x05),
        instruction.iABC(.add, 0x03, 0x03, 0x06),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initFloat(r3 + r3).toU64(), vm.registers[6]);
}

test "subtraction" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = 1000;
    const vr0 = vm.runtime.setVariable("Var0", rzval.initInt(r0));
    const r1 = 7;
    const vr1 = vm.runtime.setVariable("Var1", rzval.initInt(r1));
    const r2 = -140737488355328;
    const vr2 = vm.runtime.setVariable("Var2", rzval.initInt(r2));
    const r3: f32 = 2.5;
    const vr3 = vm.runtime.setVariable("Var3", rzval.initFloat(r3));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iABx(.loadg, 0x02, vr2),
        instruction.iABx(.loadg, 0x03, vr3),
        instruction.iABC(.sub, 0x00, 0x01, 0x04),
        instruction.iABC(.sub, 0x01, 0x00, 0x05),
        instruction.iABC(.sub, 0x02, 0x01, 0x06),
        instruction.iABC(.sub, 0x00, 0x03, 0x07),
        instruction.iABC(.sub, 0x03, 0x03, 0x08),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 - r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initInt(r1 - r0).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[6]);
    try std.testing.expectEqual(rzval.initFloat(r0 - r3).toU64(), vm.registers[7]);
    try std.testing.expectEqual(rzval.initFloat(r3 - r3).toU64(), vm.registers[8]);
}

test "multiplication" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = 1000;
    const vr0 = vm.runtime.setVariable("Var0", rzval.initInt(r0));
    const r1 = 7;
    const vr1 = vm.runtime.setVariable("Var1", rzval.initInt(r1));
    const r2 = 1 << 24;
    const vr2 = vm.runtime.setVariable("Var2", rzval.initInt(r2));
    const r3: f32 = 2.5;
    const vr3 = vm.runtime.setVariable("Var3", rzval.initFloat(r3));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iABx(.loadg, 0x02, vr2),
        instruction.iABx(.loadg, 0x03, vr3),
        instruction.iABC(.mul, 0x00, 0x01, 0x04),
        instruction.iABC(.mul, 0x02, 0x02, 0x05),
        instruction.iABC(.mul, 0x00, 0x03, 0x06),
        instruction.iABC(.mul, 0x01, 0x03, 0x07),
        instruction.iABC(.mul, 0x03, 0x03, 0x08),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 * r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initFloat(r0 * r3).toU64(), vm.registers[6]);
    try std.testing.expectEqual(rzval.initFloat(r1 * r3).toU64(), vm.registers[7]);
    try std.testing.expectEqual(rzval.initFloat(r3 * r3).toU64(), vm.registers[8]);
}

test "jmp, jz, jnz" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = 100;
    const vr0 = vm.runtime.setVariable("Var0", rzval.initInt(r0));
    const r1 = 200;
    const vr1 = vm.runtime.setVariable("Var1", rzval.initInt(r1));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iAsBx(.jmp, undefined, 0x01),
        instruction.iABC(.invalid, 0x00, 0x01, 0x01), // this should be skipped
        instruction.iABC(.add, 0x00, 0x01, 0x02),
        instruction.iAsBx(.jz, 0xFF, 0x01), // should jump next cmd
        instruction.iABC(.invalid, 0x00, 0x01, 0x03),
        instruction.iAsBx(.jz, 0x00, 0x01), // should not jump next cmd
        instruction.iABC(.add, 0x00, 0x01, 0x04),
        instruction.iAsBx(.jnz, 0xFF, 0x01), // should not jump next cmd
        instruction.iABC(.add, 0x00, 0x01, 0x05),
        instruction.iAsBx(.jnz, 0x00, 0x01), // should jump next cmd
        instruction.iABC(.invalid, 0x00, 0x01, 0x06),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[2]);
    try std.testing.expectEqual(rzval.initInt(0).toU64(), vm.registers[3]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initInt(0).toU64(), vm.registers[6]);
}

test "eql, neq" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = 100;
    const vr0 = vm.runtime.setVariable("Var0", rzval.initInt(r0));
    const r1 = 200;
    const vr1 = vm.runtime.setVariable("Var1", rzval.initInt(r1));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iABC(.eql, 0x01, 0x01, undefined),
        instruction.iABC(.invalid, 0x00, 0x00, 0x00),
        instruction.iABC(.eql, 0x00, 0x01, undefined),
        instruction.iABC(.add, 0x00, 0x01, 0x02),
        instruction.iABC(.neq, 0x01, 0x01, undefined),
        instruction.iABC(.add, 0x00, 0x01, 0x03),
        instruction.iABC(.neq, 0x00, 0x01, undefined),
        instruction.iABC(.invalid, 0x00, 0x00, 0x00),
        instruction.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[2]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[3]);
}

// @TODO(Renzix): Write test for ltn gtn ltne gtne =)

test "call, ret" {
    var vm = rzvm.init();
    // defer rzvm.deinit();
    errdefer vm.dump();
    const r0 = vm.runtime.setFunction(5, 2, 3, 0);
    const vr0 = vm.runtime.setVariable("Func0", rzval.initFunction(r0));
    const r1 = 100;
    const vr1 = vm.runtime.setVariable("Var0", rzval.initInt(r1));
    const r2 = 200;
    const vr2 = vm.runtime.setVariable("Var1", rzval.initInt(r2));
    const bytecode = [_]instruction{
        instruction.iABx(.loadg, 0x00, vr0),
        instruction.iABx(.loadg, 0x01, vr1),
        instruction.iABx(.loadg, 0x02, vr2),
        instruction.iABC(.call, 0x00, 0x01, 0x02),
        instruction.exit(),
        instruction.iABC(.add, 0x00, 0x01, 0x02),
        instruction.iABC(.ret, 0x02, 0x01, 0x00),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r1 + r2).toU64(), vm.registers[0]);
    try std.testing.expectEqual(@as(u16, 0), vm.fp);
}
