# Build Notes

## v0.2.7 — 2026-04-22

- **Remove `cls`** — class keyword, parser, AST types (`ClsExtends`, `ClsDecl.extends`), codegen, and all tests removed. `struct` continues to handle named types with methods unchanged.
- **`dat` → Static Data Block** — `dat Name { field: T }` now emits a mutable module-level singleton `var Name = struct { field: T = <zero> } {};`. All fields are zero-initialised by default and accessed as `Name.field`. No instance syntax needed.
- **`kw_ovrd` removed** — `ovrd` keyword removed from lexer; `is_ovrd` field in `ClsMethod` always false now (no user-facing effect on `struct`).
- **`@alo::dat` / `@alo::cls` removed** — use `@alo::struct(T)` for heap-allocated struct instances.
- **Docs updated** — `04_types.md`, `Index.md`, `Intro.md`, `01_variables.md`, `13_testing.md` updated.

---

## v0.2.6 — 2026-03-20

- **GCC 15 / `.sframe` linker fix** — Zig 0.15's self-hosted linker cannot handle the `R_X86_64_PC64` relocations that GCC 15 places in the `.sframe` section of `crt1.o`. Any `zcy` compilation that linked a native system library (`@xi::`, `@zcy.omp`, `@zcy.sodium`, `@zcy.sqlite`, `@zcy.qt`) would fail with `unhandled relocation type R_X86_64_PC64`. Fixed by passing `-target x86_64-linux-gnu.2.17 -L/usr/lib -I/usr/include` when system libraries are linked, which causes Zig to use its own bundled `crt1.o` (no `.sframe`) rather than the system one.
- **Remove `link_libc` from module** — `build.zig` had `.link_libc = true` on the Zcythe module, causing the compiler itself to link against system libc and hit the same `.sframe` crash. The compiler's own code (lexer / parser / codegen) uses no C functions; the flag was unnecessary and removed.

---

## v0.2.5 — 2026-03-19

- **Remove `@fs::reader` / `@fs::writer`** — the handle-based `init`/`open`/`cl` API was removed; use `@fs::file_reader` and `@fs::file_writer` instead

---

## v0.2.4 — 2026-03-19

- **Fast catch** — `expr catch default` shorthand; catches any error and returns `default`; complements the full `catch |e| { arm => … }` form for specific matching
- **`@fs::` snake_case names** — `@fs::file_reader`, `@fs::file_writer`, `@fs::byte_reader`, `@fs::byte_writer` (was PascalCase)
- **`tryRegisterFileVar` catch unwrap** — file vars declared via `catch` form are now correctly registered
- **`07_fs.md` rewrite** — clear API overview table distinguishing all six I/O APIs

---

## v0.2.3 — 2026-03-19

- **`docs/Index.md`** — comprehensive language reference covering every keyword, builtin, operator, type, namespace (`@fs::`, `@math::`, `@kry::`, `@fflog::`, `@xi::`), package API, and `zcy` CLI command with return types and descriptions
- **`elif` docs** — `02_control_flow.md` updated to use `elif` as the canonical form in all examples; noted `else if` still works as alias
- **Version bump** → v0.2.3

---

## v0.2.2 — 2026-03-19

- **`elif`** — new keyword; `if cond {} elif cond {} else {}` chains; desugars to nested `if_stmt` in else branch — no AST change required
- **`NULL`** — null pointer sentinel for heap pointer comparisons: `if H.p == NULL { … }` → emits `null`
- **`undef` in comparisons** — `x == undef` / `x != undef` emits `x == null` / `x != null` for optional-type null-checking pattern
- **`@fs::ls(path)`** — list directory entries; returns `?[]_ZcyDirEntry` (null on error); entries have `.path()`, `.isFile()`, `.isDir()` methods and the slice has `.len`
- **`@fs::reader::init(path)`** — create a `?_ZcyReader`; null if path not found; call `.open()` to open, `.cl()` to close, `.readLine(buf)` to read
- **`@fs::writer::init(path)`** — create a `?_ZcyWriter`; call `.open()`, `.write(str)`, `.cl()`
- **`@pf` multi-arg specifier inference** — bare `{}` placeholders now pick `{s}` for string/call-expr arguments automatically; prevents "cannot format slice without specifier" compile errors
- **`@fs::ls` subscript** — `files[i]` on an ls var auto-emits `files.?[@as(usize, @intCast(i))]`
- **`@fs::ls` field access** — `files.len` / `files.isFile` auto-unwrap with `.?`

---

## v0.2.1 — 2026-03-19

- **`@xi::` handle passing** — `@xi::win`, `@xi::img`, `@xi::gif`, `@xi::fnt` can be passed to functions by value (`param: @xi::type`) or by reference (`param: &@xi::type`); call sites use `&handle` for ref, bare `handle` for by-value
- **By-value xi params** — emitted with `_xiv_` suffix in Zig signature + a local `var` shadow, so field mutations (scale, load) compile but stay local to the copy
- **Ref param scope isolation** — `xi_ref_var_names` registry is saved/restored around each function body so ref params from one function don't bleed into `@main` or other functions
- **Fix: double `defer _xiDestroyFont`** — removed auto-emit font defer from var decl; `defer fnt.free()` is the single cleanup path, consistent with img/gif
- **Fix: `defer img.free()` / `gif.free()` missing `&`** — root cause was ref param names leaking into global registry during pre-scan; fixed by not calling `recordXiRefVar` in `scanNodeForXiVars`

