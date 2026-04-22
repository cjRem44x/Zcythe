# User-Defined Types

Zcythe has three ways to define structured types: `dat`, `struct`, and `enum`.

---

## `dat` — Static Data Block

`dat` declares a **static data block** — a module-level singleton where all fields are globally accessible and mutable. Methods are not allowed on `dat`; use `struct` for types with behaviour.

```
dat Foo {
    x: str,
    y: f32,
}

@main {
    # static access — no instance needed
    Foo.x = "hello"
    Foo.y = 4.0
    @pf("x={Foo.x}, y={Foo.y}\n")
}
```

All fields are zero-initialised by default (`""` for `str`, `0` for numerics, `false` for `bool`).

---

## `struct` — Struct with Methods

`struct` declares a named type with fields and optional member functions. Instances are created with struct-literal syntax.

```
struct Vec2 {
    x: f32,
    y: f32,

    pub fn length() -> f32 {
        ret @math::sqrt(self.x * self.x + self.y * self.y)
    }

    pub fn add(other: Vec2) -> Vec2 {
        ret Vec2 { .x = self.x + other.x, .y = self.y + other.y }
    }
}

@main {
    a := Vec2 { .x = 3.0, .y = 4.0 }
    @pf("length = {a.length()}\n")    # 5.0
}
```

Fields and methods are **private by default**; mark them `pub` to expose them.

`pub fn init(...)` with no `self` parameter becomes a static factory function.

---

## `enum` — Enumeration

### Plain Enum

```
enum Direction { NORTH, SOUTH, EAST, WEST }

dir := Direction.NORTH

switch dir {
    .NORTH => { @pl("going north") },
    .SOUTH => { @pl("going south") },
    _      => { @pl("other")       },
}
```

### Integer-Backed Enum

Add a backing type with `=> T`:

```
enum Status => i32 {
    IDLE    = 0,
    RUNNING = 1,
    STOPPED = 2,
    ERROR   = 3,
}

s : Status = .RUNNING
code := @i32(s)   # → 1
```

### String-Backed Enum

```
enum Size => str {
    SMALL  = "sm",
    MEDIUM = "md",
    LARGE  = "lg",
}

sz : Size = .MEDIUM
@pl(sz)    # "md"
```

### Dot-Literal Inference

When the type is known from context, you can use `.VARIANT` without spelling out the enum name:

```
fn process(d: Direction) {
    if d == .EAST { @pl("heading east") }
}

process(.EAST)
```

---

## Nested Types

Types can be declared at the top level and referenced by name anywhere in the file:

```
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn dot(a: Vec3, b: Vec3) -> f32 {
    ret a.x * b.x + a.y * b.y + a.z * b.z
}

@main {
    u := Vec3 { .x = 1.0, .y = 0.0, .z = 0.0 }
    v := Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 }
    @pf("dot = {dot(u, v)}\n")    # 0.0
}
```
