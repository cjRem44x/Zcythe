# ZcyASM Examples

This document contains example programs demonstrating ZcyASM concepts, from simple to complex.

## Example 1: Hello World (Higher-Level I/O)

```zcyasm
# Modern ZcyASM with higher-level I/O
.strout: "Hello, World!\n"
.strout: "Welcome to ZcyASM!\n"
.hlt
```

**Concepts demonstrated**:
- `.strout` instruction (higher-level string output)
- Escape sequences (`\n`)
- Program termination (`.hlt`)

---

## Example 2: Basic Data Movement and Arithmetic

```zcyasm
# Simple example: Load and add two numbers
$i32 : X = 10
$i32 : Y = 20
$i32 : result = 0

.ldd: i32r0, X          # Load X into r0
.ldd: i32r1, Y          # Load Y into r1
.add: i32r0, i32r1      # r0 = r0 + r1 = 30
.std: result, i32r0     # Store r0 into result
.fout: i32r0, "Result: %d\n"  # Print with formatting
```

**Concepts demonstrated**:
- Variable declaration
- Load data (`.ldd`)
- Arithmetic (`.add`)
- Store data (`.std`)
- Formatted output (`.fout`)

---

```zcyasm
# Working with immediate values (no variables)
.ldi: i32r0, 15         # Load immediate 15
.ldi: i32r1, 27         # Load immediate 27
.add: i32r0, i32r1      # r0 = 42
.fout: i32r0, "Answer: %d\n"  # Print: Answer: 42
```

**Concepts demonstrated**:
- Load immediate (`ldi`)
- Operating without data segment

---

## Example 4: Multiple Types and Formatting

```zcyasm
# Different type arithmetic
$i32 : int_val = 10
$f64 : float_val = 3.14

.ldd: i32r0, int_val    # Integer operations
.ldi: i32r1, 5
.mul: i32r0, i32r1      # r0 = 10 * 5 = 50

.ldd: f64r0, float_val  # Float operations
.ldi: f64r1, 2.0
.mul: f64r0, f64r1      # r0 = 3.14 * 2.0 = 6.28

.println: i32r0         # Print: 50
.println: f64r0         # Print: 6.28
```

**Concepts demonstrated**:
- Type-specific registers
- Integer vs float operations
- Type isolation
- Multiple format specifiers (`.fout`)
- Hex and binary output

---

```zcyasm
# Count from 0 to 9
$i32 : counter = 0
$i32 : limit = 10

.ldd: i32r0, counter    # r0 = counter
.ldd: i32r1, limit      # r1 = limit

.strout: "Counting to 10:\n"

loop_start:
    .fout: i32r0, "  %d\n"  # Print current value with indent
    .inc: i32r0             # Increment counter
    .cmp: i32r0, i32r1      # Compare with limit
    .jlt: loop_start        # Jump if less than

.strout: "Done!\n"
.hlt                        # Stop execution
```

**Concepts demonstrated**:
- Labels
- Comparison (`cmp`)
- Conditional jump (`jlt`)
- Increment (`inc`)
- Loop pattern

---

## Example 6: Factorial Function

```zcyasm
# Calculate factorial of 5
# factorial(n) = n * factorial(n-1), base case: factorial(0) = 1

$i32 : n = 5
$i32 : one = 1

# Main program
.ldd: i32r0, n          # r0 = input value
.call: factorial        # Call function (result in r0)
.println: i32r0         # Print: 120
.hlt

# factorial function
# Input: i32r0 (n)
# Output: i32r0 (result)
factorial:
    .ldd: i32r1, one    # r1 = 1
    .cmp: i32r0, i32r1  # Compare n with 1
    .jle: base_case     # If n <= 1, return 1

    # Recursive case: n * factorial(n-1)
    .push: i32r0        # Save n
    .dec: i32r0         # n - 1
    .call: factorial    # factorial(n-1) -> r0
    .pop: i32r1         # Restore n to r1
    .mul: i32r0, i32r1  # r0 = n * factorial(n-1)
    .ret

base_case:
    .ldi: i32r0, 1      # Return 1
    .ret
```

**Concepts demonstrated**:
- Function definition
- Function calls (`call`, `ret`)
- Recursion
- Stack usage (`push`, `pop`)
- Conditional logic

---

## Example 6: Array Sum (Future)

