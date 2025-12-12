# ZcyASM Syntax Specification

> **⚠️ PROTOTYPE PHASE**: Syntax is subject to change as the language evolves.

This document defines the formal syntax and lexical structure of ZcyASM.

## Lexical Structure

### Comments

Single-line comments begin with `#` and continue to end of line.

```zcyasm
# This is a comment
.ldi: i32r0, 42  # Inline comment
```

**Multi-line comments**: TBD - Should we support `/* ... */` style?

### Whitespace

- Spaces and tabs are whitespace
- Whitespace is ignored except for separating tokens
- Newlines terminate statements (each instruction on separate line)

### Identifiers

**Variable names**: `[a-zA-Z_][a-zA-Z0-9_]*`
- Must start with letter or underscore
- Can contain letters, digits, underscores
- Case-sensitive

Examples: `counter`, `my_var`, `x1`, `_temp`

**Label names**: `[a-zA-Z_][a-zA-Z0-9_]*:`
- Same as variable names but followed by colon
- Case-sensitive

Examples: `loop_start:`, `main:`, `done:`

### Reserved Keywords

Instruction opcodes (cannot be used as variable names):
- Data movement: `ldd`, `ldi`, `mov`, `std`, `push`, `pop`
- Arithmetic: `add`, `sub`, `mul`, `div`, `mod`, `neg`, `inc`, `dec`
- Logical: `and`, `or`, `xor`, `not`, `shl`, `shr`
- Comparison: `cmp`, `tst`
- Control flow: `jmp`, `jeq`, `jne`, `jlt`, `jgt`, `jle`, `jge`, `call`, `ret`
- I/O: `print`, `println`, `read`
- Type conversion: `cast`
- System: `nop`, `hlt`, `dbg`

Type keywords:
- Signed: `i8`, `i16`, `i32`, `i64`, `i128`
- Unsigned: `u8`, `u16`, `u32`, `u64`, `u128`
- Float: `f16`, `f32`, `f64`, `f128`
- Boolean: `bool` (PLANNED)
- String: `str` (PLANNED)

### Register Names

Format: `<type>r<index>`

**Pattern**: `(i8|i16|i32|i64|i128|u8|u16|u32|u64|u128|f16|f32|f64|f128)r[0-9]+`

Examples:
- `i32r0`, `i32r1`, `i32r99`
- `f64r0`, `f64r15`
- `u8r0`, `u8r255`

**Question**: Should we enforce maximum register index (e.g., r0-r31)?

### Literals

#### Integer Literals

**Decimal**: `[0-9]+`
- Example: `42`, `0`, `1234567`

**Hexadecimal**: `0x[0-9a-fA-F]+`
- Example: `0xFF`, `0x1A2B`, `0x0`

**Binary**: `0b[01]+`
- Example: `0b1010`, `0b11111111`

**Octal**: `0o[0-7]+`
- Example: `0o755`, `0o17`

**Negative**: `-[0-9]+`
- Example: `-42`, `-1`

#### Floating-Point Literals

**Standard**: `[0-9]+\.[0-9]+`
- Example: `3.14`, `0.5`, `99.99`

**Scientific**: `[0-9]+\.?[0-9]*[eE][+-]?[0-9]+`
- Example: `1.5e10`, `2E-5`, `6.022e23`

**Special values**: TBD - Support `inf`, `nan`?

#### Boolean Literals (PLANNED)

- `true` / `false`
- Case-sensitive? Or allow `TRUE`, `True`, etc.?

#### String Literals (PLANNED)

**Double-quoted**: `"[^"]*"`
- Example: `"Hello, World!"`
- Escape sequences: `\n`, `\t`, `\"`, `\\`

**Single-quoted**: TBD - Support `'text'`?

**Multi-line**: TBD - Support triple-quoted strings?

## Grammar

### Program Structure

```ebnf
program ::= statement*

statement ::= variable_declaration
            | instruction
            | label
            | comment
            | empty_line

empty_line ::= whitespace* newline
```

### Variable Declarations

```ebnf
variable_declaration ::= "$" type ":" identifier "=" literal

type ::= integer_type | float_type | bool_type | string_type

integer_type ::= "i8" | "i16" | "i32" | "i64" | "i128"
               | "u8" | "u16" | "u32" | "u64" | "u128"

float_type ::= "f16" | "f32" | "f64" | "f128"

bool_type ::= "bool"

string_type ::= "str"

literal ::= integer_literal | float_literal | bool_literal | string_literal
```

**Examples**:
```zcyasm
$i32 : counter = 0
$f64 : pi = 3.14159
$bool : is_active = true    # PLANNED
$str : message = "Hello"    # PLANNED
```

**Question**: Should we support array declarations?
```zcyasm
$[]i32 : numbers = {1, 2, 3, 4, 5}  # PLANNED?
```

### Labels

```ebnf
label ::= identifier ":"
```

**Examples**:
```zcyasm
main:
loop_start:
done:
```

