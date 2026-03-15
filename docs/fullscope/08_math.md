# Math — `@math::`

The `@math::` namespace wraps Zig's `std.math` and compiler intrinsics. No import needed.

---

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `@math::pi` | 3.14159265358979… | π |

```
area := @math::pi * r * r
```

---

## Basic Operations

| Function | Description |
|----------|-------------|
| `@math::abs(x)` | Absolute value (works on any numeric type) |
| `@math::min(a, b, …)` | Minimum of two or more values |
| `@math::max(a, b, …)` | Maximum of two or more values |
| `@math::floor(x)` | Floor (round down) |
| `@math::ceil(x)` | Ceiling (round up) |
| `@math::sqrt(x)` | Square root |
| `@math::exp(base, exp)` | Power: `base ^ exp` |

```
@pl(@math::abs(-7))           # 7
@pl(@math::min(3, 8, 1))      # 1
@pl(@math::max(3, 8, 1))      # 8
@pl(@math::floor(3.9))        # 3
@pl(@math::ceil(3.1))         # 4
@pl(@math::sqrt(25.0))        # 5.0
@pl(@math::exp(2.0, 10.0))    # 1024.0
```

---

## Logarithms

| Function | Description |
|----------|-------------|
| `@math::log(x)` | Natural logarithm (base e) |
| `@math::log2(x)` | Logarithm base 2 |
| `@math::log10(x)` | Logarithm base 10 |

```
@pf("ln(e)    = {@math::log(2.718281828):.4f}\n")   # 1.0000
@pf("log2(8)  = {@math::log2(8.0):.1f}\n")          # 3.0
@pf("log10(1000) = {@math::log10(1000.0):.1f}\n")   # 3.0
```

---

## Trigonometry

All trig functions work in **radians**.

| Function | Description |
|----------|-------------|
| `@math::sin(x)` | Sine |
| `@math::cos(x)` | Cosine |
| `@math::tan(x)` | Tangent |

```
angle :: @math::pi / 4.0    # 45 degrees

@pf("sin(45°) = {@math::sin(angle):.4f}\n")   # 0.7071
@pf("cos(45°) = {@math::cos(angle):.4f}\n")   # 0.7071
@pf("tan(45°) = {@math::tan(angle):.4f}\n")   # 1.0000
```

Convert degrees to radians:

```
deg := 90.0
rad := deg * @math::pi / 180.0
@pf("sin(90°) = {@math::sin(rad):.1f}\n")     # 1.0
```

---

## Examples

### Hypotenuse

```
fn hypotenuse(a: f64, b: f64) -> f64 {
    ret @math::sqrt(a * a + b * b)
}

@main {
    h := hypotenuse(3.0, 4.0)
    @pf("hypotenuse = {h:.1f}\n")    # 5.0
}
```

### Circle Area and Circumference

```
fn circle(r: f64) {
    area := @math::pi * r * r
    circ := 2.0 * @math::pi * r
    @pf("r={r:.1f}  area={area:.2f}  circ={circ:.2f}\n")
}

@main {
    circle(1.0)
    circle(5.0)
    circle(10.0)
}
```

### Clamping a Value

```
fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    ret @math::max(lo, @math::min(hi, x))
}

@main {
    @pl(clamp(15.0, 0.0, 10.0))    # 10.0
    @pl(clamp(-5.0, 0.0, 10.0))    # 0.0
    @pl(clamp( 7.0, 0.0, 10.0))    # 7.0
}
```

### Monte Carlo π Estimate

```
@main {
    inside := 0
    N :: 1000000
    for _ => 0..N {
        x := @rng(f64, -1.0, 1.0)
        y := @rng(f64, -1.0, 1.0)
        if x * x + y * y <= 1.0 {
            inside += 1
        }
    }
    est := 4.0 * @f64(inside) / @f64(N)
    @pf("π ≈ {est:.5f}\n")
}
```
