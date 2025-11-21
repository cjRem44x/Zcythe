/// Key Features:
/// - File and Directory Operations
/// - String Manipulation
/// - Random Number Generation
/// - Mathematical Functions
/// - System Commands
/// - Number Parsing
/// - Console I/O
pub const std = @import("std");
pub const print = std.debug.print;
pub const str = []const u8;
pub const random = std.crypto.random;

//=============================================================================
// External Dependencies
//=============================================================================
pub const cstdlib = @cImport(@cInclude("stdlib.h"));

//=============================================================================
// Error Handling
//=============================================================================
/// Error Reporting
/// Prints formatted error messages with the CRZLib prefix
/// Example: liberr("File not found");
pub fn liberr(report: str) void {
    strout("\n@CRZLib(**ERROR**) >> ");
    strout(report);
}

//=============================================================================
// System Operations
//=============================================================================
/// Command Line Arguments
/// Returns an array of command line arguments (excluding program name)
/// Memory must be freed by the caller using allocator.free()
/// Example: const args = try get_args(allocator);
pub fn get_args(allocator: std.mem.Allocator) ![][]const u8 {
    // Get all command line arguments
    var arg_it = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arg_it);

    // Create a dynamic array to store arguments
    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();

    // Skip program name and copy remaining arguments
    for (arg_it[1..]) |arg| {
        const arg_copy = try allocator.dupe(u8, arg);
        try args.append(arg_copy);
    }

    return args.toOwnedSlice();
}

/// System Commands
/// Executes a system command using the C standard library
/// Example: c_system("dir");
pub fn c_system(s: [*c]const u8) void {
    _ = cstdlib.system(s);
}

//=============================================================================
// File System Operations
//=============================================================================
/// File Operations
/// Reads a file and returns its contents as an array of strings (one per line)
/// Memory must be freed by the caller using allocator.free()
/// Example: const lines = try read_file(allocator, "input.txt");
pub fn read_file(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    // Open the file for reading
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // Create a dynamic array to store lines
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    // Set up buffered reading
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    // Read file line by line
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const line_copy = try allocator.dupe(u8, line);
        try lines.append(line_copy);
    }

    return lines.toOwnedSlice();
}

/// File System Checks
/// Returns true if the path points to a file
/// Example: if (is_file("test.txt")) { ... }
pub fn is_file(path: []const u8) bool {
    // Try to get file stats, return false if not a file
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.IsDir => return false,
        else => return false,
    };
    _ = stat;
    return true;
}

/// Directory Checks
/// Returns true if the path points to a directory
/// Example: if (is_dir("folder")) { ... }
pub fn is_dir(path: []const u8) bool {
    // Try to open as directory, return false if not a directory
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    defer dir.close();
    return true;
}

//=============================================================================
// Terminal and OS Operations
//=============================================================================
/// Terminal Commands
/// Executes a command in the terminal and returns its output
/// Example: try term(&[_][]const u8{"dir"});
pub fn term(argv: []const []const u8) !void {
    // Set up arena allocator for command execution
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Execute command and print output
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });

    std.debug.print("{s}\n", .{result.stdout});
}

/// OS-Specific Functions
/// Opens a URL in the default browser (Windows only)
/// Example: open_url("https://example.com");
pub fn open_url(url: []const u8) void {
    term(&[_][]const u8{ "explorer", url }) catch liberr("Failed to open URL!\n");
}

/// Opens a file with the default application (Windows only)
/// Example: open_file("document.pdf");
pub fn open_file(file_path: []const u8) void {
    term(&[_][]const u8{ "explorer", file_path }) catch liberr("Failed to open file!\n");
}

//=============================================================================
// String Operations
//=============================================================================
/// String Operations
/// Compares two strings for equality
/// Example: if (streql("hello", "hello")) { ... }
pub fn streql(s1: []const u8, s2: []const u8) bool {
    return std.mem.eql(u8, s1, s2);
}

/// Concatenates two strings
/// Memory must be freed by the caller using allocator.free()
/// Example: const result = try strcat(allocator, "Hello ", "World");
pub fn strcat(allocator: std.mem.Allocator, s1: []const u8, s2: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &[_][]const u8{ s1, s2 });
}