**Naming conventions** (recommended):
- `snake_case` for multi-word labels
- Descriptive names (`loop_start` not `l1`)

### Instructions

```ebnf
instruction ::= "." opcode ":" operand_list

operand_list ::= operand ("," whitespace* operand)*

operand ::= register | identifier | literal

register ::= type "r" index

index ::= [0-9]+
```

**Instruction format**:
```
.<opcode>: <operand1>, <operand2>, ...
```

**Examples**:
```zcyasm
.ldi: i32r0, 42
.ldd: i32r1, counter
.add: i32r0, i32r1
.jmp: loop_start
```

### Operand Types by Instruction

Different instructions accept different operand types:

| Instruction | Operand 1 | Operand 2 | Operand 3 |
|-------------|-----------|-----------|-----------|
| `ldd` | register (dest) | variable | - |
| `ldi` | register (dest) | literal | - |
| `mov` | register (dest) | register (src) | - |
| `std` | variable | register (src) | - |
| `add` | register (dest) | register (src) | - |
| `sub` | register (dest) | register (src) | - |
| `mul` | register (dest) | register (src) | - |
| `div` | register (dest) | register (src) | - |
| `jmp` | label | - | - |
| `jeq` | label | - | - |
| `call` | label | - | - |

**Question**: Should we support three-operand instructions?
```zcyasm
.add: i32r2, i32r0, i32r1  # r2 = r0 + r1 (not modifying r0)
```

## Semantic Rules

### Type Checking

1. **Register-variable type match**: In `ldd`/`std`, register type must match variable type
   ```zcyasm
   $i32 : x = 5
   .ldd: i32r0, x   # OK
   .ldd: f64r0, x   # ERROR: type mismatch
   ```

2. **Register-literal type match**: In `ldi`, literal must be compatible with register type
   ```zcyasm
   .ldi: i32r0, 42     # OK
   .ldi: i32r0, 3.14   # ERROR: float literal for int register
   ```

3. **Binary operation type match**: Both operands must be same type
   ```zcyasm
   .add: i32r0, i32r1  # OK
   .add: i32r0, f64r0  # ERROR: type mismatch
   ```

4. **Cast requirements**: Converting between types requires explicit `cast` instruction
   ```zcyasm
   .ldi: i32r0, 42
   .cast: f64r0, i32r0  # Explicit conversion required
   ```

### Register Usage

1. **Register must be loaded before use**: Cannot use uninitialized register
   ```zcyasm
   .add: i32r0, i32r1   # ERROR: r0, r1 not initialized
   ```

2. **Register scope**: Registers are global (visible everywhere)

### Variable Usage

1. **Variable must be declared before use**
   ```zcyasm
   .ldd: i32r0, x      # ERROR: x not declared
   ```

2. **Variable names are unique**: Cannot redeclare
   ```zcyasm
   $i32 : x = 5
   $i32 : x = 10       # ERROR: x already declared
   ```

### Label Usage

1. **Label must be defined before jump**: Forward references TBD
   ```zcyasm
   .jmp: target        # OK if target defined later?
   # ...
   target:
   ```

2. **Label names are unique**
   ```zcyasm
   loop:
   # ...
   loop:               # ERROR: label redefined
   ```

## Syntax Sugar (Proposed)

### Constant Declarations

Use `%` instead of `$` for immutable values:
```zcyasm
%i32 : PI = 3          # Constant, cannot be modified
$i32 : x = 5           # Variable, can be modified
```

### Register Aliases

Allow naming registers for readability:
```zcyasm
.alias: counter, i32r0  # Refer to i32r0 as "counter"
.inc: counter           # Equivalent to .inc: i32r0
```

### Macros (Future)

Define reusable code blocks:
```zcyasm
.macro: SWAP, reg1, reg2
    .push: reg1
    .mov: reg1, reg2
    .pop: reg2
.endmacro

# Usage
.SWAP: i32r0, i32r1
```

## File Structure

### Recommended Organization

```zcyasm
# 1. File header comment
# Program: Fibonacci calculator
# Author: ...
# Description: ...

# 2. Constant declarations
%i32 : MAX_COUNT = 10

# 3. Variable declarations
$i32 : counter = 0
$i32 : result = 0

# 4. Main program
main:
    .ldi: i32r0, 0
    # ... main logic ...
    .call: helper
    .hlt

# 5. Helper functions
helper:
    # ... helper logic ...
    .ret
```

### File Extension

- ZcyASM files use `.zcyasm` extension
- Convention: lowercase with underscores (e.g., `my_program.zcyasm`)

## Formatting Conventions (Style Guide)

### Indentation

- Use 4 spaces (not tabs)
- Indent instruction bodies under labels
- Indent continued operands

```zcyasm
main:
    .ldi: i32r0, 0
    .call: calculate
    .hlt

calculate:
    .ldd: i32r0, value
    .ret
```

### Spacing

- Space after instruction opcode and colon: `.ldi: `
- Space after commas: `.add: i32r0, i32r1`
- Blank line between logical sections

### Comments

