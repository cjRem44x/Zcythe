# Zcythe Language Index

Complete reference for every keyword, builtin, type, and CLI command.

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
| `catch` | error handling | Recover from an error union: `expr catch default` or `expr catch \|e\| { … }` |
| `cls` | type | Define a class with fields, constructor, destructor, and methods |
| `continue` | control flow | Skip to the next iteration of the nearest loop |
| `dat` | type | Plain data record — fields only, no methods |
| `defer` | resource | Schedule a statement to run at scope exit (LIFO order) |
| `elif` | control flow | Else-if branch in an `if` chain |
| `else` | control flow | Fallback branch for `if` / `switch` |
| `enum` | type | Enumeration, optionally with a backing type |
| `false` | literal | Boolean false |
| `fn` | declaration | Declare a named function |
| `for` | control flow | Iterate over a collection or range |
| `if` | control flow | Conditional branch |
| `imu` | modifier | Immutable pointer pointee: `*imu T` |
| `loop` | control flow | C-style `init, cond, update` loop |
| `not` | operator | Logical NOT (alias for `!`) |
| `null` / `NULL` | literal | Null pointer sentinel — both spellings accepted |
| `or` | operator | Logical OR (alias for `\|\|`) |
| `ovrd` | type | Override a parent class method inside `cls` |
| `pub` | visibility | Expose a field or method in `cls` / `struct` |
| `ret` | control flow | Return a value from the current function |
| `struct` | type | Struct with fields and methods (no inheritance) |
| `switch` | control flow | Pattern-match a value; `_` wildcard; `\|binding\|` captures union payload |
| `true` | literal | Boolean true |
| `try` | error handling | Propagate error on failure; unwrap value on success |
| `unn` | type | Tagged or untagged union; `unn X => enum` for switch capture |
| `@undef` | sentinel | Uninitialized / null sentinel for variable declarations |
| `while` | control flow | Loop while a condition holds |

---

## Declaration Sigils

| Form | Mutability | Type | Example |
|------|-----------|------|---------|
| `x := value` | mutable | inferred | `count := 0` |
| `x : T = value` | mutable | explicit | `count : i32 = 0` |
| `x :: value` | immutable | inferred | `PI :: 3.14159` |
| `x : T : value` | immutable | explicit | `PI : f64 : 3.14159` |

Multiple statements on one line — use `;` as a separator:

```
a := 1; b := 2; @pl(a + b)
```

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

### Bitwise

| Operator | Description |
|----------|-------------|
| `&` | Bitwise AND / address-of |
| `\|` | Bitwise OR |
| `^` | Bitwise XOR |
| `~` | Bitwise NOT |
| `<<` | Left shift |
| `>>` | Right shift |

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
| `&=` `\|=` `^=` | Bitwise assign |
| `<<=` `>>=` | Shift assign |

### Range

| Syntax | Description |
|--------|-------------|
| `a..b` | Exclusive range `[a, b)` |
| `a..=b` | Inclusive range `[a, b]` |
| `a..` | Open range from `a` (no upper bound) |

### Other

| Operator | Description |
|----------|-------------|
| `=>` | Arrow in `for` iteration / `while` do-expr / `switch` arm separator |
| `->` | Pointer field access — `p->field` is `(p.*).field`; use on any `*T` heap pointer |
| `.` | Field or method access |
| `.*` | Explicit pointer dereference |
| `.?` | Optional unwrap (panics if null) |
| `..` | Range (see above) |
| `<<` | `@cout` stream output |
| `>>` | `@cin` stream input |
| `;` | Inline statement separator |

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
| `isize` | pointer-sized signed | platform-dependent |
| `u8` | 8-bit unsigned | 0 … 255 (numeric; prints as integer) |
| `u16` | 16-bit unsigned | 0 … 65 535 |
| `u32` | 32-bit unsigned | 0 … 4 294 967 295 |
| `u64` | 64-bit unsigned | 0 … 1.8×10¹⁹ |
| `u128` | 128-bit unsigned | — |
| `usize` | pointer-sized unsigned | platform-dependent |

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
| `chr` | Single ASCII character — same runtime width as `u8` but prints as a character (via `{c}`) with `@pl`, `@pf`, and `@cout` |
| `bool` | Boolean (`true` / `false`) |
| `void` | No value |
| `noret` | Function never returns |
| `anytype` | Comptime-generic type parameter |

