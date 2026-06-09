const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");
const startup = @import("startup.zig");
const store = @import("store.zig");

pub fn main(init:std.process.Init) !u8 {
    var stdout_fi = std.Io.File.stdout();
    var stdout_buf:[1024]u8 = undefined;
    var stdout_wr = stdout_fi.writer(init.io, &stdout_buf);
    const stdout = &stdout_wr.interface;

    var opts:types.Opts = startup.determine_opts(init) catch |e| return hlp.err_out(e);
    defer opts.deinit(init.gpa);

    var file = try std.Io.Dir.openFileAbsolute(init.io, opts.path.?, .{ .mode = .read_write });
    defer file.close(init.io);

    switch (opts.act) {
        .get => {
            const val = try store.get_val(init.gpa, init.io, file, opts.key.?) orelse {
                std.debug.print("key not found: |{s}|\n", .{opts.key.?});
                return 1;
            };
            defer init.gpa.free(val);
            try stdout.writeAll(val);
            try stdout.flush();
        },
        .put => {
            if (try store.get_val(init.gpa, init.io, file, opts.key.?)) |_|
                @panic("TODO: overwrite existing data"); //I know how I can do this, but I'd like to think of a more elegant solution
            try store.put_val(init.io, file,opts.key.?, opts.val.?);
        },
    }
    return 0;
}

