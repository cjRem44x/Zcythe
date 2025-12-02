const std = @import("std");
const m = @import("src/main.zig");
const zcy_asm_core = @import("src/zcy_asm_core.zig");
const exp = std.testing.expect;

pub fn main() !void {
    try test_zcy_asm_core_LDD();
}

pub fn test_src_scan() !void {
    var param = [_][]const u8{ "build", "zcy_main.zcy" };
    try m.proc_args(&param);

    std.debug.print("path = {s}\n", .{m.zcy_src_file_path});
}

pub fn test_src_input() void {
    var param = [_][]const u8{ "build", "run", "main.zcy" };
    m.proc_args(&param) catch std.process.exit(1);

    std.debug.print("path = {s}\n", .{m.zcy_src_file_path});
}

pub fn test_zcy_asm_core_LDD() !void {
    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 16);
    defer core.deinit();

    const n: i32 = 44;
    core.load_data(core.I32_REG, 0, n);
    std.debug.print("I32_REG[0] = {d}\n", .{core.I32_REG[0]});
    try exp(core.I32_REG[0] == n);

    const PI: f64 = 3.14592654;
    core.load_data(core.F64_REG, 0, PI);
    std.debug.print("F64_REG[0] = {d}\n", .{core.F64_REG[0]});
    try exp(core.F64_REG[0] == PI);
}
