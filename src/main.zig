//! zcy – Zcythe CLI  —  src/main.zig
//!
//! Entry point for the `zcy` command-line tool.
//! Dispatches sub-commands:
//!   init   – scaffold a new Zcythe project in the CWD
//!   build  – transpile src/main/zcy/main.zcy → Zig, then compile
//!   run    – build and execute the compiled binary
//!
//! All commands expect to be run from the project root
//! (the directory that was initialised with `zcy init`).

const std    = @import("std");
const Zcythe = @import("Zcythe");

// ─── Usage ───────────────────────────────────────────────────────────────────

const usage =
    \\Usage: zcy <command>
    \\
    \\Commands:
    \\  init    Create a new Zcythe project in the current directory
    \\  build   Transpile src/main/zcy/main.zcy and compile it
    \\  run     Build and execute the compiled binary
    \\
;

// ═══════════════════════════════════════════════════════════════════════════
//  main
// ═══════════════════════════════════════════════════════════════════════════

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll(usage);
        std.process.exit(1);
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit();
    } else if (std.mem.eql(u8, cmd, "build")) {
        try cmdBuild(alloc);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try cmdRun(alloc);
    } else {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "zcy: unknown command '{s}'\n\n", .{cmd});
        try std.fs.File.stderr().writeAll(msg);
        try std.fs.File.stderr().writeAll(usage);
        std.process.exit(1);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy init
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
//  zcy build
// ═══════════════════════════════════════════════════════════════════════════

/// Transpile `src/main/zcy/main.zcy` → `src/zcyout/main.zig`, then compile
/// with `zig build-exe`.  The binary is written to `./main` in the CWD.
fn cmdBuild(alloc: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();

    // ── 1. Read .zcy source ──────────────────────────────────────────────
    const zcy_src = cwd.readFileAlloc(alloc, "src/main/zcy/main.zcy", 1 << 20) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll(
                "error: src/main/zcy/main.zcy not found — run `zcy init` first\n",
            );
            std.process.exit(1);
        },
        else => return err,
    };
    defer alloc.free(zcy_src);

    // ── 2. Transpile: lex → parse → codegen ─────────────────────────────
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var p = Zcythe.parser.Parser.init(aa, zcy_src);
    const root = p.parse() catch |err| {
        try std.fs.File.stderr().writeAll("error: failed to parse src/main/zcy/main.zcy\n");
        return err;
    };
    var cg = Zcythe.codegen.CodeGen.init(buf.writer(aa).any());
    try cg.emit(root);
    const zig_src = buf.items;

    // ── 3. Write generated Zig to src/zcyout/main.zig ───────────────────
    {
        const out_file = try cwd.createFile("src/zcyout/main.zig", .{});
        defer out_file.close();
        try out_file.writeAll(zig_src);
    }

    // ── 4. Compile with zig build-exe ────────────────────────────────────
    const compile = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{
            "zig", "build-exe",
            "src/zcyout/main.zig",
            "-femit-bin=./main",
        },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
            std.process.exit(1);
        },
        else => return err,
    };
    defer alloc.free(compile.stdout);
    defer alloc.free(compile.stderr);

    // Relay any compiler output to the user.
    if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
    if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);

    const exit_code: u8 = switch (compile.term) {
        .Exited => |c| c,
        else    => 1,
    };
    if (exit_code != 0) {
        try std.fs.File.stderr().writeAll("error: compilation failed\n");
        std.process.exit(exit_code);
    }

    try std.fs.File.stdout().writeAll("Build successful.\n");
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy run
// ═══════════════════════════════════════════════════════════════════════════

/// Build the project (cmdBuild), then execute `./main`, inheriting
/// stdin/stdout/stderr so the user's program can interact normally.
fn cmdRun(alloc: std.mem.Allocator) !void {
    // Build first; exits the process on any failure.
    try cmdBuild(alloc);

    // Spawn the compiled binary with the full terminal attached.
    var child = std.process.Child.init(&.{"./main"}, alloc);
    child.stdin_behavior  = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    _ = try child.wait();
}