/// Splits a string based on a pattern
/// Memory must be freed by the caller using allocator.free()
/// Example: const parts = try strsplit("a,b,c", ",");
pub fn strsplit(input: []const u8, pattern: []const u8) ![][]const u8 {
    const allocator = std.heap.page_allocator;
    var results = std.ArrayList([]const u8).init(allocator);
    errdefer results.deinit();

    // Handle empty pattern case
    if (pattern.len == 0) {
        const copy = try allocator.dupe(u8, input);
        try results.append(copy);
        return results.toOwnedSlice();
    }

    // Split string based on pattern
    var start: usize = 0;
    while (std.mem.indexOf(u8, input[start..], pattern)) |pos| {
        if (pos > 0) {
            const substring = try allocator.dupe(u8, input[start .. start + pos]);
            try results.append(substring);
        }
        start += pos + pattern.len;
    }

    // Add remaining part of string
    if (start < input.len) {
        const substring = try allocator.dupe(u8, input[start..]);
        try results.append(substring);
    }

    return results.toOwnedSlice();
}

//=============================================================================
// Random Number Generation
//=============================================================================
/// Random Number Generation
/// Generates random integers in the specified range
/// Example: const num = rng_i32(1, 100);
pub fn rng_i32(min: i32, max: i32) i32 {
    if (max - min > 0) {
        return random.intRangeAtMost(i32, min, max);
    } else {
        return min;
    }
}

/// Generates random 64-bit integers in the specified range
/// Example: const num = rng_i64(1, 1000);
pub fn rng_i64(min: i64, max: i64) i64 {
    if (max - min > 0) {
        return random.intRangeAtMost(i64, min, max);
    } else {
        return min;
    }
}

/// Generates random 128-bit integers in the specified range
/// Example: const num = rng_i128(1, 10000);
pub fn rng_i128(min: i128, max: i128) i128 {
    if (max - min > 0) {
        return random.intRangeAtMost(i128, min, max);
    } else {
        return min;
    }
}

/// Generates random usize values in the specified range
/// Example: const num = rng_usize(0, 100);
pub fn rng_usize(min: usize, max: usize) usize {
    if (max - min > 0) {
        return random.intRangeAtMost(usize, min, max);
    } else {
        return min;
    }
}

//=============================================================================
// Mathematical Functions
//=============================================================================
/// Square root functions using Newton-Raphson method
/// Calculates square root of a 32-bit float
/// Example: const root = sqrt_f32(16.0);
pub fn sqrt_f32(n: f32) f32 {
    // Handle special cases
    if (n < 0) return -1;
    if (n == 0) return 0;
    if (n == 1) return 1;

    // Initial guess
    var guess = n * 0.5;
    var prev_guess: f32 = 0;
    const tolerance = 1e-6;

    // Newton-Raphson iteration
    while (@abs(guess - prev_guess) > tolerance) {
        prev_guess = guess;
        guess = (guess + n / guess) * 0.5;
    }

    return guess;
}

/// Calculates square root of a 64-bit float
/// Example: const root = sqrt_f64(16.0);
pub fn sqrt_f64(n: f64) f64 {
    // Handle special cases
    if (n < 0) return -1;
    if (n == 0) return 0;
    if (n == 1) return 1;

    // Initial guess
    var guess = n * 0.5;
    var prev_guess: f64 = 0;
    const tolerance = 1e-10;

    // Newton-Raphson iteration
    while (@abs(guess - prev_guess) > tolerance) {
        prev_guess = guess;
        guess = (guess + n / guess) * 0.5;
    }

    return guess;
}

/// Calculates square root of a 128-bit float
/// Example: const root = sqrt_f128(16.0);
pub fn sqrt_f128(n: f128) f128 {
    // Handle special cases
    if (n < 0) return -1;
    if (n == 0) return 0;
    if (n == 1) return 1;

    // Initial guess
    var guess = n * 0.5;
    var prev_guess: f128 = 0;
    const tolerance = 1e-30;

    // Newton-Raphson iteration
    while (@abs(guess - prev_guess) > tolerance) {
        prev_guess = guess;
        guess = (guess + n / guess) * 0.5;
    }

    return guess;
}

/// Helper function for absolute value
/// Returns the absolute value of a 64-bit float
/// Example: const abs = abs_f64(-42.0);
pub fn abs_f64(n: f64) f64 {
    if (n < 0) return -n;
    return n;
}

/// Inverse square root functions using fast inverse square root algorithm
/// Calculates inverse square root of a 32-bit float
/// Example: const inv = inv_sqrt_f32(16.0);
pub fn inv_sqrt_f32(x: f32) f32 {
    // Handle special cases
    if (x < 0.0) return 0.0;
    if (x == 0.0) return 0.0;
    if (x == 1.0) return 1.0;

    // Fast inverse square root algorithm
    const half = 0.5 * x;
    var i: u32 = @bitCast(x);
    i = 0x5f3759df - (i >> 1);
    var y: f32 = @bitCast(i);
    y = y * (1.5 - (half * y * y)); // One Newton-Raphson iteration
    return y;
}

