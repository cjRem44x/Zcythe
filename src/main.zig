//! zcy – Zcythe CLI  —  src/main.zig
//!
//! Entry point for the `zcy` command-line tool.
//! Dispatches sub-commands:
//!   init        – scaffold a new Zcythe project in the CWD
//!   build       – transpile src/main/zcy/main.zcy → Zig, then compile
//!   run         – build and execute the compiled binary
//!   add <pkg>   – add a ZcytheAddLinkPkg (owner/repo)
//!   lspkg       – list all available packages (NativeSysPkg + ZcytheAddLinkPkg)
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
    \\  init                     Create a new Zcythe project in the current directory
    \\  build     [-name=N]      Transpile src/main/zcy/main.zcy and compile it
    \\  build-src                Transpile .zcy → src/zcyout only (skip compile)
    \\  build-out [-name=N]      Compile src/zcyout → zcy-bin only (skip transpile)
    \\  run       [-name=N]      Build and execute the compiled binary
    \\  test      [file.zcy]     Transpile and run @test blocks via zig test
    \\  sac <files...> [-name=N] Compile .zcy files directly to a standalone binary
    \\  add <owner/repo>         Add a ZcytheAddLinkPkg from GitHub
    \\  lspkg                    List all available packages
    \\
    \\Options:
    \\  -name=NAME   Binary output name (default: main)
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
    } else if (std.mem.eql(u8, cmd, "build-src")) {
        try cmdBuildSrc(alloc);
    } else if (std.mem.eql(u8, cmd, "build-out")) {
        const name = parseName(args[2..]);
        try cmdBuildOut(alloc, name);
    } else if (std.mem.eql(u8, cmd, "run")) {
        const name = parseName(args[2..]);
        // args[2..] are forwarded verbatim to the compiled binary.
        try cmdRun(alloc, name, args[2..]);
    } else if (std.mem.eql(u8, cmd, "test")) {
        const test_file: ?[]const u8 = if (args.len > 2) args[2] else null;
        try cmdTest(alloc, test_file);
    } else if (std.mem.eql(u8, cmd, "sac")) {
        var input_files: std.ArrayListUnmanaged([]const u8) = .empty;
        defer input_files.deinit(alloc);
        var sac_name: []const u8 = "main";
        for (args[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "-name=")) {
                sac_name = arg[6..];
            } else if (std.mem.endsWith(u8, arg, ".zcy")) {
                try input_files.append(alloc, arg);
            } else {
                const msg = try std.fmt.allocPrint(alloc, "zcy sac: unknown argument '{s}'\n", .{arg});
                defer alloc.free(msg);
                try std.fs.File.stderr().writeAll(msg);
                std.process.exit(1);
            }
        }
        try cmdSac(alloc, sac_name, input_files.items);
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) {
            try std.fs.File.stderr().writeAll("usage: zcy add raylib|<owner/repo>   (run `zcy lspkg` for full list)\n");
            std.process.exit(1);
        }
        try cmdAdd(alloc, args[2]);
    } else if (std.mem.eql(u8, cmd, "lspkg")) {
        try cmdLspkg();
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

    std.debug.print("***\n", .{});
    try std.fs.File.stdout().writeAll("Initialized Zcythe project.\n");
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy lspkg
// ═══════════════════════════════════════════════════════════════════════════

fn cmdLspkg() !void {
    const out = std.fs.File.stdout();
    try out.writeAll(
        \\Available Zcythe packages
        \\═════════════════════════════════════════════════════════════════════
        \\
        \\NativeSysPkg  —  installed via your OS package manager, auto-linked
        \\                 when detected in source.  No `zcy add` needed.
        \\─────────────────────────────────────────────────────────────────────
        \\
        \\  @zcy.sqlite   SQLite3 embedded database
        \\    Fedora/RHEL:   sudo dnf install sqlite-devel
        \\    Debian/Ubuntu: sudo apt install libsqlite3-dev
        \\    Arch:          sudo pacman -S sqlite
        \\    macOS:         brew install sqlite  (or use system-provided)
        \\
        \\  @zcy.qt       Qt5/Qt6 widget toolkit
        \\    Fedora/RHEL:   sudo dnf install qt6-qtbase-devel
        \\    Debian/Ubuntu: sudo apt install qt6-base-dev
        \\    Arch:          sudo pacman -S qt6-base
        \\    macOS:         brew install qt
        \\
        \\  @zcy.sodium   Cryptography (libsodium)
        \\    Fedora/RHEL:   sudo dnf install libsodium-devel
        \\    Debian/Ubuntu: sudo apt install libsodium-dev
        \\    Arch:          sudo pacman -S libsodium
        \\    macOS:         brew install libsodium
        \\
        \\  @zcy.openmp   Parallel threading (OpenMP / libgomp)
        \\    Fedora/RHEL:   sudo dnf install libgomp
        \\    Debian/Ubuntu: sudo apt install libgomp1
        \\    Arch:          (included with gcc)
        \\    macOS:         brew install libomp
        \\
        \\─────────────────────────────────────────────────────────────────────
        \\
        \\ZcytheAddLinkPkg  —  downloaded into zcy-pkgs/ via `zcy add`.
        \\                     No system install required.
        \\─────────────────────────────────────────────────────────────────────
        \\
        \\  @zcy.raylib   2D/3D graphics (raylib, bundled C source)
        \\    zcy add raylib
        \\
        \\  <owner/repo>  Any GitHub package
        \\    zcy add <owner/repo>
        \\
        \\═════════════════════════════════════════════════════════════════════
        \\
    );
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy add  (ZcytheAddLinkPkg)
//
//  ZcytheAddLinkPkgs are downloaded into zcy-pkgs/ and recorded in
//  zcypm.toml.  They do NOT require a system-level install.
//
//  Contrast with NativeSysPkgs (@zcy.sqlite, @zcy.qt, @zcy.sodium,
//  @zcy.openmp): those are installed via the OS package manager and linked
//  automatically when the compiler detects their @import — no `zcy add`.
// ═══════════════════════════════════════════════════════════════════════════

/// Return true when `name` appears as a key in the [dependencies] section
/// of the given TOML source.  Stops at the next `[section]` header.
fn tomlDepIsPresent(toml_src: []const u8, name: []const u8) bool {
    const deps_header = "[dependencies]";
    const header_pos = std.mem.indexOf(u8, toml_src, deps_header) orelse return false;
    const after = toml_src[header_pos + deps_header.len ..];
    // Narrow to just the deps section (stop at next `[` header).
    const end = std.mem.indexOf(u8, after, "\n[") orelse after.len;
    return std.mem.indexOf(u8, after[0..end], name) != null;
}

/// Generate `build.zig` and `build.zig.zon` for a raylib project.
/// The binary name is embedded in build.zig so `zig build` produces
/// `zig-out/bin/<name>`, which cmdBuild then copies to `zcy-bin/<name>`.
fn genRaylibBuildFiles(alloc: std.mem.Allocator, cwd: std.fs.Dir, name: []const u8) !void {
    const build_zig = try std.fmt.allocPrint(alloc,
        \\const std = @import("std");
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const rl_dep = b.dependency("raylib-zig", .{{
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    const exe = b.addExecutable(.{{
        \\        .name = "{s}",
        \\        .root_module = b.createModule(.{{
        \\            .root_source_file = b.path("src/zcyout/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\            .imports = &.{{
        \\                .{{ .name = "raylib", .module = rl_dep.module("raylib") }},
        \\            }},
        \\        }}),
        \\    }});
        \\    exe.linkLibrary(rl_dep.artifact("raylib"));
        \\    b.installArtifact(exe);
        \\}}
        \\
    , .{name});
    defer alloc.free(build_zig);
    {
        const f = try cwd.createFile("build.zig", .{});
        defer f.close();
        try f.writeAll(build_zig);
    }

    const build_zon =
        \\.{
        \\    .name = .project,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x2fb3d0ee3fd15e24,
        \\    .dependencies = .{
        \\        .@"raylib-zig" = .{
        \\            .path = "zcy-pkgs/raylib-zig/raylib-zig",
        \\        },
        \\    },
        \\    .paths = .{"."},
        \\}
        \\
    ;
    {
        const f = try cwd.createFile("build.zig.zon", .{});
        defer f.close();
        try f.writeAll(build_zon);
    }
}

/// Add a GitHub package dependency by cloning it into `zcy-pkgs/<owner>/<repo>/`
/// and recording it in `zcypm.toml`.  `pkg_arg` must be in `owner/repo` format,
/// or one of the known first-party library names (e.g. `raylib`).
fn cmdAdd(alloc: std.mem.Allocator, pkg_arg: []const u8) !void {
    const cwd = std.fs.cwd();

    // ── ZcytheAddLinkPkg: raylib ─────────────────────────────────────────
    //    Clones raylib-zig (bundles its own C source) into zcy-pkgs/.
    //    Does NOT require a system raylib install.
    if (std.mem.eql(u8, pkg_arg, "raylib")) {
        const toml_src = cwd.readFileAlloc(alloc, "zcypm.toml", 1 << 20) catch |err| switch (err) {
            error.FileNotFound => {
                try std.fs.File.stderr().writeAll("error: zcypm.toml not found — run `zcy init` first\n");
                std.process.exit(1);
            },
            else => return err,
        };
        defer alloc.free(toml_src);

        if (tomlDepIsPresent(toml_src, "raylib")) {
            try std.fs.File.stdout().writeAll("note: 'raylib' is already added\n");
            return;
        }

        // Append `raylib = "*"` to [dependencies].
        const deps_header = "[dependencies]";
        const header_pos = std.mem.indexOf(u8, toml_src, deps_header) orelse {
            try std.fs.File.stderr().writeAll("error: zcypm.toml has no [dependencies] section\n");
            std.process.exit(1);
        };
        const after_header = header_pos + deps_header.len;
        var insert_pos: usize = toml_src.len;
        var search_start = after_header;
        while (search_start < toml_src.len) {
            const nl = std.mem.indexOfScalar(u8, toml_src[search_start..], '\n') orelse break;
            const line_start = search_start + nl + 1;
            if (line_start >= toml_src.len) break;
            if (toml_src[line_start] == '[') { insert_pos = line_start; break; }
            search_start = line_start;
        }
        const new_toml = try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{
            toml_src[0..insert_pos],
            "raylib = \"*\"\n",
            toml_src[insert_pos..],
        });
        defer alloc.free(new_toml);
        {
            const f = try cwd.createFile("zcypm.toml", .{});
            defer f.close();
            try f.writeAll(new_toml);
        }

        // Clone raylib-zig with --recursive to fetch the bundled C source.
        try cwd.makePath("zcy-pkgs/raylib-zig");
        const clone = std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{
                "git", "clone", "--recursive",
                "https://github.com/raylib-zig/raylib-zig.git",
                "zcy-pkgs/raylib-zig/raylib-zig",
            },
        }) catch |err| switch (err) {
            error.FileNotFound => {
                try std.fs.File.stderr().writeAll("error: `git` not found in PATH\n");
                std.process.exit(1);
            },
            else => return err,
        };
        defer alloc.free(clone.stdout);
        defer alloc.free(clone.stderr);
        if (clone.stderr.len > 0) try std.fs.File.stderr().writeAll(clone.stderr);
        if (clone.stdout.len > 0) try std.fs.File.stdout().writeAll(clone.stdout);
        const rl_exit: u8 = switch (clone.term) { .Exited => |c| c, else => 1 };
        if (rl_exit != 0) {
            try std.fs.File.stderr().writeAll("error: failed to clone raylib-zig\n");
            std.process.exit(rl_exit);
        }
        try std.fs.File.stdout().writeAll("Added raylib.\n");
        return;
    }

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
//  zcy sac
// ═══════════════════════════════════════════════════════════════════════════

