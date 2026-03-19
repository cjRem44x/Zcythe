# Error Handling

Zcythe error handling is built on Zig's error union system. Functions that can fail return `T!` (an error union), and errors are propagated or matched explicitly.

---

## `try` — Propagate on Error

`try expr` evaluates `expr`. If it returns an error, the error is immediately returned from the current function. If it succeeds, the unwrapped value is produced.

```
fn copy_file(src: str, dst: str) -> any {
    f_in  := try @fs::file_reader::open(src)
    defer f_in.cl()

    f_out := try @fs::file_writer::open(dst)
    defer f_out.cl()

    data := try f_in.rall()
    try f_out.w(data)
}
```

`try` can only be used inside functions that declare an error-union or `any` return type.

---

## `catch` — Handle Error

`catch` lets you inspect or recover from errors inline. The syntax uses `|binding|` to name the error and a block of arms to match specific error types.

### Basic Catch

```
result := read_int() catch |err| {
    _ => { 0 }    # wildcard: return 0 on any error
}
```

### Matching Specific Errors

```
data := @fs::file_reader::open("config.txt") catch |err| {
    error.FileNotFound    => { "" },
    error.AccessDenied    => { @pl("permission denied"); "" },
    _                     => { @pl("unknown error"); "" },
}
```

### Ignoring the Binding

When you don't need the error value:

```
val := parse_number(raw) catch { _ => { -1 } }
```

---

## Error Return Types

| Annotation | Meaning |
|-----------|---------|
| `-> T!` | Returns `T` or propagates any error |
| `-> any` | Returns nothing, but may propagate an error |
| `-> T?` | Returns optional T (null = absent, no error) |
| `-> T?!E` | Returns optional T or error E |

```
fn load_config(path: str) -> str! {
    f := try @fs::file_reader::open(path)
    defer f.cl()
    ret try f.rall()
}

fn find_user(id: i32) -> str? {
    if id == 1 { ret "alice" }
    ret null
}
```

---

## Combining `try` and `catch`

Use `try` for the happy path and `catch` at a boundary where you can recover:

```
@main {
    content := load_config("settings.txt") catch |_| {
        _ => { "default=true\n" }
    }
    @pl(content)
}
```

---

## Typed Input with Error Handling

`@input::T` builtins return an error union that must be caught:

```
age_raw := @input::i32("Enter age: ") catch |_| { _ => { 0 } }
weight  := @input::f64("Weight (kg): ") catch |_| { _ => { 0.0 } }
```

Available typed inputs:
- `@input::i32(prompt)` — parse integer
- `@input::f64(prompt)` — parse float
- `@input::str(prompt)` — raw string (never fails)

---

## Example: Robust File Processing

```
fn process(path: str) -> any {
    f := try @fs::file_reader::open(path)
    defer f.cl()

    loop {
        line := f.rln() catch |_| { _ => { break } }
        if !f.eof() { break }
        @pf("> {line}\n")
    }
}

@main {
    process("data.txt") catch |err| {
        error.FileNotFound => { @pl("file not found") },
        _                  => { @pl("error reading file") },
    }
}
```
