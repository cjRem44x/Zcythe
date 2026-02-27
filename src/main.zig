//! zcy – Zcythe CLI  —  src/main.zig
//!
//! Entry point for the `zcy` command-line tool.
//! Dispatches sub-commands:
//!   init        – scaffold a new Zcythe project in the CWD
//!   build       – transpile src/main/zcy/main.zcy → Zig, then compile
//!   run         – build and execute the compiled binary
//!   add <pkg>   – add a GitHub package dependency (owner/repo)
//!
//! All commands expect to be run from the project root
//! (the directory that was initialised with `zcy init`).

const std    = @import("std");
const Zcythe = @import("Zcythe");

// ─── Usage ───────────────────────────────────────────────────────────────────

const usage =
    \\Usage: zcy <command> [options]
    \\
    \\Commands:
    \\  init              Create a new Zcythe project in the current directory
    \\  build [-name=N]   Transpile src/main/zcy/main.zcy and compile it
    \\  run   [-name=N]   Build and execute the compiled binary
    \\  add <owner/repo>  Add a GitHub package dependency
    \\
    \\Options:
    \\  -name=NAME   Binary name written to zcy-bin/ (default: main)
    \\
;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Scan extra CLI args for `-name=VALUE`; return VALUE or "main" if absent.
fn parseName(extra_args: []const []const u8) []const u8 {
    for (extra_args) |arg| {
        if (std.mem.startsWith(u8, arg, "-name=")) return arg[6..];
    }
    return "main";
}

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
        const name = parseName(args[2..]);
        try cmdBuild(alloc, name);
    } else if (std.mem.eql(u8, cmd, "run")) {
        const name = parseName(args[2..]);
        // args[2..] are forwarded verbatim to the compiled binary.
        try cmdRun(alloc, name, args[2..]);
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) {
            try std.fs.File.stderr().writeAll("usage: zcy add <owner/repo>\n");
            std.process.exit(1);
        }
        try cmdAdd(alloc, args[2]);
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
    try cwd.makePath("zcy-bin");

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

    const manifest =
        \\[package]
        \\name = "project"
        \\version = "0.1.0"
        \\
        \\[dependencies]
        \\
    ;
    const toml = cwd.createFile("zcypm.toml", .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.File.stderr().writeAll("note: zcypm.toml already exists, skipping\n");
            try std.fs.File.stdout().writeAll("Initialized Zcythe project.\n");
            return;
        },
        else => return err,
    };
    defer toml.close();
    try toml.writeAll(manifest);

    std.debug.print("***", .{});
    try std.fs.File.stdout().writeAll("Initialized Zcythe project.\n");
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy add
// ═══════════════════════════════════════════════════════════════════════════