/// Return the longest common path prefix of two absolute POSIX paths,
/// truncated to a directory boundary (i.e. never splits a path component).
fn commonDirPrefix(a: []const u8, b: []const u8) []const u8 {
    const len = @min(a.len, b.len);
    var i: usize = 0;
    var last_sep: usize = 0;
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) break;
        if (a[i] == '/') last_sep = i;
    }
    // One is a proper prefix of the other
    if (i == a.len and i == b.len) return a;
    if (i == a.len and b[i] == '/') return a;
    if (i == b.len and a[i] == '/') return b;
    // Diverged mid-component — back up to last separator
    return if (last_sep == 0) "/" else a[0..last_sep];
}

/// Ask gcc for the full path of `filename`; return the containing directory.
/// Falls back to null if gcc is unavailable or the file is not found (i.e.
/// gcc prints the bare filename back unchanged).
fn gccQueryDir(alloc: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    const arg = std.fmt.allocPrint(alloc, "-print-file-name={s}", .{filename}) catch return null;
    defer alloc.free(arg);
    const res = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "gcc", arg },
    }) catch return null;
    defer alloc.free(res.stderr);
    const path = std.mem.trimRight(u8, res.stdout, "\n\r ");
    if (path.len == 0 or std.mem.eql(u8, path, filename)) {
        alloc.free(res.stdout);
        return null;
    }
    const dir = std.fs.path.dirname(path) orelse {
        alloc.free(res.stdout);
        return null;
    };
    const owned = alloc.dupe(u8, dir) catch {
        alloc.free(res.stdout);
        return null;
    };
    alloc.free(res.stdout);
    return owned;
}

/// Ask gcc for the full path of `filename`; return the full path (not just dir).
fn gccQueryFile(alloc: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    const arg = std.fmt.allocPrint(alloc, "-print-file-name={s}", .{filename}) catch return null;
    defer alloc.free(arg);
    const res = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "gcc", arg },
    }) catch return null;
    defer alloc.free(res.stderr);
    const path = std.mem.trimRight(u8, res.stdout, "\n\r ");
    if (path.len == 0 or std.mem.eql(u8, path, filename)) {
        alloc.free(res.stdout);
        return null;
    }
    const owned = alloc.dupe(u8, path) catch {
        alloc.free(res.stdout);
        return null;
    };
    alloc.free(res.stdout);
    return owned;
}

