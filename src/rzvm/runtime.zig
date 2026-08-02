const std = @import("std");
const RzValue = @import("rzvalue.zig").RzValue;
const RzErr = @import("rzvalue.zig").RzErr;
const str = @import("datatypes/string.zig");
const StringHeader = @import("datatypes/string.zig").StringHeader;
const log = @import("std").debug.print;
const builtins = @import("builtins/builtins.zig");

pub const Proto = struct {
    argcount: u8,
    impl: union(enum) {
        bytecode: struct {
            startpc: u16,
            framesize: u8,
        },
        native: *const builtins.NativeFn,
        exec: *StringHeader,
    },
};

pub const Process = union(enum) {
    running: std.process.Child,
    exited: ?u8,
};

pub const Job = struct {
    id: u16,
    job: std.ArrayList(Process),
};

// move arrays to std.Arraylist or some manual datastructure???
pub const Runtime = struct {
    stdinfd: u8,
    stdoutfd: u8,
    stderrfd: u8,
    fi: u16,
    gi: u16,
    ci: u16,
    constants: [10000]RzValue,
    string_constant_symbol: std.StringHashMap(u16),
    variables: [std.math.maxInt(u16)+1]RzValue,
    symbol: std.StringHashMap(u16),
    jobs: std.ArrayList(Job),
    functions: [1024]Proto, // replace with closures???
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Runtime {
        var self = Runtime{
            .stdinfd = 0,
            .stdoutfd = 0,
            .stderrfd = 0,
            .fi = 0,
            .gi = 0,
            .ci = 0,
            .constants = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** 10000,
            .string_constant_symbol = .init(allocator),
            .variables = [_]RzValue{RzValue.initErr(RzErr.name_not_found)} ** (std.math.maxInt(u16) + 1),
            .symbol = .init(allocator),
            .functions = undefined,
            .jobs = .empty,
            .allocator = allocator,
        };

        // some init stuff
        self.stdinfd = @intCast(self.addConstant(RzValue.initFd(0)));
        self.stdoutfd = @intCast(self.addConstant(RzValue.initFd(1)));
        self.stderrfd = @intCast(self.addConstant(RzValue.initFd(2)));

        _ = self.addGlobal("!", RzValue.initErrCode(0));
        _ = self.addGlobal("?", RzValue.initErrCode(0));

        return self;
    }

    pub fn setEnv(self: *Runtime, map: *std.process.Environ.Map) void {
        // environment variables
        for (map.keys(), map.values()) |k, v| {
            var r0 = str.CreateAllocatedStr(v, self.allocator);
            _ = self.addGlobal(k, RzValue.initString(&r0.header));
        }
    }

    pub fn addGlobal(self: *Runtime, name: []const u8, value: RzValue) u16 {
        if (self.symbol.get(name)) |gi| {
            return gi;
        }
        self.symbol.put(name, self.gi) catch @panic("oom, no space for symbol");
        self.variables[self.gi] = value;
        self.gi += 1;
        return self.gi-1;
    }

    pub fn getGlobal(self: *Runtime, name: []const u8) ?RzValue {
        if (self.symbol.get(name)) |loc| {
            return self.variables[loc];
        }
        return null;
    }

    pub fn getGlobalIndex(self: *Runtime, loc: u16) RzValue {
        return self.variables[loc];
    }

    pub fn findGlobal(self: *Runtime, name: []const u8) ?u16 {
        if (self.symbol.get(name)) |loc| {
            return loc;
        }
        return null;
    }

    pub fn reserveGlobal(self: *Runtime, name: []const u8) u16 {
        if (self.symbol.get(name)) |gi| {
            return gi;
        }
        // take ownership of the allocation
        const key = self.allocator.dupe(u8, name) catch @panic("oom, no space for symbol");
        self.symbol.put(key, self.gi) catch @panic("oom, no space for symbol");
        self.gi += 1;
        return self.gi-1;
    }

    // for compiler use ONLY. so we dont dedup strings
    pub fn addStringConstant(self: *Runtime, value: RzValue) u16 {
        if (self.string_constant_symbol.get(value.asString())) |ci| {
            return ci;
        }
        self.string_constant_symbol.put(value.asString(), self.ci) catch @panic("oom, no space for symbol");
        return self.addConstant(value);
    }

    pub fn addConstant(self: *Runtime, value: RzValue) u16 {
        if (self.ci >= 10000) @panic("Too many constants");
        self.constants[self.ci] = value;
        self.ci += 1;
        return self.ci-1;
    }

    pub fn getConstant(self: *Runtime, loc: u16) RzValue {
        return self.constants[loc];
    }

    // debug
    pub fn printConstants(self: *Runtime) void {
        // prints a table of constants
        for(0..self.ci) |i| {
            const r = self.constants[i];
            var tempbuffer: [1000]u8 = std.mem.zeroes([1000]u8);
            r.debugString(&tempbuffer);
            // log("Type: {any}\n", .{r.type_info});
            // log("Ptr: {any}\n", .{r.ptr});
            // log("Mutable: {any}\n", .{r.mutable});
            // log("Nullable: {any}\n", .{r.nullable});
            // log("gc: {any}\n", .{r.gc});
            log("{}: {s}\n", .{i, tempbuffer});
        }
    }

    // debug
    pub fn printConstant(self: *Runtime, loc: u16) void {
        const r = self.constants[loc];
        var tempbuffer: [1000]u8 = std.mem.zeroes([1000]u8);
        r.debugString(&tempbuffer);
        log("Type: {any}\n", .{r.type_info});
        log("Ptr: {any}\n", .{r.ptr});
        log("Mutable: {any}\n", .{r.mutable});
        log("Nullable: {any}\n", .{r.nullable});
        log("gc: {any}\n", .{r.gc});
        log("data: {s}\n", .{tempbuffer});
    }

    pub fn findBuiltin(self: *Runtime, name: []const u8) ?u16 {
        if (builtins.table.get(name)) |func| {
            self.functions[self.fi] = .{
                .impl = .{ .native =  func },
                .argcount = undefined,
            };
            self.fi += 1;
            return self.fi-1;
        }
        return null;
    }

    pub fn setFunction(self: *Runtime, startpc: u16, argcount: u8, framesize: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .bytecode = .{ .startpc = startpc, .framesize = framesize} },
            .argcount = argcount,
        };
        self.fi += 1;
        return self.fi-1;
    }

    pub fn setExecFunction(self: *Runtime, bin: *StringHeader, argcount: u8) u16 {
        self.functions[self.fi] = .{
            .impl = .{ .exec = bin },
            .argcount = argcount,
        };
        self.fi += 1;
        return self.fi-1;
    }

    pub fn addJob(self: *Runtime, procs: std.ArrayList(Process)) u16 {
        const j: Job = .{ .id = @intCast(self.jobs.items.len), .job = procs };
        self.jobs.append(self.allocator, j) catch @panic("oom");
        return j.id;
    }

    pub fn waitForJob(self: *Runtime, io: std.io, id: u16) void {
        var last_rc: u8 = 0;
        for (self.jobs[id].job.items) |*proc| {
            last_rc = switch (proc.*) {
                .exited => |code| if (code) |c| c else 127,
                .running => |*child| blk: {
                    const term = child.wait(io) catch @panic("process panic'd");
                    break :blk switch (term) {
                        .exited => |code| code,
                        .signal => |sig| 128 + @as(u8, @intCast(@intFromEnum(sig))),
                        else => 1
                    };
                }
            };
        }
        return last_rc;
    }

    pub fn waitForAllJobs(self: *Runtime, io: std.io) void {
        for (self.jobs.items) |js| {
            for (js.job.items) |*proc| {
                switch (proc.*) {
                    .exited => {},
                    .running => |*child| child.wait(io) catch @panic("process panic'd"),
                }
            }
        }
    }
};
