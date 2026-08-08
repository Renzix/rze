const std = @import("std");

const rz = @import("rz");
// const repl = @import("repl.zig");
pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(proc: std.process.Init) !u8 {
    const arena: std.mem.Allocator = proc.arena.allocator();

    const args = try proc.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
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
