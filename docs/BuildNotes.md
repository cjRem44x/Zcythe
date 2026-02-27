# Build Notes

## v0.0.1 – Lexer

### Tokens covered
All syntactic categories the lexer can produce are defined in `TokenKind` (`src/lexer.zig`):

- **Literals** – `int_lit`, `float_lit`, `string_lit`, `char_lit`
- **Names** – `ident`, `builtin` (`@name`)
- **Keywords** – `fn`, `fun`, `ret`, `if`, `else`, `struct`, `cls`, `dat`, `pub`, `ovrd`, `for`, `loop`, `while`, `try`, `catch`, `self`, `any`
- **Multi-char operators** – `:=`, `::`, `->`, `=>`, `..`, `..=`, `+=`, `-=`, `*=`, `/=`, `==`, `!=`, `<=`, `>=`, `&&`, `||`, `<<`, `>>`
- **Single-char operators** – `: ? ! + - * / = < > | & .`
- **Delimiters** – `{ } ( ) [ ]`
- **Punctuation** – `, ;`
- **Meta** – `comment` (`#`), `eof`, `invalid`

### Declaration forms supported

| Form             | Example                         | Tokens produced                          |
|------------------|---------------------------------|------------------------------------------|
| Mutable implicit | `x := 32`                      | `ident decl_mut int_lit`                 |
| Mutable explicit | `y : str = "hi"`               | `ident colon ident eq string_lit`        |
| Immutable implicit | `PI :: 3.14`               | `ident decl_immut float_lit`             |
| Immutable explicit | `FOO :str: "Bar"`          | `ident colon ident colon string_lit`     |
| Array mutable    | `arr: []i32 = {1,2}`           | `ident colon l_bracket r_bracket ident …`|
| Array immutable  | `names :[]str: {"a"}`          | `ident colon l_bracket r_bracket ident colon …`|

### Test coverage (by example file)

| Example file   | Tests added                                              |
|----------------|----------------------------------------------------------|
| `HelloWorld`   | `hello world snippet`, `cout stream operator`, `cout chained with endl`, `pf format string` |
| `Types`        | `variable declarations`                                  |
| `Funcs`        | `function declaration snippet`, `error return type snippet` |
| `Arrays`       | `mutable array declaration`, `immutable array declaration` |
| `Loops`        | `for loop snippet`, `traditional loop snippet`, `while loop snippet`, `while-do snippet` |
| `Err`          | `try error propagation`, `catch error handling snippet`  |
| `Cls`          | `class declaration snippet`, `class implements shorthand`, `override method snippet` |
| `Dats`         | `dat declaration snippet`                                |
| `Structs`      | `struct with self and pub fn`                            |
| `Imports`      | `import snippet`                                         |
| `Args`         | `getArgs and for-print snippet`                          |

### Known gaps / future work
- `@` followed by a non-alphanumeric character produces a `.builtin` with a bare `@` lexeme — to be tightened up when the parser enforces valid builtin names.
- Numeric literals do not yet support hex (`0x…`) or binary (`0b…`) prefixes.

---

## v0.0.1 – Parser

Files: `src/ast.zig`, `src/parser.zig`

### AST node catalogue

| Node kind      | Payload                                         | Notes                            |
|----------------|-------------------------------------------------|----------------------------------|
| `program`      | `Program { items: []*Node }`                    | Root node                        |
| `main_block`   | `MainBlock { body: Block }`                     | `@main { … }`                    |
| `fn_decl`      | `FnDecl { name, params, ret_type, body }`       | `fn name(…) [-> T] { … }`        |
| `var_decl`     | `VarDecl { name, kind, type_ann, value }`       | All six declaration forms        |
| `block`        | `Block { stmts: []*Node }`                      | `{ … }`                          |
| `ret_stmt`     | `RetStmt { value: *Node }`                      | `ret expr`                       |
| `expr_stmt`    | `*Node`                                         | Stand-alone expression statement |
| `int_lit`      | `Token`                                         | Zero-copy raw token              |
| `float_lit`    | `Token`                                         |                                  |
| `string_lit`   | `Token`                                         |                                  |
| `char_lit`     | `Token`                                         |                                  |
| `ident_expr`   | `Token`                                         |                                  |
| `builtin_expr` | `Token`                                         | `@name`                          |
| `binary_expr`  | `BinaryExpr { op, left, right }`                |                                  |
| `unary_expr`   | `UnaryExpr { op, operand }`                     |                                  |
| `call_expr`    | `CallExpr { callee, args }`                     | `callee(args…)`                  |
| `field_expr`   | `FieldExpr { object, field }`                   | `object.field`                   |
| `array_lit`    | `ArrayLit { elems: []*Node }`                   | `{e, e, …}`                      |
| `struct_lit`   | `StructLit { type_name, fields: []StructField }`| `Type{.f = v, …}`               |

