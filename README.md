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

    # Control flow
    if (count > 0) {
        @pl("positive")
    }

    for e => items {
        @cout << e << @endl
    }

    while count < MAX {
        count += 1
    }

    # Switch on strings
    switch (input) {
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
}
```

## Builtin reference

| Zcythe | Purpose |
|---|---|
| `@main { }` | Program entry point |
| `@pl(expr)` | Print line |
| `@pf(fmt, args…)` | Formatted print |
| `@cout << a << b << @endl` | Stream output |
| `@cin >> x` | Read line from stdin |
| `@input("prompt")` | Read line with prompt |
| `@list(T)` | Create a growable `ArrayList(T)` |
| `@i32(str)` / `@f64(str)` etc. | Parse string to numeric type |
| `@sysexit(code)` | Exit with status code |
| `@import(alias = module)` | Import a `.zcy` module |
| `@getArgs()` | Get command-line arguments |
| `@typeOf(expr)` | Get Zcythe type name as string |

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
| `zcy add owner/repo` | Add a GitHub package |

See `docs/` for full build notes and language design docs.
