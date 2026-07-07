const std = @import("std");

pub const GapBuffer = struct {
    bytes: []u8,
    gap_start: usize,
    gap_end: usize,
    buffer_start: usize,
    buffer_end: usize,
    const allocator = std.heap.c_allocator;
    pub const default_capacity: usize = 12;
    pub fn init() GapBuffer {
        return GapBuffer{ .bytes = &.{}, .buffer_start = 0, .buffer_end = 0, .gap_start = 0, .gap_end = 0 };
    }
    pub fn insert_char(self: *GapBuffer, char: u8) !void {
        if ((self.gap_end - self.gap_start) < 4) {
            try self.grow();
        }
        self.bytes[self.gap_start] = char;
        self.gap_start += 1;
    }
    // @TODO(Renzix): Make us able to insert multiple characters at once
    pub fn insert_str(self: *GapBuffer, str: []const u8) !void {
        for (str) |ch| {
            try self.insert_char(ch);
        }
    }
    pub fn grow(self: *GapBuffer) !void {
        const current_cap = self.bytes.len;
        const new_cap = if (current_cap == 0) default_capacity else current_cap + default_capacity;
        self.bytes = try allocator.realloc(self.bytes, new_cap);
        const new_gap_end = self.gap_end + (new_cap - current_cap);
        std.mem.copyBackwards(u8, self.bytes[new_gap_end..new_cap], self.bytes[self.gap_end..current_cap]);
        self.gap_end = new_gap_end;
        self.buffer_end = new_cap;
    }
    // @TODO(Renzix): This is probably stupid and i should make delete remove
    // from the gap_end and backspace removes from gap_start
    pub fn delete(self: *GapBuffer) void {
        self.gap_start -= 1;
    }
    pub fn backspace(self: *GapBuffer) void {
        self.goto(self.gap_start - 1);
        self.delete();
        self.goto(self.gap_start + 1);
    }
    pub fn goto(self: *GapBuffer, loc: usize) void {
        const gap_size = self.gap_end - self.gap_start;
        const normalized_loc = if (loc < self.gap_start)
            loc
        else
            loc + gap_size;
        while (normalized_loc < self.gap_start) {
            self.gap_start -= 1;
            self.gap_end -= 1;
            self.bytes[self.gap_end] = self.bytes[self.gap_start];
        }
        while (normalized_loc > self.gap_end) {
            self.bytes[self.gap_start] = self.bytes[self.gap_end];
            self.gap_start += 1;
            self.gap_end += 1;
        }
    }
    pub fn deinit(self: *GapBuffer) void {
        allocator.free(self.bytes);
    }

    // @TODO(Renzix): Make better
    pub fn debug_print(self: *GapBuffer) void {
        for (self.bytes, 0..) |ch, i| {
            std.debug.print("[", .{});
            if ((i > self.gap_start) and (i < self.gap_end)) {
                std.debug.print("..", .{});
            } else if (i == self.gap_start) {
                std.debug.print("*", .{});
            } else {
                std.debug.print("{c}", .{ch});
            }
            std.debug.print("]", .{});
        }
        std.debug.print("\n", .{});
    }
};

test "Basic Insertion" {
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    try gapbuffer.insert_str("hello my name is renzix");

    const gapbuffer_text = gapbuffer.bytes[0..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("hello my name is renzix", gapbuffer_text);
    try std.testing.expectEqual(@as(usize, 23), gapbuffer.gap_start);
}

test "Goto Selection" {
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    try gapbuffer.insert_str("I am supposed to meake an error here");

    gapbuffer.goto(18);

    const gapbuffer_beginning = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("I am supposed to m", gapbuffer_beginning);
    const gapbuffer_ending = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings("eake an error here", gapbuffer_ending);

    gapbuffer.goto(2);
    const gapbuffer_beginning2 = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("I ", gapbuffer_beginning2);
    const gapbuffer_ending2 = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings("am supposed to meake an error here", gapbuffer_ending2);

    gapbuffer.goto(10);
    const gapbuffer_beginning3 = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("I am suppo", gapbuffer_beginning3);
    const gapbuffer_ending3 = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings("sed to meake an error here", gapbuffer_ending3);
}

test "Goto Insertion" {
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    try gapbuffer.insert_str("Hello World!");
    gapbuffer.goto(5);
    try gapbuffer.insert_str(" Cruel");

    const gapbuffer_beginning = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("Hello Cruel", gapbuffer_beginning);
    const gapbuffer_ending = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings(" World!", gapbuffer_ending);
}

test "Basic Deletion" {
    // inserts some pregenerated random numbers then deletes them
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    const random_numbers = [7]i32{ 9, 2109, 439034, 20, 0, -1, -12342 };

    // i hate this
    var buffer: [10]u8 = undefined; // zig has no itoa :(
    for (random_numbers) |i| {
        const numstr = try std.fmt.bufPrint(&buffer, "{d}", .{i});
        try gapbuffer.insert_str(numstr);
        const gapbuffer_beginning = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
        try std.testing.expectEqualStrings(numstr, gapbuffer_beginning);
        for (0..numstr.len) |_| {
            gapbuffer.delete();
        }
    }
}

test "Goto Deletion" {
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    try gapbuffer.insert_str("The goto selection test wazs supposed toi be gaoto deletion but I didnt");

    gapbuffer.goto(27);
    gapbuffer.delete();
    gapbuffer.goto(40);
    gapbuffer.delete();
    gapbuffer.goto(45);
    gapbuffer.delete();

    const gapbuffer_beginning = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("The goto selection test was supposed to be g", gapbuffer_beginning);
    const gapbuffer_ending = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings("oto deletion but I didnt", gapbuffer_ending);
}

test "Backspace" {
    var gapbuffer = GapBuffer.init();
    defer gapbuffer.deinit();

    try gapbuffer.insert_str("Hello!!!");

    gapbuffer.backspace();
    gapbuffer.backspace();

    const gapbuffer_beginning = gapbuffer.bytes[gapbuffer.buffer_start..gapbuffer.gap_start];
    try std.testing.expectEqualStrings("Hello!", gapbuffer_beginning);
    const gapbuffer_ending = gapbuffer.bytes[gapbuffer.gap_end..gapbuffer.buffer_end];
    try std.testing.expectEqualStrings("", gapbuffer_ending);
}