### Variable-declaration forms (`VarKind`)

| Kind             | Syntax            |
|------------------|-------------------|
| `mut_implicit`   | `x := expr`       |
| `immut_implicit` | `x :: expr`       |
| `mut_explicit`   | `x : T = expr`    |
| `immut_explicit` | `x : T : expr`    |
| `mut_explicit`   | `x : []T = expr`  |
| `immut_explicit` | `x : []T : expr`  |

### Operator precedence (low → high)

```
assignment   =  +=  -=  *=  /=     (right-hand side re-parsed as logical)
logical      &&  ||
equality     ==  !=
relational   <  >  <=  >=
stream       <<
additive     +  -
multiplicative  *  /
unary        -  !                  (right-recursive)
postfix      ()  .                 (left-recursive)
primary      literals, idents, builtins, struct/array literals, parentheses
```

### Test coverage

| Test                                    | Construct verified                          |
|-----------------------------------------|---------------------------------------------|
| `empty @main block`                     | program → main_block (zero stmts)           |
| `@main with @pl call`                   | builtin call expression as expr_stmt        |
| `var decl: mut implicit (:=)`           | `x := 32`                                   |
| `var decl: immut implicit (::)`         | `PI :: 3.145`                               |
| `var decl: mut explicit (: T =)`        | `y : str = "hello"`                         |
| `var decl: immut explicit (: T :)`      | `FOO : str : "Bar"`                         |
| `var decl: array mutable (: []T =)`     | `int_arr : []i32 = {1,2,3}`                 |
| `var decl: array immutable (: []T :)`   | `names : []str : {"John", "Joe"}`           |
| `fn decl without type annotations`      | `fn add(a, b) { ret a+b }`                  |
| `fn decl with typed params and ret type`| `fn add(a: i32, b: i32) -> i32 { … }`       |
| `operator precedence: a + b * c`        | `*` binds tighter than `+`                  |
| `field access chain: obj.field`         | `field_expr`                                |
| `function call with args: add(1, 2)`    | `call_expr`                                 |
| `struct literal: Person{…}`             | `struct_lit` with two fields                |
| `array literal: {1, 2, 3}`             | `array_lit` with three int elements         |

### Deferred to later versions
- Loops: `for`, `loop`, `while`
- Classes: `cls`, `ovrd`, `fun`
- Data structs: `dat`
- Error handling: `try`, `catch`, `!`/`?` types
- `pub` visibility modifier on top-level items
- `kw_self` in expression position
- Hex/binary integer literals
- Nullable and error-union type annotations (`T?`, `T!`)

---

## v0.0.2 – Code Generator

File: `src/codegen.zig`

### Overview

The `CodeGen` struct accepts any `std.io.AnyWriter` and walks the AST produced by
the parser, emitting equivalent Zig source.  Every generated file begins with a
standard preamble:

```zig
const std = @import("std");
```

Top-level function declarations are emitted before `@main`; the `@main` block
becomes `pub fn main() !void { … }`.

### Supported constructs

| Zcythe construct              | Emitted Zig                                               |
|-------------------------------|-----------------------------------------------------------|
| `@main { … }`                 | `pub fn main() !void { … }`                               |
| `fn name(p…) [-> T] { … }`   | `fn name(p…) RetType { … }`                               |
| `x := expr`                   | `var x = expr;`                                           |
| `PI :: expr`                  | `const PI = expr;`                                        |
| `y : T = expr`                | `var y: MappedT = expr;`                                  |
| `FOO : T : expr`              | `const FOO: MappedT = expr;`                              |
| `a : []T = {…}`               | `var a = [_]T{…};`                                        |
| `ret expr`                    | `return expr;`                                            |
| `obj.field`                   | `obj.field`                                               |
| `f(args)`                     | `f(args)`                                                 |
| `Type{.f=v,…}`                | `Type{ .f = v, … }`                                       |

