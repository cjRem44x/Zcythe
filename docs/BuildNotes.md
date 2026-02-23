# Build Notes

## v0.0.1 – Lexer

### Tokens covered
All syntactic categories the lexer can produce are defined in `TokenKind` (`src/lexer.zig`):

- **Literals** – `int_lit`, `float_lit`, `string_lit`, `char_lit`
- **Names** – `ident`, `builtin` (`@name`)
- **Keywords** – `fn`, `fun`, `ret`, `struct`, `cls`, `dat`, `pub`, `ovrd`, `for`, `loop`, `while`, `try`, `catch`, `self`, `any`
- **Multi-char operators** – `:=`, `::`, `->`, `=>`, `..`, `..=`, `+=`, `-=`, `*=`, `/=`, `==`, `!=`, `<=`, `>=`, `&&`, `||`, `<<`
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
