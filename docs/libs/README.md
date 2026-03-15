# Zcythe Library Reference

Function-level reference for all `@zcy.*` libraries. Each page lists every call using the alias syntax (`<alias>.func()`), its return type, and a description.

| Library | Import | Type | Page |
|---------|--------|------|------|
| OpenMP threading | `@import(omp = @zcy.openmp)` | NativeSysPkg | [omp.md](omp.md) |
| Cryptography | `@import(sodium = @zcy.sodium)` | NativeSysPkg | [sodium.md](sodium.md) |
| SQLite3 database | `@import(db = @zcy.sqlite)` | NativeSysPkg | [sqlite.md](sqlite.md) |
| Qt5/Qt6 widgets | `@import(qt = @zcy.qt)` | NativeSysPkg | [qt.md](qt.md) |
| raylib graphics | `@import(rl = @zcy.raylib)` | ZcytheAddLinkPkg | [raylib.md](raylib.md) |

See `zcy lspkg` for install commands for each NativeSysPkg.
