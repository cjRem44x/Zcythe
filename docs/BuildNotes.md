# Build Notes

## v0.1.0

### Raylib import syntax updated to `@zcy.raylib`

The canonical raylib import is now:

```zcy
@import(rl = @zcy.raylib)
```

This follows the `@eco.x.y` package namespace pattern.  The bare
`@import(rl = raylib)` form still works as a fallback but `@zcy.raylib`
is preferred.

Generated `build.zig` now calls `exe.linkLibrary(rl_dep.artifact("raylib"))`
so the C raylib library is properly linked on all platforms (fixes build
failures on Arch Linux and other distros).

---

## v0.0.7

### Enums

#### Syntax

```zcy
enum X { ONE, TWO, THREE }            # plain enum
enum Z => i32 { P = 10, Q = 20 }     # integer-backed (any int or char type)
enum Y => f32 { A = 3.145, B = 5.67 }# non-integer backing (f32, f64, bool, str, …)
```

#### Dot-literal syntax

Enum variants are written with a leading `.` in expression position:

```zcy
x: X = .ONE
y: Y = .A
```

Parsed as `enum_lit` AST nodes in `parsePrimary`. Emitted as `.VARIANT` in Zig
(Zig's inferred-type enum literal syntax).

#### Codegen

| Zcythe | Zig output |
|--------|------------|
| `enum X { A, B }` | `pub const X = enum { A, B, };` |
| `enum Z => i32 { P=10 }` | `pub const Z = enum(i32) { P = 10, pub fn val(…) i32 { … } };` |
| `enum Y => f32 { A=3.145 }` | `pub const Y = enum { A, pub fn value(…) f32 { … } };` |
| `enum S => str { A="hi" }` | `pub const S = enum { A, pub fn value(…) []const u8 { … } };` |

- **Integer-backed** (`u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`,
  `u128`, `i128`, `usize`, `isize`, `char`): Zig supports `enum(T)` natively.
  A `.val()` method is emitted as shorthand for `@intFromEnum(self)`.
- **Non-integer backing** (`f32`, `f64`, `f128`, `bool`, `str`, etc.): Zig only
  supports integer backing types, so a plain enum is emitted with a `.value()`
  method that returns the backing type via a `switch`.

#### Helper: `isIntBackingType` (codegen.zig)

Free function that returns `true` for types Zig accepts as enum backing types.
Used by `emitEnumDecl` to choose between the two codegen paths.

---

### Keywords as field/method names

`parsePostfix` previously required a strict `.ident` token after `.` for field
access. It now also accepts any keyword token (`kw_*`), allowing method names
that collide with language keywords (e.g. `.val()`, `.ret()`) to be called
without a parse error.

`TokenKind.isKeyword()` was added to `lexer.zig` to support this check cleanly.

---

### `@fs` namespace

| Builtin | Action |
|---------|--------|
| `@fs::mkdir(path)` | Create a directory |
| `@fs::mkfile(path)` | Create a file |
| `@fs::del(path)` | Delete a file or directory |
| `@fs::rename(old, new)` | Rename / move within the same parent |
| `@fs::mov(src, dst)` | Move to a different path |

`@fs::make` was split into `@fs::mkdir` + `@fs::mkfile` for clarity.

---

### `@cin` numeric coercion

`@cin >> x` now coerces the raw input string to the declared type of `x`
automatically (integers via `std.fmt.parseInt`, floats via `std.fmt.parseFloat`).
String variables receive the raw trimmed line as before.

---

### Memory: `[]T` allocation and `@free`

| Zcythe | Zig |
|--------|-----|
| `buf := malloc(n) []i32` | `var buf = try alloc.alloc(i32, n);` |
| `@free(buf)` | `alloc.free(buf);` |

The allocator is threaded through `@main` automatically when any allocation or
free is detected.

---

### `loop` init variable

`loop` now supports an optional initialiser expression before the count:

```zcy
loop i = 0, 10 { … }   # i counts 0..9
```

Emits `var i: usize = 0; while (i < 10) : (i += 1) { … }`.

---

### `@pf` subscript formatting

`@pf` format strings now support `{[n]}` subscript syntax to index into
array/slice arguments directly in the format string.

---

### Raylib import

`@import(rl = @zcy.raylib)` is the canonical raylib import and emits
`const rl = @import("raylib");` for the bundled `raylib-zig` binding.
