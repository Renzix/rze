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
        return .{ .op = op, .args = .{ .abx = .{ .a = a, .sbx = sbx } } };
    }
    pub fn exit() instruction {
        return .{ .op = .exit, .args = .{ .abc = .{ .a = 0, .b = 0, .c = 0 } } };
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
    eql = 10, // equal
    neq = 11, // not equal
    ltn = 12, // less than
    gtn = 13, // greater than
    not = 14, // not
    // control flow
    jmp = 15, // jump to stack loc
    jnz = 16, // jump if not 0
    call = 17, // jump to function
    ret = 18, // returns from function
};