---

## v0.2.0 — 2026-03-19

- **`img.load(path)` / `gif.load(path)`** — real-time resource reload: frees old GPU texture(s), loads new path, preserves scale/loop/delay settings on gif
- **`img.scale(w, h)` / `gif.scale(w, h)`** — real-time draw size override; `0` resets to natural size
- **`gif.delay(N)` real-time** — already worked; now documented as truly live (takes effect next `win.draw` call)
- **`@sys::sleep(ms)`** — sleep for N milliseconds (`std.Thread.sleep`, multiplied to nanoseconds internally)
- **`@xi::` comprehensive docs** — new `docs/fullscope/17_xi.md` covering all window management, monitor queries, event blocks, fonts, images, GIFs, colors, the full key constant table, draw model semantics, and implementation notes; added to table of contents
- **`12_raylib.md` updated** — added `@xi::` preference note pointing to `17_xi.md`

---

## v0.1.8 — 2026-03-19

- **`_XiKeyval` full US keyboard** — expanded key constants to cover the complete US standard keyboard: LGUI/RGUI/MENU, all punctuation (GRAVE, MINUS, EQUALS, LBRACKET, RBRACKET, BACKSLASH, SEMICOLON, QUOTE, COMMA, PERIOD, SLASH), navigation cluster (INS, HOME, PGUP, PGDN, END), lock keys (CAPS, NUMLOCK, SCROLL), system keys (PRTSCR, PAUSE), and full numpad (KP0–KP9, KP_DOT, KP_PLUS, KP_MINUS, KP_MUL, KP_DIV, KP_ENTER, KP_EQ)

---

## v0.1.7 — 2026-03-19

- **`zcy sac` + `@xi::`** — `sac` now supports `@xi::` programs; symlinks raylib-zig into the temp build dir, runs `zig build`, and copies the binary out; temp dir is fully cleaned up
- **`zig-out` cleanup** — `zcy build` and `zcy build-out` now delete `zig-out/` after copying the binary to `zcy-bin/`; only `zcy-bin/` remains after a raylib build

---

## v0.1.6 — 2026-03-19

- **`@xi::` graphics framework** — built-in raylib-backed window/draw/event system; auto-links raylib with no `zcy add` required

---

### `@xi::` graphics framework

Declarative window, draw, and event blocks backed by raylib. No import or `zcy add` needed — the compiler detects `@xi::` usage and links raylib automatically.

```zcy
@main {
    win := @xi::window(800, 450, "My Window")
    win.fps(60)
    win.center()

    while win.loop {
        win.frame {
            close => { win.default },
            min   => { win.default },
            max   => { win.default }
        }

        win.keys {
            key_press => {
                n := win.key.code
                if n == win.keyval.ESC { @sys::exit(0) }
            },
            key_type => {}
        }

        win.draw {
            win.clearbg(win.color.darkblue)
            win.text("Hello from @xi!", 200, 180, 32, win.color.white)
            win.text("Press ESC to quit", 240, 230, 20, win.color.lightgray)
        }
    }
}
```

| Builtin / Expression | Action |
|---------------------|--------|
| `@xi::window(w, h, title)` | Create window; returns handle |
| `@xi::color(r, g, b, a)` | Custom RGBA color |
| `win.fps(n)` | Set target FPS |
| `win.center()` | Center on primary monitor |
| `win.loop` | Loop condition |
| `win.frame { event => {} }` | Window state events (`close`, `min`, `max`, `open`) |
| `win.keys { event => {} }` | Keyboard events (`key_press`, `key_type`) |
| `win.mouse { event => {} }` | Mouse events (stub) |
| `win.draw { … }` | Drawing block |
| `win.clearbg(color)` | Clear background |
| `win.text(s, x, y, size, color)` | Draw text |
| `win.color.NAME` | 32 named colors (raylib palette + extras) |
| `win.keyval.KEY` | Key constants (A–Z, 0–9, ESC, ENTER, SPACE, arrows, F1–F12, modifiers) |
| `win.key.code` | Current key keycode |
| `win.key.char` | Current key char (u8) |
| `win.default` | Default event handler |

**Implementation notes:**
- `@xi::window(…)` emits `rl.initWindow` inside a block expression; variable emit adds `_ = &win;` to suppress unused warning
- `win.center()` emits two statements: `const _xim = rl.getCurrentMonitor();` + `rl.setWindowPosition(…)`
- `win.frame { close => … }` emits `if (rl.windowShouldClose()) { … }` chains
- `win.keys { key_press => … }` emits `var _xi_kp = rl.getKeyPressed(); while (…) { … }` loop
- `win.keys { key_type => … }` emits `var _xi_cp = rl.getCharPressed(); while (…) { … }` loop
- `win.draw { … }` wraps body in `rl.beginDrawing()` / `rl.endDrawing()`
- Parser detects xi blocks post-hoc in `parseExprStmt` after seeing `field_expr` + `{`

---

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