/// Return the directory containing libgomp.so by asking gcc.
fn gccLibDir(alloc: std.mem.Allocator) ?[]const u8 {
    return gccQueryDir(alloc, "libgomp.so");
}

// ─── Qt C++ wrapper source ────────────────────────────────────────────────────

const _zqt_wrapper_cpp: []const u8 =
    \\#include <QApplication>
    \\#include <QMainWindow>
    \\#include <QWidget>
    \\#include <QPushButton>
    \\#include <QLabel>
    \\#include <QLineEdit>
    \\#include <QCheckBox>
    \\#include <QSpinBox>
    \\#include <QVBoxLayout>
    \\#include <QHBoxLayout>
    \\#include <QString>
    \\#include <QByteArray>
    \\#include <QVariant>
    \\#include <cstring>
    \\
    \\static QByteArray _zqt_strbuf;
    \\
    \\extern "C" {
    \\
    \\void* zqt_app_create(void) {
    \\    static int argc = 0;
    \\    static QApplication* app = nullptr;
    \\    if (!app) app = new QApplication(argc, nullptr);
    \\    return app;
    \\}
    \\
    \\int zqt_app_exec(void* app) {
    \\    return static_cast<QApplication*>(app)->exec();
    \\}
    \\
    \\void zqt_app_process_events(void* /*app*/) {
    \\    QCoreApplication::processEvents();
    \\}
    \\
    \\int zqt_app_should_quit(void* /*app*/) {
    \\    for (auto* w : QApplication::topLevelWidgets()) {
    \\        if (w->isVisible()) return 0;
    \\    }
    \\    return 1;
    \\}
    \\
    \\void* zqt_window_create(const char* title, int w, int h) {
    \\    auto* win = new QMainWindow();
    \\    win->setWindowTitle(QString::fromUtf8(title));
    \\    win->resize(w, h);
    \\    return win;
    \\}
    \\
    \\void zqt_window_show(void* win) {
    \\    static_cast<QMainWindow*>(win)->show();
    \\}
    \\
    \\void zqt_window_set_layout(void* win, void* layout) {
    \\    auto* mw = static_cast<QMainWindow*>(win);
    \\    auto* central = new QWidget();
    \\    central->setLayout(static_cast<QLayout*>(layout));
    \\    mw->setCentralWidget(central);
    \\}
    \\
    \\void zqt_window_set_title(void* win, const char* title) {
    \\    static_cast<QMainWindow*>(win)->setWindowTitle(QString::fromUtf8(title));
    \\}
    \\
    \\void zqt_window_resize(void* win, int w, int h) {
    \\    static_cast<QMainWindow*>(win)->resize(w, h);
    \\}
    \\
    \\void* zqt_label_create(const char* text) {
    \\    return new QLabel(QString::fromUtf8(text));
    \\}
    \\
    \\void zqt_label_set_text(void* lbl, const char* text) {
    \\    static_cast<QLabel*>(lbl)->setText(QString::fromUtf8(text));
    \\}
    \\
    \\const char* zqt_label_text(void* lbl) {
    \\    _zqt_strbuf = static_cast<QLabel*>(lbl)->text().toUtf8();
    \\    return _zqt_strbuf.constData();
    \\}
    \\
    \\void* zqt_button_create(const char* text) {
    \\    auto* btn = new QPushButton(QString::fromUtf8(text));
    \\    btn->setProperty("_zqt_clicked", false);
    \\    QObject::connect(btn, &QPushButton::clicked, btn, [btn]() {
    \\        btn->setProperty("_zqt_clicked", true);
    \\    });
    \\    return btn;
    \\}
    \\
    \\void zqt_button_set_text(void* btn, const char* text) {
    \\    static_cast<QPushButton*>(btn)->setText(QString::fromUtf8(text));
    \\}
    \\
    \\int zqt_button_clicked(void* p) {
    \\    auto* btn = static_cast<QPushButton*>(p);
    \\    bool v = btn->property("_zqt_clicked").toBool();
    \\    if (v) btn->setProperty("_zqt_clicked", false);
    \\    return v ? 1 : 0;
    \\}
    \\
    \\void* zqt_lineedit_create(void) {
    \\    return new QLineEdit();
    \\}
    \\
    \\const char* zqt_lineedit_text(void* le) {
    \\    _zqt_strbuf = static_cast<QLineEdit*>(le)->text().toUtf8();
    \\    return _zqt_strbuf.constData();
    \\}
    \\
    \\void zqt_lineedit_set_text(void* le, const char* text) {
    \\    static_cast<QLineEdit*>(le)->setText(QString::fromUtf8(text));
    \\}
    \\
    \\void zqt_lineedit_set_placeholder(void* le, const char* text) {
    \\    static_cast<QLineEdit*>(le)->setPlaceholderText(QString::fromUtf8(text));
    \\}
    \\
    \\void* zqt_checkbox_create(const char* text) {
    \\    auto* cb = new QCheckBox(QString::fromUtf8(text));
    \\    cb->setProperty("_zqt_changed", false);
    \\    QObject::connect(cb, &QCheckBox::stateChanged, cb, [cb](int) {
    \\        cb->setProperty("_zqt_changed", true);
    \\    });
    \\    return cb;
    \\}
    \\
    \\int zqt_checkbox_checked(void* p) {
    \\    return static_cast<QCheckBox*>(p)->isChecked() ? 1 : 0;
    \\}
    \\
    \\void zqt_checkbox_set_checked(void* p, int v) {
    \\    static_cast<QCheckBox*>(p)->setChecked(v != 0);
    \\}
    \\
    \\int zqt_checkbox_changed(void* p) {
    \\    auto* cb = static_cast<QCheckBox*>(p);
    \\    bool v = cb->property("_zqt_changed").toBool();
    \\    if (v) cb->setProperty("_zqt_changed", false);
    \\    return v ? 1 : 0;
    \\}
    \\
    \\void* zqt_spinbox_create(int min, int max) {
    \\    auto* sb = new QSpinBox();
    \\    sb->setRange(min, max);
    \\    sb->setProperty("_zqt_changed", false);
    \\    QObject::connect(sb, QOverload<int>::of(&QSpinBox::valueChanged), sb, [sb](int) {
    \\        sb->setProperty("_zqt_changed", true);
    \\    });
    \\    return sb;
    \\}
    \\
    \\int zqt_spinbox_value(void* p) {
    \\    return static_cast<QSpinBox*>(p)->value();
    \\}
    \\
    \\void zqt_spinbox_set_value(void* p, int v) {
    \\    static_cast<QSpinBox*>(p)->setValue(v);
    \\}
    \\
    \\int zqt_spinbox_changed(void* p) {
    \\    auto* sb = static_cast<QSpinBox*>(p);
    \\    bool v = sb->property("_zqt_changed").toBool();
    \\    if (v) sb->setProperty("_zqt_changed", false);
    \\    return v ? 1 : 0;
    \\}
    \\
    \\void* zqt_vbox_create(void) {
    \\    return new QVBoxLayout();
    \\}
    \\
    \\void* zqt_hbox_create(void) {
    \\    return new QHBoxLayout();
    \\}
    \\
    \\void zqt_layout_add_widget(void* layout, void* widget) {
    \\    static_cast<QLayout*>(layout)->addWidget(static_cast<QWidget*>(widget));
    \\}
    \\
    \\void zqt_layout_add_layout(void* outer, void* inner) {
    \\    static_cast<QBoxLayout*>(outer)->addLayout(static_cast<QLayout*>(inner));
    \\}
    \\
    \\void zqt_layout_add_stretch(void* layout) {
    \\    static_cast<QBoxLayout*>(layout)->addStretch();
    \\}
    \\
    \\void zqt_layout_set_spacing(void* layout, int spacing) {
    \\    static_cast<QLayout*>(layout)->setSpacing(spacing);
    \\}
    \\
    \\void zqt_layout_set_margin(void* layout, int margin) {
    \\    static_cast<QLayout*>(layout)->setContentsMargins(margin, margin, margin, margin);
    \\}
    \\
    \\} // extern "C"
