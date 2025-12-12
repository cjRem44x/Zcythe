# Changelog

All notable changes to Zcythe will be documented in this file.

**⚠️ PROTOTYPE PHASE**: No official versions have been released yet. This changelog tracks significant milestones during development.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Phase 1 Complete - 2025-12-11

#### Added - ZcyASM Core VM
- Type-specific register architecture (14 register files)
- Data movement instructions: `ldd`, `ldi`, `mov`, `std`
- Arithmetic instructions: `add`, `sub`, `mul`, `div`, `mod`, `inc`, `dec`
- Higher-level I/O instructions: `strout`, `fout`, `print`, `println`
- Comprehensive test suite (test_asm_phase1.zig)
- VM core implementation (zcy_asm_core.zig)

#### Documentation
- Complete ISA reference (INSTRUCTION_SET.md)
- Architecture specification (ARCHITECTURE.md)
- Syntax specification with EBNF grammar (SYNTAX.md)
- 15+ code examples (EXAMPLES.md)
- Higher-level features guide (HIGHER_LEVEL.md)
- Implementation status tracking (IMPLEMENTATION_STATUS.md)
- README with project overview
- Contributing guidelines (CONTRIBUTING.md)

#### Infrastructure
- MIT License
- Issue templates (bug reports, feature requests)
- Pull request template
- .gitignore configuration
- GitHub-ready project structure

### Initial Commit - Earlier

#### Added
- Project structure
- Basic Zig build configuration
- Utility library (util.zig)
- File reader infrastructure (file_reader.zig)
- CLI entry point (main.zig)
- Initial Zcythe language examples
- Basic documentation structure

---

## Future Milestones (Planned)

### Phase 2: Control Flow (In Development)
- [ ] Label support
- [ ] Comparison instruction (`cmp`)
- [ ] Conditional jumps (`jeq`, `jne`, `jlt`, `jgt`, `jle`, `jge`)
- [ ] Unconditional jump (`jmp`)
- [ ] Loop examples

### Phase 3: Functions (Planned)
- [ ] Stack implementation
- [ ] Push/pop instructions
- [ ] Call/return instructions
- [ ] Calling convention
- [ ] Recursive function examples

### Phase 4: Language Features (Planned)
- [ ] Logical operations (and, or, xor, not)
- [ ] Shift operations (shl, shr)
- [ ] Type conversion (cast)
- [ ] Advanced I/O (read, strin)
- [ ] String operations

### Phase 5: Tooling (Planned)
- [ ] Lexer for .zcyasm files
- [ ] Parser for .zcyasm files
- [ ] Assembler
- [ ] Bytecode generation
- [ ] REPL/Debugger

### Phase 6: Zcythe Compiler (Future)
- [ ] Zcythe lexer/parser
- [ ] Type checker
- [ ] Code generator (Zcythe → ZcyASM)
- [ ] Standard library
- [ ] Package manager

---

## Version Guidelines (When Releases Begin)

When official releases start, we will follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to language syntax or VM behavior
- **MINOR**: New features (instructions, language constructs)
- **PATCH**: Bug fixes and documentation improvements

Example: `0.1.0` → `0.2.0` → `1.0.0`

### Pre-1.0 Notice
Until version 1.0, the API is considered unstable and breaking changes may occur in minor versions.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute to Zcythe.

For significant changes, please open an issue first to discuss what you would like to change.
