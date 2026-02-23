//! Zcythe project-builder test suite — testing/suite.zig
//!
//! Two layers of tests:
//!
//!   CLI tests    — invoke the `zcy` binary as a subprocess and verify
//!                  exit codes, stdout/stderr, and filesystem results.
//!
//!   Transpiler tests — embed .zcy source files at compile time, run them
//!                  through the full lex → parse → codegen pipeline, and
//!                  assert key properties of the emitted Zig source.
//!
//! Run with:  zig build test

const std    = @import("std");
const Zcythe = @import("Zcythe");
const opts   = @import("build_options");

/// Absolute path of the installed `zcy` binary, injected by build.zig.
const ZCY_EXE: []const u8 = opts.zcy_exe;

// ═══════════════════════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Run `src` through lex → parse → codegen; return the emitted Zig source.
/// Memory is owned by the arena allocator provided.
fn transpile(alloc: std.mem.Allocator, src: []const u8) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    var p  = Zcythe.parser.Parser.init(alloc, src);
    const root = try p.parse();
    var cg = Zcythe.codegen.CodeGen.init(buf.writer(alloc).any());
    try cg.emit(root);
    return try buf.toOwnedSlice(alloc);
}

fn has(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// Run `zcy` with `args` from `cwd`; returns the Child.RunResult.
/// Caller must free result.stdout and result.stderr.
fn runZcy(alloc: std.mem.Allocator, cwd: []const u8, args: []const []const u8) !std.process.Child.RunResult {
    var argv = try alloc.alloc([]const u8, 1 + args.len);
    defer alloc.free(argv);
    argv[0] = ZCY_EXE;
    for (args, 1..) |a, i| argv[i] = a;
    return std.process.Child.run(.{
        .allocator = alloc,
        .argv      = argv,
        .cwd       = cwd,
    });
}

// ═══════════════════════════════════════════════════════════════════════════
//  CLI — zcy init
// ═══════════════════════════════════════════════════════════════════════════

test "cli: zcy init creates src/zcyout directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r = try runZcy(std.testing.allocator, tmp_path, &.{"init"});
    defer std.testing.allocator.free(r.stdout);
    defer std.testing.allocator.free(r.stderr);

    try std.testing.expectEqual(@as(u32, 0), r.term.Exited);
    try tmp.dir.access("src/zcyout", .{});
}

test "cli: zcy init creates src/main/zcy/main.zcy" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r = try runZcy(std.testing.allocator, tmp_path, &.{"init"});
    defer std.testing.allocator.free(r.stdout);
    defer std.testing.allocator.free(r.stderr);

    try std.testing.expectEqual(@as(u32, 0), r.term.Exited);
    try tmp.dir.access("src/main/zcy/main.zcy", .{});
}

test "cli: zcy init starter main.zcy parses without error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r = try runZcy(std.testing.allocator, tmp_path, &.{"init"});
    defer std.testing.allocator.free(r.stdout);
    defer std.testing.allocator.free(r.stderr);
    try std.testing.expectEqual(@as(u32, 0), r.term.Exited);

    // Read the generated main.zcy and run it through the pipeline
    const src = try tmp.dir.readFileAlloc(std.testing.allocator, "src/main/zcy/main.zcy", 4096);
    defer std.testing.allocator.free(src);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), src);
    try std.testing.expect(has(out, "pub fn main() !void {"));
}

test "cli: zcy init is idempotent (second run succeeds)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r1 = try runZcy(std.testing.allocator, tmp_path, &.{"init"});
    defer std.testing.allocator.free(r1.stdout);
    defer std.testing.allocator.free(r1.stderr);
    try std.testing.expectEqual(@as(u32, 0), r1.term.Exited);

    const r2 = try runZcy(std.testing.allocator, tmp_path, &.{"init"});
    defer std.testing.allocator.free(r2.stdout);
    defer std.testing.allocator.free(r2.stderr);
    try std.testing.expectEqual(@as(u32, 0), r2.term.Exited);
    try std.testing.expect(has(r2.stderr, "already exists, skipping"));
}

test "cli: zcy with no args exits non-zero and prints usage" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r = try runZcy(std.testing.allocator, tmp_path, &.{});
    defer std.testing.allocator.free(r.stdout);
    defer std.testing.allocator.free(r.stderr);

    try std.testing.expect(r.term.Exited != 0);
    try std.testing.expect(has(r.stderr, "Usage: zcy"));
}

