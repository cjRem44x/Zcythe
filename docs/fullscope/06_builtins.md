# Built-in Functions

Zcythe provides a rich set of built-in functions prefixed with `@`. They are not imported — they are always available.

---

## Output

### `@pl(expr)` — Print Line

Prints any value followed by a newline. Automatically chooses the right format specifier.

```
@pl("Hello, world!")
@pl(42)
@pl(3.14)
@pl(true)
```

### `@pf(fmt)` — Printf with Interpolation

Single-argument form: embed identifiers in `{name}` placeholders.

```
name := "Alice"
age  := 30
@pf("Name: {name}, Age: {age}\n")
```

Multi-argument form (explicit args):

```
@pf("coords: ({}, {})\n", x, y)
```

**Format specifiers** — add `: spec` inside the placeholder:

```
pi :: 3.14159265
@pf("pi = {pi:.4f}\n")    # pi = 3.1416

n := 255
@pf("hex = {n:x}\n")      # hex = ff
```

Common specifiers: `d` (integer), `f` (float), `.Nf` (N decimal places), `x` (hex lowercase), `X` (hex uppercase), `s` (string), `b` (binary), `e` (scientific notation).

### `@cout` — Stream Output

```
@cout << "value: " << x << @endl
```

Chain multiple `<<` for composite output. `@endl` writes a newline.

Format specifiers work with `<<` too:

```
@cout << (pi : ".3f") << @endl   # 3.142
```

---

## Input

### `@input(prompt)` — Read String

```
name := @input("Enter your name: ")
@pf("Hello, {name}!\n")
```

### `@input::T(prompt)` — Read Typed Value

Returns an error union. Use `catch` to handle parse failures.

```
n := @input::i32("Enter a number: ") catch |_| { _ => { 0 } }
f := @input::f64("Enter weight: ")   catch |_| { _ => { 0.0 } }
s := @input::str("Enter text: ")     # never fails
```

### `@sec_input(prompt)` — Hidden Input (Passwords)

Like `@input` but disables terminal echo while the user types. Useful for passwords and secrets. Restores echo automatically and prints a newline after Enter.

```
pass := @sec_input("Password: ")
@pl(pass)
```

### `@sec_input::T(prompt)` — Typed Hidden Input

Same typed form as `@input::T`, but with echo disabled.

```
pin := @sec_input::i32("Enter PIN: ") catch |_| { _ => { -1 } }
raw := @sec_input::str("Secret: ")
```

Cast form also works:

```
n := @i32(@sec_input("Enter number: ")) catch |_| { _ => { 0 } }
```

### `@cin` — Stream Input

```
@cin >> buf
```

---

## Program Control

### `@getArgs()` — Command-Line Arguments

```
args := @getArgs()
for arg => args {
    @pl(arg)
}
```

### `@sysexit(code)` — Exit Process

```
@sysexit(0)    # success
@sysexit(1)    # failure
```

### `@sys::time_ms()` — Millisecond Timestamp

Returns the current Unix time in milliseconds as `i64`.

```
t0 :: @sys::time_ms()
# ... work ...
t1 :: @sys::time_ms()
@pf("elapsed: {t1 - t0} ms\n")
```

### `@sys::time_ns()` — Nanosecond Timestamp

Returns the current Unix time in nanoseconds as `i64`. Useful for high-resolution timing.

```
t0 :: @sys::time_ns()
# ... work ...
elapsed := @sys::time_ns() - t0
@pf("elapsed: {elapsed} ns\n")
```

Both can be used directly inside `@pf` interpolation:

```
@pf("now = {@sys::time_ms()} ms\n")
```

### `@sys::sleep(ms)` — Sleep

Pauses execution for `ms` milliseconds. Blocks the current thread (including the window event loop if called inside one).

```
@sys::sleep(1000)    # sleep 1 second
@sys::sleep(3000)    # sleep 3 seconds
```

