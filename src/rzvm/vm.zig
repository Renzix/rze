const std = @import("std");
const log = @import("std").debug.print;

const rzval = @import("rzvalue.zig").RzValue;
const rzhelper = @import("rzvalue.zig");
const typeinfo = @import("rzvalue.zig").TypeInfo;

const opcode = @import("bytecode.zig").opcode;
const inst = @import("bytecode.zig").instruction;
const RzErr = @import("rzvalue.zig").RzErr;

const Runtime = @import("runtime.zig").Runtime;

const str = @import("datatypes/string.zig");

// @TODO(Renzix): Go through each of these and decide what to keep/remove and
// then restructure what is a error?
const VmErr = error{
    InvalidOpcode,
    IncorrectArgCount,
    StackOverflow,
    CallingUncallable,
    ExpectedFrame,
    ExpectedString,
    IncorrectReturnValueCount,
    InvalidStream,
    TooManyVarArgs,
};

const Process = union(enum) {
    running: std.process.Child,
    exiting: u8,
};

const ExecContent = struct {
    pipe: Pipe,
    pending: std.ArrayList(Process),
};

const Pipe = struct {
    stdin: ?rzval = null,
    stdout: ?rzval = null,
    stderr: ?rzval = null,
};

// @TODO(Renzix): we need to check at LOAD TIME if args.sbx is out of bounds for jmps
// @TODO(Renzix): Dynamic registers/globals/functions

