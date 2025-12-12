# Zcythe

> **⚠️ PROTOTYPE PHASE**: This project is in early development. No official versions have been released. The API and language syntax are subject to change. Contributions and feedback are welcome!

A modern programming language powered by Zig, featuring a high-level source language (Zcythe) that compiles to a custom RISC-like assembly language (ZcyASM).

## Overview

Zcythe is an experimental programming language project consisting of two core components:

1. **Zcythe** - A high-level, expressive source language with clean syntax
2. **ZcyASM** - A procedural assembly language inspired by RISC principles and Atmel AVR microcode

### Philosophy

- **Type-safe by design**: Type-specific register architecture prevents type confusion
- **As low-level as possible, as high-level as necessary**: RISC core with quality-of-life features
- **Practical scripting**: Higher-level built-ins for I/O and formatting that would be syscalls in traditional assembly
- **Built on Zig**: Leverages Zig's type system and toolchain

## Status

### Current Implementation

**ZcyASM Core** (Phase 1 Complete ✓):
- ✅ Type-specific register files (i8-i128, u8-u128, f16-f128)
- ✅ Data movement instructions (LDD, LDI, MOV, STD)
- ✅ Arithmetic operations (ADD, SUB, MUL, DIV, MOD, INC, DEC)
- ✅ Higher-level I/O (STROUT, FOUT, PRINT, PRINTLN)
- ✅ Comprehensive test suite (100% passing)

**In Development**:
- 🚧 Control flow (labels, jumps, comparisons)
- 🚧 Function calls (CALL, RET, stack management)
- 🚧 Logical operations (AND, OR, XOR, shifts)
- 🚧 Parser/lexer for .zcyasm files
- 🚧 Zcythe source language compiler

## Quick Start

### Prerequisites