;

/// Write the Qt C++ wrapper to the build temp directory.
fn writeQtWrapper(tmp_dir_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const cpp_path = try std.fmt.allocPrint(alloc, "{s}/_zcythe_qt.cpp", .{tmp_dir_path});
    const f = try std.fs.createFileAbsolute(cpp_path, .{});
    defer f.close();
    try f.writeAll(_zqt_wrapper_cpp);
    return cpp_path;
}

/// Compile the Qt C++ wrapper. Returns the path to the .o file.
fn compileQtWrapper(tmp_dir_path: []const u8, cpp_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const obj_path = try std.fmt.allocPrint(alloc, "{s}/_zcythe_qt.o", .{tmp_dir_path});
    errdefer alloc.free(obj_path);
    // Get Qt cflags — try Qt6 first, fall back to Qt5
    var cflags_buf: ?[]u8 = null;
    defer if (cflags_buf) |b| alloc.free(b);
    for (&[_][]const u8{ "Qt6Widgets", "Qt5Widgets" }) |pkg| {
        const r = std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "pkg-config", "--cflags", pkg },
        }) catch continue;
        defer alloc.free(r.stdout);
        defer alloc.free(r.stderr);
        if (r.term == .Exited and r.term.Exited == 0) {
            const s = std.mem.trim(u8, r.stdout, " \n\r\t");
            if (s.len > 0) { cflags_buf = try alloc.dupe(u8, s); break; }
        }
    }
    const cflags = cflags_buf orelse "";
    // Split cflags into individual args
    var argv = std.ArrayListUnmanaged([]const u8).empty;
    defer argv.deinit(alloc);
    // -DQT_NO_VERSION_TAGGING suppresses Qt5's .qtversion section which emits
    // R_X86_64_GOT64 relocations that Zig's LLD cannot handle.
    try argv.appendSlice(alloc, &.{ "g++", "-std=c++17", "-DQT_NO_VERSION_TAGGING", "-c", "-o", obj_path, cpp_path });
    var it = std.mem.tokenizeScalar(u8, cflags, ' ');
    while (it.next()) |tok| try argv.append(alloc, tok);
    const result = try std.process.Child.run(.{ .allocator = alloc, .argv = argv.items });
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Qt wrapper compile error:\n{s}\n", .{result.stderr});
        return error.QtCompileFailed;
    }
    return obj_path;
}

/// Get Qt linker flags from pkg-config (libs only).
fn qtLibFlags(alloc: std.mem.Allocator) ![]const u8 {
    for (&[_][]const u8{ "Qt6Widgets", "Qt5Widgets" }) |pkg| {
        const r = std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "pkg-config", "--libs", pkg },
        }) catch continue;
        defer alloc.free(r.stdout);
        defer alloc.free(r.stderr);
        if (r.term == .Exited and r.term.Exited == 0) {
            const s = std.mem.trim(u8, r.stdout, " \n\r\t");
            if (s.len > 0) return try alloc.dupe(u8, s);
        }
    }
    return "";
}

/// Build a Qt program using a two-step process:
///   1. zig build-obj  → main.o  (avoids Zig LLD seeing Qt's GOT64 relocations)
///   2. g++ main.o _zcythe_qt.o $(pkg-config --libs Qt*Widgets) -o <out>
fn buildQtBinary(
    zig_src_path: []const u8,
    qt_obj_path: []const u8,
    out_binary: []const u8,
    tmp_dir: []const u8,
    alloc: std.mem.Allocator,
) !void {
    // ── Step 1: zig build-obj ────────────────────────────────────────────
    const zig_obj = try std.fmt.allocPrint(alloc, "{s}/_main.o", .{tmp_dir});
    {
        const r = try std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "zig", "build-obj", zig_src_path, try std.fmt.allocPrint(alloc, "-femit-bin={s}", .{zig_obj}) },
        });
        if (r.term != .Exited or r.term.Exited != 0) {
            std.debug.print("zig build-obj error:\n{s}\n", .{r.stderr});
            return error.ZigObjFailed;
        }
    }
    // ── Step 2: g++ link ─────────────────────────────────────────────────
    const qt_libs = try qtLibFlags(alloc);
    var argv = std.ArrayListUnmanaged([]const u8).empty;
    defer argv.deinit(alloc);
    try argv.appendSlice(alloc, &.{ "g++", zig_obj, qt_obj_path, "-o", out_binary });
    var it = std.mem.tokenizeScalar(u8, qt_libs, ' ');
    while (it.next()) |tok| try argv.append(alloc, tok);
    try argv.appendSlice(alloc, &.{ "-lstdc++", "-lc" });
    const r2 = try std.process.Child.run(.{ .allocator = alloc, .argv = argv.items });
    if (r2.term != .Exited or r2.term.Exited != 0) {
        std.debug.print("g++ link error:\n{s}\n", .{r2.stderr});
        return error.QtLinkFailed;
    }
}

