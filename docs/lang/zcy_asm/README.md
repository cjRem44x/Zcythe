# ZcyASM Documentation

ZcyASM is a procedural scripting language designed to emulate RISC assembly language, inspired by Atmel AVR microcontroller instruction sets. It serves as the low-level compilation target for the Zcythe programming language.

## Documentation Index

### Core Documentation

1. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Architecture Overview
   - Register system (type-specific register files)
   - Memory model (data, stack, heap segments)
   - Execution model
   - Type system
   - Calling conventions (planned)
   - Design decisions and open questions

2. **[INSTRUCTION_SET.md](INSTRUCTION_SET.md)** - Complete ISA Reference
   - All instructions organized by category
   - Syntax and semantics for each instruction
   - Implementation status (implemented/planned)
   - Instruction summary table
   - Implementation priority guide

3. **[SYNTAX.md](SYNTAX.md)** - Language Syntax Specification
   - Lexical structure (comments, identifiers, literals)
   - Grammar (EBNF formal specification)
   - Semantic rules (type checking, scope)
   - Style guide and formatting conventions
   - Error message guidelines

4. **[EXAMPLES.md](EXAMPLES.md)** - Code Examples
   - 15 progressively complex example programs
   - From "Hello World" to recursive functions
   - Demonstrates all major language features
   - Design notes from real-world usage

### Example Code

- **[basics/intro.zcyasm](basics/intro.zcyasm)** - Quick introduction to ZcyASM basics

## Quick Start

### Basic Syntax

**Comments**:
```zcyasm
# This is a comment
```

**Variable Declaration**:
```zcyasm
$i32 : X = 10       # 32-bit signed integer
$f64 : pi = 3.14    # 64-bit float
```

**Instructions**:
```zcyasm
.ldi: i32r0, 42         # Load immediate value 42 into register
.ldd: i32r1, X          # Load variable X into register
.add: i32r0, i32r1      # Add r0 and r1, store in r0
.println: i32r0         # Print result
```

**Labels and Control Flow**:
```zcyasm
loop_start:
    .inc: i32r0         # Increment register
    .cmp: i32r0, i32r1  # Compare registers
    .jlt: loop_start    # Jump if less than
```

## Current Implementation Status

### Implemented ✓
- `ldd` - Load data from variable
- `ldi` - Load immediate value
- `add` - Addition
- Type-specific register files
- Variable storage (data segment)

### Next Priority (Phase 1)
- `mov` - Register to register move
- `std` - Store data to variable
- `sub`, `mul`, `div`, `mod` - Complete arithmetic
- `print`, `println` - Output operations

### Planned (Phase 2+)
- Control flow (labels, jumps, comparisons)
- Function calls (call, ret, push, pop)
- Logical operations (and, or, xor, not, shifts)
- Type conversion (cast)
- I/O operations (read input)

See [INSTRUCTION_SET.md](INSTRUCTION_SET.md) for complete implementation roadmap.

## Design Philosophy

### Type-Specific Registers
Unlike traditional RISC with general-purpose registers, ZcyASM uses type-specialized register files:
- Enforces type safety at register level
- No runtime type checking overhead
- Makes assembly code more readable

### Explicit Types
All operations are explicitly typed:
```zcyasm
.add: i32r0, i32r1  # 32-bit integer addition
.add: f64r0, f64r1  # 64-bit float addition
```

### RISC Principles
- Load/store architecture
- Simple, orthogonal instruction set
- Fixed instruction format
- Register-based computation

### Inspiration from Atmel AVR
- Instruction syntax (`.opcode:` format)
- Mnemonic naming (ldd, ldi, std)
- Type-prefixed registers

## Key Design Decisions

These are critical decisions that need to be finalized:

### 1. Register Count
- **Fixed** (e.g., 32 registers per type) - Traditional approach
- **Virtual** (unlimited) - Simplified compiler
- **Configurable** - Via compile flags

Current: TBD

### 2. Memory Addressing
- How to address memory locations?
- Pointer support?
- Array indexing mechanism?

Current: Data segment only (variables via names)

### 3. Function Calling Convention
- Which registers for arguments?
- Which register for return value?
- Caller-saved vs callee-saved registers?
- Stack frame structure?

