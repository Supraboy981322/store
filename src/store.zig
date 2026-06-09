const std = @import("std");
const hlp = @import("helpers.zig");

pub fn get_val(alloc:std.mem.Allocator, io:std.Io, file:std.Io.File, key:[]const u8) !?[]const u8 {
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
                if (try reader.discard(.limited(len)) != len) return error.EndOfFile;
            continue;
        }
        n += b;
    }
    return null;
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
