# Imports & Modules

---

## `@import` — Import a Module

Use `@import(…)` at the top of a file to bring in external modules. Each argument is `alias = module_path`.

```
@import(
    math_utils = ./math_utils,
    io_helpers = ./helpers/io,
)
```

---

## `@zcy.*` — Standard Libraries

Zcythe's built-in libraries are imported with `@zcy.libname`. The compiler detects their usage and links the necessary C libraries automatically.

| Import | What it provides |
|--------|-----------------|
| `@zcy.openmp` | Parallel threading via OpenMP runtime |
| `@zcy.sodium` | Cryptography (libsodium) |
| `@zcy.raylib` | 2D/3D graphics (raylib) |

```
@import(
    omp    = @zcy.openmp,
    sodium = @zcy.sodium,
    rl     = @zcy.raylib,
)
```

After importing with an alias, the library's functions are available as `alias.method(…)`:

```
omp.set_threads(4)
omp.parallel { … }

hash := sodium.hash("password")
sodium.enc_file("vault.dat", "key")

rl.initWindow(800, 600, "Game")
```

---

## Alias Syntax vs `@ns::` Syntax

Every `@zcy.*` library also exposes a `@ns::` form that works **without** an import. The alias form is preferred for readability.

| Alias form | `@ns::` form | Requires import? |
|-----------|-------------|-----------------|
| `omp.set_threads(n)` | `@omp::set_threads(n)` | alias yes, `@omp::` no |
| `omp.parallel { }` | `@omp::parallel { }` | alias yes, `@omp::` no |
| `sodium.hash(pw)` | `@sodium::hash(pw)` | alias yes, `@sodium::` no |
| `sodium.enc_file(p, k)` | `@sodium::enc_file(p, k)` | alias yes, `@sodium::` no |
| — | `@math::sqrt(x)` | never (always available) |
| — | `@fs::FileReader::open(p)` | never (always available) |
| — | `@fflog::init(p)` | never (always available) |

---

## Multiple Imports

All imports must appear at the top of the file, before any declarations:

```
@import(
    omp    = @zcy.openmp,
    sodium = @zcy.sodium,
)

@main {
    omp.set_threads(4)

    pw   := @input("Password: ")
    hash := sodium.hash(pw)
    @pf("stored: {hash}\n")

    omp.parallel {
        id := omp.thread_id()
        @pf("thread {id}\n")
    }
}
```

---

## Module File Layout

A Zcythe project created with `zcy init` has this structure:

```
my-project/
├── zcypm.toml              # project manifest
├── src/
│   └── main/
│       └── zcy/
│           └── main.zcy    # entry point (contains @main)
└── zcy-bin/                # compiled binaries (git-ignored)
```

Additional `.zcy` files can be placed anywhere under `src/` and are compiled alongside `main.zcy` during `zcy build`.

---

## `zcypm.toml` — Project Manifest

The project manifest stores the project name and dependencies:

```toml
name = "my-project"
version = "0.1.0"
```

Dependencies added with `zcy add <owner/repo>` are appended here automatically.

---

## Adding Dependencies

```bash
# Add raylib
zcy add raylib

# Add a GitHub package
zcy add username/repo-name
```

`zcy add` downloads the package and updates both `zcypm.toml` and the build configuration.
