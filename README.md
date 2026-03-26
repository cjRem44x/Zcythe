# Zcythe

> **A systems programming language that transpiles to Zig.**

> **Requires Zig 0.15.2**

Zcythe (`.zcy`) gives you expressive, readable syntax on top of Zig's performance and safety. Source is parsed into an AST, emitted as Zig, and compiled to a native binary — no runtime, no GC, no overhead.

```
 ____           _   _
|_  / ___  _  _| |_| |_  ___
 / / / __|| || |  _|  ' \/ -_)
/___/\___| \_, |\__|_||_|\___|
           |__/

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
```
---

## Mission

Zcythe exists to make low-level systems programming feel natural. The goal is a language where writing a file parser, a game loop, or a concurrent server doesn't require fighting the toolchain — just clean, direct code that compiles fast and runs fast.

- **Familiar syntax** — feels like a modern scripting language, compiles like C
- **Zero-cost abstractions** — everything maps directly to Zig primitives
- **Single-binary compiler** — `zcy` handles transpile, compile, and run in one command
- **No hidden magic** — inspect the generated Zig in `src/zcyout/` at any time

---

## Quick Start

```sh
zcy init          # scaffold a new project
zcy run           # build and run
zcy build         # build only → zcy-bin/main
zcy version       # print version info
```

---

## Language Snapshot

```
# Variables
x    := 42            # mutable, inferred
PI   :: 3.14159       # immutable, inferred
n  : i32  = 0         # mutable, explicit type
MAX: i32  : 100       # immutable, explicit type

# Functions
fn add(a: i32, b: i32) -> i32 {
    ret a + b
}

fn double(x: any) { ret x * 2 }   # generic parameter

# Data structs
dat Point { x: f64, y: f64 }

p := Point{ .x = 1.0, .y = 2.0 }
@pf("point: ({}, {})\n", p.x, p.y)

# Structs (with methods)
struct Vec2 {
    x: f32,
    y: f32,

    pub fn len() -> f32 {
        ret @math::sqrt(self.x * self.x + self.y * self.y)
    }
}

# Control flow
if x > 0 {
    @pl("positive")
} elif x < 0 {
    @pl("negative")
} else {
    @pl("zero")
}

for e => items { @cout << e << @endl }
for _ => 0..10 { count += 1 }
while count < MAX { count += 1 }
defer @pl("done")

# Switch
switch code {
    1 => { @pl("one") },
    2 => { @pl("two") },
    _ => { @pl("other") },
}

# Type switch
fn describe(x: any) {
    T :: @type(x)
    switch T {
        i32    => { @pl("int") },
        str    => { @pl("string") },
        Point  => { @pl("Point") },
        _      => { @pl(T) },
    }
}

# Tagged unions
unn Shape => enum {
    circle:    f64,
    rectangle: f64,
}
s : Shape = Shape.circle{5.0}
switch s {
    .circle    => |r| { @pf("r={}\n", r) },
    .rectangle => |w| { @pf("w={}\n", w) },
}

# Error handling
val := @i32( @input("Enter: ") )           # implicit try
n   := @input::i32("Enter: ") catch 0      # explicit catch

# Collections
list := @list(Point)
list.add(Point{ .x = 1.0, .y = 2.0 })

# Strings
s := "hello"
@str::cat(s, " world")
@pl( @str::up(s) )     # HELLO WORLD

# Math / random
r := @math::sqrt(2.0)
n := @rng(i32, 1, 100)
```

---

## Types

| Type | Description |
|------|-------------|
| `i8` `i16` `i32` `i64` `i128` | Signed integers |
| `u8` `u16` `u32` `u64` `u128` | Unsigned integers |
| `f32` `f64` | Floats |
| `bool` | `true` / `false` |
| `str` | UTF-8 string slice (`[]const u8`) |
| `chr` | ASCII character — same bits as `u8`, prints as a character |
| `usize` `isize` | Platform-width integers |
| `any` | Comptime-generic parameter (Zig `anytype`) |
| `*T` | Pointer to T |
| `*imu T` | Pointer to immutable T |
| `*[]T` | Heap slice of T |
| `[N]T` | Fixed-size array |

### Data types

```
dat Person { name: str, age: i32 }

p := Person{ .name = "Alice", .age = 30 }
@pf("{} is {}\n", p.name, p.age)
```

### Structs (with methods)

```
struct Counter {
    n: i32,

    pub fn inc() { self.n += 1 }
    pub fn get() -> i32 { ret self.n }
}

c := Counter{ .n = 0 }
c.inc()
@pl(c.get())
```

### Enums

```
enum Dir { NORTH, SOUTH, EAST, WEST }

d : Dir = .NORTH
switch d {
    .NORTH => { @pl("north") },
    _      => { @pl("other") },
}
```

---

## Functions

```
fn greet(name: str) {
    @pf("Hello, {}!\n", name)
}

fn add(a: i32, b: i32) -> i32 { ret a + b }

fn identity(x: any) { ret x }      # generic

pub fn exported() { }               # visible to other modules

# Anonymous struct return
dat Point { x: i32, y: i32 }
fn origin() -> Point { ret .{ .x = 0, .y = 0 } }

# Lambda
double := (x: i32 => i32) { ret x * 2 }
```

---

## Built-in Functions