pub const rzvm = struct {
    registers: []u64,
    runtime: *Runtime,
    execcontent: ExecContent,
    pc: u16,
    fp: u16,
    io: std.Io,
    top: u16,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, io: std.Io, rt: *Runtime) rzvm {
        const regs = alloc.alloc(u64, 256) catch @panic("oom");
        @memset(regs, 0);
        return rzvm{
            .registers = regs,
            .runtime = rt,
            .execcontent = .{ .pending = .empty, .pipe = .{} },
            .pc = 0,
            .fp = 0,
            .io = io,
            .top = 0,
            .allocator = alloc,
        };
    }
    pub fn deinit(self: *rzvm) void {
        self.allocator.free(self.registers);
    }

    pub fn reset(self: *rzvm) void {
        @memset(self.registers, 0);
        self.pc = 0;
        self.fp = 0;
        self.top = 0;
        self.execcontent = .{ .pending = .empty, .pipe = .{} };
    }
    pub fn run(self: *rzvm, program: []const inst) VmErr!void {
        self.reset();
        var ins = program[0];
        self.pc = 1;
        vm: switch (ins.op) {
            .exit => {
                return;
            },
            .loadg => {
                const args = ins.args.abx;
                const loc = args.a;
                const index = args.bx;
                const val = self.runtime.variables[index];
                self.loadReg(val, loc);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .storeg => {
                const args = ins.args.abx;
                const loc = args.a;
                const index = args.bx;
                self.runtime.variables[index] = self.peekReg(loc);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .loadc => {
                const args = ins.args.abx;
                const loc = args.a;
                const index = args.bx;
                const val = self.runtime.constants[index];
                self.loadReg(val, loc);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .loadb => {
                const args = ins.args.abx;
                const val = rzval.initInt(@as(i48, args.bx));
                self.loadReg(val, args.a);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .argstart => {
                const args = ins.args.abc;
                const functionregister = args.a;
                self.top = self.fp + functionregister + 1;

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            inline .argvpush, .argcpush => |op| {
                const args = ins.args.abx;
                const index = args.bx;
                const val = switch (op) {
                    .argvpush => self.runtime.variables[index],
                    .argcpush => self.runtime.constants[index],
                    else => unreachable,
                };
                // grow the stack IF it needs it
                self.growStack(self.top + 1) catch return VmErr.StackOverflow;
                self.registers[self.top] = @bitCast(val);
                self.top+=1;

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .mov => {
                const args = ins.args.abc;
                self.registers[args.b+self.fp] = self.registers[args.a+self.fp];

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            // @TODO(Renzix): Collapse add/sub/mul into one comptime value
            .add => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .add);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .sub => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .sub);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .mul => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);

                const c = rzhelper.binOp(a, b, .mul);
                const loc3 = args.c;
                self.loadReg(c, loc3);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            // @TODO(Renzix): Collapse jmp/jz/jnz into one comptime value
            .jmp => {
                const args = ins.args.asbx;
                self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .jz => {
                const args = ins.args.asbx;
                const a = self.peekReg(args.a);
                if ((a.nullable==true) or (a.data==0))
                    self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .jnz => {
                const args = ins.args.asbx;
                const a = self.peekReg(args.a);
                if (!((a.nullable==true) or (a.data==0)))
                    self.pc = @intCast(@as(i32, self.pc) + args.sbx);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .call => {
                const args = ins.args.abc;
                const func = self.peekReg(args.a);
                const varargs = (args.c==0xFF);
                // @TODO(Renzix): Dont ignore args.b (this is # of return values)
                if (func.type_info != typeinfo.function)
                    return VmErr.CallingUncallable;

                const funcindex: usize = func.data;
                if (funcindex >= self.runtime.functions.len)
                    return VmErr.CallingUncallable;
                const proto = self.runtime.functions[funcindex];
                switch (proto.impl) {
                    .bytecode => {
                        const newfp: u16 = self.fp + args.a + 1;
                        if (args.c != proto.argcount)
                            return VmErr.IncorrectArgCount;
                        if ((newfp + proto.impl.bytecode.framesize) > self.registers.len)
                            self.growStack(newfp + proto.impl.bytecode.framesize) catch return VmErr.StackOverflow;

                        self.registers[newfp-1] = rzval.initFrame(self.pc, self.fp).toU64();

                        self.fp = newfp;
                        self.pc = proto.impl.bytecode.startpc;
                    },
                    .exec => {
                        // Starting processes is slow so assume we never go here
                        @branchHint(.cold);
                        // @TODO(Renzix): Make this into a seperate function???
                        // so we dont have to inline this code???
                        if (args.b!=0x01)
                            return VmErr.IncorrectReturnValueCount;
                        var argv: [256][]const u8 = undefined;
                        argv[0] = proto.impl.exec.slice();
                        const base: u16 = self.fp + args.a;
                        const argcount: u16 = if (!varargs) args.c else (self.top - (base + 1));
                        if (argcount + 1 > argv.len) return VmErr.TooManyVarArgs;
                        for (0..argcount) |i| {
                            const param = self.peekReg(args.a + 1 + @as(u8, @intCast(i)));
                            if (param.type_info != .string) {
                                return VmErr.ExpectedString;
                            }
                            const header: *const str.StringHeader = @ptrFromInt(param.data);
                            argv[1+i] = header.slice();
                        }

                        // zig is stupid and i dont know how to do this better?
                        // ig move it to another function
                        const child: ?std.process.Child = blk: {
                            break :blk std.process.spawn(self.io, .{
                            .argv   = argv[0..argcount+1],
                            .stdout = rzhelper.toStdIo(self.execcontent.pipe.stdout),
                            .stdin  = rzhelper.toStdIo(self.execcontent.pipe.stdin),
                            .stderr = rzhelper.toStdIo(self.execcontent.pipe.stderr),
                            }) catch { break :blk null; };
                        };
                        const abc: Process = if (child) |c| .{ .running = c } else .{ .exiting = 127 };

                        self.execcontent.pending.append(self.allocator, abc) catch @panic("oom");
                        const i: i48 = @intCast(self.execcontent.pending.items.len-1);
                        self.loadReg(rzval.initInt(i), args.a);
                    },
                }
                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .resolve => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                std.debug.assert(a.type_info == .string);
                // check if in path???
                const r0 = self.runtime.setExecFunction(a.asStringHeader(), undefined);
                self.loadReg(rzval.initFunction(r0), args.a);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .ret => {
                const args = ins.args.abc;
                if (self.fp == 0) return; // if you return

                const frame: rzval = @bitCast(self.registers[self.fp - 1]);
                if (frame.type_info != .frame)
                    return VmErr.ExpectedFrame;

                for (0..args.b) |i| {
                    self.registers[self.fp - 1 + i] = self.registers[self.fp + args.a + i];
                }

                self.pc = @truncate(frame.data >> 16);
                self.fp = @truncate(frame.data >>  0);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            inline .ltn, .gtn, .gtne,
                   .ltne, .eql, .neq => |op| {
                const args = ins.args.abc;
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

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .setio => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                switch (args.b) {
                    0x00 => self.execcontent.pipe.stdin = a,
                    0x01 => self.execcontent.pipe.stdout = a,
                    0x02 => self.execcontent.pipe.stderr = a,
                    else => return VmErr.InvalidStream,
                }

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .mkpipe => {
                const args = ins.args.abc;

                var fds: [2]i32 = undefined;
                const rc = std.os.linux.pipe2(&fds, .{ .CLOEXEC = true });
                switch (std.posix.errno(rc)) {
                    .SUCCESS => {},
                    else => @panic("pipe failed"),
                }
                self.loadReg(rzval.initFd((@intCast(fds[0]))), args.a);
                self.loadReg(rzval.initFd((@intCast(fds[1]))), args.b);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .pipeclose => {
                const args = ins.args.abc;
                const a = self.peekReg(args.a);
                const b = self.peekReg(args.b);
                std.debug.assert(a.type_info == .fd);
                std.debug.assert(b.type_info == .fd);
                _ = std.os.linux.close(@intCast(a.data));
                _ = std.os.linux.close(@intCast(b.data));

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .wait => {
                const args = ins.args.abc;

                var last_rc: u8 = 0;
                for (self.execcontent.pending.items) |*proc| {
                    last_rc = switch (proc.*) {
                        .exiting => |code| code,
                        .running => |*child| blk: {
                            const term = child.wait(self.io) catch @panic("process panic'd");
                            break :blk switch (term) {
                                .exited => |code| code,
                                .signal => |sig| 128 + @as(u8, @intCast(@intFromEnum(sig))),
                                else => 1
                            };
                        }
                    };
                }
                self.execcontent.pending.clearRetainingCapacity();
                self.loadReg(rzval.initErrCode(last_rc), args.a);

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            .concat => {
                const args = ins.args.abc;
                var totalmem: usize = 0;
                for (args.a..(args.a+args.b)) |index| {
                    const reg = self.peekReg(@as(u8, @intCast(index)));
                    if (reg.type_info == .string) {
                        totalmem += reg.asString().len;
                    } else{
                        log("String!", .{});
                        unreachable;
                        // break; // return rzval.initErr(???);
                    }
                }
                const raw: []u8 = self.allocator.alloc(u8, totalmem) catch @panic("oom");
                var strindex: usize = 0;
                for (args.a..(args.a+args.b)) |regindex| {
                    const reg = self.peekReg(@as(u8, @intCast(regindex)));
                    const s = reg.asString();
                    @memcpy(raw[strindex..strindex+s.len], s[0..s.len]);
                    strindex += s.len;
                }

                const r0 = str.CreateAllocatedStr(raw, self.allocator);
                self.loadReg(rzval.initString(&r0.header), args.c);
                // log("STR: {any}\n",.{self.peekReg(args.c).asString()});

                ins = program[self.pc];
                self.pc += 1;
                continue :vm ins.op;
            },
            else => {
                log("UNKNOWN OPCODE: {}\n", .{ins});
                self.pc += 1; // opcode (u8)
                return VmErr.InvalidOpcode;
            },
        }
    }

    pub fn loadReg(self: *rzvm, val: rzval, loc: u8) void {
        self.registers[self.fp + loc] = @bitCast(val);
    }

    pub fn peekReg(self: *rzvm, loc: u16) rzval {
        return @bitCast(self.registers[self.fp + loc]);
    }

    pub inline fn growStack(self: *rzvm, newsize: u16) !void {
        if (newsize <= self.registers.len) return;
        const MAX: u16 = 65500;
        if (newsize >= MAX) return VmErr.StackOverflow;
        const oldsize = self.registers.len;
        self.registers = self.allocator.realloc(self.registers,
                                           @min(@as(usize, newsize*2), MAX)) catch @panic("oom");
        @memset(self.registers[oldsize..], 0); // might delete, for safety and if i ever use gc???
    }

    pub fn dump(self: rzvm, start: usize, end: usize) void {
        log("\n=== VM STATE DUMP ===\n", .{});
        log("Program Count (PC): {}\n", .{self.pc});
        log("Function Pointer (FP): {}\n", .{self.fp});
        log("=== Registers ===\n", .{});

        for (self.registers[start..end], start..end) |reg, i| {
            log("r{:0>3}: 0x{x:0>016}    ", .{ i, reg });
            if ((i + 1) % 4 == 0) {
                log("\n", .{});
            }
        }

        log("=======================\n\n", .{});
    }
};

test "Exit" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const bytecode = [_]inst{
        inst.exit(),
    };
    try vm.run(&bytecode);
    std.debug.assert(vm.pc == 1);
}

test "load and mov" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 1001;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABC(.mov, 0x00, 0x01, 0),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0).toU64(), vm.registers[1]);
}

test "addition" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 1012;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const r1 = -5;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const r2 = -140737488355328;
    const vr2 = vm.runtime.addConstant(rzval.initInt(r2));
    const r3: f32 = 3.141595653589;
    const vr3 = vm.runtime.addConstant(rzval.initFloat(r3));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABx(.loadc, 0x02, vr2),
        inst.iABx(.loadc, 0x03, vr3),
        inst.iABC(.add, 0x00, 0x01, 0x04),
        inst.iABC(.add, 0x01, 0x02, 0x05),
        inst.iABC(.add, 0x03, 0x03, 0x06),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initFloat(r3 + r3).toU64(), vm.registers[6]);
}

test "subtraction" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 1000;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const r1 = 7;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const r2 = -140737488355328;
    const vr2 = vm.runtime.addConstant(rzval.initInt(r2));
    const r3: f32 = 2.5;
    const vr3 = vm.runtime.addConstant(rzval.initFloat(r3));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABx(.loadc, 0x02, vr2),
        inst.iABx(.loadc, 0x03, vr3),
        inst.iABC(.sub, 0x00, 0x01, 0x04),
        inst.iABC(.sub, 0x01, 0x00, 0x05),
        inst.iABC(.sub, 0x02, 0x01, 0x06),
        inst.iABC(.sub, 0x00, 0x03, 0x07),
        inst.iABC(.sub, 0x03, 0x03, 0x08),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 - r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initInt(r1 - r0).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[6]);
    try std.testing.expectEqual(rzval.initFloat(r0 - r3).toU64(), vm.registers[7]);
    try std.testing.expectEqual(rzval.initFloat(r3 - r3).toU64(), vm.registers[8]);
}

test "multiplication" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 1000;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const r1 = 7;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const r2 = 1 << 24;
    const vr2 = vm.runtime.addConstant(rzval.initInt(r2));
    const r3: f32 = 2.5;
    const vr3 = vm.runtime.addConstant(rzval.initFloat(r3));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABx(.loadc, 0x02, vr2),
        inst.iABx(.loadc, 0x03, vr3),
        inst.iABC(.mul, 0x00, 0x01, 0x04),
        inst.iABC(.mul, 0x02, 0x02, 0x05),
        inst.iABC(.mul, 0x00, 0x03, 0x06),
        inst.iABC(.mul, 0x01, 0x03, 0x07),
        inst.iABC(.mul, 0x03, 0x03, 0x08),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 * r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initErr(RzErr.overflow).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initFloat(r0 * r3).toU64(), vm.registers[6]);
    try std.testing.expectEqual(rzval.initFloat(r1 * r3).toU64(), vm.registers[7]);
    try std.testing.expectEqual(rzval.initFloat(r3 * r3).toU64(), vm.registers[8]);
}

test "jmp, jz, jnz" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 100;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const r1 = 200;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iAsBx(.jmp, undefined, 0x01),
        inst.iABC(.invalid, 0x00, 0x01, 0x01), // this should be skipped
        inst.iABC(.add, 0x00, 0x01, 0x02),
        inst.iAsBx(.jz, 0xFF, 0x01), // should jump next cmd
        inst.iABC(.invalid, 0x00, 0x01, 0x03),
        inst.iAsBx(.jz, 0x00, 0x01), // should not jump next cmd
        inst.iABC(.add, 0x00, 0x01, 0x04),
        inst.iAsBx(.jnz, 0xFF, 0x01), // should not jump next cmd
        inst.iABC(.add, 0x00, 0x01, 0x05),
        inst.iAsBx(.jnz, 0x00, 0x01), // should jump next cmd
        inst.iABC(.invalid, 0x00, 0x01, 0x06),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[2]);
    try std.testing.expectEqual(rzval.initInt(0).toU64(), vm.registers[3]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[4]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[5]);
    try std.testing.expectEqual(rzval.initInt(0).toU64(), vm.registers[6]);
}