/// Stand-alone compiler: transpile one or more .zcy files into a temp dir,
/// compile with zig build-exe, place the binary at ./<name>, then clean up.
/// The first file in `input_files` is the entry point (must contain @main).
fn cmdSac(alloc: std.mem.Allocator, name: []const u8, input_files: []const []const u8) !void {
    if (input_files.len == 0) {
        try std.fs.File.stderr().writeAll("error: sac requires at least one .zcy file\n");
        std.process.exit(1);
    }

    const cwd = std.fs.cwd();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    // ── 1. Resolve all input paths to absolute ───────────────────────────
    const abs_paths = try alloc.alloc([]u8, input_files.len);
    defer {
        for (abs_paths) |p| alloc.free(p);
        alloc.free(abs_paths);
    }
    for (input_files, 0..) |f, i| {
        abs_paths[i] = cwd.realpathAlloc(alloc, f) catch |err| {
            const msg = try std.fmt.allocPrint(alloc,
                "error: cannot find '{s}': {s}\n", .{ f, @errorName(err) });
            defer alloc.free(msg);
            try std.fs.File.stderr().writeAll(msg);
            std.process.exit(1);
        };
    }

    // ── 2. Find common ancestor directory ────────────────────────────────
    var common_dir: []const u8 = std.fs.path.dirname(abs_paths[0]) orelse "/";
    for (abs_paths[1..]) |ap| {
        const d = std.fs.path.dirname(ap) orelse "/";
        common_dir = commonDirPrefix(common_dir, d);
    }

    // ── 3. Create temp dir ────────────────────────────────────────────────
    var rng: [8]u8 = undefined;
    std.crypto.random.bytes(&rng);
    const rng_id = std.mem.readInt(u64, &rng, .little);
    const tmp_base = std.posix.getenv("TMPDIR") orelse "/tmp";
    const tmp_path = try std.fmt.allocPrint(alloc, "{s}/zcy-sac-{x}", .{ tmp_base, rng_id });
    defer alloc.free(tmp_path);
    try std.fs.makeDirAbsolute(tmp_path);

    // ── 4. Transpile each .zcy file into temp dir ─────────────────────────
    var main_zig_abs: []u8 = undefined;
    var sac_uses_omp:    bool = false;
    var sac_uses_sodium: bool = false;
    var sac_uses_sqlite: bool = false;
    var sac_uses_qt:     bool = false;
    var sac_uses_xi:     bool = false;
    {
        var tmp_dir = try std.fs.openDirAbsolute(tmp_path, .{});
        defer tmp_dir.close();

        for (input_files, 0..) |zcy_path, i| {
            const abs = abs_paths[i];

            // Compute path relative to common ancestor
            const after = abs[common_dir.len..];
            const rel_zcy = if (after.len > 0 and after[0] == '/') after[1..] else after;

            if (!std.mem.endsWith(u8, rel_zcy, ".zcy")) {
                const msg = try std.fmt.allocPrint(alloc,
                    "error: '{s}' is not a .zcy file\n", .{zcy_path});
                defer alloc.free(msg);
                try std.fs.File.stderr().writeAll(msg);
                std.fs.deleteTreeAbsolute(tmp_path) catch {};
                std.process.exit(1);
            }

            // e.g. "a/b/foo.zcy" → "a/b/foo.zig"
            const stem = rel_zcy[0 .. rel_zcy.len - 4];
            const out_rel = try std.fmt.allocPrint(alloc, "{s}.zig", .{stem});
            defer alloc.free(out_rel);

            // Ensure parent directories exist inside temp
            if (std.fs.path.dirname(out_rel)) |parent|
                try tmp_dir.makePath(parent);

            // Read source
            const src = cwd.readFileAlloc(alloc, zcy_path, 1 << 20) catch |err| {
                const msg = try std.fmt.allocPrint(alloc,
                    "error: cannot read '{s}': {s}\n", .{ zcy_path, @errorName(err) });
                defer alloc.free(msg);
                try std.fs.File.stderr().writeAll(msg);
                std.fs.deleteTreeAbsolute(tmp_path) catch {};
                std.process.exit(1);
            };
            defer alloc.free(src);

            // Transpile
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            var p = Zcythe.parser.Parser.init(aa, src);
            const root = p.parse() catch |err| {
                const loc = p.current.loc;
                const tok = p.current.lexeme;
                const msg = try std.fmt.allocPrint(alloc,
                    "error: parse error in '{s}' at {d}:{d} near '{s}'\n",
                    .{ zcy_path, loc.line, loc.col, tok });
                defer alloc.free(msg);
                try std.fs.File.stderr().writeAll(msg);
                std.fs.deleteTreeAbsolute(tmp_path) catch {};
                return err;
            };
            var cg = Zcythe.codegen.CodeGen.init(buf.writer(aa).any());
            cg.emit(root) catch |err| {
                std.fs.deleteTreeAbsolute(tmp_path) catch {};
                return err;
            };

            {
                const out_file = try tmp_dir.createFile(out_rel, .{});
                defer out_file.close();
                try out_file.writeAll(buf.items);
            }

            // First file is the entry point
            if (i == 0) {
                main_zig_abs = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ tmp_path, out_rel });
                sac_uses_omp     = if (root.* == .program) Zcythe.codegen.programUsesOmp(root.program)     else false;
                sac_uses_sodium  = if (root.* == .program) Zcythe.codegen.programUsesSodium(root.program)  else false;
                sac_uses_sqlite  = if (root.* == .program) Zcythe.codegen.programUsesSqlite(root.program)  else false;
                sac_uses_qt      = if (root.* == .program) Zcythe.codegen.programUsesQt(root.program)      else false;
                sac_uses_xi      = if (root.* == .program) Zcythe.codegen.programUsesXi(root.program)      else false;
            }
        }
    } // tmp_dir closed here — safe to deleteTree later
    defer alloc.free(main_zig_abs);

    // ── 5. Compile ────────────────────────────────────────────────────────
    //    NativeSysPkg: omp/sodium/sqlite/qt/xi linked via `zig build-exe -l` flags.
    const emit_flag = try std.fmt.allocPrint(alloc, "-femit-bin={s}", .{name});
    defer alloc.free(emit_flag);
    var sac_argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer sac_argv.deinit(alloc);
    try sac_argv.appendSlice(alloc, &.{ "zig", "build-exe", main_zig_abs, emit_flag });
    if (sac_uses_omp or sac_uses_sodium or sac_uses_sqlite or sac_uses_qt or sac_uses_xi)
        try sac_argv.appendSlice(alloc, &.{ "-target", "x86_64-linux-gnu.2.17", "-L/usr/lib", "-I/usr/include" });
    var omp_l_flag: ?[]u8 = null;
    defer if (omp_l_flag) |f| alloc.free(f);
    if (sac_uses_omp) {
        if (gccLibDir(alloc)) |dir| {
            defer alloc.free(dir);
            omp_l_flag = try std.fmt.allocPrint(alloc, "-L{s}", .{dir});
        }
        if (omp_l_flag) |f| try sac_argv.append(alloc, f);
        try sac_argv.appendSlice(alloc, &.{ "-lc", "-lgomp" });
    }
    if (sac_uses_sodium) try sac_argv.appendSlice(alloc, &.{ "-lc", "-lsodium" });
    if (sac_uses_sqlite) try sac_argv.appendSlice(alloc, &.{ "-lc", "-lsqlite3" });
    if (sac_uses_xi) try sac_argv.appendSlice(alloc, &.{ "-lSDL2", "-lSDL2_ttf", "-lSDL2_image", "-lc" });

    var sac_qt_cpp: ?[]u8 = null;
    defer if (sac_qt_cpp) |p| alloc.free(p);
    var sac_qt_obj: ?[]u8 = null;
    defer if (sac_qt_obj) |p| alloc.free(p);
    var sac_qt_link: ?[]const u8 = null;
    defer if (sac_qt_link) |p| if (p.len > 0) alloc.free(p);
    var sac_qt_libcpp: ?[]const u8 = null;
    defer if (sac_qt_libcpp) |p| alloc.free(p);
    var sac_qt_libgccs: ?[]const u8 = null;
    defer if (sac_qt_libgccs) |p| alloc.free(p);
    if (sac_uses_qt) {
        sac_qt_cpp = try writeQtWrapper(tmp_path, alloc);
        sac_qt_obj = try compileQtWrapper(tmp_path, sac_qt_cpp.?, alloc);
        try sac_argv.append(alloc, sac_qt_obj.?);
        sac_qt_link = try qtLibFlags(alloc);
        var qt_it = std.mem.tokenizeScalar(u8, sac_qt_link.?, ' ');
        while (qt_it.next()) |tok| try sac_argv.append(alloc, tok);
        // Link against shared libstdc++ and libgcc_s explicitly — the static
        // archives lack newer symbols needed by Qt C++ code.
        sac_qt_libcpp = gccQueryFile(alloc, "libstdc++.so");
        sac_qt_libgccs = gccQueryFile(alloc, "libgcc_s.so.1");
        if (sac_qt_libcpp) |p| try sac_argv.append(alloc, p) else try sac_argv.append(alloc, "-lstdc++");
        if (sac_qt_libgccs) |p| try sac_argv.append(alloc, p) else try sac_argv.append(alloc, "-lgcc_s");
        try sac_argv.appendSlice(alloc, &.{ "-lc" });
    }

    const compile = std.process.Child.run(.{
        .allocator = alloc,
        .argv = sac_argv.items,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
            std.fs.deleteTreeAbsolute(tmp_path) catch {};
            std.process.exit(1);
        },
        else => {
            std.fs.deleteTreeAbsolute(tmp_path) catch {};
            return err;
        },
    };
    defer alloc.free(compile.stdout);
    defer alloc.free(compile.stderr);
    if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
    if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);

    const exit_code: u8 = switch (compile.term) { .Exited => |c| c, else => 1 };
    std.fs.deleteTreeAbsolute(tmp_path) catch {};

    if (exit_code != 0) {
        try std.fs.File.stderr().writeAll("─── Zcythe ─────────────────────────────────────────────────────\n");
        try std.fs.File.stderr().writeAll("error: compilation failed\n");
        std.process.exit(exit_code);
    }

    std.debug.print("***\n", .{});
    const done = try std.fmt.allocPrint(alloc, "Compiled -> ./{s}\n", .{name});
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
/// Transpile only: .zcy → src/zcyout/*.zig. Does not compile.
fn cmdBuildSrc(alloc: std.mem.Allocator) !void {
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
        const loc = p.current.loc;
        const tok = p.current.lexeme;
        const msg = try std.fmt.allocPrint(alloc,
            "error: failed to parse src/main/zcy/main.zcy at line {d}:{d} near '{s}'\n",
            .{ loc.line, loc.col, tok });
        defer alloc.free(msg);
        try std.fs.File.stderr().writeAll(msg);
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

    try std.fs.File.stdout().writeAll("Transpile complete.\n");
}

