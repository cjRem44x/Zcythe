//! Zcythe CodeGen  –  src/codegen.zig
//!
//! Emits Zig source code from a Zcythe AST.
//! Caller creates any `std.io.AnyWriter`, passes it to `CodeGen.init`,
//! then calls `emit(root)`.  The arena that owns the AST is the caller's concern.
//!
//! Typical usage:
//! ```zig
//!     var buf: std.ArrayListUnmanaged(u8) = .empty;
//!     defer buf.deinit(allocator);
//!     var cg = CodeGen.init(buf.writer(allocator).any());
//!     try cg.emit(root);
//! ```

const std = @import("std");
const ast = @import("ast.zig");

// ═══════════════════════════════════════════════════════════════════════════
//  File-var kind — tracks @fs::FileReader/FileWriter/ByteReader/ByteWriter
// ═══════════════════════════════════════════════════════════════════════════

const FileVarKind = enum {
    file_reader,
    file_writer,
    byte_reader_little,
    byte_reader_big,
    byte_writer_little,
    byte_writer_big,
};

// ═══════════════════════════════════════════════════════════════════════════
//  CodeGen
// ═══════════════════════════════════════════════════════════════════════════

pub const CodeGen = struct {
    writer:        std.io.AnyWriter,
    indent_level:  usize,
    /// The innermost block currently being emitted.  Updated in
    /// `emitBlockStmts` so that `emitVarDecl` can scan siblings for
    /// reassignments and decide between `var` and `const`.
    current_block: ast.Block,
    /// Monotonically increasing counter used to generate unique buffer names
    /// for each `@cin >>` read site (e.g., `_cin_buf_0`, `_cin_buf_1`, …).
    cin_counter:   usize,
    /// Name of the innermost for-loop element variable, if any.
    /// Set in `emitForStmt` before entering the body so that `inferPfSpec`
    /// can choose the right format specifier (e.g. `{s}` for `[]str` arrays).
    loop_elem_name: ?[]const u8,
    /// The `@pf` format spec inferred for `loop_elem_name` (e.g. `"{s}"`).
    loop_elem_spec: ?[]const u8,
    /// Top-level program node, stored so `inferPfSpec` can look up dat_decl
    /// field types when interpolating field-access expressions (e.g. `{p.name}`).
    program: ?ast.Program,
    /// Cross-scope registry of variables declared via `@list(T)`.
    /// Allows `emitForStmt` and method-call remapping to recognise list vars
    /// from outer scopes where `current_block` lookup would not reach.
    list_var_names: [64][]const u8,
    list_var_count: usize,
    /// Cross-scope registry of variables opened via `@fs::FileReader::open`,
    /// `@fs::FileWriter::open`, `@fs::ByteReader::open`, `@fs::ByteWriter::open`.
    /// Allows method calls (`.rln()`, `.w()`, `.ri32()`, etc.) to be remapped.
    file_var_names: [64][]const u8,
    file_var_kinds: [64]FileVarKind,
    file_var_count: usize,

    // ─── Construction ──────────────────────────────────────────────────────

    pub fn init(writer: std.io.AnyWriter) CodeGen {
        return .{
            .writer         = writer,
            .indent_level   = 0,
            .current_block  = .{ .stmts = &.{} },
            .cin_counter    = 0,
            .loop_elem_name = null,
            .loop_elem_spec = null,
            .program        = null,
            .list_var_names = undefined,
            .list_var_count = 0,
            .file_var_names = undefined,
            .file_var_kinds = undefined,
            .file_var_count = 0,
        };
    }

    fn recordListVar(self: *CodeGen, name: []const u8) void {
        if (self.list_var_count < self.list_var_names.len) {
            self.list_var_names[self.list_var_count] = name;
            self.list_var_count += 1;
        }
    }

    fn isKnownListVar(self: *const CodeGen, name: []const u8) bool {
        for (self.list_var_names[0..self.list_var_count]) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    fn recordFileVar(self: *CodeGen, name: []const u8, kind: FileVarKind) void {
        if (self.file_var_count < self.file_var_names.len) {
            self.file_var_names[self.file_var_count] = name;
            self.file_var_kinds[self.file_var_count] = kind;
            self.file_var_count += 1;
        }
    }

    fn getFileVarKind(self: *const CodeGen, name: []const u8) ?FileVarKind {
        for (self.file_var_names[0..self.file_var_count], 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return self.file_var_kinds[i];
        }
        return null;
    }

    // ─── Public entry point ────────────────────────────────────────────────

    pub fn emit(self: *CodeGen, root: *const ast.Node) !void {
        switch (root.*) {
            .program => |p| try self.emitProgram(p),
            else     => return error.UnexpectedNode,
        }
    }

    // ─── Helpers ───────────────────────────────────────────────────────────

    /// Emit a user-supplied identifier, wrapping it in `@"…"` if it clashes
    /// with a Zig keyword.  Zcythe has its own (smaller) keyword set, so names
    /// like `var`, `const`, `type`, etc. are valid Zcythe identifiers but must
    /// be escaped in the generated Zig output.
    fn writeZigIdent(self: *CodeGen, name: []const u8) !void {
        // These are Zig built-in value keywords — they cannot be escaped as
        // @"name" and must be emitted verbatim (e.g. `while true`, `x == null`).
        const value_builtins = [_][]const u8{ "true", "false", "null", "undefined" };
        for (value_builtins) |b| {
            if (std.mem.eql(u8, name, b)) {
                try self.writer.writeAll(name);
                return;
            }
        }
        // Zcythe `undef` → Zig `undefined`
        if (std.mem.eql(u8, name, "undef")) {
            try self.writer.writeAll("undefined");
            return;
        }
        if (isZigKeyword(name)) {
            try self.writer.print("@\"{s}\"", .{name});
        } else {
            try self.writer.writeAll(name);
        }
    }

    /// Emit a dotted identifier path (e.g. `p.name`, `a.b.c`), escaping each
    /// segment that is a Zig keyword.  Used for `@pf` field-access interpolation.
    fn writeDottedIdent(self: *CodeGen, dotted: []const u8) !void {
        var it = std.mem.splitScalar(u8, dotted, '.');
        var first = true;
        while (it.next()) |part| {
            if (!first) try self.writer.writeByte('.');
            try self.writeZigIdent(part);
            first = false;
        }
    }

    fn writeIndent(self: *CodeGen) !void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.writer.writeAll("    ");
        }
    }

    /// Map a Zcythe type name to the corresponding Zig type string.
    fn mapType(name: []const u8) []const u8 {
        if (std.mem.eql(u8, name, "str"))  return "[]const u8";
        if (std.mem.eql(u8, name, "char")) return "u8";
        return name;
    }

    fn emitTypeAnn(self: *CodeGen, ta: ast.TypeAnn) !void {
        if (ta.is_array) {
            try self.writer.writeAll("[]");
        } else if (ta.is_ptr) {
            try self.writer.writeByte('*');
            if (ta.is_const_ptr) try self.writer.writeAll("const ");
        }
        try self.writer.writeAll(mapType(ta.name.lexeme));
    }

    /// Convert a user format spec (e.g. `.3f`, `d`, `s`) to the Zig format
    /// specifier portion written inside `{…}` (e.g. `d:.3`, `d`, `s`).
    /// Writes directly to the output writer.
    ///
    /// Mapping rules (printf-inspired → Zig):
    ///   last alpha char = type:  f/g → d,  d/i/u → d,  s → s,  x → x,  e → e
    ///   everything before the type = precision: `.3` → `:.3` in Zig
    fn emitZigFmtSpec(self: *CodeGen, user_spec: []const u8, default_type: []const u8) !void {
        if (user_spec.len == 0) {
            try self.writer.writeAll(default_type);
            return;
        }
        // Find last alphabetic char — that is the type letter.
        var type_pos: usize = user_spec.len; // sentinel = no type letter found
        var i: usize = user_spec.len;
        while (i > 0) {
            i -= 1;
            if (std.ascii.isAlphabetic(user_spec[i])) { type_pos = i; break; }
        }
        const precision = user_spec[0..type_pos];
        const type_char: u8 = if (type_pos < user_spec.len) user_spec[type_pos] else 0;
        const zig_type: []const u8 = switch (type_char) {
            'f', 'g'      => "d",
            'd', 'i', 'u' => "d",
            's'           => "s",
            'x'           => "x",
            'X'           => "X",
            'e'           => "e",
            0             => default_type,
            else          => "any",
        };
        try self.writer.writeAll(zig_type);
        if (precision.len > 0) {
            try self.writer.writeByte(':');
            try self.writer.writeAll(precision);
        }
    }

    /// Remap Zcythe operators that differ from Zig.
    fn remapOp(lexeme: []const u8) []const u8 {
        if (std.mem.eql(u8, lexeme, "&&")) return "and";
        if (std.mem.eql(u8, lexeme, "||")) return "or";
        return lexeme;
    }

    // ─── @import declarations ───────────────────────────────────────────────

    /// Emit one `const alias = @import("module.zig")[.Field];` line per arg.
    /// Each arg must be `alias = module` or `alias = module.Field` (binary_expr
    /// with op `=`).  Malformed args are silently skipped.
    fn emitImportDecl(self: *CodeGen, args: []*ast.Node) !void {
        for (args) |arg| {
            if (arg.* != .binary_expr) continue;
            const be = arg.binary_expr;
            if (!std.mem.eql(u8, be.op.lexeme, "=")) continue;
            if (be.left.* != .ident_expr) continue;
            const alias = be.left.ident_expr.lexeme;

            // Walk right side: ident → "mod.zig", field_expr → mod + field
            // binary `/` chains → path/to/mod.zig  (e.g. a/b → "a/b.zig")
            var mod_node = be.right;
            var field_tok: ?ast.Token = null;
            if (mod_node.* == .field_expr) {
                field_tok = mod_node.field_expr.field;
                mod_node  = mod_node.field_expr.object;
            }

            // ── zcy.<pkg>: Zcythe package namespace ───────────────────────
            // `rl = zcy.raylib` → `const rl = @import("raylib");`
            if (mod_node.* == .ident_expr and
                std.mem.eql(u8, mod_node.ident_expr.lexeme, "zcy"))
            {
                if (field_tok) |ft| {
                    try self.writer.writeAll("const ");
                    try self.writeZigIdent(alias);
                    try self.writer.writeAll(" = @import(\"");
                    try self.writer.writeAll(ft.lexeme);
                    try self.writer.writeAll("\");\n");
                    continue;
                }
            }

            // ── Standard local module import ──────────────────────────────
            try self.writer.writeAll("const ");
            try self.writeZigIdent(alias);
            try self.writer.writeAll(" = @import(\"");
            try self.emitImportPath(mod_node);
            try self.writer.writeAll(".zig\")");
            if (field_tok) |ft| {
                try self.writer.writeByte('.');
                try self.writeZigIdent(ft.lexeme);
            }
            try self.writer.writeAll(";\n");
        }
    }

    /// Emit a module path from an AST node.
    /// ident_expr        → writes the identifier  (e.g. util)
    /// binary_expr `/`   → recursively writes left/right (e.g. a/b → "a/b")
    fn emitImportPath(self: *CodeGen, node: *const ast.Node) anyerror!void {
        switch (node.*) {
            .ident_expr => |t| try self.writer.writeAll(t.lexeme),
            .binary_expr => |b| {
                if (!std.mem.eql(u8, b.op.lexeme, "/")) return;
                try self.emitImportPath(b.left);
                try self.writer.writeByte('/');
                try self.emitImportPath(b.right);
            },
            else => {},
        }
    }

    // ─── Dat declarations ──────────────────────────────────────────────────

    fn emitDatDecl(self: *CodeGen, dd: ast.DatDecl) !void {
        try self.writer.writeAll("pub const ");
        try self.writeZigIdent(dd.name.lexeme);
        try self.writer.writeAll(" = struct {\n");
        for (dd.fields) |field| {
            try self.writer.writeAll("    ");
            try self.writeZigIdent(field.name.lexeme);
            try self.writer.writeAll(": ");
            try self.emitTypeAnn(field.type_ann);
            try self.writer.writeAll(",\n");
        }
        try self.writer.writeAll("};\n");
    }

    // ─── Program ───────────────────────────────────────────────────────────

    fn emitProgram(self: *CodeGen, prog: ast.Program) !void {
        self.program = prog;
        try self.writer.writeAll("const std = @import(\"std\");\n");
        if (programUsesRl(prog)) {
            try self.writer.writeAll("const rl = @import(\"raylib\");\n");
        }
        // Runtime helper: map Zig type names to Zcythe user-visible type names.
        // Used by @typeOf(expr) → _zcyTypeName(@TypeOf(expr)).
        try self.writer.writeAll(
            \\fn _zcyTypeName(comptime T: type) []const u8 {
            \\    if (T == []const u8) return "str";
            \\    if (T == i32)        return "int";
            \\    if (T == i64)        return "int64";
            \\    if (T == u32)        return "uint";
            \\    if (T == u64)        return "uint64";
            \\    if (T == f32)        return "f32";
            \\    if (T == f64)        return "f64";
            \\    if (T == bool)       return "bool";
            \\    if (T == u8)         return "char";
            \\    return @typeName(T);
            \\}
            \\/// Type-dispatching print with newline.
            \\/// Chooses {s} for byte-slice types ([]u8, []const u8, [:0]u8, etc.)
            \\/// so loop variables over string collections print as text, not bytes.
            \\fn _zcyPrint(val: anytype) void {
            \\    const T = @TypeOf(val);
            \\    if (T == []const u8 or T == []u8 or T == [:0]u8 or T == [:0]const u8) {
            \\        std.debug.print("{s}\n", .{val});
            \\        return;
            \\    }
            \\    if (T == u8) {
            \\        std.debug.print("{c}\n", .{val});
            \\        return;
            \\    }
            \\    std.debug.print("{any}\n", .{val});
            \\}
            \\/// Type-dispatching print without trailing newline.
            \\/// Used by @pf field-access interpolation (e.g. {p.name}).
            \\fn _zcyPrintNoNl(val: anytype) void {
            \\    const T = @TypeOf(val);
            \\    if (T == []const u8 or T == []u8 or T == [:0]u8 or T == [:0]const u8) {
            \\        std.debug.print("{s}", .{val});
            \\        return;
            \\    }
            \\    if (T == u8) {
            \\        std.debug.print("{c}", .{val});
            \\        return;
            \\    }
            \\    std.debug.print("{any}", .{val});
            \\}
            \\/// Read a line from stdin, printing `prompt` first.
            \\/// Returns a heap-allocated slice (via page_allocator); leaks are
            \\/// acceptable for short-lived CLI programs.
            \\fn _zcyInput(prompt: []const u8) []const u8 {
            \\    std.debug.print("{s}", .{prompt});
            \\    var buf: [4096]u8 = undefined;
            \\    const line = std.fs.File.stdin().deprecatedReader()
            \\        .readUntilDelimiterOrEof(&buf, '\n') catch return "";
            \\    return std.heap.page_allocator.dupe(u8, line orelse "") catch return "";
            \\}
            \\fn _zcyFsIsFile(path: []const u8) bool {
            \\    const stat = std.fs.cwd().statFile(path) catch return false;
            \\    return stat.kind == .file;
            \\}
            \\fn _zcyFsIsDir(path: []const u8) bool {
            \\    var d = std.fs.cwd().openDir(path, .{}) catch return false;
            \\    d.close();
            \\    return true;
            \\}
            \\fn _zcyFsEof(f: std.fs.File) bool {
            \\    var buf: [1]u8 = undefined;
            \\    const n = f.read(&buf) catch return true;
            \\    if (n == 0) return true;
            \\    f.seekBy(-1) catch {};
            \\    return false;
            \\}
            \\fn _zcyMalloc(comptime T: type, n: usize) *T {
            \\    const s = std.heap.page_allocator.alloc(T, n) catch @panic("malloc failed");
            \\    return &s[0];
            \\}
            \\/// @rng(T, min, max) — inclusive random value in [min, max].
            \\/// Integer types use intRangeAtMost; float types scale a [0,1) float.
            \\fn _zcyRng(comptime T: type, min: T, max: T) T {
            \\    return switch (@typeInfo(T)) {
            \\        .float => min + std.crypto.random.float(T) * (max - min),
            \\        else   => std.crypto.random.intRangeAtMost(T, min, max),
            \\    };
            \\}
            \\
        );

        // Emit user @import declarations immediately after the std preamble
        for (prog.items) |item| {
            if (item.* != .expr_stmt) continue;
            const e = item.expr_stmt;
            if (e.* != .call_expr) continue;
            if (e.call_expr.callee.* != .builtin_expr) continue;
            if (!std.mem.eql(u8, e.call_expr.callee.builtin_expr.lexeme, "@import")) continue;
            try self.emitImportDecl(e.call_expr.args);
        }

        try self.writer.writeAll("\n");

        // Emit dat_decls, then fn_decls; collect @main for last
        var main_node: ?*const ast.Node = null;
        for (prog.items) |item| {
            if (item.* == .dat_decl) try self.emitDatDecl(item.dat_decl);
        }
        for (prog.items) |item| {
            switch (item.*) {
                .fn_decl    => try self.emitFnDecl(item.fn_decl),
                .main_block => main_node = item,
                else        => {},
            }
        }

        if (main_node) |mb| try self.emitMainBlock(mb.main_block);
    }

    // ─── @main block ───────────────────────────────────────────────────────

    fn emitMainBlock(self: *CodeGen, mb: ast.MainBlock) !void {
        try self.writer.writeAll("pub fn main() !void {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(mb.body);
        self.indent_level -= 1;
        try self.writer.writeAll("}\n");
    }

    // ─── Function declarations ─────────────────────────────────────────────

    fn emitFnDecl(self: *CodeGen, fn_d: ast.FnDecl) !void {
        try self.writer.writeAll("pub fn ");
        try self.writeZigIdent(fn_d.name.lexeme);
        try self.writer.writeByte('(');

        for (fn_d.params, 0..) |param, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitParam(param);
        }
        try self.writer.writeAll(") ");

        try self.emitFnReturnType(fn_d);

        try self.writer.writeAll(" {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(fn_d.body);
        self.indent_level -= 1;
        try self.writer.writeAll("}\n\n");
    }

    fn emitParam(self: *CodeGen, param: ast.Param) !void {
        // @comptime T name  →  comptime T: type, name: T
        if (param.comptime_type) |ct| {
            try self.writer.writeAll("comptime ");
            try self.writeZigIdent(ct.lexeme);
            try self.writer.writeAll(": type, ");
            try self.writeZigIdent(param.name.lexeme);
            try self.writer.writeAll(": ");
            try self.writeZigIdent(ct.lexeme);
            return;
        }
        try self.writeZigIdent(param.name.lexeme);
        try self.writer.writeAll(": ");
        if (param.type_ann) |ta| {
            try self.emitTypeAnn(ta);
        } else {
            try self.writer.writeAll("anytype");
        }
    }

    fn emitFnReturnType(self: *CodeGen, fn_d: ast.FnDecl) !void {
        // Explicit return type annotation
        if (fn_d.ret_type) |rt| {
            try self.emitTypeAnn(rt);
            return;
        }

        // No explicit return type — check whether any param is untyped
        var any_untyped = false;
        for (fn_d.params) |p| {
            if (p.type_ann == null) { any_untyped = true; break; }
        }

        if (any_untyped) {
            // Find best ret expr: prefer non-recursive calls to avoid Zig's
            // @TypeOf infinite-recursion segfault on functions like Fibonacci.
            if (findBestRetExpr(fn_d.body, fn_d.name.lexeme)) |expr| {
                try self.writer.writeAll("@TypeOf(");
                try self.emitExpr(expr);
                try self.writer.writeAll(")");
            } else {
                try self.writer.writeAll("void");
            }
        } else {
            // All params have types but no return annotation
            try self.writer.writeAll("void"); // TODO: infer return type
        }
    }

    /// Walk all statements recursively (including inside if_stmt branches) and
    /// return the first `ret` expression that does NOT call `fn_name` itself.
    /// Falls back to any ret expression when none are non-recursive.
    /// Returns null when there are no ret statements at all.
    fn findBestRetExpr(body: ast.Block, fn_name: []const u8) ?*const ast.Node {
        var any_ret: ?*const ast.Node = null;
        for (body.stmts) |stmt| {
            switch (stmt.*) {
                .ret_stmt => |rs| {
                    if (any_ret == null) any_ret = rs.value;
                    if (!exprCallsIdent(rs.value, fn_name)) return rs.value;
                },
                .if_stmt => |is| {
                    if (findBestRetExpr(is.then_blk, fn_name)) |e| {
                        if (!exprCallsIdent(e, fn_name)) return e;
                        if (any_ret == null) any_ret = e;
                    }
                    if (is.else_blk) |eb| {
                        if (findBestRetExpr(eb, fn_name)) |e| {
                            if (!exprCallsIdent(e, fn_name)) return e;
                            if (any_ret == null) any_ret = e;
                        }
                    }
                },
                else => {},
            }
        }
        return any_ret;
    }

    /// Return true if `node` (or any sub-expression) is a call whose callee
    /// is an ident matching `name`.
    fn exprCallsIdent(node: *const ast.Node, name: []const u8) bool {
        return switch (node.*) {
            .call_expr  => |ce| blk: {
                if (ce.callee.* == .ident_expr and
                    std.mem.eql(u8, ce.callee.ident_expr.lexeme, name))
                    break :blk true;
                for (ce.args) |a| { if (exprCallsIdent(a, name)) break :blk true; }
                break :blk exprCallsIdent(ce.callee, name);
            },
            .binary_expr => |be| exprCallsIdent(be.left, name) or exprCallsIdent(be.right, name),
            .unary_expr  => |ue| exprCallsIdent(ue.operand, name),
            else         => false,
        };
    }

    // ─── Blocks & statements ───────────────────────────────────────────────

    fn emitBlockStmts(self: *CodeGen, block: ast.Block) !void {
        const prev = self.current_block;
        self.current_block = block;
        defer self.current_block = prev;
        for (block.stmts) |stmt| try self.emitStmt(stmt);
    }

    fn emitStmt(self: *CodeGen, stmt: *const ast.Node) !void {
        switch (stmt.*) {
            .var_decl   => |vd| try self.emitVarDecl(vd),
            .ret_stmt   => |rs| try self.emitRetStmt(rs),
            .if_stmt    => |is| try self.emitIfStmt(is),
            .for_stmt   => |fs| try self.emitForStmt(fs),
            .while_stmt  => |ws| try self.emitWhileStmt(ws),
            .loop_stmt   => |ls| try self.emitLoopStmt(ls),
            .switch_stmt => |ss| try self.emitSwitchStmt(ss),
            .defer_stmt  => |ds| try self.emitDeferStmt(ds),
            .expr_stmt   => |es| try self.emitExprStmt(es),
            else         => {},
        }
    }

    fn emitDeferStmt(self: *CodeGen, ds: ast.DeferStmt) !void {
        try self.writeIndent();
        try self.writer.writeAll("defer ");
        try self.emitExpr(ds.expr);
        try self.writer.writeAll(";\n");
    }

    fn emitVarDecl(self: *CodeGen, vd: ast.VarDecl) !void {
        // `_ := expr` throwaway — Zig uses bare `_ = expr` with no var/const.
        if (std.mem.eql(u8, vd.name.lexeme, "_")) {
            try self.writeIndent();
            try self.writer.writeAll("_ = ");
            try self.emitExpr(vd.value);
            try self.writer.writeAll(";\n");
            return;
        }
        try self.writeIndent();
        const kw: []const u8 = switch (vd.kind) {
            // `let x: T = v` — user-explicit annotated declaration; auto-downgrade
            // to `const` when the variable is never reassigned (same as `:=`).
            // Using `const` for an unmodified pointer is still valid in Zig and
            // allows `pX.* = v` (pointee mutation does not require `var` pX).
            .kw_let => blk: {
                if (isListCall(vd.value)) break :blk "var";
                if (isReassignedInBlock(vd.name.lexeme, self.current_block))
                    break :blk "var"
                else
                    break :blk "const";
            },
            // Auto-downgrade mutable declarations to `const` when the variable
            // is never reassigned inside the same block.  This keeps generated
            // Zig valid even when the user writes `x := value` and never
            // mutates `x` — Zig would reject `var x = value` as an unused var.
            .mut_implicit, .mut_explicit => blk: {
                // @list creates an ArrayList — must be `var` so .append() works.
                if (isListCall(vd.value)) break :blk "var";
                if (isReassignedInBlock(vd.name.lexeme, self.current_block))
                    break :blk "var"
                else
                    break :blk "const";
            },
            .immut_implicit, .immut_explicit => "const",
        };
        try self.writer.writeAll(kw);
        try self.writer.writeByte(' ');
        try self.writeZigIdent(vd.name.lexeme);

        // Array type with array_lit value: var/const name = [_]T{...};
        if (vd.type_ann) |ta| {
            if (ta.is_array and vd.value.* == .array_lit) {
                try self.writer.writeAll(" = ");
                try self.emitArrayLitTyped(vd.value.array_lit, ta.name.lexeme);
                try self.writer.writeAll(";\n");
                return;
            }
            // Non-array explicit type annotation
            try self.writer.writeAll(": ");
            try self.emitTypeAnn(ta);
        } else if (vd.value.* == .string_lit) {
            // Implicit string type: Zcythe `str` = Zig `[]const u8`.
            // Without this, Zig infers `*const [N:0]u8` which is incompatible
            // with `{s}` format and makes `{any}` print raw bytes.
            try self.writer.writeAll(": []const u8");
        } else if (std.mem.eql(u8, kw, "var") and vd.value.* == .int_lit) {
            // `var x = 0` is rejected by Zig ("comptime_int must be const").
            // Default mutable integers to i64.
            try self.writer.writeAll(": i64");
        } else if (std.mem.eql(u8, kw, "var") and vd.value.* == .float_lit) {
            // Same issue for comptime_float.
            try self.writer.writeAll(": f64");
        } else if (isUndefExpr(vd.value)) {
            // `x := undef` — infer type from the first reassignment in this block.
            if (findReassignValue(vd.name.lexeme, self.current_block)) |rv| {
                if (rv.* == .string_lit or self.isStrExpr(rv)) {
                    try self.writer.writeAll(": []const u8");
                }
            }
        }

        try self.writer.writeAll(" = ");
        try self.emitExpr(vd.value);
        try self.writer.writeAll(";\n");

        // @list allocates an ArrayList — emit a paired defer to deinit it
        // and register the var name so outer-scope checks can find it.
        if (isListCall(vd.value)) {
            self.recordListVar(vd.name.lexeme);
            try self.writeIndent();
            try self.writer.writeAll("defer ");
            try self.writeZigIdent(vd.name.lexeme);
            try self.writer.writeAll(".deinit(std.heap.page_allocator);\n");
        }

        // @getArgs() allocates — emit a paired defer to free and to make the
        // variable "used" so the Zig compiler doesn't reject it.
        if (isGetArgs(vd.value)) {
            try self.writeIndent();
            try self.writer.writeAll("defer std.process.argsFree(std.heap.page_allocator, ");
            try self.writeZigIdent(vd.name.lexeme);
            try self.writer.writeAll(");\n");
        }

        // @fs::*::open — register the var so method calls can be remapped.
        self.tryRegisterFileVar(vd.name.lexeme, vd.value);
    }

    /// Walk `value` (unwrapping a `try` unary if present) to detect an
    /// `@fs::FileReader::open`, `@fs::FileWriter::open`, etc. call and register
    /// the given variable name in the file-var tracking table.
    fn tryRegisterFileVar(self: *CodeGen, name: []const u8, value: *const ast.Node) void {
        // Unwrap `try expr` → look at the inner call.
        const inner: *const ast.Node = if (value.* == .unary_expr and
            std.mem.eql(u8, value.unary_expr.op.lexeme, "try"))
            value.unary_expr.operand
        else
            value;

        if (inner.* != .call_expr) return;
        const ce = inner.call_expr;
        if (ce.callee.* != .ns_builtin_expr) return;
        const nb = ce.callee.ns_builtin_expr;
        if (!std.mem.eql(u8, nb.namespace.lexeme, "@fs")) return;
        if (nb.path.len != 2) return;
        if (!std.mem.eql(u8, nb.path[1].lexeme, "open")) return;

        const class = nb.path[0].lexeme;
        if (std.mem.eql(u8, class, "FileReader")) {
            self.recordFileVar(name, .file_reader);
        } else if (std.mem.eql(u8, class, "FileWriter")) {
            self.recordFileVar(name, .file_writer);
        } else if (std.mem.eql(u8, class, "ByteReader")) {
            const kind: FileVarKind = if (ce.args.len > 1 and isFsEndianBig(ce.args[1]))
                .byte_reader_big else .byte_reader_little;
            self.recordFileVar(name, kind);
        } else if (std.mem.eql(u8, class, "ByteWriter")) {
            const kind: FileVarKind = if (ce.args.len > 1 and isFsEndianBig(ce.args[1]))
                .byte_writer_big else .byte_writer_little;
            self.recordFileVar(name, kind);
        }
    }

    fn emitRetStmt(self: *CodeGen, rs: ast.RetStmt) !void {
        try self.writeIndent();
        try self.writer.writeAll("return ");
        try self.emitExpr(rs.value);
        try self.writer.writeAll(";\n");
    }

    fn emitIfStmt(self: *CodeGen, is: ast.IfStmt) anyerror!void {
        try self.writeIndent();
        try self.emitIfChain(is);
        try self.writer.writeByte('\n');
    }

    /// Emit the if/else chain without a leading indent or trailing newline so
    /// that `else if` can be appended inline after `}`.
    fn emitIfChain(self: *CodeGen, is: ast.IfStmt) anyerror!void {
        try self.writer.writeAll("if (");
        try self.emitExpr(is.cond);
        try self.writer.writeAll(") {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(is.then_blk);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}");
        if (is.else_blk) |eb| {
            // Single if_stmt in else → emit as `} else if (…) {` (no extra nesting).
            if (eb.stmts.len == 1 and eb.stmts[0].* == .if_stmt) {
                try self.writer.writeAll(" else ");
                try self.emitIfChain(eb.stmts[0].if_stmt);
            } else {
                try self.writer.writeAll(" else {\n");
                self.indent_level += 1;
                try self.emitBlockStmts(eb);
                self.indent_level -= 1;
                try self.writeIndent();
                try self.writer.writeAll("}");
            }
        }
    }

    // ─── Loop statements ───────────────────────────────────────────────────

    /// `for e, i => iterable, 0.. { body }`
    /// → `for (iterable, 0..) |e, i| { body }`
    fn emitForStmt(self: *CodeGen, fs: ast.ForStmt) anyerror!void {
        try self.writeIndent();
        try self.writer.writeAll("for (");

        if (fs.range) |r| {
            if (fs.idx == null) {
                // No index capture → slice the iterable: iterable[start..end]
                try self.emitExpr(fs.iterable);
                try self.writer.writeByte('[');
                try self.emitExpr(r.start);
                try self.writer.writeAll(if (r.inclusive) "..=" else "..");
                if (r.end) |end| try self.emitExpr(end);
                try self.writer.writeByte(']');
            } else {
                // Index capture present → parallel iteration: iterable, start..end
                try self.emitExpr(fs.iterable);
                try self.writer.writeAll(", ");
                try self.emitExpr(r.start);
                try self.writer.writeAll(if (r.inclusive) "..=" else "..");
                if (r.end) |end| try self.emitExpr(end);
            }
        } else {
            try self.emitExpr(fs.iterable);
            // ArrayList must be iterated via .items
            if (self.isListIdent(fs.iterable)) try self.writer.writeAll(".items");
            if (fs.idx != null) {
                // Index requested but no explicit range — auto-add `0..`
                try self.writer.writeAll(", 0..");
            }
        }

        try self.writer.writeAll(") |");
        if (fs.elem) |e| try self.writeZigIdent(e.lexeme) else try self.writer.writeAll("_");
        if (fs.idx) |i| {
            try self.writer.writeAll(", ");
            try self.writeZigIdent(i.lexeme);
        }
        try self.writer.writeAll("| {\n");
        self.indent_level += 1;
        // Inform inferPfSpec about the element variable's type for @pf inside the body.
        const prev_elem_name = self.loop_elem_name;
        const prev_elem_spec = self.loop_elem_spec;
        defer { self.loop_elem_name = prev_elem_name; self.loop_elem_spec = prev_elem_spec; }
        if (fs.elem) |elem| {
            self.loop_elem_name = elem.lexeme;
            self.loop_elem_spec = self.inferIterElemSpec(fs.iterable);
        }
        try self.emitBlockStmts(fs.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
    }

    /// Infer the `@pf` format spec for a single element drawn from `iterable`.
    /// Looks up the iterable's var_decl in the current block to check its type.
    fn inferIterElemSpec(self: *const CodeGen, iterable: *const ast.Node) []const u8 {
        if (iterable.* != .ident_expr) return "{any}";
        const iter_name = iterable.ident_expr.lexeme;
        for (self.current_block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            if (!std.mem.eql(u8, vd.name.lexeme, iter_name)) continue;
            // Explicit element type: []str → {s}
            if (vd.type_ann) |ta| {
                if (std.mem.eql(u8, ta.name.lexeme, "str")) return "{s}";
                return "{any}";
            }
            // Array literal of string literals → element is str
            if (vd.value.* == .array_lit) {
                const al = vd.value.array_lit;
                if (al.elems.len > 0 and al.elems[0].* == .string_lit) return "{s}";
            }
            return "{any}";
        }
        return "{any}";
    }

    /// `while cond { body }` / `while cond => do_expr { body }`
    /// → `while (cond) { }` / `while (cond) : (do_expr) { }`
    fn emitWhileStmt(self: *CodeGen, ws: ast.WhileStmt) anyerror!void {
        try self.writeIndent();
        try self.writer.writeAll("while (");
        try self.emitExpr(ws.cond);
        try self.writer.writeByte(')');
        if (ws.do_expr) |de| {
            try self.writer.writeAll(" : (");
            try self.emitExpr(de);
            try self.writer.writeByte(')');
        }
        try self.writer.writeAll(" {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(ws.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
    }

    /// `loop init, cond, update { body }`
    /// → `{ var init; while (cond) : (update) { body } }`
    fn emitLoopStmt(self: *CodeGen, ls: ast.LoopStmt) anyerror!void {
        // Wrap in a block to scope the init variable.
        try self.writeIndent();
        try self.writer.writeAll("{\n");
        self.indent_level += 1;
        try self.emitStmt(ls.init);
        try self.writeIndent();
        try self.writer.writeAll("while (");
        try self.emitExpr(ls.cond);
        try self.writer.writeAll(") : (");
        try self.emitExpr(ls.update);
        try self.writer.writeAll(") {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(ls.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
    }

    /// `switch (subject) { "x" => { stmts }, _ => { stmts } }`
    /// Emitted as an if/else-if chain (Zig switch doesn't support strings).
    fn emitSwitchStmt(self: *CodeGen, ss: ast.SwitchStmt) anyerror!void {
        try self.writeIndent();
        var first = true;
        for (ss.arms) |arm| {
            if (arm.pattern == null) {
                // Wildcard `_` → else branch
                try self.writer.writeAll(" else {\n");
            } else {
                if (!first) try self.writer.writeAll(" else ");
                try self.writer.writeAll("if (");
                if (arm.pattern.?.* == .string_lit) {
                    try self.writer.writeAll("std.mem.eql(u8, ");
                    try self.emitExpr(ss.subject);
                    try self.writer.writeAll(", ");
                    try self.emitExpr(arm.pattern.?);
                    try self.writer.writeByte(')');
                } else {
                    try self.emitExpr(ss.subject);
                    try self.writer.writeAll(" == ");
                    try self.emitExpr(arm.pattern.?);
                }
                try self.writer.writeAll(") {\n");
                first = false;
            }
            self.indent_level += 1;
            try self.emitBlockStmts(arm.body);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.writer.writeByte('}');
        }
        try self.writer.writeByte('\n');
    }

    /// `subject catch |err_bind| { ErrName => value, _ => value }`
    /// → `subject catch |err_bind| switch (err_bind) { error.ErrName => value, else => value }`
    fn emitCatchExpr(self: *CodeGen, ce: ast.CatchExpr) anyerror!void {
        // For numeric-cast subjects, emit without the `catch 0` wrapper so
        // the error union is preserved for the catch to handle.
        if (ce.subject.* == .call_expr) {
            const cc = ce.subject.call_expr;
            if (cc.callee.* == .builtin_expr and cc.args.len > 0 and
                self.isStrExpr(cc.args[0]))
            {
                const bname = cc.callee.builtin_expr.lexeme;
                const int_casts = [_][]const u8{
                    "@i8","@i16","@i32","@i64","@i128",
                    "@u8","@u16","@u32","@u64","@u128","@usize","@isize",
                };
                for (int_casts) |cast| {
                    if (std.mem.eql(u8, bname, cast)) {
                        try self.writer.print("std.fmt.parseInt({s}, ", .{cast[1..]});
                        try self.emitExpr(cc.args[0]);
                        try self.writer.writeAll(", 10)");
                        return self.writeCatchArms(ce, cast[1..]);
                    }
                }
                const float_casts = [_][]const u8{ "@f32", "@f64", "@f128" };
                for (float_casts) |cast| {
                    if (std.mem.eql(u8, bname, cast)) {
                        try self.writer.print("std.fmt.parseFloat({s}, ", .{cast[1..]});
                        try self.emitExpr(cc.args[0]);
                        try self.writer.writeByte(')');
                        return self.writeCatchArms(ce, cast[1..]);
                    }
                }
            }
        }
        try self.emitExpr(ce.subject);
        try self.writeCatchArms(ce, null);
    }

    /// Emit the `catch |bind| switch (bind) { … }` suffix.
    /// `default_type`: when non-null, arms whose value is a void call (@pl etc.)
    /// are wrapped in a labeled block that runs the side-effect then breaks with
    /// `@as(T, 0)` so the switch stays type-consistent (e.g. for numeric casts).
    fn writeCatchArms(self: *CodeGen, ce: ast.CatchExpr, default_type: ?[]const u8) anyerror!void {
        const bind = if (ce.err_bind) |b| b.lexeme else "_zcyerr";
        try self.writer.print(" catch |{s}| switch ({s}) {{\n", .{ bind, bind });
        self.indent_level += 1;
        for (ce.arms) |arm| {
            try self.writeIndent();
            if (arm.error_name) |en| {
                try self.writer.print("error.{s} => ", .{mapZcyError(en.lexeme)});
            } else {
                try self.writer.writeAll("else => ");
            }
            // A void-returning call (e.g. @pl) can't be a switch-arm value.
            // Wrap it: `blk: { side_effect; break :blk @as(T, 0); }`.
            if (default_type != null and isVoidProducingCall(arm.value)) {
                try self.writer.writeAll("blk: { ");
                try self.emitExpr(arm.value);
                try self.writer.print("; break :blk @as({s}, 0); }}", .{default_type.?});
            } else {
                try self.emitExpr(arm.value);
            }
            try self.writer.writeAll(",\n");
        }
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeByte('}');
    }

    fn emitExprStmt(self: *CodeGen, expr: *const ast.Node) !void {
        // @cout << … chains expand into one print statement per segment.
        if (isCoutChain(expr)) {
            try self.emitCoutChain(expr);
            return;
        }
        // @cin >> … chains expand into readUntilDelimiterOrEof calls.
        if (isCinChain(expr)) {
            try self.emitCinChain(expr);
            return;
        }
        // @pf("…{p.name}…") with field-access interpolation: multi-call expansion.
        if (isPfFieldInterp(expr)) {
            try self.emitPfMultiCall(expr.call_expr.args[0].string_lit.lexeme);
            return;
        }
        try self.writeIndent();
        try self.emitExpr(expr);
        try self.writer.writeAll(";\n");
    }

    /// Recursively walk a `@cin >> x >> y` chain (left-recursive) and emit
    /// a uniquely-named stack buffer + `readUntilDelimiterOrEof` for each `>>`.
    fn emitCinChain(self: *CodeGen, node: *const ast.Node) anyerror!void {
        if (node.* == .builtin_expr) return; // base: bare @cin — nothing to emit
        const be = node.binary_expr;
        try self.emitCinChain(be.left); // earlier reads first
        try self.writeIndent();
        const n = self.cin_counter;
        self.cin_counter += 1;
        try self.writer.print(
            "var _cin_buf_{d}: [4096]u8 = undefined;\n",
            .{n},
        );
        try self.writeIndent();
        try self.emitExpr(be.right); // variable name (ident_expr)
        try self.writer.print(
            " = (try std.fs.File.stdin().deprecatedReader().readUntilDelimiterOrEof(&_cin_buf_{d}, '\\n')) orelse \"\";\n",
            .{n},
        );
    }

    /// Recursively walk a `@cout << a << b << c` chain (left-recursive) and
    /// emit one `std.debug.print(…);\n` call per `<<` segment.
    fn emitCoutChain(self: *CodeGen, node: *const ast.Node) !void {
        if (node.* == .builtin_expr) return; // base: bare @cout — nothing to emit
        const be = node.binary_expr;
        try self.emitCoutChain(be.left); // earlier segments first
        try self.writeIndent();
        if (be.right.* == .builtin_expr and
            std.mem.eql(u8, be.right.builtin_expr.lexeme, "@endl"))
        {
            // @endl → newline character
            try self.writer.writeAll("std.debug.print(\"\\n\", .{});\n");
        } else if (be.right.* == .fmt_expr) {
            // expr:spec  (e.g. y:.3f) — emit with explicit Zig format spec
            const fe = be.right.fmt_expr;
            const default_type: []const u8 = if (fe.value.* == .string_lit) "s" else "d";
            try self.writer.writeAll("std.debug.print(\"{");
            try self.emitZigFmtSpec(fe.spec, default_type);
            try self.writer.writeAll("}\", .{");
            try self.emitExpr(fe.value);
            try self.writer.writeAll("});\n");
        } else if (isStringLike(be.right)) {
            try self.writer.writeAll("std.debug.print(\"{s}\", .{");
            try self.emitExpr(be.right);
            try self.writer.writeAll("});\n");
        } else {
            try self.writer.writeAll("_zcyPrintNoNl(");
            try self.emitExpr(be.right);
            try self.writer.writeAll(");\n");
        }
    }

    // ─── Expressions ───────────────────────────────────────────────────────

    // Explicit anyerror!void required to break the inference cycle:
    //   emitExpr → emitBinaryExpr → emitExpr
    //   emitExpr → emitFunExpr → emitBlockStmts → … → emitExpr
    fn emitExpr(self: *CodeGen, node: *const ast.Node) anyerror!void {
        switch (node.*) {
            .int_lit      => |t|  try self.writer.writeAll(t.lexeme),
            .float_lit    => |t|  try self.writer.writeAll(t.lexeme),
            .string_lit   => |t|  try self.writer.writeAll(t.lexeme),
            .char_lit     => |t|  try self.writer.writeAll(t.lexeme),
            .ident_expr   => |t|  try self.writeZigIdent(t.lexeme),
            .builtin_expr => |t|  try self.writer.writeAll(t.lexeme),
            .binary_expr  => |be| try self.emitBinaryExpr(be),
            .unary_expr   => |ue| try self.emitUnaryExpr(ue),
            .call_expr    => |ce| try self.emitCallExpr(ce),
            .field_expr   => |fe| try self.emitFieldExpr(fe),
            .array_lit    => |al| try self.emitArrayLit(al),
            .struct_lit   => |sl| try self.emitStructLit(sl),
            .fun_expr     => |fe| try self.emitFunExpr(fe),
            .fmt_expr        => |fe| try self.emitExpr(fe.value), // spec only meaningful in stream context
            .catch_expr      => |ce| try self.emitCatchExpr(ce),
            .ns_builtin_expr => |nb| try self.emitNsBuiltinExpr(nb),
            else             => {},
        }
    }

    /// Emit a `fun` expression as `struct { fn call(params) RetType { body } }.call`.
    /// This lets a `fun` literal appear in any expression position (variable
    /// initialiser, function argument, etc.) while still being callable.
    fn emitFunExpr(self: *CodeGen, fe: ast.FunExpr) anyerror!void {
        try self.writer.writeAll("struct { fn call(");
        for (fe.params, 0..) |param, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitParam(param);
        }
        try self.writer.writeAll(") ");

        // Inline return-type logic (mirrors emitFnReturnType for FnDecl).
        if (fe.ret_type) |rt| {
            try self.emitTypeAnn(rt);
        } else {
            var any_untyped = false;
            for (fe.params) |p| {
                if (p.type_ann == null) { any_untyped = true; break; }
            }
            if (any_untyped) {
                if (findBestRetExpr(fe.body, "")) |expr| {
                    try self.writer.writeAll("@TypeOf(");
                    try self.emitExpr(expr);
                    try self.writer.writeAll(")");
                } else {
                    try self.writer.writeAll("void");
                }
            } else {
                try self.writer.writeAll("void");
            }
        }

        try self.writer.writeAll(" {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(fe.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("} }.call");
    }

    fn emitBinaryExpr(self: *CodeGen, be: ast.BinaryExpr) !void {
        const op = be.op.lexeme;
        // String equality: `a == b` / `a != b` where either side is a string →
        // emit `std.mem.eql(u8, a, b)` / `!std.mem.eql(u8, a, b)`.
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=")) {
            if (self.isStrExpr(be.left) or self.isStrExpr(be.right)) {
                if (std.mem.eql(u8, op, "!=")) try self.writer.writeByte('!');
                try self.writer.writeAll("std.mem.eql(u8, ");
                try self.emitExpr(be.left);
                try self.writer.writeAll(", ");
                try self.emitExpr(be.right);
                try self.writer.writeByte(')');
                return;
            }
        }
        // Always wrap sub-binary-expressions in parens to preserve source grouping.
        if (be.left.* == .binary_expr) {
            try self.writer.writeByte('(');
            try self.emitExpr(be.left);
            try self.writer.writeByte(')');
        } else {
            try self.emitExpr(be.left);
        }
        try self.writer.writeByte(' ');
        try self.writer.writeAll(remapOp(op));
        try self.writer.writeByte(' ');
        if (be.right.* == .binary_expr) {
            try self.writer.writeByte('(');
            try self.emitExpr(be.right);
            try self.writer.writeByte(')');
        } else {
            try self.emitExpr(be.right);
        }
    }

    /// Return true when `node` is known to produce a `[]const u8` (string) value.
    /// Checks: string literals, and identifiers declared as `str` or initialized
    /// with a string literal in the current block.
    fn isStrExpr(self: *const CodeGen, node: *const ast.Node) bool {
        if (node.* == .string_lit) return true;
        // @input always returns []const u8
        if (node.* == .call_expr) {
            const ce = node.call_expr;
            if (ce.callee.* == .builtin_expr and
                std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@input"))
                return true;
        }
        if (node.* != .ident_expr) return false;
        const name = node.ident_expr.lexeme;
        for (self.current_block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            if (!std.mem.eql(u8, vd.name.lexeme, name)) continue;
            if (vd.type_ann) |ta| {
                if (std.mem.eql(u8, ta.name.lexeme, "str")) return true;
            }
            if (vd.value.* == .string_lit) return true;
            return false;
        }
        return false;
    }

    /// Return true when `node` is an identifier declared via `@list(...)`.
    /// Checks the current block first, then the cross-scope registry so that
    /// list vars from outer scopes are still recognised.
    fn isListIdent(self: *const CodeGen, node: *const ast.Node) bool {
        if (node.* != .ident_expr) return false;
        const name = node.ident_expr.lexeme;
        for (self.current_block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            if (!std.mem.eql(u8, vd.name.lexeme, name)) continue;
            return isListCall(vd.value);
        }
        return self.isKnownListVar(name);
    }

    // ─── Namespaced builtins ───────────────────────────────────────────────

    /// Emit an `@ns::path` expression in non-call position (e.g. `@math::pi`,
    /// `@fs::Little`).  Call position is handled by `emitNsBuiltinCall`.
    fn emitNsBuiltinExpr(self: *CodeGen, nb: ast.NsBuiltinExpr) !void {
        const ns = nb.namespace.lexeme;
        if (std.mem.eql(u8, ns, "@math")) {
            if (nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "pi")) {
                try self.writer.writeAll("std.math.pi");
                return;
            }
        }
        if (std.mem.eql(u8, ns, "@fs")) {
            if (nb.path.len == 1) {
                const seg = nb.path[0].lexeme;
                if (std.mem.eql(u8, seg, "Little") or std.mem.eql(u8, seg, "Litlle")) {
                    try self.writer.writeAll(".little"); return;
                }
                if (std.mem.eql(u8, seg, "Big")) {
                    try self.writer.writeAll(".big"); return;
                }
            }
        }
        // Fallback: strip '@', join with '.'
        try self.writer.writeAll(ns[1..]);
        for (nb.path) |seg| {
            try self.writer.writeByte('.');
            try self.writer.writeAll(seg.lexeme);
        }
    }

    /// Emit an `@ns::path(args)` call expression.
    fn emitNsBuiltinCall(self: *CodeGen, nb: ast.NsBuiltinExpr, args: []*ast.Node) !void {
        const ns = nb.namespace.lexeme;

        // ── @math:: ──────────────────────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@math") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;
            if (std.mem.eql(u8, fn_name, "sqrt")) {
                try self.writer.writeAll("std.math.sqrt(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "exp")) {
                // @math::exp(base, exp) → std.math.pow(f64, base, exp)
                // Always use f64 to avoid comptime_float issues with literal args.
                try self.writer.writeAll("std.math.pow(f64, ");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "abs")) {
                try self.writer.writeAll("@abs(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "min")) {
                try self.writer.writeAll("@min(");
                for (args, 0..) |a, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(a); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "max")) {
                try self.writer.writeAll("@max(");
                for (args, 0..) |a, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(a); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "floor")) {
                try self.writer.writeAll("@floor(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "ceil")) {
                try self.writer.writeAll("@ceil(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "log")) {
                try self.writer.writeAll("std.math.log(f64, std.math.e, ");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "log2")) {
                try self.writer.writeAll("std.math.log2(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "log10")) {
                try self.writer.writeAll("std.math.log10(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "sin")) {
                try self.writer.writeAll("@sin(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "cos")) {
                try self.writer.writeAll("@cos(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "tan")) {
                try self.writer.writeAll("std.math.tan(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            // Unknown @math:: — fall through to std.math.*
            try self.writer.writeAll("std.math.");
            try self.writer.writeAll(fn_name);
            try self.writer.writeByte('(');
            for (args, 0..) |a, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(a); }
            try self.writer.writeByte(')');
            return;
        }

        // ── @sys:: ───────────────────────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@sys")) {
            if (nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "exit")) {
                try self.writer.writeAll("std.process.exit(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @fs:: ────────────────────────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@fs")) {
            if (nb.path.len == 1) {
                const seg = nb.path[0].lexeme;
                if (std.mem.eql(u8, seg, "path")) {
                    // @fs::path("x") is identity — just emit the string arg.
                    if (args.len > 0) try self.emitExpr(args[0]);
                    return;
                }
                if (std.mem.eql(u8, seg, "isFile")) {
                    try self.writer.writeAll("_zcyFsIsFile(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, seg, "isDir")) {
                    try self.writer.writeAll("_zcyFsIsDir(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
            }
            if (nb.path.len == 2) {
                const class  = nb.path[0].lexeme;
                const method = nb.path[1].lexeme;
                if (std.mem.eql(u8, method, "open")) {
                    if (std.mem.eql(u8, class, "FileReader")) {
                        try self.writer.writeAll("std.fs.cwd().openFile(");
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                    if (std.mem.eql(u8, class, "FileWriter")) {
                        try self.writer.writeAll("std.fs.cwd().createFile(");
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                    if (std.mem.eql(u8, class, "ByteReader") or
                        std.mem.eql(u8, class, "ByteWriter"))
                    {
                        const open_fn = if (std.mem.eql(u8, class, "ByteReader"))
                            "std.fs.cwd().openFile(" else "std.fs.cwd().createFile(";
                        try self.writer.writeAll(open_fn);
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                }
            }
        }

        // Fallback: unknown namespace call — emit as dotted path call.
        try self.emitNsBuiltinExpr(nb);
        try self.writer.writeByte('(');
        for (args, 0..) |a, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(a); }
        try self.writer.writeByte(')');
    }

    /// Emit a method call on a tracked file/byte-reader/writer variable.
    fn emitFileVarMethod(self: *CodeGen, obj: *const ast.Node, method: []const u8, kind: FileVarKind, args: []*ast.Node) !void {
        switch (kind) {
            .file_reader => {
                if (std.mem.eql(u8, method, "rln")) {
                    try self.writer.writeAll("(try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".deprecatedReader().readUntilDelimiterOrEofAlloc(std.heap.page_allocator, '\\n', 4096)) orelse \"\"");
                    return;
                }
                if (std.mem.eql(u8, method, "rch")) {
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".deprecatedReader().readByte()");
                    return;
                }
                if (std.mem.eql(u8, method, "rall")) {
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".deprecatedReader().readAllAlloc(std.heap.page_allocator, std.math.maxInt(usize))");
                    return;
                }
                if (std.mem.eql(u8, method, "r")) {
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".deprecatedReader().readBytesNoEof(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, method, "eof")) {
                    // `reader.eof()` in Zcythe means "has more data to read"
                    // (i.e. NOT at end-of-file) — negate the helper.
                    try self.writer.writeAll("!_zcyFsEof(");
                    try self.emitExpr(obj);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, method, "cl") or std.mem.eql(u8, method, "close")) {
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".close()");
                    return;
                }
            },
            .file_writer => {
                if (std.mem.eql(u8, method, "w")) {
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".writeAll(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, method, "wln")) {
                    // Two Zig writeAll calls — inline; emitExprStmt appends the final ";\n"
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".writeAll(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll("); try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".writeAll(\"\\n\")");
                    return;
                }
                if (std.mem.eql(u8, method, "wch")) {
                    // std.fs.File has no writeByte; use writeAll with a 1-byte slice
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".writeAll(&[_]u8{");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll("})");
                    return;
                }
                if (std.mem.eql(u8, method, "fl")) {
                    try self.writer.writeAll("try ");
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".sync()");
                    return;
                }
                if (std.mem.eql(u8, method, "cl") or std.mem.eql(u8, method, "close")) {
                    try self.emitExpr(obj);
                    try self.writer.writeAll(".close()");
                    return;
                }
            },
            .byte_reader_little, .byte_reader_big => {
                const endian: []const u8 = if (kind == .byte_reader_little) ".little" else ".big";
                const int_map = [_][2][]const u8{
                    .{ "ri8",   "i8"   }, .{ "ru8",   "u8"   },
                    .{ "ri16",  "i16"  }, .{ "ru16",  "u16"  },
                    .{ "ri32",  "i32"  }, .{ "ru32",  "u32"  },
                    .{ "ri64",  "i64"  }, .{ "ru64",  "u64"  },
                    .{ "ri128", "i128" }, .{ "ru128", "u128" },
                };
                for (int_map) |entry| {
                    if (std.mem.eql(u8, method, entry[0])) {
                        try self.writer.writeAll("try ");
                        try self.emitExpr(obj);
                        try self.writer.print(".deprecatedReader().readInt({s}, {s})", .{ entry[1], endian });
                        return;
                    }
                }
                const float_map = [_][2][]const u8{
                    .{ "rf16", "f16" }, .{ "rf32", "f32" },
                    .{ "rf64", "f64" }, .{ "rf128", "f128" },
                };
                for (float_map) |entry| {
                    if (std.mem.eql(u8, method, entry[0])) {
                        try self.writer.writeAll("try ");
                        try self.emitExpr(obj);
                        try self.writer.print(".deprecatedReader().readFloat({s})", .{entry[1]});
                        return;
                    }
                }
                if (std.mem.eql(u8, method, "cl") or std.mem.eql(u8, method, "close")) {
                    try self.emitExpr(obj); try self.writer.writeAll(".close()"); return;
                }
            },
            .byte_writer_little, .byte_writer_big => {
                const endian: []const u8 = if (kind == .byte_writer_little) ".little" else ".big";
                const int_map = [_][2][]const u8{
                    .{ "wi8",   "i8"   }, .{ "wu8",   "u8"   },
                    .{ "wi16",  "i16"  }, .{ "wu16",  "u16"  },
                    .{ "wi32",  "i32"  }, .{ "wu32",  "u32"  },
                    .{ "wi64",  "i64"  }, .{ "wu64",  "u64"  },
                    .{ "wi128", "i128" }, .{ "wu128", "u128" },
                };
                for (int_map) |entry| {
                    if (std.mem.eql(u8, method, entry[0])) {
                        try self.writer.writeAll("try ");
                        try self.emitExpr(obj);
                        try self.writer.print(".deprecatedWriter().writeInt({s}, ", .{entry[1]});
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.print(", {s})", .{endian});
                        return;
                    }
                }
                const float_map = [_][2][]const u8{
                    .{ "wf16", "f16" }, .{ "wf32", "f32" },
                    .{ "wf64", "f64" }, .{ "wf128", "f128" },
                };
                for (float_map) |entry| {
                    if (std.mem.eql(u8, method, entry[0])) {
                        try self.writer.writeAll("try ");
                        try self.emitExpr(obj);
                        try self.writer.print(".deprecatedWriter().writeFloat({s}, ", .{entry[1]});
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeByte(')');
                        return;
                    }
                }
                if (std.mem.eql(u8, method, "cl") or std.mem.eql(u8, method, "close")) {
                    try self.emitExpr(obj); try self.writer.writeAll(".close()"); return;
                }
            },
        }
        // Fallback: unknown method — pass through.
        try self.emitExpr(obj);
        try self.writer.writeByte('.');
        try self.writer.writeAll(method);
        try self.writer.writeByte('(');
        for (args, 0..) |a, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(a); }
        try self.writer.writeByte(')');
    }

    fn emitUnaryExpr(self: *CodeGen, ue: ast.UnaryExpr) !void {
        // `try @fs::path(x)` — @fs::path is identity (returns a plain string,
        // not an error union).  Strip the `try` and emit just the argument.
        if (std.mem.eql(u8, ue.op.lexeme, "try") and ue.operand.* == .call_expr) {
            const ce = ue.operand.call_expr;
            if (ce.callee.* == .ns_builtin_expr) {
                const nb = ce.callee.ns_builtin_expr;
                if (std.mem.eql(u8, nb.namespace.lexeme, "@fs") and
                    nb.path.len == 1 and
                    std.mem.eql(u8, nb.path[0].lexeme, "path"))
                {
                    // Just emit the argument — no try.
                    if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                    return;
                }
            }
        }
        // `try @iN/@uN/@fN(str)` — emit as `try std.fmt.parseInt/parseFloat`
        // without the `catch 0` fallback, so the error propagates.
        if (std.mem.eql(u8, ue.op.lexeme, "try") and ue.operand.* == .call_expr) {
            const ce = ue.operand.call_expr;
            if (ce.callee.* == .builtin_expr and ce.args.len > 0 and
                self.isStrExpr(ce.args[0]))
            {
                const name = ce.callee.builtin_expr.lexeme;
                const int_casts = [_][]const u8{
                    "@i8","@i16","@i32","@i64","@i128",
                    "@u8","@u16","@u32","@u64","@u128","@usize","@isize",
                };
                for (int_casts) |cast| {
                    if (std.mem.eql(u8, name, cast)) {
                        try self.writer.print("try std.fmt.parseInt({s}, ", .{cast[1..]});
                        try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll(", 10)");
                        return;
                    }
                }
                const float_casts = [_][]const u8{ "@f32", "@f64", "@f128" };
                for (float_casts) |cast| {
                    if (std.mem.eql(u8, name, cast)) {
                        try self.writer.print("try std.fmt.parseFloat({s}, ", .{cast[1..]});
                        try self.emitExpr(ce.args[0]);
                        try self.writer.writeByte(')');
                        return;
                    }
                }
            }
        }
        try self.writer.writeAll(ue.op.lexeme);
        // Keyword prefix operators need a space before the operand.
        if (ue.op.lexeme.len > 0 and std.ascii.isAlphabetic(ue.op.lexeme[0]))
            try self.writer.writeByte(' ');
        try self.emitExpr(ue.operand);
    }

    fn emitCallExpr(self: *CodeGen, ce: ast.CallExpr) !void {
        // Namespaced builtins: @math::sqrt, @fs::FileReader::open, etc.
        if (ce.callee.* == .ns_builtin_expr) {
            try self.emitNsBuiltinCall(ce.callee.ns_builtin_expr, ce.args);
            return;
        }

        if (ce.callee.* == .builtin_expr) {
            const name = ce.callee.builtin_expr.lexeme;
            if (std.mem.eql(u8, name, "@pl")) {
                try self.emitPlCall(ce.args);
                return;
            }
            if (std.mem.eql(u8, name, "@pf")) {
                try self.emitPfCall(ce.args);
                return;
            }
            if (std.mem.eql(u8, name, "@typeOf")) {
                // @typeOf(expr) → _zcyTypeName(@TypeOf(expr))
                // Returns the Zcythe-visible type name (e.g. "str" for []const u8).
                try self.writer.writeAll("_zcyTypeName(@TypeOf(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeAll("))");
                return;
            }
            if (std.mem.eql(u8, name, "@getArgs")) {
                // @getArgs() → try std.process.argsAlloc(std.heap.page_allocator)
                try self.writer.writeAll("try std.process.argsAlloc(std.heap.page_allocator)");
                return;
            }
            if (std.mem.eql(u8, name, "@cout")) {
                // @cout used as a function call rather than with <<; not supported.
                try self.writer.writeAll("@compileError(\"use @cout << expr, not @cout()\")");
                return;
            }
            if (std.mem.eql(u8, name, "@sysexit")) {
                // @sysexit(code) → std.process.exit(code)
                try self.writer.writeAll("std.process.exit(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@list")) {
                // @list(T) → std.ArrayList(T){} (Zig 0.15: unmanaged, no stored allocator)
                try self.writer.writeAll("std.ArrayList(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeAll("){}");
                return;
            }
            if (std.mem.eql(u8, name, "@input")) {
                // @input("prompt") → _zcyInput("prompt")
                try self.writer.writeAll("_zcyInput(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            // Numeric type-cast builtins: @i32, @i64, @u32, @u64, @f32, @f64, …
            // When the argument is a string, parse it; otherwise @as-cast.
            {
                const int_casts = [_][]const u8{
                    "@i8","@i16","@i32","@i64","@i128",
                    "@u8","@u16","@u32","@u64","@u128",
                    "@usize","@isize",
                };
                const float_casts = [_][]const u8{ "@f32", "@f64", "@f128" };
                for (int_casts) |cast| {
                    if (std.mem.eql(u8, name, cast)) {
                        const zig_type = cast[1..]; // strip leading @
                        if (ce.args.len > 0 and self.isStrExpr(ce.args[0])) {
                            try self.writer.print("(std.fmt.parseInt({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeAll(", 10) catch 0)");
                        } else {
                            try self.writer.print("@as({s}, ", .{zig_type});
                            if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                            try self.writer.writeByte(')');
                        }
                        return;
                    }
                }
                for (float_casts) |cast| {
                    if (std.mem.eql(u8, name, cast)) {
                        const zig_type = cast[1..];
                        if (ce.args.len > 0 and self.isStrExpr(ce.args[0])) {
                            try self.writer.print("(std.fmt.parseFloat({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeAll(") catch 0)");
                        } else {
                            try self.writer.print("@as({s}, ", .{zig_type});
                            if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                            try self.writer.writeByte(')');
                        }
                        return;
                    }
                }
            }
            if (std.mem.eql(u8, name, "@rng")) {
                // @rng(T, min, max) → _zcyRng(T, min, max)
                try self.writer.writeAll("_zcyRng(");
                for (ce.args, 0..) |arg, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    try self.emitExpr(arg);
                }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@malloc")) {
                try self.writer.writeAll("_zcyMalloc(");
                for (ce.args, 0..) |arg, i| { if (i > 0) try self.writer.writeAll(", "); try self.emitExpr(arg); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@free")) {
                // page_allocator.free requires a slice; emit a no-op void block.
                try self.writer.writeAll("({})");
                return;
            }
            if (std.mem.eql(u8, name, "@getPageAlloc")) {
                try self.writer.writeAll("std.heap.page_allocator");
                return;
            }
            if (std.mem.eql(u8, name, "@getGenPurpAlloc")) {
                try self.writer.writeAll("blk: { var _gpa = std.heap.GeneralPurposeAllocator(.{}){}; break :blk _gpa.allocator(); }");
                return;
            }
            if (std.mem.eql(u8, name, "@getFixedBufAlloc")) {
                try self.writer.writeAll("blk: { var _fba_buf: [65536]u8 = undefined; var _fba = std.heap.FixedBufferAllocator.init(&_fba_buf); break :blk _fba.allocator(); }");
                return;
            }
            if (std.mem.eql(u8, name, "@getArenaAlloc")) {
                try self.writer.writeAll("blk: { var _arena = std.heap.ArenaAllocator.init(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeAll("); break :blk _arena.allocator(); }");
                return;
            }
            // Unknown builtin: pass through as-is
            try self.writer.writeAll(name);
            try self.writer.writeByte('(');
            for (ce.args, 0..) |arg, i| {
                if (i > 0) try self.writer.writeAll(", ");
                try self.emitExpr(arg);
            }
            try self.writer.writeByte(')');
            return;
        }

        // `getArgs()` without `@` — alias for @getArgs()
        if (ce.callee.* == .ident_expr and
            std.mem.eql(u8, ce.callee.ident_expr.lexeme, "getArgs"))
        {
            try self.writer.writeAll("try std.process.argsAlloc(std.heap.page_allocator)");
            return;
        }

        // Remap list .add(v) → try list.append(allocator, v)
        // Zig 0.15 ArrayList is unmanaged; allocator must be passed to each call.
        // `.add` is not a Zig method — always remap it.
        // Also remap file-var methods (.rln, .w, .ri32, .cl, etc.)
        if (ce.callee.* == .field_expr) {
            const fe = ce.callee.field_expr;
            if (std.mem.eql(u8, fe.field.lexeme, "add")) {
                try self.writer.writeAll("try ");
                try self.emitExpr(fe.object);
                try self.writer.writeAll(".append(std.heap.page_allocator");
                for (ce.args) |arg| {
                    try self.writer.writeAll(", ");
                    try self.emitExpr(arg);
                }
                try self.writer.writeByte(')');
                return;
            }
            // File-var method remapping
            if (fe.object.* == .ident_expr) {
                const obj_name = fe.object.ident_expr.lexeme;
                if (self.getFileVarKind(obj_name)) |fkind| {
                    try self.emitFileVarMethod(fe.object, fe.field.lexeme, fkind, ce.args);
                    return;
                }
            }
        }

        // Regular function call
        try self.emitExpr(ce.callee);
        try self.writer.writeByte('(');
        for (ce.args, 0..) |arg, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitExpr(arg);
        }
        try self.writer.writeByte(')');
    }

    /// `@pl(string_lit)`        → `std.debug.print("{s}\n",       .{<lit>})`
    /// `@pl("prefix" + expr)`  → `std.debug.print("{s}{any}\n",  .{"prefix", expr})`
    /// `@pl(other)`            → `std.debug.print("{any}\n",     .{<expr>})`
    fn emitPlCall(self: *CodeGen, args: []*ast.Node) !void {
        if (args.len == 0) {
            try self.writer.writeAll("std.debug.print(\"\\n\", .{})");
            return;
        }
        const arg = args[0];
        // Handle `"prefix" + val` string concatenation: expand to two-arg print.
        if (arg.* == .binary_expr and arg.binary_expr.op.kind == .plus and
            arg.binary_expr.left.* == .string_lit)
        {
            const be = arg.binary_expr;
            const right_fmt: []const u8 = if (be.right.* == .string_lit) "{s}" else "{any}";
            try self.writer.writeAll("std.debug.print(\"{s}");
            try self.writer.writeAll(right_fmt);
            try self.writer.writeAll("\\n\", .{");
            try self.emitExpr(be.left);
            try self.writer.writeAll(", ");
            try self.emitExpr(be.right);
            try self.writer.writeAll("})");
            return;
        }
        // String literals: emit directly with {s} (type is known at parse time).
        // All other expressions: route through _zcyPrint which picks {s} or
        // {any} at Zig compile time based on the actual runtime type.
        if (isStringLike(arg)) {
            try self.writer.writeAll("std.debug.print(\"{s}\\n\", .{");
            try self.emitExpr(arg);
            try self.writer.writeAll("})");
        } else {
            try self.writer.writeAll("_zcyPrint(");
            try self.emitExpr(arg);
            try self.writer.writeByte(')');
        }
    }

    /// `@pf(fmt, args…)` → `std.debug.print(<fmt>, .{<args…>})`
    ///
    /// Single-arg shorthand: `@pf("Hello {name}\n")` auto-extracts every
    /// `{identifier}` placeholder and injects the identifiers as arguments,
    /// replacing each `{ident}` with `{any}` in the format string.
    fn emitPfCall(self: *CodeGen, args: []*ast.Node) !void {
        if (args.len == 0) return;
        // Single-arg interpolation: @pf("Hello {name}\n")
        if (args.len == 1 and args[0].* == .string_lit) {
            const raw = args[0].string_lit.lexeme;
            if (containsInterpolation(raw)) {
                try self.emitPfInterpolated(raw);
                return;
            }
        }
        // Standard multi-arg form: @pf(fmt, arg1, arg2, …)
        try self.writer.writeAll("std.debug.print(");
        try self.emitExpr(args[0]);
        try self.writer.writeAll(", .{");
        for (args[1..], 0..) |arg, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitExpr(arg);
        }
        try self.writer.writeAll("})");
    }

    /// Emit `std.debug.print(<transformed_fmt>, .{<idents…>})` where every
    /// `{identifier}` placeholder in the raw string literal is replaced with
    /// `{any}` and the identifier names are injected as arguments.
    ///
    /// Two passes over the inner content of `raw_lit` (quotes already stripped):
    ///   1. Emit the transformed format string.
    ///   2. Emit the argument list.
    fn emitPfInterpolated(self: *CodeGen, raw_lit: []const u8) !void {
        // Strip surrounding double-quotes.
        const s = raw_lit[1 .. raw_lit.len - 1];

        // Pass 1: emit transformed format string.
        // `{ident}` → Zig specifier inferred from declaration.
        // `{ident:spec}` → Zig specifier derived from user-provided spec.
        try self.writer.writeAll("std.debug.print(\"");
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '{') {
                const start = i + 1;
                var j = start;
                while (j < s.len and s[j] != '}') j += 1;
                if (j < s.len) {
                    const spec = s[start..j];
                    if (isInterpolationIdent(spec)) {
                        const fmt = interpFmt(spec);
                        // The source `{` is consumed but NOT forwarded; we
                        // emit a full replacement `{spec}` here.
                        try self.writer.writeByte('{');
                        if (fmt.len > 0) {
                            // User provided an explicit format — map to Zig.
                            try self.emitZigFmtSpec(fmt, "d");
                        } else {
                            // Infer from variable declaration.
                            // inferPfSpec returns e.g. "{s}"; strip the braces.
                            const inferred = self.inferPfSpec(interpIdent(spec));
                            try self.writer.writeAll(inferred[1 .. inferred.len - 1]);
                        }
                        try self.writer.writeByte('}');
                        i = j + 1;
                        continue;
                    }
                }
            }
            try self.writer.writeByte(s[i]);
            i += 1;
        }
        try self.writer.writeAll("\", .{");

        // Pass 2: emit the identifier arguments in order.
        var first = true;
        i = 0;
        while (i < s.len) {
            if (s[i] == '{') {
                const start = i + 1;
                var j = start;
                while (j < s.len and s[j] != '}') j += 1;
                if (j < s.len) {
                    const spec = s[start..j];
                    if (isInterpolationIdent(spec)) {
                        if (!first) try self.writer.writeAll(", ");
                        try self.writeDottedIdent(interpIdent(spec)); // handles p.name etc.
                        first = false;
                        i = j + 1;
                        continue;
                    }
                }
            }
            i += 1;
        }
        try self.writer.writeAll("})");
    }

    /// Return the best Zig format specifier for a named identifier appearing
    /// inside an `@pf` interpolation placeholder.
    ///
    /// We inspect the current block for the variable's declaration and infer
    /// the specifier from its type annotation or initializer:
    ///   - explicit `str` annotation, or string_lit initializer → `{s}`
    ///   - int_lit / float_lit initializer                      → `{d}`
    ///   - anything else (no decl found, complex expr)           → `{any}`
    fn inferPfSpec(self: *const CodeGen, name: []const u8) []const u8 {
        // For-loop element variable: type was resolved in emitForStmt.
        if (self.loop_elem_name) |en| {
            if (std.mem.eql(u8, en, name)) return self.loop_elem_spec orelse "{any}";
        }
        // Field-access path (e.g. `p.name`): look up via dat_decl type info.
        if (std.mem.indexOfScalar(u8, name, '.')) |dot_idx| {
            return self.inferPfSpecField(name[0..dot_idx], name[dot_idx + 1 ..]);
        }
        for (self.current_block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            if (!std.mem.eql(u8, vd.name.lexeme, name)) continue;
            // Explicit type annotation takes priority.
            if (vd.type_ann) |ta| {
                const tn = ta.name.lexeme;
                if (std.mem.eql(u8, tn, "str"))   return "{s}";
                if (std.mem.eql(u8, tn, "char"))  return "{c}";
                if (std.mem.eql(u8, tn, "i8")    or std.mem.eql(u8, tn, "i16")  or
                    std.mem.eql(u8, tn, "i32")   or std.mem.eql(u8, tn, "i64")  or
                    std.mem.eql(u8, tn, "u8")    or std.mem.eql(u8, tn, "u16")  or
                    std.mem.eql(u8, tn, "u32")   or std.mem.eql(u8, tn, "u64")  or
                    std.mem.eql(u8, tn, "f32")   or std.mem.eql(u8, tn, "f64")  or
                    std.mem.eql(u8, tn, "usize") or std.mem.eql(u8, tn, "isize"))
                    return "{d}";
                return "{any}";
            }
            // Infer from the initialiser expression.
            return switch (vd.value.*) {
                .string_lit                        => "{s}",
                .int_lit, .float_lit               => "{d}",
                .binary_expr, .unary_expr          => if (exprIsNumeric(vd.value)) "{d}" else "{any}",
                else                               => "{any}",
            };
        }
        return "{any}"; // identifier not found in this block
    }

    /// Infer a Zig format specifier for a field access `base.field` by looking
    /// up the base variable's struct-lit type in the current block, then finding
    /// the matching `dat_decl` in the program and reading the field's type.
    fn inferPfSpecField(self: *const CodeGen, base: []const u8, field: []const u8) []const u8 {
        // Find the base variable's type (must be initialised by a struct literal).
        const type_name = blk: {
            for (self.current_block.stmts) |stmt| {
                if (stmt.* != .var_decl) continue;
                if (!std.mem.eql(u8, stmt.var_decl.name.lexeme, base)) continue;
                const val = stmt.var_decl.value;
                if (val.* != .struct_lit) break :blk null;
                const tn = val.struct_lit.type_name;
                if (tn.* == .ident_expr) break :blk tn.ident_expr.lexeme;
                break :blk null;
            }
            break :blk null;
        };
        const tname = type_name orelse return "{any}";
        // Search program for a dat_decl with that name and the matching field.
        const prog = self.program orelse return "{any}";
        for (prog.items) |item| {
            if (item.* != .dat_decl) continue;
            if (!std.mem.eql(u8, item.dat_decl.name.lexeme, tname)) continue;
            for (item.dat_decl.fields) |f| {
                if (!std.mem.eql(u8, f.name.lexeme, field)) continue;
                const ft = f.type_ann.name.lexeme;
                if (std.mem.eql(u8, ft, "str"))  return "{s}";
                if (std.mem.eql(u8, ft, "char")) return "{c}";
                if (std.mem.eql(u8, ft, "i32")  or std.mem.eql(u8, ft, "i64") or
                    std.mem.eql(u8, ft, "u32")  or std.mem.eql(u8, ft, "u64") or
                    std.mem.eql(u8, ft, "f32")  or std.mem.eql(u8, ft, "f64"))
                    return "{d}";
                return "{any}";
            }
        }
        return "{any}";
    }

    /// Emit `@pf("Hello {p.name}…")` as a series of `std.debug.print` / `_zcyPrintNoNl`
    /// calls when any placeholder is a field-access expression.
    /// Each literal segment → `std.debug.print("literal", .{});`
    /// Each interpolation  → `_zcyPrintNoNl(p.name);`
    fn emitPfMultiCall(self: *CodeGen, raw_lit: []const u8) !void {
        const s = raw_lit[1 .. raw_lit.len - 1]; // strip outer quotes
        var lit_start: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '{') {
                const brace_start = i;
                const inner_start = i + 1;
                var j = inner_start;
                while (j < s.len and s[j] != '}') j += 1;
                if (j < s.len) {
                    const spec = s[inner_start..j];
                    if (isInterpolationIdent(spec)) {
                        // Emit any accumulated literal before this placeholder.
                        if (brace_start > lit_start) {
                            try self.writeIndent();
                            try self.writer.writeAll("std.debug.print(\"");
                            try self.writer.writeAll(s[lit_start..brace_start]);
                            try self.writer.writeAll("\", .{});\n");
                        }
                        // Emit type-dispatching print for the expression.
                        try self.writeIndent();
                        try self.writer.writeAll("_zcyPrintNoNl(");
                        try self.writeDottedIdent(interpIdent(spec));
                        try self.writer.writeAll(");\n");
                        i = j + 1;
                        lit_start = i;
                        continue;
                    }
                }
            }
            i += 1;
        }
        // Trailing literal segment.
        if (lit_start < s.len) {
            try self.writeIndent();
            try self.writer.writeAll("std.debug.print(\"");
            try self.writer.writeAll(s[lit_start..]);
            try self.writer.writeAll("\", .{});\n");
        }
    }

    fn emitFieldExpr(self: *CodeGen, fe: ast.FieldExpr) !void {
        // @os.platform → @import("builtin").os.tag == .platform
        if (fe.object.* == .builtin_expr and
            std.mem.eql(u8, fe.object.builtin_expr.lexeme, "@os"))
        {
            try self.writer.writeAll("@import(\"builtin\").os.tag == .");
            try self.writer.writeAll(fe.field.lexeme);
            return;
        }
        try self.emitExpr(fe.object);
        try self.writer.writeByte('.');
        // `.*` pointer dereference: field token is a star, not an identifier.
        if (fe.field.kind == .star) {
            try self.writer.writeByte('*');
        } else {
            try self.writeZigIdent(fe.field.lexeme);
        }
    }

    /// Array literal without a type context: emit as `.{elem, …}` (Zig anonymous).
    fn emitArrayLit(self: *CodeGen, al: ast.ArrayLit) !void {
        try self.writer.writeAll(".{");
        for (al.elems, 0..) |elem, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitExpr(elem);
        }
        try self.writer.writeByte('}');
    }

    /// Array literal with a known element type: `[_]MappedT{elem, …}`.
    fn emitArrayLitTyped(self: *CodeGen, al: ast.ArrayLit, elem_type: []const u8) !void {
        try self.writer.writeAll("[_]");
        try self.writer.writeAll(mapType(elem_type));
        try self.writer.writeByte('{');
        for (al.elems, 0..) |elem, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.emitExpr(elem);
        }
        try self.writer.writeByte('}');
    }

    fn emitStructLit(self: *CodeGen, sl: ast.StructLit) !void {
        try self.emitExpr(sl.type_name);
        try self.writer.writeAll("{");
        for (sl.fields, 0..) |field, i| {
            if (i > 0) try self.writer.writeAll(",");
            try self.writer.writeAll(" .");
            try self.writeZigIdent(field.name.lexeme);
            try self.writer.writeAll(" = ");
            try self.emitExpr(field.value);
        }
        try self.writer.writeAll(" }");
    }
};