Current: PLANNED - not yet designed

### 4. Entry Point
- Start at first instruction?
- Require `main:` label?
- Explicit entry directive?

Current: TBD

### 5. String Representation
- Null-terminated arrays?
- Length-prefixed?
- Fat pointers (ptr + length)?

Current: PLANNED - not yet implemented

See [ARCHITECTURE.md](ARCHITECTURE.md#design-decisions-needed) for complete list.

## Architecture Highlights

### Register Files

Each type has its own register file:
- Signed integers: `i8r0...i8rN`, `i16r0...i16rN`, `i32r0...i32rN`, `i64r0...i64rN`, `i128r0...i128rN`
- Unsigned integers: `u8r0...u8rN`, `u16r0...u16rN`, `u32r0...u32rN`, `u64r0...u64rN`, `u128r0...u128rN`
- Floating-point: `f16r0...f16rN`, `f32r0...f32rN`, `f64r0...f64rN`, `f128r0...f128rN`

### Memory Segments

**Data Segment** (Implemented):
- Global variables
- Declared with `$` prefix
- Static allocation

**Stack Segment** (Planned):
- Local variables
- Function call frames
- Return addresses

**Heap Segment** (Future):
- Dynamic allocation

### Type System

Inherits Zig's primitive types:
- Signed: i8, i16, i32, i64, i128
- Unsigned: u8, u16, u32, u64, u128
- Float: f16, f32, f64, f128
- Bool: TBD
- String: TBD

## Example Program

```zcyasm
# Calculate factorial of 5
$i32 : n = 5
$i32 : result = 1

.ldd: i32r0, n          # Load n
.ldi: i32r1, 1          # result = 1

factorial_loop:
    .mul: i32r1, i32r0  # result *= n
    .dec: i32r0         # n--
    .ldi: i32r2, 1
    .cmp: i32r0, i32r2  # n > 1?
    .jgt: factorial_loop

.std: result, i32r1     # Store result
.println: i32r1         # Print: 120
.hlt
```

## Contributing to Documentation

When adding to these docs:

1. **Mark implementation status**:
   - ✓ IMPLEMENTED
   - PLANNED
   - FUTURE
   - TBD (design decision needed)

2. **Include examples** for all new instructions

3. **Update multiple docs** when adding features:
   - Add instruction to INSTRUCTION_SET.md
   - Add grammar rules to SYNTAX.md
   - Add example to EXAMPLES.md
   - Update ARCHITECTURE.md if architectural change

4. **Raise design questions** clearly:
   - Mark as **[TBD]**
   - List options
   - Note tradeoffs

## Implementation Guide

For building a ZcyASM interpreter:

1. **Lexer** - Tokenize source code
   - See SYNTAX.md for token definitions

2. **Parser** - Build AST
   - See SYNTAX.md for grammar

3. **Semantic Analysis** - Type checking
   - See SYNTAX.md for semantic rules

4. **Interpreter** - Execute instructions
   - See INSTRUCTION_SET.md for instruction semantics
   - See ARCHITECTURE.md for register/memory model

5. **Error Reporting** - Clear error messages
   - See SYNTAX.md for error message guidelines

## Next Steps

### For Language Design
1. Review design decisions in ARCHITECTURE.md
2. Finalize calling convention
3. Design memory addressing model
4. Specify string representation

### For Implementation
1. Implement Phase 1 instructions (see INSTRUCTION_SET.md)
2. Add print/println for testing
3. Build simple interpreter
4. Test with examples from EXAMPLES.md

### For Documentation
1. Add more examples as features are implemented
2. Document implementation details
3. Create tutorials for common patterns
4. Add troubleshooting guide

## Resources

- **Main project**: [Zcythe](../../..)
- **Zig language**: https://ziglang.org/
- **RISC principles**: (reference links TBD)
- **Atmel AVR instruction set**: (reference links TBD)

## Questions or Feedback?

This is a living specification. If you find ambiguities, errors, or have suggestions:
- Open an issue
- Submit a pull request
- Start a discussion

The goal is to create a clear, consistent, and implementable assembly language that serves as a solid foundation for Zcythe.
