//! Zcythe AST  –  src/ast.zig
//!
//! Node type catalogue for the Zcythe parser.
//! All memory is owned by a caller-provided arena allocator; nodes never
//! heap-allocate independently.  Free the arena to release the entire tree.

const lexer = @import("lexer.zig");

/// Re-export Token so consumers only need to import ast.
pub const Token = lexer.Token;

// ═══════════════════════════════════════════════════════════════════════════
//  Type annotation
// ═══════════════════════════════════════════════════════════════════════════

/// A concrete type name, optionally array/pointer-qualified.
/// Examples: `T`, `[]T`, `*T`, `*val T` (const pointee).
pub const TypeAnn = struct {
    name:         Token,
    is_array:     bool,
    array_size:   ?Token = null,  // non-null for [N]T fixed-size arrays
    is_ptr:       bool = false,   // *T
    is_const_ptr: bool = false,   // *val T  (pointee is const)
};

// ═══════════════════════════════════════════════════════════════════════════
//  Variable-declaration kind
// ═══════════════════════════════════════════════════════════════════════════

pub const VarKind = enum {
    mut_implicit,   // x := expr
    mut_explicit,   // x : T = expr   or  x : []T = expr
    immut_implicit, // x :: expr
    immut_explicit, // x : T : expr   or  x : []T : expr
};

// ═══════════════════════════════════════════════════════════════════════════
//  Sub-structs
// ═══════════════════════════════════════════════════════════════════════════

pub const Param = struct {
    name:          Token,
    type_ann:      ?TypeAnn,
    /// Set when the param was declared with `@comptime T name`.
    /// Holds the user-supplied type-parameter identifier (e.g. `T`).
    comptime_type: ?Token = null,
};

pub const Block = struct {
    stmts: []*Node,
};

pub const Program = struct {
    items: []*Node,
};

pub const MainBlock = struct {
    body: Block,
};

pub const FnDecl = struct {
    name:     Token,
    params:   []Param,
    ret_type: ?TypeAnn,
    body:     Block,
};

pub const VarDecl = struct {
    name:     Token,
    kind:     VarKind,
    type_ann: ?TypeAnn,
    value:    *Node,
};

pub const RetStmt = struct {
    value: *Node,
};

pub const IfStmt = struct {
    cond:     *Node,
    then_blk: Block,
    else_blk: ?Block,
};

/// Optional range attached to a `for` loop: `start..end` or `start..=end`.
/// `end == null` means an open range (`0..`).
pub const RangeNode = struct {
    start:     *Node,
    end:       ?*Node,
    inclusive: bool,
};

/// `for elem [, idx] => iterable [, range] { body }`
pub const ForStmt = struct {
    elem:     ?Token,      // null when user wrote `_`
    idx:      ?Token,      // null when index not requested
    iterable: *Node,
    range:    ?RangeNode,
    body:     Block,
};

/// `while cond [=> do_expr] { body }`
pub const WhileStmt = struct {
    cond:    *Node,
    do_expr: ?*Node,
    body:    Block,
};

/// `loop init, cond, update { body }`  (C-style; emitted as scoped while)
pub const LoopStmt = struct {
    init:   *Node,
    cond:   *Node,
    update: *Node,
    body:   Block,
};

/// One arm of a `switch` statement: `pattern => { stmts }` or `_ => { stmts }`.
/// `pattern == null` means the wildcard arm (`_`).
pub const SwitchArm = struct {
    pattern: ?*Node,
    body:    Block,
};

/// `switch (subject) { arm, arm, … }`
pub const SwitchStmt = struct {
    subject: *Node,
    arms:    []SwitchArm,
};

/// One arm of a `catch` expression: `ErrorName => value` or `_ => value`.
/// `error_name == null` means the wildcard / else arm.
pub const CatchArm = struct {
    error_name: ?Token,
    value:      *Node,
};

/// `subject catch |err_bind| { arm, arm, … }`
pub const CatchExpr = struct {
    subject:  *Node,
    err_bind: ?Token,
    arms:     []CatchArm,
};

pub const BinaryExpr = struct {
    op:    Token,
    left:  *Node,
    right: *Node,
};

pub const UnaryExpr = struct {
    op:      Token,
    operand: *Node,
};

pub const CallExpr = struct {
    callee: *Node,
    args:   []*Node,
};

pub const FieldExpr = struct {
    object: *Node,
    field:  Token,
};

pub const ArrayLit = struct {
    elems: []*Node,
};

pub const StructField = struct {
    name:  Token,
    value: *Node,
};

pub const StructLit = struct {
    type_name: *Node,  // ident_expr or field_expr chain (e.g. a.Person)
    fields:    []StructField,
};

pub const DatField = struct {
    name:     Token,
    type_ann: TypeAnn,
};

pub const EnumVariant = struct {
    name:  Token,
    value: ?*Node,  // null for plain variants; set for `A = expr`
};

pub const EnumDecl = struct {
    name:         Token,
    backing_type: ?Token,  // null = plain enum; "str" = string-backed; int type = enum(T)
    variants:     []EnumVariant,
};

pub const DatDecl = struct {
    name:   Token,
    fields: []DatField,
};

pub const ClsExtends = struct {
    name:   Token,
    is_pub: bool,
};