// ─── Zig keyword escaping (file-scope helpers) ───────────────────────────────

/// Full list of Zig reserved keywords (as of Zig 0.13/0.14).
/// Zcythe identifiers that match must be emitted as `@"name"`.
fn isZigKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace", "align",        "allowzero",    "and",         "anyframe",
        "anyopaque",  "anytype",      "asm",          "async",       "await",
        "break",      "callconv",     "catch",        "comptime",    "const",
        "continue",   "defer",        "else",         "enum",        "errdefer",
        "export",     "extern",       "false",        "fn",          "for",
        "if",         "inline",       "linksection",  "noalias",     "noinline",
        "nosuspend",  "null",         "opaque",       "or",          "orelse",
        "packed",     "pub",          "resume",       "return",      "struct",
        "suspend",    "switch",       "test",         "threadlocal", "true",
        "try",        "type",         "undefined",    "union",       "unreachable",
        "usingnamespace", "var",      "volatile",     "while",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

// ─── @fs helpers (file-scope) ────────────────────────────────────────────────

/// Return true when `node` is `@fs::Big` (big-endian marker).
fn isFsEndianBig(node: *const ast.Node) bool {
    if (node.* != .ns_builtin_expr) return false;
    const nb = node.ns_builtin_expr;
    if (!std.mem.eql(u8, nb.namespace.lexeme, "@fs")) return false;
    if (nb.path.len != 1) return false;
    return std.mem.eql(u8, nb.path[0].lexeme, "Big");
}

