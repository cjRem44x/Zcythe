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

/// A concrete type name, optionally array-qualified: `T` or `[]T`.
/// Nullable (`T?`) and error-union (`T!`) markers are deferred to a later version.
pub const TypeAnn = struct {
    name:     Token,
    is_array: bool,
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
    name:     Token,
    type_ann: ?TypeAnn,
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
    type_name: Token,
    fields:    []StructField,
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
};
