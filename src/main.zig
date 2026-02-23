const std = @import("std");

const usage =
    \\Usage: zcy <command>
    \\
    \\Commands:
    \\  init    Create a new Zcythe project in the current directory
    \\
;

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll(usage);
        std.process.exit(1);
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit();
    } else {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "zcy: unknown command '{s}'\n\n", .{cmd});
        try std.fs.File.stderr().writeAll(msg);
        try std.fs.File.stderr().writeAll(usage);
        std.process.exit(1);
    }
}

fn cmdInit() !void {
    const cwd = std.fs.cwd();

    try cwd.makePath("src/zcyout");
    try cwd.makePath("src/main/zcy");

    const starter =
        \\# entry point
        \\@main {
        \\    @pl("Hello World")
        \\}
        \\
    ;

    const file = cwd.createFile("src/main/zcy/main.zcy", .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.File.stderr().writeAll("note: src/main/zcy/main.zcy already exists, skipping\n");
            try std.fs.File.stdout().writeAll("Initialized Zcythe project.\n");
            return;
        },
        else => return err,
    };
    defer file.close();
    try file.writeAll(starter);

    try std.fs.File.stdout().writeAll("Initialized Zcythe project.\n");
}