#### `chr` vs `u8`

`chr` and `u8` are both 8-bit unsigned integers at the Zig level. The distinction is **printing behaviour**:

| Type | `@pl` / `@pf {}` / `@cout <<` |
|------|-------------------------------|
| `u8` | prints as integer (`90`) |
| `chr` | prints as character (`Z`) |

```
c : chr = 'Z'
n : u8  = 90
@pf("chr={} num={}\n", c, n)   # chr=Z num=90
@pl(c)                          # Z
@pl(n)                          # 90
```

---

## Composite Type Modifiers

| Syntax | Description |
|--------|-------------|
| `[]T` | Slice (dynamic-length array) |
| `[N]T` | Fixed-size array of N elements |
| `*T` | Nullable heap pointer — emitted as `?*T` in Zig; supports `== null` and `->` field access |
| `*imu T` | Pointer to immutable T |
| `*[]T` | Heap-owned slice — result of `@alo(T, N)`; pass to `@free` when done |
| `@self` | "Pointer to the enclosing struct/cls instance" — valid only as a parameter type in member functions |

---

## Built-in Functions

All builtins start with `@` and require no import.

### Output

| Builtin | Description |
|---------|-------------|
| `@pl(expr)` | Print any value followed by a newline |
| `@pf(fmt, …)` | Printf-style formatted output |
| `@cout << v << … << @endl` | Streaming output; chain with `<<`; `@endl` appends a newline |

#### `@pf` usage

```
name := "Alice"
age  := 30
@pf("Hello {name}, you are {age} years old!\n")   # {ident} interpolation
@pf("Values: {} {}\n", name, age)                  # positional {} placeholders
```

`@pf` infers the format specifier from the argument type: `str` → `{s}`, `chr` → `{c}`, everything else → `{}`. Use an explicit specifier to override:

| Specifier | Meaning |
|-----------|---------|
| `{s}` | String |
| `{c}` | Character |
| `{d}` | Integer decimal |
| `{f}` | Float |
| `{.Nf}` | Float, N decimal places |
| `{x}` / `{X}` | Hex lower / upper |
| `{b}` | Binary |
| `{e}` | Scientific notation |

#### `@cout` usage

```
p := person("John", 24)
@cout << "Hello " << p.name << ", age " << p.age << @endl
```

`@cout` auto-selects `{s}` for `str`, `{c}` for `chr`, and `{any}` for everything else.

### Input

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@input(prompt)` | `str` | Read a line from stdin |
| `@input::T(prompt)` | `T!` | Read and parse a typed value; use `catch` on error |
| `@input::str(prompt)` | `str` | Always returns a string |
| `@sec_input(prompt)` | `str` | Read with echo disabled (passwords) |
| `@cin >> buf` | — | Stream input into `buf` (auto-coerces to declared type) |

### Program Control

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@main { }` | — | Top-level entry point |
| `@args` | `[]str` | Command-line arguments |
| `@sys::ex(code)` | never | Exit with code |
| `@sys::sleep(ms)` | void | Sleep `ms` milliseconds |
| `@sys::waist(ms)` | void | Busy-wait `ms` milliseconds (high-precision) |
| `@sys::time_ms()` | `i64` | Unix time in milliseconds |
| `@sys::time_ns()` | `i64` | Unix time in nanoseconds |
| `@sys::cli(fmt, …)` | void | Run a shell command with `{ident}` / `{}` interpolation |

```
host := "example.com"
@sys::cli("ping -c 1 {host}")
@sys::cli("echo {} {}", "a", "b")
```

### Type Utilities

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@typeOf(expr)` | `str` | Runtime type name as a string |
| `@str(expr)` | `str` | Convert any value to a string |

### Numeric Casts

`@T(expr)` casts to type T. When `expr` is a `str`, it parses it (returns an error union — use `catch`).

| Builtin | Target |
|---------|--------|
| `@i8` `@i16` `@i32` `@i64` `@i128` `@isize` | Signed integers |
| `@u8` `@u16` `@u32` `@u64` `@u128` `@usize` | Unsigned integers |
| `@f32` `@f64` `@f128` | Floats |

```
n := @i32("42") catch 0    # parse str → i32, default 0 on error
x := @f64(n)               # cast i32 → f64
```

### Randomness

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@rng(T, min, max)` | `T` | Uniform random value in `[min, max]` inclusive |