| Builtin | Description |
|---------|-------------|
| `@pl(expr)` | Print with newline |
| `@pf("…{x}…")` | Print with `{ident}` interpolation |
| `@cout << a << b << @endl` | Stream output |
| `@cin >> x` | Read from stdin |
| `@input("prompt")` | Read line with prompt |
| `@type(expr)` | Zcythe type name as a string (`"i32"`, `"str"`, `"Point"`, …) |
| `@str(expr)` | Convert value to string |
| `@list(T)` | Growable array (`ArrayList(T)`) |
| `@rng(T, min, max)` | Random value in `[min, max]` |
| `@emparr()` | Zero-initialise a fixed-size array |
| `@i32(x)` / `@f64(x)` / … | Numeric cast / parse |
| `@sys::exit(code)` | Exit with status code |
| `@import(alias = module)` | Import a `.zcy` module |
| `@args()` | Command-line arguments |
| `defer expr` | Run when scope exits |

### String methods (`@str::`)

| Method | Description |
|--------|-------------|
| `@str::cat(s, t)` | Append `t` onto `s` |
| `@str::in(s, sub)` | Contains substring |
| `@str::start(s, p)` | Starts with prefix |
| `@str::end(s, p)` | Ends with suffix |
| `@str::low(s)` | Lowercase |
| `@str::up(s)` | Uppercase |
| `@str::trim(s)` | Trim whitespace |
| `@str::spl(s, delim)` | Split into slice |
| `@str::repall(s, old, new)` | Replace all occurrences |

### Math (`@math::`)

`sqrt`, `sin`, `cos`, `tan`, `log`, `pow`, `abs`, `floor`, `ceil`, `min`, `max`, `pi`, `e`

### File I/O (`@fs::`)

```
r := @fs::file_reader::open("data.txt")
line := r.read_line()
r.close()

w := @fs::file_writer::open("out.txt")
w.write_line("hello")
w.close()
```

Binary I/O: `@fs::byte_reader` / `@fs::byte_writer` with typed read/write methods (`ri32`, `ru64`, `rf32`, …).

---

## Project Structure

```
my_project/
  src/
    main/
      zcy/
        main.zcy      ← entry point
    zcyout/           ← generated Zig (auto, do not edit)
  zcy-bin/            ← compiled binary output
  build.zig           ← generated by zcy init
```

`zcy init` scaffolds this layout. The generated Zig in `src/zcyout/` is human-readable and can be inspected at any time.

---

## CLI — `zcy`

| Command | Description |
|---------|-------------|
| `zcy init` | Scaffold a new project |
| `zcy build [-o=N]` | Transpile + compile → `zcy-bin/` |
| `zcy build-src` | Transpile only → `src/zcyout/` |
| `zcy build-out [-o=N]` | Compile only → `zcy-bin/` |
| `zcy run [-o=N]` | Build and execute |
| `zcy sac <files…> [-o=N]` | Compile `.zcy` files without a project |
| `zcy test [file]` | Run `@test` blocks |
| `zcy add <pkg>` | Add a package (`zcy add raylib`) |
| `zcy lspkg` | List available packages |
| `zcy version` | Print version info |

**`-o=NAME`** sets the output binary name (default: `main`). Mirrors C's `-o` flag.

---

## Graphics — `@xi::`

`@xi::` is the built-in 2D graphics framework backed by SDL2. The compiler detects `@xi::` usage and links SDL2 automatically — no `zcy add` required.

**Requires:** `SDL2`, `SDL2_ttf`, `SDL2_image`

```
@main {
    win := @xi::window(800, 450, "Demo")
    win.fps(60)

    fnt := @xi::font("monospace", "NORMAL", win.color.white, win.color.clear, 24)
    defer fnt.free()

    while win.loop {
        win.frame { close => { win.default }, _ => {} }
        win.draw {
            win.text(fnt, "Hello!", 200, 180)
        }
        win.clearbg(win.color.darkblue)
    }
}
```

---

## Error Names

| Zcythe | Zig |
|--------|-----|
| `NumFormatErr` | `InvalidCharacter` |
| `NumOverflow` | `Overflow` |
| `ParseErr` | `InvalidCharacter` |
| `OutOfMem` | `OutOfMemory` |
| `EndOfStream` | `EndOfStream` |
| `AccessDenied` | `AccessDenied` |
| `FileNotFound` | `FileNotFound` |
| `BrokenPipe` | `BrokenPipe` |

---

## Documentation

Full language reference: [`docs/Index.md`](docs/Index.md)

---

## cls — Object-Oriented Classes *(BETA)*

> `cls` is implemented and functional but still being refined. Inheritance, interface enforcement, and method dispatch are subject to change.

```
cls Counter {
    count: i32,

    @init {}
    @deinit {}

    pub fn inc() { self.count += 1 }
    pub fn get() -> i32 { ret self.count }
}

cls Person : pub Counter {
    pub name: str,
    @init {}
    pub fn greet() { @pl(self.name) }
}
```

| Syntax | Description |
|--------|-------------|
| `cls Name { }` | Plain class |
| `cls Name : pub Base { }` | Extends Base |
| `cls Name :: Iface { }` | Implements interface |
| `@init { }` | Constructor |
| `@deinit { }` | Destructor |
| `pub fn name() { }` | Public method (`self` injected) |
| `ovrd fun name() { }` | Override from base class |

Classes compile to Zig structs with an embedded `_base` field for inheritance.
