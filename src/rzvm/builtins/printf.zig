const rzvm = @import("../vm.zig").rzvm;
const std = @import("std");

// return 1 = general write error
// return 2 = flush error
// return 3 = % parse error
// return 4 = \ expected character

// printf itself https://pubs.opengroup.org/onlinepubs/9699919799/utilities/printf.html
pub fn printf(vm: *rzvm, argv: []const []const u8) u8 {
    var outbuf: [1024]u8 = undefined;
    const fileno: std.Io.File = .stdout(); // @TODO(Renzix): handle pipe
    var file: std.Io.File.Writer = .init(fileno, vm.io, &outbuf);
    const writer = &file.interface;
    var index: usize = 0;
    const format = argv[1];
    var currarg: usize = 2; // for %
    while (index<format.len) {
        switch (format[index]) {
            '%' => { // % --- https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap05.html#tag_05
                index+=1;
                if (index>=format.len) return fail(writer, "printf: %: invalid ch", 3);
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
                switch(format[index]) {
                    's' => {
                        writer.print("{s}", .{argv[currarg]}) catch return 1;
                        currarg+=1;
                    },
                    'c' => {
                        writer.print("{c}", .{argv[currarg][0]}) catch return 1;
                        currarg+=1;
                    },
                    'd', 'i' => {
                        const int = std.fmt.parseInt(i64, argv[currarg], 10) catch fail(writer, "printf: %: failed to parse int", 3);
                        writer.print("{}", .{int}) catch return 1;
                        currarg+=1;
                    },
                    'x' => {
                        const int = parseuint(argv[currarg]) catch fail(writer, "printf: %: failed to parse int", 3);
                        writer.print("{x}", .{int}) catch return 1;
                        currarg+=1;
                    },
                    'X' => {
                        const int = parseuint(argv[currarg]) catch fail(writer, "printf: %: failed to parse int", 3);
                        writer.print("{X}", .{int}) catch return 1;
                        currarg+=1;
                    },
                    'u' => {
                        // -1 is supposed to give 18446744073709551615 :)
                        const uint: u64 = parseuint(argv[currarg]) catch fail(writer, "printf: %: failed to parse uint (too long)", 3);
                        writer.print("{}", .{uint}) catch return 1;
                        currarg+=1;
                    },
                    '%' => {
                        writer.print("%", .{}) catch return 1;
                    },
                    '#' => {
                        // lot of this is not specified
                        writer.print("unimplemented\n", .{}) catch return 3;
                        unreachable;
                    },
                    else => return fail(writer, "printf: %: invalid ch", 3),
                }
            },
            '\\' => {
                index+=1;
                if (index>=format.len) return fail(writer, "printf: \\: tried to \\ when nothing is next", 4);
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
    writer.print("\n", .{}) catch return 1;
    writer.flush() catch return 2;
    return 0;
}

fn fail(writer: *std.Io.Writer, msg: []const u8, ret: u8) u8 {
    writer.print("{s}\n", .{msg}) catch return ret;
    return ret;
}

fn parseuint(str: []const u8) !u64 {
    if (std.fmt.parseInt(i64, str, 0)) |n| return @as(u64, @bitCast(n)) else |err| {
        if (err != error.Overflow) return err;
        return try std.fmt.parseInt(u64, str, 0);
    }
}
