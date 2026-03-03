# Zcythe

A transpiled programming language that compiles to Zig.

Zcythe source (`.zcy`) is parsed into an AST, then emitted as Zig source, which is compiled to a native binary by the Zig toolchain.

## Quick start

```
mkdir MyProject && cd MyProject
zcy init          # scaffold project
zcy run           # build + run
zcy build         # build only → zcy-bin/main
```

## Language snapshot

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
    if (count > 0) {
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

    # Error handling
    val := @i32( @input("Enter number: ") ) catch |e| {
        NumFormatErr => 0,
        _ => { @pl("parse failed") ret 0 }
    }

    result := try @i32( @input("Strict: ") )

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

## Builtin reference

| Zcythe | Purpose |
|---|---|
| `@main { }` | Program entry point |
| `@pl(expr)` | Print line |
| `@pf("…{ident}…")` | Print with `{…}` interpolation (complex exprs supported) |
| `@cout << a << b << @endl` | Stream output |
| `@cin >> x` | Read line from stdin |
| `@input("prompt")` | Read line with prompt |
| `@list(T)` | Create a growable `ArrayList(T)` |
| `@rng(T, min, max)` | Random value in `[min, max]` |
| `@emparr()` | Zero-initialise a fixed-size array (`Foo: [N]T = @emparr()`) |
| `@i32(s)` / `@f64(s)` / … | Parse string to numeric type |
| `@f32FromInt(n)` / `@f64FromInt(n)` | Convert integer to float |
| `@intFromFloat(n)` / `@intCast(n)` | Convert float/int to int |
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

## Zcythe error names

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

## CLI

| Command | Description |
|---|---|
| `zcy init` | Scaffold a new project |
| `zcy build [-name=NAME]` | Transpile and compile |
| `zcy run [-name=NAME]` | Build and execute |
| `zcy add owner/repo` | Add a GitHub package (e.g. `zcy add raylib`) |

See `docs/` for full build notes and language design docs.
