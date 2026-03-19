# Control Flow

## If / Else

Parentheses around the condition are optional.

```
x := 42

if x > 0 {
    @pl("positive")
}

if (x > 100) {
    @pl("big")
} else {
    @pl("small")
}
```

Chains with `elif` (preferred) or `else if`:

```
grade := 85

if grade >= 90 {
    @pl("A")
} elif grade >= 80 {
    @pl("B")
} elif grade >= 70 {
    @pl("C")
} else {
    @pl("F")
}
```

`elif` is the canonical Zcythe form; `else if` also works as an alias.

---

## For Loop

Zcythe's `for` loop is always an iteration over a collection or range.

### Iterating a Collection

```
words := {"apple", "banana", "cherry"}

for w => words {
    @pl(w)
}
```

### With an Index

```
for w, i => words {
    @pf("[{i}] {w}\n")
}
```

### Index Only (discard element)

```
for _, i => items {
    @pf("index {i}\n")
}
```

### With an Explicit Range

Iterate only a sub-range of the collection:

```
data := {10, 20, 30, 40, 50}

# Exclusive range 0..3  → indices 0, 1, 2
for v => data, 0..3 {
    @pl(v)
}

# Inclusive range 1..=3 → indices 1, 2, 3
for v, i => data, 1..=3 {
    @pf("data[{i}] = {v}\n")
}
```

### Range-Only Loop (no collection)

Use a range expression as the iterable to produce integers:

```
for i => 0..10 {
    @pf("{i} ")
}
# prints: 0 1 2 3 4 5 6 7 8 9

for i => 1..=5 {
    @pf("{i} ")
}
# prints: 1 2 3 4 5
```

### Open Range

```
for i => 5.. {    # from 5 with no upper bound
    @pl(i)
    if i >= 9 { break }    # must break manually
}
```

---

## While Loop

```
n := 1
while n <= 10 {
    @pf("{n} ")
    n += 1
}
```

### While with Do-Expression

The expression after `=>` runs at the end of each iteration (like the update clause of a C `for`):

```
i := 0
while i < 10 => i += 1 {
    @pf("{i} ")
}
```

---

## Loop (C-Style)

`loop` is syntactic sugar for a classic init/condition/update loop. All three parts are separated by commas.

```
loop i := 0, i < 10, i += 1 {
    @pf("{i} ")
}

# With multiple variables
loop i := 0, j := 10, i < j, i += 1, j -= 1 {
    @pf("{i},{j} ")
}
```

---

## Switch

`switch` matches a subject against a list of value arms. Use `_` as the default/wildcard arm.

```
status := 2

switch (status) {
    1 => { @pl("running") },
    2 => { @pl("stopped") },
    3 => { @pl("error")   },
    _ => { @pl("unknown") },
}
```

Works with enums:

```
enum Color { RED, GREEN, BLUE }

c : Color = .GREEN

switch c {
    .RED   => { @pl("red")   },
    .GREEN => { @pl("green") },
    .BLUE  => { @pl("blue")  },
}
```

---

## Defer

`defer` schedules a statement to run when the enclosing scope exits — regardless of how it exits (normal return, early return, or error).

```
@main {
    f := @fs::file_writer::open("out.txt")
    defer f.cl()

    f.w("line 1\n")
    f.w("line 2\n")
    # f.cl() is called here automatically
}
```

Multiple `defer` statements run in reverse order (LIFO):

```
defer @pl("third")
defer @pl("second")
defer @pl("first")
# prints: first, second, third
```

---

## Break and Continue

Standard `break` and `continue` work inside loops:

```
for i => 0..20 {
    if i == 5 { continue }   # skip 5
    if i == 10 { break }     # stop at 10
    @pf("{i} ")
}
```
