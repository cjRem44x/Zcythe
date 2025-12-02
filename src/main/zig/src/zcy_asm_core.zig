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

    // -- Instructions -- // 
    //
    // LDD: Load data into register
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
};