test "eql, neq" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = 100;
    const vr0 = vm.runtime.addConstant(rzval.initInt(r0));
    const r1 = 200;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABC(.eql, 0x01, 0x01, undefined),
        inst.iABC(.invalid, 0x00, 0x00, 0x00),
        inst.iABC(.eql, 0x00, 0x01, undefined),
        inst.iABC(.add, 0x00, 0x01, 0x02),
        inst.iABC(.neq, 0x01, 0x01, undefined),
        inst.iABC(.add, 0x00, 0x01, 0x03),
        inst.iABC(.neq, 0x00, 0x01, undefined),
        inst.iABC(.invalid, 0x00, 0x00, 0x00),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[2]);
    try std.testing.expectEqual(rzval.initInt(r0 + r1).toU64(), vm.registers[3]);
}

// @TODO(Renzix): Write test for ltn gtn ltne gtne =)

test "call, ret (bytecode)" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    const r0 = vm.runtime.setFunction(5, 2, 3);
    const vr0 = vm.runtime.addConstant(rzval.initFunction(r0));
    const r1 = 100;
    const vr1 = vm.runtime.addConstant(rzval.initInt(r1));
    const r2 = 200;
    const vr2 = vm.runtime.addConstant(rzval.initInt(r2));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABx(.loadc, 0x02, vr2),
        inst.iABC(.call, 0x00, 0x01, 0x02),
        inst.exit(),
        inst.iABC(.add, 0x00, 0x01, 0x02),
        inst.iABC(.ret, 0x02, 0x01, 0x00),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initInt(r1 + r2).toU64(), vm.registers[0]);
    try std.testing.expectEqual(@as(u16, 0), vm.fp);
}