// ─── @cout chain helper (file-scope; no CodeGen state needed) ────────────────

/// Return true if `node` is `@cout` or a `<<` binary chain whose leftmost
/// leaf is `@cout`.  Used to decide whether an expression-statement should
/// be routed through `emitCoutChain` rather than the generic emitter.
fn isCoutChain(node: *const ast.Node) bool {
    return switch (node.*) {
        .builtin_expr => |t|  std.mem.eql(u8, t.lexeme, "@cout"),
        .binary_expr  => |be| be.op.kind == .lshift and isCoutChain(be.left),
        else          => false,
    };
}

// ─── @cin chain helper (file-scope; no CodeGen state needed) ─────────────────

/// Return true if `node` is `@cin` or a `>>` binary chain whose leftmost
/// leaf is `@cin`.  Used to route `@cin >> x` through `emitCinChain`.
fn isCinChain(node: *const ast.Node) bool {
    return switch (node.*) {
        .builtin_expr => |t|  std.mem.eql(u8, t.lexeme, "@cin"),
        .binary_expr  => |be| be.op.kind == .rshift and isCinChain(be.left),
        else          => false,
    };
}

fn isGetArgs(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* == .builtin_expr)
        return std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@getArgs");
    if (ce.callee.* == .ident_expr)
        return std.mem.eql(u8, ce.callee.ident_expr.lexeme, "getArgs");
    return false;
}