/// Calculates inverse square root of a 64-bit float
/// Example: const inv = inv_sqrt_f64(16.0);
pub fn inv_sqrt_f64(n: f64) f64 {
    // Handle special cases
    if (n <= 0) return 0;
    if (n == 1) return 1;

    // Fast inverse square root algorithm
    const x2 = n * 0.5;
    const threehalfs = 1.5;
    var i = @as(i64, @bitCast(n));
    i = 0x5fe6eb50c7b537a9 - (i >> 1);
    var y = @as(f64, @bitCast(i));
    y = y * (threehalfs - (x2 * y * y));
    y = y * (threehalfs - (x2 * y * y));

    return y;
}

/// Calculates inverse square root of a 128-bit float
/// Example: const inv = inv_sqrt_f128(16.0);
pub fn inv_sqrt_f128(n: f128) f128 {
    // Handle special cases
    if (n <= 0) return 0;
    if (n == 1) return 1;

    // Fast inverse square root algorithm
    const x2 = n * 0.5;
    const threehalfs = 1.5;
    var i = @as(i128, @bitCast(n));
    i = 0x5fe6eb50c7b537a9 - (i >> 1);
    var y = @as(f128, @bitCast(i));
    y = y * (threehalfs - (x2 * y * y));
    y = y * (threehalfs - (x2 * y * y));
    y = y * (threehalfs - (x2 * y * y));

    return y;
}

// Computes the sine of a floating-point number (x) using the Maclaurin series expansion.
// sin(x) ≈ x - x^3/3! + x^5/5! - x^7/7! + ... (up to n terms)
pub fn sin_f32(x: f32) f32 {
    // Number of terms in the series expansion, affecting precision
    const n = 15;

    // The first term in the Maclaurin series is x itself
    var t: f32 = x;
    var sin: f32 = t; // Initialize result with the first term
    var a: f32 = 1; // Factorial tracking variable (starting at 1)

    // Loop to compute the subsequent terms in the series
    for (0..n) |_| {
        // Compute the next term: (-x^2) / ((2a) * (2a + 1))
        // This represents the factorial denominator and sign alternation
        const mul = -x * x / ((2 * a) * (2 * a + 1));

        // Multiply the previous term by mul to get the next term
        t *= mul;

        // Add the computed term to the sine sum
        sin += t;

        // Increment a for the next factorial calculation
        a += 1;
    }

    // Return the approximated sine value
    return sin;
}

// Computes the cosine of a floating-point number (x) using the Maclaurin series expansion.
// cos(x) ≈ 1 - x^2/2! + x^4/4! - x^6/6! + ... (up to n terms)
pub fn cos_f32(x: f32) f32 {
    // Number of terms in the series expansion, affecting precision
    const n = 15;

    // The first term in the Maclaurin series is 1
    var t: f32 = 1;
    var cos: f32 = t; // Initialize result with the first term
    var a: f32 = 1; // Factorial tracking variable (starting at 1)

    // Loop to compute the subsequent terms in the series
    for (0..n) |_| {
        // Compute the next term: (-x^2) / ((2a) * (2a - 1))
        // This represents the factorial denominator and sign alternation
        const mul = -x * x / ((2 * a) * (2 * a - 1));

        // Multiply the previous term by mul to get the next term
        t *= mul;

        // Add the computed term to the cosine sum
        cos += t;

        // Increment a for the next factorial calculation
        a += 1;
    }

    // Return the approximated cosine value
    return cos;
}

// Computes the sine of a floating-point number (x) using the Maclaurin series expansion.
// sin(x) ≈ x - x^3/3! + x^5/5! - x^7/7! + ... (up to n terms)
pub fn sin_f64(x: f64) f64 {
    // Number of terms in the series expansion, affecting precision
    const n = 15;

    // The first term in the Maclaurin series is x itself
    var t: f64 = x;
    var sin: f64 = t; // Initialize result with the first term
    var a: f64 = 1; // Factorial tracking variable (starting at 1)

    // Loop to compute the subsequent terms in the series
    for (0..n) |_| {
        // Compute the next term: (-x^2) / ((2a) * (2a + 1))
        // This represents the factorial denominator and sign alternation
        const mul = -x * x / ((2 * a) * (2 * a + 1));

        // Multiply the previous term by mul to get the next term
        t *= mul;

        // Add the computed term to the sine sum
        sin += t;

        // Increment a for the next factorial calculation
        a += 1;
    }

    // Return the approximated sine value
    return sin;
}

