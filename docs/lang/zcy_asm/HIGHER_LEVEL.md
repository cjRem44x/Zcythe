# Higher-Level Built-in Instructions

Since ZcyASM is a *scripting language* that emulates assembly rather than raw hardware ASM, it includes higher-level built-in instructions for common operations. These would typically be library functions or syscalls in traditional assembly.

## Philosophy

**"Escape the metal"**: ZcyASM provides convenience without sacrificing the low-level feel. The goal is to make practical programs easier to write while maintaining explicit control.

**Examples of higher-level features**:
- String I/O with escape sequences (`.strout`)
- Formatted output like printf (`.fout`)
- Math helpers (abs, min, max)
- String operations (strlen, strcmp)
- Memory operations (memcpy, memset)
- Random number generation
- Time/sleep functions

## Categories

### 1. I/O Operations (Detailed in INSTRUCTION_SET.md)

#### String Output
- `.strout: "text\n"` - Print string with escape sequences
- `.fout: reg, "format %d"` - Printf-style formatted output

#### String Input
- `.strin: str_var` - Read line from stdin
- `.read: reg` - Read numeric value into register

#### Simple Output
- `.print: reg` - Print register value
- `.println: reg` - Print register value with newline

---

### 2. String Operations (PLANNED)

#### STRLEN - String Length
**Syntax**: `.strlen: <dest_reg>, <str_var>`

Get length of string.

**Example**:
```zcyasm
$str : message = "Hello"
.strlen: u64r0, message  # r0 = 5
```

---

#### STRCMP - String Compare
**Syntax**: `.strcmp: <dest_reg>, <str_var1>, <str_var2>`

Compare two strings. Returns:
- 0 if equal
- -1 if str1 < str2
- 1 if str1 > str2

**Example**:
```zcyasm
$str : a = "apple"
$str : b = "banana"
.strcmp: i32r0, a, b  # r0 = -1 (apple < banana)
```

---

#### STRCAT - String Concatenate
**Syntax**: `.strcat: <dest_str>, <src_str>`

Append src_str to dest_str.

**Example**:
```zcyasm
$str : greeting = "Hello"
$str : name = " World"
.strcat: greeting, name  # greeting = "Hello World"
```

---

#### SUBSTR - Substring
**Syntax**: `.substr: <dest_str>, <src_str>, <start_reg>, <length_reg>`

Extract substring.

**Example**:
```zcyasm
$str : text = "Hello World"
$str : result = ""
.ldi: u64r0, 0      # start
.ldi: u64r1, 5      # length
.substr: result, text, u64r0, u64r1  # result = "Hello"
```

---

### 3. Math Helpers (PLANNED)

These operate on registers and are more convenient than manual comparisons.

#### ABS - Absolute Value
**Syntax**: `.abs: <reg>`

**Example**:
```zcyasm
.ldi: i32r0, -42
.abs: i32r0          # r0 = 42
```

---

#### MIN - Minimum
**Syntax**: `.min: <dest_reg>, <src_reg>`

Store minimum of two values in dest_reg.

**Example**:
```zcyasm
.ldi: i32r0, 10
.ldi: i32r1, 5
.min: i32r0, i32r1   # r0 = 5
```

---

#### MAX - Maximum
**Syntax**: `.max: <dest_reg>, <src_reg>`

Store maximum of two values in dest_reg.

**Example**:
```zcyasm
.ldi: i32r0, 10
.ldi: i32r1, 5
.max: i32r0, i32r1   # r0 = 10
```

---

#### CLAMP - Clamp Value
**Syntax**: `.clamp: <value_reg>, <min_reg>, <max_reg>`

Clamp value to range [min, max].

**Example**:
```zcyasm
.ldi: i32r0, 150     # value
.ldi: i32r1, 0       # min
.ldi: i32r2, 100     # max
.clamp: i32r0, i32r1, i32r2  # r0 = 100
```

---

#### POW - Power
**Syntax**: `.pow: <dest_reg>, <base_reg>, <exp_reg>`

Calculate base^exponent.

**Example**:
```zcyasm
.ldi: f64r0, 2.0
.ldi: f64r1, 3.0
.pow: f64r0, f64r1   # r0 = 8.0 (2^3)
```

---

#### SQRT - Square Root
**Syntax**: `.sqrt: <reg>`

**Example**:
```zcyasm
.ldi: f64r0, 16.0
.sqrt: f64r0         # r0 = 4.0
```

---