/// Return true when `node` is `@pf("…")` with a single interpolated string
/// that contains at least one field-access placeholder (e.g. `{p.name}`).
/// These are routed through `emitPfMultiCall` instead of the single-call path.
fn isPfFieldInterp(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .builtin_expr) return false;
    if (!std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@pf")) return false;
    if (ce.args.len != 1 or ce.args[0].* != .string_lit) return false;
    const raw = ce.args[0].string_lit.lexeme;
    if (!containsInterpolation(raw)) return false;
    // Check whether any placeholder is a field-access (contains '.').
    const s = raw[1 .. raw.len - 1];
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '{') {
            const start = i + 1;
            var j = start;
            while (j < s.len and s[j] != '}') j += 1;
            if (j < s.len) {
                const spec = s[start..j];
                if (isInterpolationIdent(spec) and
                    std.mem.indexOfScalar(u8, interpIdent(spec), '.') != null)
                    return true;
                i = j + 1;
                continue;
            }
        }
        i += 1;
    }
    return false;
}

/// Return true when `node` produces a `[]const u8` value — i.e. string
/// literals and `@typeOf(…)` calls (which emit `@typeName(@TypeOf(…))`).
/// Used to choose `{s}` instead of `{any}` in print format strings.
fn isStringLike(node: *const ast.Node) bool {
    if (node.* == .string_lit) return true;
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    return ce.callee.* == .builtin_expr and
           std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@typeOf");
}

