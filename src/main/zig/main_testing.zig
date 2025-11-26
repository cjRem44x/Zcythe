const std = @import("std");
const m = @import("src/main.zig");

pub fn main() !void {
    try test_src_scan();
}

pub fn test_src_scan() !void {
    var param = [_][]const u8{ "build", "zcy_main.zcy" };
    try m.proc_args(&param);

    std.debug.print("path = {s}\n", .{m.zcy_src_file_path});
}

pub fn test_src_input() void {
    var param = [_][]const u8{ "build", "run", "main.zcy" };
    m.proc_args(&param) catch std.process.exit(1);

    std.debug.print("path = {s}\n", .{m.zcy_src_file_path});
}
