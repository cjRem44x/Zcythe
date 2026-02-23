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
- No parser yet; lexer output is a flat token stream.
- `@` followed by a non-alphanumeric character produces a `.builtin` with a bare `@` lexeme — to be tightened up when the parser enforces valid builtin names.
- Numeric literals do not yet support hex (`0x…`) or binary (`0b…`) prefixes.