// ─── Auto-const mutation analysis (file-scope) ───────────────────────────────

/// Return true when `node` is a `@list(T)` call expression.
fn isListCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    return ce.callee.* == .builtin_expr and
        std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@list");
}

/// Return true if `name` ever appears as the left-hand side of an assignment
/// (`=`, `+=`, `-=`, `*=`, `/=`) anywhere in `block`, including inside nested
/// while/for/loop/if bodies (but not inside nested fn_decl scopes).
fn isReassignedInBlock(name: []const u8, block: ast.Block) bool {
    for (block.stmts) |stmt| {
        switch (stmt.*) {
            .expr_stmt => |expr| {
                if (expr.* != .binary_expr) continue;
                const be = expr.binary_expr;
                const op = be.op.lexeme;
                const is_assign =
                    std.mem.eql(u8, op, "=")  or
                    std.mem.eql(u8, op, "+=") or
                    std.mem.eql(u8, op, "-=") or
                    std.mem.eql(u8, op, "*=") or
                    std.mem.eql(u8, op, "/=");
                if (!is_assign) {
                    // `@cin >> x` counts as a mutation of x
                    if (be.op.kind == .rshift and isCinChain(be.left) and
                        be.right.* == .ident_expr and
                        std.mem.eql(u8, be.right.ident_expr.lexeme, name)) return true;
                    continue;
                }
                if (be.left.* != .ident_expr) continue;
                if (std.mem.eql(u8, be.left.ident_expr.lexeme, name)) return true;
            },
            // Recurse into nested control-flow bodies
            .while_stmt => |ws| {
                if (isReassignedInBlock(name, ws.body)) return true;
            },
            .for_stmt => |fs| {
                if (isReassignedInBlock(name, fs.body)) return true;
            },
            .loop_stmt => |ls| {
                if (isReassignedInBlock(name, ls.body)) return true;
            },
            .if_stmt => |is_| {
                if (isReassignedInBlock(name, is_.then_blk)) return true;
                if (is_.else_blk) |eb| {
                    if (isReassignedInBlock(name, eb)) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

// ── Raylib usage detection ────────────────────────────────────────────────

/// Return true when any node in the program uses `@rl::` (the raylib namespace).
/// Used to conditionally emit `const rl = @import("raylib");` in the preamble.
fn programUsesRl(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesRl(item)) return true;
    return false;
}

fn blockUsesRl(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesRl(s)) return true;
    return false;
}

fn nodeUsesRl(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@rl"),
        .call_expr       => |ce| blk: {
            if (nodeUsesRl(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesRl(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesRl(be.left) or nodeUsesRl(be.right),
        .unary_expr   => |ue| nodeUsesRl(ue.operand),
        .var_decl     => |vd| nodeUsesRl(vd.value),
        .ret_stmt     => |rs| nodeUsesRl(rs.value),
        .expr_stmt    => |es| nodeUsesRl(es),
        .field_expr   => |fe| nodeUsesRl(fe.object),
        .defer_stmt   => |ds| nodeUsesRl(ds.expr),
        .catch_expr   => |ce| blk: {
            if (nodeUsesRl(ce.subject)) break :blk true;
            for (ce.arms) |arm| if (nodeUsesRl(arm.value)) break :blk true;
            break :blk false;
        },
        .if_stmt      => |is_| blk: {
            if (nodeUsesRl(is_.cond)) break :blk true;
            if (blockUsesRl(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesRl(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesRl(ws.cond) or blockUsesRl(ws.body),
        .for_stmt     => |fs| nodeUsesRl(fs.iterable) or blockUsesRl(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesRl(ls.init) or nodeUsesRl(ls.cond) or nodeUsesRl(ls.update)) break :blk true;
            break :blk blockUsesRl(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesRl(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesRl(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl      => |fd| blockUsesRl(fd.body),
        .main_block   => |mb| blockUsesRl(mb.body),
        .block        => |b|  blockUsesRl(b),
        .fun_expr     => |fe| blockUsesRl(fe.body),
        .array_lit    => |al| blk: {
            for (al.elems) |e| if (nodeUsesRl(e)) break :blk true;
            break :blk false;
        },
        .struct_lit   => |sl| blk: {
            if (nodeUsesRl(sl.type_name)) break :blk true;
            for (sl.fields) |f| if (nodeUsesRl(f.value)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// Return true when `node` is or contains a numeric literal (int or float).
/// Used by inferPfSpec to detect binary-expression initializers that produce numbers.
fn exprIsNumeric(node: *const ast.Node) bool {
    return switch (node.*) {
        .int_lit, .float_lit => true,
        .binary_expr => |be| exprIsNumeric(be.left) or exprIsNumeric(be.right),
        .unary_expr  => |ue| exprIsNumeric(ue.operand),
        else         => false,
    };
}

/// Map a Zcythe error name to its Zig counterpart.
/// Zcythe provides a friendlier vocabulary; the table below bridges the gap.
/// Unrecognised names pass through unchanged so user-defined errors still work.
fn mapZcyError(name: []const u8) []const u8 {
    // ── Number parsing (std.fmt.parseInt / parseFloat) ────────────────────
    if (std.mem.eql(u8, name, "NumFormatErr"))   return "InvalidCharacter";
    if (std.mem.eql(u8, name, "NumOverflow"))    return "Overflow";
    if (std.mem.eql(u8, name, "NumUnderflow"))   return "Underflow";
    if (std.mem.eql(u8, name, "ParseErr"))       return "InvalidCharacter";
    if (std.mem.eql(u8, name, "InvalidBase"))    return "InvalidBase";
    // ── Memory ────────────────────────────────────────────────────────────
    if (std.mem.eql(u8, name, "OutOfMem"))       return "OutOfMemory";
    // ── I/O / filesystem ──────────────────────────────────────────────────
    if (std.mem.eql(u8, name, "EndOfStream"))    return "EndOfStream";
    if (std.mem.eql(u8, name, "StreamTooLong"))  return "StreamTooLong";
    if (std.mem.eql(u8, name, "AccessDenied"))   return "AccessDenied";
    if (std.mem.eql(u8, name, "FileNotFound"))   return "FileNotFound";
    if (std.mem.eql(u8, name, "FileExists"))     return "PathAlreadyExists";
    if (std.mem.eql(u8, name, "FileTooBig"))     return "FileTooBig";
    if (std.mem.eql(u8, name, "IsDir"))          return "IsDir";
    if (std.mem.eql(u8, name, "NotDir"))         return "NotDir";
    if (std.mem.eql(u8, name, "NoSpace"))        return "NoSpaceLeft";
    if (std.mem.eql(u8, name, "NotReadable"))    return "NotOpenForReading";
    if (std.mem.eql(u8, name, "NotWritable"))    return "NotOpenForWriting";
    if (std.mem.eql(u8, name, "BrokenPipe"))     return "BrokenPipe";
    if (std.mem.eql(u8, name, "InvalidUtf8"))    return "InvalidUtf8";
    // ── System / OS ───────────────────────────────────────────────────────
    if (std.mem.eql(u8, name, "UnexpectedErr"))  return "Unexpected";
    if (std.mem.eql(u8, name, "NotSupported"))   return "Unsupported";
    if (std.mem.eql(u8, name, "WouldBlock"))     return "WouldBlock";
    if (std.mem.eql(u8, name, "SysResources"))   return "SystemResources";
    if (std.mem.eql(u8, name, "InvalidHandle"))  return "InvalidHandle";
    // ── Pass-through: user-defined or already-Zig error names ────────────
    return name;
}

/// Return true when `node` is a call to a void-producing builtin (@pl, @pf,
/// @cout) — i.e., a call whose Zig equivalent returns `void`.
/// Used in catch-arm codegen to detect side-effect-only arms.
fn isVoidProducingCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .builtin_expr) return false;
    const name = ce.callee.builtin_expr.lexeme;
    return std.mem.eql(u8, name, "@pl") or
           std.mem.eql(u8, name, "@pf") or
           std.mem.eql(u8, name, "@cout");
}

/// Return true when `node` is an `ident_expr` whose lexeme is the Zcythe
/// `undef` keyword (maps to Zig `undefined`).
fn isUndefExpr(node: *const ast.Node) bool {
    if (node.* != .ident_expr) return false;
    return std.mem.eql(u8, node.ident_expr.lexeme, "undef");
}

/// Scan `block` for the first simple assignment `name = rhs` and return the
/// rhs node.  Used to infer the concrete type for `x := undef` declarations.
fn findReassignValue(name: []const u8, block: ast.Block) ?*const ast.Node {
    for (block.stmts) |stmt| {
        if (stmt.* != .expr_stmt) continue;
        const expr = stmt.expr_stmt;
        if (expr.* != .binary_expr) continue;
        const be = expr.binary_expr;
        if (!std.mem.eql(u8, be.op.lexeme, "=")) continue;
        if (be.left.* != .ident_expr) continue;
        if (std.mem.eql(u8, be.left.ident_expr.lexeme, name)) return be.right;
    }
    return null;
}

// ─── @pf interpolation helpers (file-scope) ──────────────────────────────────

/// Return true if `raw_lit` (the token lexeme, including surrounding `"`)
/// contains at least one `{identifier}` placeholder that is not a standard
/// Zig format specifier.
fn containsInterpolation(raw_lit: []const u8) bool {
    if (raw_lit.len < 2) return false;
    const s = raw_lit[1 .. raw_lit.len - 1];
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '{') {
            const start = i + 1;
            var j = start;
            while (j < s.len and s[j] != '}') j += 1;
            if (j < s.len and isInterpolationIdent(s[start..j])) return true;
            i = j + 1;
        } else {
            i += 1;
        }
    }
    return false;
}

/// Return true if `spec` (the text between `{` and `}`) is a user-supplied
/// identifier or field-access path, optionally followed by `:fmt_spec`.
/// Examples: `name`, `y:.3f`, `p.name`, `a.b.c`.
fn isInterpolationIdent(spec: []const u8) bool {
    if (spec.len == 0) return false;
    // Reject specifiers that can never be valid Zcythe identifiers.
    // Single-letter specs (s, d, x, f …) are intentionally NOT excluded here:
    // single-arg @pf always uses interpolation mode, so a single-letter `{x}`
    // means the variable `x`, not the Zig hex specifier.  Use the two-arg form
    // @pf("{x}", val) for raw Zig format specs.
    const known = [_][]const u8{ "any", "*", "?" };
    for (known) |k| {
        if (std.mem.eql(u8, spec, k)) return false;
    }
    // Must start with a letter or `_`.
    if (spec[0] != '_' and !std.ascii.isAlphabetic(spec[0])) return false;
    // Advance through ident chars and `.` (for field access like `p.name`).
    // A `.` is only allowed when followed by another ident-start char.
    var i: usize = 1;
    while (i < spec.len) {
        if (spec[i] == '_' or std.ascii.isAlphanumeric(spec[i])) {
            i += 1;
        } else if (spec[i] == '.' and i + 1 < spec.len and
                   (std.ascii.isAlphabetic(spec[i + 1]) or spec[i + 1] == '_'))
        {
            i += 1; // include the '.'
        } else {
            break;
        }
    }
    // After the ident/path: either end of string or `:` introducing a format spec.
    if (i == spec.len) return true;
    if (spec[i] == ':') return true;
    return false;
}

/// Return just the identifier/path prefix of `spec` (everything before any `:`).
/// Handles dotted field-access paths like `p.name` in addition to plain idents.
fn interpIdent(spec: []const u8) []const u8 {
    var i: usize = 0;
    if (i < spec.len) i += 1; // first char (already validated)
    while (i < spec.len) {
        if (spec[i] == '_' or std.ascii.isAlphanumeric(spec[i])) {
            i += 1;
        } else if (spec[i] == '.' and i + 1 < spec.len and
                   (std.ascii.isAlphabetic(spec[i + 1]) or spec[i + 1] == '_'))
        {
            i += 1; // include the '.'
        } else {
            break;
        }
    }
    return spec[0..i];
}

/// Return the format part of `spec` after `:`, or `""` for a bare identifier.
fn interpFmt(spec: []const u8) []const u8 {
    const ident = interpIdent(spec);
    if (ident.len < spec.len and spec[ident.len] == ':') return spec[ident.len + 1..];
    return "";
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════════════════════

const parser = @import("parser.zig");

/// Parse `src` into an AST (arena-owned) and emit Zig source into a buffer.
/// Returns the emitted string as a slice owned by `buf`.
fn parseAndEmit(
    arena:  std.mem.Allocator,
    buf:    *std.ArrayListUnmanaged(u8),
    src:    []const u8,
) ![]const u8 {
    var p    = parser.Parser.init(arena, src);
    const root = try p.parse();
    var cg = CodeGen.init(buf.writer(arena).any());
    try cg.emit(root);
    return buf.items;
}

test "preamble" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "");
    try std.testing.expect(std.mem.startsWith(u8, out, "const std = @import(\"std\");"));
}

test "empty @main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main {}");
    const expected =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "@pl string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    @pl("Hello World")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("{s}\n", .{"Hello World"})
    ) != null);
}

test "var decl mut implicit — auto-const (never reassigned)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `x` is declared with `:=` but never reassigned → emitted as `const`
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { x := 32 }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const x = 32;") != null);
}

test "var decl mut implicit — stays var when reassigned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `x` is reassigned after declaration → must remain `var`
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { x := 32  x = 99 }");
    try std.testing.expect(std.mem.indexOf(u8, out, "var x = 32;") != null);
}

test "var decl immut implicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { PI :: 3.145 }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const PI = 3.145;") != null);
}

test "var decl mut explicit — auto-const (never reassigned)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `y` is declared with `: str =` but never reassigned → emitted as `const`
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { y : str = \"hi\" }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const y: []const u8 = \"hi\";") != null);
}

test "var decl immut explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { FOO : str : \"Bar\" }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const FOO: []const u8 = \"Bar\";") != null);
}

