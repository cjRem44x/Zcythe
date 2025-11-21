const std = @import("std");
const m = @import("src/main.zig");

pub fn main() !void {
    var param = [_][]const u8{ "build", "run", "main.zcy" };
    m.proc_args(&param);

    std.debug.print("path = {s}\n", .{m.zcy_src_file_path});
}
