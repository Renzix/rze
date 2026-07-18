// opcodes!!!
pub const opcode = enum(u8) {
    invalid = 0,
    exit = 1, // exits the program
    load_reg = 2, // opcode(u8) + loc(u8) + value(u64)
    mov = 5, //
    // math
    add = 6, // opcode(u8) + a(u8) + b(u8) + c(u8) // adds a + b and puts it in reg c
    sub = 7, // subtract
    mul = 8, // multiply
    div = 9, // divide
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