```
roll := @rng(i32, 1, 6)
frac := @rng(f64, 0.0, 1.0)
```

### Memory

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@alo(T, N)` | `*[]T` | Allocate a heap array of N elements of type T |
| `@alo::str(s)` | `*str` | Duplicate a string onto the heap |
| `@alo::dat(T)` | `*T` | Allocate a single `dat` instance on the heap |
| `@alo::struct(T)` | `*T` | Allocate a single `struct` instance on the heap |
| `@alo::cls(T)` | `*T` | Allocate a single `cls` instance on the heap |
| `@free(ptr)` | void | Free a pointer returned by any `@alo` variant |
| `@undef` | — | Uninitialized-value sentinel |

#### Heap array (`@alo`)

```
nums :*[]i32 = @alo(i32, 4)
defer @free(nums)
nums[0] = 10
nums[1] = 20
@pl(nums[0])   # 10
```

Index a `*[]T` directly with `[i]` — no explicit dereference.

#### Heap single instance (`@alo::dat / struct / cls`)

```
dat Person { name: str, age: i32, }

p :*Person = @alo::dat(Person)
defer @free(p)

p->name = "Alice"    # -> accesses fields through the pointer
p->age  = 30
@pl(p->name)         # Alice

if p == null { @pl("allocation failed") }
```

`->` is the pointer field-access operator: `p->field` = `(p.*).field`. Use it any time the variable is a `*T` heap pointer.

`*T` pointers emit as `?*T` (nullable) in Zig. You can always compare them to `null` and they support `->` for field access.

### Namespace `@mem::`

Allocator handles — no import required.

| Expression / Type | Description |
|-------------------|-------------|
| `@mem::Allocator` | `std.mem.Allocator` — use as a function parameter type |
| `@mem::page_alo` | Page allocator |
| `@mem::gen_purp_alo` | General-purpose allocator |
| `@mem::arena_alo` | Arena allocator |
| `@mem::fix_buf_alo` | 64 KB fixed-buffer allocator |

```
fn alloc_n(alo: @mem::Allocator, n: usize) -> []i32 {
    ret try alo.alloc(i32, n)
}
```

### Dynamic Arrays

| Builtin / Method | Returns | Description |
|------------------|---------|-------------|
| `@list(T)` | list | Create a growable typed array |
| `list.add(v)` | void | Append element |
| `list.remove(i)` | void | Remove element at index `i` |
| `list.clear()` | void | Remove all elements |
| `list.len` | `usize` | Number of elements |

```
nums := @list(i32)
nums.add(1)
nums.add(2)
nums.add(3)
for v => nums { @pl(v) }
```

### Testing

| Builtin | Description |
|---------|-------------|
| `@test "name" { }` | Declare a test block |
| `@assert(cond)` | Fail if `cond` is false |
| `@assert_eq(a, b)` | Fail if `a != b` |
| `@assert_str(a, b)` | Fail if strings are not equal |

```
@test "addition" {
    @assert_eq(1 + 1, 2)
}
```

Run with `zcy test`.

---

## Namespace `@fs::`

No import required.

### Path Utilities

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::is_file(path)` | `bool` | True if path exists and is a regular file |
| `@fs::is_dir(path)` | `bool` | True if path exists and is a directory |
| `@fs::mkdir(path)` | void | Create directory (and parents) |
| `@fs::mkfile(path)` | void | Create an empty file (truncates if exists) |
| `@fs::del(path)` | void | Delete file or directory |
| `@fs::rename(old, new)` | void | Rename or move |
| `@fs::mov(src, dst)` | void | Move (alias for rename) |

