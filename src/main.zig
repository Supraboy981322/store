const std = @import("std");
pub const Opts = struct {
    path:?[]const u8 = null,
    key:?[]const u8 = null,
    val:?[]const u8 = null,
    act:enum{ get, put } = .get,

    pub fn deinit(self:*Opts, alloc:std.mem.Allocator) void {
        for ([_]?[]const u8{
            self.path,
            //self.key,
            //self.val,
        }) |thing|
            if (thing) |t| alloc.free(t);
    }
};

pub fn main(init:std.process.Init) !u8 {
    var stdout_fi = std.Io.File.stdout();
    var stdout_buf:[1024]u8 = undefined;
    var stdout_wr = stdout_fi.writer(init.io, &stdout_buf);
    const stdout = &stdout_wr.interface;

    var opts:Opts = determine_opts(init) catch |e| return err_out(e);
    defer opts.deinit(init.gpa);

    var file = try std.Io.Dir.openFileAbsolute(init.io, opts.path.?, .{ .mode = .read_write });
    defer file.close(init.io);

    switch (opts.act) {
        .get => {
            const val = try get_val(init.gpa, init.io, file, opts.key.?) orelse {
                std.debug.print("key not found: |{s}|\n", .{opts.key.?});
                return 1;
            };
            defer init.gpa.free(val);
            try stdout.writeAll(val);
            try stdout.flush();
        },
        .put => {
            if (try get_val(init.gpa, init.io, file, opts.key.?)) |_| @panic("TODO: overwrite existing data");
            try put_val(init.io, file,opts.key.?, opts.val.?);
        },
    }
    return 0;
}

pub fn err_out(err:anyerror) u8 {
    std.debug.print("{t}\n", .{err});
    return 1;
}

pub fn wrap(thing:anyerror!u8) !?u8 {
    if (thing) |t|
        return t
    else |e|
        if (e == error.EndOfStream)
            return null
        else
            return e;
}

pub fn get_val(alloc:std.mem.Allocator, io:std.Io, file:std.Io.File, key:[]const u8) !?[]const u8 {
    var buf:[1024]u8 = undefined;
    var useless_reader = file.reader(io, &buf);
    const reader = &useless_reader.interface;
    var val:?[]const u8 = null;

    var n:usize = 0;
    while (try wrap(reader.takeByte())) |b| {
        if (b == 0) {
            defer n = 0;
            const k = try reader.take(n);
            if (std.mem.eql(u8, k, key)) {
                var len:usize = 0;
                while (try wrap(reader.takeByte())) |c| {
                    if (c == 0) break;
                    len += c;
                }
                val = try alloc.dupe(u8, try reader.take(len));
                break;
            }
            continue;
        }
        n += b;
    }
    return val;
}

pub fn put_val(io:std.Io, file:std.Io.File, key:[]const u8, val:[]const u8) !void {

    var buf:[1024]u8 = undefined;
    var useless_writer = file.writer(io, &buf);
    try useless_writer.seekTo(try file.length(io));
    const writer = &useless_writer.interface;

    var n:usize = key.len;
    while (n > 255) : (n -= 255)
        try writer.writeAll(@constCast(&[_]u8{255}));
    try writer.writeAll(@constCast(&[_]u8{@intCast(n)}));
    if (n > 0) try writer.writeAll(@constCast(&[_]u8{0}));
    try writer.flush();
    try writer.writeAll(key);
    try writer.flush();

    n = val.len;
    while (n > 255) : (n -= 255)
        try writer.writeAll(@constCast(&[_]u8{255}));
    try writer.writeAll(@constCast(&[_]u8{@intCast(n)}));
    if (n > 0) try writer.writeAll(@constCast(&[_]u8{0}));
    try writer.flush();
    try writer.writeAll(val);
    try writer.flush();
}

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
