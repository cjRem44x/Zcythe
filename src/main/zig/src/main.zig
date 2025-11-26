const std = @import("std");
const u = @import("util.zig");
const vals = @import("vals.zig");
const file_reader = @import("file_reader.zig").FileReader;

// Mode flags
pub var is_building: bool = false;
pub var is_running: bool = false;
pub var zcy_src_file_path: []const u8 = undefined;

pub fn scan_src_file() !void {
    var fr = try file_reader.init(zcy_src_file_path);
    defer fr.deinit();

    while (fr.read_in_char()) |c| {
        std.debug.print("{c}", .{c}); // simple print for now
    }
}    

pub fn proc_args(args: [][]const u8) !void {
    for (args) |e| {
        if (std.mem.eql(u8, e, vals.BUILD_ARG)) {
            is_building = true;
        } else if (std.mem.eql(u8, e, vals.RUN_ARG)) {
            is_running = true;
        } else if (u.ends_with(e, vals.ZCY_SRC_EXT)) {
            zcy_src_file_path = @as([]const u8, e); 
            try scan_src_file();
        } else {
            u.strlog("!! Zcythe CLI Argument not recognized !!");
        }
    }
}

pub fn main() !void {
    const args_alloc = std.heap.page_allocator;
    const args = try u.get_args(args_alloc);

    if (args.len < 2) {
        u.strlog("!! Zcythe CLI Arguments are to short !!");
    } else {
        proc_args(args);
    }
}
