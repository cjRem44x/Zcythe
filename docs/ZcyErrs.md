# Zcythe Error Reference

Zcythe uses a friendlier error vocabulary that maps to Zig's standard error set at compile time.
When you write an error name in a `catch` arm, Zcythe translates it to the correct Zig name automatically.
Unrecognised names pass through unchanged, so user-defined errors always work.

---

## Syntax

```zcy
expr catch |e| {
    ErrName  => value,
    OtherErr => value,
    _        => value,   # wildcard / fallback
}
```

`try expr` propagates an error upward to the caller (or `@main`, which always accepts `!void`).

---

## Error Table

### Parsing / Number Conversion
Triggered by `@i8` / `@i16` / `@i32` / `@i64` / `@u8` / `@u16` / `@u32` / `@u64` /
`@f32` / `@f64` / `@usize` / `@isize` casts when the argument is a `str`.

| Zcythe Name   | Zig Name            | When it occurs                                      |
|---------------|---------------------|-----------------------------------------------------|
| `NumFormatErr`| `InvalidCharacter`  | String contains a non-numeric character             |
| `NumOverflow` | `Overflow`          | Parsed value exceeds the target type's max          |
| `NumUnderflow`| `Underflow`         | Parsed value is below the target type's min         |
| `ParseErr`    | `InvalidCharacter`  | Generic parse failure (alias for `NumFormatErr`)    |
| `InvalidBase` | `InvalidBase`       | Base argument to parseInt is not 2–16               |

### Memory
Triggered by `heap` `.alo()`, `@list`, or any operation using an allocator.

| Zcythe Name | Zig Name        | When it occurs                       |
|-------------|-----------------|--------------------------------------|
| `OutOfMem`  | `OutOfMemory`   | Allocator cannot satisfy the request |

### I/O — Streams
Triggered by `@input`, `@fs::` reader/writer methods.

| Zcythe Name    | Zig Name          | When it occurs                                  |
|----------------|-------------------|-------------------------------------------------|
| `EndOfStream`  | `EndOfStream`     | Read past end of file or stream                 |
| `StreamTooLong`| `StreamTooLong`   | `readln` line exceeded the internal buffer size |
| `BrokenPipe`   | `BrokenPipe`      | Write to a closed pipe or socket                |
| `InvalidUtf8`  | `InvalidUtf8`     | Byte sequence is not valid UTF-8                |

### I/O — Filesystem
Triggered by `@fs::file::open`, `@fs::dir::open`, and related `@fs::` calls.

| Zcythe Name   | Zig Name               | When it occurs                                    |
|---------------|------------------------|---------------------------------------------------|
| `FileNotFound`| `FileNotFound`         | Path does not exist                               |
| `FileExists`  | `PathAlreadyExists`    | Create/exclusive-open of an already-existing path |
| `FileTooBig`  | `FileTooBig`           | File exceeds OS or filesystem size limit          |
| `AccessDenied`| `AccessDenied`         | Insufficient permissions for the operation        |
| `IsDir`       | `IsDir`                | Expected a file but path is a directory           |
| `NotDir`      | `NotDir`               | Expected a directory but path is a file           |
| `NoSpace`     | `NoSpaceLeft`          | Disk or volume is full                            |
| `NotReadable` | `NotOpenForReading`    | File handle was not opened for reading            |
| `NotWritable` | `NotOpenForWriting`    | File handle was not opened for writing            |

### System / OS
Triggered by `@sys::exit` edge cases or low-level OS interactions.

| Zcythe Name    | Zig Name          | When it occurs                                         |
|----------------|-------------------|--------------------------------------------------------|
| `UnexpectedErr`| `Unexpected`      | OS returned an error code with no specific Zig mapping |
| `NotSupported` | `Unsupported`     | Operation not supported on this platform               |
| `WouldBlock`   | `WouldBlock`      | Non-blocking operation would have blocked              |
| `SysResources` | `SystemResources` | OS ran out of handles, threads, or file descriptors    |
| `InvalidHandle`| `InvalidHandle`   | File descriptor or handle is invalid                   |

---

## Pass-Through Names

Any error name not in the table above is emitted verbatim. This means:

- User-defined error names work without registration:
  ```zcy
  fn divide(a: i32, b: i32) -> i32! {
      if (b == 0) ret @err(DivByZero)
      ret a / b
  }

  divide(10, 0) catch |e| {
      DivByZero => @pl("can't divide by zero"),
      _         => @pl("other error"),
  }
  ```
- Zig error names can be used directly if no Zcythe alias exists for them.

---

## Examples

### Numeric cast with catch
```zcy
@main {
    s : str = @input("Enter number: ")
    n : i32 = @i32(s) catch |e| {
        NumFormatErr => 0,
        NumOverflow  => 2147483647,
        _            => -1,
    }
    @pl(n)
}
```

### File read with error handling
```zcy
@main {
    f := try @fs::file::open("data.txt", "r")
    line : str = f.readln() catch |e| {
        FileNotFound => "",
        AccessDenied => "",
        EndOfStream  => "",
        _            => "",
    }
    @pl(line)
    f.close()
}
```

### Propagating errors with try
```zcy
fn loadFile(path: str) -> str! {
    f := try @fs::file::open(path, "r")
    data := try f.readln()
    f.close()
    ret data
}

@main {
    content := loadFile("config.txt") catch |e| {
        FileNotFound => "default",
        _            => "",
    }
    @pl(content)
}
```

---

## Notes

- The mapping is applied at **codegen time** — no runtime cost.
- `_` as a catch arm matches any error not handled by a named arm (Zig `else =>`).
- When a catch arm value is a void call like `@pl(...)`, Zcythe automatically wraps it in a labeled block so the `switch` remains type-consistent.
- Math panics (`DivByZero`, integer overflow in arithmetic) are **runtime panics** in Zig, not catchable errors. Use guards (`if b != 0`) instead of catch for those.
