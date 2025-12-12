# ZcyASM Architecture Specification

> **⚠️ PROTOTYPE PHASE**: This specification is subject to change. No official versions released.

ZcyASM is a procedural scripting language designed to emulate RISC assembly language principles, inspired by Atmel AVR microcontroller instruction sets. It serves as the low-level compilation target for the Zcythe programming language.

## Design Philosophy

- **Type-specific registers**: Unlike traditional RISC architectures with uniform general-purpose registers, ZcyASM uses type-specialized register files
- **Explicit types**: All operations are explicitly typed (no type coercion at assembly level)
- **Simple instruction set**: Minimal, orthogonal instruction set inspired by RISC principles
- **Readable syntax**: Assembly code should be human-readable with clear type information
- **Practical scripting**: Higher-level built-ins for common operations (I/O, formatting) since this is a scripting language, not raw hardware ASM
- **Escape the metal**: Convenience features that would be syscalls or library code in real ASM are built-in instructions here

## Register Architecture

### Register Files

ZcyASM organizes registers into type-specific files rather than having a unified register file. Each type has its own set of registers:

#### Signed Integer Registers
- `i8r0` - `i8rN`: 8-bit signed integer registers
- `i16r0` - `i16rN`: 16-bit signed integer registers
- `i32r0` - `i32rN`: 32-bit signed integer registers
- `i64r0` - `i64rN`: 64-bit signed integer registers
- `i128r0` - `i128rN`: 128-bit signed integer registers

#### Unsigned Integer Registers
- `u8r0` - `u8rN`: 8-bit unsigned integer registers
- `u16r0` - `u16rN`: 16-bit unsigned integer registers
- `u32r0` - `u32rN`: 32-bit unsigned integer registers
- `u64r0` - `u64rN`: 64-bit unsigned integer registers
- `u128r0` - `u128rN`: 128-bit unsigned integer registers

#### Floating-Point Registers
- `f16r0` - `f16rN`: 16-bit float registers
- `f32r0` - `f32rN`: 32-bit float registers
- `f64r0` - `f64rN`: 64-bit float registers
- `f128r0` - `f128rN`: 128-bit float registers

### Register Naming Convention

Format: `<type>r<index>`
- `<type>`: The data type (i8, i16, i32, i64, i128, u8, u16, u32, u64, u128, f16, f32, f64, f128)
- `r`: Literal character 'r' (for "register")
- `<index>`: Zero-based register index

Examples:
- `i32r0` - 32-bit signed integer register 0
- `f64r5` - 64-bit float register 5
- `u8r12` - 8-bit unsigned integer register 12

### Register Count

**Current Status**: TBD - needs design decision

Options:
1. **Fixed count** (e.g., 32 registers per type) - Traditional RISC approach
2. **Virtual registers** (unlimited) - Simplified register allocation for compiler
3. **Configurable** - Set via configuration or compile flags

**Question for consideration**: How many registers per type should we support?

## Memory Model

**Current Status**: PLANNED - Not yet implemented

### Proposed Memory Segments

1. **Register Space**
   - Type-specific register files (as described above)
   - Fastest access, no addressing required

2. **Data Segment** (Static Storage)
   - Global variables declared with `$` prefix
   - Allocated at program start
   - Persistent throughout execution
   - Example: `$i32 : X = 4`

3. **Stack Segment** (PLANNED)
   - Local variables
   - Function call frames
   - Return addresses
   - Grows downward from high memory

4. **Heap Segment** (FUTURE)
   - Dynamic allocation
   - Managed by runtime

### Memory Addressing (PLANNED)

TBD - Design needed for:
- How to address memory locations
- Load/store instructions for memory access
- Pointer support
- Array indexing

## Data Types

### Primitive Types

ZcyASM inherits Zig's primitive type system:

**Signed Integers**: `i8`, `i16`, `i32`, `i64`, `i128`
**Unsigned Integers**: `u8`, `u16`, `u32`, `u64`, `u128`
**Floating-Point**: `f16`, `f32`, `f64`, `f128`
**Boolean**: `bool` (TBD - representation as u8 or dedicated type?)

### Complex Types (PLANNED)

