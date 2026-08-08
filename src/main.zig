const std = @import("std");

const rz = @import("rz");
// const repl = @import("repl.zig");
pub const std_options: std.Options = .{
    .log_level = .info,
};

const Flags = struct {
    job: u8
};

pub fn main(proc: std.process.Init) !u8 {
    const arena: std.mem.Allocator = proc.arena.allocator();

    // parse stuff
    var flags: Flags = .{ .job = 'z' };
    const args = try proc.minimal.args.toSlice(arena);
    const command = std.fs.path.basename(args[0]);
    if (std.mem.startsWith(u8, command,"rz")) {
        if (command.len>2) {
            flags.job = args[0][2];
        } else {
            flags.job = switch (args[1][0]) {
                'x', 'l', 'e' => |ch| ch,
                else => @panic("unknown tool"),
            };
        }
    }
    else {
        // @TODO(Renzix): print warning or assume the next arg is the command? ?
        return 1;
    }
    // // var display = try rze.Display.init();
    // // defer display.deinit();
    // // display.run();
    const interactive = (std.Io.File.stdin().isTty(proc.io) catch false) and
        (std.Io.File.stderr().isTty(proc.io) catch false);

    if (interactive) {
        var repl = rz.repl.init(proc);
        return repl.run();
    } else {
        var script = rz.script.init(proc);
        return script.run(null);
    }
}
