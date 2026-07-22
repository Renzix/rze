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
    argstart = 23, // start a variadic arguments function
    argpush = 24, // push a variable onto var args
    argexpand = 25, // expand var specifically for unquoted shell variables (pushes multiple args)
    // misc
    setio = 21, // opcode(u8) + reg of fd(u8) + stream(u8) + unused(u8)
    concat = 22, // opcode(u8) + start reg(u8) + reg count(u8) + reg of result(u8)

};
