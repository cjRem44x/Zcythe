# Testing — `@test` & `@assert`

Zcythe has a first-class test system modelled after Zig's built-in tests. Tests live alongside normal code in `.zcy` files and are run with `zcy test`.

---

## Writing Tests

Use `@test "description" { … }` as a top-level block:

```
@test "addition works" {
    result := 2 + 3
    @assert_eq(result, 5)
}

@test "string comparison" {
    greeting :: "hello"
    @assert_str(greeting, "hello")
}

@test "boolean condition" {
    x := 42
    @assert(x > 0)
    @assert(x < 100)
}
```

---

## Running Tests

```bash
# Run all @test blocks in the project
zcy test

# Run tests in a specific file
zcy test src/main/zcy/utils.zcy
```

Output looks like:

```
1/3 main.test.addition works...OK
2/3 main.test.string comparison...OK
3/3 main.test.boolean condition...OK
All 3 tests passed.
```

If a test fails, the output shows which assertion failed and the expected vs. actual values:

```
1/3 main.test.addition works...FAIL (TestUnexpectedResult)
    expected 6
    found    5
```

---

## Assert Builtins

### `@assert(condition)`

Asserts that `condition` is `true`. Fails with `TestUnexpectedResult` otherwise.

```
@test "range check" {
    n := 50
    @assert(n >= 0)
    @assert(n <= 100)
    @assert(n != 0)
}
```

### `@assert_eq(actual, expected)`

Asserts that `actual == expected`. Fails with a message showing both values.

```
@test "math" {
    @assert_eq(2 + 2, 4)
    @assert_eq(10 / 2, 5)
    @assert_eq(@math::abs(-7), 7)
}
```

### `@assert_str(actual, expected)`

Asserts that two strings are equal. Shows the full strings on failure (byte-by-byte comparison).

```
@test "strings" {
    s := "hello"
    @assert_str(s, "hello")
    @assert_str("world", "world")
}
```

---

## Tests Alongside Code

`@test` blocks can coexist with `@main` and function declarations in the same file. `zcy build` and `zcy run` ignore test blocks; `zcy test` ignores `@main`.

```
fn add(a: i32, b: i32) -> i32 { ret a + b }
fn mul(a: i32, b: i32) -> i32 { ret a * b }

@test "add" {
    @assert_eq(add(2, 3), 5)
    @assert_eq(add(0, 0), 0)
    @assert_eq(add(-1, 1), 0)
}

@test "mul" {
    @assert_eq(mul(3, 4), 12)
    @assert_eq(mul(0, 99), 0)
}

@main {
    @pf("2 + 3 = {add(2, 3)}\n")
    @pf("3 * 4 = {mul(3, 4)}\n")
}
```

---

## Testing User-Defined Types

```
struct Vec2 { x: f32, y: f32 }

fn length(v: Vec2) -> f32 {
    ret @math::sqrt(v.x * v.x + v.y * v.y)
}

@test "Vec2 length" {
    v := Vec2 { .x = 3.0, .y = 4.0 }
    l := length(v)
    @assert(l > 4.9)
    @assert(l < 5.1)
}

@test "zero vector" {
    zero := Vec2 { .x = 0.0, .y = 0.0 }
    @assert_eq(length(zero), 0.0)
}
```

---

## Complete Test Suite Example

```
fn is_prime(n: i32) -> bool {
    if n < 2 { ret false }
    i := 2
    while i * i <= n {
        if n % i == 0 { ret false }
        i += 1
    }
    ret true
}

fn factorial(n: i32) -> i32 {
    if n <= 1 { ret 1 }
    ret n * factorial(n - 1)
}

@test "primality" {
    @assert(!is_prime(1))
    @assert( is_prime(2))
    @assert( is_prime(3))
    @assert(!is_prime(4))
    @assert( is_prime(5))
    @assert(!is_prime(9))
    @assert( is_prime(97))
}

@test "factorial" {
    @assert_eq(factorial(0), 1)
    @assert_eq(factorial(1), 1)
    @assert_eq(factorial(5), 120)
    @assert_eq(factorial(10), 3628800)
}

@main {
    @pl("Run `zcy test` to verify these functions.")
}
```

---

## Quick Reference

| Construct | Description |
|-----------|-------------|
| `@test "name" { … }` | Declare a test block |
| `@assert(cond)` | Fail if `cond` is false |
| `@assert_eq(a, b)` | Fail if `a != b` |
| `@assert_str(a, b)` | Fail if strings differ |
| `zcy test` | Run all test blocks |
| `zcy test file.zcy` | Run tests from one file |