### Directory Listing

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::ls(path)` | `?[]entry` | List directory entries; null if path invalid |
| `e.path()` | `str` | Absolute path of the entry |
| `e.is_file()` | `bool` | True if entry is a regular file |
| `e.is_dir()` | `bool` | True if entry is a directory |
| `entries.len` | `usize` | Number of entries |

```
entries := @fs::ls(".")
if entries != @undef {
    for e => entries {
        if e.is_file() { @pl(e.path()) }
    }
}
```

### `file_reader`

Open with `try @fs::file_reader::open(path)`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.rall()` | `str!` | Read entire file into a string |
| `f.rln()` | `str!` | Read one line (strips `\n`) |
| `f.rch()` | `chr!` | Read a single byte as a character |
| `f.r(n)` | `[]u8!` | Read exactly n bytes |
| `f.eof()` | `bool` | True while data remains |
| `f.cl()` | void | Close the file |

```
f := try @fs::file_reader::open("data.txt")
defer f.cl()
while !f.eof() {
    line := try f.rln()
    @pl(line)
}
```

### `file_writer`

Open with `try @fs::file_writer::open(path)`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.w(data)` | `void!` | Write string or bytes |
| `f.wln(data)` | `void!` | Write string then newline |
| `f.wch(byte)` | `void!` | Write a single byte |
| `f.fl()` | `void!` | Flush to disk |
| `f.cl()` | void | Close the file |

### Binary I/O

Open with `try @fs::byte_reader::open(path)` / `try @fs::byte_writer::open(path)`.

| Constant | Description |
|----------|-------------|
| `@fs::Little` | Little-endian |
| `@fs::Big` | Big-endian |

---

## Namespace `@math::`

No import required.

### Constants

| Constant | Description |
|----------|-------------|
| `@math::pi` | π ≈ 3.14159265358979… |

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
| `@math::log(x)` | f64 | Natural log |
| `@math::log2(x)` | f64 | Log base 2 |
| `@math::log10(x)` | f64 | Log base 10 |
| `@math::sin(x)` | f64 | Sine (radians) |
| `@math::cos(x)` | f64 | Cosine (radians) |
| `@math::tan(x)` | f64 | Tangent (radians) |

---

## Namespace `@kry::`

No import required. Pure-Zig cryptography.

| Call | Returns | Description |
|------|---------|-------------|
| `@kry::hash(pw)` | `str` | PBKDF2-HMAC-SHA512, random salt → `"hex_salt$hex_key"` |
| `@kry::hash_auth(pw, stored)` | `bool` | Verify password against stored hash |
| `@kry::enc_file(path, pw)` | void | AES-256-GCM encrypt file in-place |
| `@kry::dec_file(path, pw)` | void | AES-256-GCM decrypt file in-place |

Encrypted file layout: `[32-byte salt][12-byte nonce][ciphertext][16-byte GCM tag]`.

---

## Namespace `@fflog::`

No import required. Flat-file JSONL logger.

| Call | Returns | Description |
|------|---------|-------------|
| `@fflog::init(path)` | logger | Create logger pointing at `path` |
| `log.open()` | void | Open (or create) the log file |
| `log.close()` | void | Flush and close |
| `log.wr(level, component, msg)` | void | Append one JSON entry with Unix timestamp |

Entry format: `{"ts":…,"level":"…","component":"…","msg":"…"}`

---

## Namespace `@xi::`

No import required. Graphics backed by SDL2.

**Requires:** `SDL2`, `SDL2_ttf`, `SDL2_image`

### Window

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::window(w, h, title)` | window | Create window |
| `win.fps(n)` | void | Set target frame rate |
| `win.center()` | void | Center on primary monitor |
| `win.size(w, h)` | void | Resize |
| `win.minsize(w, h)` | void | Set minimum size |
| `win.maxsize(w, h)` | void | Set maximum size |
| `win.resize(bool)` | void | Enable / disable user resizing |
| `win.pos(x, y)` | void | Move window |
| `win.loop` | `bool` | Main loop condition |

### Events

| Call | Description |
|------|-------------|
| `win.frame { close => {…}, … }` | Window close / minimize / maximize events |
| `win.keys { key_press => {…}, key_type => {…} }` | Keyboard events |
| `win.mouse { … }` | Mouse events |
| `win.key.code` | Current key code |
| `win.key.char` | Current key char (`u8`) |
| `win.default` | Default event handler |

### Drawing

| Call | Description |
|------|-------------|
| `win.draw { … }` | Drawing block |
| `win.clearbg(color)` | Clear background |
| `win.text(fnt, str, x, y)` | Draw text |
| `win.rect(x, y, w, h, color)` | Draw filled rectangle |
| `win.circle(x, y, r, color)` | Draw filled circle |
| `win.line(x1, y1, x2, y2, color)` | Draw line |