// requires sh to be present in the shell
test "call, ret (executable)" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);
    var s0 = str.CreateStaticStr("/bin/sh");
    const r0 = vm.runtime.setExecFunction(&s0.header, 2);
    const vr0 = vm.runtime.addConstant(rzval.initFunction(r0));
    const s1 = str.CreateStaticStr("-c");
    const vr1 = vm.runtime.addConstant(rzval.initString(&s1.header));
    const s2 = str.CreateStaticStr("exit 7");
    const vr2 = vm.runtime.addConstant(rzval.initString(&s2.header));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABx(.loadc, 0x02, vr2),
        inst.iABC(.call, 0x00, 0x01, 0x02),
        inst.iABC(.wait, 0x00, undefined, undefined),
        inst.exit(),
    };
    try vm.run(&bytecode);
    try std.testing.expectEqual(rzval.initErrCode(7).toU64(), vm.registers[0]);
}

//@TODO(Renzix): test "setio"

test "concat" {
    var debugallocator: std.heap.DebugAllocator(.{}) =.init;
    const allocator = debugallocator.allocator();
    var rt = Runtime.init(allocator);
    var vm = rzvm.init(allocator, std.testing.io, &rt);
    defer vm.deinit();
    errdefer vm.dump(0, 12);

    var r0 = str.CreateAllocatedStr("Hello my name is", allocator);
    defer str.DestroyAllocatedStr(r0, allocator);
    const vr0 = vm.runtime.addConstant(rzval.initString(&r0.header));
    var r1 = str.CreateStaticStr(" renzix");
    const vr1 = vm.runtime.addConstant(rzval.initString(&r1.header));
    const bytecode = [_]inst{
        inst.iABx(.loadc, 0x00, vr0),
        inst.iABx(.loadc, 0x01, vr1),
        inst.iABC(.concat, 0x00, 0x02, 0x02),
        inst.exit(),
    };

    try vm.run(&bytecode);

    var answer = str.CreateStaticStr("Hello my name is renzix");
    const response: rzval = @bitCast(vm.registers[2]);
    try std.testing.expectEqualStrings(rzval.initString(&answer.header).asString(), response.asString());
}

// @TODO(Renzix): Test var args with argstart and argpush
