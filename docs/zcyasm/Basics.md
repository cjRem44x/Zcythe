# ZcytheASM

There is Zcythe Source, then there is ZcytheASM: a far lower level, RISC assembly emulator.

The general and simple syntax.
```
# comment
@main # @ is used for labels
op arg1 arg2 ... # every instruc starts with opcodes, followed by args
...
```

ZcytheASM is designed to be a dead simple, procedural assembly script.

Hello World,
```
@main
printStr "Hello World\n" # prints string without having to load into anything
```

Since all of Zcythe is built on Zig, ZcytheASM will only use the basic provide types:
`u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, f16, f32, f64, f128, usize, isize,`
Just the primitives.

