# User-Defined Types

Zcythe has four ways to define structured types: `dat`, `cls`, `struct`, and `enum`.

---

## `dat` — Data Record

`dat` declares a plain data record with named, typed fields. Methods are **not** allowed on `dat` — it is data only.

```
dat Point {
    x: f32,
    y: f32,
}

dat Person {
    name: str,
    age:  i32,
}
```

Create an instance with struct-literal syntax:

```
p := Point  { .x = 3.0, .y = 4.0 }
alice := Person { .name = "Alice", .age = 30 }
```

Access fields with `.`:

```
@pf("({p.x}, {p.y})\n")
@pf("{alice.name} is {alice.age}\n")
```

---

## `cls` — Class *(Beta)*

> **Beta:** `cls` is implemented and functional, but the system is still being refined. Inheritance, interface enforcement, and method dispatch are expected to improve in upcoming releases.

`cls` is a full object-oriented type with fields, a constructor (`@init`), a destructor (`@deinit`), and methods.

### Basic Class

```
cls Counter {
    value: i32,

    @init {
        self.value = 0
    }

    pub fn increment() {
        self.value += 1
    }

    pub fn get() -> i32 {
        ret self.value
    }
}

@main {
    c := Counter{}
    c.increment()
    c.increment()
    @pl(c.get())    # 2
}
```

### Visibility

Fields and methods are **private by default**. Mark them `pub` to expose them.

```
cls Wallet {
    balance: f64,         # private

    @init {
        self.balance = 0.0
    }

    pub fn deposit(amount: f64) {
        self.balance += amount
    }

    pub fn get_balance() -> f64 {
        ret self.balance
    }
}
```

### Inheritance

Use `: ParentClass` to extend another class. Mark the base class `pub` if the parent's public API should be re-exported.

```
cls Animal {
    name: str,

    @init {
        self.name = "unknown"
    }

    pub fn speak() {
        @pl("...")
    }
}

cls Dog : pub Animal {
    @init {
        self.name = "Rex"
    }

    ovrd fun speak() {
        @pf("{self.name} says: woof!\n")
    }
}
```

`ovrd fun` overrides a method from the parent class.

### Interfaces / Implements

```
cls Printable :: IShow {
    pub fn show() {
        @pl("I am printable")
    }
}
```

With both a base class and interfaces:

```
cls Widget : pub View : IClickable, IDrawable {
    ...
}
```

### Constructor and Destructor

```
cls Buffer {
    data: []u8,

    @init {
        self.data = @malloc(u8, 256)
    }

    @deinit {
        @free(self.data)
    }

    pub fn write(b: u8, i: usize) {
        self.data[i] = b
    }
}
```

---

## `struct` — Struct with Methods

`struct` is similar to `cls` but lighter — no inheritance, no `@init`/`@deinit` blocks. Fields can omit their type annotation when the type can be inferred from usage.

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
dat Vec3 { x: f32, y: f32, z: f32 }

fn dot(a: Vec3, b: Vec3) -> f32 {
    ret a.x * b.x + a.y * b.y + a.z * b.z
}

@main {
    u := Vec3 { .x = 1.0, .y = 0.0, .z = 0.0 }
    v := Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 }
    @pf("dot = {dot(u, v)}\n")    # 0.0
}
```
