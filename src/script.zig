const std = @import("std");
const print = @import("std").debug.print;

const p = @import("rzx/parser.zig");
const c = @import("rzx/compiler.zig");
const v = @import("rzvm/vm.zig");
const Runtime  = @import("rzvm/runtime.zig").Runtime;

pub const Script = struct {
    code: [10240]u8,
    code_len: usize,
    proc: std.process.Init,
    allocator: std.mem.Allocator,
    parser: p.Parser,
    compiler: c.Compiler,
    vm: v.rzvm,

    pub fn init(proc: std.process.Init) Script {
        var debug_alloc: std.heap.DebugAllocator(.{}) =.init;

        var self = Script{
            .code = std.mem.zeroes([10240]u8),
            .code_len = 0,
            .proc = proc,
            .allocator = debug_alloc.allocator(),
            // .allocator = std.heap.c_allocator,
            .parser = undefined,
            .compiler = undefined,
            .vm = undefined,
        };

        var runtime = Runtime.init(self.allocator);
        runtime.setEnv(proc.environ_map);
        self.parser = p.Parser.init(self.allocator);
        self.compiler = c.Compiler.init(self.allocator, &runtime);
        self.vm = v.rzvm.init(self.allocator, self.proc.io, &runtime);

        return self;
    }

    pub fn run(self: *Script, file: ?[]const u8) u8 {
        // read file
        const fileno = blk: {
            if (file) |f| {
                break :blk std.Io.Dir.cwd().openFile(self.proc.io, f, .{}) catch { return 127; };
            } else {
                break :blk std.Io.File.stdin();
            }
        };
        var buf: [4096]u8 = undefined;
        var stream = fileno.readerStreaming(self.proc.io, &buf);
        const prog = stream.interface.allocRemaining(self.allocator, .limited(1 << 20)) catch |err| {
            print("Error opening file {any}", .{err});
            return 1;
        };
        // defer self.proc.gpa.free(val);
        // self.code_len = self.reader.readSliceAll(self.code[0..]) catch 0;

        const ast = self.parser.run(prog) catch |err| {
            // @TODO(Renzix): Move all this terminal stuff to a seperate file and probably write a
            // smaller version for the repl specifically
            print("\x1b[91m\x1b[1m--------- PARSER ERROR --------\n", .{});
            print("error: {t}\n", .{err});
            switch (err) {
                error.SyntaxError => {
                    const code       = self.parser.code;
                    const pos        = self.parser.diag.pos;
                    const code_start = if (std.mem.lastIndexOfScalar(u8, code[0..pos], '\n')) |n| n + 1 else 0;
                    const code_end   = std.mem.indexOfScalarPos(u8, code, pos, '\n') orelse code.len;
                    const code_str   = code[code_start..code_end];
                    const column     = pos - code_start;
                    const lineno     = std.mem.count(u8, code[0..code_start], "\n") + 1;
                    print("line:  {}\n", .{lineno});
                    print("code:  {s}\n", .{code_str});
                    print("       ", .{});
                    for (code_str[0..column]) |col| {
                        print("{c}", .{@as(u8, if (col == '\t') '\t' else ' ')});
                    }
                    print("^\n", .{});
                },
                error.Unimplemented => {
                    print("Send patches\n", .{});
                },
                else => {},
            }
            print("-------------------------------\n\x1b[0m", .{});
            return 1;
        };

        const bytecode = self.compiler.run(ast.?);

        _ = self.vm.run(bytecode.items) catch {
            self.vm.dump(0, 12);
            @panic("AAAAAHHHH");
        };

        // print("{s}\n", .{prog});
        return 0;
    }
};
