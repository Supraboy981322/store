const std = @import("std");
const types = @import("types.zig");

const Opts = types.Opts;

pub fn determine_opts(init:std.process.Init) !Opts {
    var opts:Opts = .{};
    var itr = init.minimal.args.iterate();
    const argv0 = blk: {
        const foo = itr.next().?;
        if (std.mem.cutScalarLast(u8, foo, '/')) |thing| break :blk thing[1];
        break :blk std.mem.absorbSentinel(foo)[0..foo.len];
    };
    const Mode = enum(u2){ get, put, store };
    var mode = std.meta.stringToEnum(Mode, argv0) orelse .store;
    sw: switch (mode) {
        .get, .put => {},
        .store => {
            const arg = itr.next() orelse return error.NotEnoughArgs;
            const a = std.meta.stringToEnum(
                enum{ path, get, put }, arg
            ) orelse {
                opts.key = arg;
                opts.act = .get;
                if (itr.next()) |a| {
                    std.debug.print("unexpected args: |{s}| followed by |{s}|\n", .{arg, a});
                    std.process.exit(1);
                }
                break :sw;
            };
            if (a == .path) @panic("TODO: path arg");
            mode = std.meta.stringToEnum(Mode, @tagName(a)).?; //less likely to break
        }
    }
    switch (mode) {
        .store => {},
        inline .get, .put => |w| {
            opts.act = comptime if (w == .get) .get else .put;
            opts.key = itr.next() orelse return error.NotEnoughArgs;
            if (comptime w == .put)
                opts.val = itr.next() orelse return error.NotEnoughArgs;
        }
    }
    if (opts.path == null) {
        const home_dir = blk: {
            const env = init.minimal.environ.block.slice;
            for (env) |thing| if (thing) |c_set| {
                var i:usize = 0;
                const set = std.mem.span(c_set);
                for (set) |b| {
                    if (b == '=') break else i += 1;
                }
                if (std.mem.eql(u8, "HOME", set[0..i])) break :blk set[i+1..];
            };
            unreachable; // $HOME not in env vars
        };
        opts.path = try std.mem.join(init.gpa, "/", &.{ home_dir, ".local", "state", "store.bin" });
    }
    return opts;
}