/// Add a GitHub package dependency by cloning it into `zcy-pkgs/<owner>/<repo>/`
/// and recording it in `zcypm.toml`.  `pkg_arg` must be in `owner/repo` format.
fn cmdAdd(alloc: std.mem.Allocator, pkg_arg: []const u8) !void {
    const cwd = std.fs.cwd();

    // ── 1. Validate owner/repo format ────────────────────────────────────
    const slash_idx = std.mem.indexOfScalar(u8, pkg_arg, '/') orelse {
        try std.fs.File.stderr().writeAll("error: package must be in 'owner/repo' format\n");
        std.process.exit(1);
    };
    // Ensure there is only one slash.
    if (std.mem.indexOfScalar(u8, pkg_arg[slash_idx + 1 ..], '/') != null) {
        try std.fs.File.stderr().writeAll("error: package must be in 'owner/repo' format\n");
        std.process.exit(1);
    }
    const owner = pkg_arg[0..slash_idx];
    const repo  = pkg_arg[slash_idx + 1 ..];

    // ── 2. Read zcypm.toml ────────────────────────────────────────────────
    const toml_src = cwd.readFileAlloc(alloc, "zcypm.toml", 1 << 20) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("error: zcypm.toml not found — run `zcy init` first\n");
            std.process.exit(1);
        },
        else => return err,
    };
    defer alloc.free(toml_src);

    // ── 3. Duplicate check ────────────────────────────────────────────────
    if (std.mem.indexOf(u8, toml_src, pkg_arg) != null) {
        const msg = try std.fmt.allocPrint(alloc, "note: '{s}' is already added\n", .{pkg_arg});
        defer alloc.free(msg);
        try std.fs.File.stdout().writeAll(msg);
        return;
    }

    // ── 4. Append dep to [dependencies] section ──────────────────────────
    const dep_line = try std.fmt.allocPrint(alloc, "{s} = \"*\"\n", .{pkg_arg});
    defer alloc.free(dep_line);

    // Find "[dependencies]" header position.
    const deps_header = "[dependencies]";
    const header_pos  = std.mem.indexOf(u8, toml_src, deps_header) orelse {
        try std.fs.File.stderr().writeAll("error: zcypm.toml has no [dependencies] section\n");
        std.process.exit(1);
    };
    const after_header = header_pos + deps_header.len;

    // Find the start of the next section (if any) after [dependencies].
    var insert_pos: usize = toml_src.len;
    var search_start = after_header;
    while (search_start < toml_src.len) {
        const nl = std.mem.indexOfScalar(u8, toml_src[search_start..], '\n') orelse break;
        const line_start = search_start + nl + 1;
        if (line_start >= toml_src.len) break;
        if (toml_src[line_start] == '[') {
            insert_pos = line_start;
            break;
        }
        search_start = line_start;
    }

    // Build new file contents: everything up to insert_pos + dep_line + rest.
    const new_toml = try std.fmt.allocPrint(
        alloc,
        "{s}{s}{s}",
        .{ toml_src[0..insert_pos], dep_line, toml_src[insert_pos..] },
    );
    defer alloc.free(new_toml);

    {
        const toml_file = try cwd.createFile("zcypm.toml", .{});
        defer toml_file.close();
        try toml_file.writeAll(new_toml);
    }

    // ── 5. Ensure zcy-pkgs/<owner>/ exists ───────────────────────────────
    const pkg_owner_dir = try std.fmt.allocPrint(alloc, "zcy-pkgs/{s}", .{owner});
    defer alloc.free(pkg_owner_dir);
    try cwd.makePath(pkg_owner_dir);

    // ── 6. git clone ──────────────────────────────────────────────────────
    const url  = try std.fmt.allocPrint(alloc, "https://github.com/{s}/{s}", .{ owner, repo });
    defer alloc.free(url);
    const dest = try std.fmt.allocPrint(alloc, "zcy-pkgs/{s}/{s}", .{ owner, repo });
    defer alloc.free(dest);

    const clone = std.process.Child.run(.{
        .allocator = alloc,
        .argv      = &.{ "git", "clone", url, dest },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("error: `git` not found in PATH\n");
            std.process.exit(1);
        },
        else => return err,
    };
    defer alloc.free(clone.stdout);
    defer alloc.free(clone.stderr);

    // git prints progress to stderr; relay it.
    if (clone.stderr.len > 0) try std.fs.File.stderr().writeAll(clone.stderr);
    if (clone.stdout.len > 0) try std.fs.File.stdout().writeAll(clone.stdout);

    const exit_code: u8 = switch (clone.term) {
        .Exited => |c| c,
        else    => 1,
    };
    if (exit_code != 0) {
        const msg = try std.fmt.allocPrint(alloc, "error: failed to clone '{s}'\n", .{pkg_arg});
        defer alloc.free(msg);
        try std.fs.File.stderr().writeAll(msg);
        std.process.exit(exit_code);
    }

    // ── 7. Done ───────────────────────────────────────────────────────────
    const done = try std.fmt.allocPrint(alloc, "Added {s}.\n", .{pkg_arg});
    defer alloc.free(done);
    try std.fs.File.stdout().writeAll(done);
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy build
// ═══════════════════════════════════════════════════════════════════════════

