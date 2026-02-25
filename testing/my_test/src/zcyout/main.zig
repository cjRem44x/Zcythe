const std = @import("std");
fn _zcyTypeName(comptime T: type) []const u8 {
    if (T == []const u8) return "str";
    if (T == i32)        return "int";
    if (T == i64)        return "int64";
    if (T == u32)        return "uint";
    if (T == u64)        return "uint64";
    if (T == f32)        return "f32";
    if (T == f64)        return "f64";
    if (T == bool)       return "bool";
    if (T == u8)         return "char";
    return @typeName(T);
}
/// Type-dispatching print with newline.
/// Chooses {s} for byte-slice types ([]u8, []const u8, [:0]u8, etc.)
/// so loop variables over string collections print as text, not bytes.
fn _zcyPrint(val: anytype) void {
    const T = @TypeOf(val);
    if (T == []const u8 or T == []u8 or T == [:0]u8 or T == [:0]const u8) {
        std.debug.print("{s}\n", .{val});
        return;
    }
    std.debug.print("{any}\n", .{val});
}

pub fn main() !void {
    var x: i64 = 0;
    while (x < 99) {
        _zcyPrint(x);
        x += 1;
    }
}