#### SIN, COS, TAN - Trigonometric Functions
**Syntax**: `.sin: <reg>`, `.cos: <reg>`, `.tan: <reg>`

Operate on radians.

**Example**:
```zcyasm
.ldi: f64r0, 3.14159  # PI
.sin: f64r0           # r0 ≈ 0.0
```

---

### 4. Random Numbers (PLANNED)

#### RNG - Random Number Generator
**Syntax**: `.rng: <dest_reg>, <min_reg>, <max_reg>`

Generate random number in range [min, max].

**Example**:
```zcyasm
.ldi: i32r1, 1       # min
.ldi: i32r2, 100     # max
.rng: i32r0, i32r1, i32r2  # r0 = random number 1-100
```

---

#### SEED - Seed RNG
**Syntax**: `.seed: <seed_reg>`

Set random number generator seed.

**Example**:
```zcyasm
.ldi: u64r0, 12345
.seed: u64r0
```

---

### 5. Memory Operations (PLANNED)

#### MEMCPY - Memory Copy
**Syntax**: `.memcpy: <dest_addr>, <src_addr>, <size_reg>`

Copy block of memory.

**Example**:
```zcyasm
# TBD - depends on memory/pointer model
```

---

#### MEMSET - Memory Set
**Syntax**: `.memset: <dest_addr>, <value_reg>, <size_reg>`

Fill memory with value.

**Example**:
```zcyasm
# TBD - depends on memory/pointer model
```

---

### 6. Time and Delays (PLANNED)

#### SLEEP - Sleep Milliseconds
**Syntax**: `.sleep: <ms_reg>`

Pause execution for specified milliseconds.

**Example**:
```zcyasm
.ldi: u64r0, 1000
.sleep: u64r0        # Sleep for 1 second
```

---

#### TIME - Get Current Time
**Syntax**: `.time: <dest_reg>`

Get current Unix timestamp in milliseconds.

**Example**:
```zcyasm
.time: u64r0         # r0 = current time in ms
```

---

### 7. Array/Collection Helpers (FUTURE)

#### ARRLEN - Array Length
**Syntax**: `.arrlen: <dest_reg>, <array_var>`

Get length of array.

**Example**:
```zcyasm
$[]i32 : numbers = {10, 20, 30}
.arrlen: u64r0, numbers  # r0 = 3
```

---

#### ARRSUM - Array Sum
**Syntax**: `.arrsum: <dest_reg>, <array_var>`

Sum all elements of numeric array.

**Example**:
```zcyasm
$[]i32 : numbers = {10, 20, 30}
.arrsum: i32r0, numbers  # r0 = 60
```

---

### 8. Type Introspection (FUTURE)

#### TYPEOF - Get Type
**Syntax**: `.typeof: <dest_reg>, <var>`

Get type ID of variable.

**Example**:
```zcyasm
$i32 : x = 42
.typeof: u8r0, x     # r0 = TYPE_I32 constant
```

---

### 9. Debugging and Assertions (PLANNED)

#### ASSERT - Runtime Assertion
**Syntax**: `.assert: <condition_reg>, "<message>"`

Assert condition is true, halt with message if false.

**Example**:
```zcyasm
.ldi: i32r0, 5
.ldi: i32r1, 10
.cmp: i32r0, i32r1
.jlt: ok
.ldi: i32r2, 0
.assert: i32r2, "Expected r0 < r1"
ok:
```

Alternative simpler syntax:
```zcyasm
.ldi: i32r0, 5
.ldi: i32r1, 10
.assert_lt: i32r0, i32r1, "Expected r0 < r1"
```

---

#### TRACE - Debug Trace
**Syntax**: `.trace: "<message>"`

Print debug message with line number.

**Example**:
```zcyasm
.trace: "Entering loop"
loop_start:
    # ... loop body
```

Output: `[Line 2] Entering loop`

---

#### DUMP - Dump Register State
**Syntax**: `.dump: <reg>`

Print register name and value for debugging.

**Example**:
```zcyasm
.ldi: i32r0, 42
.dump: i32r0         # Output: i32r0 = 42
```

---

### 10. File I/O (FUTURE)

If we want to support file operations:

#### FOPEN - Open File
```zcyasm
.fopen: file_handle, "path.txt", "r"  # Read mode
```

#### FREAD - Read from File
```zcyasm
.fread: str_var, file_handle, size
```

#### FWRITE - Write to File
```zcyasm
.fwrite: file_handle, "data\n"
```

#### FCLOSE - Close File
```zcyasm
.fclose: file_handle
```

---

## Design Considerations