test "array var decl — auto-const (never reassigned)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // Array declared with `: []i32 =` but never reassigned → `const`
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { a : []i32 = {1,2,3} }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const a = [_]i32{1, 2, 3};") != null);
}

test "fn untyped params" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "fn add(a, b) { ret a+b }");
    try std.testing.expect(std.mem.indexOf(u8, out, "fn add(a: anytype, b: anytype)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@TypeOf(a + b)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "return a + b;") != null);
}

test "fn typed params and ret" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "fn add(a: i32, b: i32) -> i32 { ret a + b }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn add(a: i32, b: i32) i32 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "return a + b;") != null);
}

test "logical operators remapped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { a && b }");
    try std.testing.expect(std.mem.indexOf(u8, out, "a and b") != null);
}

test "field access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { obj.field }");
    try std.testing.expect(std.mem.indexOf(u8, out, "obj.field") != null);
}

test "function call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { add(1, 2) }");
    try std.testing.expect(std.mem.indexOf(u8, out, "add(1, 2)") != null);
}

test "struct literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { p := Person{.name=\"J\",.age=32} }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    // `p` is never reassigned → auto-promoted to `const`
    try std.testing.expect(std.mem.indexOf(u8, out, "const p = Person{ .name = \"J\", .age = 32 };") != null);
}

