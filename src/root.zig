//! Zcythe library root  –  src/root.zig
//!
//! Public surface of the Zcythe compiler library.
//! Sub-modules are imported here and re-exported so that consumers only
//! need a single `@import("Zcythe")` to access the full pipeline.

const std = @import("std");

/// Zcythe lexer: converts source text into a flat stream of Tokens.
pub const lexer = @import("lexer.zig");

/// Zcythe AST: node type catalogue produced by the parser.
pub const ast = @import("ast.zig");

/// Zcythe parser: recursive-descent parser that builds an AST from tokens.
pub const parser = @import("parser.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
