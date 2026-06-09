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
