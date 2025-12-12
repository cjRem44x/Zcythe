# ZcyASM Instruction Set Reference

> **⚠️ PROTOTYPE PHASE**: Instruction set is evolving. Subject to breaking changes.

This document specifies the complete instruction set for ZcyASM. Instructions are categorized by function and include syntax, semantics, and examples.

## Instruction Format

All instructions follow this format:

```
.<opcode>: <operand1>, <operand2>, ...
```

- Instructions begin with `.` (period)
- Opcode follows immediately (lowercase)
- Operands separated by commas
- Type information embedded in register names

## Instruction Categories

- [Data Movement](#data-movement)
- [Arithmetic](#arithmetic)
- [Logical](#logical)
- [Comparison](#comparison)
- [Control Flow](#control-flow)
- [Function Calls](#function-calls)
- [I/O Operations](#io-operations)
- [Type Conversion](#type-conversion)

---

## Data Movement

### LDD - Load Data
**Status**: IMPLEMENTED ✓

Load a variable's value into a register.

**Syntax**: `.ldd: <dest_reg>, <variable>`

**Operands**:
- `dest_reg`: Destination register
- `variable`: Variable name (from data segment)

**Types**: Register type must match variable type

**Example**:
```zcyasm
$i32 : X = 10
.ldd: i32r0, X      # i32r0 = 10
```

**Implementation**: zcy_asm_core.zig - loads from variable storage into register

---

### LDI - Load Immediate
**Status**: IMPLEMENTED ✓

Load a literal value into a register.

**Syntax**: `.ldi: <dest_reg>, <immediate>`

**Operands**:
- `dest_reg`: Destination register
- `immediate`: Literal value

**Types**: Immediate value must match register type

**Example**:
```zcyasm
.ldi: i32r1, 42     # i32r1 = 42
.ldi: f64r0, 3.14   # f64r0 = 3.14
```

---

### MOV - Move Register to Register
**Status**: PLANNED

Copy value from one register to another.

**Syntax**: `.mov: <dest_reg>, <src_reg>`

**Operands**:
- `dest_reg`: Destination register
- `src_reg`: Source register

**Types**: Both registers must be same type

**Example**:
```zcyasm
.ldi: i32r0, 5
.mov: i32r1, i32r0  # i32r1 = i32r0 = 5
```

---

### STD - Store Data
**Status**: PLANNED

Store a register's value to a variable.

**Syntax**: `.std: <variable>, <src_reg>`

**Operands**:
- `variable`: Variable name (from data segment)
- `src_reg`: Source register

**Types**: Register type must match variable type

**Example**:
```zcyasm
$i32 : result = 0
.ldi: i32r0, 99
.std: result, i32r0  # result = 99
```

---

### PUSH - Push to Stack
**Status**: PLANNED (requires stack implementation)

Push register value onto stack.

**Syntax**: `.push: <src_reg>`

**Example**:
```zcyasm
.ldi: i32r0, 42
.push: i32r0        # Stack grows
```

---

### POP - Pop from Stack
**Status**: PLANNED (requires stack implementation)

Pop value from stack into register.

**Syntax**: `.pop: <dest_reg>`

**Example**:
```zcyasm
.pop: i32r0         # i32r0 = top of stack
```

---

## Arithmetic

### ADD - Addition
**Status**: IMPLEMENTED ✓

Add two registers, store result in destination.

**Syntax**: `.add: <dest_reg>, <src_reg>`

**Operands**:
- `dest_reg`: Destination register (also first operand)
- `src_reg`: Source register (second operand)

**Operation**: `dest_reg = dest_reg + src_reg`

**Types**: Both registers must be same type

**Example**:
```zcyasm
.ldi: i32r0, 10
.ldi: i32r1, 5
.add: i32r0, i32r1  # i32r0 = 10 + 5 = 15
```

---

### SUB - Subtraction
**Status**: PLANNED

Subtract second register from first, store result in destination.

**Syntax**: `.sub: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg - src_reg`

**Types**: Both registers must be same type

**Example**:
```zcyasm
.ldi: i32r0, 10
.ldi: i32r1, 3
.sub: i32r0, i32r1  # i32r0 = 10 - 3 = 7
```

---

### MUL - Multiplication
**Status**: PLANNED

Multiply two registers, store result in destination.

**Syntax**: `.mul: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg * src_reg`

**Types**: Both registers must be same type

**Example**:
```zcyasm
.ldi: i32r0, 7
.ldi: i32r1, 6
.mul: i32r0, i32r1  # i32r0 = 7 * 6 = 42
```

---

### DIV - Division
**Status**: PLANNED

Divide first register by second, store result in destination.

**Syntax**: `.div: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg / src_reg`

**Types**: Both registers must be same type

**Notes**:
- Integer division truncates
- Division by zero behavior: TBD (trap? return 0?)

**Example**:
```zcyasm
.ldi: i32r0, 20
.ldi: i32r1, 4
.div: i32r0, i32r1  # i32r0 = 20 / 4 = 5
```

---

### MOD - Modulo
**Status**: PLANNED

Compute remainder of division, store result in destination.

**Syntax**: `.mod: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg % src_reg`

**Types**: Integer types only

**Example**:
```zcyasm
.ldi: i32r0, 17
.ldi: i32r1, 5
.mod: i32r0, i32r1  # i32r0 = 17 % 5 = 2
```

---

### NEG - Negate
**Status**: PLANNED

Negate register value (two's complement).

**Syntax**: `.neg: <reg>`

**Operation**: `reg = -reg`

**Types**: Signed types only

**Example**:
```zcyasm
.ldi: i32r0, 42
.neg: i32r0         # i32r0 = -42
```

---

### INC - Increment
**Status**: PLANNED

Increment register by 1.

**Syntax**: `.inc: <reg>`

**Operation**: `reg = reg + 1`

**Example**:
```zcyasm
.ldi: i32r0, 9
.inc: i32r0         # i32r0 = 10
```

---

### DEC - Decrement
**Status**: PLANNED

Decrement register by 1.

**Syntax**: `.dec: <reg>`

**Operation**: `reg = reg - 1`

**Example**:
```zcyasm
.ldi: i32r0, 10
.dec: i32r0         # i32r0 = 9
```

---

## Logical

### AND - Bitwise AND
**Status**: PLANNED

Perform bitwise AND.

**Syntax**: `.and: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg & src_reg`

**Types**: Integer types only

**Example**:
```zcyasm
.ldi: u8r0, 0b11110000
.ldi: u8r1, 0b10101010
.and: u8r0, u8r1    # u8r0 = 0b10100000
```

---

### OR - Bitwise OR
**Status**: PLANNED

Perform bitwise OR.

**Syntax**: `.or: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg | src_reg`

**Types**: Integer types only

---

### XOR - Bitwise XOR
**Status**: PLANNED

Perform bitwise XOR.

**Syntax**: `.xor: <dest_reg>, <src_reg>`

**Operation**: `dest_reg = dest_reg ^ src_reg`

**Types**: Integer types only

---

### NOT - Bitwise NOT
**Status**: PLANNED

Perform bitwise NOT (one's complement).

**Syntax**: `.not: <reg>`

**Operation**: `reg = ~reg`

**Types**: Integer types only

---

### SHL - Shift Left
**Status**: PLANNED

Shift bits left.

**Syntax**: `.shl: <dest_reg>, <shift_amount>`

**Operation**: `dest_reg = dest_reg << shift_amount`

**Types**: Integer types only

**Example**:
```zcyasm
.ldi: u8r0, 0b00001111
.ldi: u8r1, 2
.shl: u8r0, u8r1    # u8r0 = 0b00111100
```

---

### SHR - Shift Right
**Status**: PLANNED

Shift bits right (logical shift for unsigned, arithmetic shift for signed).

**Syntax**: `.shr: <dest_reg>, <shift_amount>`

**Operation**: `dest_reg = dest_reg >> shift_amount`

**Types**: Integer types only

---

## Comparison

All comparison instructions set flags for conditional branching.

**Question**: Should we have:
1. Implicit flag register (like x86)?
2. Explicit boolean result register?
3. Status register visible to programmer?

### CMP - Compare
**Status**: PLANNED

Compare two registers, set flags.

**Syntax**: `.cmp: <reg1>, <reg2>`

**Operation**: Sets flags based on `reg1 - reg2`
- Zero flag: reg1 == reg2
- Negative flag: reg1 < reg2
- etc.

**Example**:
```zcyasm
.ldi: i32r0, 5
.ldi: i32r1, 10
.cmp: i32r0, i32r1  # Sets flags (negative)
```

---

### TST - Test (AND without storing)
**Status**: PLANNED

Perform bitwise AND and set flags without storing result.

**Syntax**: `.tst: <reg1>, <reg2>`

---

## Control Flow

### Labels
**Status**: PLANNED

**Syntax**: `label_name:`

**Example**:
```zcyasm
loop_start:
    .inc: i32r0
    .jmp: loop_start
```

---

### JMP - Unconditional Jump
**Status**: PLANNED

Jump to label unconditionally.

**Syntax**: `.jmp: <label>`

---

### JEQ / JZ - Jump if Equal / Zero
**Status**: PLANNED

Jump if last comparison was equal (zero flag set).

**Syntax**: `.jeq: <label>`

---

### JNE / JNZ - Jump if Not Equal / Not Zero
**Status**: PLANNED

Jump if last comparison was not equal (zero flag clear).

**Syntax**: `.jne: <label>`

---

### JLT - Jump if Less Than
**Status**: PLANNED

Jump if first operand < second operand.

**Syntax**: `.jlt: <label>`

---

### JGT - Jump if Greater Than
**Status**: PLANNED

Jump if first operand > second operand.

**Syntax**: `.jgt: <label>`

---

### JLE - Jump if Less Than or Equal
**Status**: PLANNED

**Syntax**: `.jle: <label>`

---

### JGE - Jump if Greater Than or Equal
**Status**: PLANNED

**Syntax**: `.jge: <label>`

---

## Function Calls

### CALL - Call Function
**Status**: PLANNED

Call a function at label, saving return address.

**Syntax**: `.call: <label>`

**Operation**:
1. Push return address onto stack
2. Jump to label

---

### RET - Return from Function
**Status**: PLANNED

Return from function to caller.

**Syntax**: `.ret`

**Operation**:
1. Pop return address from stack
2. Jump to return address

---

## I/O Operations

ZcyASM includes higher-level I/O built-ins since it's a scripting language, not raw hardware assembly. These would be syscalls or library functions in traditional ASM.

### STROUT - String Output
**Status**: PLANNED

Print a string literal with escape sequence support.

**Syntax**: `.strout: "<string>"`

**Escape Sequences**:
- `\n` - newline
- `\t` - tab
- `\\` - backslash
- `\"` - double quote
- `\r` - carriage return
- `\0` - null character

**Example**:
```zcyasm
.strout: "Hello, World!\n"
.strout: "Line 1\nLine 2\n"
.strout: "Tab\tseparated\tvalues\n"
.strout: "Quote: \"text\"\n"
```

**Notes**:
- Does NOT add automatic newline (unlike println)
- Supports full escape sequence processing
- String is not stored in data segment, embedded in instruction

---

### FOUT - Formatted Output
**Status**: PLANNED

Print formatted output with variables, similar to printf.

**Syntax**: `.fout: <reg>, "<format_spec>"`

**Format Specifiers**:
- `%d` - signed decimal integer
- `%u` - unsigned decimal integer
- `%f` - floating-point
- `%x` - hexadecimal (lowercase)
- `%X` - hexadecimal (uppercase)
- `%b` - binary
- `%o` - octal
- `%c` - character (from u8)
- `%s` - string (FUTURE - when strings implemented)
- `%%` - literal percent sign

**Precision/Width** (optional):
- `%5d` - minimum width 5
- `%.2f` - 2 decimal places
- `%8.3f` - width 8, 3 decimal places

**Example**:
```zcyasm
.ldi: i32r0, 42
.fout: i32r0, "The answer is: %d\n"          # Output: The answer is: 42

.ldi: i32r1, 255
.fout: i32r1, "Hex: %x, Binary: %b\n"        # Output: Hex: ff, Binary: 11111111

.ldi: f64r0, 3.14159
.fout: f64r0, "Pi: %.2f\n"                   # Output: Pi: 3.14

.ldi: i32r2, 10
.fout: i32r2, "Width: %5d end\n"             # Output: Width:    10 end
```

**Multi-argument** (FUTURE):
```zcyasm
# Possible future syntax for multiple values:
.fout: "x=%d, y=%d\n", i32r0, i32r1
```

**Notes**:
- Format string supports escape sequences
- Type of register must match format specifier
- Invalid format specifier = error

---

### PRINT - Print Value
**Status**: PLANNED

Print register value to stdout (simple, no formatting).

**Syntax**: `.print: <reg>`

**Example**:
```zcyasm
.ldi: i32r0, 42
.print: i32r0       # Output: 42
```

**Notes**: No newline added, no formatting applied

---

### PRINTLN - Print with Newline
**Status**: PLANNED

Print register value followed by newline.

**Syntax**: `.println: <reg>`

**Example**:
```zcyasm
.ldi: i32r0, 42
.println: i32r0     # Output: 42\n
```

---

### STRIN - String Input
**Status**: PLANNED

Read a line of text from stdin into a string variable.

**Syntax**: `.strin: <str_var>`

**Example**:
```zcyasm
$str : user_input = ""
.strout: "Enter your name: "
.strin: user_input
.strout: "Hello, "
# ... print user_input
```

**Notes**: Reads until newline, stores in string variable

---

### READ - Read Numeric Input
**Status**: PLANNED

Read numeric value from stdin into register.

**Syntax**: `.read: <reg>`

**Example**:
```zcyasm
.strout: "Enter a number: "
.read: i32r0        # User types: 42
.println: i32r0     # Echo: 42
```

**Notes**:
- Parses based on register type (int vs float)
- Invalid input behavior: TBD (error? zero? retry?)

---

### FREAD - Formatted Read (scanf-like)
**Status**: FUTURE

Read formatted input from stdin.

**Syntax**: `.fread: "<format>", <reg>`

**Example**:
```zcyasm
.strout: "Enter x and y: "
.fread: "%d %d", i32r0, i32r1    # User types: 10 20
```

---

## Type Conversion

### CAST - Type Cast
**Status**: PLANNED

Convert between types.

**Syntax**: `.cast: <dest_reg>, <src_reg>`

**Example**:
```zcyasm
.ldi: i32r0, 42
.cast: f64r0, i32r0  # f64r0 = 42.0
```

**Notes**: May need separate instructions for each conversion type (i32tof64, f64toi32, etc.)

---

## System

### NOP - No Operation
**Status**: PLANNED

Do nothing (useful for alignment, timing, debugging).

**Syntax**: `.nop`

---

### HLT - Halt
**Status**: PLANNED

Stop program execution.

**Syntax**: `.hlt`

---

### DBG - Debug Breakpoint
**Status**: PLANNED

Trigger debugger breakpoint.

**Syntax**: `.dbg`

---

## Instruction Summary Table

| Opcode | Operands | Status | Category |
|--------|----------|--------|----------|
| `ldd` | dest_reg, var | IMPLEMENTED | Data Movement |
| `ldi` | dest_reg, imm | IMPLEMENTED | Data Movement |
| `mov` | dest_reg, src_reg | PLANNED | Data Movement |
| `std` | var, src_reg | PLANNED | Data Movement |
| `push` | src_reg | PLANNED | Data Movement |
| `pop` | dest_reg | PLANNED | Data Movement |
| `add` | dest_reg, src_reg | IMPLEMENTED | Arithmetic |
| `sub` | dest_reg, src_reg | PLANNED | Arithmetic |
| `mul` | dest_reg, src_reg | PLANNED | Arithmetic |
| `div` | dest_reg, src_reg | PLANNED | Arithmetic |
| `mod` | dest_reg, src_reg | PLANNED | Arithmetic |
| `neg` | reg | PLANNED | Arithmetic |
| `inc` | reg | PLANNED | Arithmetic |
| `dec` | reg | PLANNED | Arithmetic |
| `and` | dest_reg, src_reg | PLANNED | Logical |
| `or` | dest_reg, src_reg | PLANNED | Logical |
| `xor` | dest_reg, src_reg | PLANNED | Logical |
| `not` | reg | PLANNED | Logical |
| `shl` | dest_reg, amount | PLANNED | Logical |
| `shr` | dest_reg, amount | PLANNED | Logical |
| `cmp` | reg1, reg2 | PLANNED | Comparison |
| `tst` | reg1, reg2 | PLANNED | Comparison |
| `jmp` | label | PLANNED | Control Flow |
| `jeq` | label | PLANNED | Control Flow |
| `jne` | label | PLANNED | Control Flow |
| `jlt` | label | PLANNED | Control Flow |
| `jgt` | label | PLANNED | Control Flow |
| `jle` | label | PLANNED | Control Flow |
| `jge` | label | PLANNED | Control Flow |
| `call` | label | PLANNED | Functions |
| `ret` | - | PLANNED | Functions |
| `strout` | string_literal | PLANNED | I/O |
| `fout` | reg, format_str | PLANNED | I/O |
| `print` | reg | PLANNED | I/O |
| `println` | reg | PLANNED | I/O |
| `strin` | str_var | PLANNED | I/O |
| `read` | reg | PLANNED | I/O |
| `fread` | format_str, regs | FUTURE | I/O |
| `cast` | dest_reg, src_reg | PLANNED | Type Conversion |
| `nop` | - | PLANNED | System |
| `hlt` | - | PLANNED | System |
| `dbg` | - | PLANNED | System |

---

## Implementation Priority

Suggested order for implementation:

**Phase 1: Basic Arithmetic** (MVP)
1. `mov`, `std` (complete data movement)
2. `sub`, `mul`, `div`, `mod` (complete arithmetic)
3. `strout`, `fout` (higher-level output - more practical than print/println)
4. `print`, `println` (simple output)

**Phase 2: Control Flow**
4. Labels
5. `cmp`
6. `jmp`, `jeq`, `jne`, `jlt`, `jgt`

**Phase 3: Functions**
7. Stack implementation
8. `call`, `ret`
9. `push`, `pop`

**Phase 4: Advanced**
10. Logical operations
11. Type conversion
12. Input operations
13. System operations
