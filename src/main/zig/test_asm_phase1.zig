// ZcyASM Phase 1 Instruction Tests
// Comprehensive test suite for all Phase 1 MVP instructions

const std = @import("std");
const zcy_asm_core = @import("src/zcy_asm_core.zig");
const exp = std.testing.expect;

pub fn main() !void {
    std.debug.print("\n=== ZcyASM Phase 1 Instruction Tests ===\n\n", .{});

    try test_data_movement();
    try test_arithmetic();
    try test_io();
    try test_practical_example();

    std.debug.print("\n=== All Tests Passed! ===\n\n", .{});
}

// ========================================
// DATA MOVEMENT TESTS
// ========================================

pub fn test_data_movement() !void {
    std.debug.print("--- Testing Data Movement Instructions ---\n", .{});

    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
    defer core.deinit();

    // Test LDD (Load Data)
    std.debug.print("Testing LDD...\n", .{});
    const x: i32 = 42;
    core.load_data(core.I32_REG, 0, x);
    try exp(core.I32_REG[0] == 42);
    std.debug.print("  ✓ LDD: Loaded 42 into i32r0\n", .{});

    // Test LDI (Load Immediate)
    std.debug.print("Testing LDI...\n", .{});
    core.load_immediate(core.I32_REG, 1, @as(i32, 100));
    try exp(core.I32_REG[1] == 100);
    std.debug.print("  ✓ LDI: Loaded immediate 100 into i32r1\n", .{});

    // Test MOV (Move)
    std.debug.print("Testing MOV...\n", .{});
    core.mov(i32, 2, 0);  // Move i32r0 to i32r2
    try exp(core.I32_REG[2] == 42);
    std.debug.print("  ✓ MOV: Copied i32r0 (42) to i32r2\n", .{});

    // Test STD (Store Data)
    std.debug.print("Testing STD...\n", .{});
    const stored_val = core.store_data(i32, 1);
    try exp(stored_val == 100);
    std.debug.print("  ✓ STD: Retrieved 100 from i32r1\n", .{});

    // Test with floats
    core.load_immediate(core.F64_REG, 0, @as(f64, 3.14159));
    try exp(core.F64_REG[0] == 3.14159);
    std.debug.print("  ✓ LDI: Loaded 3.14159 into f64r0\n", .{});

    std.debug.print("Data Movement Tests: PASSED\n\n", .{});
}

// ========================================
// ARITHMETIC TESTS
// ========================================

pub fn test_arithmetic() !void {
    std.debug.print("--- Testing Arithmetic Instructions ---\n", .{});

    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
    defer core.deinit();

    // Test ADD
    std.debug.print("Testing ADD...\n", .{});
    core.load_immediate(core.I32_REG, 0, @as(i32, 10));
    core.load_immediate(core.I32_REG, 1, @as(i32, 5));
    core.add(i32, 0, 1);  // i32r0 = i32r0 + i32r1
    try exp(core.I32_REG[0] == 15);
    std.debug.print("  ✓ ADD: 10 + 5 = 15\n", .{});

    // Test SUB
    std.debug.print("Testing SUB...\n", .{});
    core.load_immediate(core.I32_REG, 2, @as(i32, 20));
    core.load_immediate(core.I32_REG, 3, @as(i32, 8));
    core.sub(i32, 2, 3);  // i32r2 = i32r2 - i32r3
    try exp(core.I32_REG[2] == 12);
    std.debug.print("  ✓ SUB: 20 - 8 = 12\n", .{});

    // Test MUL
    std.debug.print("Testing MUL...\n", .{});
    core.load_immediate(core.I32_REG, 4, @as(i32, 7));
    core.load_immediate(core.I32_REG, 5, @as(i32, 6));
    core.mul(i32, 4, 5);  // i32r4 = i32r4 * i32r5
    try exp(core.I32_REG[4] == 42);
    std.debug.print("  ✓ MUL: 7 * 6 = 42\n", .{});

    // Test DIV
    std.debug.print("Testing DIV...\n", .{});
    core.load_immediate(core.I32_REG, 6, @as(i32, 100));
    core.load_immediate(core.I32_REG, 7, @as(i32, 4));
    core.div(i32, 6, 7);  // i32r6 = i32r6 / i32r7
    try exp(core.I32_REG[6] == 25);
    std.debug.print("  ✓ DIV: 100 / 4 = 25\n", .{});

    // Test MOD
    std.debug.print("Testing MOD...\n", .{});
    core.load_immediate(core.I32_REG, 8, @as(i32, 17));
    core.load_immediate(core.I32_REG, 9, @as(i32, 5));
    core.mod(i32, 8, 9);  // i32r8 = i32r8 % i32r9
    try exp(core.I32_REG[8] == 2);
    std.debug.print("  ✓ MOD: 17 %% 5 = 2\n", .{});

    // Test INC
    std.debug.print("Testing INC...\n", .{});
    core.load_immediate(core.I32_REG, 10, @as(i32, 99));
    core.inc(i32, 10);  // i32r10++
    try exp(core.I32_REG[10] == 100);
    std.debug.print("  ✓ INC: 99 -> 100\n", .{});

    // Test DEC
    std.debug.print("Testing DEC...\n", .{});
    core.load_immediate(core.I32_REG, 11, @as(i32, 50));
    core.dec(i32, 11);  // i32r11--
    try exp(core.I32_REG[11] == 49);
    std.debug.print("  ✓ DEC: 50 -> 49\n", .{});

    // Test with floats
    std.debug.print("Testing float arithmetic...\n", .{});
    core.load_immediate(core.F64_REG, 0, @as(f64, 10.5));
    core.load_immediate(core.F64_REG, 1, @as(f64, 2.5));
    core.add(f64, 0, 1);
    try exp(core.F64_REG[0] == 13.0);
    std.debug.print("  ✓ ADD (float): 10.5 + 2.5 = 13.0\n", .{});

    core.load_immediate(core.F64_REG, 2, @as(f64, 20.0));
    core.load_immediate(core.F64_REG, 3, @as(f64, 4.0));
    core.div(f64, 2, 3);
    try exp(core.F64_REG[2] == 5.0);
    std.debug.print("  ✓ DIV (float): 20.0 / 4.0 = 5.0\n", .{});

    std.debug.print("Arithmetic Tests: PASSED\n\n", .{});
}