Useful for timed transitions before a main loop, or deliberate pauses in non-interactive programs.

---

## Type Utilities

### `@typeOf(expr)` — Runtime Type Name

Returns a `str` describing the Zcythe-visible type of `expr`.

```
x := 42
@pl(@typeOf(x))     # "int" (i32 displays as "int")

s := "hello"
@pl(@typeOf(s))     # "str"

f := 3.14
@pl(@typeOf(f))     # "f64"
```

---

## Numeric Casts

`@T(expr)` casts `expr` to type `T`. When `expr` is a string, it parses it.

```
big  : i64  = 100000
tiny := @i32(big)

raw  := @input("num: ")
n    := @i32(raw) catch |_| { _ => { -1 } }
```

Full list: `@i8 @i16 @i32 @i64 @i128 @u8 @u16 @u32 @u64 @u128 @usize @isize @f32 @f64 @f128`

---

## Randomness

### `@rng(T, min, max)` — Random Number

Returns a uniformly random value in the inclusive range `[min, max]`.

```
die  := @rng(i32, 1, 6)
prob := @rng(f64, 0.0, 1.0)
byte := @rng(u8, 0, 255)
```

---

## Memory

### `@malloc(T, n)` — Allocate Array

```
buf := @malloc(u8, 1024)
buf[0] = 65
buf[1] = 66
```

### `@free(ptr)` — Free Allocation

```
@free(buf)
```

### Allocator Handles

```
pa  := @getPageAlloc()           # page allocator (simple, no free needed)
gpa := @getGenPurpAlloc()        # general purpose allocator
aa  := @getArenaAlloc(gpa)       # arena on top of gpa
fba := @getFixedBufAlloc()       # 64 KB fixed buffer
```

---

## Dynamic Arrays (`@list`)

```
nums := @list(i32)
nums.add(1)
nums.add(2)
nums.add(3)

@pf("length: {nums.len}\n")

for n => nums {
    @pf("{n} ")
}

nums.remove(0)    # remove index 0
nums.clear()      # clear all
```

---

## Undefined Value

```
buf : [256]u8 = @undef    # declare without initializing
```

Only safe when you guarantee a write before any read.

---

## Quick Reference Table

| Builtin | Purpose |
|---------|---------|
| `@pl(v)` | Print value + newline |
| `@pf(fmt, …)` | Printf-style formatted print |
| `@cout << v` | Stream output |
| `@cin >> buf` | Stream input |
| `@endl` | Newline for `@cout` |
| `@input(prompt)` | Read line as string |
| `@input::i32(p)` | Read and parse integer |
| `@input::f64(p)` | Read and parse float |
| `@input::str(p)` | Read string (no parse) |
| `@sec_input(p)` | Read string, echo hidden |
| `@sec_input::T(p)` | Read typed value, echo hidden |
| `@getArgs()` | Command-line arguments |
| `@sysexit(n)` | Exit with code n |
| `@sys::time_ms()` | Unix time in milliseconds (i64) |
| `@sys::time_ns()` | Unix time in nanoseconds (i64) |
| `@typeOf(e)` | Type name string |
| `@T(expr)` | Numeric cast / string parse |
| `@rng(T, lo, hi)` | Random in [lo, hi] |
| `@malloc(T, n)` | Allocate `[]T` of length n |
| `@free(p)` | Free allocation |
| `@list(T)` | Growable array |
| `@undef` | Uninitialized sentinel |
| `@fs::ls(path)` | List directory entries → `?[]entry` |
| `@fs::reader::init(path)` | Buffered file reader handle |
| `@fs::writer::init(path)` | Buffered file writer handle |
| `@getPageAlloc()` | Page allocator handle |
| `@getGenPurpAlloc()` | GPA handle |
| `@getArenaAlloc(a)` | Arena allocator handle |
| `@getFixedBufAlloc()` | 64 KB fixed-buffer allocator |