/// Compile only: src/zcyout → zcy-bin. Parses main.zcy for dep detection
/// but does not regenerate any .zig files.
fn cmdBuildOut(alloc: std.mem.Allocator, name: []const u8) !void {
    const cwd = std.fs.cwd();

    // ── Parse main.zcy for dep detection (no output written) ────────────
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

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    var p = Zcythe.parser.Parser.init(aa, zcy_src);
    const root = p.parse() catch |err| {
        const loc = p.current.loc;
        const tok = p.current.lexeme;
        const msg = try std.fmt.allocPrint(alloc,
            "error: failed to parse src/main/zcy/main.zcy at line {d}:{d} near '{s}'\n",
            .{ loc.line, loc.col, tok });
        defer alloc.free(msg);
        try std.fs.File.stderr().writeAll(msg);
        return err;
    };
    const uses_omp    = if (root.* == .program) Zcythe.codegen.programUsesOmp(root.program)    else false;
    const uses_sodium = if (root.* == .program) Zcythe.codegen.programUsesSodium(root.program) else false;
    const uses_sqlite = if (root.* == .program) Zcythe.codegen.programUsesSqlite(root.program) else false;
    const uses_qt     = if (root.* == .program) Zcythe.codegen.programUsesQt(root.program)     else false;
    const uses_xi     = if (root.* == .program) Zcythe.codegen.programUsesXi(root.program)     else false;

    // ── Detect ZcytheAddLinkPkg deps ─────────────────────────────────────
    try cwd.makePath("zcy-bin");
    const maybe_toml = cwd.readFileAlloc(alloc, "zcypm.toml", 1 << 20) catch |err| switch (err) {
        error.FileNotFound => @as(?[]u8, null),
        else => return err,
    };
    defer if (maybe_toml) |t| alloc.free(t);
    const has_raylib = if (maybe_toml) |t| tomlDepIsPresent(t, "raylib") else false;

    // ── Compile ───────────────────────────────────────────────────────────
    const exit_code: u8 = blk: {
        if (has_raylib) {
            try genRaylibBuildFiles(alloc, cwd, name);
            const compile = std.process.Child.run(.{
                .allocator = alloc,
                .argv = &.{ "zig", "build" },
            }) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
                    std.process.exit(1);
                },
                else => return err,
            };
            defer alloc.free(compile.stdout);
            defer alloc.free(compile.stderr);
            if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
            if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);
            const code: u8 = switch (compile.term) { .Exited => |c| c, else => 1 };
            if (code == 0) {
                const src_bin = try std.fmt.allocPrint(alloc, "zig-out/bin/{s}", .{name});
                defer alloc.free(src_bin);
                const dst_bin = try std.fmt.allocPrint(alloc, "zcy-bin/{s}", .{name});
                defer alloc.free(dst_bin);
                try cwd.copyFile(src_bin, cwd, dst_bin, .{});
                cwd.deleteTree("zig-out") catch {};
            }
            break :blk code;
        } else {
            const emit_flag = try std.fmt.allocPrint(alloc, "-femit-bin=zcy-bin/{s}", .{name});
            defer alloc.free(emit_flag);
            var argv: std.ArrayListUnmanaged([]const u8) = .empty;
            defer argv.deinit(alloc);
            try argv.appendSlice(alloc, &.{ "zig", "build-exe", "src/zcyout/main.zig", emit_flag });
            if (uses_omp or uses_sodium or uses_sqlite or uses_qt or uses_xi)
                try argv.appendSlice(alloc, &.{ "-target", "x86_64-linux-gnu.2.17", "-L/usr/lib", "-I/usr/include" });
            var omp_l_flag: ?[]u8 = null;
            defer if (omp_l_flag) |f| alloc.free(f);
            if (uses_omp) {
                if (gccLibDir(alloc)) |dir| {
                    defer alloc.free(dir);
                    omp_l_flag = try std.fmt.allocPrint(alloc, "-L{s}", .{dir});
                }
                if (omp_l_flag) |f| try argv.append(alloc, f);
                try argv.appendSlice(alloc, &.{ "-lc", "-lgomp" });
            }
            if (uses_sodium) try argv.appendSlice(alloc, &.{ "-lc", "-lsodium" });
            if (uses_sqlite) try argv.appendSlice(alloc, &.{ "-lc", "-lsqlite3" });
            if (uses_xi) try argv.appendSlice(alloc, &.{ "-lSDL2", "-lSDL2_ttf", "-lSDL2_image", "-lc" });
            var qt_tmp2: ?[]u8 = null;
            defer if (qt_tmp2) |qt_p| { std.fs.deleteTreeAbsolute(qt_p) catch {}; alloc.free(qt_p); };
            var qt_cpp_path: ?[]u8 = null;
            defer if (qt_cpp_path) |qt_cp| alloc.free(qt_cp);
            var qt_obj_path: ?[]u8 = null;
            defer if (qt_obj_path) |qt_op| alloc.free(qt_op);
            var qt_link_str: ?[]const u8 = null;
            defer if (qt_link_str) |qt_ls| if (qt_ls.len > 0) alloc.free(qt_ls);
            var qt_libcpp: ?[]const u8 = null;
            defer if (qt_libcpp) |qt_lc| alloc.free(qt_lc);
            var qt_libgccs: ?[]const u8 = null;
            defer if (qt_libgccs) |qt_lg| alloc.free(qt_lg);
            if (uses_qt) {
                var rng2: [8]u8 = undefined;
                std.crypto.random.bytes(&rng2);
                const rng_id2 = std.mem.readInt(u64, &rng2, .little);
                const tmp_base2 = std.posix.getenv("TMPDIR") orelse "/tmp";
                const tmp2 = try std.fmt.allocPrint(alloc, "{s}/zcy-qt-{x}", .{ tmp_base2, rng_id2 });
                qt_tmp2 = tmp2;
                try std.fs.makeDirAbsolute(tmp2);
                qt_cpp_path = try writeQtWrapper(tmp2, alloc);
                qt_obj_path = try compileQtWrapper(tmp2, qt_cpp_path.?, alloc);
                try argv.append(alloc, qt_obj_path.?);
                qt_link_str = try qtLibFlags(alloc);
                var qt_it = std.mem.tokenizeScalar(u8, qt_link_str.?, ' ');
                while (qt_it.next()) |tok| try argv.append(alloc, tok);
                qt_libcpp = gccQueryFile(alloc, "libstdc++.so");
                qt_libgccs = gccQueryFile(alloc, "libgcc_s.so.1");
                if (qt_libcpp) |qt_lc| try argv.append(alloc, qt_lc) else try argv.append(alloc, "-lstdc++");
                if (qt_libgccs) |qt_lg| try argv.append(alloc, qt_lg) else try argv.append(alloc, "-lgcc_s");
                try argv.appendSlice(alloc, &.{ "-lc" });
            }
            const compile = std.process.Child.run(.{
                .allocator = alloc,
                .argv = argv.items,
            }) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
                    std.process.exit(1);
                },
                else => return err,
            };
            defer alloc.free(compile.stdout);
            defer alloc.free(compile.stderr);
            if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
            if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);
            break :blk switch (compile.term) { .Exited => |c| c, else => 1 };
        }
    };

    if (exit_code != 0) {
        try std.fs.File.stderr().writeAll("─── Zcythe ─────────────────────────────────────────────────────\n");
        try std.fs.File.stderr().writeAll("error: compilation failed\n");
        std.process.exit(exit_code);
    }
    std.debug.print("***\n", .{});
    try std.fs.File.stdout().writeAll("Build successful.\n");
}

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
        const loc = p.current.loc;
        const tok = p.current.lexeme;
        const msg2 = try std.fmt.allocPrint(alloc,
            "error: failed to parse src/main/zcy/main.zcy at line {d}:{d} near '{s}'\n",
            .{ loc.line, loc.col, tok });
        defer alloc.free(msg2);
        try std.fs.File.stderr().writeAll(msg2);
        return err;
    };
    var cg = Zcythe.codegen.CodeGen.init(buf.writer(aa).any());
    try cg.emit(root);
    const zig_src = buf.items;
    const uses_omp     = if (root.* == .program) Zcythe.codegen.programUsesOmp(root.program)     else false;
    const uses_sodium  = if (root.* == .program) Zcythe.codegen.programUsesSodium(root.program)  else false;
    const uses_sqlite  = if (root.* == .program) Zcythe.codegen.programUsesSqlite(root.program)  else false;
    const uses_qt      = if (root.* == .program) Zcythe.codegen.programUsesQt(root.program)      else false;
    const uses_xi      = if (root.* == .program) Zcythe.codegen.programUsesXi(root.program)      else false;

    // ── 3. Write generated Zig to src/zcyout/main.zig ───────────────────
    {
        const out_file = try cwd.createFile("src/zcyout/main.zig", .{});
        defer out_file.close();
        try out_file.writeAll(zig_src);
    }

    // ── 3b. Transpile all other .zcy files in src/main/zcy/ ─────────────
    try transpileZcyDir(alloc, aa, cwd, "src/main/zcy", "src/zcyout", "");

    // ── 4. Detect deps and choose compile strategy ────────────────────────
    //
    //    Two package categories:
    //      NativeSysPkg     — @zcy.omp / @zcy.sodium / @zcy.sqlite / @zcy.qt
    //                         Detected by scanning AST; linked via -l flags.
    //                         No zcypm.toml entry required.
    //      ZcytheAddLinkPkg — @zcy.raylib / owner/repo packages
    //                         Registered in zcypm.toml via `zcy add`.
    //                         Stored under zcy-pkgs/; uses `zig build`.
    try cwd.makePath("zcy-bin");

    // Read zcypm.toml to check for ZcytheAddLinkPkg dependencies.
    const maybe_toml = cwd.readFileAlloc(alloc, "zcypm.toml", 1 << 20) catch |err| switch (err) {
        error.FileNotFound => @as(?[]u8, null),
        else => return err,
    };
    defer if (maybe_toml) |t| alloc.free(t);
    const has_raylib = if (maybe_toml) |t| tomlDepIsPresent(t, "raylib") else false;

    const exit_code: u8 = blk: {
        if (has_raylib) {
            // ── 4a. ZcytheAddLinkPkg path: raylib — generate build files, run `zig build` ──
            try genRaylibBuildFiles(alloc, cwd, name);
            const compile = std.process.Child.run(.{
                .allocator = alloc,
                .argv = &.{ "zig", "build" },
            }) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
                    std.process.exit(1);
                },
                else => return err,
            };
            defer alloc.free(compile.stdout);
            defer alloc.free(compile.stderr);
            if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
            if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);
            const code: u8 = switch (compile.term) { .Exited => |c| c, else => 1 };
            if (code == 0) {
                // Copy zig-out/bin/<name> → zcy-bin/<name>
                const src_bin = try std.fmt.allocPrint(alloc, "zig-out/bin/{s}", .{name});
                defer alloc.free(src_bin);
                const dst_bin = try std.fmt.allocPrint(alloc, "zcy-bin/{s}", .{name});
                defer alloc.free(dst_bin);
                try cwd.copyFile(src_bin, cwd, dst_bin, .{});
                cwd.deleteTree("zig-out") catch {};
            }
            break :blk code;
        } else {
            // ── 4b. NativeSysPkg path: `zig build-exe` + -l flags ────────
            const emit_flag = try std.fmt.allocPrint(alloc, "-femit-bin=zcy-bin/{s}", .{name});
            defer alloc.free(emit_flag);
            var argv: std.ArrayListUnmanaged([]const u8) = .empty;
            defer argv.deinit(alloc);
            try argv.appendSlice(alloc, &.{ "zig", "build-exe", "src/zcyout/main.zig", emit_flag });
            if (uses_omp or uses_sodium or uses_sqlite or uses_qt or uses_xi)
                try argv.appendSlice(alloc, &.{ "-target", "x86_64-linux-gnu.2.17", "-L/usr/lib", "-I/usr/include" });
            var omp_l_flag: ?[]u8 = null;
            defer if (omp_l_flag) |f| alloc.free(f);
            if (uses_omp) {
                if (gccLibDir(alloc)) |dir| {
                    defer alloc.free(dir);
                    omp_l_flag = try std.fmt.allocPrint(alloc, "-L{s}", .{dir});
                }
                if (omp_l_flag) |f| try argv.append(alloc, f);
                try argv.appendSlice(alloc, &.{ "-lc", "-lgomp" });
            }
            if (uses_sodium) try argv.appendSlice(alloc, &.{ "-lc", "-lsodium" });
            if (uses_sqlite) try argv.appendSlice(alloc, &.{ "-lc", "-lsqlite3" });
            if (uses_xi) try argv.appendSlice(alloc, &.{ "-lSDL2", "-lSDL2_ttf", "-lSDL2_image", "-lc" });
            var qt_tmp2: ?[]u8 = null;
            defer if (qt_tmp2) |qt_p| { std.fs.deleteTreeAbsolute(qt_p) catch {}; alloc.free(qt_p); };
            var qt_cpp_path: ?[]u8 = null;
            defer if (qt_cpp_path) |qt_cp| alloc.free(qt_cp);
            var qt_obj_path: ?[]u8 = null;
            defer if (qt_obj_path) |qt_op| alloc.free(qt_op);
            var qt_link_str: ?[]const u8 = null;
            defer if (qt_link_str) |qt_ls| if (qt_ls.len > 0) alloc.free(qt_ls);
            var qt_libcpp: ?[]const u8 = null;
            defer if (qt_libcpp) |qt_lc| alloc.free(qt_lc);
            var qt_libgccs: ?[]const u8 = null;
            defer if (qt_libgccs) |qt_lg| alloc.free(qt_lg);
            if (uses_qt) {
                var rng2: [8]u8 = undefined;
                std.crypto.random.bytes(&rng2);
                const rng_id2 = std.mem.readInt(u64, &rng2, .little);
                const tmp_base2 = std.posix.getenv("TMPDIR") orelse "/tmp";
                const tmp2 = try std.fmt.allocPrint(alloc, "{s}/zcy-qt-{x}", .{ tmp_base2, rng_id2 });
                qt_tmp2 = tmp2; // cleaned up after compile via defer above
                try std.fs.makeDirAbsolute(tmp2);
                qt_cpp_path = try writeQtWrapper(tmp2, alloc);
                qt_obj_path = try compileQtWrapper(tmp2, qt_cpp_path.?, alloc);
                try argv.append(alloc, qt_obj_path.?);
                qt_link_str = try qtLibFlags(alloc);
                var qt_it = std.mem.tokenizeScalar(u8, qt_link_str.?, ' ');
                while (qt_it.next()) |tok| try argv.append(alloc, tok);
                qt_libcpp = gccQueryFile(alloc, "libstdc++.so");
                qt_libgccs = gccQueryFile(alloc, "libgcc_s.so.1");
                if (qt_libcpp) |qt_lc| try argv.append(alloc, qt_lc) else try argv.append(alloc, "-lstdc++");
                if (qt_libgccs) |qt_lg| try argv.append(alloc, qt_lg) else try argv.append(alloc, "-lgcc_s");
                try argv.appendSlice(alloc, &.{ "-lc" });
            }
            const compile = std.process.Child.run(.{
                .allocator = alloc,
                .argv = argv.items,
            }) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
                    std.process.exit(1);
                },
                else => return err,
            };
            defer alloc.free(compile.stdout);
            defer alloc.free(compile.stderr);
            if (compile.stdout.len > 0) try std.fs.File.stdout().writeAll(compile.stdout);
            if (compile.stderr.len > 0) try std.fs.File.stderr().writeAll(compile.stderr);
            break :blk switch (compile.term) { .Exited => |c| c, else => 1 };
        }
    };

    if (exit_code != 0) {
        try std.fs.File.stderr().writeAll("─── Zcythe ─────────────────────────────────────────────────────\n");
        try std.fs.File.stderr().writeAll("error: compilation failed\n");
        std.process.exit(exit_code);
    }
    std.debug.print("***\n", .{});
    try std.fs.File.stdout().writeAll("Build successful.\n");
}