test "zig keyword escaped in var decl" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `var` is a valid Zcythe identifier but a Zig keyword → must be @"var".
    // Initialized with a string literal → type inferred as `[]const u8`.
    // Never reassigned → auto-promoted to `const`.
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { var := \"6..7\" }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const @\"var\": []const u8 = \"6..7\";") != null);
}

test "zig keyword escaped in ident expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { var := 1  @pl(var) }");
    try std.testing.expect(std.mem.indexOf(u8, out, "@\"var\"") != null);
}

test "@pf with string interpolation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `greet` is string-initialized → specifier inferred as `{s}`, not `{any}`
    const src =
        \\@main {
        \\    greet := "hello"
        \\    @pf("Value: {greet}\n")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("Value: {s}\n", .{greet})
    ) != null);
}

test "@pf with zig-keyword interpolation identifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `var` is string-initialized → `{s}`; it's a Zig keyword → emitted as @"var"
    const src =
        \\@main {
        \\    var := "6..7"
        \\    @pf("Hello Pog {var}\n")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("Hello Pog {s}\n", .{@"var"})
    ) != null);
}

test "@pf with integer interpolation identifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // `n` is int-initialized → specifier inferred as `{d}`
    const src =
        \\@main {
        \\    n := 42
        \\    @pf("Answer: {n}\n")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("Answer: {d}\n", .{n})
    ) != null);
}