test "cli: zcy unknown command exits non-zero" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const r = try runZcy(std.testing.allocator, tmp_path, &.{"bogus"});
    defer std.testing.allocator.free(r.stdout);
    defer std.testing.allocator.free(r.stderr);

    try std.testing.expect(r.term.Exited != 0);
    try std.testing.expect(has(r.stderr, "unknown command"));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 01 Hello World
// ═══════════════════════════════════════════════════════════════════════════

test "lang 01: preamble and main signature present" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("01_hello_world.zcy"));
    try std.testing.expect(has(out, "const std = @import(\"std\");"));
    try std.testing.expect(has(out, "pub fn main() !void {"));
}

test "lang 01: @pl emits debug.print with string format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("01_hello_world.zcy"));
    try std.testing.expect(has(out,
        \\std.debug.print("{s}\n", .{"Hello World"})
    ));
}

test "lang 01: @pf emits debug.print with format and args" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("01_hello_world.zcy"));
    try std.testing.expect(has(out,
        \\std.debug.print("Value: {d}\n", .{42})
    ));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 02 Variables
// ═══════════════════════════════════════════════════════════════════════════

test "lang 02: mutable implicit := becomes var" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("02_variables.zcy"));
    try std.testing.expect(has(out, "var x = 32;"));
}

test "lang 02: immutable implicit :: becomes const" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("02_variables.zcy"));
    try std.testing.expect(has(out, "const PI = 3.145;"));
}

test "lang 02: mutable explicit str maps to []const u8" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("02_variables.zcy"));
    try std.testing.expect(has(out, "var msg: []const u8 = \"hello\";"));
}

test "lang 02: immutable explicit str maps to []const u8" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("02_variables.zcy"));
    try std.testing.expect(has(out, "const NAME: []const u8 = \"Zcythe\";"));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 03 Functions
// ═══════════════════════════════════════════════════════════════════════════

test "lang 03: untyped params become anytype" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("03_functions.zcy"));
    try std.testing.expect(has(out, "fn add(a: anytype, b: anytype)"));
}

test "lang 03: return type inferred as @TypeOf for untyped fn" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("03_functions.zcy"));
    try std.testing.expect(has(out, "@TypeOf(a + b)"));
}

test "lang 03: typed params with explicit return type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("03_functions.zcy"));
    try std.testing.expect(has(out, "fn identity(x: i32) i32 {"));
}

test "lang 03: fn_decl appears before pub fn main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("03_functions.zcy"));
    const fn_pos   = std.mem.indexOf(u8, out, "fn add(").?;
    const main_pos = std.mem.indexOf(u8, out, "pub fn main(").?;
    try std.testing.expect(fn_pos < main_pos);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 04 Arrays
// ═══════════════════════════════════════════════════════════════════════════

test "lang 04: mutable []i32 array becomes [_]i32{...}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("04_arrays.zcy"));
    try std.testing.expect(has(out, "var nums = [_]i32{1, 2, 3};"));
}

test "lang 04: immutable []str array becomes [_][]const u8{...}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("04_arrays.zcy"));
    try std.testing.expect(has(out,
        \\const words = [_][]const u8{"hello", "world"};
    ));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 05 Structs
// ═══════════════════════════════════════════════════════════════════════════

test "lang 05: struct literal emitted correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("05_structs.zcy"));
    try std.testing.expect(has(out, "Point{ .x = 10, .y = 20 }"));
}

test "lang 05: field access emitted correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("05_structs.zcy"));
    try std.testing.expect(has(out, "p.x;"));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transpiler — 06 Operators
// ═══════════════════════════════════════════════════════════════════════════

test "lang 06: arithmetic precedence preserved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("06_operators.zcy"));
    try std.testing.expect(has(out, "var sum = 1 + 2 * 3;"));
}

test "lang 06: && remapped to and" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("06_operators.zcy"));
    try std.testing.expect(has(out, "sum > 5 and sum < 20"));
    try std.testing.expect(!has(out, "&&"));
}

test "lang 06: || remapped to or" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try transpile(arena.allocator(), @embedFile("06_operators.zcy"));
    try std.testing.expect(has(out, "sum == 0 or sum != 6"));
    try std.testing.expect(!has(out, "||"));
}
