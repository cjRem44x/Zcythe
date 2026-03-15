# Concurrency — `@omp::`

Zcythe's `@omp::` namespace provides data-parallel constructs inspired by OpenMP. Under the hood these spawn OS threads via Zig's `std.Thread`, so no external OpenMP runtime is required for most usage — though `libgomp` is linked when the namespace is detected.

To use the alias syntax, import the library:

```
@import(omp = @zcy.openmp)
```

After this import, all `@omp::` calls can be written as `omp.*` instead.

---

## Thread Count

### `omp.set_threads(n)` — Set Maximum Threads

```
omp.set_threads(4)
```

### `omp.max_threads()` — Query Max Threads

```
@pf("threads: {omp.max_threads()}\n")
```

### `omp.num_threads()` — Threads in Current Region

Returns the actual number of threads running in the current parallel region.

```
omp.parallel {
    @pf("using {omp.num_threads()} threads\n")
}
```

### `omp.thread_id()` — Current Thread Index

Inside a parallel region, returns the 0-based ID of the calling thread.

```
omp.parallel {
    id := omp.thread_id()
    @pf("hello from thread {id}\n")
}
```

---

## `omp.parallel { }` — Parallel Region

Spawns `max_threads()` threads; each thread independently executes the body.

```
@import(omp = @zcy.openmp)

@main {
    omp.set_threads(4)

    omp.parallel {
        id := omp.thread_id()
        @pf("thread {id} running\n")
    }
}
```

Output (order varies):
```
thread 0 running
thread 2 running
thread 1 running
thread 3 running
```

> **Note:** Statements in the body run concurrently. Shared mutable state requires external synchronization (e.g., atomics or a mutex via Zig interop).

---

## `omp.for` — Parallel Range Loop

Splits an integer range across all available threads. Each thread processes a contiguous chunk.

```
@import(omp = @zcy.openmp)

@main {
    omp.set_threads(4)
    omp.for i => 0..16 {
        @pf("  i={i}\n")
    }
}
```

Output: indices 0–15, each processed by one thread, order within a chunk is sequential.

### Inclusive Range

```
omp.for i => 0..=15 {    # 0, 1, 2, …, 15
    @pf("{i} ")
}
```

### Custom Range Bounds from Variables

```
n := 100
omp.for i => 0..n {
    process(i)
}
```

---

## Timing with `omp.wtime()`

Returns wall-clock seconds as `f64` — useful for benchmarking parallel workloads.

```
t0 := omp.wtime()

omp.for i => 0..1000000 {
    heavy_compute(i)
}

t1 := omp.wtime()
@pf("elapsed: {t1 - t0:.3f}s\n")
```

---

## `omp.in_parallel()` — Detect Parallel Context

Returns `bool` — `true` when called from inside a running parallel region.

```
omp.parallel {
    if omp.in_parallel() {
        @pl("yes, inside parallel region")
    }
}
```

---

## Complete Example: Parallel Sum

```
@import(omp = @zcy.openmp)

@main {
    omp.set_threads(8)

    @pf("max threads: {omp.max_threads()}\n")

    t0 := omp.wtime()

    # Each thread processes its chunk of the range
    omp.for i => 0..32 {
        id := omp.thread_id()
        @pf("thread {id}: i={i}\n")
    }

    t1 := omp.wtime()
    @pf("done in {t1 - t0:.4f}s\n")
}
```

---

## `@omp::` vs `omp.` Syntax

Both are equivalent when `omp = @zcy.openmp` is imported. The `@omp::` form can also be used directly without an import:

| `omp.` alias | `@omp::` form |
|-------------|---------------|
| `omp.set_threads(n)` | `@omp::set_threads(n)` |
| `omp.max_threads()` | `@omp::max_threads()` |
| `omp.thread_id()` | `@omp::thread_id()` |
| `omp.parallel { }` | `@omp::parallel { }` |
| `omp.for i => r { }` | `@omp::for i => r { }` |

The alias form (`omp.`) is preferred for readability.

---

## Quick Reference

| Call | Description |
|------|-------------|
| `omp.set_threads(n)` | Set thread pool size |
| `omp.max_threads()` | Max threads available |
| `omp.num_threads()` | Threads in current region |
| `omp.thread_id()` | 0-based ID of current thread |
| `omp.wtime()` | Wall-clock time (f64 seconds) |
| `omp.in_parallel()` | True if inside a parallel region |
| `omp.parallel { }` | Spawn N threads, all run body |
| `omp.for v => range { }` | Parallel loop over integer range |
