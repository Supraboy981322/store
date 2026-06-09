pub fn err_out(err:anyerror) u8 {
    @import("std").debug.print("{t}\n", .{err});
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