// ========================================
// I/O TESTS
// ========================================

pub fn test_io() !void {
    std.debug.print("--- Testing I/O Instructions ---\n", .{});

    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
    defer core.deinit();

    // Test STROUT
    std.debug.print("Testing STROUT...\n", .{});
    zcy_asm_core._CORE_SYSTEM_.strout("  ✓ STROUT: Hello from ZcyASM!\n");

    // Test FOUT with integers
    std.debug.print("Testing FOUT (integers)...\n", .{});
    core.load_immediate(core.I32_REG, 0, @as(i32, 42));
    std.debug.print("  ", .{});
    core.fout(i32, 0, "✓ FOUT: The answer is {d}\n");

    // Test FOUT with floats
    std.debug.print("Testing FOUT (floats)...\n", .{});
    core.load_immediate(core.F64_REG, 0, @as(f64, 3.14159));
    std.debug.print("  ", .{});
    core.fout(f64, 0, "✓ FOUT: Pi ≈ {d:.2}\n");

    // Test PRINT
    std.debug.print("Testing PRINT...\n", .{});
    core.load_immediate(core.I32_REG, 1, @as(i32, 123));
    std.debug.print("  ✓ PRINT: ", .{});
    core.print(i32, 1);
    std.debug.print("\n", .{});

    // Test PRINTLN
    std.debug.print("Testing PRINTLN...\n", .{});
    core.load_immediate(core.I32_REG, 2, @as(i32, 456));
    std.debug.print("  ✓ PRINTLN: ", .{});
    core.println(i32, 2);

    std.debug.print("I/O Tests: PASSED\n\n", .{});
}

// ========================================
// PRACTICAL EXAMPLE
// ========================================

pub fn test_practical_example() !void {
    std.debug.print("--- Practical Example: Calculate (a + b) * c ---\n", .{});

    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
    defer core.deinit();

    // Simulate: $i32 : a = 10, b = 5, c = 3
    const a: i32 = 10;
    const b: i32 = 5;
    const c: i32 = 3;

    zcy_asm_core._CORE_SYSTEM_.strout("Variables: a=10, b=5, c=3\n");
    zcy_asm_core._CORE_SYSTEM_.strout("Expression: (a + b) * c\n\n");

    // .ldd: i32r0, a
    core.load_data(core.I32_REG, 0, a);
    zcy_asm_core._CORE_SYSTEM_.strout("Step 1: Load a into i32r0\n");
    std.debug.print("  i32r0 = {d}\n", .{core.I32_REG[0]});

    // .ldd: i32r1, b
    core.load_data(core.I32_REG, 1, b);
    zcy_asm_core._CORE_SYSTEM_.strout("Step 2: Load b into i32r1\n");
    std.debug.print("  i32r1 = {d}\n", .{core.I32_REG[1]});

    // .add: i32r0, i32r1  (r0 = a + b)
    core.add(i32, 0, 1);
    zcy_asm_core._CORE_SYSTEM_.strout("Step 3: Add i32r0 + i32r1\n");
    std.debug.print("  i32r0 = {d} (a + b)\n", .{core.I32_REG[0]});

    // .ldd: i32r2, c
    core.load_data(core.I32_REG, 2, c);
    zcy_asm_core._CORE_SYSTEM_.strout("Step 4: Load c into i32r2\n");
    std.debug.print("  i32r2 = {d}\n", .{core.I32_REG[2]});

    // .mul: i32r0, i32r2  (r0 = (a + b) * c)
    core.mul(i32, 0, 2);
    zcy_asm_core._CORE_SYSTEM_.strout("Step 5: Multiply i32r0 * i32r2\n");
    std.debug.print("  i32r0 = {d} ((a + b) * c)\n\n", .{core.I32_REG[0]});

    // Store result
    const result = core.store_data(i32, 0);
    try exp(result == 45);  // (10 + 5) * 3 = 45

    // Print final result
    std.debug.print("Result: ", .{});
    core.fout(i32, 0, "(10 + 5) * 3 = {d}\n");
    zcy_asm_core._CORE_SYSTEM_.strout("✓ Practical Example: PASSED\n\n");
}