// ═══════════════════════════════════════════════════════════════════════════
//  zcy test
// ═══════════════════════════════════════════════════════════════════════════

/// Run `@test` blocks: transpile then `zig test src/zcyout/main.zig`.
/// If `maybe_file` is non-null, only transpile that single .zcy file (sac-style).
fn cmdTest(alloc: std.mem.Allocator, maybe_file: ?[]const u8) !void {
    _ = maybe_file; // TODO: single-file test mode
    const cwd = std.fs.cwd();

    // ── 1. Read .zcy source ──────────────────────────────────────────────
    const zcy_src = cwd.readFileAlloc(alloc, "src/main/zcy/main.zcy", 10 * 1024 * 1024) catch {
        try std.fs.File.stderr().writeAll("error: could not read src/main/zcy/main.zcy\n");
        std.process.exit(1);
    };
    defer alloc.free(zcy_src);

    // ── 2. Parse + codegen ───────────────────────────────────────────────
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aa = arena.allocator();
    var parser = Zcythe.parser.Parser.init(aa, zcy_src);
    const root = parser.parse() catch |err| {
        const msg2 = try std.fmt.allocPrint(alloc, "parse error: {}\n", .{err});
        defer alloc.free(msg2);
        try std.fs.File.stderr().writeAll(msg2);
        std.process.exit(1);
    };
    var buf = std.ArrayListUnmanaged(u8){};
    var cg = Zcythe.codegen.CodeGen.init(buf.writer(aa).any());
    try cg.emit(root);
    const zig_src = buf.items;

    // ── 3. Write Zig to src/zcyout/main.zig ─────────────────────────────
    try cwd.makePath("src/zcyout");
    var out_file = try cwd.createFile("src/zcyout/main.zig", .{});
    defer out_file.close();
    try out_file.writeAll(zig_src);

    // ── 4. Run zig test ──────────────────────────────────────────────────
    const test_result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "zig", "test", "src/zcyout/main.zig" },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("error: `zig` not found in PATH\n");
            std.process.exit(1);
        },
        else => return err,
    };
    defer alloc.free(test_result.stdout);
    defer alloc.free(test_result.stderr);
    if (test_result.stdout.len > 0) try std.fs.File.stdout().writeAll(test_result.stdout);
    if (test_result.stderr.len > 0) try std.fs.File.stderr().writeAll(test_result.stderr);
    if (test_result.term != .Exited or test_result.term.Exited != 0) {
        std.process.exit(1);
    }
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
