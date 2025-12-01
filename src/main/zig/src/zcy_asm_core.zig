const std = @import("std");

const _CORE_SYSTEM_ = struct {
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
};