test "@cout single segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { @cout << \"Hello\\n\" }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("{s}", .{"Hello\n"})
    ) != null);
}

test "@cout chained with @endl" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { @cout << \"Hello\" << @endl }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("{s}", .{"Hello"})
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("\n", .{})
    ) != null);
}

test "full hello world round-trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    @pl("Hello World")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    // Must begin with the standard preamble
    try std.testing.expect(std.mem.startsWith(u8, out, "const std = @import(\"std\");"));
    // Must contain a valid main signature
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn main() !void {") != null);
    // Must contain the print call
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("{s}\n", .{"Hello World"})
    ) != null);
}

test "@cin reads into declared variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    x := ""
        \\    @cin >> x
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        "std.fs.File.stdin().deprecatedReader().readUntilDelimiterOrEof(&_cin_buf_0, '\\n')"
    ) != null);
}

test "@cin keeps target as var" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    x := ""
        \\    @cin >> x
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "var x") != null);
}

test "fun expression stored in variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { f := fun(a, b) { ret a+b } }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "struct { fn call(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "} }.call") != null);
}

test "fun passed as argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { mymap(arr, fun(x) { ret x }) }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "struct { fn call(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "} }.call") != null);
}

test "@import single alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@import(x = mymod)";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\const x = @import("mymod.zig");
    ) != null);
}

test "@import field import" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@import(y = mymod.MyStruct)";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\const y = @import("mymod.zig").MyStruct;
    ) != null);
}

test "char type maps to u8" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { c : char = 'a' }");
    try std.testing.expect(std.mem.indexOf(u8, out, "const c: u8 = 'a';") != null);
}

test "_zcyPrint preamble has u8 char branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "");
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\if (T == u8) {
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\std.debug.print("{c}\n", .{val});
    ) != null);
}

test "if statement emits braces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { if (x > 0) { @pl(\"pos\") } }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "if (x > 0) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "std.debug.print(\"pos\\n\"") != null);
}

test "if/else statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "@main { if (x) { @pl(\"y\") } else { @pl(\"n\") } }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "if (x) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "} else {") != null);
}

test "if inline body wraps to block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "fn abs(n) { if (n < 0) ret n  ret n }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "if (n < 0) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "return n;") != null);
}

test "recursive fn uses non-recursive ret for @TypeOf" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // Fibonacci: base case `ret n` is non-recursive; return type should be @TypeOf(n)
    const src = "fn fib(n) { if (n <= 1) ret n  ret fib(n-1)+fib(n-2) }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "@TypeOf(n)") != null);
}

test "@typeOf emits _zcyTypeName wrapper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { x := \"hi\"  @pl(@typeOf(x)) }");
    try std.testing.expect(std.mem.indexOf(u8, out, "_zcyTypeName(@TypeOf(x))") != null);
    // preamble maps []const u8 → "str"
    try std.testing.expect(std.mem.indexOf(u8, out, "if (T == []const u8) return \"str\";") != null);
}

test "@typeOf in @cout uses {s} format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { x := 1  @cout << @typeOf(x) << @endl }");
    try std.testing.expect(std.mem.indexOf(u8, out, "\"{s}\"") != null);
}

test "@comptime T param emits two Zig params" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "fn foo(@comptime T val) { ret val }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "comptime T: type, val: T") != null);
}

test "for loop basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { for e => items { @pl(e) } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "for (items) |e| {") != null);
}

test "for loop with index auto-range" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { for _, i => items { @pl(i) } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "for (items, 0..) |_, i| {") != null);
}

test "for loop elem and index with range" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { for e, i => items, 0..10 { } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "for (items, 0..10) |e, i| {") != null);
}

test "while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { while running { } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "while (running) {") != null);
}

test "while loop with do" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { while cond => tick() { } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "while (cond) : (tick()) {") != null);
}

test "loop stmt emits scoped while" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "@main { loop i := 0, i < 10, i+=1 { } }");
    try std.testing.expect(std.mem.indexOf(u8, out, "var i") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "while (i < 10) : (i += 1) {") != null);
}
