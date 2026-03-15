# `@zcy.openmp` — OpenMP Parallel Threading

**Type:** NativeSysPkg
**Install:** `dnf install libgomp` / `apt install libgomp1` / `brew install libomp`

```
@import(omp = @zcy.openmp)
```

---

## Function Calls

| Call | Returns | Description |
|------|---------|-------------|
| `omp.set_threads(n)` | `void` | Set the number of threads to use for parallel regions |
| `omp.max_threads()` | `i32` | Maximum threads available (from `OMP_NUM_THREADS` or CPU count) |
| `omp.num_threads()` | `i32` | Number of threads currently active in the parallel region |
| `omp.thread_id()` | `i32` | Index of the calling thread (0-based) — valid inside `omp.parallel` or `omp.for` |
| `omp.wtime()` | `f64` | Wall-clock time in seconds — use two calls to measure elapsed time |
| `omp.in_parallel()` | `bool` | True if currently executing inside a parallel region |

---

## Block Statements

### `omp.parallel { ... }`

Spawns `omp.max_threads()` threads and runs the body concurrently. Inside the block, `omp.thread_id()` returns the current thread's index.

```
omp.set_threads(4)
omp.parallel {
    id := omp.thread_id()
    @pf("thread {id} running\n")
}
```

### `omp.for elem => start..end { ... }`

Splits a range loop across all available threads. Each thread processes a contiguous chunk of `start..end`. `elem` holds the current index.

```
omp.for i => 0..100 {
    @pf("item {i} on thread {omp.thread_id()}\n")
}
```

---

## Timing Example

```
@import(omp = @zcy.openmp)

@main {
    t0 := omp.wtime()

    omp.set_threads(8)
    omp.parallel {
        # ... work ...
    }

    t1 := omp.wtime()
    @pf("elapsed: {t1 - t0}s\n")
}
```
