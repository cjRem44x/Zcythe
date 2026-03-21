# 🌀 Zcythe

A modern transpiled programming language that compiles to Zig, combining expressive syntax with the power and performance of low-level systems programming.  A language **by Zig** and **for Zig.**

Zcythe source (`.zcy`) is parsed into an AST, then emitted as Zig source, which is compiled to a native binary by the Zig toolchain.



                                                ±∫∑Iiliii;i
                                       !IiI!×±++lII;i;i;;;::;:;:::::;   ×<
                                  :;::;;ii<Ii;IIIiiI;i;;I:i::,:;lI,,.  l;:+
                               :::::Ill!->÷∑∑≠≥∑≤∑≤==++!!lIii;;i:,,,:,,::,
                            :::I!<--                        ±<llI:i;:.!,,
                          =:l<≤                                 >>   :i,
                         i<                                         ;:.
                       !                                           ,i.
                                                                  -:.
                                                                 l,,
                                                                ;i,
                                                                i.
                                                 ∂≠             i.
                                               +=÷<Ii          i,.
                                              =;>×!:,-         I, .:
                                              Il,;,.,:        ×li :    ,
                                             l; !!;;,.;      il-   :
                                            <:,  >l: ;.i    >iI
                                         ∂±l.i   +I   :,i=- !
                                       .;l><:;, ..  ,,,,;;.÷>
                                     .+li;li::..:.,;..,::l.:>±
                                      l.,l;,,:,,:,.,,,:,:;..×I
                                      ;:;:,;,.,.,:,,.,,i,..,Ii+
                                     >:;;,:.;::.:..,..+,,, ;li,×
                                    ll,;l;;.,...:...i;... .:;:,i
                                     ,,lll;....,...ii.. . ,;i.,,
                                    i,,.Il>!>.,.,:I,...,...: .,l
                                    i,.,:;:; i:÷I<.,,,.,. ., ..!
                                     ;,,.,,; ,. i:,,.: ...., .,!
                                     i,..,:; ,<.,...: ,. .., ,,
                                     +..,,, .<....... ,.  ., ,:i
                                     l:,,,,;,,.. ,......  ., ,;
                                     ll..,l; , . ......    , ,!
                                     =:,,!,  :. ........   ..:!
                                    II ,<,: . .,....,...    ,:l
                                    l..l:,: . .;..,.....    :.i<
                                   !. i,,,, ,   ..,......   , .:<
                                  -. I. .,, ,  ...,,.....   ,. :;+
                                 !..i.   .: ,  ...,,.... .. .. ..i<
                               +:,.:,    ,:.   ...,,....    .   ..I-
                              !,,.:, ..  ,:. . .,.,,......  .  .,.l-
                            II,,.;, .,.   ,  .  ,,.,..,,. ...., ..:,,I
                          l:., ,l,  ,,.  ., ..  .:....,,......,..i,..,i
                         I,  .,I,   ,.: ,. .,. ..,,....,, .....:,    .,,
                        :     ;.   >,;  ,. ,,.....,,....,. ...:.;.   .  ,:
                       .     ,,   l.i.  . ,, ., .,.,,...,......:.;!      .
                            ::   >!    , ., ..,,..,.,,..., ...,,:.;i
                           :,  .<,   , ,:, .. .,,..,,.,...,  ..,:..:i;,
                          l:.iII. .,  .,.   .  .,:..,,, ...   ..,;,,.,:i
                      iIii:,:.,.,,. .:,....,,  ..,::,..,,,... .....:I,::,,:::                 ±.
                               . ,::,,......,, ....,:,  ,:..,,.  ,,,....                      ±




## 🚀 Quick start

```
mkdir MyProject && cd MyProject
zcy init          # scaffold project
zcy run           # build + run
zcy build         # build only → zcy-bin/main
```

## 📸 Language snapshot

