const std = @import("std");
const types = @import("types.zig");

const print = std.debug.print;
const exit = std.process.exit;
const stringToEnum = std.meta.stringToEnum;
const cutScalarLast = std.mem.cutScalarLast;
const absorbSentinel = std.mem.absorbSentinel;
const span = std.mem.span;
const join = std.mem.join;
const eql = std.mem.eql;

const Opts = types.Opts;

pub fn determine_opts(init:std.process.Init) !Opts {
    var opts:Opts = .{};
    var itr = init.minimal.args.iterate();
    const argv0 = blk: {
        const foo = itr.next().?;
        if (cutScalarLast(u8, foo, '/')) |thing| break :blk thing[1];
        break :blk absorbSentinel(foo)[0..foo.len];
    };
    const Mode = enum(u3){ get, put, store, dump, del };
    var mode = stringToEnum(Mode, argv0) orelse .store;
    sw: switch (mode) {
        .get, .put, .dump, .del => {},
        .store => {
            const arg = itr.next() orelse return error.NotEnoughArgs;
            const Args = enum{ path, get, put, dump, del };
            var a = stringToEnum(
                Args, arg
            ) orelse {
                opts.key = arg;
                opts.act = .get;
                if (itr.next()) |a| {
                    print("unexpected args: |{s}| followed by |{s}|\n", .{arg, a});
                    exit(1);
                }
                break :sw;
            };
            if (a == .path) {
                opts.path = try init.gpa.dupe(
                    u8, itr.next() orelse return error.NotEnoughArgs
                );
                a = stringToEnum(
                    Args, itr.next() orelse return error.NotEnoughArgs
                ) orelse return error.ModeExpected;
                if (a == .path) return error.MissplacedArg;
            }
            mode = stringToEnum(Mode, @tagName(a)).?; //less likely to break
        }
    }
    switch (mode) {
        .store => {},
        .dump => opts.act = .dump,
        inline .get, .put, .del => |w| {
            opts.act = comptime if (w == .get) .get else if (w == .del) .del else .put;
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
                const set = span(c_set);
                for (set) |b| {
                    if (b == '=') break else i += 1;
                }
                if (eql(u8, "HOME", set[0..i])) break :blk set[i+1..];
            };
            unreachable; // $HOME not in env vars
        };
        opts.path = try join(
            init.gpa, "/", &.{ home_dir, ".local", "state", "store.bin" }
        );
    }
    return opts;
}