pub const ClsField = struct {
    name:     Token,
    type_ann: TypeAnn,
    is_pub:   bool,
};

pub const ClsMethod = struct {
    name:     Token,
    params:   []Param,
    ret_type: ?TypeAnn,
    body:     Block,
    is_pub:   bool,
    is_ovrd:  bool,
};

pub const ClsMember = union(enum) {
    field:        ClsField,
    init_block:   Block,
    deinit_block: Block,
    method:       ClsMethod,
};

pub const ClsDecl = struct {
    name:       Token,
    extends:    ?ClsExtends,
    implements: []Token,
    members:    []ClsMember,
};

pub const FunExpr = struct {
    params:   []Param,
    ret_type: ?TypeAnn,
    body:     Block,
};

/// An expression paired with an explicit format specifier for stream output.
/// Produced when the parser sees `expr : fmt_spec` in a stream context.
/// `spec` is the raw user-supplied spec text (e.g. `".3f"`, `"d"`, `"s"`).
pub const FmtExpr = struct {
    value: *Node,
    spec:  []const u8,
};

/// `@ns::seg1::seg2(args)` — namespaced builtin call or constant.
/// `namespace` = the `@ns` token (e.g. `@math`, `@fs`, `@sys`).
/// `path`      = identifier tokens after each `::` (e.g. `["sqrt"]` or
///               `["FileReader", "open"]`).
pub const NsBuiltinExpr = struct {
    namespace: Token,
    path:      []Token,
};

/// `defer expr` statement.
pub const DeferStmt = struct {
    expr: *Node,
};

/// `@omp::parallel { body }` — spawns `max_threads()` Zig threads, each running body.
pub const OmpParallelStmt = struct {
    body: Block,
};

/// `@omp::for elem => start..end { body }` — parallel range loop, range split across threads.
pub const OmpForStmt = struct {
    elem:      Token,
    start:     *Node,
    end:       *Node,
    inclusive: bool,
    body:      Block,
};

/// `@test "name" { body }` — a named test block emitted as Zig `test "name" { … }`.
pub const TestDecl = struct {
    name: Token,  // string_lit token — the test name
    body: Block,
};

/// One field in a `heap` block: `[imu] name: *[imu] [[]T]`.
pub const HeapField = struct {
    name:          Token,
    base_type:     Token,  // the T in *T, *imu T, *[]T — a single ident token
    is_imu_field:  bool,   // `imu c: *i32` — the pointer cannot be reassigned
    is_imu_ptr:    bool,   // `*imu T`      — the pointee becomes immutable after first write
    is_slice_elem: bool,   // `*[]T` or `*T[]` — base_type is slice element type
};

/// `heap Name { field: *T, … }` — named heap-allocation block.
pub const HeapDecl = struct {
    name:   Token,
    fields: []HeapField,
};

// ═══════════════════════════════════════════════════════════════════════════
//  @xi — built-in OpenGL graphics framework (raylib backend)
// ═══════════════════════════════════════════════════════════════════════════

/// One named arm in a `win.frame { event => { body } }` or `win.keys { … }` block.
pub const XiArm = struct {
    event: []const u8,
    body:  Block,
};

/// `win.draw { stmts }` — wrapped draw block (BeginDrawing / EndDrawing).
pub const XiDrawBlock = struct {
    win:  *Node,
    body: Block,
};

/// `win.frame { arm => body, … }` / `win.keys { … }` / `win.mouse { … }` event block.
pub const XiEventBlock = struct {
    win:  *Node,
    kind: []const u8,   // "frame", "keys", "mouse"
    arms: []XiArm,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Node — the root tagged union
// ═══════════════════════════════════════════════════════════════════════════

pub const Node = union(enum) {
    program:      Program,
    main_block:   MainBlock,
    fn_decl:      FnDecl,
    var_decl:     VarDecl,
    block:        Block,
    ret_stmt:     RetStmt,
    if_stmt:      IfStmt,
    for_stmt:     ForStmt,
    while_stmt:   WhileStmt,
    loop_stmt:    LoopStmt,
    switch_stmt:  SwitchStmt,
    expr_stmt:    *Node,     // stand-alone expression used as a statement
    int_lit:      Token,
    float_lit:    Token,
    string_lit:   Token,
    char_lit:     Token,
    ident_expr:   Token,
    builtin_expr: Token,
    binary_expr:  BinaryExpr,
    unary_expr:   UnaryExpr,
    call_expr:    CallExpr,
    field_expr:   FieldExpr,
    array_lit:    ArrayLit,
    struct_lit:   StructLit,
    dat_decl:     DatDecl,
    cls_decl:     ClsDecl,
    fun_expr:        FunExpr,
    fmt_expr:        FmtExpr,
    catch_expr:      CatchExpr,
    ns_builtin_expr: NsBuiltinExpr,
    defer_stmt:      DeferStmt,
    range_expr:      RangeNode,
    enum_decl:       EnumDecl,
    enum_lit:        Token,  // `.VARIANT` — inferred-type enum literal
    omp_parallel:    OmpParallelStmt,
    omp_for:         OmpForStmt,
    test_decl:       TestDecl,
    heap_decl:       HeapDecl,
    xi_draw_block:   XiDrawBlock,
    xi_event_block:  XiEventBlock,
};