### Colors

| Access | Description |
|--------|-------------|
| `win.color.NAME` | Named color (`black`, `white`, `red`, `green`, `blue`, `yellow`, `orange`, `purple`, etc.) |
| `@xi::color(r, g, b, a)` | Custom RGBA color |

### Fonts, Images, GIFs

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::fnt` | font handle type | Font handle |
| `fnt.load(path, size)` | void | Load a TTF font |
| `fnt.free()` | void | Free font |
| `@xi::img` | image handle type | Image handle |
| `img.load(path)` | void | Load image |
| `img.scale(w, h)` | void | Set draw size (`0` = natural) |
| `img.free()` | void | Free image |
| `@xi::gif` | GIF handle type | Animated GIF handle |
| `gif.load(path)` | void | Load GIF |
| `gif.scale(w, h)` | void | Set draw size |
| `gif.delay(N)` | void | Set frame delay |
| `gif.free()` | void | Free GIF |

### Handle Passing

```
fn draw_it(img: @xi::img) { … }         # by value
fn resize(win: &@xi::win) { … }         # by reference

draw_it(img)
resize(&win)
```

---

## User-Defined Types

### `dat` — Data Record

`dat` defines a plain data struct: fields only, no methods. Use it for simple value types and return values.

```
dat Person {
    name: str,
    age:  i32,
}
```

**Creating instances:**

```
p := Person{.name = "Alice", .age = 30}
@pl(p.name)   # Alice
```

**Returning from a function — anonymous literal:**

```
fn make_person(name: str, age: i32) -> Person {
    ret .{.name = name, .age = age}   # type inferred from return annotation
}

p := make_person("Bob", 25)
@pl(p.name)   # Bob
```

`.{…}` syntax (`ret .{…}`) infers the struct type from the function's declared return type. This works for `dat`, `struct`, and any named type.

**Heap allocation:**

```
p :*Person = @alo::dat(Person)
defer @free(p)
p->name = "Charlie"
p->age  = 40
@pl(p->name)                         # Charlie
if p == null { @pl("alloc failed") }
```

---

### `struct` — Struct with Methods

Like `dat` but supports member functions via `@self`. No inheritance. Compiles to a plain Zig struct.

```
struct Counter {
    count: i32,

    pub fn inc(self: @self) {
        self.count += 1
    }

    pub fn get(self: @self) -> i32 {
        ret self.count
    }

    pub fn make(start: i32) -> Counter {
        ret .{.count = start}   # static factory — no @self
    }
}

ctr := Counter.make(0)
ctr.inc()
ctr.inc()
@pl(ctr.get())   # 2
```

**Field defaults:**

Fields can declare a default value. Omitted fields use their default.

```
struct Point {
    x: i32 = 0,
    y: i32 = 0,
    pub fn sum(self: @self) -> i32 { ret self.x + self.y }
}

pt  := Point{}           # x=0, y=0
pt2 := Point{.x = 5}    # x=5, y=0
@pl(pt2.sum())           # 5
```

**Heap allocation:**

```
p :*Point = @alo::struct(Point)
defer @free(p)
p->x = 3
p->y = 4
@pl(p->sum())   # 7 — methods work through ->
```

#### `@self` annotation

`self: @self` inside a member function means "mutable pointer to the enclosing struct". Rules:
- Must be the first parameter of any member function.
- Omit entirely for static (no-instance) functions.
- The compiler automatically promotes `const` to `var` for variables that call mutating methods.

#### Visibility

| Syntax | Effect |
|--------|--------|
| `field: T` | Private field |
| `pub field: T` | Public field |
| `fn method(self: @self)` | Private member function |
| `pub fn method(self: @self)` | Public member function |
| `pub fn static()` | Public static function |

#### Anonymous return literal

Any function returning a struct/dat type can use `.{…}` to skip naming a temporary:

```
fn origin() -> Point {
    ret .{.x = 0, .y = 0}
}
```

---

### `unn` — Union

A union holds one active field at a time. Two forms:

#### Plain union — `unn X { … }`

No runtime tag. Caller tracks the active variant manually.

```
unn Num {
    i: i32,
    f: f64,
}

