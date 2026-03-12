# Python Library Integration — Design Plan

> **Status:** Planning / Not yet implemented

---

## Overview

Zcythe will support calling Python libraries from `.zcy` source via the CPython
embedding API.  Since Zig has native C interop (`@cImport`), we can link against
`libpython3.x`, call Python's C API from generated Zig code, and present a clean
import surface to the `.zcy` programmer.

---

## Import Syntax

Three forms, all under the `@py.*` namespace:

| `.zcy` syntax | Python equivalent | Notes |
|---|---|---|
| `@import(np = @py.numpy)` | `import numpy` | whole module bound to alias |
| `@import(path = @py.os.path)` | `from os import path` | attribute of a module |
| `@import(np = @py.numpy.{array, zeros, ones})` | `from numpy import array, zeros, ones` | multi-name destructure |

Inside `@import(...)` these follow the same `alias = rhs` pattern as existing
imports, so the parser needs no new syntax — only codegen needs to handle `@py.*`
on the RHS.

---

## Codegen

### Preamble additions

When any `@py.*` import is present in a program, the generated preamble gets:

```zig
const _py = @cImport({ @cInclude("Python.h"); });
```

And `@main` is wrapped so Python is initialised before user code and finalised
after:

```zig
_py.Py_Initialize();
defer _py.Py_Finalize();
```

### Import forms → generated Zig

#### `@import(np = @py.numpy)`

```zig
const np: *_py.PyObject = _py.PyImport_ImportModule("numpy") orelse
    @panic("Python import failed: numpy");
defer _ = _py.Py_DecRef(np);
```

#### `@import(path = @py.os.path)`

```zig
const _py_os = _py.PyImport_ImportModule("os") orelse
    @panic("Python import failed: os");
defer _ = _py.Py_DecRef(_py_os);
const path: *_py.PyObject = _py.PyObject_GetAttrString(_py_os, "path") orelse
    @panic("Python attr failed: os.path");
defer _ = _py.Py_DecRef(path);
```

#### `@import(np = @py.numpy.{array, zeros})`

Destructure produces one binding per name:

```zig
const _py_numpy = _py.PyImport_ImportModule("numpy") orelse
    @panic("Python import failed: numpy");
defer _ = _py.Py_DecRef(_py_numpy);
const array: *_py.PyObject = _py.PyObject_GetAttrString(_py_numpy, "array") orelse
    @panic("Python attr failed: numpy.array");
defer _ = _py.Py_DecRef(array);
const zeros: *_py.PyObject = _py.PyObject_GetAttrString(_py_numpy, "zeros") orelse
    @panic("Python attr failed: numpy.zeros");
defer _ = _py.Py_DecRef(zeros);
```

### Calling Python objects

When a bound Python name is called in `.zcy` code:

```zcy
result := np.array([1, 2, 3])
```

Codegen emits a `PyObject_CallObject` / `PyObject_Call` invocation, wrapping
arguments through type-conversion helpers (see below).

---

## Type Conversion Helpers

Generated into the preamble when Python is used.  All live in the `_zcy_py_*`
namespace to avoid collisions.

| Zig / Zcythe type | → Python | Python → |
|---|---|---|
| `i32` / `i64` | `PyLong_FromLong` | `PyLong_AsLong` |
| `f32` / `f64` | `PyFloat_FromDouble` | `PyFloat_AsDouble` |
| `[]const u8` | `PyUnicode_FromStringAndSize` | `PyUnicode_AsUTF8` |
| `bool` | `PyBool_FromLong` | `PyObject_IsTrue` |
| slice / list | `PyList_New` + element loop | iterate with `PyList_GetItem` |
| `*PyObject` (passthrough) | identity | identity |

Return values from Python calls come back as `*PyObject`; an explicit Zcythe cast
annotation like `@i32(result)` triggers the appropriate `PyLong_AsLong` wrapper.

---

## Build System Changes

### Detection

`cmdBuild` needs a `programUsesPy` scan (same pattern as `programUsesRl`) that
checks for any `@py.*` import in the program.

### Linking

When Python is detected, the build must:

1. Run `python3-config --includes` and `python3-config --ldflags` (or
   `pkg-config python3-embed`) to get include paths and link flags.
2. Add those to the compile step.

For the `zig build` path a helper `genPythonBuildFiles` (similar to
`genRaylibBuildFiles`) generates a `build.zig` that calls:

```zig
exe.linkSystemLibrary("python3");
exe.addIncludePath(.{ .cwd_relative = "<python-include-dir>" });
```

For the simple `zig build-exe` path, pass `-lc -lpython3.x` and
`-I<include-dir>` flags directly.

### `zcypm.toml`

No special entry is needed for stdlib Python modules.  Third-party pip packages
remain the user's responsibility (installed in the active Python environment) —
they are not cloned by `zcy add`.  May revisit this with a `[python-dependencies]`
section in a later version.

---

## AST / Parser Changes

The destructure form `@py.C.{x, y, z}` requires the parser to recognise a
brace-set on the RHS of an import binding.  Options:

- **Option A** — Treat `{x, y, z}` as an `array_lit` of ident nodes; codegen
  special-cases it in the `@py.*` handler.
- **Option B** — Add a dedicated `import_destructure` AST node.

Option A is simpler and avoids touching the grammar.  Prefer A unless ambiguity
arises.

---

## Codegen Detection Functions Needed

| Function | Purpose |
|---|---|
| `programUsesPy(prog)` | true if any `@py.*` import exists |
| `programHasPyImport(prog)` | true if explicit import (suppress auto-init) |
| `emitPyImportDecl(alias, mod, field, destructure)` | emit the import + attr bindings |
| `emitPyPreamble()` | emit `_py` cImport + init/finalise wrappers |

---

## Open Questions

- **GIL management** — for now assume single-threaded; GIL acquire/release can be
  added later if Zig threads are used alongside Python.
- **Exception propagation** — `PyErr_Occurred()` after each call; map to Zcythe
  `try/catch` or panic.  Needs design.
- **Pip package installation** — should `zcy add` be able to run `pip install`?
  Deferred.
- **Multiple Python versions** — detect via `python3-config`; no version pinning
  yet.
- **Virtual environments** — `Py_SetPythonHome` can point at a venv; expose via
  `zcypm.toml`?
