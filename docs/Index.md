# Zcythe Language Index

Complete reference for every keyword, builtin, type, operator, and CLI command.

---

## Table of Contents

1. [Keywords](#keywords)
2. [Declaration Sigils](#declaration-sigils)
3. [Operators](#operators)
4. [Primitive Types](#primitive-types)
5. [Composite Type Modifiers](#composite-type-modifiers)
6. [Control Flow](#control-flow)
7. [Functions](#functions)
8. [Built-in Functions — `@`](#built-in-functions)
9. [Namespace — `@str::`](#namespace-str)
10. [Namespace — `@fs::`](#namespace-fs)
11. [Namespace — `@math::`](#namespace-math)
12. [Namespace — `@kry::`](#namespace-kry)
13. [Namespace — `@fflog::`](#namespace-fflog)
14. [Namespace — `@xi::`](#namespace-xi)
15. [User-Defined Types](#user-defined-types)
16. [Error Handling](#error-handling)
17. [Packages & Imports](#packages--imports)
18. [CLI — `zcy`](#cli--zcy)

---

## Keywords

| Keyword | Category | Description |
|---------|----------|-------------|
| `and` | operator | Logical AND (alias `&&`) |
| `break` | control flow | Exit the nearest enclosing loop |
| `catch` | error handling | Recover from an error union |
| `cls` | type | Class with fields, init/deinit, and methods |
| `continue` | control flow | Skip to next loop iteration |
| `dat` | type | Plain data record — fields only, no methods |
| `defer` | resource | Schedule expression at scope exit (LIFO) |
| `elif` | control flow | Else-if branch in an `if` chain |
| `else` | control flow | Fallback branch for `if` / `switch` |
| `enum` | type | Enumeration, optionally with a backing type |
| `false` | literal | Boolean false |
| `fn` | declaration | Named function |
| `for` | control flow | Iterate over a collection, range, or with index |
| `if` | control flow | Conditional branch |
| `imu` | modifier | Immutable pointee: `*imu T` |
| `loop` | control flow | C-style `init, cond, update` loop |
| `not` | operator | Logical NOT (alias `!`) |
| `null` / `NULL` | literal | Null pointer sentinel — both accepted |
| `or` | operator | Logical OR (alias `\|\|`) |
| `ovrd` | modifier | Override a parent class method |
| `pub` | visibility | Expose a field or method in `struct` / `cls` |
| `ret` | control flow | Return from function; `ret` alone returns void |
| `struct` | type | Struct with fields and methods, no inheritance |
| `switch` | control flow | Match a value against arms; `_` wildcard; `\|binding\|` captures union payload |
| `true` | literal | Boolean true |
| `try` | error handling | Propagate error on failure, unwrap on success |
| `unn` | type | Tagged or plain union |
| `@undef` | sentinel | Uninitialized value sentinel |
| `while` | control flow | Loop while a condition holds |

---

## Declaration Sigils

| Form | Mutability | Type | Example |
|------|-----------|------|---------|
| `x := value` | mutable | inferred | `count := 0` |
| `x : T = value` | mutable | explicit | `count : i32 = 0` |
| `x :: value` | immutable | inferred | `PI :: 3.14159` |
| `x : T : value` | immutable | explicit | `PI : f64 : 3.14159` |

The compiler promotes `const` to `var` automatically when it detects mutation (assignment, `+=`, method calls with `@self`, `@cin >>`, `@str::cat`). You rarely need to think about this.

**Inline separator** — use `;` to write multiple statements on one line:

```
a := 1; b := 2; @pl(a + b)   # 3
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
| `%` | Modulo |

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
| `==` | Equal (string equality uses deep compare automatically) |
| `!=` | Not equal |
| `<` `<=` `>` `>=` | Relational |

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
| `+=` `-=` `*=` `/=` `%=` | Arithmetic-assign |
| `&=` `\|=` `^=` `<<=` `>>=` | Bitwise-assign |

### Range

| Syntax | Description |
|--------|-------------|
| `a..b` | Exclusive `[a, b)` |
| `a..=b` | Inclusive `[a, b]` |
| `a..` | Open-ended from `a` |

### Other

| Operator | Description |
|----------|-------------|
| `=>` | `for` iteration arrow / `switch` arm separator / `while` do-expr |
| `->` | Pointer field access: `p->field` = `(p.*).field` |
| `.` | Field or method access |
| `.*` | Explicit pointer dereference |
| `.?` | Optional unwrap (panics if null) |
| `<<` | `@cout` stream output |
| `>>` | `@cin` stream input |
| `;` | Inline statement separator |

---

## Primitive Types

### Integer

| Type | Width | Notes |
|------|-------|-------|
| `i8` | 8-bit signed | −128…127 |
| `i16` | 16-bit signed | |
| `i32` | 32-bit signed | common default integer |
| `i64` | 64-bit signed | |
| `i128` | 128-bit signed | |
| `isize` | pointer-sized signed | |
| `u8` | 8-bit unsigned | numeric; prints as integer |
| `u16` `u32` `u64` `u128` | unsigned variants | |
| `usize` | pointer-sized unsigned | |

### Floating-Point

| Type | Width |
|------|-------|
| `f16` | 16-bit IEEE 754 |
| `f32` | 32-bit |
| `f64` | 64-bit — common default float |
| `f128` | 128-bit |

### Other Primitives

| Type | Description |
|------|-------------|
| `str` | UTF-8 string slice — `[]const u8` in Zig |
| `chr` | Single ASCII character — same bits as `u8`, but prints as a character via `@pl` / `@pf` / `@cout` |
| `bool` | `true` / `false` |
| `void` | No return value |
| `noret` | Function never returns (e.g. wraps `@panic`) |
| `anytype` | Comptime-generic type parameter |

#### `chr` vs `u8`

Both are 8-bit unsigned integers. The distinction is **print behaviour only**:

```
c : chr = 'Z'
n : u8  = 90
@pl(c)                        # Z
@pl(n)                        # 90
@pf("chr={} num={}\n", c, n)  # chr=Z num=90
@cout << c << " " << n << @endl  # Z 90
```

`chr` literals use single quotes: `'A'`, `'\n'`, `'\t'`.

---

## Composite Type Modifiers

| Syntax | Description |
|--------|-------------|
| `[]T` | Slice — dynamic-length array |
| `[N]T` | Fixed-size array of N elements |
| `*T` | Nullable heap pointer — emitted as `?*T` in Zig; supports `== null` and `->` |
| `*imu T` | Pointer to immutable T (read-only pointee) |
| `*[]T` | Heap-owned slice — returned by `@alo(T, N)`; pass to `@free` |
| `@self` | Pointer to enclosing struct/cls instance — only valid as a parameter type in member functions |

#### `imu` — immutable pointer

`*imu T` means the value pointed at cannot be modified through this pointer. Use it for read-only function parameters:

```
fn print_name(p: *imu Person) {
    @pl(p->name)   # read OK
    # p->name = "x"  ← compile error
}
```

#### Array literals

Inline arrays with `[…]`:

```
nums  := [1, 2, 3, 4, 5]
names := ["Alice", "Bob", "Carol"]

for v => nums  { @pl(v) }
for n => names { @pl(n) }

@pl(nums[0])    # 1
@pl(names.len)  # 3
```

An empty array with an explicit type: `x :[]i32 = []`.

#### `@undef` — uninitialized sentinel

`@undef` has two uses:

**1 — Declare without initializing** (assign a real value before reading):

```
x := @undef
x  = 42
@pl(x)   # 42
```

**2 — Null/absent check** (e.g. on `@fs::ls` results):

```
entries := @fs::ls(".")
if entries != @undef {
    for e => entries { @pl(e.path()) }
}
```

`@undef` in a comparison behaves like a null check — it tests whether the value is the zero/null sentinel.

---

## Control Flow

### `if` / `elif` / `else`

```
score := 85

if score >= 90 {
    @pl("A")
} elif score >= 80 {
    @pl("B")
} elif score >= 70 {
    @pl("C")
} else {
    @pl("F")
}
```

Parentheses around the condition are not required.

### `for` — iteration

**Over a collection (element only):**

```
names := ["Alice", "Bob", "Carol"]
for name => names {
    @pl(name)
}
```

**Over a collection (index + element):**

```
for i, name => names {
    @pf("{}: {}\n", i, name)
}
```

**Over a range:**

```
for i => 0..5 {
    @pl(i)   # 0 1 2 3 4
}

for i => 1..=5 {
    @pl(i)   # 1 2 3 4 5
}
```

**Discard element (just run N times):**

```
for _ => 0..3 {
    @pl("hello")
}
```

**Over a `@list`:**

```
nums := @list(i32)
nums.add(10); nums.add(20); nums.add(30)
for v => nums { @pl(v) }
```

`break` and `continue` work inside any `for` body.

### `while`

**Basic:**

```
i := 0
while i < 5 {
    @pl(i)
    i += 1
}
```

**With do-expression** (executed after each iteration, like a `for` update):

```
i := 0
while i < 5 => i += 1 {
    @pl(i)
}
```

### `loop` — C-style

```
loop i := 0, i < 5, i += 1 {
    @pl(i)
}
```

Equivalent to `for (int i = 0; i < 5; i++)`. The init variable is scoped to the loop.

### `break` / `continue`

```
for i => 0..10 {
    if i == 3 { continue }   # skip 3
    if i == 7 { break }      # stop at 7
    @pl(i)
}
# prints: 0 1 2 4 5 6
```

### `defer`

Deferred expressions run at scope exit in reverse (LIFO) order. Ideal for cleanup:

```
f := try @fs::file_reader::open("data.txt")
defer f.cl()

p :*Person = @alo::dat(Person)
defer @free(p)
```

Multiple defers unwind in reverse order:

```
defer @pl("third")
defer @pl("second")
defer @pl("first")
# prints: first / second / third
```

### `switch`

**On integers or strings:**

```
code := 2
switch code {
    1 => { @pl("one") },
    2 => { @pl("two") },
    _ => { @pl("other") },   # wildcard
}
```

**On enum values:**

```
enum Dir { NORTH, SOUTH, EAST, WEST }
d : Dir = .NORTH

switch d {
    .NORTH => { @pl("north") },
    .SOUTH => { @pl("south") },
    _      => { @pl("other") },
}
```

**On a tagged union (with payload capture):**

```
unn Shape => enum {
    circle:    f64,
    rectangle: f64,
}

s : Shape = Shape.circle{5.0}

switch s {
    .circle    => |r| { @pf("circle r={}\n",   r) },
    .rectangle => |w| { @pf("rectangle w={}\n", w) },
}
```

`|binding|` after `=>` binds the active payload. Only `unn X => enum` supports capture.

---

## Functions

### Named functions

```
fn add(a: i32, b: i32) -> i32 {
    ret a + b
}

fn greet(name: str) {
    @pf("Hello {}!\n", name)
}
```

**Return type annotations:**

| Annotation | Meaning |
|------------|---------|
| `-> T` | Returns T |
| `-> T!` | Returns T or propagates an error |
| *(omitted)* | Returns void |
| `-> T?` | Returns optional T (null = absent) |

**Untyped parameters** — omit `: Type` to accept any type (comptime-generic):

```
fn double(x) { ret x * 2 }

@pl(double(5))      # 10
@pl(double(3.14))   # 6.28
```

**`pub` functions** — mark `pub` to export from the file for use in other modules:

```
pub fn greet(name: str) { @pf("Hi {}!\n", name) }
```

**`@comptime` parameters** — compile-time generic type parameter. Emits two Zig params: `comptime T: type, name: T`. Lets you write type-safe generic functions:

```
fn zero(@comptime T val) -> T {
    ret @T(0)
}

@pl(zero(@i32(0)))   # 0
@pl(zero(@f64(0)))   # 0.0
```

Use `anytype` in the return annotation when the return type depends on the comptime param.

**Anonymous struct return** — use `.{…}` to return a struct/dat literal without naming a temp variable. The type is inferred from the return annotation:

```
dat Point { x: i32, y: i32 }

fn origin() -> Point {
    ret .{.x = 0, .y = 0}
}

fn offset(p: Point, dx: i32, dy: i32) -> Point {
    ret .{.x = p.x + dx, .y = p.y + dy}
}
```

### Lambdas

```
double  := (x: i32 => i32) { ret x * 2 }
void_fn := (msg: str => _)  { @pl(msg) }   # _ = void return

@pl(double(5))   # 10
void_fn("hi")    # hi
```

Syntax: `(param: Type, … => ReturnType) { body }`. Pass inline to higher-order functions:

```
fn apply(f: (x: i32 => i32), v: i32) -> i32 { ret f(v) }

n := apply((x: i32 => i32) { ret x + 1 }, 10)   # 11
```

---

## Built-in Functions

All builtins start with `@` and require no import.

### Output

| Builtin | Description |
|---------|-------------|
| `@pl(expr)` | Print any value with a newline |
| `@pf(fmt, …)` | Printf-style formatted output |
| `@cout << v << … << @endl` | Streaming output; `@endl` appends newline |

#### `@pl` type dispatch

`@pl` auto-selects the right format: `str` prints as text, `chr` as a character, all others via `{any}`.

#### `@pf` format strings

Three forms:

```
name := "Alice"
age  := 30
# 1 — {ident} interpolation — single-string form, no extra args needed
@pf("Hello {name}, age {age}\n")

# 2 — {obj.field} field-access interpolation — also single-string
p := Person{.name = "Bob", .age = 25}
@pf("name={p.name} age={p.age}\n")

# 3 — positional {} with extra arguments
@pf("Hello {}, age {}\n", name, age)
```

Type inference for bare `{}`:

| Argument type | Emitted specifier |
|---------------|-------------------|
| `str` | `{s}` |
| `chr` | `{c}` |
| all others | `{}` |

Explicit specifiers (override inference):

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

#### `@cout` streaming

```
p := make_person("John", 24)
@cout << "Hello " << p.name << ", age " << p.age << @endl
```

`@cout` automatically uses `{s}` for `str`, `{c}` for `chr`, and `{any}` for everything else.

### Input

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@input(prompt)` | `str` | Read line from stdin |
| `@input::T(prompt)` | `T!` | Read and parse typed value — use `catch` for errors |
| `@input::str(prompt)` | `str` | Always returns a string (never fails) |
| `@sec_input(prompt)` | `str` | Read with echo disabled (passwords) |
| `@sec_input::T(prompt)` | `T!` | Typed hidden input |
| `@cin >> var` | — | Stream input — coerces to the variable's declared type |

```
name := @input("Name: ")
age  := @i32(@input("Age: ")) catch 0

# stream form
x : i32 = 0
@cin >> x
```

### Program Control

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@main { }` | — | Top-level entry point (required in every executable) |
| `@args` | `[]str` | Command-line arguments |
| `@sys::ex(code)` | never | Exit process with code |
| `@sys::sleep(ms)` | void | Sleep `ms` milliseconds |
| `@sys::waist(ms)` | void | Busy-wait `ms` ms (high precision) |
| `@sys::time_ms()` | `i64` | Unix time in milliseconds |
| `@sys::time_ns()` | `i64` | Unix time in nanoseconds |
| `@sys::cli(fmt, …)` | void | Run shell command with `{ident}` / `{}` interpolation |

```
host := "example.com"
@sys::cli("ping -c 1 {host}")
@sys::cli("echo {} {}", "hello", "world")
```

### Type Utilities

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@typeOf(expr)` | `str` | Runtime type name as a string |
| `@str(expr)` | `str` | Convert any value to a string |

```
n := 42
@pl(@typeOf(n))   # i32
@pl(@str(n))      # "42"
```

### Numeric Casts

`@T(expr)` casts to type T. When `expr` is a `str`, it parses it (returns an error union — use `catch`).

| Builtin | Target |
|---------|--------|
| `@i8` `@i16` `@i32` `@i64` `@i128` `@isize` | Signed integers |
| `@u8` `@u16` `@u32` `@u64` `@u128` `@usize` | Unsigned integers |
| `@f32` `@f64` `@f128` | Floats |

```
n := @i32("42") catch 0    # parse str → i32; 0 on failure
x := @f64(n)               # widen i32 → f64
b := @u8(255)              # numeric cast
```

### Randomness

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@rng(T, min, max)` | T | Uniform random value in `[min, max]` inclusive |

```
roll := @rng(i32, 1, 6)
prob := @rng(f64, 0.0, 1.0)
```

### Memory

#### Heap arrays — `@alo(T, N)`

```
buf :*[]i32 = @alo(i32, 8)
defer @free(buf)

buf[0] = 100
buf[1] = 200
@pl(buf[0])   # 100

for v => buf { @pl(v) }
```

`*[]T` indexes directly with `[i]` — no dereference needed.

#### Heap single instance — `@alo::dat / struct / cls`

```
dat Person { name: str, age: i32 }

p :*Person = @alo::dat(Person)
defer @free(p)

p->name = "Alice"
p->age  = 30

@pf("{} is {}\n", p->name, p->age)   # Alice is 30

if p == null { @pl("alloc failed") }
```

`->` is the pointer field-access operator (`p->field` = `(p.*).field`). Use it on any `*T` variable.

All `*T` heap pointers emit as `?*T` (nullable) in Zig — you can always compare them to `null`.

#### Allocator table

| Builtin | Returns | Description |
|---------|---------|-------------|
| `@alo(T, N)` | `*[]T` | Heap array of N elements |
| `@alo::str(s)` | `*str` | Heap-duplicate a string |
| `@alo::dat(T)` | `*T` | Heap-allocate a `dat` instance |
| `@alo::struct(T)` | `*T` | Heap-allocate a `struct` instance |
| `@alo::cls(T)` | `*T` | Heap-allocate a `cls` instance |
| `@free(ptr)` | void | Free any `@alo` result |
| `@undef` | — | Uninitialized-value sentinel |

### Namespace `@mem::`

Allocator handles for passing to Zig-compatible APIs. No import required.

| Name | Description |
|------|-------------|
| `@mem::Allocator` | `std.mem.Allocator` — use as parameter type |
| `@mem::page_alo` | Page allocator |
| `@mem::gen_purp_alo` | General-purpose allocator |
| `@mem::arena_alo` | Arena allocator |
| `@mem::fix_buf_alo` | 64 KB fixed-buffer allocator |

```
fn alloc_ints(alo: @mem::Allocator, n: usize) -> []i32 {
    ret try alo.alloc(i32, n)
}
```

### Dynamic Arrays — `@list`

| Builtin / Method | Returns | Description |
|------------------|---------|-------------|
| `@list(T)` | list | Growable typed array |
| `list.add(v)` | void | Append element |
| `list.remove(i)` | void | Remove element at index `i` |
| `list.clear()` | void | Remove all elements |
| `list.len` | `usize` | Number of elements |
| `list[i]` | T | Index access (read or write) |

```
words := @list(str)
words.add("apple")
words.add("banana")
words.add("cherry")

@pl(words[0])        # apple
words[0] = "avocado"

for i, w => words {
    @pf("{}: {}\n", i, w)
}
# 0: avocado  1: banana  2: cherry
```

### Testing

| Builtin | Description |
|---------|-------------|
| `@test "name" { }` | Declare a test block |
| `@assert(cond)` | Fail the test if `cond` is false |
| `@assert_eq(a, b)` | Fail if `a != b` |
| `@assert_str(a, b)` | Fail if strings differ |

```
fn add(a: i32, b: i32) -> i32 { ret a + b }

@test "addition" {
    @assert_eq(add(2, 3), 5)
    @assert_eq(add(-1, 1), 0)
}

@test "strings" {
    s := "hello"
    @assert_str(s, "hello")
}
```

Run with `zcy test`.

---

## Namespace `@str::`

String utilities. No import required.

### Mutation (modify a `str` variable in-place)

| Call | Description |
|------|-------------|
| `@str::cat(dest, src)` | Append `src` to `dest` |
| `@str::repall(dest, old, new)` | Replace every occurrence of `old` with `new` |
| `@str::repsub(dest, old, new)` | Replace only the first occurrence of `old` with `new` |

```
s :str = "Hello World"
@str::cat(s, "!")
@pl(s)   # Hello World!

@str::repall(s, "l", "r")
@pl(s)   # Herro Worrd!

t :str = "aabbaa"
@str::repsub(t, "a", "x")
@pl(t)   # xabbaa
```

### Predicates (return `bool`)

| Call | Description |
|------|-------------|
| `@str::in(s, sub)` | True if `s` contains `sub` |
| `@str::start(s, prefix)` | True if `s` starts with `prefix` |
| `@str::end(s, suffix)` | True if `s` ends with `suffix` |

```
if @str::in("Hello World", "World")  { @pl("found") }
if @str::start("Hello", "He")        { @pl("starts He") }
if @str::end("Hello", "lo")          { @pl("ends lo") }
```

### Transforms (return a new `str`)

| Call | Description |
|------|-------------|
| `@str::low(s)` | Lowercase copy |
| `@str::up(s)` | Uppercase copy |
| `@str::trim(s)` | Strip leading and trailing whitespace |
| `@str::ltrim(s)` | Strip leading whitespace only |
| `@str::rtrim(s)` | Strip trailing whitespace only |
| `@str::trimall(s)` | Remove every whitespace character (spaces, tabs, newlines, carriage returns) |

```
low  := @str::low("Hello WORLD")   # "hello world"
high := @str::up("hello world")    # "HELLO WORLD"

padded := "  hello  "
@pl(@str::trim(padded))      # "hello"
@pl(@str::ltrim(padded))     # "hello  "
@pl(@str::rtrim(padded))     # "  hello"
@pl(@str::trimall("h e l")) # "hel"
```

### Split (return `[]str`)

| Call | Description |
|------|-------------|
| `@str::spl(s, delim)` | Split `s` on `delim`; returns a `[]str` slice |

```
parts :[]str = @str::spl("one,two,three", ",")
for p => parts { @pl(p) }   # one / two / three
```

### Notes

- String subscript `s[i]` yields a `u8` byte. Iterate characters with `for ch => s` (each `ch` is a `u8`).
- `s.len` gives the byte length (`usize`) — valid on any `str` or `[]str` slice.
- String equality (`==` / `!=`) performs deep comparison automatically.

---

## Namespace `@fs::`

File system utilities. No import required.

### Path Utilities

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::is_file(path)` | `bool` | True if path exists and is a regular file |
| `@fs::is_dir(path)` | `bool` | True if path exists and is a directory |
| `@fs::mkdir(path)` | void | Create directory (and all parents) |
| `@fs::mkfile(path)` | void | Create empty file (truncates if exists) |
| `@fs::del(path)` | void | Delete file or directory |
| `@fs::rename(old, new)` | void | Rename / move |
| `@fs::mov(src, dst)` | void | Move (alias for rename) |

### Directory Listing

| Call | Returns | Description |
|------|---------|-------------|
| `@fs::ls(path)` | `?[]entry` | List directory; `@undef` if path invalid |
| `e.path()` | `str` | Absolute path of entry |
| `e.is_file()` | `bool` | True if regular file |
| `e.is_dir()` | `bool` | True if directory |
| `entries.len` | `usize` | Number of entries |

```
entries := @fs::ls("./src")
if entries != @undef {
    for e => entries {
        if e.is_file() { @pl(e.path()) }
    }
}
```

### `file_reader`

Open with `try @fs::file_reader::open(path)`. Wrap in `defer f.cl()`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.rall()` | `str!` | Read entire file as a string |
| `f.rln()` | `str!` | Read one line (strips `\n`) |
| `f.rch()` | `chr!` | Read a single character |
| `f.r(n)` | `[]u8!` | Read exactly n bytes |
| `f.eof()` | `bool` | True when no more data |
| `f.cl()` | void | Close |

```
f := try @fs::file_reader::open("log.txt")
defer f.cl()
while !f.eof() {
    line := f.rln() catch break
    @pl(line)
}
```

### `file_writer`

Open with `try @fs::file_writer::open(path)`. Wrap in `defer f.cl()`.

| Method | Returns | Description |
|--------|---------|-------------|
| `f.w(data)` | `void!` | Write bytes or string |
| `f.wln(data)` | `void!` | Write string + newline |
| `f.wch(byte)` | `void!` | Write single byte |
| `f.fl()` | `void!` | Flush to disk |
| `f.cl()` | void | Close |

```
f := try @fs::file_writer::open("out.txt")
defer f.cl()
try f.wln("line one")
try f.wln("line two")
```

### Binary I/O (`byte_reader` / `byte_writer`)

Open with `try @fs::byte_reader::open(path)` or `try @fs::byte_writer::open(path)`. Pass `@fs::Little` or `@fs::Big` when reading/writing multi-byte values.

| Constant | Description |
|----------|-------------|
| `@fs::Little` | Little-endian byte order |
| `@fs::Big` | Big-endian byte order |

**`byte_reader` read methods** — each returns the typed value or an error (`!`):

| Method | Returns |
|--------|---------|
| `f.ri8(e)` `f.ru8(e)` | `i8!` / `u8!` |
| `f.ri16(e)` `f.ru16(e)` | `i16!` / `u16!` |
| `f.ri32(e)` `f.ru32(e)` | `i32!` / `u32!` |
| `f.ri64(e)` `f.ru64(e)` | `i64!` / `u64!` |
| `f.ri128(e)` `f.ru128(e)` | `i128!` / `u128!` |
| `f.rf16(e)` `f.rf32(e)` `f.rf64(e)` `f.rf128(e)` | float variants |
| `f.eof()` | `bool` |
| `f.cl()` | void |

**`byte_writer` write methods** — each takes the value and endianness:

| Method | Writes |
|--------|--------|
| `f.wi8(v, e)` `f.wu8(v, e)` | `i8` / `u8` |
| `f.wi16(v, e)` `f.wu16(v, e)` | `i16` / `u16` |
| `f.wi32(v, e)` `f.wu32(v, e)` | `i32` / `u32` |
| `f.wi64(v, e)` `f.wu64(v, e)` | `i64` / `u64` |
| `f.wi128(v, e)` `f.wu128(v, e)` | `i128` / `u128` |
| `f.wf16(v, e)` `f.wf32(v, e)` `f.wf64(v, e)` `f.wf128(v, e)` | float variants |
| `f.cl()` | void |

```
# write
w := try @fs::byte_writer::open("data.bin")
defer w.cl()
try w.wi32(42, @fs::Little)
try w.wf32(3.14, @fs::Little)

# read back
r := try @fs::byte_reader::open("data.bin")
defer r.cl()
n := try r.ri32(@fs::Little)   # 42
x := try r.rf32(@fs::Little)   # 3.14
```

---

## Namespace `@math::`

No import required.

| Call | Returns | Description |
|------|---------|-------------|
| `@math::pi` | f64 | π ≈ 3.14159… |
| `@math::abs(x)` | T | Absolute value |
| `@math::min(a, b, …)` | T | Minimum of 2+ values |
| `@math::max(a, b, …)` | T | Maximum of 2+ values |
| `@math::floor(x)` | f64 | Round down |
| `@math::ceil(x)` | f64 | Round up |
| `@math::sqrt(x)` | f64 | Square root |
| `@math::exp(base, exp)` | f64 | `base ^ exp` |
| `@math::log(x)` | f64 | Natural log (base e) |
| `@math::log2(x)` | f64 | Log base 2 |
| `@math::log10(x)` | f64 | Log base 10 |
| `@math::sin(x)` | f64 | Sine (radians) |
| `@math::cos(x)` | f64 | Cosine (radians) |
| `@math::tan(x)` | f64 | Tangent (radians) |

```
hyp := @math::sqrt(@f64(3*3 + 4*4))   # 5.0
@pf("pi = {.4f}\n", @math::pi)        # pi = 3.1416
```

---

## Namespace `@kry::`

Pure-Zig cryptography. No import required.

| Call | Returns | Description |
|------|---------|-------------|
| `@kry::hash(pw)` | `str` | PBKDF2-HMAC-SHA512, random salt → `"hex_salt$hex_key"` (129 chars) |
| `@kry::hash_auth(pw, stored)` | `bool` | Constant-time password verification |
| `@kry::enc_file(path, pw)` | void | AES-256-GCM encrypt file in-place |
| `@kry::dec_file(path, pw)` | void | AES-256-GCM decrypt file in-place |

Encrypted layout: `[32-byte salt][12-byte nonce][ciphertext][16-byte GCM tag]`.

```
hash   := @kry::hash("hunter2")
valid  := @kry::hash_auth("hunter2", hash)   # true
```

---

## Namespace `@fflog::`

Flat-file JSONL logger. No import required.

| Call | Returns | Description |
|------|---------|-------------|
| `@fflog::init(path)` | logger | Create logger pointing at `path` |
| `log.open()` | void | Open / create the log file |
| `log.close()` | void | Flush and close |
| `log.wr(level, component, msg)` | void | Append one JSON log line |

Entry format: `{"ts":…,"level":"…","component":"…","msg":"…"}`

```
log := @fflog::init("app.log")
log.open()
defer log.close()
log.wr("INFO", "main", "server started")
```

---

## Namespace `@xi::`

2D graphics backed by SDL2. No import required.

**Requires:** `SDL2`, `SDL2_ttf`, `SDL2_image`

### Window

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::window(w, h, title)` | window | Create window |
| `win.fps(n)` | void | Target frame rate |
| `win.center()` | void | Center on screen |
| `win.size(w, h)` | void | Resize |
| `win.minsize(w, h)` | void | Minimum resizable size |
| `win.maxsize(w, h)` | void | Maximum resizable size |
| `win.resize(bool)` | void | Enable / disable user resizing |
| `win.pos(x, y)` | void | Move window |
| `win.fullscreen(bool)` | void | Toggle fullscreen mode |
| `win.show()` | void | Show the window |
| `win.width()` | `i32` | Current window width |
| `win.height()` | `i32` | Current window height |
| `win.loop` | `bool` | Main loop condition |

### Monitors

| Call | Returns | Description |
|------|---------|-------------|
| `@xi::monitors()` | `i32` | Number of connected displays |
| `@xi::monitor_width(i)` | `i32` | Width of monitor `i` |
| `@xi::monitor_height(i)` | `i32` | Height of monitor `i` |
| `@xi::pri_monitor()` | `bool` | True if primary monitor is active |

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

All draw calls must be inside a `win.draw { … }` block.

| Call | Description |
|------|-------------|
| `win.draw { … }` | Drawing block — wraps begin/end frame |
| `win.clearbg(color)` | Clear to color |
| `win.text(fnt, str, x, y)` | Draw text using a loaded font |
| `win.rect(x, y, w, h, color)` | Filled rectangle |
| `win.circle(x, y, r, color)` | Filled circle |
| `win.line(x1, y1, x2, y2, color)` | Line |
| `win.img(img, x, y)` | Draw image at position |
| `win.gif(gif, x, y)` | Draw animated GIF frame at position |
| `win.border(color, thickness)` | Draw border around window interior |

### Colors

| Access | Description |
|--------|-------------|
| `win.color.NAME` | Named color — `black`, `white`, `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `darkblue`, `lightgray`, … |
| `@xi::color(r, g, b, a)` | Custom RGBA |

### Fonts, Images, GIFs

Declare with the handle type, then load before use:

| Type | Description |
|------|-------------|
| `@xi::fnt` | Font handle type |
| `@xi::img` | Image handle type |
| `@xi::gif` | Animated GIF handle type |

| Method | Description |
|--------|-------------|
| `fnt.load(path, size)` | Load TTF font at `size` points |
| `fnt.free()` | Free font resources |
| `img.load(path)` | Load image from file |
| `img.scale(w, h)` | Set draw size (`0` = natural size) |
| `img.free()` | Free image resources |
| `gif.load(path)` | Load animated GIF from file |
| `gif.scale(w, h)` | Set draw size |
| `gif.delay(N)` | Milliseconds per frame |
| `gif.free()` | Free GIF resources |

```
fnt : @xi::fnt
img : @xi::img
fnt.load("assets/font.ttf", 24)
img.load("assets/logo.png")
defer fnt.free()
defer img.free()

# inside win.draw { }
win.text(fnt, "Hello", 10, 10)
win.img(img, 100, 100)
```

### Handle Passing

```
fn draw_sprite(img: @xi::img) { … }       # by value
fn resize_win(win: &@xi::win) { … }       # by reference (&)
```

---

## User-Defined Types

### `dat` — Data Record

Fields only; no methods. Use for plain value types and function return values.

```
dat Person {
    name: str,
    age:  i32,
}
```

**Create an instance:**

```
p := Person{.name = "Alice", .age = 30}
@pl(p.name)   # Alice
@pl(p.age)    # 30
```

**Return from a function — anonymous literal (type inferred):**

```
fn make_person(name: str, age: i32) -> Person {
    ret .{.name = name, .age = age}
}

p := make_person("Bob", 25)
@pl(p.name)   # Bob
```

**Heap allocation:**

```
p :*Person = @alo::dat(Person)
defer @free(p)

p->name = "Charlie"   # -> for pointer field access
p->age  = 40

@pf("{} is {}\n", p->name, p->age)   # Charlie is 40
if p == null { @pl("alloc failed") }
```

---

### `struct` — Struct with Methods

Like `dat` but supports member functions via `@self`. No inheritance.

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
        ret .{.count = start}   # static factory
    }
}

ctr := Counter.make(0)
ctr.inc()
ctr.inc()
@pl(ctr.get())   # 2
```

**Field defaults** — omit a field in the literal to use its default:

```
struct Config {
    host:    str  = "localhost",
    port:    i32  = 8080,
    verbose: bool = false,
}

cfg  := Config{}                   # all defaults
cfg2 := Config{.port = 9090}       # host="localhost", port=9090, verbose=false
cfg3 := Config{.verbose = true}    # host="localhost", port=8080, verbose=true
@pf("{}:{}\n", cfg2.host, cfg2.port)   # localhost:9090
```

**Heap allocation:**

```
p :*Counter = @alo::struct(Counter)
defer @free(p)
p->count = 10
p->inc()          # methods work through ->
@pl(p->get())     # 11
```

#### `@self` parameter

`self: @self` = "mutable pointer to the enclosing struct". Rules:
- Must be the **first** parameter of a member function.
- **Omit entirely** for static (class-level) functions.
- The compiler automatically makes variables `var` when they call mutating methods.
- `self.field` accesses instance fields; `self.method()` calls other members.

#### Visibility

| Syntax | Effect |
|--------|--------|
| `field: T` | Private field |
| `pub field: T` | Public field |
| `fn method(self: @self)` | Private member function |
| `pub fn method(self: @self)` | Public member function |
| `pub fn static_fn()` | Public static function (no instance) |

---

### `unn` — Union

Holds exactly one active field at a time. Two forms:

#### Plain union

No runtime tag — caller tracks the active field:

```
unn Num {
    i: i32,
    f: f64,
}

n : Num = Num{.i = 42}     # struct-literal form
n  = Num.f{3.14}           # shorthand: Type.variant{value}
@pl(n.f)                    # 3.14
```

#### Tagged union — `unn X => enum { … }`

Carries an enum tag, enabling runtime field checks and `switch` capture:

```
unn Value => enum {
    int_val:  i32,
    flt_val:  f64,
    str_val:  str,
}

v : Value = Value.int_val{42}

switch v {
    .int_val => |n| { @pf("int:   {}\n", n) },
    .flt_val => |f| { @pf("float: {}\n", f) },
    .str_val => |s| { @pf("str:   {}\n", s) },
}
```

**Instantiation:**

| Syntax | Meaning |
|--------|---------|
| `Type.variant{value}` | Shorthand — set the named field |
| `Type{.variant = value}` | Struct-literal — always valid |

**Switch capture:** `\|binding\|` between `=>` and `{` binds the payload value. Only `unn X => enum` supports this; plain `unn` needs direct field access (`n.i`, `n.f`).

---

### `cls` — Class *(Beta)*

> **Beta:** `cls` is functional. Full method dispatch and interface enforcement are still being refined.

```
cls Animal {
    name: str,

    @init { self.name = "Animal" }
    @deinit { }

    pub fn speak() {
        @pf("{} makes a sound\n", self.name)
    }
}

cls Dog extends Animal {
    pub ovrd fn speak() {
        @pf("{} says woof!\n", self.name)
    }
}

d := Dog{}
d.name = "Rex"
d.speak()   # Rex says woof!
```

- `@init { }` — constructor body; `self` is available
- `@deinit { }` — destructor body
- Members are **private by default** — mark `pub` to expose
- `extends Parent` — single inheritance
- `ovrd` — override a parent method
- Use `@alo::cls(T)` and `@free` for heap instances

---

### `enum` — Enumeration

```
enum Direction { NORTH, SOUTH, EAST, WEST }

enum Status(i32) { IDLE = 0, RUNNING = 1, DONE = 2 }
```

**Usage:**

```
dir : Direction = .NORTH

switch dir {
    .NORTH => { @pl("north") },
    .SOUTH => { @pl("south") },
    _      => { @pl("east or west") },
}
```

Integer-backed enums expose `.val()` to get the raw integer value:

```
s : Status = .RUNNING
@pl(s.val())   # 1
```

---

## Error Handling

| Construct | Description |
|-----------|-------------|
| `try expr` | Propagate error on failure; unwrap value on success |
| `expr catch default` | Return `default` on any error (fast form) |
| `expr catch \|e\| { arm => {…} }` | Inline arm-based error handling; `_` wildcard |
| `error.Name` | Match a specific error variant |

```
# propagate
f := try @fs::file_reader::open("data.txt")

# fast default
n := @i32(@input("num: ")) catch 0

# arm matching
result := risky() catch |e| {
    error.NotFound  => { ret "missing" },
    _               => { ret "other" },
}
```

---

## Packages & Imports

### Always available (no import)

`@fs::`, `@math::`, `@kry::`, `@fflog::`, `@xi::`, `@str::`, `@mem::`, `@list`, `@alo`, `@free`, `@rng`, `@pl`, `@pf`, `@cout`, `@cin`, `@input`, `@sec_input`, `@sys::`, `@str`, `@typeOf`, etc.

### NativeSysPkg — system-installed libraries

| Import | Library |
|--------|---------|
| `@import(omp = @zcy.openmp)` | OpenMP threading |
| `@import(sodium = @zcy.sodium)` | libsodium crypto |
| `@import(db = @zcy.sqlite)` | SQLite3 |
| `@import(qt = @zcy.qt)` | Qt5/Qt6 GUI |

### ZcytheAddLinkPkg — install with `zcy add`

| Import | Library |
|--------|---------|
| `@import(rl = @zcy.raylib)` | raylib 2D/3D graphics |

### `@zcy.raylib` — raylib

After `@import(rl = @zcy.raylib)`, use the `@rl::` namespace. Unknown methods fall through to `rl.<method>` directly.

**Convenience constructors** — these wrap common raylib struct types with automatic type coercion:

| Call | Returns | Description |
|------|---------|-------------|
| `@rl::vec2(x, y)` | `Vector2` | 2D vector |
| `@rl::vec3(x, y, z)` | `Vector3` | 3D vector |
| `@rl::vec4(x, y, z, w)` | `Vector4` | 4D vector |
| `@rl::rect(x, y, w, h)` | `Rectangle` | Rectangle |
| `@rl::color(r, g, b, a)` | `Color` | RGBA color |
| `@rl::cam2d(target, offset, rot, zoom)` | `Camera2D` | 2D camera |
| `@rl::key(Name)` | `KeyboardKey` | Keyboard key constant (e.g. `@rl::key(space)`) |
| `@rl::btn(Name)` | `MouseButton` | Mouse button constant |
| `@rl::gamepad(Name)` | `GamepadButton` | Gamepad button constant |

**Named constants** — access via `@rl::Color::ray_white`, `@rl::KeyboardKey::space`, etc.:

```
@import(rl = @zcy.raylib)

pos  := @rl::vec2(100.0, 200.0)
col  := @rl::color(255, 0, 0, 255)
rect := @rl::rect(0.0, 0.0, 800.0, 600.0)
```

Any other raylib function: `rl.DrawCircle(x, y, r, col)`, `rl.DrawText(...)`, etc. — use the raw `rl.` prefix.

### `@zcy.openmp` — OpenMP

```
@import(omp = @zcy.openmp)
```

| Call | Returns | Description |
|------|---------|-------------|
| `omp.set_threads(n)` | void | Set thread pool size |
| `omp.max_threads()` | `i32` | Max available threads |
| `omp.num_threads()` | `i32` | Threads in current parallel region |
| `omp.thread_id()` | `i32` | Current thread ID (0-based) |
| `omp.wtime()` | `f64` | Wall-clock seconds |
| `omp.in_parallel()` | `bool` | True if inside a parallel region |
| `omp.parallel { }` | — | Spawn N threads, all execute body |
| `omp.for v => range { }` | — | Parallel loop over integer range |

```
@import(omp = @zcy.openmp)

omp.set_threads(4)
omp.parallel {
    id := omp.thread_id()
    @pf("thread {}\n", id)
}
```

### `@zcy.sodium` — libsodium

| Call | Returns | Description |
|------|---------|-------------|
| `sodium.hash(pw)` | `str` | Argon2id → self-describing hash string |
| `sodium.hash_auth(pw, hash)` | `bool` | Constant-time verification |
| `sodium.enc_file(path, key)` | void | XChaCha20-Poly1305 encrypt in-place |
| `sodium.dec_file(path, key)` | void | Decrypt in-place |

### `@zcy.sqlite` — SQLite3

| Call | Returns | Description |
|------|---------|-------------|
| `db.open(path)` | connection | Open or create database |
| `conn.exec(sql)` | void | Execute SQL statement |
| `conn.prepare(sql)` | statement | Prepare statement |
| `stmt.step()` | `bool` | Advance to next row |
| `stmt.col_str(i)` | `str` | Column `i` as string |
| `stmt.col_int(i)` | `i64` | Column `i` as integer |
| `stmt.finalize()` | void | Finalize prepared statement |
| `conn.close()` | void | Close connection |

```
conn := db.open("app.db")
conn.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER, name TEXT)")
conn.exec("INSERT INTO users VALUES (1, 'Alice')")

stmt := conn.prepare("SELECT * FROM users")
while stmt.step() {
    @pf("id={} name={}\n", stmt.col_int(0), stmt.col_str(1))
}
stmt.finalize()
conn.close()
```

### `@zcy.qt` — Qt GUI

| Call | Returns | Description |
|------|---------|-------------|
| `qt.app()` | app | Create Qt application |
| `qt.window(title, w, h)` | window | Create window |
| `qt.label(text)` | widget | Label |
| `qt.button(text)` | widget | Push button |
| `qt.input(placeholder)` | widget | Line-edit input |
| `qt.checkbox(text)` | widget | Checkbox |
| `qt.spinbox(min, max)` | widget | Integer spinbox |
| `qt.vbox()` | layout | Vertical box layout |
| `qt.hbox()` | layout | Horizontal box layout |
| `layout.add(widget)` | void | Add widget to layout |
| `win.set_layout(layout)` | void | Attach layout to window |
| `win.show()` | void | Show window |
| `app.process_events()` | void | Poll pending events |
| `app.should_quit()` | `bool` | True when app should close |
| `widget.clicked()` | `bool` | True if button was clicked this frame |
| `widget.set_text(str)` | void | Update widget text |

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
| `zcy sac <files…>` | Compile `.zcy` files to a standalone binary (no project required) |
| `zcy test` | Run all `@test` blocks in the project |
| `zcy test <file>` | Run tests from a single file |
| `zcy add <pkg>` | Add a ZcytheAddLinkPkg (`rl`, or `owner/repo`) |
| `zcy lspkg` | List available packages |

### Project layout

```
my_project/
  src/
    main/
      zcy/
        main.zcy        ← entry point
    zcyout/             ← generated Zig (gitignored)
  zcy-bin/              ← compiled binary (gitignored)
  zig-out/              ← Zig build system output (gitignored)
  build.zig             ← generated by zcy init
```

### Quick-start

```
zcy init
# edit src/main/zcy/main.zcy
zcy run
```

For a single-file script with no project:

```
zcy sac myscript.zcy -name=myscript
./myscript
```