### Type-name mapping

| Zcythe type | Zig type     |
|-------------|--------------|
| `str`       | `[]const u8` |
| everything else | pass-through |

### Builtin table

| Zcythe                       | Emitted Zig                                               |
|------------------------------|-----------------------------------------------------------|
| `@pl(string_lit)`            | `std.debug.print("{s}\n", .{<lit>});`                    |
| `@pl(other_expr)`            | `std.debug.print("{any}\n", .{<expr>});`                 |
| `@pf(fmt, args…)`            | `std.debug.print(<fmt>, .{<args…>});`                    |
| `@cout << string_lit`        | `std.debug.print("{s}", .{<lit>});`                      |
| `@cout << other_expr`        | `std.debug.print("{any}", .{<expr>});`                   |
| `… << @endl`                 | `std.debug.print("\n", .{});`                            |
| `@cout << a << b << @endl`   | one `std.debug.print` call per `<<` segment              |
| other `@builtin(…)`          | pass through as-is                                        |

### Function return-type inference

| Situation                                  | Emitted return type                              |
|--------------------------------------------|--------------------------------------------------|
| Explicit `-> T`                            | `mapType(T)`                                     |
| No annotation, at least one untyped param, exactly one `ret` | `@TypeOf(<ret expr>)`       |
| No annotation, at least one untyped param, zero or multiple `ret` | `void`             |
| No annotation, all params typed            | `void` *(TODO: infer)*                           |

Untyped parameter → `anytype`.

### Operator remapping

| Zcythe | Zig   |
|--------|-------|
| `&&`   | `and` |
| `\|\|` | `or`  |
| all others | pass-through lexeme |

### Zig keyword escaping

Zcythe has a smaller keyword set than Zig.  Names like `var`, `const`, `type`,
`if`, `return`, etc. are valid Zcythe identifiers but are reserved in Zig.
The codegen wraps any such name in Zig's `@"…"` escape syntax wherever a
user-supplied identifier is emitted:

- Variable names (`var @"var" = …`)
- Parameter names
- Function names
- Identifier expressions (`@"var"`)
- Field-access names (`obj.@"type"`)
- Struct literal type and field names

The full Zig keyword table lives in `isZigKeyword` (codegen.zig).

### Test coverage

| Test                                   | Key assertion                                           |
|----------------------------------------|---------------------------------------------------------|
| `zig keyword escaped in var decl`      | `var := …` with name `var` → `var @"var" = …;`         |
| `zig keyword escaped in ident expr`    | `@pl(var)` → `@"var"` in output                        |
| `preamble`                             | output starts with `const std = @import("std");`        |
| `empty @main`                   | exact round-trip for `@main {}`                         |
| `@pl string literal`            | `std.debug.print("{s}\n", .{"Hello World"})`            |
| `var decl mut implicit`         | `var x = 32;`                                           |
| `var decl immut implicit`       | `const PI = 3.145;`                                     |
| `var decl mut explicit`         | `var y: []const u8 = "hi";`                             |
| `var decl immut explicit`       | `const FOO: []const u8 = "Bar";`                        |
| `array var decl`                | `var a = [_]i32{1, 2, 3};`                              |
| `fn untyped params`             | `anytype` params, `@TypeOf(a + b)` return               |
| `fn typed params and ret`       | `fn add(a: i32, b: i32) i32 {`                          |
| `logical operators remapped`    | `a and b`                                               |
| `field access`                  | `obj.field`                                             |
| `function call`                 | `add(1, 2)`                                             |
| `struct literal`                | `Person{ .name = "J", .age = 32 }`                      |
| `@cout single segment`          | `std.debug.print("{s}", .{"Hello\n"})`                   |
| `@cout chained with @endl`      | one print per segment, `"\n"` for `@endl`                |
| `full hello world round-trip`   | preamble + main sig + print call all present            |

