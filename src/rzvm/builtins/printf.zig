const rzvm = @import("../vm.zig").rzvm;
const std = @import("std");

// return 1 = general write error
// return 2 = flush error
// return 3 = % parse error
// return 4 = \ expected character

// i probably could have just passed this to c stdlib printf but i thought i might as well
// try to see how it works


// so that i can use a enum with the ascii chars for nicety
const SubConversion = enum(u8) {
    d = 'd',
    i = 'i',
    o = 'o',
    u = 'u',
    x = 'x',
    X = 'X',
    f = 'f',
    F = 'F',
    e = 'e',
    E = 'E',
    g = 'g',
    G = 'G',
    a = 'a',
    A = 'A',
    c = 'c',
    s = 's',
    percent = '%',
};

const SubFlags = packed struct(u8) {
    zero: bool = false,  // 0 modifier (does padding if field width is present)
    alt: bool  = false,  // # modifier (alternate way to view things (depends on type))
    sign: bool = false,  // + modifier (if number include sign)
    space: bool= false,  // ' ' modifier (prepends a space, may be invalid)
    left: bool = false,  // - modifier left justified
    _: u3 = 0,           // reserved
};

const SubErr = error{
    OutOfMemory,
    ParseInt,
    ParseUInt,
    InvalidConversion,
};

