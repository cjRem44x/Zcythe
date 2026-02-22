# An Introduction

Zcythe is a statically-typed, compiled programming language implemented in Zig.

---

## Language at a glance

| Concept | Syntax |
|---|---|
| Mutable implicit-type var | `x := 32` |
| Mutable explicit-type var | `y : str = "hello"` |
| Immutable implicit-type | `PI :: 3.145` |
| Immutable explicit-type | `FOO :str: "Bar"` |
| Function | `fn name(a, b) -> RetType { ret val }` |
| Simple function | `fn add(a, b) { ret a+b }` |
| Line comment | `# this is a comment` |
| Builtin | `@main`, `@pl`, `@pf`, `@import`, … |

### Control flow

```
for e, i => collection, 0.. { }   # for-each with index
for e => collection { }            # for-each
loop i := 0, i < n, i+=1 { }      # C-style loop
while cond { }                     # while
while cond => my_func() { }        # while-do
```

### Error handling

```
try Foo()               # propagate error up
Foo() catch |e| {
    SpecificErr => {},
    _ => {}
}
```

### Types

```
i8  u8  i16  u16  i32  u32  i64  u64  i128  u128
f16  f32  f64  f128
str   # alias for []const u8
any
```

### Structs, Dats, and Classes

```
struct Foo { x, bar: str, pub fn method() {} }
dat   Point { x: f32, y: f32 }          # data-only, no methods
cls   Person : pub Human : Talk, Walk { @init {} }
```

---

## Compiler pipeline

```
Source text
    │
    ▼
[ Lexer ]  ──  src/lexer.zig
    │  Token stream (TokenKind, lexeme, Loc)
    ▼
[ Parser ]  (planned)
    │  AST
    ▼
[ Codegen ]  (planned)
```

---

## Lexer token reference  (`src/lexer.zig`)

### Literals

| Kind | Example |
|---|---|
| `int_lit` | `42` |
| `float_lit` | `3.14` |
| `string_lit` | `"hello"` |
| `char_lit` | `'A'` |

### Names

| Kind | Example |
|---|---|
| `ident` | `foo`, `MyType`, `_x` |
| `builtin` | `@main`, `@pl`, `@import` |

### Keywords

`fn` `fun` `ret` `struct` `cls` `dat` `pub` `ovrd`
`for` `loop` `while` `try` `catch` `self` `any`

### Operators

| Token | Kind |
|---|---|
| `:=` | `decl_mut` |
| `::` | `decl_immut` |
| `->` | `arrow` |
| `=>` | `fat_arrow` |
| `..` | `range_ex` |
| `..=` | `range_in` |
| `<<` | `lshift` |
| `+=` `-=` `*=` `/=` | compound assign |
| `==` `!=` `<=` `>=` | comparison |
| `&&` `\|\|` | logical |