### Codegen leniency — string literal type inference

When a variable is initialised with a string literal and carries no explicit
type annotation, the codegen automatically inserts `: []const u8`:

| Zcythe              | Emitted Zig                              |
|---------------------|------------------------------------------|
| `x := "hello"`      | `const x: []const u8 = "hello";`        |
| `x : str = "hello"` | `const x: []const u8 = "hello";` (unchanged — explicit annotation) |

Without this, Zig infers `*const [N:0]u8`, which is incompatible with `{s}`
and causes `{any}` to print raw byte values instead of the string text.

`@pf` interpolation also consults the declaration to pick the right specifier:

| Initialiser of `name` | Spec used in `@pf("…{name}…")` |
|-----------------------|--------------------------------|
| string literal / `str`| `{s}`                          |
| integer / float       | `{d}`                          |
| other / not found     | `{any}`                        |

### Codegen leniency — auto-`const` promotion

Zcythe lets users write `x := value` for any mutable variable.  Zig, however,
rejects `var x = value` if `x` is never reassigned ("unused local variable").

The codegen now performs a mutation pre-pass over each block before emitting
variable declarations.  If a `:=` or `: T =` variable is never the target of
an assignment (`=`, `+=`, `-=`, `*=`, `/=`) in the same block, the generated
keyword is silently downgraded to `const`:

| Zcythe               | Zig (never reassigned) | Zig (reassigned later) |
|----------------------|------------------------|------------------------|
| `x := expr`          | `const x = expr;`      | `var x = expr;`        |
| `y : T = expr`       | `const y: T = expr;`   | `var y: T = expr;`     |
| `a : []T = {…}`      | `const a = [_]T{…};`   | `var a = [_]T{…};`     |

### Codegen leniency — `@pf` string interpolation

`@pf` traditionally follows Zig's `std.debug.print` signature:
`@pf(fmt, arg1, arg2, …)`.  To spare users from repeating identifiers,
single-arg `@pf` calls whose format string contains `{identifier}` patterns
have their arguments auto-extracted:

```
@pf("Hello {name}\n")
→  std.debug.print("Hello {any}\n", .{name});

@pf("Hello Pog {var}\n")
→  std.debug.print("Hello Pog {any}\n", .{@"var"});
```

Rules:
- Only triggered when `@pf` receives exactly **one** argument (the format string).
- Any `{spec}` where `spec` is a known Zig format specifier (`s`, `d`, `any`, …) is left unchanged.
- `{identifier}` → `{any}` in the format string; identifier is injected into the args tuple.
- Zig-keyword identifiers (`var`, `const`, …) are escaped with `@"name"` as usual.
- Multi-arg `@pf(fmt, a, b)` calls are passed through unchanged.

### `@cin >>` input stream

`@cin >> x` reads one line from stdin into an existing variable `x`.  Chaining
(`@cin >> x >> y`) reads successive lines.  Each `>>` site gets a unique
stack buffer (`_cin_buf_N: [4096]u8`).

| Zcythe                  | Emitted Zig (per `>>` site)                                             |
|-------------------------|-------------------------------------------------------------------------|
| `@cin >> x`             | `var _cin_buf_0: [4096]u8 = undefined;`<br>`x = (try std.io.getStdIn().reader().readUntilDelimiterOrEof(&_cin_buf_0, '\n')) orelse "";` |
| `@cin >> x >> y`        | two buffer+read pairs, indices 0 and 1                                 |

Auto-const analysis recognises `@cin >> x` as a mutation of `x`, so a
`:=`-declared variable that is only written via `@cin >>` is correctly
emitted as `var` instead of `const`.

### `fun` anonymous / first-class function expressions

`fun(params) [-> RetType] { body }` produces an anonymous function that can
appear in any expression position (variable initialisers, call arguments, etc.).

| Zcythe                       | Emitted Zig                                                 |
|------------------------------|-------------------------------------------------------------|
| `f := fun(a, b) { ret a+b }` | `const f = struct { fn call(a: anytype, b: anytype) @TypeOf(a + b) { return a + b; } }.call;` |
| `map(arr, fun(x) { ret x })` | `map(arr, struct { fn call(x: anytype) @TypeOf(x) { return x; } }.call)` |

