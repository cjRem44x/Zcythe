# Contributing to Zcythe

Thank you for your interest in contributing to Zcythe! This document provides guidelines and information for contributors.

## ⚠️ Prototype Phase Notice

**Important**: Zcythe is in early prototype development. There are no official releases or versions yet. The codebase and language syntax are subject to significant changes.

**What this means**:
- Breaking changes may occur frequently
- APIs are unstable
- Documentation may be incomplete or outdated
- Core features are still being implemented

**Why contribute now**:
- Shape the direction of the language early
- Learn about language design and VM implementation
- Be part of an exciting experimental project
- Your ideas and feedback have significant impact

## Getting Started

### Prerequisites

- **Zig** (latest version): [Download here](https://ziglang.org/)
- **Git**: For version control
- **Familiarity with**:
  - Assembly language concepts (helpful but not required)
  - Systems programming
  - Compiler/interpreter design (for advanced contributions)

### Setting Up Development Environment

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/YOUR_USERNAME/Zcythe.git
   cd Zcythe
   ```

2. **Build the project**
   ```bash
   cd src/main/zig
   zig build-exe test_asm_phase1.zig
   ```

3. **Run tests**
   ```bash
   ./test_asm_phase1
   # All tests should pass ✓
   ```

4. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Ways to Contribute

### 🐛 Reporting Bugs

**Before submitting**:
- Check existing issues to avoid duplicates
- Verify the bug exists in the latest code

**When reporting**:
- Use a clear, descriptive title
- Describe expected vs actual behavior
- Provide minimal reproduction steps
- Include relevant code snippets
- Mention your Zig version and OS

**Example**:
```markdown
**Title**: "INC instruction fails with f128 registers"

**Description**:
The INC instruction panics when used with f128 register type.

**To Reproduce**:
```zig
core.inc(f128, 0);  // Panics with "index out of bounds"
```

**Expected**: Should increment f128r0 by 1.0
**Actual**: Panic occurs

**Environment**:
- Zig version: 0.11.0
- OS: Windows 11
```

### 💡 Suggesting Features

We welcome feature suggestions! Please:

- Check if the feature is already planned (see [Roadmap](README.md#roadmap))
- Explain the use case and motivation
- Provide example syntax/API if applicable
- Consider backwards compatibility (even in prototype phase)

**Example**:
```markdown
**Title**: "Add NEG instruction for negation"

**Motivation**:
Currently, negating a value requires loading 0 and subtracting, which is verbose.

**Proposed Syntax**:
```zcyasm
.ldi: i32r0, 42
.neg: i32r0      # r0 = -42
```

**Implementation Notes**:
Could be implemented as wrapping negation for integers, standard negation for floats.
```

### 📖 Improving Documentation

Documentation improvements are **always welcome**!

**Areas needing help**:
- Fixing typos and grammar
- Adding more code examples
- Clarifying confusing explanations
- Creating tutorials
- Expanding API documentation
- Adding diagrams and visual aids

**Documentation structure**:
- `README.md` - Project overview
- `docs/lang/zcy_asm/` - ZcyASM documentation
- `docs/lang/*.zcy` - Zcythe example programs
- Inline code comments

### 🧪 Writing Tests

Help expand test coverage:

**Current test file**: `src/main/zig/test_asm_phase1.zig`

**Test guidelines**:
- Test both success and failure cases
- Cover edge cases (overflow, underflow, division by zero)
- Test all register types when applicable
- Use descriptive test names
- Print clear pass/fail messages

**Example test**:
```zig
pub fn test_overflow_wrapping() !void {
    var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
    defer core.deinit();

    // Test wrapping addition
    core.load_immediate(core.I8_REG, 0, @as(i8, 127));  // Max i8
    core.load_immediate(core.I8_REG, 1, @as(i8, 1));
    core.add(i8, 0, 1);

    try exp(core.I8_REG[0] == -128);  // Should wrap
    std.debug.print("  ✓ i8 overflow wraps correctly\n", .{});
}
```

### 💻 Contributing Code

#### Phase 2 Priority Areas

We're currently implementing **Phase 2: Control Flow**. Help needed with:

1. **Labels**
   - Label parsing and storage (HashMap?)
   - Label resolution at jump time
   - Forward reference handling

2. **Comparison**
   - CMP instruction implementation
   - Flag register or comparison state storage
   - Comparison for all numeric types

3. **Jumps**
   - Unconditional jump (JMP)
   - Conditional jumps (JEQ, JNE, JLT, JGT, JLE, JGE)
   - Program counter management

4. **Examples**
   - Loop examples using labels and jumps
   - Conditional examples
   - Algorithm implementations (Fibonacci, GCD, etc.)

#### Code Style Guidelines

**Zig Code**:
- Follow Zig's standard style (4 spaces, snake_case)
- Use meaningful variable names
- Add comments for complex logic
- Prefer compile-time when possible (`comptime`)
- Handle errors explicitly

**ZcyASM Syntax**:
- Use consistent indentation (4 spaces)
- Comment non-obvious operations
- Use descriptive label names (`loop_start`, not `l1`)
- Follow style guide in [SYNTAX.md](docs/lang/zcy_asm/SYNTAX.md)

**Example**:
```zig
// Good: Clear, typed, documented
pub fn cmp(self: *_CORE_SYSTEM_, comptime RegType: type,
           reg1_idx: usize, reg2_idx: usize) void {
    // Compare two registers by subtracting (without storing result)
    // Sets comparison flags for subsequent conditional jumps
    const val1 = switch (RegType) {
        i32 => self.I32_REG[reg1_idx],
        // ... other types
        else => @compileError("Unsupported register type"),
    };
    // ... implementation
}

// Bad: Unclear, untyped
pub fn c(s: *_CORE_SYSTEM_, t: anytype, a: usize, b: usize) void {
    // ...
}
```

#### Commit Messages

Use clear, descriptive commit messages:

**Format**:
```
<type>: <short description>

<optional longer description>
<optional reference to issue>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `style`: Code style changes (formatting)
- `chore`: Build process, tooling

**Examples**:
```
feat: add CMP instruction for i32 registers

Implements comparison instruction for 32-bit signed integers.
Sets internal comparison flags for use with conditional jumps.

Refs #42
```

```
docs: add examples for loop constructs

Added 5 new examples demonstrating different loop patterns
in ZcyASM using labels and conditional jumps.
```

### Pull Request Process

1. **Before submitting**:
   - Ensure all tests pass
   - Update documentation if needed
   - Add tests for new features
   - Follow code style guidelines

2. **Submit PR**:
   - Use a clear, descriptive title
   - Reference related issues
   - Describe what changed and why
   - Include test results
   - Add examples if applicable

3. **PR Template**:
   ```markdown
   ## Description
   Brief description of changes

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Test addition

   ## Testing
   - [ ] All existing tests pass
   - [ ] Added new tests for changes
   - [ ] Manual testing completed

   ## Related Issues
   Fixes #123

   ## Notes
   Any additional context or screenshots
   ```

4. **Review process**:
   - Maintainers will review your PR
   - Address feedback and requested changes
   - Be patient - this is a part-time project
   - PRs may be merged, closed, or marked for future consideration

## Development Workflow

### Adding a New Instruction

**Example**: Adding the `NEG` instruction

1. **Update documentation**:
   - Add to `docs/lang/zcy_asm/INSTRUCTION_SET.md`
   - Add examples to `docs/lang/zcy_asm/EXAMPLES.md`

2. **Implement in core**:
   ```zig
   // In zcy_asm_core.zig
   pub fn neg(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) void {
       switch (RegType) {
           i32 => {
               self.I32_REG[reg_idx] = -%self.I32_REG[reg_idx];
           },
           // ... other types
           else => @compileError("Unsupported register type"),
       }
   }
   ```

3. **Add tests**:
   ```zig
   pub fn test_neg() !void {
       var core = try zcy_asm_core._CORE_SYSTEM_.init(std.heap.page_allocator, 32);
       defer core.deinit();

       core.load_immediate(core.I32_REG, 0, @as(i32, 42));
       core.neg(i32, 0);
       try exp(core.I32_REG[0] == -42);
   }
   ```

4. **Update status**:
   - Mark as implemented in `INSTRUCTION_SET.md`
   - Update `IMPLEMENTATION_STATUS.md`

### Running Tests

```bash
# Build and run main test suite
cd src/main/zig
zig build-exe test_asm_phase1.zig
./test_asm_phase1

# For specific test during development
zig build-exe test_asm_phase1.zig && ./test_asm_phase1
```

## Project Conventions

### Naming Conventions

**Zig code**:
- Structs: `PascalCase` or `_UPPERCASE_WITH_UNDERSCORES_` (for special types)
- Functions: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- Variables: `snake_case`

**ZcyASM**:
- Variables: `snake_case` (e.g., `my_variable`)
- Labels: `snake_case` (e.g., `loop_start`)
- Registers: `<type>r<index>` (e.g., `i32r0`)
- Instructions: lowercase (e.g., `.add`, `.ldi`)

### File Organization

```
src/main/zig/src/
├── zcy_asm_core.zig    # VM core (registers, instructions)
├── main.zig            # CLI entry point
├── util.zig            # Utility functions
├── file_reader.zig     # File I/O
└── (future files)
    ├── lexer.zig       # Tokenization
    ├── parser.zig      # AST construction
    └── codegen.zig     # Code generation
```

## Communication

### Getting Help

- **Issues**: Ask questions by opening an issue with the "question" label
- **Discussions**: For broader topics, use GitHub Discussions (if enabled)
- **Code review**: Comment on pull requests

### Reporting Security Issues

If you discover a security vulnerability:
- **Do not** open a public issue
- Email the maintainer directly (add your email to README)
- Provide detailed description and reproduction steps

## Design Philosophy

When contributing, keep these principles in mind:

1. **Type safety first**: Leverage Zig's compile-time type checking
2. **Simplicity over cleverness**: Clear code beats clever code
3. **QOL without bloat**: Add convenience features thoughtfully
4. **Document everything**: Code is read more than written
5. **Test thoroughly**: Bugs in a VM affect all programs

## Recognition

Contributors will be:
- Listed in the README's Acknowledgments section
- Credited in release notes (when releases begin)
- Recognized in commit history

Significant contributors may be offered collaborator status.

## Questions?

Don't hesitate to ask questions:
- Open an issue with the "question" label
- Include context and what you've tried
- Be patient - maintainers are volunteers

## Code of Conduct

### Our Standards

- Be respectful and professional
- Welcome newcomers and be patient with questions
- Accept constructive criticism gracefully
- Focus on what's best for the project
- Show empathy towards other contributors

### Unacceptable Behavior

- Harassment or discriminatory language
- Trolling or deliberately derailing discussions
- Personal attacks
- Publishing others' private information
- Other unprofessional conduct

### Enforcement

Maintainers reserve the right to:
- Remove comments, commits, or contributions
- Temporarily or permanently ban contributors
- Report serious violations to GitHub

---

## Thank You!

Your contributions help make Zcythe better. Whether you're fixing a typo or implementing a major feature, every contribution is valued.

**Happy coding!** 🚀
