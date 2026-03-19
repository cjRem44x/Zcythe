# Build Notes

## v0.1.5 — 2026-03-19

- **`@kry::` builtins** — pure-Zig crypto (PBKDF2-HMAC-SHA512 + AES-256-GCM); no external library required

---

### `@kry::` crypto builtins

Password hashing and file encryption using only `std.crypto` — no external dependencies.

```zcy
@main {
    pw :: "my-password"

    # Hash a password — returns "hex(salt)$hex(key)" (129 chars)
    h := @kry::hash(pw)
    @pl(h)

    # Verify — true if password matches the stored hash
    ok := @kry::hash_auth(pw, h)
    @pf("matches: {ok}\n")

    # Encrypt a file in-place (AES-256-GCM, PBKDF2-derived key)
    @kry::enc_file("secret.txt", pw)

    # Decrypt
    @kry::dec_file("secret.txt", pw)
}
```

| Builtin | Action |
|---------|--------|
| `@kry::hash(pw)` | PBKDF2-HMAC-SHA512, 600k iter, random 32-byte salt → `"hex_salt$hex_key"` |
| `@kry::hash_auth(pw, stored)` | Verify password against stored hash → `bool` |
| `@kry::enc_file(path, pw)` | AES-256-GCM encrypt file in-place |
| `@kry::dec_file(path, pw)` | AES-256-GCM decrypt file in-place |

Encrypted file layout: `[32-byte salt][12-byte nonce][ciphertext][16-byte GCM tag]`.

---

## v0.1.4 — 2026-03-19

- **`build-src`** — transpile `.zcy → src/zcyout` only; skip `zig build-exe` (useful when hand-editing generated Zig)
- **`build-out`** — compile `src/zcyout → zcy-bin` only; skip transpile (re-compile after manual edits)
- **`build`** — unchanged; full pipeline as before

---

## v0.1.2

### SQLite3 bindings — `@zcy.sqlite`

First-class SQLite3 support via NativeSysPkg. Import with an alias and use `alias.method()` everywhere — no `@sqlite::` prefix at call sites.

```zcy
@import(db = @zcy.sqlite)

@main {
    conn := db.open(":memory:")
    conn.exec("CREATE TABLE t (name TEXT, val INTEGER)")
    stmt := conn.prepare("SELECT name, val FROM t ORDER BY val DESC")
    while stmt.step() {
        @pf("{stmt.col_str(0)}: {stmt.col_int(1)}\n")
    }
    stmt.finalize()
    conn.close()
}
```

Auto-links `-lsqlite3` when detected. Requires system install (`dnf install sqlite-devel` / `apt install libsqlite3-dev`).

---

### Qt5/Qt6 bindings — `@zcy.qt`

Polling-style Qt widget API via NativeSysPkg. No callbacks — check widget state each frame.

```zcy
@import(qt = @zcy.qt)

@main {
    app    := qt.app()
    win    := qt.window("Counter", 300, 200)
    lbl    := qt.label("0")
    inc    := qt.button("+1")

    layout := qt.vbox()
    layout.add(lbl)
    layout.add(inc)
    win.set_layout(layout)
    win.show()

    count := 0
    while !app.should_quit() {
        app.process_events()
        if inc.clicked() { count += 1 ; lbl.set_text(@str(count)) }
    }
}
```

Compiles a thin C++ wrapper at build time and links it with Qt. Requires system install (`dnf install qt6-qtbase-devel` / `apt install qt6-base-dev`).

Widgets: `label`, `button`, `input`, `checkbox`, `spinbox`. Layouts: `vbox`, `hbox`.

---

### `@str(expr)` builtin

Convert any value to a string:

```zcy
n := 42
s := @str(n)    # "42"
```

---

### `@str::parseNum(s)` builtin

Parse a string to a number — type is inferred from the variable's declared type:

```zcy
x: i32 = @str::parseNum("42")
y: f64 = @str::parseNum("3.14")
```

Defaults to `i64` when no type annotation is present.

---

### NativeSysPkg vs ZcytheAddLinkPkg

Two distinct package categories are now formalised:

| Category | Examples | Setup |
|----------|---------|-------|
| **NativeSysPkg** | `@zcy.sqlite`, `@zcy.qt`, `@zcy.sodium`, `@zcy.openmp` | OS package manager, auto-linked |
| **ZcytheAddLinkPkg** | `@zcy.raylib`, `owner/repo` | `zcy add`, stored in `zcy-pkgs/` |

---

### `zcy lspkg`

New command — lists all available packages with type and per-distro install commands:

```
zcy lspkg
```

---

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