n : Num = Num{.i = 42}    # struct-literal form
n  = Num.f{3.14}          # shorthand: Type.variant{value}
@pl(n.f)                   # 3.14
```

#### Tagged union — `unn X => enum { … }`

Carries an enum tag — required for `switch` with payload capture.

```
unn Shape => enum {
    circle:    f64,   # radius
    rectangle: f64,   # width (simplified)
}

s : Shape = Shape.circle{5.0}

switch s {
    .circle    => |r| { @pf("circle r={}\n", r) },
    .rectangle => |w| { @pf("rect w={}\n", w) },
}
```

**Instantiation forms:**

| Syntax | Meaning |
|--------|---------|
| `Type.variant{value}` | Shorthand — set the named variant |
| `Type{.variant = value}` | Struct-literal — always valid |

**Switch capture:** write `\|binding\|` after `=>` to bind the active payload. Only `unn X => enum` supports capture; plain `unn` requires direct field access.

---

### `cls` — Class *(Beta)*

> **Beta:** `cls` is implemented and functional. Full inheritance dispatch and interface enforcement are still being refined.

```
cls Animal {
    name: str,

    @init { self.name = "?" }   # constructor body
    @deinit { }                  # destructor body

    pub fn speak() {
        @pl("…")
    }
}

cls Dog extends Animal {
    pub ovrd fn speak() {
        @pf("{} says woof!\n", self.name)
    }
}
```

- Members are private by default; mark `pub` to expose.
- `@init` / `@deinit` are the constructor and destructor bodies.
- Use `extends Parent` for single inheritance.
- Use `ovrd` on a method to override a parent method.
- Use `@alo::cls(T)` to allocate on the heap.

---

### `enum` — Enumeration

```
enum Direction { NORTH, SOUTH, EAST, WEST }

enum Status(i32) { IDLE = 0, RUNNING = 1, DONE = 2 }
```

Use dot-literal syntax (`.VARIANT`) when the type is known from context:

```
dir : Direction = .NORTH
switch dir {
    .NORTH => { @pl("going north") },
    _      => { @pl("other") },
}
```

Integer-backed enums expose `.val()` to get the raw integer value.

---

### `fn` — Named Functions

```
fn add(a: i32, b: i32) -> i32 {
    ret a + b
}
```

**Return type annotations:**

| Annotation | Meaning |
|------------|---------|
| `-> T` | Returns T |
| `-> T!` | Returns T or propagates an error |
| `-> void` | Returns nothing |
| `-> T?` | Returns optional T (null = absent) |

**Untyped parameters:** omit the `: Type` annotation to accept any type (comptime-generic):

```
fn greet(name) {
    @pf("Hello {}!\n", name)
}
```

**Generic / comptime parameters:**

```
fn identity(comptime T: anytype, val: T) -> T {
    ret val
}
```

---

### Lambdas

```
double   := (x: i32 => i32)  { ret x * 2 }
void_fn  := (msg: str => _)  { @pl(msg) }     # _ = void return

result := double(5)   # 10
```

Syntax: `(param: Type, … => RetType) { body }`. Use `_` for void return. Pass inline:

```
fn apply(f: (x: i32 => i32), v: i32) -> i32 { ret f(v) }

n := apply((x: i32 => i32) { ret x + 1 }, 10)   # 11
```

---

## Error Handling

| Construct | Description |
|-----------|-------------|
| `try expr` | Propagate error on failure; unwrap value on success |
| `expr catch default` | Catch any error and return `default` |
| `expr catch \|e\| { arm => {…} }` | Inline error handling with arm matching; `_` wildcard |
| `error.Name` | Match a specific error variant |

```
n := @i32(@input("number: ")) catch 0