const Subsitution = struct {
    flags: SubFlags  = .{},  // modifiers
    field_width: u32 = 0,    // amount of space a field takes up (fills with 0 or spaces), MINIMUM
    precision: ?u32  = null, // amount of bytes depends on type
    conv: SubConversion,     // type to convert to
    chars_parsed: u32 = 0,
    write_buf: [4096]u8 = undefined,
    write_len: u16 = 0,

    pub fn parse(self: *Subsitution, arr: []const u8, index: u32) !void {
        std.debug.assert(arr[index] == '%');
        var i: u32 = index;
        var ch: u8 = '%';
        defer self.chars_parsed = i-index;
        errdefer self.chars_parsed = i-index;
        // flags
        while (true) {
            ch = try getChar(arr, &i);
            switch(ch) {
                '0' => self.flags.zero  = true,
                '#' => self.flags.alt   = true,
                '+' => self.flags.sign  = true,
                ' ' => self.flags.space = true,
                '-' => self.flags.left  = true,
                else => break,
            }
        }
        // field width
        self.write_buf = .{0}**4096;
        self.write_len=0;
        while (true) {
            switch(ch) {
                '0'...'9' => {
                    self.write_buf[self.write_len] = ch;
                    self.write_len += 1;
                },
                else => break,
            }
            ch = try getChar(arr, &i);
        }
        // @TODO(Renzix): parse
        if (self.write_len>0)
            self.field_width = std.fmt.parseInt(u32, self.write_buf[0..self.write_len], 10) catch return SubErr.InvalidConversion;

        // self.field_width = std.enums.fromInt(SubConversion, fwarr) orelse return error.InvalidConversion;

        // precision
        self.write_buf = .{0}**4096;
        self.write_len=0;
        if (arr[i]=='.') {
            _  = try getChar(arr, &i); // eat the .
            ch = try getChar(arr, &i); // get the new input
            while (true) {
                switch(ch) {
                    '0'...'9' => {
                        self.write_buf[self.write_len] = ch;
                        self.write_len += 1;
                    },
                    else => break,
                }
                ch = try getChar(arr, &i);
            }
            // @TODO(Renzix): parse
            if (self.write_len>0)
                self.precision = std.fmt.parseInt(u32, self.write_buf[0..self.write_len], 10) catch return SubErr.InvalidConversion
            else
                self.precision = 0;
        }

        // conversion
        // @TODO(Renzix): parse
        self.conv = std.enums.fromInt(SubConversion, arr[i]) orelse return SubErr.InvalidConversion;
    }

    // afaik only flags left and field width matter here
    fn writeBufString(self: *Subsitution, str: []const u8) void {
        self.field_width = @max(self.field_width, @as(u32, @intCast(str.len)));

        @memset(self.write_buf[0..self.field_width], ' ');
        if (self.flags.left) {
            @memcpy(self.write_buf[0..str.len],str);
        } else {
            @memcpy(self.write_buf[self.field_width-str.len..self.field_width],str);
        }
    }

    // afaik only flags left and field width matter here
    fn writeBufChar(self: *Subsitution, ch: u8) void {
        self.field_width = @max(self.field_width, @as(u32, @intCast(1)));

        @memset(self.write_buf[0..self.field_width], ' ');
        if (self.flags.left) {
            self.write_buf[0]=ch;
        } else {
            self.write_buf[self.field_width-1]=ch;
        }
    }

    fn writeBufInt(self: *Subsitution, intstr: []const u8, signed: Sign) void {
        const sign: ?u8 = blk: {
            switch(signed) {
                .NEGITIVE => break :blk '-',
                .POSITIVE => break :blk '+',
                .NO_SIGN => {
                    if (self.flags.sign) {
                        break :blk '+';
                    } else if (self.flags.space) {
                        break :blk ' ';
                    } else {
                        break :blk null;
                    }
                },
            }
        };

        const signlen: u8 = if(sign!=null) 1 else 0;
        const numlen = intstr.len+signlen;
        self.field_width = @max(self.field_width, @as(u32, @intCast(numlen)));
        const start: usize = if (self.flags.left) 0 else self.field_width-numlen;
        const end: usize = if (self.flags.left) numlen else self.field_width;

        if (self.flags.zero and !self.flags.left and self.precision==null) {
            @memset(self.write_buf[0..self.field_width], '0');
            if (sign) |s| self.write_buf[0] = s;
        } else {
            @memset(self.write_buf[0..self.field_width], ' ');
            if (sign) |s| self.write_buf[start] = s;
        }

        @memcpy(self.write_buf[start+signlen..end],intstr);
    }

    // probably not needed???
    fn parseInt(intstr: []const u8) ?i64 {
        // @TODO(Renzix): need to parse 0x10 as hex (ie 16 decimal), 0b10 as octal (8 decimal)
        // @TODO(Renzix): need better error handling for stuff like "42 " and " 42  " and "  42"
        const int = std.fmt.parseInt(i64, intstr, 10) catch null;
        return int;
    }

    const Sign = enum(u8) {
        NO_SIGN,
        POSITIVE,
        NEGITIVE,
    };
    fn isIntSigned(intstr: []const u8) Sign {
        for(intstr) |ch| {
            switch (ch) {
                ' ' => continue,
                '+' => return Sign.POSITIVE,
                '-' => return Sign.NEGITIVE,
                else => return Sign.NO_SIGN,
            }
        } else return Sign.NO_SIGN;
    }

    // These need to be in this specific order
    // flags below (any flag can be in any order and multiple of them)
    // @TODO(Renzix): 0 modifier (padding)
    // @TODO(Renzix): # modifier (extra functionality)
    // @TODO(Renzix): + modifier (always include sign)
    // @TODO(Renzix): ' ' modifier (prefixes with space)
    // @TODO(Renzix): - modifier (left justified)
    //
    // @TODO(Renzix): Field width
    // @TODO(Renzix): Precision
    //
    // These are the conversion type TODOs
    // @TODO(Renzix): %o
    // @TODO(Renzix): %a/%A
    // @TODO(Renzix): %f/%F
    // @TODO(Renzix): %e/%E
    // @TODO(Renzix): %g/%G
    pub fn write(self: *Subsitution, writer: *std.Io.Writer, _: *std.Io.Writer, arg: ?[]const u8) SubErr!bool {
        const s = if (arg) |a|
            std.mem.trimStart(u8, a, " \t\n\x0b\x0c\r")
        else
            "0";
        switch (self.conv) {
            .s => {
                    self.writeBufString(s);
            },
            .c => {
                    self.writeBufChar(s[0]);
            },
            .d, .i => {
                const int = parseInt(s); // probaby can make "isInt" instead?
                if (int) |_| {
                    const signed: Sign = isIntSigned(s);
                    switch (signed) {
                        .NEGITIVE, .POSITIVE => |sign| self.writeBufInt(s[1..], sign),
                        .NO_SIGN => |sign| self.writeBufInt(s[0..], sign),
                    }
                } else {
                    // write error buf
                    self.writeBufInt("0", .NO_SIGN);
                }
            },
            // .x => {
            //     if (arg) |a| {
            //         const int = parseuint(a) catch return SubErr.ParseInt;
            //         writer.print("{x}", .{int}) catch return SubErr.OutOfMemory;
            //     } else {
            //         writer.print("0", .{}) catch return SubErr.OutOfMemory;
            //     }
            // },
            // .X => {
            //     if (arg) |a| {
            //         const int = parseuint(a) catch return SubErr.ParseInt;
            //         writer.print("{X}", .{int}) catch return SubErr.OutOfMemory;
            //     } else {
            //         writer.print("0", .{}) catch return SubErr.OutOfMemory;
            //     }
            // },
            // .u => {
            //     if (arg) |a| {
            //         // -1 is supposed to give 18446744073709551615 :)
            //         const uint: u64 = parseuint(a) catch return SubErr.ParseUInt;
            //         writer.print("{}", .{uint}) catch return SubErr.OutOfMemory;
            //     } else {
            //         writer.print("0", .{}) catch return SubErr.OutOfMemory;
            //     }
            // },
            // .percent => {
            //     writer.print("%", .{}) catch return SubErr.OutOfMemory;
            //     return false;
            // },
            else => unreachable,
        }
        writer.writeAll(self.write_buf[0..self.field_width]) catch return SubErr.OutOfMemory;
        writer.flush() catch {};
        return true;
    }

    fn parseuint(str: []const u8) !u64 {
        if (std.fmt.parseInt(i64, str, 0)) |n| return @as(u64, @bitCast(n)) else |err| {
            if (err != error.Overflow) return err;
            return try std.fmt.parseInt(u64, str, 0);
        }
    }

    fn getChar(arr: []const u8, index: *u32) !u8 {
        index.* += 1;
        if (index.*>=arr.len)
            return error.UnexpectedEOF; // @TODO(Renzix): better error
        return arr[index.*];
    }
};