Return-type inference follows the same rules as named `fn` declarations.

### `@import` top-level declarations

`@import(alias = module, alias2 = module2.TypeName, …)` at the top level emits
`const` import bindings immediately after the std preamble.

| Zcythe                          | Emitted Zig                                    |
|---------------------------------|------------------------------------------------|
| `@import(x = mymod)`            | `const x = @import("mymod.zig");`              |
| `@import(y = mymod.MyStruct)`   | `const y = @import("mymod.zig").MyStruct;`     |
| multiple args in one `@import`  | one `const` line per arg                       |

### Type-name mapping update

| Zcythe type | Zig type     |
|-------------|--------------|
| `str`       | `[]const u8` |
| `char`      | `u8`         |
| everything else | pass-through |

### `if` / `else` statements

Zcythe `if`/`else` maps directly to Zig `if`/`else`.  Both block-body and
single-statement bodies are supported; the codegen always wraps the body in
braces for clarity.

```zcythe
if (n <= 1) ret n                       // inline body
if (x > 0) { @pl("pos") }              // block body
if (flag) { a() } else { b() }         // with else
```

Emits:
```zig
if (n <= 1) {
    return n;
}
```

**Return-type inference fix** — recursive functions whose only top-level `ret`
is a recursive call (e.g. Fibonacci) previously caused Zig's type resolver to
segfault via `@TypeOf(fib(n-1)+fib(n-2))`.  The codegen now walks all `ret`
statements recursively through `if`/`else` branches and picks the first
non-recursive one for `@TypeOf`.  For Fibonacci this yields `@TypeOf(n)`.

### Test additions (v0.0.3)

| Test                                  | Key assertion                                                    |
|---------------------------------------|------------------------------------------------------------------|
| `@cin reads into declared variable`   | `readUntilDelimiterOrEof(&_cin_buf_0, '\n')` in output          |
| `@cin keeps target as var`            | `var x` emitted (not `const`) when `@cin >> x` present          |
| `fun expression stored in variable`   | `struct { fn call(` and `} }.call` in output                    |
| `fun passed as argument`              | same struct trick inside a call-arg position                     |
| `@import single alias`                | `const x = @import("mymod.zig");`                               |
| `@import field import`                | `const y = @import("mymod.zig").MyStruct;`                      |
| `char type maps to u8`                | `const c: u8 = 'a';`                                            |
| `if statement emits braces`           | `if (x > 0) {` in output                                        |
| `if/else statement`                   | `} else {` in output                                            |
| `if inline body wraps to block`       | inline `ret` still gets braces                                   |
| `recursive fn uses non-recursive ret` | `@TypeOf(n)` not `@TypeOf(fib(n-1)+fib(n-2))`                  |

### Loops

All three Zcythe loop forms are now parsed and emitted:

| Zcythe                              | Emitted Zig                                            |
|-------------------------------------|--------------------------------------------------------|
| `for e => items { body }`           | `for (items) \|e\| { body }`                          |
| `for e, i => items { body }`        | `for (items, 0..) \|e, i\| { body }`                  |
| `for e => items, 1.. { body }`      | `for (items[1..]) \|e\| { body }` *(slice, no idx)*   |
| `for e, i => items, 1.. { body }`   | `for (items, 1..) \|e, i\| { body }` *(parallel)*     |
| `while cond { body }`               | `while (cond) { body }`                               |
| `while cond => do { body }`         | `while (cond) : (do) { body }`                        |
| `loop init, cond, update { body }`  | `{ var init; while (cond) : (update) { body } }`      |

**Range semantics** — a range suffix (`start..`, `start..end`, `start..=end`) without an
index capture variable slices the iterable (`items[start..end]`).  When an index variable
is also requested the range becomes a parallel Zig for-input instead.

### Codegen leniency — mutable integer/float literals

Zig rejects `var x = 0` because `0` is a `comptime_int` which cannot be stored at runtime
without an explicit type.  The codegen now inserts a default type annotation whenever a
mutable (`var`) variable is initialised with a bare numeric literal and carries no explicit
type annotation:

