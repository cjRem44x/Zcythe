const std = @import("std");
const u = @import("util.zig");
const vals = @import("vals.zig");

// Mode flags
var is_building: bool = false;
var is_running: bool = false;

pub fn proc_args(args: [][]const u8) void {
    for (args) |e| {
        if (std.mem.eql(u8, e, vals.BUILD_ARG)) {
            is_building = true;
        } else if (std.mem.eql(u8, e, vals.RUN_ARG)) {
            is_running = true;
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