/// Recursively transpile every `.zcy` file under `src_base/<rel>/`
/// (skipping `main.zcy` at the top level) into `out_base/<rel>/*.zig`.
/// `rel` is the relative subdirectory path within src_base; pass "" for root.
fn transpileZcyDir(
    alloc: std.mem.Allocator,
    aa:    std.mem.Allocator,
    cwd:   std.fs.Dir,
    src_base: []const u8,
    out_base: []const u8,
    rel:      []const u8,
) !void {
    const dir_path = if (rel.len == 0)
        try alloc.dupe(u8, src_base)
    else
        try std.fmt.allocPrint(alloc, "{s}/{s}", .{ src_base, rel });
    defer alloc.free(dir_path);

    var dir = try cwd.openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const entry_rel = if (rel.len == 0)
            try alloc.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(alloc, "{s}/{s}", .{ rel, entry.name });
        defer alloc.free(entry_rel);

        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zcy")) continue;
                // Skip top-level main.zcy — already handled by cmdBuild.
                if (rel.len == 0 and std.mem.eql(u8, entry.name, "main.zcy")) continue;

                const stem     = entry.name[0 .. entry.name.len - 4];
                const rel_stem = if (rel.len == 0)
                    try alloc.dupe(u8, stem)
                else
                    try std.fmt.allocPrint(alloc, "{s}/{s}", .{ rel, stem });
                defer alloc.free(rel_stem);

                const src_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ src_base, entry_rel });
                defer alloc.free(src_path);
                const out_path = try std.fmt.allocPrint(alloc, "{s}/{s}.zig", .{ out_base, rel_stem });
                defer alloc.free(out_path);

                // Ensure the output subdirectory exists.
                if (std.fs.path.dirname(out_path)) |parent|
                    try cwd.makePath(parent);

                const src = try cwd.readFileAlloc(alloc, src_path, 1 << 20);
                defer alloc.free(src);

                var buf: std.ArrayListUnmanaged(u8) = .empty;
                var p = Zcythe.parser.Parser.init(aa, src);
                const root = p.parse() catch |err| {
                    const msg = try std.fmt.allocPrint(alloc, "error: failed to parse {s}\n", .{src_path});
                    defer alloc.free(msg);
                    try std.fs.File.stderr().writeAll(msg);
                    return err;
                };
                var cg = Zcythe.codegen.CodeGen.init(buf.writer(aa).any());
                try cg.emit(root);

                const out_file = try cwd.createFile(out_path, .{});
                defer out_file.close();
                try out_file.writeAll(buf.items);
            },
            .directory => try transpileZcyDir(alloc, aa, cwd, src_base, out_base, entry_rel),
            else => {},
        }
    }
}

/// Transpile `src/main/zcy/main.zcy` → `src/zcyout/main.zig`, then compile
/// with `zig build-exe`.  The binary is written to `zcy-bin/<name>`.
fn cmdBuild(alloc: std.mem.Allocator, name: []const u8) !void {
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

    // ── 3b. Transpile all other .zcy files in src/main/zcy/ ─────────────
    try transpileZcyDir(alloc, aa, cwd, "src/main/zcy", "src/zcyout", "");

    // ── 4. Compile with zig build-exe ────────────────────────────────────
    try cwd.makePath("zcy-bin");
    const emit_flag = try std.fmt.allocPrint(alloc, "-femit-bin=zcy-bin/{s}", .{name});
    defer alloc.free(emit_flag);
    const compile = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{
            "zig", "build-exe",
            "src/zcyout/main.zig",
            emit_flag,
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
    std.debug.print("***\n", .{});
    try std.fs.File.stdout().writeAll("Build successful.\n");
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy run
// ═══════════════════════════════════════════════════════════════════════════

/// Build the project (cmdBuild), then execute `zcy-bin/<name>`, inheriting
/// stdin/stdout/stderr so the user's program can interact normally.
/// `run_args` are any tokens after `zcy run` and are forwarded verbatim
/// to the compiled binary (e.g. `zcy run a b c` → `zcy-bin/main a b c`).
fn cmdRun(alloc: std.mem.Allocator, name: []const u8, run_args: []const []const u8) !void {
    // Build first; exits the process on any failure.
    try cmdBuild(alloc, name);
    std.debug.print("Running Zcythe Code...\n\n", .{});

    // Build argv: ["zcy-bin/<name>"] ++ run_args
    const argv = try alloc.alloc([]const u8, 1 + run_args.len);
    defer alloc.free(argv);
    const bin_path = try std.fmt.allocPrint(alloc, "zcy-bin/{s}", .{name});
    defer alloc.free(bin_path);
    argv[0] = bin_path;
    @memcpy(argv[1..], run_args);

    // Spawn the compiled binary with the full terminal attached.
    var child = std.process.Child.init(argv, alloc);
    child.stdin_behavior  = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    _ = try child.wait();
}