- [Zig](https://ziglang.org/) (latest version recommended)
- Git (for cloning the repository)

### Building

```bash
git clone https://github.com/yourusername/Zcythe.git
cd Zcythe/src/main/zig

# Build and run tests
zig build-exe test_asm_phase1.zig
./test_asm_phase1
```

### Example Code

**ZcyASM** (Assembly):
```zcyasm
# Simple arithmetic demonstration
$i32 : a = 10
$i32 : b = 5
$i32 : result = 0

.ldd: i32r0, a          # Load a into register 0
.ldd: i32r1, b          # Load b into register 1
.add: i32r0, i32r1      # r0 = r0 + r1
.std: result, i32r0     # Store result

.fout: i32r0, "Result: {d}\n"
```

**Zcythe** (High-level - planned):
```zcythe
fn add(x: i32, y: i32) -> i32 {
    ret x + y
}

fn main() {
    result := add(10, 5)
    @pl("Result: " + result)
}
```

## Features

### Type-Specific Registers

Unlike traditional RISC architectures with general-purpose registers, ZcyASM uses type-specialized register files:

- **Clarity**: Registers are named by type and index (`i32r0`, `f64r1`, `u8r5`)
- **Safety**: Compile-time type checking prevents type errors
- **Performance**: No runtime type overhead

### Higher-Level Built-ins

ZcyASM includes convenience features that make it feel like a scripting language:

```zcyasm
.strout: "Hello, World!\n"              # String output with escape sequences
.fout: i32r0, "The answer is {d}\n"     # Printf-style formatting
```

These features would require syscalls or library functions in traditional assembly, but are built-in to ZcyASM.

### Comprehensive Type Support

- Signed integers: `i8`, `i16`, `i32`, `i64`, `i128`
- Unsigned integers: `u8`, `u16`, `u32`, `u64`, `u128`
- Floating-point: `f16`, `f32`, `f64`, `f128`

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[ZcyASM Architecture](docs/lang/zcy_asm/ARCHITECTURE.md)** - System design and memory model
- **[Instruction Set Reference](docs/lang/zcy_asm/INSTRUCTION_SET.md)** - Complete ISA documentation
- **[Language Syntax](docs/lang/zcy_asm/SYNTAX.md)** - Formal grammar and style guide
- **[Code Examples](docs/lang/zcy_asm/EXAMPLES.md)** - 15+ example programs
- **[Higher-Level Features](docs/lang/zcy_asm/HIGHER_LEVEL.md)** - QOL built-ins reference
- **[Implementation Status](docs/lang/zcy_asm/IMPLEMENTATION_STATUS.md)** - Current progress

### Language Examples

See `docs/lang/` for example code:
- **Zcythe examples**: `docs/lang/*.zcy`
- **ZcyASM examples**: `docs/lang/zcy_asm/basics/*.zcyasm`

## Project Structure

```
Zcythe/
├── src/main/zig/           # Zig implementation
│   ├── src/
│   │   ├── main.zig        # CLI entry point
│   │   ├── zcy_asm_core.zig    # ZcyASM virtual machine
│   │   ├── util.zig        # Utility library
│   │   └── file_reader.zig # File I/O
│   ├── test_asm_phase1.zig # Phase 1 test suite
│   └── build.zig           # Build configuration
├── docs/lang/              # Language documentation
│   ├── zcy_asm/           # ZcyASM docs and examples
│   └── *.zcy              # Zcythe example programs
└── scripts/                # Build scripts
```

## Roadmap

### Phase 1: Core VM ✅ (Complete)
- [x] Type-specific register architecture
- [x] Basic arithmetic operations
- [x] Data movement instructions
- [x] Higher-level I/O
- [x] Test suite

### Phase 2: Control Flow 🚧 (In Progress)
- [ ] Labels and jumps
- [ ] Comparison instructions
- [ ] Conditional branches
- [ ] Loop constructs

### Phase 3: Functions 🚧 (Planned)
- [ ] Stack implementation
- [ ] Function calls (CALL/RET)
- [ ] Calling convention
- [ ] Recursion support

### Phase 4: Language Features 📋 (Future)
- [ ] Logical operations (AND, OR, XOR, shifts)
- [ ] Type conversion (CAST)
- [ ] Advanced I/O (READ, STRIN)
- [ ] String operations

### Phase 5: Tooling 📋 (Future)
- [ ] Assembler (parse .zcyasm files)
- [ ] Bytecode generation
- [ ] Debugger/REPL
- [ ] Optimization passes

### Phase 6: Zcythe Compiler 📋 (Future)
- [ ] Lexer and parser for .zcy files
- [ ] Type checker
- [ ] Code generator (Zcythe → ZcyASM)
- [ ] Standard library

## Contributing

**We welcome contributions!** However, please note this project is in the prototype phase.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### How to Contribute

- 🐛 **Report bugs**: Open an issue describing the problem
- 💡 **Suggest features**: Share your ideas in the discussions
- 📖 **Improve docs**: Documentation improvements are always welcome
- 🧪 **Write tests**: Help expand test coverage
- 💻 **Submit code**: Fork, implement, and submit a pull request

### Development Status

Currently seeking contributors for:
- Control flow implementation (jumps, branches)
- Stack and function call mechanism
- Parser/lexer development
- Example programs and tutorials

## Design Decisions

Some key architectural choices:

1. **Type-specific registers**: Unique approach prioritizing type safety over register economy
2. **Higher-level built-ins**: Pragmatic QOL features in an assembly language
3. **Zig-based implementation**: Leveraging Zig's compile-time features and safety
4. **Two-tier design**: High-level language compiling to custom assembly

See [ARCHITECTURE.md](docs/lang/zcy_asm/ARCHITECTURE.md) for detailed rationale.

## Testing

Run the comprehensive test suite:

```bash
cd src/main/zig
zig build-exe test_asm_phase1.zig
./test_asm_phase1
```

**Expected output**: All tests passing ✓

Tests cover:
- Data movement (LDD, LDI, MOV, STD)
- Arithmetic (ADD, SUB, MUL, DIV, MOD, INC, DEC)
- I/O (STROUT, FOUT, PRINT, PRINTLN)
- Practical examples

## Inspiration

Zcythe draws inspiration from:
- **Zig**: Modern systems programming, compile-time features
- **Atmel AVR**: Assembly instruction syntax and microcode design
- **RISC principles**: Simplicity, orthogonality, load/store architecture
- **Scripting languages**: Ease of use, higher-level abstractions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Carrick Remillard**

## Acknowledgments

- The Zig community for an excellent language and toolchain
- Atmel AVR architecture for assembly design inspiration
- All contributors and early testers

---

**⚠️ Remember**: This is a prototype. Expect breaking changes. No versioned releases yet. Use at your own risk!

**Questions?** Open an issue or start a discussion. We'd love to hear from you!