// Computes the cosine of a floating-point number (x) using the Maclaurin series expansion.
// cos(x) ≈ 1 - x^2/2! + x^4/4! - x^6/6! + ... (up to n terms)
pub fn cos_f64(x: f64) f64 {
    // Number of terms in the series expansion, affecting precision
    const n = 15;

    // The first term in the Maclaurin series is 1
    var t: f64 = 1;
    var cos: f64 = t; // Initialize result with the first term
    var a: f64 = 1; // Factorial tracking variable (starting at 1)

    // Loop to compute the subsequent terms in the series
    for (0..n) |_| {
        // Compute the next term: (-x^2) / ((2a) * (2a - 1))
        // This represents the factorial denominator and sign alternation
        const mul = -x * x / ((2 * a) * (2 * a - 1));

        // Multiply the previous term by mul to get the next term
        t *= mul;

        // Add the computed term to the cosine sum
        cos += t;

        // Increment a for the next factorial calculation
        a += 1;
    }

    // Return the approximated cosine value
    return cos;
}

/// Power function
/// Calculates x raised to the power of exp
/// Example: const result = pow(2, 3); // returns 8
pub fn pow(x: anytype, exp: usize) @TypeOf(x) {
    if (exp == 0) {
        return @as(@TypeOf(x), 1);
    }

    var y = x;
    for (0..exp - 1) |_| {
        y *= x;
    }

    return y;
}

//=============================================================================
// Console I/O Operations
//=============================================================================
/// Console Output
/// Prints a string without a newline
/// Example: strout("Hello ");
pub fn strout(s: []const u8) void {
    print("{s}", .{s});
}

/// Prints a string with a newline
/// Example: log("Hello World");
pub fn log(s: []const u8) void {
    print("{s}\n", .{s});
}
//
pub fn logn(x: anytype) void {
    print("{}\n", .{x});
}

/// Console Input
/// Reads a line from stdin with a prompt
/// Example: var buf: [256]u8 = undefined;
///          const input = try cin(&buf, "Enter text: ");
pub fn cin(buf: []u8, prompt: []const u8) ![]const u8 {
    const stdin = std.io.getStdIn().reader();
    strout(prompt);
    const line = (try stdin.readUntilDelimiterOrEof(buf, '\n')) orelse return "";
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trim(u8, line, "\r");
    } else {
        return line;
    }
}

//=============================================================================
// Number Parsing
//=============================================================================
/// String to Integer Conversion
/// Converts string to i8, returns 0 if parsing fails
/// Example: const num = str_i8("42");
pub fn str_i8(s: []const u8) i8 {
    return std.fmt.parseInt(i8, s, 10) catch 0;
}

/// Converts string to i16, returns 0 if parsing fails
/// Example: const num = str_i16("42");
pub fn str_i16(s: []const u8) i16 {
    return std.fmt.parseInt(i16, s, 10) catch 0;
}

/// Converts string to i32, returns 0 if parsing fails
/// Example: const num = str_i32("42");
pub fn str_i32(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

/// Converts string to i64, returns 0 if parsing fails
/// Example: const num = str_i64("42");
pub fn str_i64(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch 0;
}

/// Converts string to i128, returns 0 if parsing fails
/// Example: const num = str_i128("42");
pub fn str_i128(s: []const u8) i128 {
    return std.fmt.parseInt(i128, s, 10) catch 0;
}

/// String to Float Conversion
/// Converts string to f32, returns 0.0 if parsing fails
/// Example: const num = str_f32("42.5");
pub fn str_f32(s: []const u8) f32 {
    return std.fmt.parseFloat(f32, s) catch 0.0;
}

/// Converts string to f64, returns 0.0 if parsing fails
/// Example: const num = str_f64("42.5");
pub fn str_f64(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0.0;
}

/// Converts string to f128, returns 0.0 if parsing fails
/// Example: const num = str_f128("42.5");
pub fn str_f128(s: []const u8) f128 {
    return std.fmt.parseFloat(f128, s) catch 0.0;
}

pub fn sleep_ms(ms: u64) void {
    std.Thread.sleep(ms * 1_000_000);
}

pub fn sleep_sec(sec: u64) void {
    std.Thread.sleep(sec * 1_000_000_000);
}