```
# Classes
cls Counter {
    count: i32,

    @init {}
    @deinit {}

    pub fn inc() {
        self.count += 1
    }

    pub fn get() -> i32 {
        ret self.count
    }
}

# Extends + implements
cls Person : pub Counter : Greet {
    pub name: str,

    @init {}

    pub fn greet() {
        @pl(self.name)
    }

    ovrd fun greetLoud() {
        @pl(self.name)
    }
}

# Implements only
cls Window :: Keyboard {
    width: i32,
    height: i32,
}

# Data structs
dat Point {
    x: f64,
    y: f64,
}

# Entry point
@main {
    # Variable declarations
    x := 42                    # mutable, type-inferred
    PI :: 3.14159              # immutable, type-inferred
    count : i32 = 0            # explicitly mutable
    MAX : i32 : 100            # explicitly immutable

    # Pointer types
    pCount : *i32 = &count
    pCount.* += 1

    # Fixed-size arrays
    buf : [64]i32 = @emparr()  # zero-initialised 64-element array
    buf[0] = 42

    # Control flow
    if count > 0 {
        @pl("positive")
    }

    for e => items {
        @cout << e << @endl
    }

    for _ => 0..10 {           # range iteration
        count += 1
    }

    while count < MAX {
        count += 1
    }

    defer @pl("done")          # runs when scope exits

    # Switch on strings (parens optional)
    switch input {
        "yes" => { @pl("Affirmative") },
        "no"  => { @pl("Negative") },
        _     => { @pl("Unknown") }
    }

    # Logical operators (and / or as first-class keywords)
    if count > 0 and count < MAX {
        @pl("in range")
    }

    # Error handling — @i32(@input) adds implicit try under the hood
    val := @i32( @input("Enter number: ") )   # propagates parse error

    # Explicit typed input with catch
    n := @input::i32("Enter: ") catch |e| {
        NumFormatErr => 0,
        _ => { @pl("parse failed") ret 0 }
    }

    # Literal braces in @pf format strings via \{ / \}
    @pf("Set notation: \{ x | x > 0 \}\n")

    # Collections
    list := @list(Point)
    list.add(Point{.x=1.0, .y=2.0})

    # String operations
    pass := ""
    @str::cat(pass, "hello")

    # Math
    r := @math::sqrt(2.0)
    @pf("sqrt(2) = {r}\n")

    # Random
    n := @rng(i32, 1, 100)
    @pf("rolled {n}\n")
}
```

## 🏗️ Class syntax

> **Beta:** `cls` is implemented and functional, but the system is still being refined. Expect improvements to inheritance, interface enforcement, and method dispatch in upcoming releases.

```
cls NAME [: [pub] Base [: Iface, Iface]] { members }   # extends + implements
cls NAME :: Iface, Iface { members }                   # implements only
cls NAME { members }                                   # plain class
```

| Member | Description |
|---|---|
| `pub name: Type,` | Public field |
| `name: Type,` | Private field (default) |
| `@init { }` | Constructor — emitted as `init(self: *@This())` |
| `@deinit { }` | Destructor — emitted as `deinit(self: *@This())` |
| `pub fn name(params) -> T { }` | Public method — `self` is injected automatically |
| `fn name(params) -> T { }` | Private method |
| `ovrd fun name(params) { }` | Override method from extended class |

Classes compile to Zig structs. Extends becomes an embedded `_base` field; implements lists become a `// implements:` comment.

## 🔧 Builtin reference

| Zcythe | Purpose |
|---|---|
| `@main { }` | Program entry point |
| `@pl(expr)` | Print line |
| `@pf("…{ident}…")` | Print with `{…}` interpolation; use `\{` / `\}` for literal braces |
| `@cout << a << b << @endl` | Stream output |
| `@cin >> x` | Read line from stdin |
| `@input("prompt")` | Read line with prompt |
| `@list(T)` | Create a growable `ArrayList(T)` |
| `@rng(T, min, max)` | Random value in `[min, max]` |
| `@emparr()` | Zero-initialise a fixed-size array (`Foo: [N]T = @emparr()`) |
| `@i32(expr)` / `@f64(expr)` / … | Cast to numeric type — auto-dispatches `floatFromInt` / `intFromFloat` / `intCast` as needed |
| `@i32(@input("p"))` / `@f32(@input("p"))` | Parse typed input — implicit `try`, error propagates |
| `@input::i32("p")` / `@input::f32("p")` | Typed input returning error union for explicit `catch` |
| `@sys::exit(code)` | Exit with status code |
| `@import(alias = module)` | Import a `.zcy` module |
| `@getArgs()` | Get command-line arguments |
| `@typeOf(expr)` | Get Zcythe type name as string |
| `@str::cat(a, b)` | Concatenate string `b` onto `a` |
| `@math::sqrt(x)` / `@math::pi` / … | Math functions and constants |
| `@math::sin` / `cos` / `tan` / `log` / … | Trigonometry and logarithms |
| `@math::min(a,b)` / `max` / `abs` / `floor` / `ceil` | Numeric utilities |
| `@fs::file_reader::open(p)` | Open file for reading |
| `@fs::file_writer::open(p)` | Open file for writing |
| `@fs::byte_reader::open(p)` | Open binary file for reading |
| `@fs::byte_writer::open(p)` | Open binary file for writing |
| `@kry::hash(pw)` | PBKDF2-HMAC-SHA512 password hash → `"hex_salt$hex_key"` |
| `@kry::hash_auth(pw, stored)` | Verify password against stored hash → `bool` |
| `@kry::enc_file(path, pw)` | AES-256-GCM encrypt file in-place (no external dep) |
| `@kry::dec_file(path, pw)` | AES-256-GCM decrypt file in-place |
| `@xi::window(w, h, title)` | Create a raylib-backed window; returns a window handle |
| `@xi::color(r, g, b, a)` | Create a custom RGBA color |
| `defer expr` | Run `expr` when current scope exits |

