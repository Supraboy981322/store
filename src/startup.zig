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
    const mode = std.meta.stringToEnum(
        enum(u2){ get, put, store }, argv0
    ).?;
    sw: switch (mode) {
        inline .get, .put => |w| {
            opts.act = comptime if (w == .get) .get else .put;
            opts.key = itr.next() orelse return error.NotEnoughArgs;
            if (w == .put)
                opts.val = itr.next() orelse return error.NotEnoughArgs;
        },
        .store => {
            const arg = itr.next() orelse return error.NotEnoughArgs;
            const a = std.meta.stringToEnum(
                enum{ path, get, put }, arg
            ) orelse {
                opts.key = arg;
                if (itr.next()) |a| {
                    std.debug.print("unexpected args: |{s}| followed by |{s}|\n", .{arg, a});
                    std.process.exit(1);
                }
                break :sw;
            };
            switch (a) {
                .path =>
                    opts.path = itr.next() orelse return error.MissingArg,
                inline .get, .put => |w| {
                    opts.act = comptime if (w == .get) .get else .put;
                    opts.key = itr.next() orelse return error.NotEnoughArgs;
                    if (w == .put)
                        opts.val = itr.next() orelse return error.NotEnoughArgs;
                },
            }
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
        opts.path = try std.fmt.allocPrint(init.gpa, "{s}/.local/state/store.bin", .{home_dir});
    }
    return opts;
}
