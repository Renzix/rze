const std = @import("std");

const rz = @import("rz");
// const repl = @import("repl.zig");
pub const std_options: std.Options = .{
    .log_level = .info,
};

const Flags = struct {
    job: u8, // replace with enum of commands
};

pub fn main(proc: std.process.Init) !u8 {
    const arena: std.mem.Allocator = proc.arena.allocator();

    // parse stuff
    var flags: Flags = .{ .job = 'z' };
    const args = try proc.minimal.args.toSlice(arena);
    const command = std.fs.path.basename(args[0]);
    var argpos: usize = 0;
    if (std.mem.startsWith(u8, command,"rz")) {
        if (command.len>2) {
            flags.job = args[0][2];
        } else {
            argpos += 1;
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
    argpos += 1;

    // parse --flags

    // // var display = try rze.Display.init();
    // // defer display.deinit();
    // // display.run();
    var interactive = (std.Io.File.stdin().isTty(proc.io) catch false) and
        (std.Io.File.stderr().isTty(proc.io) catch false);
    if (args.len > argpos) interactive=false;

    // handle flags to open editor or shell or lisp interpreter or compiler
    if (interactive) {
        var repl = rz.repl.init(proc);
        return repl.run();
    } else {
        var script = rz.script.init(proc);
        const file = if (args.len > argpos) args[argpos] else null;
        return script.run(file);
    }
}
