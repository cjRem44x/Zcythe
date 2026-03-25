# Zcythe Language Index

Complete reference of every keyword, builtin, function, type, and CLI command. Entries are sorted alphabetically within each section.

---

## Table of Contents

1. [Keywords](#keywords)
2. [Declaration Sigils](#declaration-sigils)
3. [Operators](#operators)
4. [Primitive Types](#primitive-types)
5. [Composite Type Modifiers](#composite-type-modifiers)
6. [Built-in Functions — `@`](#built-in-functions)
7. [Namespace — `@fs::`](#namespace-fs)
8. [Namespace — `@math::`](#namespace-math)
9. [Namespace — `@kry::`](#namespace-kry)
10. [Namespace — `@fflog::`](#namespace-fflog)
11. [Namespace — `@xi::`](#namespace-xi)
12. [User-Defined Types](#user-defined-types)
13. [Error Handling](#error-handling)
14. [Packages & Imports](#packages--imports)
15. [CLI — `zcy`](#cli--zcy)

---

## Keywords

| Keyword | Category | Description |
|---------|----------|-------------|
| `and` | operator | Logical AND (alias for `&&`) |
| `break` | control flow | Exit the nearest enclosing loop |
| `catch` | error handling | Recover from an error union: fast form `expr catch default`; full form `expr catch \|e\| { arm => { … } }` |
| `cls` | type | Define a class with fields, constructor, destructor, and methods |
| `continue` | control flow | Skip to the next iteration of the nearest loop |
| `dat` | type | Define a plain data record (fields only, no methods) |
| `defer` | resource | Schedule a statement to run at scope exit (LIFO order) |
| `elif` | control flow | Else-if branch in an `if` chain (preferred over `else if`) |
| `else` | control flow | Fallback branch for `if` / `switch` |
| `enum` | type | Define an enumeration, optionally with a backing type |
| `false` | literal | Boolean false |
| `for` | control flow | Iterate over a collection or range |
| `fn` | declaration | Declare a named function |
| `fun` | declaration | Create an anonymous function (lambda) |
| `if` | control flow | Conditional branch |
| `imu` | modifier | Mark a field or pointer as immutable after first write |
| `loop` | control flow | C-style `init, cond, update` loop |
| `not` | operator | Logical NOT (alias for `!`) |
| `null` | literal | Null / absent value for optional return types |
| `NULL` | literal | Null sentinel for heap pointer comparisons |
| `or` | operator | Logical OR (alias for `\|\|`) |
| `omp.for` | concurrency | Parallel range loop (requires `@import(omp = @zcy.openmp)`) |
| `omp.parallel` | concurrency | Parallel region block |
| `ovrd` | type | Override a method from a parent class in `cls` inheritance |
| `pub` | visibility | Mark a field or method as public in `cls` / `struct` |
| `ret` | control flow | Return a value from the current function |
| `struct` | type | Define a struct with fields and methods (no inheritance) |
| `switch` | control flow | Pattern-match a value against arms; `_` is the wildcard |
| `true` | literal | Boolean true |
| `try` | error handling | Propagate error from error union; unwrap on success |
| `unn` | type | Define a tagged union; use `unn X => enum` for a union(enum) with switch capture |
| `@undef` | sentinel | Uninitialized / null sentinel — use as declaration value (`x = @undef`) or in comparisons (`x != @undef`) |
| `while` | control flow | Loop while a condition holds |

---

## Declaration Sigils

| Form | Mutability | Type | Example |
|------|-----------|------|---------|
| `x := value` | mutable | inferred | `count := 0` |
| `x : T = value` | mutable | explicit | `count : i32 = 0` |
| `x :: value` | immutable | inferred | `PI :: 3.14159` |
| `x : T : value` | immutable | explicit | `PI : f64 : 3.14159` |

---

## Operators

### Arithmetic

| Operator | Description |
|----------|-------------|
| `+` | Addition |
| `-` | Subtraction |
| `*` | Multiplication |
| `/` | Division |
| `%` | Modulo (remainder) |

### Comparison

| Operator | Description |
|----------|-------------|
| `==` | Equal |
| `!=` | Not equal |
| `<` | Less than |
| `<=` | Less than or equal |
| `>` | Greater than |
| `>=` | Greater than or equal |

### Logical

| Operator | Alias | Description |
|----------|-------|-------------|
| `&&` | `and` | Logical AND |
| `\|\|` | `or` | Logical OR |
| `!` | `not` | Logical NOT |

### Assignment

| Operator | Description |
|----------|-------------|
| `=` | Assign |
| `+=` | Add and assign |
| `-=` | Subtract and assign |
| `*=` | Multiply and assign |
| `/=` | Divide and assign |
| `%=` | Modulo and assign |

### Range

| Syntax | Description |
|--------|-------------|
| `a..b` | Exclusive range [a, b) |
| `a..=b` | Inclusive range [a, b] |
| `a..` | Open range from a (no upper bound; must `break` manually) |

### Other

| Operator | Description |
|----------|-------------|
| `=>` | Iteration arrow in `for` / `while do-expr`; arm separator in `switch` |
| `&` | Address-of |
| `*` | Pointer type prefix / dereference |
| `.` | Field / method access |
| `.*` | Explicit pointer dereference |
| `<<` | Stream output with `@cout` |
| `>>` | Stream input with `@cin` |

---

## Primitive Types

### Integer

| Type | Width | Range |
|------|-------|-------|
| `i8` | 8-bit signed | −128 … 127 |
| `i16` | 16-bit signed | −32 768 … 32 767 |
| `i32` | 32-bit signed | −2 147 483 648 … 2 147 483 647 |
| `i64` | 64-bit signed | −9.2×10¹⁸ … 9.2×10¹⁸ |
| `i128` | 128-bit signed | — |
| `isize` | machine word, signed | platform-dependent |
| `u8` | 8-bit unsigned | 0 … 255 |
| `u16` | 16-bit unsigned | 0 … 65 535 |
| `u32` | 32-bit unsigned | 0 … 4 294 967 295 |
| `u64` | 64-bit unsigned | 0 … 1.8×10¹⁹ |
| `u128` | 128-bit unsigned | — |
| `usize` | machine word, unsigned | platform-dependent |

### Floating-Point

| Type | Width |
|------|-------|
| `f16` | 16-bit IEEE 754 |
| `f32` | 32-bit IEEE 754 |
| `f64` | 64-bit IEEE 754 |
| `f128` | 128-bit IEEE 754 |

### Other Primitives

| Type | Description |
|------|-------------|
| `str` | UTF-8 string slice (`[]const u8`) |
| `char` | Single byte / ASCII character (`u8`) |
| `bool` | Boolean (`true` / `false`) |

---

## Composite Type Modifiers

| Syntax | Description |
|--------|-------------|
| `[]T` | Slice (dynamic-length array of T) |
| `[N]T` | Fixed-size array of N elements |
| `*T` | Pointer to T |
| `*imu T` | Pointer to immutable T |

---

## Built-in Functions

All builtins start with `@` and are always available without an import.

### Output

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@pl(expr)` | void | Print any value followed by a newline |
| `@pf(fmt, …)` | void | Printf-style formatted output; `{name}` interpolation or `{}` placeholders with optional `:spec` |
| `@cout << v` | — | Stream output; chain `<<`; use `@endl` for newline |
| `@endl` | — | Newline constant for `@cout` |

#### `@pf` format specifiers

| Specifier | Meaning |
|-----------|---------|
| `d` | Integer (decimal) |
| `f` | Float |
| `.Nf` | Float with N decimal places |
| `x` / `X` | Hex lower / upper |
| `s` | String |
| `b` | Binary |
| `e` | Scientific notation |

### Input

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@input(prompt)` | `str` | Read a line from stdin |
| `@input::T(prompt)` | `T!` | Read and parse a typed value; use `catch` on error |
| `@input::str(prompt)` | `str` | Read string (never fails) |
| `@sec_input(prompt)` | `str` | Read line with echo disabled (passwords) |
| `@sec_input::T(prompt)` | `T!` | Typed hidden input |
| `@cin >> buf` | — | Stream input into `buf` (auto-coerces to declared type) |

### Program Control

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@main { }` | — | Top-level entry point block (required in every executable) |
| `@args` | `[]str` | Command-line arguments as a string slice |
| `@sys::ex(code)` | never | Exit the process with the given exit code |
| `@sys::sleep(ms)` | void | Sleep for `ms` milliseconds |
| `@sys::time_ms()` | `i64` | Current Unix time in milliseconds |
| `@sys::time_ns()` | `i64` | Current Unix time in nanoseconds |

### Type Utilities

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@typeOf(expr)` | `str` | Runtime type name of `expr` as a string |
| `@str(expr)` | `str` | Convert any value to a string |

### Numeric Casts

`@T(expr)` casts `expr` to type `T`; when `expr` is a `str`, it parses it (returns an error union — use `catch`).

| Builtin | Converts to |
|---------|-------------|
| `@i8(expr)` | `i8` |
| `@i16(expr)` | `i16` |
| `@i32(expr)` | `i32` |
| `@i64(expr)` | `i64` |
| `@i128(expr)` | `i128` |
| `@isize(expr)` | `isize` |
| `@u8(expr)` | `u8` |
| `@u16(expr)` | `u16` |
| `@u32(expr)` | `u32` |
| `@u64(expr)` | `u64` |
| `@u128(expr)` | `u128` |
| `@usize(expr)` | `usize` |
| `@f32(expr)` | `f32` |
| `@f64(expr)` | `f64` |
| `@f128(expr)` | `f128` |

### Randomness

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@rng(T, min, max)` | `T` | Uniformly random value in `[min, max]` inclusive |

### Memory

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@alo(T, N)` | `*[]T` | Allocate a heap array of N elements of type T |
| `@alo::str(s)` | `*str` | Allocate a single heap string |
| `@alo::dat(T)` | `*T` | Allocate a single dat instance |
| `@alo::struct(T)` | `*T` | Allocate a single struct instance |
| `@alo::cls(T)` | `*T` | Allocate a single cls instance |
| `@free(ptr)` | void | Free a previously allocated pointer |
| `@undef` | — | Uninitialized sentinel for variable declarations |

### Namespace `@mem::`

Zig allocator handles. No import required.

| Call | Returns | Description |
|------|---------|-------------|
| `@mem::gen_purp_alo` | allocator | General-purpose allocator |
| `@mem::page_alo` | allocator | Page allocator |
| `@mem::arena_alo` | allocator | Arena allocator |
| `@mem::fix_buf_alo` | allocator | 64 KB fixed-buffer allocator |

### Dynamic Arrays

| Builtin / Method | Returns | Description |
|------------------|---------|-------------|
| `@list(T)` | list | Create a growable typed array |
| `list.add(v)` | void | Append element to end |
| `list.remove(i)` | void | Remove element at index `i` |
| `list.clear()` | void | Remove all elements |
| `list.len` | `usize` | Number of elements |


### Testing

| Builtin | Description |
|---------|-------------|
| `@test "name" { }` | Declare a test block |
| `@assert(cond)` | Fail if `cond` is false |
| `@assert_eq(a, b)` | Fail if `a != b` |
| `@assert_str(a, b)` | Fail if strings are not equal |

---

## Namespace `@fs::`

No import required.

### Path Utilities

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::is_file(path)` | `bool` | True if `path` exists and is a regular file |
| `@fs::is_dir(path)` | `bool` | True if `path` exists and is a directory |
| `@fs::mkdir(path)` | void | Create a directory (and all parents) |
| `@fs::mkfile(path)` | void | Create an empty file (truncates if exists) |
| `@fs::del(path)` | void | Delete a file or directory |
| `@fs::rename(old, new)` | void | Rename or move a file |
| `@fs::mov(src, dst)` | void | Move to a different path (alias for rename) |

### Directory Listing

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::ls(path)` | `?[]entry` | List directory entries; check `!= @undef` before use |
| `e.path()` | `str` | Absolute path of the entry |
| `e.is_file()` | `bool` | True if entry is a regular file |
| `e.is_dir()` | `bool` | True if entry is a directory |
| `files.len` | `usize` | Number of entries |

### file_reader (`try`-based)

Open with `try @fs::file_reader::open(path)`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.rall()` | `str!` | Read entire file into a string |
| `f.rln()` | `str!` | Read one line (strips trailing `\n`) |
| `f.rch()` | `char!` | Read a single byte |
| `f.r(n)` | `[]u8!` | Read exactly n bytes |
| `f.eof()` | `bool` | True while data remains |
| `f.cl()` / `f.close()` | void | Close the file |

### file_writer (`try`-based)

Open with `try @fs::file_writer::open(path)`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.w(data)` | `void!` | Write string or bytes |
| `f.wln(data)` | `void!` | Write string then newline |
| `f.wch(byte)` | `void!` | Write a single byte |
| `f.fl()` | `void!` | Flush to disk |
| `f.cl()` / `f.close()` | void | Close the file |


### Binary I/O

| Constant | Description |
|----------|-------------|
| `@fs::Little` | Little-endian constant |
| `@fs::Big` | Big-endian constant |

Open with `try @fs::byte_reader::open(path)` / `try @fs::byte_writer::open(path)`. Methods mirror file_reader/file_writer.

---

## Namespace `@math::`

No import required.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `@math::pi` | 3.14159265358979… | π |

### Functions

| Call | Returns | Description |
|------|---------|-------------|
| `@math::abs(x)` | T | Absolute value |
| `@math::min(a, b, …)` | T | Minimum of two or more values |
| `@math::max(a, b, …)` | T | Maximum of two or more values |
| `@math::floor(x)` | f64 | Round down |
| `@math::ceil(x)` | f64 | Round up |
| `@math::sqrt(x)` | f64 | Square root |
| `@math::exp(base, exp)` | f64 | `base ^ exp` |
| `@math::log(x)` | f64 | Natural logarithm (base e) |
| `@math::log2(x)` | f64 | Logarithm base 2 |
| `@math::log10(x)` | f64 | Logarithm base 10 |
| `@math::sin(x)` | f64 | Sine (radians) |
| `@math::cos(x)` | f64 | Cosine (radians) |
| `@math::tan(x)` | f64 | Tangent (radians) |

---

## Namespace `@kry::`

No import required. Pure-Zig cryptography — no external dependency.

| Call | Returns | Description |
|------|---------|-------------|
| `@kry::hash(pw)` | `str` | PBKDF2-HMAC-SHA512 (600k iterations, random 32-byte salt) → `"hex_salt$hex_key"` (129 chars) |
| `@kry::hash_auth(pw, stored)` | `bool` | Verify `pw` against stored hash |
| `@kry::enc_file(path, pw)` | void | AES-256-GCM encrypt file in-place |
| `@kry::dec_file(path, pw)` | void | AES-256-GCM decrypt file in-place |

Encrypted file layout: `[32-byte salt][12-byte nonce][ciphertext][16-byte GCM tag]`.

---

## Namespace `@fflog::`

No import required. Flat-file JSON logger (JSONL format).

| Call | Returns | Description |
|------|---------|-------------|
| `@fflog::init(path)` | logger | Create logger pointing at `path` |
| `log.open()` | void | Open (or create) the log file for writing |
| `log.close()` | void | Flush and close the log file |
| `log.wr(level, component, msg)` | void | Append one JSON log entry with Unix timestamp |

Each entry is: `{"ts":…,"level":"…","component":"…","msg":"…"}`

---

## Namespace `@xi::`

No import required. Graphics framework backed by SDL2. Detected automatically at compile time.

**System requirement:** `SDL2`, `SDL2_ttf`, `SDL2_image`

### Window

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::window(w, h, title)` | window handle | Create a window |
| `win.fps(n)` | void | Set target frame rate |
| `win.center()` | void | Center on primary monitor |
| `win.size(w, h)` | void | Resize window |
| `win.minsize(w, h)` | void | Set minimum resizable size |
| `win.maxsize(w, h)` | void | Set maximum resizable size |
| `win.resize(bool)` | void | Enable/disable user resizing |
| `win.pos(x, y)` | void | Move window to screen position |
| `win.loop` | `bool` | Main loop condition |

### Events

| Call | Description |
|------|-------------|
| `win.frame { close => {…}, min => {…}, max => {…} }` | Window state events |
| `win.keys { key_press => {…}, key_type => {…} }` | Keyboard events |
| `win.mouse { … }` | Mouse events |
| `win.key.code` | Current key code |
| `win.key.char` | Current key char (`u8`) |
| `win.default` | Default event handler |

### Drawing

| Call | Description |
|------|-------------|
| `win.draw { … }` | Drawing block (wrapped in begin/end drawing) |
| `win.clearbg(color)` | Clear background to a color |
| `win.text(fnt, str, x, y)` | Draw text using a font handle |
| `win.rect(x, y, w, h, color)` | Draw a filled rectangle |
| `win.circle(x, y, r, color)` | Draw a filled circle |
| `win.line(x1, y1, x2, y2, color)` | Draw a line |

### Colors

| Access | Description |
|--------|-------------|
| `win.color.NAME` | Named color constant (32 colors: `black`, `white`, `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `darkblue`, `lightgray`, etc.) |
| `@xi::color(r, g, b, a)` | Custom RGBA color |

### Fonts, Images, GIFs

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::fnt` | font handle type | Font handle (pass by value or `&` ref) |
| `fnt.load(path, size)` | void | Load a TTF font |
| `fnt.free()` | void | Free font resources |
| `@xi::img` | image handle type | Image handle |
| `img.load(path)` | void | Load an image |
| `img.scale(w, h)` | void | Set draw size (`0` resets to natural) |
| `img.free()` | void | Free image resources |
| `@xi::gif` | GIF handle type | Animated GIF handle |
| `gif.load(path)` | void | Load a GIF |
| `gif.scale(w, h)` | void | Set draw size |
| `gif.delay(N)` | void | Set frame delay |
| `gif.free()` | void | Free GIF resources |

### Handle Passing

Pass `@xi::` handles to functions by value or by reference:

```
fn draw_it(img: @xi::img) { … }          # by value
fn update_win(win: &@xi::win) { … }      # by reference

draw_it(img)
update_win(&win)
```

---

## User-Defined Types

### `dat` — Data Record

```
dat Name { field: Type, … }
```

Fields only; no methods. Create instances with struct-literal syntax: `Name { .field = value }`.

### `unn` — Tagged Union

```
unn X {
    x: i32,
    f: f32,
    p: Person,
    anon: .{a: str, b: str},
}

unn Y => enum {
    a: i32,
    b: f32,
}
```

Standard unions hold one active field at a time. `unn X => enum` is a union(enum) — use `switch` with `|capture|` syntax to destructure:

```
switch y {
    .a => |a| { @pl(a) },
    .b => |b| { @pl(b) },
}
```

Instantiate with `X.field{value}`, e.g. `x := X.f{3.14}`.

---

### `cls` — Class *(Beta)*

> **Beta:** `cls` is implemented and functional. Inheritance, interface enforcement, and method dispatch are still being refined.

```
cls Name {
    field: Type,
    @init { self.field = … }
    @deinit { … }
    pub fn method() { … }
}
```

Supports inheritance (`cls Dog : pub Animal`) and interface implementation (`cls X :: IFace`). Use `ovrd fun` to override parent methods. Members are private by default; mark `pub` to expose.

### `struct` — Struct with Methods

```
struct P {
    x: i32, y: f32,

    pub baz: str = "foo"   # public static field (P.baz)
    faz: str = "bar"       # private static field

    pub fn thing() {}      # static func (no @self)

    pub fn foo(self: @self, x, y) {}  # public member func
    fn bar(self: @self) -> f32 {}     # private member func
}
```

Like `cls` but no inheritance, no `@init`/`@deinit`. Members are private by default; mark `pub` to expose. Member functions require `self: @self`; static functions omit it. Simple stack-type params (i32, f32, str, dat, …) may be implicit; pointer and allocator params must be explicitly annotated.

### `enum` — Enumeration

```
enum Direction { NORTH, SOUTH, EAST, WEST }
enum Status => i32 { IDLE = 0, RUNNING = 1 }
enum Size => str { SMALL = "sm", LARGE = "lg" }
```

Use dot-literal syntax (`.VARIANT`) when the type is known from context. Integer-backed enums get a `.val()` method; non-integer-backed get `.value()`.

### `fn` / `fun` — Functions

```
fn add(a: i32, b: i32) -> i32 { ret a + b }
double := (x: i32 => i32) { ret x * 2 }  # lambda: (params => ret) { body }
void_fn := (bar: str => _) { @pl(bar) }   # use _ for void return
```

Lambdas use the form `(params => ret) { body }` and can be passed directly as arguments.

| Return annotation | Meaning |
|-------------------|---------|
| `-> T` | Returns T |
| `-> T!` | Returns T or propagates an error |
| `-> any` | Returns void, may propagate an error |
| `-> T?` | Returns optional T (null = absent) |
| `-> T?!E` | Optional T or error E |

Use `@comptime T param` for generic/comptime type parameters.

---

## Error Handling

| Construct | Description |
|-----------|-------------|
| `try expr` | Propagate error on failure; unwrap value on success |
| `expr catch default` | Catch any error and return `default` (fast form) |
| `expr catch \|e\| { arm => {…} }` | Handle error inline with arm matching; `_` is wildcard |
| `error.Name` | Match a specific error variant in a `catch` arm |

---

## Packages & Imports

### Built-in namespaces (no import)

`@fs::`, `@math::`, `@kry::`, `@fflog::`, `@xi::`, `@mem::`, `@list`, `@alo`, `@free`, `@rng`, `@pl`, `@pf`, etc.

### NativeSysPkg (OS install + no `zcy add`)

| Import | Library |
|--------|---------|
| `@import(omp = @zcy.openmp)` | OpenMP threading |
| `@import(sodium = @zcy.sodium)` | libsodium crypto |
| `@import(db = @zcy.sqlite)` | SQLite3 |
| `@import(qt = @zcy.qt)` | Qt5/Qt6 widgets |

### ZcytheAddLinkPkg (`zcy add` required)

| Import | Library |
|--------|---------|
| `@import(rl = @zcy.raylib)` | raylib 2D/3D graphics |

### `@zcy.openmp` — OpenMP (via `omp` alias)

| Call | Returns | Description |
|------|---------|-------------|
| `omp.set_threads(n)` | void | Set thread pool size |
| `omp.max_threads()` | `i32` | Max threads available |
| `omp.num_threads()` | `i32` | Threads in current parallel region |
| `omp.thread_id()` | `i32` | 0-based ID of current thread |
| `omp.wtime()` | `f64` | Wall-clock seconds |
| `omp.in_parallel()` | `bool` | True if inside a parallel region |
| `omp.parallel { }` | — | Spawn N threads, all run body |
| `omp.for v => range { }` | — | Parallel loop over integer range |

### `@zcy.sodium` — libsodium (via `sodium` alias)

| Call | Returns | Description |
|------|---------|-------------|
| `sodium.hash(pw)` | `str` | Argon2id hash → self-describing string |
| `sodium.hash_auth(pw, hash)` | `bool` | Constant-time password verification |
| `sodium.enc_file(path, key)` | void | Encrypt file in-place (XChaCha20-Poly1305) |
| `sodium.dec_file(path, key)` | void | Decrypt file in-place |

### `@zcy.sqlite` — SQLite3 (via `db` alias)

| Call | Returns | Description |
|------|---------|-------------|
| `db.open(path)` | connection | Open (or create) a SQLite database |
| `conn.exec(sql)` | void | Execute a SQL statement |
| `conn.prepare(sql)` | statement | Prepare a SQL statement |
| `stmt.step()` | `bool` | Advance to next result row |
| `stmt.col_str(i)` | `str` | Read column `i` as string |
| `stmt.col_int(i)` | `i64` | Read column `i` as integer |
| `stmt.finalize()` | void | Finalize a prepared statement |
| `conn.close()` | void | Close the database connection |

### `@zcy.qt` — Qt (via `qt` alias)

| Call | Returns | Description |
|------|---------|-------------|
| `qt.app()` | app | Create the Qt application |
| `qt.window(title, w, h)` | window | Create a window |
| `qt.label(text)` | widget | Label widget |
| `qt.button(text)` | widget | Push button |
| `qt.input(placeholder)` | widget | Line-edit input |
| `qt.checkbox(text)` | widget | Checkbox |
| `qt.spinbox(min, max)` | widget | Integer spinbox |
| `qt.vbox()` | layout | Vertical box layout |
| `qt.hbox()` | layout | Horizontal box layout |
| `layout.add(widget)` | void | Add widget to layout |
| `win.set_layout(layout)` | void | Attach layout to window |
| `win.show()` | void | Display the window |
| `app.process_events()` | void | Process pending events (polling) |
| `app.should_quit()` | `bool` | True when the app should exit |
| `widget.clicked()` | `bool` | True if button was clicked this frame |
| `widget.set_text(str)` | void | Update widget text |

---

## CLI — `zcy`

| Command | Description |
|---------|-------------|
| `zcy init <name>` | Create a new Zcythe project |
| `zcy build` | Full pipeline: transpile `.zcy` → Zig → binary in `zcy-bin/` |
| `zcy build-src` | Transpile only: `.zcy` → `src/zcyout/` (skip `zig build-exe`) |
| `zcy build-out` | Compile only: `src/zcyout/` → `zcy-bin/` (skip transpile) |
| `zcy run` | Build and run (passes remaining args to the binary) |
| `zcy sac` | Build a self-contained single binary (includes `@xi::` support) |
| `zcy test` | Run all `@test` blocks in the project |
| `zcy test <file>` | Run tests from one specific `.zcy` file |
| `zcy add <pkg>` | Add a ZcytheAddLinkPkg (`raylib`, or `owner/repo`) |
| `zcy lspkg` | List all available packages with install instructions |