## 🖼️ @xi:: graphics framework

`@xi::` is the built-in graphics framework backed by SDL2. No `zcy add` needed — the compiler detects `@xi::` usage and links `libSDL2`, `libSDL2_ttf`, and `libSDL2_image` automatically.

**System requirement:** SDL2, SDL2_ttf, SDL2_image

```
@main {
    win := @xi::window(800, 450, "My Window")
    win.fps(60)
    win.center()

    fnt := @xi::font("monospace", "NORMAL", win.color.white, win.color.clear, 24)
    defer fnt.free()

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
            win.text(fnt, "Hello!", 200, 180)
        }
        win.clearbg(win.color.darkblue)
    }
}
```

| Expression | Description |
|---|---|
| `win.loop` | Loop condition — true while window is open |
| `win.fps(n)` | Set target FPS |
| `win.center()` | Center window on the primary monitor |
| `win.frame { close/min/max => {} }` | Window state events |
| `win.keys { key_press/key_type => {} }` | Keyboard events |
| `win.draw { … }` | Drawing block |
| `win.clearbg(color)` | Clear background (call outside `win.draw`) |
| `win.text(fnt, str, x, y)` | Draw text using a font handle |
| `win.rect(x, y, w, h, color)` | Draw a filled rectangle |
| `win.circle(x, y, r, color)` | Draw a filled circle |
| `win.color.NAME` | Named color (32 built-in: `black`, `white`, `red`, `blue`, … `coral`) |
| `win.keyval.KEY` | Key constant (`A`–`Z`, `0`–`9`, `ESC`, `ENTER`, `SPACE`, `UP`, `DOWN`, … `F12`) |
| `win.key.code` | Current key-press keycode |
| `win.key.char` | Current key-press char (u8) |
| `win.default` | Default window event handler (no-op / close on close) |
| `@xi::font(name, style, fg, bg, size)` | Load system font by name; returns font handle |
| `@xi::img(path)` | Load PNG/JPEG image; returns image handle |
| `@xi::gif(path)` | Load animated GIF; returns GIF handle |

## ⚠️ Zcythe error names

Zcythe provides friendly error names that map to Zig's internal errors:

| Zcythe | Zig |
|---|---|
| `NumFormatErr` | `InvalidCharacter` |
| `NumOverflow` | `Overflow` |
| `ParseErr` | `InvalidCharacter` |
| `OutOfMem` | `OutOfMemory` |
| `EndOfStream` | `EndOfStream` |
| `AccessDenied` | `AccessDenied` |
| `FileNotFound` | `FileNotFound` |
| `BrokenPipe` | `BrokenPipe` |

## 💻 CLI

| Command | Description |
|---|---|
| `zcy init` | Scaffold a new project |
| `zcy build [-name=NAME]` | Transpile and compile (full pipeline) |
| `zcy build-src` | Transpile `.zcy → src/zcyout` only |
| `zcy build-out [-name=NAME]` | Compile `src/zcyout → zcy-bin` only |
| `zcy run [-name=NAME]` | Build and execute |
| `zcy sac <files...> [-name=N]` | Compile `.zcy` files directly to a standalone binary (no project needed) |
| `zcy add owner/repo` | Add a GitHub package (e.g. `zcy add raylib`) |

See `docs/` for full build notes and language design docs.
