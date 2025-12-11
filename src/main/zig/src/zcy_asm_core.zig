const std = @import("std");

pub const _CORE_SYSTEM_ = struct {
    // -- Registers -- //
    //
    I8_REG: []i8,
    I16_REG: []i16,
    I32_REG: []i32,
    I64_REG: []i64,
    I128_REG: []i128,
    //
    U8_REG: []u8,
    U16_REG: []u16,
    U32_REG: []u32,
    U64_REG: []u64,
    U128_REG: []u128,
    //
    F16_REG: []f16,
    F32_REG: []f32,
    F64_REG: []f64,
    F128_REG: []f128,
    //
    allocator: std.mem.Allocator,

    // -- Initialization and Deinitialization -- // 
    //
    pub fn init(allocator: std.mem.Allocator, _REG_SIZE_: usize) !_CORE_SYSTEM_ {
        return .{
            .I8_REG = try allocator.alloc(i8, _REG_SIZE_),
            .I16_REG = try allocator.alloc(i16, _REG_SIZE_),
            .I32_REG = try allocator.alloc(i32, _REG_SIZE_),
            .I64_REG = try allocator.alloc(i64, _REG_SIZE_),
            .I128_REG = try allocator.alloc(i128, _REG_SIZE_),
            .U8_REG = try allocator.alloc(u8, _REG_SIZE_),
            .U16_REG = try allocator.alloc(u16, _REG_SIZE_),
            .U32_REG = try allocator.alloc(u32, _REG_SIZE_),
            .U64_REG = try allocator.alloc(u64, _REG_SIZE_),
            .U128_REG = try allocator.alloc(u128, _REG_SIZE_),
            .F16_REG = try allocator.alloc(f16, _REG_SIZE_),
            .F32_REG = try allocator.alloc(f32, _REG_SIZE_),
            .F64_REG = try allocator.alloc(f64, _REG_SIZE_),
            .F128_REG = try allocator.alloc(f128, _REG_SIZE_),
            .allocator = allocator,
        };
    }
    //
    pub fn deinit(self: *_CORE_SYSTEM_) void {
        self.allocator.free(self.I8_REG);
        self.allocator.free(self.I16_REG);
        self.allocator.free(self.I32_REG);
        self.allocator.free(self.I64_REG);
        self.allocator.free(self.I128_REG);
        self.allocator.free(self.U8_REG);
        self.allocator.free(self.U16_REG);
        self.allocator.free(self.U32_REG);
        self.allocator.free(self.U64_REG);
        self.allocator.free(self.U128_REG);
        self.allocator.free(self.F16_REG);
        self.allocator.free(self.F32_REG);
        self.allocator.free(self.F64_REG);
        self.allocator.free(self.F128_REG);
    }

    // ========================================
    // == DATA MOVEMENT INSTRUCTIONS
    // ========================================

    // LDD: Load data from variable into register
    pub fn load_data(self: *_CORE_SYSTEM_, _REG_: anytype, _REG_IDX_: usize, _DAT_: anytype) void {
        const REG_T = @TypeOf(_REG_);
        const DAT_T = @TypeOf(_DAT_);

        if (REG_T == []i8 and DAT_T == i8) {
            self.I8_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []i16 and DAT_T == i16) {
            self.I16_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []i32 and DAT_T == i32) {
            self.I32_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []i64 and DAT_T == i64) {
            self.I64_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []i128 and DAT_T == i128) {
            self.I128_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []u8 and DAT_T == u8) {
            self.U8_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []u16 and DAT_T == u16) {
            self.U16_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []u32 and DAT_T == u32) {
            self.U32_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []u64 and DAT_T == u64) {
            self.U64_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []u128 and DAT_T == u128) {
            self.U128_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []f16 and DAT_T == f16) {
            self.F16_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []f32 and DAT_T == f32) {
            self.F32_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []f64 and DAT_T == f64) {
            self.F64_REG[_REG_IDX_] = _DAT_;
        } else if (REG_T == []f128 and DAT_T == f128) {
            self.F128_REG[_REG_IDX_] = _DAT_;
        } else {
            @panic("Unsupported register or data type");
        }
    }

    // LDI: Load immediate value into register
    // Same implementation as load_data (immediate values are just data)
    pub fn load_immediate(self: *_CORE_SYSTEM_, _REG_: anytype, _REG_IDX_: usize, _IMM_: anytype) void {
        self.load_data(_REG_, _REG_IDX_, _IMM_);
    }

    // MOV: Move register to register
    pub fn mov(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => self.I8_REG[dest_idx] = self.I8_REG[src_idx],
            i16 => self.I16_REG[dest_idx] = self.I16_REG[src_idx],
            i32 => self.I32_REG[dest_idx] = self.I32_REG[src_idx],
            i64 => self.I64_REG[dest_idx] = self.I64_REG[src_idx],
            i128 => self.I128_REG[dest_idx] = self.I128_REG[src_idx],
            u8 => self.U8_REG[dest_idx] = self.U8_REG[src_idx],
            u16 => self.U16_REG[dest_idx] = self.U16_REG[src_idx],
            u32 => self.U32_REG[dest_idx] = self.U32_REG[src_idx],
            u64 => self.U64_REG[dest_idx] = self.U64_REG[src_idx],
            u128 => self.U128_REG[dest_idx] = self.U128_REG[src_idx],
            f16 => self.F16_REG[dest_idx] = self.F16_REG[src_idx],
            f32 => self.F32_REG[dest_idx] = self.F32_REG[src_idx],
            f64 => self.F64_REG[dest_idx] = self.F64_REG[src_idx],
            f128 => self.F128_REG[dest_idx] = self.F128_REG[src_idx],
            else => @compileError("Unsupported register type"),
        }
    }

    // STD: Store register data to variable (returns value for variable storage)
    pub fn store_data(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) RegType {
        return switch (RegType) {
            i8 => self.I8_REG[reg_idx],
            i16 => self.I16_REG[reg_idx],
            i32 => self.I32_REG[reg_idx],
            i64 => self.I64_REG[reg_idx],
            i128 => self.I128_REG[reg_idx],
            u8 => self.U8_REG[reg_idx],
            u16 => self.U16_REG[reg_idx],
            u32 => self.U32_REG[reg_idx],
            u64 => self.U64_REG[reg_idx],
            u128 => self.U128_REG[reg_idx],
            f16 => self.F16_REG[reg_idx],
            f32 => self.F32_REG[reg_idx],
            f64 => self.F64_REG[reg_idx],
            f128 => self.F128_REG[reg_idx],
            else => @compileError("Unsupported register type"),
        };
    }

    // ========================================
    // == ARITHMETIC INSTRUCTIONS
    // ========================================

    // ADD: Addition (dest = dest + src)
    pub fn add(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => {
                self.I8_REG[dest_idx] +%= self.I8_REG[src_idx];
            },
            i16 => {
                self.I16_REG[dest_idx] +%= self.I16_REG[src_idx];
            },
            i32 => {
                self.I32_REG[dest_idx] +%= self.I32_REG[src_idx];
            },
            i64 => {
                self.I64_REG[dest_idx] +%= self.I64_REG[src_idx];
            },
            i128 => {
                self.I128_REG[dest_idx] +%= self.I128_REG[src_idx];
            },
            u8 => {
                self.U8_REG[dest_idx] +%= self.U8_REG[src_idx];
            },
            u16 => {
                self.U16_REG[dest_idx] +%= self.U16_REG[src_idx];
            },
            u32 => {
                self.U32_REG[dest_idx] +%= self.U32_REG[src_idx];
            },
            u64 => {
                self.U64_REG[dest_idx] +%= self.U64_REG[src_idx];
            },
            u128 => {
                self.U128_REG[dest_idx] +%= self.U128_REG[src_idx];
            },
            f16 => {
                self.F16_REG[dest_idx] += self.F16_REG[src_idx];
            },
            f32 => {
                self.F32_REG[dest_idx] += self.F32_REG[src_idx];
            },
            f64 => {
                self.F64_REG[dest_idx] += self.F64_REG[src_idx];
            },
            f128 => {
                self.F128_REG[dest_idx] += self.F128_REG[src_idx];
            },
            else => @compileError("Unsupported register type"),
        }
    }

    // SUB: Subtraction (dest = dest - src)
    pub fn sub(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => {
                self.I8_REG[dest_idx] -%= self.I8_REG[src_idx];
            },
            i16 => {
                self.I16_REG[dest_idx] -%= self.I16_REG[src_idx];
            },
            i32 => {
                self.I32_REG[dest_idx] -%= self.I32_REG[src_idx];
            },
            i64 => {
                self.I64_REG[dest_idx] -%= self.I64_REG[src_idx];
            },
            i128 => {
                self.I128_REG[dest_idx] -%= self.I128_REG[src_idx];
            },
            u8 => {
                self.U8_REG[dest_idx] -%= self.U8_REG[src_idx];
            },
            u16 => {
                self.U16_REG[dest_idx] -%= self.U16_REG[src_idx];
            },
            u32 => {
                self.U32_REG[dest_idx] -%= self.U32_REG[src_idx];
            },
            u64 => {
                self.U64_REG[dest_idx] -%= self.U64_REG[src_idx];
            },
            u128 => {
                self.U128_REG[dest_idx] -%= self.U128_REG[src_idx];
            },
            f16 => {
                self.F16_REG[dest_idx] -= self.F16_REG[src_idx];
            },
            f32 => {
                self.F32_REG[dest_idx] -= self.F32_REG[src_idx];
            },
            f64 => {
                self.F64_REG[dest_idx] -= self.F64_REG[src_idx];
            },
            f128 => {
                self.F128_REG[dest_idx] -= self.F128_REG[src_idx];
            },
            else => @compileError("Unsupported register type"),
        }
    }

    // MUL: Multiplication (dest = dest * src)
    pub fn mul(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => {
                self.I8_REG[dest_idx] *%= self.I8_REG[src_idx];
            },
            i16 => {
                self.I16_REG[dest_idx] *%= self.I16_REG[src_idx];
            },
            i32 => {
                self.I32_REG[dest_idx] *%= self.I32_REG[src_idx];
            },
            i64 => {
                self.I64_REG[dest_idx] *%= self.I64_REG[src_idx];
            },
            i128 => {
                self.I128_REG[dest_idx] *%= self.I128_REG[src_idx];
            },
            u8 => {
                self.U8_REG[dest_idx] *%= self.U8_REG[src_idx];
            },
            u16 => {
                self.U16_REG[dest_idx] *%= self.U16_REG[src_idx];
            },
            u32 => {
                self.U32_REG[dest_idx] *%= self.U32_REG[src_idx];
            },
            u64 => {
                self.U64_REG[dest_idx] *%= self.U64_REG[src_idx];
            },
            u128 => {
                self.U128_REG[dest_idx] *%= self.U128_REG[src_idx];
            },
            f16 => {
                self.F16_REG[dest_idx] *= self.F16_REG[src_idx];
            },
            f32 => {
                self.F32_REG[dest_idx] *= self.F32_REG[src_idx];
            },
            f64 => {
                self.F64_REG[dest_idx] *= self.F64_REG[src_idx];
            },
            f128 => {
                self.F128_REG[dest_idx] *= self.F128_REG[src_idx];
            },
            else => @compileError("Unsupported register type"),
        }
    }

    // DIV: Division (dest = dest / src)
    pub fn div(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => self.I8_REG[dest_idx] = @divTrunc(self.I8_REG[dest_idx], self.I8_REG[src_idx]),
            i16 => self.I16_REG[dest_idx] = @divTrunc(self.I16_REG[dest_idx], self.I16_REG[src_idx]),
            i32 => self.I32_REG[dest_idx] = @divTrunc(self.I32_REG[dest_idx], self.I32_REG[src_idx]),
            i64 => self.I64_REG[dest_idx] = @divTrunc(self.I64_REG[dest_idx], self.I64_REG[src_idx]),
            i128 => self.I128_REG[dest_idx] = @divTrunc(self.I128_REG[dest_idx], self.I128_REG[src_idx]),
            u8 => self.U8_REG[dest_idx] = @divTrunc(self.U8_REG[dest_idx], self.U8_REG[src_idx]),
            u16 => self.U16_REG[dest_idx] = @divTrunc(self.U16_REG[dest_idx], self.U16_REG[src_idx]),
            u32 => self.U32_REG[dest_idx] = @divTrunc(self.U32_REG[dest_idx], self.U32_REG[src_idx]),
            u64 => self.U64_REG[dest_idx] = @divTrunc(self.U64_REG[dest_idx], self.U64_REG[src_idx]),
            u128 => self.U128_REG[dest_idx] = @divTrunc(self.U128_REG[dest_idx], self.U128_REG[src_idx]),
            f16 => self.F16_REG[dest_idx] /= self.F16_REG[src_idx],
            f32 => self.F32_REG[dest_idx] /= self.F32_REG[src_idx],
            f64 => self.F64_REG[dest_idx] /= self.F64_REG[src_idx],
            f128 => self.F128_REG[dest_idx] /= self.F128_REG[src_idx],
            else => @compileError("Unsupported register type"),
        }
    }

    // MOD: Modulo (dest = dest % src) - integers only
    pub fn mod(self: *_CORE_SYSTEM_, comptime RegType: type, dest_idx: usize, src_idx: usize) void {
        switch (RegType) {
            i8 => self.I8_REG[dest_idx] = @rem(self.I8_REG[dest_idx], self.I8_REG[src_idx]),
            i16 => self.I16_REG[dest_idx] = @rem(self.I16_REG[dest_idx], self.I16_REG[src_idx]),
            i32 => self.I32_REG[dest_idx] = @rem(self.I32_REG[dest_idx], self.I32_REG[src_idx]),
            i64 => self.I64_REG[dest_idx] = @rem(self.I64_REG[dest_idx], self.I64_REG[src_idx]),
            i128 => self.I128_REG[dest_idx] = @rem(self.I128_REG[dest_idx], self.I128_REG[src_idx]),
            u8 => self.U8_REG[dest_idx] = @rem(self.U8_REG[dest_idx], self.U8_REG[src_idx]),
            u16 => self.U16_REG[dest_idx] = @rem(self.U16_REG[dest_idx], self.U16_REG[src_idx]),
            u32 => self.U32_REG[dest_idx] = @rem(self.U32_REG[dest_idx], self.U32_REG[src_idx]),
            u64 => self.U64_REG[dest_idx] = @rem(self.U64_REG[dest_idx], self.U64_REG[src_idx]),
            u128 => self.U128_REG[dest_idx] = @rem(self.U128_REG[dest_idx], self.U128_REG[src_idx]),
            else => @compileError("Modulo only supported for integer types"),
        }
    }

    // INC: Increment register by 1
    pub fn inc(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) void {
        switch (RegType) {
            i8 => {
                self.I8_REG[reg_idx] +%= 1;
            },
            i16 => {
                self.I16_REG[reg_idx] +%= 1;
            },
            i32 => {
                self.I32_REG[reg_idx] +%= 1;
            },
            i64 => {
                self.I64_REG[reg_idx] +%= 1;
            },
            i128 => {
                self.I128_REG[reg_idx] +%= 1;
            },
            u8 => {
                self.U8_REG[reg_idx] +%= 1;
            },
            u16 => {
                self.U16_REG[reg_idx] +%= 1;
            },
            u32 => {
                self.U32_REG[reg_idx] +%= 1;
            },
            u64 => {
                self.U64_REG[reg_idx] +%= 1;
            },
            u128 => {
                self.U128_REG[reg_idx] +%= 1;
            },
            f16 => {
                self.F16_REG[reg_idx] += 1.0;
            },
            f32 => {
                self.F32_REG[reg_idx] += 1.0;
            },
            f64 => {
                self.F64_REG[reg_idx] += 1.0;
            },
            f128 => {
                self.F128_REG[reg_idx] += 1.0;
            },
            else => @compileError("Unsupported register type"),
        }
    }

    // DEC: Decrement register by 1
    pub fn dec(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) void {
        switch (RegType) {
            i8 => {
                self.I8_REG[reg_idx] -%= 1;
            },
            i16 => {
                self.I16_REG[reg_idx] -%= 1;
            },
            i32 => {
                self.I32_REG[reg_idx] -%= 1;
            },
            i64 => {
                self.I64_REG[reg_idx] -%= 1;
            },
            i128 => {
                self.I128_REG[reg_idx] -%= 1;
            },
            u8 => {
                self.U8_REG[reg_idx] -%= 1;
            },
            u16 => {
                self.U16_REG[reg_idx] -%= 1;
            },
            u32 => {
                self.U32_REG[reg_idx] -%= 1;
            },
            u64 => {
                self.U64_REG[reg_idx] -%= 1;
            },
            u128 => {
                self.U128_REG[reg_idx] -%= 1;
            },
            f16 => {
                self.F16_REG[reg_idx] -= 1.0;
            },
            f32 => {
                self.F32_REG[reg_idx] -= 1.0;
            },
            f64 => {
                self.F64_REG[reg_idx] -= 1.0;
            },
            f128 => {
                self.F128_REG[reg_idx] -= 1.0;
            },
            else => @compileError("Unsupported register type"),
        }
    }

    // ========================================
    // == I/O INSTRUCTIONS (Higher-Level)
    // ========================================

    // STROUT: Print string literal (higher-level QOL feature)
    pub fn strout(message: []const u8) void {
        std.debug.print("{s}", .{message});
    }

    // FOUT: Formatted output (printf-style, higher-level QOL feature)
    pub fn fout(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize, comptime fmt: []const u8) void {
        const value = switch (RegType) {
            i8 => self.I8_REG[reg_idx],
            i16 => self.I16_REG[reg_idx],
            i32 => self.I32_REG[reg_idx],
            i64 => self.I64_REG[reg_idx],
            i128 => self.I128_REG[reg_idx],
            u8 => self.U8_REG[reg_idx],
            u16 => self.U16_REG[reg_idx],
            u32 => self.U32_REG[reg_idx],
            u64 => self.U64_REG[reg_idx],
            u128 => self.U128_REG[reg_idx],
            f16 => self.F16_REG[reg_idx],
            f32 => self.F32_REG[reg_idx],
            f64 => self.F64_REG[reg_idx],
            f128 => self.F128_REG[reg_idx],
            else => @compileError("Unsupported register type"),
        };
        std.debug.print(fmt, .{value});
    }

    // PRINT: Print register value without newline
    pub fn print(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) void {
        self.fout(RegType, reg_idx, "{d}");
    }

    // PRINTLN: Print register value with newline
    pub fn println(self: *_CORE_SYSTEM_, comptime RegType: type, reg_idx: usize) void {
        self.fout(RegType, reg_idx, "{d}\n");
    }
};
