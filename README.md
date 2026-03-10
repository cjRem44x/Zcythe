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
    let count: i32 = 0         # explicitly mutable
    val let MAX: i32 = 100     # explicitly immutable

    # Pointer types
    val let pCount: *i32 = &count
    pCount.* += 1

    # Fixed-size arrays
    buf: [64]i32 = @emparr()   # zero-initialised 64-element array
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
| `@fs::FileReader::open(p)` | Open file for reading |
| `@fs::FileWriter::open(p)` | Open file for writing |
| `@fs::ByteReader::open(p, endian)` | Open binary file for reading |
| `@fs::ByteWriter::open(p, endian)` | Open binary file for writing |
| `defer expr` | Run `expr` when current scope exits |

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
| `zcy build [-name=NAME]` | Transpile and compile |
| `zcy run [-name=NAME]` | Build and execute |
| `zcy add owner/repo` | Add a GitHub package (e.g. `zcy add raylib`) |

See `docs/` for full build notes and language design docs.
