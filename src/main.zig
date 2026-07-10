const std = @import("std");

const rze = @import("rze");
// const repl = @import("repl.zig");

pub fn main(init: std.process.Init) !void {
    // // const arena: std.mem.Allocator = init.arena.allocator();

    // // const args = try init.minimal.args.toSlice(arena);
    // // for (args) |arg| {
    // //     std.log.info("arg: {s}", .{arg});
    // // }
    // // var display = try rze.Display.init();
    // // defer display.deinit();
    // // display.run();
    var myrepl = rze.repl.init(init);
    myrepl.run();
}
