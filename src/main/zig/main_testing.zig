const std = @import("std");
const m = @import("src/main.zig");

pub fn main() !void {
    var param = [_][]const u8{ "build", "ru" };
    m.proc_args(&param);
}