### When to Add Built-ins vs Library Functions?

**Add as built-in if**:
- Very common operation
- Requires runtime/VM support (I/O, time, RNG)
- Significantly simpler than manual implementation
- Hard to implement without language support

**Keep as library if**:
- Can be easily implemented with existing instructions
- Complex algorithm better shown explicitly
- Not performance-critical

**Examples**:
- `abs` - Could be library, but so common it's worth built-in
- `strlen` - Needs string support, good as built-in
- `bubble_sort` - Complex algorithm, keep as library
- `rng` - Requires runtime support, must be built-in

### Balancing Convenience and Simplicity

**Pros of higher-level built-ins**:
- Faster development
- Cleaner code
- More accessible to beginners
- Less boilerplate

**Cons**:
- Larger instruction set to learn
- More implementation complexity
- Less "pure" assembly feel
- May hide useful learning opportunities

**Our approach**: Provide built-ins for:
1. Operations that require runtime support (I/O, RNG, time)
2. Very common operations (abs, min, max, string ops)
3. Operations that would be tedious in pure ASM (formatted output)

But keep the core arithmetic and control flow simple and explicit.

### Naming Conventions

- All instructions lowercase
- Descriptive names (`.strout` not `.so`)
- Consistent with category (`.str*` for strings, `.arr*` for arrays)
- Math functions match common names (`sqrt`, `sin`, `abs`)

---

## Integration with Zcythe

When Zcythe compiles to ZcyASM:

**Zcythe code**:
```zcythe
@pl("Hello, World!")
```

**Could compile to**:
```zcyasm
.strout: "Hello, World!\n"
```

**Zcythe code**:
```zcythe
@pf("x = %d\n", x)
```

**Could compile to**:
```zcyasm
.ldd: i32r0, x
.fout: i32r0, "x = %d\n"
```

This makes the compilation simpler and ZcyASM more ergonomic to write by hand.

---

## Implementation Priority

For higher-level features:

**Phase 1** (Essential):
- `.strout`, `.fout` (I/O is critical for testing)
- `.println` (simple debugging)

**Phase 2** (Very Useful):
- `.abs`, `.min`, `.max` (common math helpers)
- `.strlen`, `.strcmp` (basic string ops)
- `.sleep`, `.time` (useful utilities)

**Phase 3** (Nice to Have):
- `.sqrt`, `.pow` (advanced math)
- `.sin`, `.cos`, `.tan` (trig)
- `.rng`, `.seed` (randomness)
- `.assert`, `.trace`, `.dump` (debugging)

**Phase 4** (Future):
- String manipulation (`.substr`, `.strcat`)
- Array helpers (`.arrsum`, `.arrlen`)
- File I/O
- Memory operations

---

## Examples Using Higher-Level Instructions

### Interactive Calculator
```zcyasm
$i32 : a = 0
$i32 : b = 0
$i32 : result = 0

.strout: "Enter first number: "
.read: i32r0
.std: a, i32r0

.strout: "Enter second number: "
.read: i32r1
.std: b, i32r1

.add: i32r0, i32r1
.std: result, i32r0

.fout: i32r0, "Result: %d\n"
```

### Random Number Game
```zcyasm
$i32 : secret = 0
$i32 : guess = 0

# Generate random number 1-100
.ldi: i32r1, 1
.ldi: i32r2, 100
.rng: i32r0, i32r1, i32r2
.std: secret, i32r0

.strout: "Guess the number (1-100): "

game_loop:
    .read: i32r1
    .ldd: i32r0, secret
    .cmp: i32r1, i32r0
    .jeq: correct
    .jlt: too_low

    .strout: "Too high! Try again: "
    .jmp: game_loop

too_low:
    .strout: "Too low! Try again: "
    .jmp: game_loop

correct:
    .strout: "Correct!\n"
    .hlt
```

### Debug Tracing
```zcyasm
.trace: "Starting calculation"

.ldi: i32r0, 10
.dump: i32r0

.ldi: i32r1, 5
.dump: i32r1

.add: i32r0, i32r1
.dump: i32r0

.trace: "Calculation complete"
```

Output:
```
[Line 1] Starting calculation
i32r0 = 10
i32r1 = 5
i32r0 = 15
[Line 11] Calculation complete
```

---

## Summary

Higher-level built-ins make ZcyASM a **practical scripting language** while maintaining the explicit, low-level control of assembly. The key is finding the right balance between convenience and simplicity.

The philosophy: **"As low-level as possible, as high-level as necessary"**
