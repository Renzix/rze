//
// Instructions are heavily inspired by lua and luajit
//
// Every instruction is 32 bits, the first 8 bits are the opcode
//
// There are currently two ways to call a opcode (similar to lua)
// iABC has three 8 bit arguments, useful for stuff like add/mul
// iABx has one 8 bit argument and one 16 bit argument, useful if you want
// to act on a single register
//
const TypeInfo = @import("rzvalue.zig").TypeInfo;

pub const instruction = packed struct(u32) {
    op: opcode,
    args: packed union {
        abc: packed struct(u24) {
            a: u8,
            b: u8,
            c: u8,
        },
        abx: packed struct(u24) {
            a: u8,
            bx: u16,
        },
        asbx: packed struct(u24) {
            a: u8,
            sbx: i16,
        },
    },
    pub fn iABC(op: opcode, a: u8, b: u8, c: u8) instruction {
        return .{ .op = op, .args = .{ .abc = .{ .a = a, .b = b, .c = c } } };
    }
    pub fn iABx(op: opcode, a: u8, bx: u16) instruction {
        return .{ .op = op, .args = .{ .abx = .{ .a = a, .bx = bx } } };
    }
    pub fn iAsBx(op: opcode, a: u8, sbx: i16) instruction {
        return .{ .op = op, .args = .{ .asbx = .{ .a = a, .sbx = sbx } } };
    }
    pub fn resolve(reg: u8, typ: TypeInfo) instruction {
        return .{ .op = .resolve, .args = .{ .abc = .{ .a = reg, .b = @intFromEnum(typ), .c = undefined } } };
    }
    pub fn exit() instruction {
        return .{ .op = .exit, .args = .{ .abc = .{ .a = undefined, .b = undefined, .c = undefined } } };
    }
};

// opcodes!!!
pub const opcode = enum(u8) {
    invalid = 0,
    exit = 1, // exits the program
    loadg = 2, // opcode(u8) + reg(u8) + index(u16)
    loadc = 3, // opcode(u8) + reg(u8) + ???
    loadb = 4, // opcode(u8) + reg(u8) + value(u16) // always sets int
    storeg = 28, // opcode(u8) + reg(u8) + index(u16)
    mov  = 5, // opcode(u8) + from(u8) + to(u8)
    // math
    add  = 6, // opcode(u8) + rega(u8) + regb(u8) + regc(u8)
    sub  = 7, // opcode(u8) + rega(u8) + regb(u8) + regc(u8)
    mul  = 8, // opcode(u8) + rega(u8) + regb(u8) + regc(u8)
    div  = 9, // unimplemented
    // comparison
    eql = 10, // opcode(u8) + rega(u8) + regb(u8)
    neq = 11, // opcode(u8) + rega(u8) + regb(u8)
    ltn = 12, // opcode(u8) + rega(u8) + regb(u8)
    gtn = 13, // opcode(u8) + rega(u8) + regb(u8)
    ltne = 14, // opcode(u8) + rega(u8) + regb(u8)
    gtne = 15, // opcode(u8) + rega(u8) + regb(u8)
    // control flow
    jmp = 16, // opcode(u8) + undefined(u8) + amount(u16)
    jz = 17, // jump if not 0
    jnz = 18, // jump if 0
    call = 19, // opcode(u8) + reg for funtion ptr(u8) + return count(u8) + argcount(u8)
    ret = 20, // returns from function
    // var args
    argstart = 21, // start a variadic arguments function
    argvpush = 22, // push a variable onto var args
    argcpush = 23, // push a variable onto var args
    argexpand = 24, // expand var specifically for unquoted shell variables (pushes multiple args)
    // misc
    setio = 25, // opcode(u8) + reg of fd(u8) + stream(u8) + unused(u8)
    concat = 26, // opcode(u8) + start reg(u8) + reg count(u8) + reg of result(u8)
    resolve = 27, // opcode(u8) + reg(u8) + type(u8) + unused(u8)

};

const std = @import("std");
const log = @import("std").log.debug;

// helper function
pub fn dump(bytecode: std.ArrayList(instruction)) void {
    for (bytecode.items) |ins| {
        switch (ins.op) {
            .loadg, .loadc, .storeg => log(".{s:<10} r{} var[{}]", .{@tagName(ins.op), ins.args.abx.a, ins.args.abx.bx}),
            .concat => {
                log(".{s:<10} {}-{} res{}", .{@tagName(ins.op), ins.args.abc.a, ins.args.abc.a+ins.args.abc.b, ins.args.abc.c});
            },
            .resolve => {
                const t: TypeInfo = @enumFromInt(ins.args.abc.b);
                log(".{s:<10} r{} {}", .{@tagName(ins.op), ins.args.abc.a, t});
            },
            .call => {
                log(".{s:<10} r{} ret{} arg{}", .{@tagName(ins.op), ins.args.abc.a, ins.args.abc.b, ins.args.abc.c});
            },
            .exit => log(".{s:<10}", .{@tagName(ins.op)}),
            else => log(".{s:<10} 0b{b:0>8} 0b{b:0>8} 0b{b:0>8}",
                        .{@tagName(ins.op), ins.args.abc.a, ins.args.abc.b, ins.args.abc.c}),

        }
    }
}