// printf itself https://pubs.opengroup.org/onlinepubs/9699919799/utilities/printf.html
pub fn printf(vm: *rzvm, argv: []const []const u8) u8 {
    var outbuf: [1024]u8 = undefined;
    var errbuf: [1024]u8 = undefined;
    const fileno: std.Io.File = .stdout(); // @TODO(Renzix): handle pipe
    const errno: std.Io.File = .stderr();  // @TODO(Renzix): handle pipe
    var file: std.Io.File.Writer = .init(fileno, vm.io, &outbuf);
    const writer = &file.interface;
    var errfile: std.Io.File.Writer = .init(errno, vm.io, &errbuf);
    const errwriter = &errfile.interface;
    var index: u32 = 0;
    const format = argv[1];
    var currarg: usize = 2; // for %
    while (index<format.len) {
        switch (format[index]) {
            '%' => { // % --- https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap05.html#tag_05
                var sub: Subsitution = .{ .conv = .s };
                sub.parse(format, index) catch {
                    fail(errwriter, "printf: %: invalid directive");
                    break;
                };
                if (currarg>=argv.len) {
                    _ = sub.write(writer, errwriter, null) catch fail(errwriter, "printf: %: could not write % value");
                } else {
                    const used_arg = sub.write(writer, errwriter, argv[currarg]) catch blk: {
                        fail(errwriter, "printf: %: could not write % value");
                        break :blk true;
                    };
                    if (used_arg) currarg += 1;
                }
                index += sub.chars_parsed;
            },
            '\\' => {
                index+=1;
                if (index>=format.len) {
                    fail(errwriter, "printf: \\: tried to \\ when nothing is next");
                    return 4;
                }
                const byte: ?u8 = switch (format[index]) {
                    '\\' => '\\',
                    'a' => '\x07',
                    'b' => '\x08',
                    'f' => '\x0C',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'v' => '\x0B',
                    else => null,
                };
                if (byte) |b|
                    writer.print("{c}", .{b}) catch return 1;
            },
            else => writer.print("{c}", .{format[index]}) catch return 1,
        }
        index+=1;
    }
    errwriter.flush() catch return 2;
    writer.flush() catch return 2;
    return 0;
}

fn fail(writer: *std.Io.Writer, msg: []const u8) void {
    writer.print("{s}\n", .{msg}) catch return;
    writer.flush() catch return;
}
