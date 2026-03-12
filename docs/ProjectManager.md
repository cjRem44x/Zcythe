# Project Manager for Zcythe

## Starting a new Project
```
mkdir Porject
cd Porject

zcy init
```

`zcy` is the CLI call to the Zcythe env.

## Project Structure
This is what `zcy init` creates, plus what grows as you add packages.
```
/proj
    zcypm.toml          # package manifest (name, version, dependencies)
    /src
        /zcyout         # transpiled .zig source goes here
        /main
            /zcy
                main.zcy
    /zcy-bin            # compiled binaries go here
    /zcy-pkgs           # cloned dependencies (created by `zcy add`)
        /<owner>/
            /<repo>/
```

## Building a Project
```
zcy build [-name=NAME]
```
Transpiles `src/main/zcy/main.zcy` → `src/zcyout/main.zig`, then compiles it with `zig`.
The resulting binary is written to `zcy-bin/<NAME>` (default: `zcy-bin/main`).

Examples:
```
zcy build              # produces zcy-bin/main
zcy build -name=greet  # produces zcy-bin/greet
```

## Running a Project
```
zcy run [-name=NAME]
```
Builds the project (same as `zcy build`) and immediately executes `zcy-bin/<NAME>`.
The program's stdin/stdout/stderr are connected to your terminal normally.

Examples:
```
zcy run              # builds and runs zcy-bin/main
zcy run -name=greet  # builds and runs zcy-bin/greet
```

## Adding a Package
```
zcy add <owner/repo>
```
Adds a GitHub repository as a dependency. It:
1. Appends `owner/repo = "*"` to `zcypm.toml`
2. Clones `https://github.com/<owner>/<repo>` into `zcy-pkgs/<owner>/<repo>/`

Examples:
```
zcy add cjRem44x/zcymath
```

Running `zcy add` again with the same package prints "already added" and exits cleanly.

> **Note:** `zcypm.toml` is created by `zcy init`. If it is missing, run `zcy init` first.

### Dependency Import Calls
- Local Zcythe libs / native pkgs `foo = @zcy.x.y.z`
- Zig imports `zigFoo = @zig.x.y.z`
- C inclues `cFoo = @c.include("stdio.h")` OR `cFoo = @c.include("stdio.h", "stdlib.h", ...)` for multiple includes
- Python libs `pyFoo = @py.x` import module, or `pyFoo = @py.x.y` from module x import y

### zcypm.toml format
```toml
[package]
name = "my-project"
version = "0.1.0"

[dependencies]
cjRem44x/zcymath = "*"
```

`"*"` means latest main branch. Pinned versions are planned for a future release.
