# Zcythe Language Reference

Zcythe is a compiled, statically-typed language that transpiles to Zig. It offers a clean, expressive syntax while giving you full access to Zig's performance and safety guarantees, plus a rich set of built-in libraries covering I/O, file systems, math, concurrency, cryptography, logging, and graphics.

```
.zcy source  →  Zcythe compiler (zcy)  →  Zig source  →  zig build-exe  →  binary
```

## CLI

| Command | Description |
|---------|-------------|
| `zcy init` | Create a new project in the current directory |
| `zcy build` | Transpile and compile `src/main/zcy/main.zcy` |
| `zcy run` | Build then run the compiled binary |
| `zcy test [file.zcy]` | Transpile and run `@test` blocks |
| `zcy sac <files…> [-name=N]` | Stand-alone compile one or more `.zcy` files |
| `zcy add raylib` | Add the raylib graphics library |
| `zcy add <owner/repo>` | Add a GitHub package dependency |

## Table of Contents

1. [Variables & Types](01_variables.md)
2. [Control Flow](02_control_flow.md)
3. [Functions](03_functions.md)
4. [User-Defined Types](04_types.md)
5. [Error Handling](05_error_handling.md)
6. [Built-in Functions](06_builtins.md)
7. [I/O & File System — `@fs::`](07_fs.md)
8. [Math — `@math::`](08_math.md)
9. [Concurrency — `@omp::`](09_concurrency.md)
10. [Cryptography — `@sodium::`](10_crypto.md)
11. [Logging — `@fflog::`](11_logging.md)
12. [Raylib — `@rl::`](12_raylib.md)
13. [Testing — `@test` & `@assert`](13_testing.md)
14. [Imports & Modules](14_imports.md)
