# Functions

## Basic Declaration

```
fn greet() {
    @pl("Hello!")
}
```

## Parameters

Parameters can omit the type annotation (type is inferred) or include it explicitly.

```
fn add(a: i32, b: i32) -> i32 {
    ret a + b
}

fn print_name(name) {
    @pf("Name: {name}\n")
}
```

## Return Types

```
fn square(x: i32) -> i32 {
    ret x * x
}
```

### Optional Return (`T?`)

The function may return a value or nothing (`null`).

```
fn find(items: []i32, target: i32) -> i32? {
    for v, i => items {
        if v == target { ret i }
    }
    ret null
}
```

### Error Union Return (`T!`)

The function may return a value or propagate an error.

```
fn read_line(path: str) -> str! {
    f := try @fs::FileReader::open(path)
    defer f.cl()
    ret try f.rln()
}
```

### Optional Error Union (`T?!E`)

Both optional and error-returning:

```
fn parse_int(s: str) -> i32?!ParseError {
    ...
}
```

### Void Error Return (`any`)

Functions that return nothing but may fail use `any` as the return type:

```
fn write_file(path: str, data: str) -> any {
    f := try @fs::FileWriter::open(path)
    defer f.cl()
    try f.w(data)
}
```

---

## The `ret` Statement

`ret` returns from the current function. It can be used without a value in void functions.

```
fn check(x: i32) {
    if x < 0 { ret }
    @pf("x = {x}\n")
}

fn double(x: i32) -> i32 {
    ret x * 2
}
```

---

## Calling Functions

```
result := add(3, 4)
print_name("Alice")
```

---

## Generic / Comptime Parameters

Use `@comptime T param_name` to declare a type parameter. The caller passes a concrete type.

```
fn identity(@comptime T val, x: T) -> T {
    ret x
}

n := identity(i32, 42)
s := identity(str, "hello")
```

This maps to Zig `comptime T: type` parameters.

---

## Lambda / Anonymous Functions

Use `fun` to create a function value that can be stored or passed as an argument.

```
double := fun(x: i32) -> i32 { ret x * 2 }
result := double(21)
```

Short block form:

```
transform := fun(n: i32) { @pf("n={n}\n") }
transform(5)
```

With explicit return type:

```
adder := fun(a: i32, b: i32) -> i32 {
    ret a + b
}
```

---

## Functions as Values

Functions are first-class. You can store them in variables, pass them to other functions, and return them.

```
fn apply(f: fun(i32) -> i32, x: i32) -> i32 {
    ret f(x)
}

triple := fun(n: i32) -> i32 { ret n * 3 }
@pl(apply(triple, 7))   # prints 21
```

---

## Recursion

```
fn fib(n: i32) -> i32 {
    if n <= 1 { ret n }
    ret fib(n - 1) + fib(n - 2)
}

@main {
    for i => 0..10 {
        @pf("fib({i}) = {fib(i)}\n")
    }
}
```

---

## Method Calls

Methods on types (see [User-Defined Types](04_types.md)) are called with dot notation:

```
p := Person { .name = "Alice", .age = 30 }
p.greet()
name := p.get_name()
```

---

## Top-Level Entry Point

Every executable Zcythe program has exactly one `@main` block:

```
@main {
    @pl("Hello, world!")
}
```

`@main` compiles to `pub fn main() !void { … }`.