f := try @fs::file_reader::open("log.txt")
defer f.cl()
```

---

## Packages & Imports

### Built-in (no import)

`@fs::`, `@math::`, `@kry::`, `@fflog::`, `@xi::`, `@mem::`, `@list`, `@alo`, `@free`, `@rng`, `@pl`, `@pf`, `@cout`, `@cin`, `@input`, `@sys::`, etc.

### NativeSysPkg (system install required, no `zcy add`)

| Import | Library |
|--------|---------|
| `@import(omp = @zcy.openmp)` | OpenMP threading |
| `@import(sodium = @zcy.sodium)` | libsodium crypto |
| `@import(db = @zcy.sqlite)` | SQLite3 |
| `@import(qt = @zcy.qt)` | Qt5/Qt6 |

### ZcytheAddLinkPkg (`zcy add` required)

| Import | Library |
|--------|---------|
| `@import(rl = @zcy.raylib)` | raylib 2D/3D |

### `@zcy.openmp` — OpenMP

| Call | Returns | Description |
|------|---------|-------------|
| `omp.set_threads(n)` | void | Set thread pool size |
| `omp.max_threads()` | `i32` | Max available threads |
| `omp.num_threads()` | `i32` | Threads in current region |
| `omp.thread_id()` | `i32` | Current thread ID (0-based) |
| `omp.wtime()` | `f64` | Wall-clock seconds |
| `omp.in_parallel()` | `bool` | True inside parallel region |
| `omp.parallel { }` | — | Spawn N threads, all run body |
| `omp.for v => range { }` | — | Parallel loop over integer range |

### `@zcy.sodium` — libsodium

| Call | Returns | Description |
|------|---------|-------------|
| `sodium.hash(pw)` | `str` | Argon2id hash → self-describing string |
| `sodium.hash_auth(pw, hash)` | `bool` | Constant-time verification |
| `sodium.enc_file(path, key)` | void | XChaCha20-Poly1305 encrypt in-place |
| `sodium.dec_file(path, key)` | void | Decrypt in-place |

### `@zcy.sqlite` — SQLite3

| Call | Returns | Description |
|------|---------|-------------|
| `db.open(path)` | connection | Open or create database |
| `conn.exec(sql)` | void | Execute SQL |
| `conn.prepare(sql)` | statement | Prepare statement |
| `stmt.step()` | `bool` | Advance to next row |
| `stmt.col_str(i)` | `str` | Column `i` as string |
| `stmt.col_int(i)` | `i64` | Column `i` as integer |
| `stmt.finalize()` | void | Finalize statement |
| `conn.close()` | void | Close connection |

### `@zcy.qt` — Qt

| Call | Returns | Description |
|------|---------|-------------|
| `qt.app()` | app | Create Qt application |
| `qt.window(title, w, h)` | window | Create window |
| `qt.label(text)` | widget | Label |
| `qt.button(text)` | widget | Push button |
| `qt.input(placeholder)` | widget | Line-edit |
| `qt.checkbox(text)` | widget | Checkbox |
| `qt.spinbox(min, max)` | widget | Integer spinbox |
| `qt.vbox()` | layout | Vertical box layout |
| `qt.hbox()` | layout | Horizontal box layout |
| `layout.add(widget)` | void | Add widget to layout |
| `win.set_layout(layout)` | void | Attach layout |
| `win.show()` | void | Show window |
| `app.process_events()` | void | Poll events |
| `app.should_quit()` | `bool` | True when app should exit |
| `widget.clicked()` | `bool` | Button clicked this frame |
| `widget.set_text(str)` | void | Update text |

---

## CLI — `zcy`

| Command | Description |
|---------|-------------|
| `zcy version` | Print Zcythe version |
| `zcy init` | Create a new project in the current directory |
| `zcy build` | Transpile `.zcy` → Zig → binary (`zcy-bin/`) |
| `zcy build-src` | Transpile only: `.zcy` → `src/zcyout/` |
| `zcy build-out` | Compile only: `src/zcyout/` → `zcy-bin/` |
| `zcy run` | Build and run |
| `zcy sac <files…>` | Compile one or more `.zcy` files to a standalone binary |
| `zcy test` | Run all `@test` blocks |
| `zcy test <file>` | Run tests from a specific file |
| `zcy add <pkg>` | Add a ZcytheAddLinkPkg |
| `zcy lspkg` | List available packages |

### Project layout

```
my_project/
  src/
    main/
      zcy/
        main.zcy      ← entry point
    zcyout/           ← generated Zig (gitignore)
  zcy-bin/            ← compiled binary (gitignore)
  zig-out/            ← Zig build output (gitignore)
  build.zig           ← generated by zcy init
```