- Comment complex logic
- Explain non-obvious operations
- Document function parameters and return values

```zcyasm
# Calculate factorial of n
# Input: i32r0 (n)
# Output: i32r0 (result)
# Modifies: i32r1 (temporary)
factorial:
    .ldd: i32r1, one
    .cmp: i32r0, i32r1
    .jle: base_case
    # ... recursive case ...
```

### Naming

- **Variables**: `snake_case` (e.g., `my_variable`, `loop_count`)
- **Labels**: `snake_case` (e.g., `main`, `loop_start`, `done`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `MAX_VALUE`, `PI`) - if we add constants

## Error Messages (For Implementors)

Good error messages should include:
1. Line number
2. Column number (if possible)
3. Error description
4. Suggestion for fix

**Example**:
```
error: type mismatch at line 15, column 12
  .ldd: f64r0, x
           ^^
  Expected f64 variable, but 'x' has type i32
  Suggestion: Use .cast instruction or change register type to i32r0
```

## Formal Grammar (EBNF)

```ebnf
(* ZcyASM Formal Grammar *)

program = { statement } ;

statement = variable_decl
          | instruction
          | label
          | comment ;

(* Variable declarations *)
variable_decl = "$" , type , ":" , identifier , "=" , literal ;

type = int_type | float_type | bool_type | str_type ;

int_type = "i8" | "i16" | "i32" | "i64" | "i128"
         | "u8" | "u16" | "u32" | "u64" | "u128" ;

float_type = "f16" | "f32" | "f64" | "f128" ;

bool_type = "bool" ;

str_type = "str" ;

(* Instructions *)
instruction = "." , opcode , ":" , operand_list ;

opcode = "ldd" | "ldi" | "mov" | "std" | "push" | "pop"
       | "add" | "sub" | "mul" | "div" | "mod" | "neg" | "inc" | "dec"
       | "and" | "or" | "xor" | "not" | "shl" | "shr"
       | "cmp" | "tst"
       | "jmp" | "jeq" | "jne" | "jlt" | "jgt" | "jle" | "jge"
       | "call" | "ret"
       | "print" | "println" | "read"
       | "cast"
       | "nop" | "hlt" | "dbg" ;

operand_list = operand , { "," , operand } ;

operand = register | identifier | literal ;

register = type , "r" , digit , { digit } ;

(* Labels *)
label = identifier , ":" ;

(* Literals *)
literal = int_literal | float_literal | bool_literal | str_literal ;

int_literal = [ "-" ] , ( decimal | hexadecimal | binary | octal ) ;

decimal = digit , { digit } ;

hexadecimal = "0x" , hex_digit , { hex_digit } ;

binary = "0b" , bin_digit , { bin_digit } ;

octal = "0o" , oct_digit , { oct_digit } ;

float_literal = [ "-" ] , digit , { digit } , "." , digit , { digit } , [ exponent ] ;

exponent = ( "e" | "E" ) , [ "+" | "-" ] , digit , { digit } ;

bool_literal = "true" | "false" ;

str_literal = '"' , { char } , '"' ;

(* Comments *)
comment = "#" , { any_char } , newline ;

(* Identifiers *)
identifier = ( letter | "_" ) , { letter | digit | "_" } ;

(* Character classes *)
letter = "a" | "b" | ... | "z" | "A" | "B" | ... | "Z" ;

digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;

hex_digit = digit | "a" | "b" | "c" | "d" | "e" | "f" | "A" | "B" | "C" | "D" | "E" | "F" ;

bin_digit = "0" | "1" ;

oct_digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" ;
```

## Encoding (Future Consideration)

If we want to emit bytecode instead of interpreting text:

### Instruction Encoding

Each instruction could be encoded as:
```
[opcode: 1 byte][operand_count: 1 byte][operand1: N bytes][operand2: N bytes]...
```

### Opcode Table

```
LDD  = 0x01
LDI  = 0x02
MOV  = 0x03
STD  = 0x04
ADD  = 0x10
SUB  = 0x11
MUL  = 0x12
...
```

This would enable faster execution and smaller file sizes.

## Implementation Checklist

For implementors building a ZcyASM parser/interpreter:

- [ ] Lexer (tokenization)
  - [ ] Comments
  - [ ] Keywords
  - [ ] Identifiers
  - [ ] Register names
  - [ ] Literals (int, float, string)
  - [ ] Operators (`:`, `,`, `=`, `$`, `.`)
- [ ] Parser (AST construction)
  - [ ] Variable declarations
  - [ ] Instructions
  - [ ] Labels
  - [ ] Operand validation
- [ ] Semantic analyzer
  - [ ] Type checking
  - [ ] Variable declaration checking
  - [ ] Label resolution
  - [ ] Register initialization checking
- [ ] Interpreter / Code generator
  - [ ] Virtual machine execution
  - [ ] Or bytecode emission
- [ ] Error reporting
  - [ ] Syntax errors
  - [ ] Type errors
  - [ ] Runtime errors
