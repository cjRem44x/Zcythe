# Variables & Types

## Declaration Syntax

Zcythe has five ways to declare a variable. The sigil between the name and value encodes both mutability and whether the type is explicit.

| Form | Mutability | Type | Example |
|------|-----------|------|---------|
| `x := value` | mutable | inferred | `count := 0` |
| `x : T = value` | mutable | explicit | `count : i32 = 0` |
| `x :: value` | immutable | inferred | `PI :: 3.14159` |
| `x : T : value` | immutable | explicit | `PI : f64 : 3.14159` |
| `let x : T = value` | mutable | explicit | `let name : str = "alice"` |

```
# Mutable, type inferred
score := 100

# Mutable, explicit type
score : i32 = 100

# Immutable constant
MAX :: 255

# Immutable constant with explicit type
MAX : u8 : 255

# let — explicit mutable declaration
let label : str = "hello"
```

> **Tip:** Prefer `:=` and `::` for local variables. Use `: T =` or `: T :` when the type needs to be documented at the declaration site.

---

## Primitive Types

### Integer Types

| Type | Width | Range |
|------|-------|-------|
| `i8` | 8-bit signed | −128 … 127 |
| `i16` | 16-bit signed | −32 768 … 32 767 |
| `i32` | 32-bit signed | −2 147 483 648 … 2 147 483 647 |
| `i64` | 64-bit signed | −9.2×10¹⁸ … 9.2×10¹⁸ |
| `i128` | 128-bit signed | — |
| `u8` | 8-bit unsigned | 0 … 255 |
| `u16` | 16-bit unsigned | 0 … 65 535 |
| `u32` | 32-bit unsigned | 0 … 4 294 967 295 |
| `u64` | 64-bit unsigned | 0 … 1.8×10¹⁹ |
| `u128` | 128-bit unsigned | — |
| `usize` | machine word, unsigned | platform-dependent |
| `isize` | machine word, signed | platform-dependent |

### Floating-Point Types

| Type | Width |
|------|-------|
| `f16` | 16-bit IEEE 754 |
| `f32` | 32-bit IEEE 754 |
| `f64` | 64-bit IEEE 754 |
| `f128` | 128-bit IEEE 754 |

### Other Primitives

| Type | Description | Zig equivalent |
|------|-------------|----------------|
| `str` | UTF-8 string slice | `[]const u8` |
| `char` | Single byte / ASCII character | `u8` |
| `bool` | Boolean | `bool` |

---

## Composite Type Modifiers

Type annotations can be prefixed to create arrays and pointers.

```
# Slice (dynamic array)
names : []str = {"alice", "bob"}

# Fixed-size array
coords : [3]f32 = {1.0, 2.0, 3.0}

# Pointer
ptr : *i32 = &value

# Pointer to immutable value (const pointee)
cptr : *val i32 = &constant
```

---

## Literals

### Integer & Float
```
x := 42
y := -7
pi :: 3.14159
```

### String
```
greeting :: "Hello, Zcythe!"
```

### Character
```
ch :: 'A'
```

### Boolean
```
flag := true
done := false
```

### Array
```
nums := {1, 2, 3, 4, 5}
words : []str = {"cat", "dog", "fox"}
```

### Struct
```
dat Point { x: f32, y: f32 }

p := Point { .x = 1.0, .y = 2.0 }
```

### Enum Literal (dot-notation)
```
enum Direction { NORTH, SOUTH, EAST, WEST }

dir := Direction.NORTH
dir2 : Direction = .SOUTH    # inferred type
```

---

## Numeric Casting

Use `@T(expr)` to cast between numeric types.

```
n : i64 = 1000
small := @i32(n)

f : f64 = 3.99
rounded := @i32(f)        # truncates toward zero

byte := @u8(255)
big   := @i64(byte)
```

The `@T` cast builtins cover every numeric type:
`@i8`, `@i16`, `@i32`, `@i64`, `@i128`,
`@u8`, `@u16`, `@u32`, `@u64`, `@u128`,
`@usize`, `@isize`, `@f32`, `@f64`, `@f128`.

When the source is a `str`, the cast parses the string:

```
raw  := @input("Enter a number: ")
num  := @i32(raw) catch |_| { 0 }    # parse error → default 0
```

---

## Undefined / Uninitialized Values

Use `@undef` to declare a variable without initializing it (dangerous — only use when you will assign before reading).

```
buf : [256]u8 = @undef
```

---

## Dynamic Arrays (`@list`)

`@list(T)` creates a growable array backed by `std.ArrayListUnmanaged(T)`.

```
nums := @list(i32)
nums.add(10)
nums.add(20)
nums.add(30)

@pf("count: {nums.len}\n")

for n => nums {
    @pl(n)
}

nums.remove(0)     # remove at index 0
nums.clear()       # remove all elements
```

---

## Memory Allocation

For manual heap allocation use `@malloc` and `@free`:

```
buf := @malloc(u8, 1024)
buf[0] = 65

@free(buf)
```

For allocator handles:
```
pa  := @getPageAlloc()
gpa := @getGenPurpAlloc()
aa  := @getArenaAlloc(gpa)
fba := @getFixedBufAlloc()    # 64 KB fixed buffer
```
