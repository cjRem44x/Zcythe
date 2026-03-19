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

Zcythe's built-in libraries are accessed via `@import(alias = @zcy.libname)`. There are two categories:

---

### NativeSysPkg — Native System Packages

These libraries must be installed on your system via your OS package manager. The Zcythe compiler detects their usage and links them automatically — **no `zcy add` needed**.

| Import | Library | Install |
|--------|---------|---------|
| `@zcy.openmp` | OpenMP threading | `dnf install libgomp` / `apt install libgomp1` |
| `@zcy.sodium` | Cryptography (libsodium) | `dnf install libsodium-devel` / `apt install libsodium-dev` |
| `@zcy.sqlite` | SQLite3 database | `dnf install sqlite-devel` / `apt install libsqlite3-dev` |
| `@zcy.qt` | Qt5/Qt6 widgets | `dnf install qt6-qtbase-devel` / `apt install qt6-base-dev` |

```
@import(omp = @zcy.openmp)
@import(db  = @zcy.sqlite)
@import(qt  = @zcy.qt)
```

The build system auto-links the required system libraries (`-lsqlite3`, `-lgomp`, etc.) when it detects a NativeSysPkg import in your source.

---

### ZcytheAddLinkPkg — Project-Local Packages

These packages are downloaded into the project directory via `zcy add` and stored under `zcy-pkgs/`. They do **not** require a system-level install.

| Import | Library | Setup |
|--------|---------|-------|
| `@zcy.raylib` | 2D/3D graphics (raylib) | `zcy add raylib` |

```
@import(rl = @zcy.raylib)
```

Any GitHub package added with `zcy add owner/repo` also becomes a ZcytheAddLinkPkg and is recorded in `zcypm.toml`.

**Key difference:**

| | NativeSysPkg | ZcytheAddLinkPkg |
|-|-------------|-----------------|
| Installed by | OS package manager | `zcy add` |
| Stored in | system (`/usr/lib`, etc.) | `zcy-pkgs/` inside your project |
| `zcy add` needed? | No — just install the OS pkg | Yes |
| `zcypm.toml` entry? | No | Yes |

---

## Alias Syntax

All `@zcy.*` libraries are used through their import alias. There is no secondary `@ns::` call syntax for them.

```
@import(omp    = @zcy.openmp)
@import(sodium = @zcy.sodium)
@import(db     = @zcy.sqlite)
@import(qt     = @zcy.qt)
@import(rl     = @zcy.raylib)
```

Then call everything as `alias.func(...)`:

```
omp.set_threads(4)
hash := sodium.hash(pw)
conn := db.open(":memory:")
app  := qt.app()
rl.initWindow(800, 600, "Game")
```

Some built-in namespaces (`@math::`, `@fs::`, `@fflog::`) are always available without any import and have no alias form — they are accessed directly:

```
r := @math::sqrt(x)
f := @fs::file_reader::open("data.txt")
log := @fflog::init("app.log.json")
```

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
├── zcy-pkgs/               # ZcytheAddLinkPkgs (git-cloned, git-ignored)
└── zcy-bin/                # compiled binaries (git-ignored)
```

Additional `.zcy` files can be placed anywhere under `src/` and are compiled alongside `main.zcy` during `zcy build`.

---

## `zcypm.toml` — Project Manifest

The project manifest stores the project name and ZcytheAddLinkPkg dependencies:

```toml
name = "my-project"
version = "0.1.0"

[dependencies]
raylib = "*"
```

NativeSysPkgs are never listed here — they are resolved from the system at build time.

---

## Adding ZcytheAddLinkPkgs

```bash
# Add the bundled raylib graphics library
zcy add raylib

# Add any GitHub package
zcy add username/repo-name
```

`zcy add` clones the package into `zcy-pkgs/` and appends an entry to `zcypm.toml`.

To see all available packages — both NativeSysPkgs and ZcytheAddLinkPkgs — with their types and OS-specific install commands, run:

```bash
zcy lspkg
```
