const std = @import("std");
const hlp = @import("helpers.zig");

pub fn get_val(
    alloc:std.mem.Allocator,
    io:std.Io,
    file:std.Io.File,
    key:[]const u8
) !?[]const u8 {
    var buf:[1024]u8 = undefined;
    var useless_reader = file.reader(io, &buf);
    const reader = &useless_reader.interface;

    var n:usize = 0;
    while (try hlp.wrap(reader.takeByte())) |b| {
        if (b == 0) {
            const k = try reader.take(n);
            n = 0;
            var len:usize = 0;
            while (try hlp.wrap(reader.takeByte())) |c| {
                if (c == 0) break;
                len += c;
            }
            if (std.mem.eql(u8, k, key))
                return try alloc.dupe(u8, try reader.take(len))
            else
                if (try reader.discard(.limited(len)) != len)
                    return error.EndOfFile;
            continue;
        }
        n += b;
    }
    return null;
}

pub fn put_val(
    io:std.Io,
    file:std.Io.File,
    key:[]const u8,
    val:[]const u8
) !void {
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

pub fn dump(
    io:std.Io,
    db:std.Io.File,
    writer:*std.Io.Writer,
) !void {
    var buf:[1024]u8 = undefined;
    var useless_reader = db.reader(io, &buf);
    const reader = &useless_reader.interface;

    var n:usize = 0;
    while (try hlp.wrap(reader.takeByte())) |b| {
        if (b == 0) {
            const k = try reader.take(n);
            n = 0;
            var len:usize = 0;
            while (try hlp.wrap(reader.takeByte())) |c| {
                if (c == 0) break;
                len += c;
            }
            const val = try reader.take(len);
            const is_ascii = for (val) |c| {
                if (!std.ascii.isAscii(c)) break false;
            } else true;
            try writer.print("\n{s}\n\t", .{k});
            if (is_ascii)
                try writer.writeAll(val)
            else
                for (val) |c| try writer.print(" 0x{X}", .{c});
            try writer.writeAll("\n");
            try writer.flush();
            continue;
        }
        n += b;
    }
}

pub fn del(
    io:std.Io,
    db:std.Io.File,
    key:[]const u8,
) !void {
    var buf:[1024]u8 = undefined;
    var useless_reader = db.reader(io, &buf);
    const reader = &useless_reader.interface;

    const copy:std.Io.File = .{
        .handle = try std.posix.memfd_create("", 0),
        .flags = .{ .nonblocking = false }
    };
    defer copy.close(io);

    var n:usize = 0;
    var read:usize = 0;
    var found:bool = false;
    while (try hlp.wrap(reader.takeByte())) |b| : (read += 1) {
        if (b == 0) {
            const k = try reader.take(n);
            n = 0;
            var len:usize = 0;
            while (try hlp.wrap(reader.takeByte())) |c| : (read += 1) {
                if (c == 0) break;
                len += c;
            }
            if (!found) if (std.mem.eql(u8, k, key)) {
                found = true;
                if (try reader.discard(.limited(len)) != len)
                    return error.EndOfFile;
                read -= k.len-1;
                continue;
            };
            const val = try reader.take(len);
            try put_val(io, copy, k, val);
            continue;
        }
        n += b;
    }
    if (!found)
        return error.KeyNotFound;
    _ = std.posix.system.ftruncate(db.handle, 0);
    _ = std.posix.system.lseek(copy.handle, 0, std.posix.SEEK.SET);
    var copy_buf:[1024]u8 = undefined;
    var copy_reader = copy.reader(io, &copy_buf);
    var useless_writer = db.writer(io, &buf);
    const wrote = try copy_reader.interface.streamRemaining(&useless_writer.interface);
    try useless_writer.interface.flush();
    if (wrote < read)
        return error.FailedToCopyStore;
}