**Strings**
- Representation: TBD
- Options:
  - Null-terminated byte arrays `[]u8` with null terminator
  - Length-prefixed: `[4 bytes length][data bytes]`
  - Fat pointer: `struct { ptr: *u8, len: usize }`

**Arrays**
- Fixed-size arrays
- Element access
- Bounds checking (runtime or compile-time?)

**Tuples** (FUTURE)
- Heterogeneous fixed-size collections
- Stack-allocated structures

## Execution Model

### Program Structure

A ZcyASM program consists of:

1. **Data Section** (optional)
   - Variable declarations: `$<type> : <name> = <value>`
   - String literals (PLANNED)
   - Constant definitions (PLANNED)

2. **Code Section**
   - Instructions prefixed with `.`
   - Executed sequentially unless branching
   - Entry point: TBD (first instruction? labeled `main:`?)

### Instruction Execution

- Sequential execution (program counter increments)
- Branch instructions modify program counter
- No pipelining or out-of-order execution (interpreter model)

### Control Flow (PLANNED)

TBD - Needs design for:
- Labels: `label_name:`?
- Jump instructions: `.jmp`, `.jeq`, `.jne`, etc.
- Conditional execution
- Function calls and returns

## Calling Convention (PLANNED)

**Critical design decision needed**: How do functions work in ZcyASM?

### Questions to Answer:

1. **Function Definition**
   - Syntax: `func_name:` label?
   - Entry/exit instructions?

2. **Parameter Passing**
   - Which registers for arguments?
   - Convention: First N args in specific registers, rest on stack?
   - Mixed types - how to handle?

3. **Return Values**
   - Which register(s) for return value?
   - Type-specific return registers?

4. **Register Preservation**
   - Caller-saved vs callee-saved registers
   - Which registers must be preserved across calls?

5. **Stack Management**
   - Stack pointer register?
   - Frame pointer?
   - Stack frame structure?

### Proposed Simple Convention (Draft)

```
Arguments: Pass in r0, r1, r2, r3 of appropriate type
Return: r0 of appropriate type
Preserved: All registers except r0-r3 must be saved by callee
Stack: Not yet defined
```

## Type Safety

ZcyASM enforces type safety at the instruction level:

- **No implicit conversions**: Must use explicit cast instructions
- **Type checking**: Operations validate register types match
- **Runtime checks**: TBD - bounds checking, overflow detection?

## Comparison with Traditional RISC

### Similarities to RISC
- Load/store architecture (separate data movement from computation)
- Simple, fixed-format instructions
- Orthogonal instruction set
- Register-based computation

### Differences from RISC
- Type-specific register files instead of general-purpose registers
- Explicit type information in all operations
- Higher-level abstractions (typed registers vs raw bits)
- Designed for VM interpretation rather than hardware implementation
- Built-in I/O and string operations (what would be syscalls/libraries in real ASM)
- Convenience instructions for common tasks (formatting, conversions, etc.)

## Implementation Notes

### Current Implementation (zcy_asm_core.zig)

The virtual machine maintains:
- Separate ArrayLists for each register type
- Variable storage for data segment
- Instruction execution loop

### Performance Considerations

- Interpreted execution (not JIT or compiled)
- Type-specific registers may reduce runtime type checking
- Future optimization: JIT compilation to native code

## Design Decisions Needed

Mark decisions as **[DECIDED]**, **[PROPOSED]**, or **[TBD]**

1. **[TBD]** Register count per type (fixed vs unlimited)
2. **[TBD]** Memory addressing model
3. **[TBD]** String representation
4. **[TBD]** Function calling convention
5. **[TBD]** Control flow label syntax
6. **[TBD]** Entry point specification
7. **[TBD]** Boolean representation (dedicated type or u8)
8. **[TBD]** Error handling mechanism (exceptions? error codes?)
9. **[TBD]** I/O instructions (print, read, file ops)
10. **[TBD]** Debugging support (breakpoints, inspection)

## Future Extensions

Ideas for future consideration:

- **SIMD operations**: Vector registers and operations
- **Atomic operations**: For concurrent programming
- **Inline assembly**: Allow Zig code inline
- **JIT compilation**: Translate to native machine code at runtime
- **Debugging protocol**: GDB-like debugging interface