| Zcythe          | Emitted Zig (when mutated)   |
|-----------------|------------------------------|
| `x := 0`        | `var x: i64 = 0;`            |
| `y := 3.14`     | `var y: f64 = 3.14;`         |

`const`-promoted variables (never reassigned) are unaffected — Zig handles `const x = 0`
fine because the value stays comptime.

### Codegen leniency — nested-block mutation detection

The auto-`const` promotion pass previously only scanned the **top-level** statements of the
block containing a declaration.  Assignments inside nested `while`/`for`/`loop`/`if` bodies
were invisible to it, causing variables mutated inside a loop to be wrongly emitted as
`const`.

`isReassignedInBlock` now recurses into all control-flow bodies (but not into nested `fn`
declarations, which introduce a new scope):

```zcythe
x := 0          # x mutated inside while → correctly emitted as var
while x < 99 {
    x += 1
}
```

emits `var x: i64 = 0;` (not `const`).

### Deferred to v0.0.4+

- Semantic analysis: symbol table, name resolution, type inference engine
- Classes, error handling (not yet parsed)
- Proper stdout vs stderr distinction (`@pl` currently uses `std.debug.print`)
- Hex/binary numeric literals

---

## v0.0.1 – CLI: build + run

File: `src/main.zig`

### Commands added

| Command      | What it does                                                              |
|--------------|---------------------------------------------------------------------------|
| `zcy build`  | Transpile → compile; writes `src/zcyout/main.zig`, emits `zcy-bin/main`  |
| `zcy run`    | `zcy build` then execute `zcy-bin/main` with inherited stdin/stdout/stderr |

### Build pipeline (zcy build)

1. Read `src/main/zcy/main.zcy` (error if missing — prompts `zcy init`).
2. Run through the full lex → parse → codegen pipeline.
3. Write generated Zig source to `src/zcyout/main.zig`.
4. Invoke `zig build-exe src/zcyout/main.zig -femit-bin=zcy-bin/<name>`.
5. Relay compiler stdout/stderr to the user.
6. Exit non-zero on compilation failure; print `"Build successful."` on success.

### Run pipeline (zcy run)

Calls `cmdBuild` then spawns `zcy-bin/<name>` with `.Inherit` on all three
standard file descriptors so interactive programs work normally.

### Error handling

| Condition                              | Behaviour                                           |
|----------------------------------------|-----------------------------------------------------|
| `src/main/zcy/main.zcy` missing        | Print helpful message, exit 1                       |
| Parse error                            | Print message, propagate error                      |
| `zig` not found in PATH                | Print message, exit 1                               |
| Non-zero exit from `zig build-exe`     | Relay compiler output, print "compilation failed", exit |

### Test coverage

| Test                                        | Key assertion                                    |
|---------------------------------------------|--------------------------------------------------|
| `cli: zcy build produces main binary`       | Exit 0, stdout contains "Build successful.", `zcy-bin/main` exists |
| `cli: zcy build writes src/zcyout/main.zig` | `src/zcyout/main.zig` exists after build         |
| `cli: zcy build without init exits non-zero`| Exit non-zero, stderr contains "not found"       |
| `cli: zcy run exits zero for hello world`   | Exit 0 for default hello-world project           |

---

## v0.0.1 – CLI: -name flag + zcy-bin output directory

File: `src/main.zig`

### Changes

- `zcy build` and `zcy run` now accept an optional `-name=NAME` flag.
- The compiled binary is always written to `zcy-bin/<NAME>` (default `NAME=main`).
- `zcy init` now creates the `zcy-bin/` directory alongside `src/zcyout/` and `src/main/zcy/`.
- A `parseName` helper scans extra CLI args for `-name=VALUE`.

### -name flag

| Invocation              | Binary path        |
|-------------------------|--------------------|
| `zcy build`             | `zcy-bin/main`     |
| `zcy build -name=greet` | `zcy-bin/greet`    |
| `zcy run`               | runs `zcy-bin/main`|
| `zcy run -name=greet`   | runs `zcy-bin/greet`|
