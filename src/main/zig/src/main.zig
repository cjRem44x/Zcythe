const std = @import("std");
const u = @import("util.zig");

pub fn main() !void {
    const args_alloc = std.heap.page_allocator;
    const args = try u.get_args(args_alloc);

    if (args.len == 0) {
        std.debug.print("No arguments provided.\n", .{});
        return;
    }
    for (args, 0..) |arg, i| {
        std.debug.print("Arg {d}: {s}\n", .{ i, arg });
    }
}