```zcyasm
# Sum elements of an array (requires array support)
$[]i32 : numbers = {10, 20, 30, 40, 50}
$i32 : sum = 0
$i32 : index = 0

.ldi: i32r2, 0          # r2 = sum accumulator
.ldi: i32r3, 0          # r3 = index

loop_start:
    .ldx: i32r0, numbers, i32r3  # Load numbers[index]
    .add: i32r2, i32r0           # sum += numbers[index]
    .inc: i32r3                  # index++
    .ldi: i32r1, 5               # array length
    .cmp: i32r3, i32r1           # index < length?
    .jlt: loop_start             # Continue loop

.println: i32r2         # Print: 150
```

**Concepts demonstrated**:
- Array declaration (PLANNED)
- Indexed load (`ldx` - PLANNED)
- Array traversal

---

## Example 7: String Operations (Future)

```zcyasm
# String concatenation and printing
$str : greeting = "Hello"
$str : name = "World"
$str : result = ""

.lds: sr0, greeting     # Load string into string register
.lds: sr1, name
.strcat: sr0, sr1       # Concatenate strings
.println: sr0           # Print: "HelloWorld"
```

**Concepts demonstrated**:
- String type (PLANNED)
- String registers (PLANNED)
- String operations (PLANNED)

---

## Example 8: Fibonacci Sequence

```zcyasm
# Print first 10 Fibonacci numbers
$i32 : count = 10
$i32 : zero = 0
$i32 : one = 1

# Initialize
.ldi: i32r0, 0          # fib(0) = 0
.ldi: i32r1, 1          # fib(1) = 1
.ldi: i32r2, 0          # counter
.ldd: i32r3, count      # limit

fib_loop:
    .println: i32r0     # Print current Fibonacci number

    .mov: i32r4, i32r0  # temp = fib(n)
    .mov: i32r0, i32r1  # fib(n) = fib(n+1)
    .add: i32r1, i32r4  # fib(n+1) = fib(n) + fib(n+1)

    .inc: i32r2         # counter++
    .cmp: i32r2, i32r3  # counter < limit?
    .jlt: fib_loop      # Continue

.hlt
```

**Concepts demonstrated**:
- Iterative algorithm
- Register shuffling
- Multiple arithmetic operations

---

## Example 9: Greatest Common Divisor (Euclidean Algorithm)

```zcyasm
# Calculate GCD of two numbers using Euclidean algorithm
$i32 : a = 48
$i32 : b = 18
$i32 : zero = 0

.ldd: i32r0, a          # r0 = a
.ldd: i32r1, b          # r1 = b

gcd_loop:
    .ldd: i32r2, zero
    .cmp: i32r1, i32r2  # Check if b == 0
    .jeq: gcd_done      # If yes, we're done

    .mod: i32r2, i32r0, i32r1  # r2 = a % b
    .mov: i32r0, i32r1         # a = b
    .mov: i32r1, i32r2         # b = a % b
    .jmp: gcd_loop             # Repeat

gcd_done:
    .println: i32r0     # Print GCD: 6
    .hlt
```

**Concepts demonstrated**:
- Modulo operation (`mod`)
- Classical algorithm implementation
- Loop with exit condition

---

## Example 10: Bitwise Operations

```zcyasm
# Demonstrate bitwise operations
$u8 : val1 = 0b11110000
$u8 : val2 = 0b10101010

.ldd: u8r0, val1
.ldd: u8r1, val2

# AND operation
.mov: u8r2, u8r0
.and: u8r2, u8r1        # r2 = 0b10100000
.println: u8r2

# OR operation
.mov: u8r2, u8r0
.or: u8r2, u8r1         # r2 = 0b11111010
.println: u8r2

# XOR operation
.mov: u8r2, u8r0
.xor: u8r2, u8r1        # r2 = 0b01011010
.println: u8r2

# NOT operation
.mov: u8r2, u8r0
.not: u8r2              # r2 = 0b00001111
.println: u8r2

# Shift operations
.ldi: u8r0, 0b00001111
.ldi: u8r1, 2
.shl: u8r0, u8r1        # r0 = 0b00111100
.println: u8r0
```

**Concepts demonstrated**:
- Binary literals
- Bitwise AND, OR, XOR, NOT
- Shift operations
- Unsigned integer types

---

## Example 11: Type Conversion

```zcyasm
# Convert between integer and float
$i32 : int_num = 42
$f64 : float_num = 3.14

.ldd: i32r0, int_num
.cast: f64r0, i32r0     # f64r0 = 42.0
.println: f64r0

.ldd: f64r1, float_num
.cast: i32r1, f64r1     # i32r1 = 3 (truncated)
.println: i32r1
```

