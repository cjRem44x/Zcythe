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

    // ─── Construction ──────────────────────────────────────────────────────

    pub fn init(writer: std.io.AnyWriter) CodeGen {
        return .{
            .writer        = writer,
            .indent_level  = 0,
            .current_block = .{ .stmts = &.{} },
            .cin_counter   = 0,
        };
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
        if (isZigKeyword(name)) {
            try self.writer.print("@\"{s}\"", .{name});
        } else {
            try self.writer.writeAll(name);
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
        if (ta.is_array) try self.writer.writeAll("[]");
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
            try self.writer.writeAll("const ");
            try self.writeZigIdent(be.left.ident_expr.lexeme);
            try self.writer.writeAll(" = @import(\"");
            // Walk right side: ident → "mod.zig", field_expr → "mod.zig").Field
            var mod_node = be.right;
            var field_tok: ?ast.Token = null;
            if (mod_node.* == .field_expr) {
                field_tok = mod_node.field_expr.field;
                mod_node  = mod_node.field_expr.object;
            }
            if (mod_node.* == .ident_expr)
                try self.writer.writeAll(mod_node.ident_expr.lexeme);
            try self.writer.writeAll(".zig\")");
            if (field_tok) |ft| {
                try self.writer.writeByte('.');
                try self.writeZigIdent(ft.lexeme);
            }
            try self.writer.writeAll(";\n");
        }
    }

    // ─── Program ───────────────────────────────────────────────────────────

    fn emitProgram(self: *CodeGen, prog: ast.Program) !void {
        try self.writer.writeAll("const std = @import(\"std\");\n");
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

        // Emit fn_decls first, collect @main for last
        var main_node: ?*const ast.Node = null;
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
        try self.writer.writeAll("fn ");
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
            .while_stmt => |ws| try self.emitWhileStmt(ws),
            .loop_stmt  => |ls| try self.emitLoopStmt(ls),
            .expr_stmt  => |es| try self.emitExprStmt(es),
            else        => {},
        }
    }

    fn emitVarDecl(self: *CodeGen, vd: ast.VarDecl) !void {
        try self.writeIndent();
        const kw: []const u8 = switch (vd.kind) {
            // Auto-downgrade mutable declarations to `const` when the variable
            // is never reassigned inside the same block.  This keeps generated
            // Zig valid even when the user writes `x := value` and never
            // mutates `x` — Zig would reject `var x = value` as an unused var.
            .mut_implicit, .mut_explicit => blk: {
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
        }

        try self.writer.writeAll(" = ");
        try self.emitExpr(vd.value);
        try self.writer.writeAll(";\n");

        // @getArgs() allocates — emit a paired defer to free and to make the
        // variable "used" so the Zig compiler doesn't reject it.
        if (isGetArgs(vd.value)) {
            try self.writeIndent();
            try self.writer.writeAll("defer std.process.argsFree(std.heap.page_allocator, ");
            try self.writeZigIdent(vd.name.lexeme);
            try self.writer.writeAll(");\n");
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
        try self.emitExpr(fs.iterable);

        if (fs.range) |r| {
            try self.writer.writeAll(", ");
            try self.emitExpr(r.start);
            try self.writer.writeAll(if (r.inclusive) "..=" else "..");
            if (r.end) |end| try self.emitExpr(end);
        } else if (fs.idx != null) {
            // Index requested but no explicit range — auto-add `0..`
            try self.writer.writeAll(", 0..");
        }

        try self.writer.writeAll(") |");
        if (fs.elem) |e| try self.writeZigIdent(e.lexeme) else try self.writer.writeAll("_");
        if (fs.idx) |i| {
            try self.writer.writeAll(", ");
            try self.writeZigIdent(i.lexeme);
        }
        try self.writer.writeAll("| {\n");
        self.indent_level += 1;
        try self.emitBlockStmts(fs.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
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
            " = (try std.io.getStdIn().reader().readUntilDelimiterOrEof(&_cin_buf_{d}, '\\n')) orelse \"\";\n",
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
        } else {
            const fmt: []const u8 = if (isStringLike(be.right)) "{s}" else "{any}";
            try self.writer.print("std.debug.print(\"{s}\", .{{", .{fmt});
            try self.emitExpr(be.right);
            try self.writer.writeAll("});\n");
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
            .fmt_expr     => |fe| try self.emitExpr(fe.value), // spec only meaningful in stream context
            else          => {},
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
        try self.emitExpr(be.left);
        try self.writer.writeByte(' ');
        try self.writer.writeAll(remapOp(be.op.lexeme));
        try self.writer.writeByte(' ');
        try self.emitExpr(be.right);
    }

    fn emitUnaryExpr(self: *CodeGen, ue: ast.UnaryExpr) !void {
        try self.writer.writeAll(ue.op.lexeme);
        try self.emitExpr(ue.operand);
    }

    fn emitCallExpr(self: *CodeGen, ce: ast.CallExpr) !void {
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
        const fmt = if (isStringLike(arg)) "{s}\\n" else "{any}\\n";
        try self.writer.print("std.debug.print(\"{s}\", .{{", .{fmt});
        try self.emitExpr(arg);
        try self.writer.writeAll("})");
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
                        try self.writeZigIdent(interpIdent(spec)); // ident part only
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
        for (self.current_block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            if (!std.mem.eql(u8, vd.name.lexeme, name)) continue;
            // Explicit type annotation takes priority.
            if (vd.type_ann) |ta| {
                if (std.mem.eql(u8, ta.name.lexeme, "str")) return "{s}";
                return "{any}";
            }
            // Infer from the initialiser expression.
            return switch (vd.value.*) {
                .string_lit           => "{s}",
                .int_lit, .float_lit  => "{d}",
                else                  => "{any}",
            };
        }
        return "{any}"; // identifier not found in this block
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
        try self.writeZigIdent(fe.field.lexeme);
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
        try self.writeZigIdent(sl.type_name.lexeme);
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

/// Return true if `name` ever appears as the direct left-hand side of an
/// assignment expression (`=`, `+=`, `-=`, `*=`, `/=`) inside `block`.
/// Only top-level expression-statements are checked — nested scopes are
/// intentionally ignored so we don't accidentally promote a variable that is
/// mutated inside an inner block to `const`.
fn isReassignedInBlock(name: []const u8, block: ast.Block) bool {
    for (block.stmts) |stmt| {
        if (stmt.* != .expr_stmt) continue;
        const expr = stmt.expr_stmt;
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
    }
    return false;
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
/// identifier, optionally followed by `:fmt_spec` (e.g. `name` or `y:.3f`).
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
    // Advance through the identifier portion.
    var i: usize = 1;
    while (i < spec.len and (spec[i] == '_' or std.ascii.isAlphanumeric(spec[i]))) i += 1;
    // After the ident: either end of string or `:` introducing a format spec.
    if (i == spec.len) return true;
    if (spec[i] == ':') return true;
    return false;
}

/// Return just the identifier prefix of `spec` (everything before any `:`).
fn interpIdent(spec: []const u8) []const u8 {
    var i: usize = 0;
    if (i < spec.len) i += 1; // first char (already validated)
    while (i < spec.len and (spec[i] == '_' or std.ascii.isAlphanumeric(spec[i]))) i += 1;
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
        "readUntilDelimiterOrEof(&_cin_buf_0, '\\n')"
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