**Concepts demonstrated**:
- Type casting
- Integer to float conversion
- Float to integer truncation

---

## Example 12: Conditional Maximum

```zcyasm
# Find maximum of two numbers
$i32 : a = 15
$i32 : b = 23
$i32 : max = 0

.ldd: i32r0, a
.ldd: i32r1, b
.cmp: i32r0, i32r1      # Compare a and b
.jge: a_is_greater      # If a >= b, jump

# b is greater
.mov: i32r2, i32r1      # max = b
.jmp: done

a_is_greater:
.mov: i32r2, i32r0      # max = a

done:
.std: max, i32r2
.println: i32r2         # Print: 23
```

**Concepts demonstrated**:
- Conditional branching
- Comparison and jump
- If-else pattern in assembly

---

## Example 13: Multiply by Repeated Addition

```zcyasm
# Implement multiplication using repeated addition
# result = a * b (where b > 0)
$i32 : a = 7
$i32 : b = 6
$i32 : result = 0
$i32 : zero = 0

.ldi: i32r0, 0          # result accumulator
.ldd: i32r1, a          # value to add
.ldd: i32r2, b          # counter
.ldd: i32r3, zero       # zero for comparison

mult_loop:
    .cmp: i32r2, i32r3  # counter == 0?
    .jeq: mult_done     # If yes, done

    .add: i32r0, i32r1  # result += a
    .dec: i32r2         # counter--
    .jmp: mult_loop

mult_done:
    .std: result, i32r0
    .println: i32r0     # Print: 42
```

**Concepts demonstrated**:
- Implementing higher-level operation with primitives
- Accumulator pattern
- Loop-based algorithm

---

## Example 14: Average of Numbers

```zcyasm
# Calculate average of 5 numbers
$i32 : num1 = 10
$i32 : num2 = 20
$i32 : num3 = 30
$i32 : num4 = 40
$i32 : num5 = 50

.ldi: i32r0, 0          # sum accumulator

# Add all numbers
.ldd: i32r1, num1
.add: i32r0, i32r1
.ldd: i32r1, num2
.add: i32r0, i32r1
.ldd: i32r1, num3
.add: i32r0, i32r1
.ldd: i32r1, num4
.add: i32r0, i32r1
.ldd: i32r1, num5
.add: i32r0, i32r1

# Divide by count
.ldi: i32r1, 5
.div: i32r0, i32r1      # r0 = sum / 5

.println: i32r0         # Print: 30
```

**Concepts demonstrated**:
- Accumulation pattern
- Division operation
- Sequential operations

---

## Example 15: Power Function (x^n)

```zcyasm
# Calculate x^n using repeated multiplication
# Example: 2^5 = 32
$i32 : base = 2
$i32 : exponent = 5
$i32 : one = 1

.ldi: i32r0, 1          # result = 1
.ldd: i32r1, base       # base value
.ldd: i32r2, exponent   # counter
.ldd: i32r3, one        # one for comparison

power_loop:
    .cmp: i32r2, i32r3  # counter == 1?
    .jlt: power_done    # If counter < 1, done

    .mul: i32r0, i32r1  # result *= base
    .dec: i32r2         # counter--
    .jmp: power_loop

power_done:
    .println: i32r0     # Print: 32
    .hlt
```

**Concepts demonstrated**:
- Exponentiation algorithm
- Repeated multiplication
- Loop with decrementing counter

---

## Design Notes from Examples

These examples reveal several design considerations:

### 1. String Registers
Examples 7 shows a need for string-specific registers (like `sr0`). Should we:
- Add string register file?
- Treat strings as memory addresses in integer registers?
- Have special string instructions?

### 2. Three-Operand Instructions
Example 9 shows `.mod: i32r2, i32r0, i32r1` (three operands). Should we:
- Keep two-operand format (dest = dest OP src)?
- Allow three-operand format (dest = src1 OP src2)?
- Use separate instruction (`.mov` then `.mod`)?

### 3. Array Support
Example 6 requires array indexing. We need:
- Array declaration syntax
- Indexed load instruction (`.ldx`)
- Indexed store instruction (`.stx`)
- Bounds checking?

### 4. Entry Point
Should programs:
- Start at first instruction?
- Require a `main:` label?
- Have explicit entry point directive?

### 5. Constants
Should we support:
- Named constants (like variables but immutable)?
- Syntax: `%i32 : PI = 3` (using `%` instead of `$`)?
