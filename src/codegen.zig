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
    /// Cross-scope registry of variables declared as plain `str` (string scalars).
    /// Populated in `emitVarDecl` so that inner-scope code (e.g. inside for bodies)
    /// can detect outer-scope str vars (needed by `isStrExpr` and `@str::cat`).
    str_var_names: [64][]const u8,
    str_var_count: usize,
    /// Cross-scope registry of variables opened via `@fs::FileReader::open`,
    /// `@fs::FileWriter::open`, `@fs::ByteReader::open`, `@fs::ByteWriter::open`.
    /// Allows method calls (`.rln()`, `.w()`, `.ri32()`, etc.) to be remapped.
    file_var_names: [64][]const u8,
    file_var_kinds: [64]FileVarKind,
    file_var_count: usize,
    /// Set to true when any `@omp::` usage or `@zcy.openmp` import is detected.
    /// Triggers `const _omp = @cImport(...)` in the preamble.
    uses_omp: bool,
    /// When non-null, `@omp::thread_id()` emits this variable name instead of
    /// `_omp.omp_get_thread_num()` — set inside parallel region codegen.
    omp_thread_id_var: ?[]const u8,
    /// Set to true when any `@sodium::` usage or `@zcy.sodium` import is detected.
    /// Triggers `const _sodium = @cImport(@cInclude("sodium.h"));` in the preamble.
    uses_sodium: bool,
    /// Set to true when any `@fflog::` usage is detected.
    /// Triggers `const _FfLog = struct { … };` in the preamble.
    uses_fflog: bool,
    /// Set to true when any `@sqlite::` usage or `@zcy.sqlite` import is detected.
    /// Triggers sqlite3 extern declarations + `_Sqlite3`/`_Sqlite3Stmt` in the preamble.
    uses_sqlite: bool,
    /// Set to true when any `@qt::` usage or `@zcy.qt` import is detected.
    /// Triggers Qt C wrapper extern declarations + `_QtApp`/`_QtWindow`/etc. in the preamble.
    uses_qt: bool,
    /// Set to true when any `@kry::` usage or `@zcy.kry` import is detected.
    /// Triggers crypto helpers (PBKDF2-HMAC-SHA512 + AES-256-GCM) in the preamble.
    /// No external library required — uses std.crypto only.
    uses_kry: bool,
    /// Set to true when any `@xi::` usage is detected.
    /// Triggers xi color/keyval preamble helpers and forces raylib import.
    uses_xi: bool,
    /// Registry of variable names created by `@xi::window(…)`.
    /// Allows method calls on these vars (win.fps, win.center, etc.) to be remapped.
    xi_var_names: [16][]const u8,
    xi_var_count: usize,
    /// Registry of variable names created by `@xi::font(…)`.
    xi_font_var_names: [16][]const u8,
    xi_font_var_count: usize,
    /// Registry of variable names created by `@xi::img(…)`.
    xi_img_var_names:  [16][]const u8,
    xi_img_var_count:  usize,
    /// Registry of variable names created by `@xi::gif(…)`.
    xi_gif_var_names:  [16][]const u8,
    xi_gif_var_count:  usize,
    /// Registry of xi handle vars that are *already pointers* (passed by ref
    /// via `&@xi::win` / `&@xi::img` etc. params). These skip the `&` prefix
    /// when passed to runtime helpers that expect `*_XiWin` / `*_XiImg` etc.
    xi_ref_var_names:  [32][]const u8,
    xi_ref_var_count:  usize,
    /// Registry of variables created by `@fs::ls(…)` — these are `?[]_ZcyDirEntry`
    /// optionals; field access and subscript auto-unwrap with `.?`.
    ls_var_names: [32][]const u8,
    ls_var_count: usize,
    /// Name of the innermost xi window var currently being used inside a
    /// `xi_keys` block body — allows win.key.char / win.key.code substitution.
    xi_keys_var: ?[]const u8,
    /// The event arm currently being emitted (e.g. "close", "key_press").
    /// Used by `emitExprStmt` to make `win.default` context-sensitive.
    xi_current_arm: ?[]const u8,
    /// Type name of the variable currently being declared (e.g. "i32", "f64").
    /// Set in `emitVarDecl` before emitting the value; used by `@str::parseNum`
    /// to select the correct Zig parse function and type parameter.
    pending_var_type: ?[]const u8,
    /// Registry of `@import(alias = @zcy.lib)` pairs, populated in `emitProgram`.
    /// Used by `emitPfRawExpr` to translate `alias.method()` inside @pf strings.
    alias_ns_aliases: [8][]const u8,
    alias_ns_names:   [8][]const u8,   // "@omp", "@rl", "@sodium", …
    alias_ns_count:   usize,
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
            .str_var_names  = undefined,
            .str_var_count  = 0,
            .file_var_names    = undefined,
            .file_var_kinds    = undefined,
            .file_var_count    = 0,
            .uses_omp          = false,
            .omp_thread_id_var = null,
            .uses_sodium       = false,
            .uses_fflog        = false,
            .uses_sqlite       = false,
            .uses_qt           = false,
            .uses_kry          = false,
            .uses_xi           = false,
            .xi_var_names      = undefined,
            .xi_var_count      = 0,
            .xi_font_var_names = undefined,
            .xi_font_var_count = 0,
            .xi_img_var_names  = undefined,
            .xi_img_var_count  = 0,
            .xi_gif_var_names  = undefined,
            .xi_gif_var_count  = 0,
            .xi_ref_var_names  = undefined,
            .xi_ref_var_count  = 0,
            .ls_var_names      = undefined,
            .ls_var_count      = 0,
            .xi_keys_var       = null,
            .xi_current_arm    = null,
            .pending_var_type  = null,
            .alias_ns_aliases  = undefined,
            .alias_ns_names    = undefined,
            .alias_ns_count    = 0,
        };
    }

    /// Scan `@import(alias = @zcy.lib)` top-level nodes and populate the alias registry.
    /// Called once at the start of `emitProgram`.
    fn populateAliasRegistry(self: *CodeGen, prog: ast.Program) void {
        for (prog.items) |item| {
            if (item.* != .expr_stmt) continue;
            const inner = item.expr_stmt;
            if (inner.* != .call_expr) continue;
            const ce = inner.call_expr;
            if (ce.callee.* != .builtin_expr) continue;
            if (!std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@import")) continue;
            for (ce.args) |arg| {
                if (arg.* != .binary_expr) continue;
                const be = arg.binary_expr;
                if (be.left.* != .ident_expr) continue;
                if (be.right.* != .field_expr) continue;
                const fe = be.right.field_expr;
                if (fe.object.* != .builtin_expr) continue;
                if (!std.mem.eql(u8, fe.object.builtin_expr.lexeme, "@zcy")) continue;
                const alias = be.left.ident_expr.lexeme;
                const lib   = fe.field.lexeme;
                const ns: []const u8 =
                    if (std.mem.eql(u8, lib, "openmp")) "@omp"
                    else if (std.mem.eql(u8, lib, "raylib"))  "@rl"
                    else if (std.mem.eql(u8, lib, "sodium"))  "@sodium"
                    else if (std.mem.eql(u8, lib, "sqlite"))  "@sqlite"
                    else if (std.mem.eql(u8, lib, "qt"))      "@qt"
                    else if (std.mem.eql(u8, lib, "kry"))     "@kry"
                    else continue;
                if (self.alias_ns_count < self.alias_ns_aliases.len) {
                    self.alias_ns_aliases[self.alias_ns_count] = alias;
                    self.alias_ns_names  [self.alias_ns_count] = ns;
                    self.alias_ns_count += 1;
                }
            }
        }
    }

    /// If `text` starts with a registered alias followed by `.`, return the
    /// namespace string (e.g. "@omp") and the length of the alias prefix.
    fn lookupAliasNs(self: *const CodeGen, text: []const u8) ?struct { ns: []const u8, alias_len: usize } {
        for (self.alias_ns_aliases[0..self.alias_ns_count], 0..) |alias, idx| {
            if (std.mem.startsWith(u8, text, alias) and
                text.len > alias.len and text[alias.len] == '.')
            {
                return .{ .ns = self.alias_ns_names[idx], .alias_len = alias.len };
            }
        }
        return null;
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

    fn recordXiVar(self: *CodeGen, name: []const u8) void {
        if (self.xi_var_count < self.xi_var_names.len) {
            self.xi_var_names[self.xi_var_count] = name;
            self.xi_var_count += 1;
        }
    }

    fn isXiVar(self: *const CodeGen, name: []const u8) bool {
        for (self.xi_var_names[0..self.xi_var_count]) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    fn recordXiFontVar(self: *CodeGen, name: []const u8) void {
        if (self.xi_font_var_count < self.xi_font_var_names.len) {
            self.xi_font_var_names[self.xi_font_var_count] = name;
            self.xi_font_var_count += 1;
        }
    }
    fn isXiFontVar(self: *const CodeGen, name: []const u8) bool {
        for (self.xi_font_var_names[0..self.xi_font_var_count]) |n|
            if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
    fn recordXiImgVar(self: *CodeGen, name: []const u8) void {
        if (self.xi_img_var_count < self.xi_img_var_names.len) {
            self.xi_img_var_names[self.xi_img_var_count] = name;
            self.xi_img_var_count += 1;
        }
    }
    fn isXiImgVar(self: *const CodeGen, name: []const u8) bool {
        for (self.xi_img_var_names[0..self.xi_img_var_count]) |n|
            if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
    fn recordXiGifVar(self: *CodeGen, name: []const u8) void {
        if (self.xi_gif_var_count < self.xi_gif_var_names.len) {
            self.xi_gif_var_names[self.xi_gif_var_count] = name;
            self.xi_gif_var_count += 1;
        }
    }
    fn isXiGifVar(self: *const CodeGen, name: []const u8) bool {
        for (self.xi_gif_var_names[0..self.xi_gif_var_count]) |n|
            if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
    fn recordXiRefVar(self: *CodeGen, name: []const u8) void {
        if (self.xi_ref_var_count < self.xi_ref_var_names.len) {
            self.xi_ref_var_names[self.xi_ref_var_count] = name;
            self.xi_ref_var_count += 1;
        }
    }
    /// True when `name` is an xi handle that was passed by reference (`&@xi::…`)
    /// and is therefore already a pointer — callers must NOT add `&` prefix.
    fn isXiRefVar(self: *const CodeGen, name: []const u8) bool {
        for (self.xi_ref_var_names[0..self.xi_ref_var_count]) |n|
            if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
    fn recordLsVar(self: *CodeGen, name: []const u8) void {
        if (self.ls_var_count < self.ls_var_names.len) {
            self.ls_var_names[self.ls_var_count] = name;
            self.ls_var_count += 1;
        }
    }
    /// True when `name` was created by `@fs::ls(…)` — it is `?[]_ZcyDirEntry`
    /// so field access and subscript must auto-unwrap with `.?`.
    fn isLsVar(self: *const CodeGen, name: []const u8) bool {
        for (self.ls_var_names[0..self.ls_var_count]) |n|
            if (std.mem.eql(u8, n, name)) return true;
        return false;
    }

    /// Pre-scan all var_decls and register xi window variable names so that
    /// method calls like win.fps() can be remapped before code is emitted.
    fn preScanXiVars(self: *CodeGen, prog: ast.Program) void {
        for (prog.items) |item| self.scanNodeForXiVars(item);
    }

    fn scanNodeForXiVars(self: *CodeGen, node: *ast.Node) void {
        switch (node.*) {
            .var_decl => |vd| {
                if (isXiWindowCall(vd.value))
                    self.recordXiVar(vd.name.lexeme);
                if (isXiFontCall(vd.value))
                    self.recordXiFontVar(vd.name.lexeme);
                // img may be wrapped in a catch_expr
                const raw_val_scan = if (vd.value.* == .catch_expr) vd.value.catch_expr.subject else vd.value;
                if (isXiImgCall(raw_val_scan))
                    self.recordXiImgVar(vd.name.lexeme);
                if (isXiGifCall(vd.value))
                    self.recordXiGifVar(vd.name.lexeme);
            },
            .fn_decl    => |fd| {
                // Register any @xi:: typed parameters so method calls inside
                // the function body are recognised and emitted correctly.
                for (fd.params) |p| {
                    if (p.type_ann) |ta| {
                        const tn = ta.name.lexeme;
                        if (std.mem.eql(u8, tn, "@xi::win")) self.recordXiVar(p.name.lexeme);
                        if (std.mem.eql(u8, tn, "@xi::img")) self.recordXiImgVar(p.name.lexeme);
                        if (std.mem.eql(u8, tn, "@xi::gif")) self.recordXiGifVar(p.name.lexeme);
                        if (std.mem.eql(u8, tn, "@xi::fnt")) self.recordXiFontVar(p.name.lexeme);
                        // NOTE: do NOT call recordXiRefVar here — ref-param tracking
                        // is scoped to each function's emission via emitFnDecl's
                        // save/restore, so a global pre-scan would pollute @main.
                    }
                }
                for (fd.body.stmts) |s| self.scanNodeForXiVars(s);
            },
            .main_block => |mb| for (mb.body.stmts) |s| self.scanNodeForXiVars(s),
            .if_stmt    => |is_| {
                for (is_.then_blk.stmts) |s| self.scanNodeForXiVars(s);
                if (is_.else_blk) |eb| for (eb.stmts) |s| self.scanNodeForXiVars(s);
            },
            .while_stmt => |ws| for (ws.body.stmts) |s| self.scanNodeForXiVars(s),
            .for_stmt   => |fs| for (fs.body.stmts) |s| self.scanNodeForXiVars(s),
            .block      => |b|  for (b.stmts) |s| self.scanNodeForXiVars(s),
            else => {},
        }
    }

    /// Pre-scan all var_decls in the entire program and register string
    /// variables in `str_var_names` before any code is emitted.  This ensures
    /// that `isStrExpr` works correctly for variables referenced from function
    /// bodies that are emitted before the declaring scope (e.g. `@main`).
    fn preScanStrVars(self: *CodeGen, prog: ast.Program) void {
        for (prog.items) |item| {
            switch (item.*) {
                .main_block => |mb| self.preScanBlock(mb.body),
                .fn_decl    => |fd| self.preScanBlock(fd.body),
                else        => {},
            }
        }
    }

    fn preScanBlock(self: *CodeGen, block: ast.Block) void {
        for (block.stmts) |stmt| {
            if (stmt.* != .var_decl) continue;
            const vd = stmt.var_decl;
            const is_str =
                (vd.type_ann != null and std.mem.eql(u8, vd.type_ann.?.name.lexeme, "str")) or
                (vd.value.* == .string_lit);
            if (is_str and self.str_var_count < self.str_var_names.len) {
                self.str_var_names[self.str_var_count] = vd.name.lexeme;
                self.str_var_count += 1;
            }
        }
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
        // Zcythe `NULL` → Zig `null`
        if (std.mem.eql(u8, name, "NULL")) {
            try self.writer.writeAll("null");
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
            // Subscript segments like `buf[0]` are emitted raw — the `[N]`
            // portion is a literal index, not a keyword that needs escaping.
            if (std.mem.indexOfScalar(u8, part, '[') != null) {
                try self.writer.writeAll(part);
            } else {
                try self.writeZigIdent(part);
            }
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
        if (std.mem.eql(u8, name, "str"))       return "[]const u8";
        if (std.mem.eql(u8, name, "char"))      return "u8";
        if (std.mem.eql(u8, name, "@xi::win"))  return "_XiWin";
        if (std.mem.eql(u8, name, "@xi::img"))  return "_XiImg";
        if (std.mem.eql(u8, name, "@xi::gif"))  return "_XiGif";
        if (std.mem.eql(u8, name, "@xi::fnt"))  return "_XiFont";
        return name;
    }

    fn emitTypeAnn(self: *CodeGen, ta: ast.TypeAnn) !void {
        if (ta.is_self) {
            // @self → *@This() (pointer to the enclosing struct/cls instance)
            try self.writer.writeAll("*@This()");
            return;
        }
        if (ta.is_array) {
            try self.writer.writeByte('[');
            if (ta.array_size) |sz| try self.writer.writeAll(sz.lexeme);
            try self.writer.writeByte(']');
        } else if (ta.is_ptr) {
            try self.writer.writeByte('*');
            if (ta.is_const_ptr) try self.writer.writeAll("const ");
        }
        try self.writer.writeAll(mapType(ta.name.lexeme));
    }

    /// Emit a node as a type name (used when a type is passed as a value expression,
    /// e.g. the first arg of `@alo(i32, N)`).
    fn emitTypeExpr(self: *CodeGen, node: *const ast.Node) !void {
        switch (node.*) {
            .ident_expr => |tok| try self.writer.writeAll(mapType(tok.lexeme)),
            .builtin_expr => |tok| try self.writer.writeAll(mapType(tok.lexeme)),
            else => try self.emitExpr(node),
        }
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
        if (std.mem.eql(u8, lexeme, "&&"))  return "and";
        if (std.mem.eql(u8, lexeme, "||"))  return "or";
        if (std.mem.eql(u8, lexeme, "and")) return "and";
        if (std.mem.eql(u8, lexeme, "or"))  return "or";
        return lexeme;
    }

    /// Precedence levels for binary operators (higher = tighter binding).
    /// Used to decide whether to emit parens around sub-binary-expressions.
    fn binOpPrec(op: []const u8) u8 {
        if (std.mem.eql(u8, op, "||") or std.mem.eql(u8, op, "or"))  return 1;
        if (std.mem.eql(u8, op, "&&") or std.mem.eql(u8, op, "and")) return 2;
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=")) return 3;
        if (std.mem.eql(u8, op, "<")  or std.mem.eql(u8, op, ">") or
            std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">=")) return 4;
        if (std.mem.eql(u8, op, "+")  or std.mem.eql(u8, op, "-")) return 5;
        if (std.mem.eql(u8, op, "*")  or std.mem.eql(u8, op, "/") or
            std.mem.eql(u8, op, "%")) return 6;
        return 0;
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

            // ── @zcy.<pkg>: Zcythe package namespace ──────────────────────
            // `rl = @zcy.raylib`  → `const rl = @import("raylib");`
            // `omp = @zcy.openmp` → suppressed (preamble emits _omp cImport)
            if (mod_node.* == .builtin_expr and
                std.mem.eql(u8, mod_node.builtin_expr.lexeme, "@zcy"))
            {
                if (field_tok) |ft| {
                    if (std.mem.eql(u8, ft.lexeme, "openmp")) continue; // handled by preamble
                    if (std.mem.eql(u8, ft.lexeme, "sodium")) continue; // handled by preamble
                    if (std.mem.eql(u8, ft.lexeme, "sqlite")) continue; // handled by preamble
                    if (std.mem.eql(u8, ft.lexeme, "qt"))     continue; // handled by preamble
                    try self.writer.writeAll("const ");
                    try self.writeZigIdent(alias);
                    try self.writer.writeAll(" = @import(\"");
                    try self.writer.writeAll(ft.lexeme);
                    try self.writer.writeAll("\");\n");
                    continue;
                }
            }

            // ── Known native packages (no .zig suffix) ────────────────
            // `@import(rl = raylib)` without `zcy.` — emit as named module.
            if (field_tok == null and mod_node.* == .ident_expr) {
                const native_pkgs = [_][]const u8{ "raylib" };
                const mn = mod_node.ident_expr.lexeme;
                var is_native = false;
                for (native_pkgs) |pkg| {
                    if (std.mem.eql(u8, mn, pkg)) { is_native = true; break; }
                }
                if (is_native) {
                    try self.writer.writeAll("const ");
                    try self.writeZigIdent(alias);
                    try self.writer.writeAll(" = @import(\"");
                    try self.writer.writeAll(mn);
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

    // ─── Heap declarations ─────────────────────────────────────────────────

    fn emitUnnDecl(self: *CodeGen, ud: ast.UnnDecl) !void {
        if (ud.is_enum) {
            try self.writer.writeAll("pub const ");
            try self.writeZigIdent(ud.name.lexeme);
            try self.writer.writeAll(" = union(enum) {\n");
        } else {
            try self.writer.writeAll("pub const ");
            try self.writeZigIdent(ud.name.lexeme);
            try self.writer.writeAll(" = union {\n");
        }
        for (ud.fields) |f| {
            try self.writer.writeAll("    ");
            try self.writeZigIdent(f.name.lexeme);
            try self.writer.writeAll(": ");
            try self.emitTypeAnn(f.type_ann);
            try self.writer.writeAll(",\n");
        }
        try self.writer.writeAll("};\n");
    }

    // ─── Class declarations ────────────────────────────────────────────────

    fn emitClsDecl(self: *CodeGen, cd: ast.ClsDecl) !void {
        // Implements comment
        if (cd.implements.len > 0) {
            try self.writer.writeAll("// implements:");
            for (cd.implements, 0..) |iface, i| {
                if (i > 0) try self.writer.writeByte(',');
                try self.writer.writeByte(' ');
                try self.writer.writeAll(iface.lexeme);
            }
            try self.writer.writeByte('\n');
        }

        try self.writer.writeAll("pub const ");
        try self.writeZigIdent(cd.name.lexeme);
        try self.writer.writeAll(" = struct {\n");

        // Extends → embedded base field
        if (cd.extends) |ext| {
            if (ext.is_pub) {
                try self.writer.writeAll("    pub _base: ");
            } else {
                try self.writer.writeAll("    _base: ");
            }
            try self.writeZigIdent(ext.name.lexeme);
            try self.writer.writeAll(",\n");
        }

        // Fields
        for (cd.members) |member| {
            switch (member) {
                .field => |f| {
                    try self.writer.writeAll("    ");
                    if (f.is_pub) try self.writer.writeAll("pub ");
                    try self.writeZigIdent(f.name.lexeme);
                    try self.writer.writeAll(": ");
                    try self.emitTypeAnn(f.type_ann);
                    try self.writer.writeAll(",\n");
                },
                else => {},
            }
        }

        // Methods
        for (cd.members) |member| {
            switch (member) {
                .init_block => |body| {
                    try self.writer.writeAll("    pub fn init(self: *@This()) void {\n");
                    self.indent_level = 2;
                    try self.emitBlockStmts(body);
                    self.indent_level = 0;
                    try self.writer.writeAll("    }\n");
                },
                .deinit_block => |body| {
                    try self.writer.writeAll("    pub fn deinit(self: *@This()) void {\n");
                    self.indent_level = 2;
                    try self.emitBlockStmts(body);
                    self.indent_level = 0;
                    try self.writer.writeAll("    }\n");
                },
                .method => |m| {
                    try self.writer.writeAll("    ");
                    if (m.is_pub) try self.writer.writeAll("pub ");
                    try self.writer.writeAll("fn ");
                    try self.writeZigIdent(m.name.lexeme);
                    try self.writer.writeAll("(self: *@This()");
                    for (m.params) |param| {
                        try self.writer.writeAll(", ");
                        try self.emitParam(param);
                    }
                    try self.writer.writeAll(") ");
                    if (m.ret_type) |rt| {
                        try self.emitTypeAnn(rt);
                    } else {
                        try self.writer.writeAll("void");
                    }
                    try self.writer.writeAll(" {\n");
                    self.indent_level = 2;
                    try self.emitBlockStmts(m.body);
                    self.indent_level = 0;
                    try self.writer.writeAll("    }\n");
                },
                .field => {},
            }
        }

        try self.writer.writeAll("};\n\n");
    }

    /// Returns true for types that Zig supports as enum backing types (integers only).
    fn isIntBackingType(name: []const u8) bool {
        if (std.mem.eql(u8, name, "char") or
            std.mem.eql(u8, name, "usize") or
            std.mem.eql(u8, name, "isize") or
            std.mem.eql(u8, name, "comptime_int")) return true;
        // u8, u16, u32, u64, u128, i8, i16, i32, i64, i128, etc.
        if (name.len >= 2 and (name[0] == 'u' or name[0] == 'i')) {
            for (name[1..]) |c| {
                if (c < '0' or c > '9') return false;
            }
            return true;
        }
        return false;
    }

    fn emitEnumDecl(self: *CodeGen, ed: ast.EnumDecl) !void {
        try self.writer.writeAll("pub const ");
        try self.writeZigIdent(ed.name.lexeme);

        if (ed.backing_type) |bt| {
            if (isIntBackingType(bt.lexeme)) {
                // Integer-backed: Zig supports enum(T) natively.
                const zig_int = mapType(bt.lexeme);
                try self.writer.writeAll(" = enum(");
                try self.writer.writeAll(zig_int);
                try self.writer.writeAll(") {\n");
                for (ed.variants) |v| {
                    try self.writer.writeAll("    ");
                    try self.writeZigIdent(v.name.lexeme);
                    if (v.value) |val| {
                        try self.writer.writeAll(" = ");
                        try self.emitExpr(val);
                    }
                    try self.writer.writeAll(",\n");
                }
                // .val() shorthand: returns the underlying integer value.
                try self.writer.writeAll("    pub fn val(self: ");
                try self.writeZigIdent(ed.name.lexeme);
                try self.writer.writeAll(") ");
                try self.writer.writeAll(zig_int);
                try self.writer.writeAll(" { return @intFromEnum(self); }\n");
                try self.writer.writeAll("};\n");
            } else {
                // Non-integer backing (str, f32, f64, bool, ...):
                // Zig only supports integer enum backing types, so emit a plain
                // enum with a .value() method returning the backing type.
                const zig_type = mapType(bt.lexeme);
                try self.writer.writeAll(" = enum {\n");
                for (ed.variants) |v| {
                    try self.writer.writeAll("    ");
                    try self.writeZigIdent(v.name.lexeme);
                    try self.writer.writeAll(",\n");
                }
                try self.writer.writeAll("    pub fn value(self: ");
                try self.writeZigIdent(ed.name.lexeme);
                try self.writer.writeAll(") ");
                try self.writer.writeAll(zig_type);
                try self.writer.writeAll(" {\n");
                try self.writer.writeAll("        return switch (self) {\n");
                for (ed.variants) |v| {
                    try self.writer.writeAll("            .");
                    try self.writeZigIdent(v.name.lexeme);
                    try self.writer.writeAll(" => ");
                    if (v.value) |val| {
                        try self.emitExpr(val);
                    } else {
                        try self.writer.writeByte('"');
                        try self.writer.writeAll(v.name.lexeme);
                        try self.writer.writeByte('"');
                    }
                    try self.writer.writeAll(",\n");
                }
                try self.writer.writeAll("        };\n");
                try self.writer.writeAll("    }\n");
                try self.writer.writeAll("};\n");
            }
        } else {
            // Plain enum: `enum { A, B, C }`
            try self.writer.writeAll(" = enum {\n");
            for (ed.variants) |v| {
                try self.writer.writeAll("    ");
                try self.writeZigIdent(v.name.lexeme);
                try self.writer.writeAll(",\n");
            }
            try self.writer.writeAll("};\n");
        }
    }

    // ─── Program ───────────────────────────────────────────────────────────

    fn emitProgram(self: *CodeGen, prog: ast.Program) !void {
        self.program = prog;
        // Populate alias registry so emitPfRawExpr can translate alias.method().
        self.populateAliasRegistry(prog);
        // Populate str_var_names before emitting any code so that
        // isStrExpr works correctly for cross-function references.
        self.preScanStrVars(prog);
        try self.writer.writeAll("const std = @import(\"std\");\n");
        const uses_rl = programUsesRl(prog);
        self.uses_omp     = programUsesOmp(prog);
        self.uses_sodium  = programUsesSodium(prog);
        self.uses_fflog   = programUsesFflog(prog);
        self.uses_sqlite  = programUsesSqlite(prog);
        self.uses_qt      = programUsesQt(prog);
        self.uses_kry     = programUsesKry(prog);
        self.uses_xi      = programUsesXi(prog);
        if (self.uses_xi) self.preScanXiVars(prog);
        // Only emit the auto-import when the program doesn't already have an
        // explicit `@import(rl = @zcy.raylib)` — that path emits the same line.
        if (uses_rl and !programHasRlImport(prog)) {
            try self.writer.writeAll("const rl = @import(\"raylib\");\n");
        }
        if (self.uses_xi) {
            try self.writer.writeAll("const c = @cImport({ @cInclude(\"stdio.h\"); @cInclude(\"SDL2/SDL.h\"); @cInclude(\"SDL2/SDL_ttf.h\"); @cInclude(\"SDL2/SDL_image.h\"); });\n");
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
            \\/// Like _zcyInput but disables terminal echo for password entry.
            \\fn _zcySecInput(prompt: []const u8) []const u8 {
            \\    std.debug.print("{s}", .{prompt});
            \\    const stdin_fd = std.fs.File.stdin().handle;
            \\    const old_term = std.posix.tcgetattr(stdin_fd) catch null;
            \\    if (old_term) |term| {
            \\        var t = term;
            \\        t.lflag.ECHO = false;
            \\        std.posix.tcsetattr(stdin_fd, .NOW, t) catch {};
            \\    }
            \\    defer if (old_term) |term| {
            \\        std.posix.tcsetattr(stdin_fd, .NOW, term) catch {};
            \\    };
            \\    var buf: [4096]u8 = undefined;
            \\    const line = std.fs.File.stdin().deprecatedReader()
            \\        .readUntilDelimiterOrEof(&buf, '\n') catch return "";
            \\    if (old_term != null) std.debug.print("\n", .{});
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
            \\// @fs::ls — directory listing entry
            \\const _ZcyDirEntry = struct {
            \\    _abs: []const u8,
            \\    pub fn path(self: @This()) []const u8 { return self._abs; }
            \\    pub fn is_file(self: @This()) bool { return _zcyFsIsFile(self._abs); }
            \\    pub fn is_dir(self: @This()) bool  { return _zcyFsIsDir(self._abs);  }
            \\};
            \\fn _zcyFsLs(dir_path: []const u8) ?[]_ZcyDirEntry {
            \\    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return null;
            \\    defer dir.close();
            \\    var list: std.ArrayListUnmanaged(_ZcyDirEntry) = .empty;
            \\    var it = dir.iterate();
            \\    while (it.next() catch null) |ent| {
            \\        const full = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{dir_path, ent.name}) catch continue;
            \\        list.append(std.heap.page_allocator, .{ ._abs = full }) catch continue;
            \\    }
            \\    return list.toOwnedSlice(std.heap.page_allocator) catch null;
            \\}

            \\fn _zcyFsEof(f: std.fs.File) bool {
            \\    var buf: [1]u8 = undefined;
            \\    const n = f.read(&buf) catch return true;
            \\    if (n == 0) return true;
            \\    f.seekBy(-1) catch {};
            \\    return false;
            \\}
            \\/// @rng(T, min, max) — inclusive random value in [min, max].
            \\/// Integer types use intRangeAtMost; float types scale a [0,1) float.
            \\fn _zcyRng(comptime T: type, min: T, max: T) T {
            \\    return switch (@typeInfo(T)) {
            \\        .float => min + std.crypto.random.float(T) * (max - min),
            \\        else   => std.crypto.random.intRangeAtMost(T, min, max),
            \\    };
            \\}
            \\/// Numeric cast to a float type — handles both int→float and float→float.
            \\inline fn _zcyToFloat(comptime T: type, v: anytype) T {
            \\    return switch (@typeInfo(@TypeOf(v))) {
            \\        .float, .comptime_float => @floatCast(v),
            \\        else => @floatFromInt(v),
            \\    };
            \\}
            \\/// Numeric cast to an integer type — handles both float→int and int→int.
            \\inline fn _zcyToInt(comptime T: type, v: anytype) T {
            \\    return switch (@typeInfo(@TypeOf(v))) {
            \\        .float, .comptime_float => @intFromFloat(v),
            \\        else => @intCast(v),
            \\    };
            \\}
            \\
        );
        if (uses_rl) {
            try self.writer.writeAll(
                \\/// Convert a Zcythe `str` ([]const u8) to a null-terminated [:0]const u8
                \\/// for raylib functions that require C-style strings.
                \\var _zcyRlStrBuf: [4096]u8 = undefined;
                \\fn _zcyRlStr(s: []const u8) [:0]const u8 {
                \\    const n = @min(s.len, _zcyRlStrBuf.len - 1);
                \\    @memcpy(_zcyRlStrBuf[0..n], s[0..n]);
                \\    _zcyRlStrBuf[n] = 0;
                \\    return _zcyRlStrBuf[0..n :0];
                \\}
                \\
            );
        }
        if (self.uses_omp) {
            // Declare omp runtime functions directly instead of @cImport to
            // avoid clang-incompatible __malloc__ attribute in GCC 15 omp.h.
            try self.writer.writeAll(
                \\const _omp = struct {
                \\    pub extern fn omp_set_num_threads(n: c_int) void;
                \\    pub extern fn omp_get_num_threads() c_int;
                \\    pub extern fn omp_get_max_threads() c_int;
                \\    pub extern fn omp_get_thread_num() c_int;
                \\    pub extern fn omp_in_parallel() c_int;
                \\    pub extern fn omp_get_wtime() f64;
                \\};
                \\
            );
        }
        if (self.uses_sodium) {
            try self.writer.writeAll("const _sodium = @cImport(@cInclude(\"sodium.h\"));\n");
            try self.writer.writeAll(
                \\fn _sodiumEncFile(path: []const u8, key_str: []const u8) void {
                \\    var _key: [32]u8 = undefined;
                \\    _ = _sodium.crypto_generichash(&_key, _key.len, key_str.ptr, @as(c_ulonglong, key_str.len), null, 0);
                \\    const _plain = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 26) catch return;
                \\    defer std.heap.page_allocator.free(_plain);
                \\    var _nonce: [24]u8 = undefined;
                \\    _sodium.randombytes_buf(&_nonce, _nonce.len);
                \\    const _ct = std.heap.page_allocator.alloc(u8, _plain.len + 16) catch return;
                \\    defer std.heap.page_allocator.free(_ct);
                \\    if (_sodium.crypto_secretbox_easy(_ct.ptr, _plain.ptr, @as(c_ulonglong, _plain.len), &_nonce, &_key) != 0) return;
                \\    const _f = std.fs.cwd().createFile(path, .{}) catch return;
                \\    defer _f.close();
                \\    _f.writeAll(&_nonce) catch return;
                \\    _f.writeAll(_ct) catch return;
                \\}
                \\fn _sodiumDecFile(path: []const u8, key_str: []const u8) void {
                \\    var _key: [32]u8 = undefined;
                \\    _ = _sodium.crypto_generichash(&_key, _key.len, key_str.ptr, @as(c_ulonglong, key_str.len), null, 0);
                \\    const _blob = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 26) catch return;
                \\    defer std.heap.page_allocator.free(_blob);
                \\    if (_blob.len < 40) return;
                \\    const _nonce = _blob[0..24];
                \\    const _ct = _blob[24..];
                \\    if (_ct.len < 16) return;
                \\    const _pt = std.heap.page_allocator.alloc(u8, _ct.len - 16) catch return;
                \\    defer std.heap.page_allocator.free(_pt);
                \\    if (_sodium.crypto_secretbox_open_easy(_pt.ptr, _ct.ptr, @as(c_ulonglong, _ct.len), _nonce.ptr, &_key) != 0) return;
                \\    const _f = std.fs.cwd().createFile(path, .{}) catch return;
                \\    defer _f.close();
                \\    _f.writeAll(_pt) catch return;
                \\}
                \\
            );
        }

        if (self.uses_kry) {
            try self.writer.writeAll(
                \\// ── @kry crypto helpers (std.crypto only, no external deps) ─────────
                \\fn _kryHash(password: []const u8) []const u8 {
                \\    var salt: [32]u8 = undefined;
                \\    std.crypto.random.bytes(&salt);
                \\    var key: [32]u8 = undefined;
                \\    std.crypto.pwhash.pbkdf2(&key, password, &salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha512) catch return "";
                \\    const out = std.heap.page_allocator.alloc(u8, 129) catch return "";
                \\    const salt_hex = std.fmt.bytesToHex(salt, .lower);
                \\    const key_hex  = std.fmt.bytesToHex(key,  .lower);
                \\    const result = std.fmt.bufPrint(out, "{s}${s}", .{salt_hex, key_hex}) catch return "";
                \\    return result;
                \\}
                \\fn _kryHashAuth(password: []const u8, stored: []const u8) bool {
                \\    if (stored.len < 129) return false;
                \\    if (stored[64] != '$') return false;
                \\    var salt: [32]u8 = undefined;
                \\    _ = std.fmt.hexToBytes(&salt, stored[0..64]) catch return false;
                \\    var expected_key: [32]u8 = undefined;
                \\    _ = std.fmt.hexToBytes(&expected_key, stored[65..129]) catch return false;
                \\    var derived_key: [32]u8 = undefined;
                \\    std.crypto.pwhash.pbkdf2(&derived_key, password, &salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha512) catch return false;
                \\    return std.mem.eql(u8, &derived_key, &expected_key);
                \\}
                \\fn _kryEncFile(path: []const u8, password: []const u8) void {
                \\    const Aes = std.crypto.aead.aes_gcm.Aes256Gcm;
                \\    const plain = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 30) catch return;
                \\    defer std.heap.page_allocator.free(plain);
                \\    var salt: [32]u8 = undefined;
                \\    std.crypto.random.bytes(&salt);
                \\    var nonce: [Aes.nonce_length]u8 = undefined;
                \\    std.crypto.random.bytes(&nonce);
                \\    var key: [Aes.key_length]u8 = undefined;
                \\    std.crypto.pwhash.pbkdf2(&key, password, &salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha512) catch return;
                \\    const ct = std.heap.page_allocator.alloc(u8, plain.len + Aes.tag_length) catch return;
                \\    defer std.heap.page_allocator.free(ct);
                \\    var tag: [Aes.tag_length]u8 = undefined;
                \\    Aes.encrypt(ct[0..plain.len], &tag, plain, "", nonce, key);
                \\    @memcpy(ct[plain.len..], &tag);
                \\    const f = std.fs.cwd().createFile(path, .{}) catch return;
                \\    defer f.close();
                \\    f.writeAll(&salt) catch return;
                \\    f.writeAll(&nonce) catch return;
                \\    f.writeAll(ct) catch return;
                \\}
                \\fn _kryDecFile(path: []const u8, password: []const u8) void {
                \\    const Aes = std.crypto.aead.aes_gcm.Aes256Gcm;
                \\    const blob = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 30) catch return;
                \\    defer std.heap.page_allocator.free(blob);
                \\    const header_len = 32 + Aes.nonce_length;
                \\    if (blob.len < header_len + Aes.tag_length) return;
                \\    const salt = blob[0..32];
                \\    const nonce = blob[32..][0..Aes.nonce_length].*;
                \\    const ct_and_tag = blob[header_len..];
                \\    const ct_len = ct_and_tag.len - Aes.tag_length;
                \\    const ct = ct_and_tag[0..ct_len];
                \\    const tag = ct_and_tag[ct_len..][0..Aes.tag_length].*;
                \\    var key: [Aes.key_length]u8 = undefined;
                \\    std.crypto.pwhash.pbkdf2(&key, password, salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha512) catch return;
                \\    const pt = std.heap.page_allocator.alloc(u8, ct_len) catch return;
                \\    defer std.heap.page_allocator.free(pt);
                \\    Aes.decrypt(pt, ct, tag, "", nonce, key) catch return;
                \\    const f = std.fs.cwd().createFile(path, .{}) catch return;
                \\    defer f.close();
                \\    f.writeAll(pt) catch return;
                \\}
                \\
            );
        }

        if (self.uses_xi) {
            try self.writer.writeAll(
                \\// ── @xi SDL2 renderer runtime ────────────────────────────────────────
                \\var _xi_renderer: ?*c.SDL_Renderer = null;
                \\const _XiColor = struct { r: u8, g: u8, b: u8, a: u8 };
                \\const _XiColors = struct {
                \\    pub const black      = _XiColor{ .r=0,   .g=0,   .b=0,   .a=255 };
                \\    pub const white      = _XiColor{ .r=255, .g=255, .b=255, .a=255 };
                \\    pub const red        = _XiColor{ .r=230, .g=41,  .b=55,  .a=255 };
                \\    pub const green      = _XiColor{ .r=0,   .g=228, .b=48,  .a=255 };
                \\    pub const blue       = _XiColor{ .r=0,   .g=121, .b=241, .a=255 };
                \\    pub const yellow     = _XiColor{ .r=253, .g=249, .b=0,   .a=255 };
                \\    pub const orange     = _XiColor{ .r=255, .g=161, .b=0,   .a=255 };
                \\    pub const pink       = _XiColor{ .r=255, .g=109, .b=194, .a=255 };
                \\    pub const purple     = _XiColor{ .r=200, .g=122, .b=255, .a=255 };
                \\    pub const darkgray   = _XiColor{ .r=80,  .g=80,  .b=80,  .a=255 };
                \\    pub const gray       = _XiColor{ .r=130, .g=130, .b=130, .a=255 };
                \\    pub const lightgray  = _XiColor{ .r=200, .g=200, .b=200, .a=255 };
                \\    pub const skyblue    = _XiColor{ .r=102, .g=191, .b=255, .a=255 };
                \\    pub const lime       = _XiColor{ .r=0,   .g=158, .b=47,  .a=255 };
                \\    pub const darkblue   = _XiColor{ .r=0,   .g=82,  .b=172, .a=255 };
                \\    pub const darkgreen  = _XiColor{ .r=0,   .g=117, .b=44,  .a=255 };
                \\    pub const darkpurple = _XiColor{ .r=112, .g=31,  .b=126, .a=255 };
                \\    pub const darkbrown  = _XiColor{ .r=76,  .g=63,  .b=31,  .a=255 };
                \\    pub const brown      = _XiColor{ .r=127, .g=106, .b=79,  .a=255 };
                \\    pub const beige      = _XiColor{ .r=211, .g=176, .b=140, .a=255 };
                \\    pub const maroon     = _XiColor{ .r=190, .g=33,  .b=55,  .a=255 };
                \\    pub const gold       = _XiColor{ .r=255, .g=203, .b=0,   .a=255 };
                \\    pub const violet     = _XiColor{ .r=135, .g=60,  .b=190, .a=255 };
                \\    pub const magenta    = _XiColor{ .r=255, .g=0,   .b=255, .a=255 };
                \\    pub const raywhite   = _XiColor{ .r=245, .g=245, .b=245, .a=255 };
                \\    pub const blank      = _XiColor{ .r=0,   .g=0,   .b=0,   .a=0   };
                \\    pub const crimson    = _XiColor{ .r=220, .g=20,  .b=60,  .a=255 };
                \\    pub const teal       = _XiColor{ .r=0,   .g=128, .b=128, .a=255 };
                \\    pub const indigo     = _XiColor{ .r=75,  .g=0,   .b=130, .a=255 };
                \\    pub const silver     = _XiColor{ .r=192, .g=192, .b=192, .a=255 };
                \\    pub const tan        = _XiColor{ .r=210, .g=180, .b=140, .a=255 };
                \\    pub const coral      = _XiColor{ .r=255, .g=127, .b=80,  .a=255 };
                \\    pub const clear      = _XiColor{ .r=0,   .g=0,   .b=0,   .a=0   };
                \\};
                \\const _XiKeyval = struct {
                \\    pub const A: c.SDL_Keycode = c.SDLK_a; pub const B: c.SDL_Keycode = c.SDLK_b;
                \\    pub const C: c.SDL_Keycode = c.SDLK_c; pub const D: c.SDL_Keycode = c.SDLK_d;
                \\    pub const E: c.SDL_Keycode = c.SDLK_e; pub const F: c.SDL_Keycode = c.SDLK_f;
                \\    pub const G: c.SDL_Keycode = c.SDLK_g; pub const H: c.SDL_Keycode = c.SDLK_h;
                \\    pub const I: c.SDL_Keycode = c.SDLK_i; pub const J: c.SDL_Keycode = c.SDLK_j;
                \\    pub const K: c.SDL_Keycode = c.SDLK_k; pub const L: c.SDL_Keycode = c.SDLK_l;
                \\    pub const M: c.SDL_Keycode = c.SDLK_m; pub const N: c.SDL_Keycode = c.SDLK_n;
                \\    pub const O: c.SDL_Keycode = c.SDLK_o; pub const P: c.SDL_Keycode = c.SDLK_p;
                \\    pub const Q: c.SDL_Keycode = c.SDLK_q; pub const R: c.SDL_Keycode = c.SDLK_r;
                \\    pub const S: c.SDL_Keycode = c.SDLK_s; pub const T: c.SDL_Keycode = c.SDLK_t;
                \\    pub const U: c.SDL_Keycode = c.SDLK_u; pub const V: c.SDL_Keycode = c.SDLK_v;
                \\    pub const W: c.SDL_Keycode = c.SDLK_w; pub const X: c.SDL_Keycode = c.SDLK_x;
                \\    pub const Y: c.SDL_Keycode = c.SDLK_y; pub const Z: c.SDL_Keycode = c.SDLK_z;
                \\    pub const @"0": c.SDL_Keycode = c.SDLK_0; pub const @"1": c.SDL_Keycode = c.SDLK_1;
                \\    pub const @"2": c.SDL_Keycode = c.SDLK_2; pub const @"3": c.SDL_Keycode = c.SDLK_3;
                \\    pub const @"4": c.SDL_Keycode = c.SDLK_4; pub const @"5": c.SDL_Keycode = c.SDLK_5;
                \\    pub const @"6": c.SDL_Keycode = c.SDLK_6; pub const @"7": c.SDL_Keycode = c.SDLK_7;
                \\    pub const @"8": c.SDL_Keycode = c.SDLK_8; pub const @"9": c.SDL_Keycode = c.SDLK_9;
                \\    pub const ESC:   c.SDL_Keycode = c.SDLK_ESCAPE;    pub const ENTER: c.SDL_Keycode = c.SDLK_RETURN;
                \\    pub const SPACE: c.SDL_Keycode = c.SDLK_SPACE;     pub const TAB:   c.SDL_Keycode = c.SDLK_TAB;
                \\    pub const BACK:  c.SDL_Keycode = c.SDLK_BACKSPACE; pub const DEL:   c.SDL_Keycode = c.SDLK_DELETE;
                \\    pub const UP:    c.SDL_Keycode = c.SDLK_UP;        pub const DOWN:  c.SDL_Keycode = c.SDLK_DOWN;
                \\    pub const LEFT:  c.SDL_Keycode = c.SDLK_LEFT;      pub const RIGHT: c.SDL_Keycode = c.SDLK_RIGHT;
                \\    pub const F1:  c.SDL_Keycode = c.SDLK_F1;  pub const F2:  c.SDL_Keycode = c.SDLK_F2;
                \\    pub const F3:  c.SDL_Keycode = c.SDLK_F3;  pub const F4:  c.SDL_Keycode = c.SDLK_F4;
                \\    pub const F5:  c.SDL_Keycode = c.SDLK_F5;  pub const F6:  c.SDL_Keycode = c.SDLK_F6;
                \\    pub const F7:  c.SDL_Keycode = c.SDLK_F7;  pub const F8:  c.SDL_Keycode = c.SDLK_F8;
                \\    pub const F9:  c.SDL_Keycode = c.SDLK_F9;  pub const F10: c.SDL_Keycode = c.SDLK_F10;
                \\    pub const F11: c.SDL_Keycode = c.SDLK_F11; pub const F12: c.SDL_Keycode = c.SDLK_F12;
                \\    pub const LSHIFT: c.SDL_Keycode = c.SDLK_LSHIFT; pub const RSHIFT: c.SDL_Keycode = c.SDLK_RSHIFT;
                \\    pub const LCTRL:  c.SDL_Keycode = c.SDLK_LCTRL;  pub const RCTRL:  c.SDL_Keycode = c.SDLK_RCTRL;
                \\    pub const LALT:   c.SDL_Keycode = c.SDLK_LALT;   pub const RALT:   c.SDL_Keycode = c.SDLK_RALT;
                \\    pub const LGUI:   c.SDL_Keycode = c.SDLK_LGUI;   pub const RGUI:   c.SDL_Keycode = c.SDLK_RGUI;
                \\    pub const MENU:   c.SDL_Keycode = c.SDLK_APPLICATION;
                \\    pub const GRAVE:     c.SDL_Keycode = c.SDLK_BACKQUOTE;  pub const MINUS:    c.SDL_Keycode = c.SDLK_MINUS;
                \\    pub const EQUALS:    c.SDL_Keycode = c.SDLK_EQUALS;     pub const LBRACKET: c.SDL_Keycode = c.SDLK_LEFTBRACKET;
                \\    pub const RBRACKET:  c.SDL_Keycode = c.SDLK_RIGHTBRACKET; pub const BACKSLASH: c.SDL_Keycode = c.SDLK_BACKSLASH;
                \\    pub const SEMICOLON: c.SDL_Keycode = c.SDLK_SEMICOLON; pub const QUOTE:    c.SDL_Keycode = c.SDLK_QUOTE;
                \\    pub const COMMA:     c.SDL_Keycode = c.SDLK_COMMA;     pub const PERIOD:   c.SDL_Keycode = c.SDLK_PERIOD;
                \\    pub const SLASH:     c.SDL_Keycode = c.SDLK_SLASH;
                \\    pub const INS:    c.SDL_Keycode = c.SDLK_INSERT;   pub const HOME:   c.SDL_Keycode = c.SDLK_HOME;
                \\    pub const PGUP:   c.SDL_Keycode = c.SDLK_PAGEUP;   pub const PGDN:   c.SDL_Keycode = c.SDLK_PAGEDOWN;
                \\    pub const END:    c.SDL_Keycode = c.SDLK_END;
                \\    pub const CAPS:    c.SDL_Keycode = c.SDLK_CAPSLOCK;   pub const NUMLOCK:  c.SDL_Keycode = c.SDLK_NUMLOCKCLEAR;
                \\    pub const SCROLL:  c.SDL_Keycode = c.SDLK_SCROLLLOCK;
                \\    pub const PRTSCR:  c.SDL_Keycode = c.SDLK_PRINTSCREEN; pub const PAUSE:    c.SDL_Keycode = c.SDLK_PAUSE;
                \\    pub const KP0: c.SDL_Keycode = c.SDLK_KP_0; pub const KP1: c.SDL_Keycode = c.SDLK_KP_1;
                \\    pub const KP2: c.SDL_Keycode = c.SDLK_KP_2; pub const KP3: c.SDL_Keycode = c.SDLK_KP_3;
                \\    pub const KP4: c.SDL_Keycode = c.SDLK_KP_4; pub const KP5: c.SDL_Keycode = c.SDLK_KP_5;
                \\    pub const KP6: c.SDL_Keycode = c.SDLK_KP_6; pub const KP7: c.SDL_Keycode = c.SDLK_KP_7;
                \\    pub const KP8: c.SDL_Keycode = c.SDLK_KP_8; pub const KP9: c.SDL_Keycode = c.SDLK_KP_9;
                \\    pub const KP_DOT:   c.SDL_Keycode = c.SDLK_KP_PERIOD; pub const KP_PLUS:  c.SDL_Keycode = c.SDLK_KP_PLUS;
                \\    pub const KP_MINUS: c.SDL_Keycode = c.SDLK_KP_MINUS;  pub const KP_MUL:   c.SDL_Keycode = c.SDLK_KP_MULTIPLY;
                \\    pub const KP_DIV:   c.SDL_Keycode = c.SDLK_KP_DIVIDE; pub const KP_ENTER: c.SDL_Keycode = c.SDLK_KP_ENTER;
                \\    pub const KP_EQ:    c.SDL_Keycode = c.SDLK_KP_EQUALS;
                \\};
                \\const _XiWin = struct {
                \\    window:      ?*c.SDL_Window = null,
                \\    running:     bool = false,
                \\    close_req:   bool = false,
                \\    min_req:     bool = false,
                \\    max_req:     bool = false,
                \\    key_pressed: c.SDL_Keycode = 0,
                \\    key_char:    u8 = 0,
                \\    target_fps:  u32 = 60,
                \\    frame_start: u32 = 0,
                \\    screen_w:    i32 = 0,
                \\    screen_h:    i32 = 0,
                \\};
                \\fn _xiInitWindow(w: i32, h: i32, title: [*:0]const u8) _XiWin {
                \\    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
                \\    var win = _XiWin{};
                \\    win.window = c.SDL_CreateWindow(title,
                \\        c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED,
                \\        w, h, c.SDL_WINDOW_SHOWN);
                \\    _xi_renderer = c.SDL_CreateRenderer(win.window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC);
                \\    if (_xi_renderer == null)
                \\        _xi_renderer = c.SDL_CreateRenderer(win.window, -1, c.SDL_RENDERER_SOFTWARE);
                \\    _ = c.TTF_Init();
                \\    _ = c.IMG_Init(c.IMG_INIT_PNG | c.IMG_INIT_JPG);
                \\    win.running = true;
                \\    win.screen_w = w;
                \\    win.screen_h = h;
                \\    return win;
                \\}
                \\fn _xiDestroyWindow(win: *_XiWin) void {
                \\    c.TTF_Quit();
                \\    c.IMG_Quit();
                \\    if (_xi_renderer) |r| c.SDL_DestroyRenderer(r);
                \\    c.SDL_DestroyWindow(win.window);
                \\    c.SDL_Quit();
                \\}
                \\fn _xiPollEvents(win: *_XiWin) void {
                \\    win.close_req   = false;
                \\    win.min_req     = false;
                \\    win.max_req     = false;
                \\    win.key_pressed = 0;
                \\    win.key_char    = 0;
                \\    win.frame_start = c.SDL_GetTicks();
                \\    var ev: c.SDL_Event = undefined;
                \\    while (c.SDL_PollEvent(&ev) != 0) {
                \\        switch (ev.type) {
                \\            c.SDL_QUIT => win.close_req = true,
                \\            c.SDL_WINDOWEVENT => switch (ev.window.event) {
                \\                c.SDL_WINDOWEVENT_MINIMIZED => win.min_req = true,
                \\                c.SDL_WINDOWEVENT_MAXIMIZED => win.max_req = true,
                \\                else => {},
                \\            },
                \\            c.SDL_KEYDOWN   => win.key_pressed = ev.key.keysym.sym,
                \\            c.SDL_TEXTINPUT => win.key_char = ev.text.text[0],
                \\            else => {},
                \\        }
                \\    }
                \\}
                \\fn _xiFrameEnd(win: *_XiWin) void {
                \\    if (_xi_renderer) |r| c.SDL_RenderPresent(r);
                \\    if (win.target_fps > 0) {
                \\        const ms = @as(u32, 1000) / win.target_fps;
                \\        const elapsed = c.SDL_GetTicks() - win.frame_start;
                \\        if (elapsed < ms) c.SDL_Delay(ms - elapsed);
                \\    }
                \\}
                \\fn _xiClearBg(color: _XiColor) void {
                \\    const ren = _xi_renderer orelse return;
                \\    _ = c.SDL_SetRenderDrawColor(ren, color.r, color.g, color.b, color.a);
                \\    _ = c.SDL_RenderClear(ren);
                \\}
                \\const _xi_font: [96][8]u8 = .{
                \\    .{0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, // 32 space
                \\    .{0x30,0x78,0x78,0x30,0x30,0x00,0x30,0x00}, // 33 !
                \\    .{0x6C,0x6C,0x6C,0x00,0x00,0x00,0x00,0x00}, // 34 "
                \\    .{0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0x00}, // 35 #
                \\    .{0x30,0x7C,0xC0,0x78,0x0C,0xF8,0x30,0x00}, // 36 $
                \\    .{0x00,0xC6,0xCC,0x18,0x30,0x66,0xC6,0x00}, // 37 %
                \\    .{0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00}, // 38 &
                \\    .{0x60,0x60,0xC0,0x00,0x00,0x00,0x00,0x00}, // 39 '
                \\    .{0x18,0x30,0x60,0x60,0x60,0x30,0x18,0x00}, // 40 (
                \\    .{0x60,0x30,0x18,0x18,0x18,0x30,0x60,0x00}, // 41 )
                \\    .{0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00}, // 42 *
                \\    .{0x00,0x30,0x30,0xFC,0x30,0x30,0x00,0x00}, // 43 +
                \\    .{0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x60}, // 44 ,
                \\    .{0x00,0x00,0x00,0xFC,0x00,0x00,0x00,0x00}, // 45 -
                \\    .{0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x00}, // 46 .
                \\    .{0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00}, // 47 /
                \\    .{0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0x7C,0x00}, // 48 0
                \\    .{0x30,0x70,0x30,0x30,0x30,0x30,0xFC,0x00}, // 49 1
                \\    .{0x78,0xCC,0x0C,0x38,0x60,0xCC,0xFC,0x00}, // 50 2
                \\    .{0x78,0xCC,0x0C,0x38,0x0C,0xCC,0x78,0x00}, // 51 3
                \\    .{0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x1E,0x00}, // 52 4
                \\    .{0xFC,0xC0,0xF8,0x0C,0x0C,0xCC,0x78,0x00}, // 53 5
                \\    .{0x38,0x60,0xC0,0xF8,0xCC,0xCC,0x78,0x00}, // 54 6
                \\    .{0xFC,0xCC,0x0C,0x18,0x30,0x30,0x30,0x00}, // 55 7
                \\    .{0x78,0xCC,0xCC,0x78,0xCC,0xCC,0x78,0x00}, // 56 8
                \\    .{0x78,0xCC,0xCC,0x7C,0x0C,0x18,0x70,0x00}, // 57 9
                \\    .{0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x00}, // 58 :
                \\    .{0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x60}, // 59 ;
                \\    .{0x18,0x30,0x60,0xC0,0x60,0x30,0x18,0x00}, // 60 <
                \\    .{0x00,0x00,0xFC,0x00,0x00,0xFC,0x00,0x00}, // 61 =
                \\    .{0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00}, // 62 >
                \\    .{0x78,0xCC,0x0C,0x18,0x30,0x00,0x30,0x00}, // 63 ?
                \\    .{0x7C,0xC6,0xDE,0xDE,0xDE,0xC0,0x78,0x00}, // 64 @
                \\    .{0x30,0x78,0xCC,0xCC,0xFC,0xCC,0xCC,0x00}, // 65 A
                \\    .{0xFC,0x66,0x66,0x7C,0x66,0x66,0xFC,0x00}, // 66 B
                \\    .{0x3C,0x66,0xC0,0xC0,0xC0,0x66,0x3C,0x00}, // 67 C
                \\    .{0xF8,0x6C,0x66,0x66,0x66,0x6C,0xF8,0x00}, // 68 D
                \\    .{0xFE,0x62,0x68,0x78,0x68,0x62,0xFE,0x00}, // 69 E
                \\    .{0xFE,0x62,0x68,0x78,0x68,0x60,0xF0,0x00}, // 70 F
                \\    .{0x3C,0x66,0xC0,0xC0,0xCE,0x66,0x3A,0x00}, // 71 G
                \\    .{0xCC,0xCC,0xCC,0xFC,0xCC,0xCC,0xCC,0x00}, // 72 H
                \\    .{0x78,0x30,0x30,0x30,0x30,0x30,0x78,0x00}, // 73 I
                \\    .{0x1E,0x0C,0x0C,0x0C,0xCC,0xCC,0x78,0x00}, // 74 J
                \\    .{0xE6,0x66,0x6C,0x78,0x6C,0x66,0xE6,0x00}, // 75 K
                \\    .{0xF0,0x60,0x60,0x60,0x62,0x66,0xFE,0x00}, // 76 L
                \\    .{0xC6,0xEE,0xFE,0xFE,0xD6,0xC6,0xC6,0x00}, // 77 M
                \\    .{0xC6,0xE6,0xF6,0xDE,0xCE,0xC6,0xC6,0x00}, // 78 N
                \\    .{0x38,0x6C,0xC6,0xC6,0xC6,0x6C,0x38,0x00}, // 79 O
                \\    .{0xFC,0x66,0x66,0x7C,0x60,0x60,0xF0,0x00}, // 80 P
                \\    .{0x78,0xCC,0xCC,0xCC,0xDC,0x78,0x1C,0x00}, // 81 Q
                \\    .{0xFC,0x66,0x66,0x7C,0x6C,0x66,0xE6,0x00}, // 82 R
                \\    .{0x78,0xCC,0xE0,0x70,0x1C,0xCC,0x78,0x00}, // 83 S
                \\    .{0xFC,0xB4,0x30,0x30,0x30,0x30,0x78,0x00}, // 84 T
                \\    .{0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xFC,0x00}, // 85 U
                \\    .{0xCC,0xCC,0xCC,0xCC,0xCC,0x78,0x30,0x00}, // 86 V
                \\    .{0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0x00}, // 87 W
                \\    .{0xC6,0xC6,0x6C,0x38,0x38,0x6C,0xC6,0x00}, // 88 X
                \\    .{0xCC,0xCC,0xCC,0x78,0x30,0x30,0x78,0x00}, // 89 Y
                \\    .{0xFE,0xC6,0x8C,0x18,0x32,0x66,0xFE,0x00}, // 90 Z
                \\    .{0x78,0x60,0x60,0x60,0x60,0x60,0x78,0x00}, // 91 [
                \\    .{0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00}, // 92 backslash
                \\    .{0x78,0x18,0x18,0x18,0x18,0x18,0x78,0x00}, // 93 ]
                \\    .{0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00}, // 94 ^
                \\    .{0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF}, // 95 _
                \\    .{0x30,0x30,0x18,0x00,0x00,0x00,0x00,0x00}, // 96 `
                \\    .{0x00,0x00,0x78,0x0C,0x7C,0xCC,0x76,0x00}, // 97 a
                \\    .{0xE0,0x60,0x60,0x7C,0x66,0x66,0xDC,0x00}, // 98 b
                \\    .{0x00,0x00,0x78,0xCC,0xC0,0xCC,0x78,0x00}, // 99 c
                \\    .{0x1C,0x0C,0x0C,0x7C,0xCC,0xCC,0x76,0x00}, // 100 d
                \\    .{0x00,0x00,0x78,0xCC,0xFC,0xC0,0x78,0x00}, // 101 e
                \\    .{0x38,0x6C,0x64,0xF0,0x60,0x60,0xF0,0x00}, // 102 f
                \\    .{0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0xF8}, // 103 g
                \\    .{0xE0,0x60,0x6C,0x76,0x66,0x66,0xE6,0x00}, // 104 h
                \\    .{0x30,0x00,0x70,0x30,0x30,0x30,0x78,0x00}, // 105 i
                \\    .{0x0C,0x00,0x0C,0x0C,0x0C,0xCC,0xCC,0x78}, // 106 j
                \\    .{0xE0,0x60,0x66,0x6C,0x78,0x6C,0xE6,0x00}, // 107 k
                \\    .{0x70,0x30,0x30,0x30,0x30,0x30,0x78,0x00}, // 108 l
                \\    .{0x00,0x00,0xCC,0xFE,0xFE,0xD6,0xC6,0x00}, // 109 m
                \\    .{0x00,0x00,0xF8,0xCC,0xCC,0xCC,0xCC,0x00}, // 110 n
                \\    .{0x00,0x00,0x78,0xCC,0xCC,0xCC,0x78,0x00}, // 111 o
                \\    .{0x00,0x00,0xDC,0x66,0x66,0x7C,0x60,0xF0}, // 112 p
                \\    .{0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0x1E}, // 113 q
                \\    .{0x00,0x00,0xDC,0x76,0x66,0x60,0xF0,0x00}, // 114 r
                \\    .{0x00,0x00,0x7C,0xC0,0x78,0x0C,0xF8,0x00}, // 115 s
                \\    .{0x10,0x30,0x7C,0x30,0x30,0x34,0x18,0x00}, // 116 t
                \\    .{0x00,0x00,0xCC,0xCC,0xCC,0xCC,0x76,0x00}, // 117 u
                \\    .{0x00,0x00,0xCC,0xCC,0xCC,0x78,0x30,0x00}, // 118 v
                \\    .{0x00,0x00,0xC6,0xD6,0xFE,0xFE,0x6C,0x00}, // 119 w
                \\    .{0x00,0x00,0xC6,0x6C,0x38,0x6C,0xC6,0x00}, // 120 x
                \\    .{0x00,0x00,0xCC,0xCC,0xCC,0x7C,0x0C,0xF8}, // 121 y
                \\    .{0x00,0x00,0xFC,0x98,0x30,0x64,0xFC,0x00}, // 122 z
                \\    .{0x1C,0x30,0x30,0xE0,0x30,0x30,0x1C,0x00}, // 123 {
                \\    .{0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00}, // 124 |
                \\    .{0xE0,0x30,0x30,0x1C,0x30,0x30,0xE0,0x00}, // 125 }
                \\    .{0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00}, // 126 ~
                \\    .{0x00,0x10,0x38,0x6C,0xC6,0xFE,0x00,0x00}, // 127 del
                \\};
                \\fn _xiOpenFont(name: []const u8, style: []const u8, size: i32) ?*c.TTF_Font {
                \\    // Primary: use fc-match for reliable fontconfig resolution
                \\    {
                \\        const bold   = std.mem.indexOf(u8, style, "BOLD")   != null;
                \\        const italic = std.mem.indexOf(u8, style, "ITALIC") != null;
                \\        const style_hint: []const u8 =
                \\            if (bold and italic) ":bold:italic"
                \\            else if (bold)        ":bold"
                \\            else if (italic)      ":italic"
                \\            else                  "";
                \\        var cmd_buf: [640]u8 = undefined;
                \\        const cmd = std.fmt.bufPrintZ(&cmd_buf,
                \\            "fc-match --format=%{{file}} \"{s}{s}\" 2>/dev/null",
                \\            .{ name, style_hint }) catch null;
                \\        if (cmd) |z_cmd| {
                \\            if (c.popen(z_cmd, "r")) |fp| {
                \\                defer _ = c.pclose(fp);
                \\                var path_buf: [512]u8 = undefined;
                \\                if (c.fgets(&path_buf, 512, fp) != null) {
                \\                    const raw = std.mem.sliceTo(&path_buf, 0);
                \\                    const trimmed = std.mem.trimRight(u8, raw, "\n\r \t");
                \\                    var z_path: [512]u8 = undefined;
                \\                    const zp = std.fmt.bufPrintZ(&z_path, "{s}", .{trimmed}) catch null;
                \\                    if (zp) |zz| if (c.TTF_OpenFont(zz, size)) |f| return f;
                \\                }
                \\            }
                \\        }
                \\    }
                \\    // Fallback: try as absolute path
                \\    {
                \\        var buf: [512]u8 = undefined;
                \\        const z = std.fmt.bufPrintZ(&buf, "{s}", .{name}) catch return null;
                \\        if (c.TTF_OpenFont(z, size)) |f| return f;
                \\    }
                \\    return null;
                \\}
                \\fn _xiDrawSysText(text: []const u8, x: i32, y: i32, size: i32, color: _XiColor, font_name: []const u8) void {
                \\    const ren = _xi_renderer orelse return;
                \\    const font = _xiOpenFont(font_name, "", size) orelse { _xiDrawText(text, x, y, size, color); return; };
                \\    defer c.TTF_CloseFont(font);
                \\    const sdl_color = c.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
                \\    var z_buf: [4096]u8 = undefined;
                \\    const z_text = std.fmt.bufPrintZ(&z_buf, "{s}", .{text}) catch return;
                \\    const surface = c.TTF_RenderUTF8_Blended(font, z_text, sdl_color) orelse return;
                \\    defer c.SDL_FreeSurface(surface);
                \\    const tex = c.SDL_CreateTextureFromSurface(ren, surface) orelse return;
                \\    defer c.SDL_DestroyTexture(tex);
                \\    var tw: c_int = 0; var th: c_int = 0;
                \\    _ = c.SDL_QueryTexture(tex, null, null, &tw, &th);
                \\    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
                \\    const dst = c.SDL_Rect{ .x = x, .y = y, .w = tw, .h = th };
                \\    _ = c.SDL_RenderCopy(ren, tex, null, &dst);
                \\}
                \\// ── @xi font handle ─────────────────────────────────────────────────────────
                \\const _XiFont = struct { handle: ?*c.TTF_Font = null, fg: _XiColor = _XiColor{ .r=255,.g=255,.b=255,.a=255 }, bg: _XiColor = _XiColor{ .r=0,.g=0,.b=0,.a=0 } };
                \\fn _xiLoadFont(name: []const u8, style: []const u8, fg: _XiColor, bg: _XiColor, size: i32) _XiFont {
                \\    const font = _xiOpenFont(name, style, size) orelse return _XiFont{ .fg = fg, .bg = bg };
                \\    var flags: c_int = c.TTF_STYLE_NORMAL;
                \\    if (std.mem.indexOf(u8, style, "BOLD")          != null) flags |= c.TTF_STYLE_BOLD;
                \\    if (std.mem.indexOf(u8, style, "ITALIC")        != null) flags |= c.TTF_STYLE_ITALIC;
                \\    if (std.mem.indexOf(u8, style, "UNDERLINE")     != null) flags |= c.TTF_STYLE_UNDERLINE;
                \\    if (std.mem.indexOf(u8, style, "STRIKETHROUGH") != null) flags |= c.TTF_STYLE_STRIKETHROUGH;
                \\    c.TTF_SetFontStyle(font, flags);
                \\    return _XiFont{ .handle = font, .fg = fg, .bg = bg };
                \\}
                \\fn _xiDestroyFont(fnt: *_XiFont) void {
                \\    if (fnt.handle) |h| c.TTF_CloseFont(h);
                \\    fnt.handle = null;
                \\}
                \\fn _xiFontWidth(fnt: *const _XiFont, text: []const u8) i32 {
                \\    const h = fnt.handle orelse return 0;
                \\    var buf: [4096]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return 0;
                \\    var w: c_int = 0; var ht: c_int = 0;
                \\    _ = c.TTF_SizeUTF8(h, z, &w, &ht);
                \\    return @intCast(w);
                \\}
                \\fn _xiFontHeight(fnt: *const _XiFont, text: []const u8) i32 {
                \\    const h = fnt.handle orelse return 0;
                \\    var buf: [4096]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return 0;
                \\    var w: c_int = 0; var ht: c_int = 0;
                \\    _ = c.TTF_SizeUTF8(h, z, &w, &ht);
                \\    return @intCast(ht);
                \\}
                \\fn _xiDrawFontText(fnt: *const _XiFont, text: []const u8, x: i32, y: i32) void {
                \\    const ren = _xi_renderer orelse return;
                \\    const handle = fnt.handle orelse { _xiDrawText(text, x, y, 16, fnt.fg); return; };
                \\    const sdl_fg = c.SDL_Color{ .r = fnt.fg.r, .g = fnt.fg.g, .b = fnt.fg.b, .a = fnt.fg.a };
                \\    var buf: [4096]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
                \\    const surface = c.TTF_RenderUTF8_Blended(handle, z, sdl_fg) orelse return;
                \\    defer c.SDL_FreeSurface(surface);
                \\    const tex = c.SDL_CreateTextureFromSurface(ren, surface) orelse return;
                \\    defer c.SDL_DestroyTexture(tex);
                \\    var tw: c_int = 0; var th: c_int = 0;
                \\    _ = c.SDL_QueryTexture(tex, null, null, &tw, &th);
                \\    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
                \\    const dst = c.SDL_Rect{ .x = x, .y = y, .w = tw, .h = th };
                \\    _ = c.SDL_RenderCopy(ren, tex, null, &dst);
                \\}
                \\// ── @xi image handle ─────────────────────────────────────────────────────────
                \\const _XiImg = struct { tex: ?*c.SDL_Texture = null, _w: i32 = 0, _h: i32 = 0, _dw: i32 = 0, _dh: i32 = 0 };
                \\fn _xiSurfaceToTex(ren: *c.SDL_Renderer, surface: *c.SDL_Surface) ?*c.SDL_Texture {
                \\    const conv = c.SDL_ConvertSurfaceFormat(surface, c.SDL_PIXELFORMAT_RGBA8888, 0) orelse surface;
                \\    defer if (conv != surface) c.SDL_FreeSurface(conv);
                \\    return c.SDL_CreateTextureFromSurface(ren, conv);
                \\}
                \\fn _xiLoadImg(path: []const u8) anyerror!_XiImg {
                \\    const ren = _xi_renderer orelse return error.NoRenderer;
                \\    var buf: [512]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return error.PathTooLong;
                \\    const surface = c.IMG_Load(z) orelse return error.LoadFailed;
                \\    defer c.SDL_FreeSurface(surface);
                \\    const tex = _xiSurfaceToTex(ren, surface) orelse return error.TextureFailed;
                \\    var w: c_int = 0; var h: c_int = 0;
                \\    _ = c.SDL_QueryTexture(tex, null, null, &w, &h);
                \\    return _XiImg{ .tex = tex, ._w = @intCast(w), ._h = @intCast(h) };
                \\}
                \\fn _xiDestroyImg(img: *_XiImg) void {
                \\    if (img.tex) |t| c.SDL_DestroyTexture(t);
                \\    img.tex = null;
                \\}
                \\fn _xiReloadImg(img: *_XiImg, path: []const u8) void {
                \\    if (img.tex) |t| c.SDL_DestroyTexture(t);
                \\    img.tex = null; img._w = 0; img._h = 0;
                \\    const ren = _xi_renderer orelse return;
                \\    var buf: [512]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
                \\    const surface = c.IMG_Load(z) orelse return;
                \\    defer c.SDL_FreeSurface(surface);
                \\    const tex = _xiSurfaceToTex(ren, surface) orelse return;
                \\    var w: c_int = 0; var h: c_int = 0;
                \\    _ = c.SDL_QueryTexture(tex, null, null, &w, &h);
                \\    img.tex = tex; img._w = @intCast(w); img._h = @intCast(h);
                \\}
                \\fn _xiDrawImg(img: *const _XiImg, x: i32, y: i32) void {
                \\    const ren = _xi_renderer orelse return;
                \\    const tex = img.tex orelse return;
                \\    const dw = if (img._dw > 0) img._dw else img._w;
                \\    const dh = if (img._dh > 0) img._dh else img._h;
                \\    const dst = c.SDL_Rect{ .x = x, .y = y, .w = dw, .h = dh };
                \\    _ = c.SDL_RenderCopy(ren, tex, null, &dst);
                \\}
                \\// ── @xi gif handle ───────────────────────────────────────────────────────────
                \\const _XiGif = struct {
                \\    texs:         [256]?*c.SDL_Texture = [_]?*c.SDL_Texture{null} ** 256,
                \\    frame_delays: [256]u32             = [_]u32{0} ** 256,
                \\    frame_count:  u32 = 0,
                \\    cur_frame:    u32 = 0,
                \\    loop_en:      bool = true,
                \\    user_delay:   u32 = 0,
                \\    last_ms:      u32 = 0,
                \\    _dw:          i32 = 0,
                \\    _dh:          i32 = 0,
                \\};
                \\fn _xiLoadGif(path: []const u8) _XiGif {
                \\    const ren = _xi_renderer orelse return _XiGif{};
                \\    var buf: [512]u8 = undefined;
                \\    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return _XiGif{};
                \\    const anim = c.IMG_LoadAnimation(z) orelse return _XiGif{};
                \\    defer c.IMG_FreeAnimation(anim);
                \\    var gif = _XiGif{};
                \\    const count: u32 = @min(@as(u32, @intCast(anim.*.count)), 256);
                \\    var i: u32 = 0;
                \\    while (i < count) : (i += 1) {
                \\        const sf = anim.*.frames[i];
                \\        const tex = _xiSurfaceToTex(ren, sf) orelse continue;
                \\        gif.texs[i] = tex;
                \\        gif.frame_delays[i] = if (anim.*.delays != null) @as(u32, @intCast(anim.*.delays[i])) else 100;
                \\        gif.frame_count += 1;
                \\    }
                \\    return gif;
                \\}
                \\fn _xiDestroyGif(gif: *_XiGif) void {
                \\    for (&gif.texs) |*t| { if (t.*) |tex| c.SDL_DestroyTexture(tex); t.* = null; }
                \\    gif.frame_count = 0;
                \\}
                \\fn _xiReloadGif(gif: *_XiGif, path: []const u8) void {
                \\    const dw = gif._dw; const dh = gif._dh;
                \\    const loop_en = gif.loop_en; const user_delay = gif.user_delay;
                \\    _xiDestroyGif(gif);
                \\    const g2 = _xiLoadGif(path);
                \\    gif.texs = g2.texs;
                \\    gif.frame_delays = g2.frame_delays;
                \\    gif.frame_count = g2.frame_count;
                \\    gif.cur_frame = 0;
                \\    gif.last_ms = c.SDL_GetTicks();
                \\    gif._dw = dw; gif._dh = dh;
                \\    gif.loop_en = loop_en; gif.user_delay = user_delay;
                \\}
                \\fn _xiDrawGif(gif: *_XiGif, x: i32, y: i32) void {
                \\    const ren = _xi_renderer orelse return;
                \\    if (gif.frame_count == 0) return;
                \\    const now = c.SDL_GetTicks();
                \\    const delay = if (gif.user_delay > 0) gif.user_delay else gif.frame_delays[gif.cur_frame];
                \\    if (now - gif.last_ms >= delay) {
                \\        gif.cur_frame += 1;
                \\        if (gif.cur_frame >= gif.frame_count) gif.cur_frame = if (gif.loop_en) 0 else gif.frame_count - 1;
                \\        gif.last_ms = now;
                \\    }
                \\    const tex = gif.texs[gif.cur_frame] orelse return;
                \\    var w: c_int = 0; var h: c_int = 0;
                \\    _ = c.SDL_QueryTexture(tex, null, null, &w, &h);
                \\    const dw = if (gif._dw > 0) gif._dw else w;
                \\    const dh = if (gif._dh > 0) gif._dh else h;
                \\    const dst = c.SDL_Rect{ .x = x, .y = y, .w = dw, .h = dh };
                \\    _ = c.SDL_RenderCopy(ren, tex, null, &dst);
                \\}
                \\fn _xiDrawText(text: []const u8, x: i32, y: i32, size: i32, color: _XiColor) void {
                \\    const ren = _xi_renderer orelse return;
                \\    const scale: i32 = @max(1, @divTrunc(size, 8));
                \\    _ = c.SDL_SetRenderDrawColor(ren, color.r, color.g, color.b, color.a);
                \\    var cx: i32 = x;
                \\    for (text) |ch| {
                \\        if (ch >= 32 and ch <= 127) {
                \\            const glyph = _xi_font[ch - 32];
                \\            var row: i32 = 0;
                \\            while (row < 8) : (row += 1) {
                \\                const bits = glyph[@intCast(row)];
                \\                var col: i32 = 0;
                \\                while (col < 8) : (col += 1) {
                \\                    if (bits & (@as(u8, 0x80) >> @intCast(col)) != 0) {
                \\                        const rect = c.SDL_Rect{
                \\                            .x = cx + col * scale,
                \\                            .y = y  + row * scale,
                \\                            .w = scale, .h = scale,
                \\                        };
                \\                        _ = c.SDL_RenderFillRect(ren, &rect);
                \\                    }
                \\                }
                \\            }
                \\        }
                \\        cx += 8 * scale;
                \\    }
                \\}
                \\
            );
        }

        if (self.uses_fflog) {
            try self.writer.writeAll(
                \\const _FfLog = struct {
                \\    path: []const u8,
                \\    file: ?std.fs.File,
                \\    pub fn init(path: []const u8) _FfLog {
                \\        return .{ .path = path, .file = null };
                \\    }
                \\    pub fn open(self: *_FfLog) void {
                \\        self.file = std.fs.cwd().createFile(self.path, .{}) catch @panic("fflog: open failed");
                \\    }
                \\    pub fn close(self: *_FfLog) void {
                \\        if (self.file) |f| f.close();
                \\        self.file = null;
                \\    }
                \\    pub fn wr(self: *_FfLog, level: []const u8, component: []const u8, msg: []const u8) void {
                \\        const f = self.file orelse return;
                \\        const ts = std.time.timestamp();
                \\        f.deprecatedWriter().print("{{\"ts\":{d},\"level\":\"{s}\",\"component\":\"{s}\",\"msg\":\"{s}\"}}\n", .{ ts, level, component, msg }) catch {};
                \\    }
                \\};
                \\
            );
        }

        if (self.uses_sqlite) {
            try self.writer.writeAll(
                \\// ── sqlite3 extern declarations ────────────────────────────────────────
                \\const _sqlite3_c = struct {
                \\    pub extern fn sqlite3_open(filename: [*:0]const u8, ppDb: **anyopaque) c_int;
                \\    pub extern fn sqlite3_close(pDb: *anyopaque) c_int;
                \\    pub extern fn sqlite3_exec(pDb: *anyopaque, sql: [*:0]const u8, cb: ?*anyopaque, data: ?*anyopaque, errmsg: ?*?[*:0]u8) c_int;
                \\    pub extern fn sqlite3_prepare_v2(pDb: *anyopaque, sql: [*:0]const u8, nByte: c_int, ppStmt: **anyopaque, tail: ?*?[*:0]const u8) c_int;
                \\    pub extern fn sqlite3_step(pStmt: *anyopaque) c_int;
                \\    pub extern fn sqlite3_finalize(pStmt: *anyopaque) c_int;
                \\    pub extern fn sqlite3_reset(pStmt: *anyopaque) c_int;
                \\    pub extern fn sqlite3_column_count(pStmt: *anyopaque) c_int;
                \\    pub extern fn sqlite3_column_name(pStmt: *anyopaque, iCol: c_int) ?[*:0]const u8;
                \\    pub extern fn sqlite3_column_text(pStmt: *anyopaque, iCol: c_int) ?[*:0]const u8;
                \\    pub extern fn sqlite3_column_int(pStmt: *anyopaque, iCol: c_int) c_int;
                \\    pub extern fn sqlite3_column_int64(pStmt: *anyopaque, iCol: c_int) i64;
                \\    pub extern fn sqlite3_column_double(pStmt: *anyopaque, iCol: c_int) f64;
                \\    pub extern fn sqlite3_errmsg(pDb: *anyopaque) ?[*:0]const u8;
                \\    pub extern fn sqlite3_bind_text(pStmt: *anyopaque, i: c_int, text: [*:0]const u8, n: c_int, destructor: ?*anyopaque) c_int;
                \\    pub extern fn sqlite3_bind_int(pStmt: *anyopaque, i: c_int, val: c_int) c_int;
                \\    pub extern fn sqlite3_bind_int64(pStmt: *anyopaque, i: c_int, val: i64) c_int;
                \\    pub extern fn sqlite3_bind_double(pStmt: *anyopaque, i: c_int, val: f64) c_int;
                \\    pub extern fn sqlite3_bind_null(pStmt: *anyopaque, i: c_int) c_int;
                \\};
                \\const _SQLITE_ROW: c_int  = 100;
                \\const _SQLITE_DONE: c_int = 101;
                \\// SQLITE_TRANSIENT = (void*)(-1) — tells sqlite3 to copy the string.
                \\const _SQLITE_TRANSIENT: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
                \\const _Sqlite3 = struct {
                \\    db: *anyopaque,
                \\    pub fn open(path: []const u8) _Sqlite3 {
                \\        var raw: *anyopaque = undefined;
                \\        const z = std.heap.page_allocator.dupeZ(u8, path) catch @panic("sqlite3: alloc");
                \\        defer std.heap.page_allocator.free(z);
                \\        if (_sqlite3_c.sqlite3_open(z, &raw) != 0) @panic("sqlite3_open failed");
                \\        return .{ .db = raw };
                \\    }
                \\    pub fn close(self: *_Sqlite3) void {
                \\        _ = _sqlite3_c.sqlite3_close(self.db);
                \\    }
                \\    pub fn exec(self: *_Sqlite3, sql: []const u8) void {
                \\        const z = std.heap.page_allocator.dupeZ(u8, sql) catch @panic("sqlite3: alloc");
                \\        defer std.heap.page_allocator.free(z);
                \\        _ = _sqlite3_c.sqlite3_exec(self.db, z, null, null, null);
                \\    }
                \\    pub fn prepare(self: *_Sqlite3, sql: []const u8) _Sqlite3Stmt {
                \\        const z = std.heap.page_allocator.dupeZ(u8, sql) catch @panic("sqlite3: alloc");
                \\        defer std.heap.page_allocator.free(z);
                \\        var raw: *anyopaque = undefined;
                \\        if (_sqlite3_c.sqlite3_prepare_v2(self.db, z, -1, &raw, null) != 0) @panic("sqlite3_prepare_v2 failed");
                \\        return .{ .stmt = raw };
                \\    }
                \\    pub fn errmsg(self: *_Sqlite3) []const u8 {
                \\        const p = _sqlite3_c.sqlite3_errmsg(self.db) orelse return "";
                \\        return std.mem.sliceTo(p, 0);
                \\    }
                \\};
                \\const _Sqlite3Stmt = struct {
                \\    stmt: *anyopaque,
                \\    pub fn step(self: *_Sqlite3Stmt) bool {
                \\        return _sqlite3_c.sqlite3_step(self.stmt) == _SQLITE_ROW;
                \\    }
                \\    pub fn finalize(self: *_Sqlite3Stmt) void {
                \\        _ = _sqlite3_c.sqlite3_finalize(self.stmt);
                \\    }
                \\    pub fn reset(self: *_Sqlite3Stmt) void {
                \\        _ = _sqlite3_c.sqlite3_reset(self.stmt);
                \\    }
                \\    pub fn col_count(self: *_Sqlite3Stmt) i32 {
                \\        return @intCast(_sqlite3_c.sqlite3_column_count(self.stmt));
                \\    }
                \\    pub fn col_name(self: *_Sqlite3Stmt, col: i32) []const u8 {
                \\        const p = _sqlite3_c.sqlite3_column_name(self.stmt, @intCast(col)) orelse return "";
                \\        return std.mem.sliceTo(p, 0);
                \\    }
                \\    pub fn col_str(self: *_Sqlite3Stmt, col: i32) []const u8 {
                \\        const p = _sqlite3_c.sqlite3_column_text(self.stmt, @intCast(col)) orelse return "";
                \\        return std.mem.sliceTo(p, 0);
                \\    }
                \\    pub fn col_int(self: *_Sqlite3Stmt, col: i32) i32 {
                \\        return @intCast(_sqlite3_c.sqlite3_column_int(self.stmt, @intCast(col)));
                \\    }
                \\    pub fn col_i64(self: *_Sqlite3Stmt, col: i32) i64 {
                \\        return _sqlite3_c.sqlite3_column_int64(self.stmt, @intCast(col));
                \\    }
                \\    pub fn col_f64(self: *_Sqlite3Stmt, col: i32) f64 {
                \\        return _sqlite3_c.sqlite3_column_double(self.stmt, @intCast(col));
                \\    }
                \\    pub fn bind_str(self: *_Sqlite3Stmt, idx: i32, val: []const u8) void {
                \\        const z = std.heap.page_allocator.dupeZ(u8, val) catch @panic("sqlite3: alloc");
                \\        defer std.heap.page_allocator.free(z);
                \\        _ = _sqlite3_c.sqlite3_bind_text(self.stmt, @intCast(idx), z, -1, _SQLITE_TRANSIENT);
                \\    }
                \\    pub fn bind_int(self: *_Sqlite3Stmt, idx: i32, val: i32) void {
                \\        _ = _sqlite3_c.sqlite3_bind_int(self.stmt, @intCast(idx), @intCast(val));
                \\    }
                \\    pub fn bind_i64(self: *_Sqlite3Stmt, idx: i32, val: i64) void {
                \\        _ = _sqlite3_c.sqlite3_bind_int64(self.stmt, @intCast(idx), val);
                \\    }
                \\    pub fn bind_f64(self: *_Sqlite3Stmt, idx: i32, val: f64) void {
                \\        _ = _sqlite3_c.sqlite3_bind_double(self.stmt, @intCast(idx), val);
                \\    }
                \\    pub fn bind_null(self: *_Sqlite3Stmt, idx: i32) void {
                \\        _ = _sqlite3_c.sqlite3_bind_null(self.stmt, @intCast(idx));
                \\    }
                \\};
                \\
            );
        }

        if (self.uses_qt) {
            try self.writer.writeAll(
                \\// ── Qt C wrapper declarations ────────────────────────────────────────────
                \\const _zqt_c = struct {
                \\    pub extern fn zqt_app_create() *anyopaque;
                \\    pub extern fn zqt_app_exec(app: *anyopaque) c_int;
                \\    pub extern fn zqt_app_process_events(app: *anyopaque) void;
                \\    pub extern fn zqt_app_should_quit(app: *anyopaque) c_int;
                \\    pub extern fn zqt_window_create(title: [*:0]const u8, w: c_int, h: c_int) *anyopaque;
                \\    pub extern fn zqt_window_show(win: *anyopaque) void;
                \\    pub extern fn zqt_window_set_layout(win: *anyopaque, layout: *anyopaque) void;
                \\    pub extern fn zqt_window_set_title(win: *anyopaque, title: [*:0]const u8) void;
                \\    pub extern fn zqt_window_resize(win: *anyopaque, w: c_int, h: c_int) void;
                \\    pub extern fn zqt_label_create(text: [*:0]const u8) *anyopaque;
                \\    pub extern fn zqt_label_set_text(lbl: *anyopaque, text: [*:0]const u8) void;
                \\    pub extern fn zqt_label_text(lbl: *anyopaque) [*:0]const u8;
                \\    pub extern fn zqt_button_create(text: [*:0]const u8) *anyopaque;
                \\    pub extern fn zqt_button_set_text(btn: *anyopaque, text: [*:0]const u8) void;
                \\    pub extern fn zqt_button_clicked(btn: *anyopaque) c_int;
                \\    pub extern fn zqt_lineedit_create() *anyopaque;
                \\    pub extern fn zqt_lineedit_text(le: *anyopaque) [*:0]const u8;
                \\    pub extern fn zqt_lineedit_set_text(le: *anyopaque, text: [*:0]const u8) void;
                \\    pub extern fn zqt_lineedit_set_placeholder(le: *anyopaque, text: [*:0]const u8) void;
                \\    pub extern fn zqt_checkbox_create(text: [*:0]const u8) *anyopaque;
                \\    pub extern fn zqt_checkbox_checked(cb: *anyopaque) c_int;
                \\    pub extern fn zqt_checkbox_set_checked(cb: *anyopaque, v: c_int) void;
                \\    pub extern fn zqt_checkbox_changed(cb: *anyopaque) c_int;
                \\    pub extern fn zqt_spinbox_create(min: c_int, max: c_int) *anyopaque;
                \\    pub extern fn zqt_spinbox_value(sb: *anyopaque) c_int;
                \\    pub extern fn zqt_spinbox_set_value(sb: *anyopaque, v: c_int) void;
                \\    pub extern fn zqt_spinbox_changed(sb: *anyopaque) c_int;
                \\    pub extern fn zqt_vbox_create() *anyopaque;
                \\    pub extern fn zqt_hbox_create() *anyopaque;
                \\    pub extern fn zqt_layout_add_widget(layout: *anyopaque, widget: *anyopaque) void;
                \\    pub extern fn zqt_layout_add_layout(outer: *anyopaque, inner: *anyopaque) void;
                \\    pub extern fn zqt_layout_add_stretch(layout: *anyopaque) void;
                \\    pub extern fn zqt_layout_set_spacing(layout: *anyopaque, spacing: c_int) void;
                \\    pub extern fn zqt_layout_set_margin(layout: *anyopaque, margin: c_int) void;
                \\};
                \\fn _zqt_dupeZ(s: []const u8) [*:0]const u8 {
                \\    const z = std.heap.page_allocator.dupeZ(u8, s) catch @panic("qt: alloc");
                \\    return z;
                \\}
                \\const _QtApp = struct {
                \\    app: *anyopaque,
                \\    pub fn run(self: *_QtApp) void { _ = _zqt_c.zqt_app_exec(self.app); }
                \\    pub fn process_events(self: *_QtApp) void { _zqt_c.zqt_app_process_events(self.app); }
                \\    pub fn should_quit(self: *_QtApp) bool { return _zqt_c.zqt_app_should_quit(self.app) != 0; }
                \\};
                \\const _QtWindow = struct {
                \\    win: *anyopaque,
                \\    pub fn show(self: *_QtWindow) void { _zqt_c.zqt_window_show(self.win); }
                \\    pub fn set_layout(self: *_QtWindow, layout: anytype) void { _zqt_c.zqt_window_set_layout(self.win, layout.layout); }
                \\    pub fn set_title(self: *_QtWindow, t: []const u8) void { _zqt_c.zqt_window_set_title(self.win, _zqt_dupeZ(t)); }
                \\    pub fn resize(self: *_QtWindow, w: i32, h: i32) void { _zqt_c.zqt_window_resize(self.win, @intCast(w), @intCast(h)); }
                \\};
                \\const _QtLabel = struct {
                \\    widget: *anyopaque,
                \\    pub fn set_text(self: *_QtLabel, t: []const u8) void { _zqt_c.zqt_label_set_text(self.widget, _zqt_dupeZ(t)); }
                \\    pub fn text(self: *_QtLabel) []const u8 { return std.mem.sliceTo(_zqt_c.zqt_label_text(self.widget), 0); }
                \\};
                \\const _QtButton = struct {
                \\    widget: *anyopaque,
                \\    pub fn clicked(self: *_QtButton) bool { return _zqt_c.zqt_button_clicked(self.widget) != 0; }
                \\    pub fn set_text(self: *_QtButton, t: []const u8) void { _zqt_c.zqt_button_set_text(self.widget, _zqt_dupeZ(t)); }
                \\};
                \\const _QtInput = struct {
                \\    widget: *anyopaque,
                \\    pub fn text(self: *_QtInput) []const u8 { return std.mem.sliceTo(_zqt_c.zqt_lineedit_text(self.widget), 0); }
                \\    pub fn set_text(self: *_QtInput, t: []const u8) void { _zqt_c.zqt_lineedit_set_text(self.widget, _zqt_dupeZ(t)); }
                \\    pub fn set_placeholder(self: *_QtInput, t: []const u8) void { _zqt_c.zqt_lineedit_set_placeholder(self.widget, _zqt_dupeZ(t)); }
                \\};
                \\const _QtCheckbox = struct {
                \\    widget: *anyopaque,
                \\    pub fn checked(self: *_QtCheckbox) bool { return _zqt_c.zqt_checkbox_checked(self.widget) != 0; }
                \\    pub fn set_checked(self: *_QtCheckbox, v: bool) void { _zqt_c.zqt_checkbox_set_checked(self.widget, if (v) @as(c_int, 1) else @as(c_int, 0)); }
                \\    pub fn changed(self: *_QtCheckbox) bool { return _zqt_c.zqt_checkbox_changed(self.widget) != 0; }
                \\};
                \\const _QtSpinbox = struct {
                \\    widget: *anyopaque,
                \\    pub fn value(self: *_QtSpinbox) i32 { return @intCast(_zqt_c.zqt_spinbox_value(self.widget)); }
                \\    pub fn set_value(self: *_QtSpinbox, v: i32) void { _zqt_c.zqt_spinbox_set_value(self.widget, @intCast(v)); }
                \\    pub fn changed(self: *_QtSpinbox) bool { return _zqt_c.zqt_spinbox_changed(self.widget) != 0; }
                \\};
                \\const _QtVBox = struct {
                \\    layout: *anyopaque,
                \\    pub fn add(self: *_QtVBox, item: anytype) void {
                \\        const T = @TypeOf(item);
                \\        if (@hasField(T, "widget")) _zqt_c.zqt_layout_add_widget(self.layout, item.widget)
                \\        else if (@hasField(T, "layout")) _zqt_c.zqt_layout_add_layout(self.layout, item.layout);
                \\    }
                \\    pub fn add_stretch(self: *_QtVBox) void { _zqt_c.zqt_layout_add_stretch(self.layout); }
                \\    pub fn set_spacing(self: *_QtVBox, s: i32) void { _zqt_c.zqt_layout_set_spacing(self.layout, @intCast(s)); }
                \\    pub fn set_margin(self: *_QtVBox, m: i32) void { _zqt_c.zqt_layout_set_margin(self.layout, @intCast(m)); }
                \\};
                \\const _QtHBox = struct {
                \\    layout: *anyopaque,
                \\    pub fn add(self: *_QtHBox, item: anytype) void {
                \\        const T = @TypeOf(item);
                \\        if (@hasField(T, "widget")) _zqt_c.zqt_layout_add_widget(self.layout, item.widget)
                \\        else if (@hasField(T, "layout")) _zqt_c.zqt_layout_add_layout(self.layout, item.layout);
                \\    }
                \\    pub fn add_stretch(self: *_QtHBox) void { _zqt_c.zqt_layout_add_stretch(self.layout); }
                \\    pub fn set_spacing(self: *_QtHBox, s: i32) void { _zqt_c.zqt_layout_set_spacing(self.layout, @intCast(s)); }
                \\    pub fn set_margin(self: *_QtHBox, m: i32) void { _zqt_c.zqt_layout_set_margin(self.layout, @intCast(m)); }
                \\};
                \\
            );
        }

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

        // Emit dat_decls, enum_decls, unn_decls, cls_decls, then fn_decls; collect @main for last
        var main_node: ?*const ast.Node = null;
        for (prog.items) |item| {
            if (item.* == .dat_decl)  try self.emitDatDecl(item.dat_decl);
            if (item.* == .enum_decl) try self.emitEnumDecl(item.enum_decl);
            if (item.* == .unn_decl)  try self.emitUnnDecl(item.unn_decl);
            if (item.* == .cls_decl)  try self.emitClsDecl(item.cls_decl);
            if (item.* == .var_decl)  try self.emitVarDecl(item.var_decl);
        }
        for (prog.items) |item| {
            switch (item.*) {
                .fn_decl    => try self.emitFnDecl(item.fn_decl),
                .test_decl  => try self.emitTestDecl(item.test_decl),
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
        if (self.uses_sodium) {
            try self.writeIndent();
            try self.writer.writeAll("_ = _sodium.sodium_init();\n");
        }
        try self.emitBlockStmts(mb.body);
        self.indent_level -= 1;
        try self.writer.writeAll("}\n");
    }

    // ─── Test declarations ──────────────────────────────────────────────────

    fn emitTestDecl(self: *CodeGen, td: ast.TestDecl) !void {
        try self.writeIndent();
        try self.writer.print("test {s} {{\n", .{td.name.lexeme});
        self.indent_level += 1;
        for (td.body.stmts) |s| try self.emitStmt(s);
        self.indent_level -= 1;
        try self.writeIndent();
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

        // Register xi params in scoped ref registry (save/restore so they
        // don't bleed into other functions or @main).
        const saved_ref_count = self.xi_ref_var_count;
        for (fn_d.params) |p| {
            if (p.type_ann) |ta| {
                const tn = ta.name.lexeme;
                const is_xi = std.mem.eql(u8, tn, "@xi::win") or
                              std.mem.eql(u8, tn, "@xi::img") or
                              std.mem.eql(u8, tn, "@xi::gif") or
                              std.mem.eql(u8, tn, "@xi::fnt");
                if (is_xi and ta.is_ptr) self.recordXiRefVar(p.name.lexeme);
                // By-value xi params: shadow with a local `var` so methods
                // that mutate fields (scale, load, delay, loop) compile correctly.
                // The mutation only affects the local copy — originals unchanged.
                if (is_xi and !ta.is_ptr) {
                    try self.writeIndent();
                    try self.writer.print("var {s} = {s}_xiv_;\n", .{ p.name.lexeme, p.name.lexeme });
                    try self.writeIndent();
                    try self.writer.print("_ = &{s};\n", .{p.name.lexeme});
                }
            }
        }

        try self.emitBlockStmts(fn_d.body);
        self.indent_level -= 1;
        // Restore ref var scope — remove entries added for this function's params.
        self.xi_ref_var_count = saved_ref_count;
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
        // By-value xi params: emit with `_xiv_` suffix to avoid Zig's
        // no-shadowing rule; the body then creates `var name = name_xiv_;`.
        const is_xi_byval = blk: {
            if (param.type_ann) |ta| {
                if (!ta.is_ptr) {
                    const tn = ta.name.lexeme;
                    break :blk std.mem.eql(u8, tn, "@xi::win") or
                               std.mem.eql(u8, tn, "@xi::img") or
                               std.mem.eql(u8, tn, "@xi::gif") or
                               std.mem.eql(u8, tn, "@xi::fnt");
                }
            }
            break :blk false;
        };
        if (is_xi_byval) {
            try self.writer.print("{s}_xiv_", .{param.name.lexeme});
        } else {
            try self.writeZigIdent(param.name.lexeme);
        }
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
            .defer_stmt   => |ds| try self.emitDeferStmt(ds),
            .omp_parallel  => |op| try self.emitOmpParallelStmt(op),
            .omp_for       => |of| try self.emitOmpForStmt(of),
            .xi_draw_block  => |xd| try self.emitXiDrawBlock(xd),
            .xi_event_block => |xe| try self.emitXiEventBlock(xe),
            .expr_stmt     => |es| try self.emitExprStmt(es),
            else           => {},
        }
    }

    fn emitDeferStmt(self: *CodeGen, ds: ast.DeferStmt) !void {
        try self.writeIndent();
        try self.writer.writeAll("defer ");
        try self.emitExpr(ds.expr);
        try self.writer.writeAll(";\n");
    }

    // ─── @xi block emitters ────────────────────────────────────────────────

    /// `win.draw { stmts }` → stmts; _xiFrameEnd(&win);
    fn emitXiDrawBlock(self: *CodeGen, xd: ast.XiDrawBlock) anyerror!void {
        const wn: []const u8 = if (xd.win.* == .ident_expr) xd.win.ident_expr.lexeme else "win";
        try self.emitBlockStmts(xd.body);
        try self.writeIndent();
        if (self.isXiRefVar(wn)) try self.writer.print("_xiFrameEnd({s});\n", .{wn})
        else                     try self.writer.print("_xiFrameEnd(&{s});\n", .{wn});
    }

    /// `win.frame { close=>{}, min=>{}, max=>{} }` — window event arms (SDL2).
    /// `win.keys  { key_press=>{}, key_type=>{} }` — keyboard arms (SDL2).
    /// `win.mouse { … }` — mouse arms (stub).
    fn emitXiEventBlock(self: *CodeGen, xe: ast.XiEventBlock) anyerror!void {
        const wn: []const u8 = if (xe.win.* == .ident_expr) xe.win.ident_expr.lexeme else "win";
        if (std.mem.eql(u8, xe.kind, "frame")) {
            for (xe.arms) |arm| {
                try self.writeIndent();
                if (std.mem.eql(u8, arm.event, "close")) {
                    try self.writer.print("if ({s}.close_req) {{\n", .{wn});
                } else if (std.mem.eql(u8, arm.event, "min")) {
                    try self.writer.print("if ({s}.min_req) {{\n", .{wn});
                } else if (std.mem.eql(u8, arm.event, "max")) {
                    try self.writer.print("if ({s}.max_req) {{\n", .{wn});
                } else {
                    try self.writer.writeAll("{\n");
                }
                self.indent_level += 1;
                const prev_arm = self.xi_current_arm;
                self.xi_current_arm = arm.event;
                try self.emitBlockStmts(arm.body);
                self.xi_current_arm = prev_arm;
                self.indent_level -= 1;
                try self.writeIndent();
                try self.writer.writeAll("}\n");
            }
        } else if (std.mem.eql(u8, xe.kind, "keys")) {
            for (xe.arms) |arm| {
                if (std.mem.eql(u8, arm.event, "key_press")) {
                    try self.writeIndent();
                    try self.writer.print("if ({s}.key_pressed != 0) {{\n", .{wn});
                    self.indent_level += 1;
                    const prev_arm = self.xi_current_arm;
                    const prev_keys = self.xi_keys_var;
                    self.xi_current_arm = arm.event;
                    self.xi_keys_var = wn;
                    try self.emitBlockStmts(arm.body);
                    self.xi_current_arm = prev_arm;
                    self.xi_keys_var = prev_keys;
                    self.indent_level -= 1;
                    try self.writeIndent();
                    try self.writer.writeAll("}\n");
                } else if (std.mem.eql(u8, arm.event, "key_type")) {
                    try self.writeIndent();
                    try self.writer.print("if ({s}.key_char != 0) {{\n", .{wn});
                    self.indent_level += 1;
                    const prev_arm = self.xi_current_arm;
                    const prev_keys = self.xi_keys_var;
                    self.xi_current_arm = arm.event;
                    self.xi_keys_var = wn;
                    try self.emitBlockStmts(arm.body);
                    self.xi_current_arm = prev_arm;
                    self.xi_keys_var = prev_keys;
                    self.indent_level -= 1;
                    try self.writeIndent();
                    try self.writer.writeAll("}\n");
                }
            }
        } else if (std.mem.eql(u8, xe.kind, "mouse")) {
            for (xe.arms) |arm| {
                try self.writeIndent();
                try self.writer.writeAll("{\n");
                self.indent_level += 1;
                try self.emitBlockStmts(arm.body);
                self.indent_level -= 1;
                try self.writeIndent();
                try self.writer.writeAll("}\n");
            }
        }
    }

    /// `@omp::parallel { body }` — spawns `omp_get_max_threads()` Zig threads,
    /// each running `body` with `_omp_thread_id: usize` injected.
    fn emitOmpParallelStmt(self: *CodeGen, op: ast.OmpParallelStmt) anyerror!void {
        try self.writeIndent();
        try self.writer.writeAll("{\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.writeAll("const _omp_n: usize = @intCast(_omp.omp_get_max_threads());\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_handles = std.heap.page_allocator.alloc(std.Thread, _omp_n) catch @panic(\"omp alloc\");\n");
        try self.writeIndent();
        try self.writer.writeAll("defer std.heap.page_allocator.free(_omp_handles);\n");
        try self.writeIndent();
        try self.writer.writeAll("const _OmpBody = struct {\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.writeAll("fn run(_omp_thread_id: usize) void {\n");
        self.indent_level += 1;
        // Save/restore omp_thread_id_var so @omp::thread_id() uses the local param.
        const prev_tid_var = self.omp_thread_id_var;
        self.omp_thread_id_var = "_omp_thread_id";
        for (op.body.stmts) |s| try self.emitStmt(s);
        self.omp_thread_id_var = prev_tid_var;
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("};\n");
        // Spawn threads
        try self.writeIndent();
        try self.writer.writeAll("for (0.._omp_n) |_i| {\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.writeAll("_omp_handles[_i] = std.Thread.spawn(.{}, _OmpBody.run, .{_i}) catch @panic(\"omp spawn\");\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        // Join threads
        try self.writeIndent();
        try self.writer.writeAll("for (_omp_handles) |_h| _h.join();\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
    }

    /// `@omp::for elem => start..end { body }` — parallel range loop split
    /// across `omp_get_max_threads()` threads.
    fn emitOmpForStmt(self: *CodeGen, of: ast.OmpForStmt) anyerror!void {
        const elem = of.elem.lexeme;
        try self.writeIndent();
        try self.writer.writeAll("{\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.writeAll("const _omp_n: usize = @intCast(_omp.omp_get_max_threads());\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_start: isize = @intCast(");
        try self.emitExpr(of.start);
        try self.writer.writeAll(");\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_end: isize = @intCast(");
        try self.emitExpr(of.end);
        if (of.inclusive) try self.writer.writeAll(" + 1");
        try self.writer.writeAll(");\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_total: usize = @intCast(@max(0, _omp_end - _omp_start));\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_chunk: usize = (_omp_total + _omp_n - 1) / _omp_n;\n");
        try self.writeIndent();
        try self.writer.writeAll("const _omp_handles = std.heap.page_allocator.alloc(std.Thread, _omp_n) catch @panic(\"omp alloc\");\n");
        try self.writeIndent();
        try self.writer.writeAll("defer std.heap.page_allocator.free(_omp_handles);\n");
        try self.writeIndent();
        try self.writer.writeAll("const _OmpForCtx = struct { s: isize, e: isize };\n");
        try self.writeIndent();
        try self.writer.writeAll("const _OmpForBody = struct {\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.print("fn run(ctx: _OmpForCtx) void {{\n", .{});
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.print("var {s}: isize = ctx.s;\n", .{elem});
        try self.writeIndent();
        try self.writer.print("while ({s} < ctx.e) : ({s} += 1) {{\n", .{ elem, elem });
        self.indent_level += 1;
        const prev_tid_var = self.omp_thread_id_var;
        self.omp_thread_id_var = null;
        for (of.body.stmts) |s| try self.emitStmt(s);
        self.omp_thread_id_var = prev_tid_var;
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("};\n");
        // Spawn threads with chunk ranges
        try self.writeIndent();
        try self.writer.writeAll("for (0.._omp_n) |_i| {\n");
        self.indent_level += 1;
        try self.writeIndent();
        try self.writer.writeAll("const _s = _omp_start + @as(isize, @intCast(_i * _omp_chunk));\n");
        try self.writeIndent();
        try self.writer.writeAll("const _e = @min(_omp_end, _s + @as(isize, @intCast(_omp_chunk)));\n");
        try self.writeIndent();
        try self.writer.writeAll("_omp_handles[_i] = std.Thread.spawn(.{}, _OmpForBody.run, .{_OmpForCtx{ .s = _s, .e = _e }}) catch @panic(\"omp spawn\");\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
        // Join
        try self.writeIndent();
        try self.writer.writeAll("for (_omp_handles) |_h| _h.join();\n");
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
    }

    fn emitVarDecl(self: *CodeGen, vd: ast.VarDecl) !void {
        // `_ := expr` throwaway — Zig uses bare `_ = expr` with no var/const.
        if (std.mem.eql(u8, vd.name.lexeme, "_")) {
            // If the value is a plain identifier that is actually used elsewhere in the
            // current block (as an expr or in an @pf/{ident} interpolation), Zig will
            // reject `_ = ident` as a "pointless discard".  Skip the emission in that case.
            const skip = if (vd.value.* == .ident_expr)
                identUsedInBlock(vd.value.ident_expr.lexeme, self.current_block)
            else
                false;
            if (!skip) {
                try self.writeIndent();
                try self.writer.writeAll("_ = ");
                try self.emitExpr(vd.value);
                try self.writer.writeAll(";\n");
            }
            return;
        }
        try self.writeIndent();
        const kw: []const u8 = switch (vd.kind) {
            // Auto-downgrade mutable declarations to `const` when the variable
            // is never reassigned inside the same block.  This keeps generated
            // Zig valid even when the user writes `x := value` and never
            // mutates `x` — Zig would reject `var x = value` as an unused var.
            .mut_implicit, .mut_explicit => blk: {
                // @list creates an ArrayList — must be `var` so .append() works.
                if (isListCall(vd.value)) break :blk "var";

                // @fflog::init — must be `var` so open/close/wr can mutate self.
                if (isFflogInitCall(vd.value)) break :blk "var";
                // @sqlite::open — must be `var` so close/exec/prepare can mutate self.
                if (isSqliteOpenCall(vd.value)) break :blk "var";
                // db.prepare() returns _Sqlite3Stmt — must be `var` (step/finalize mutate self).
                if (isSqliteStmtCall(vd.value)) break :blk "var";
                // @xi::window — must be `var` (mutable _XiWin struct).
                if (isXiWindowCall(vd.value)) break :blk "var";
                // @xi::font / @xi::img / @xi::gif — must be `var` (mutable handles).
                if (isXiFontCall(vd.value)) break :blk "var";
                if (isXiGifCall(vd.value)) break :blk "var";
                {
                    const raw_v = if (vd.value.* == .catch_expr) vd.value.catch_expr.subject else vd.value;
                    if (isXiImgCall(raw_v)) break :blk "var";
                }
                // @qt::* constructors — must be `var` so methods can mutate self,
                // but only when methods are actually called on the variable.
                // If the variable is only passed by value (e.g. layout.add(row)),
                // Zig allows `const` since no method takes `*Self` on the value itself.
                if (isQtCall(vd.value) and isMethodReceiverInBlock(vd.name.lexeme, self.current_block)) break :blk "var";
                // Top-level (file-scope) mutable vars: always `var`.
                // isReassignedInBlock only scans the local block, missing
                // function-body mutations of globals.
                if (self.indent_level == 0) break :blk "var";
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
            // [N]T = @emparr() → var name: [N]T = std.mem.zeroes([N]T)
            if (ta.is_array and ta.array_size != null and isEmparrCall(vd.value)) {
                try self.writer.writeAll(": ");
                try self.emitTypeAnn(ta);
                try self.writer.writeAll(" = std.mem.zeroes(");
                try self.emitTypeAnn(ta);
                try self.writer.writeAll(");\n");
                return;
            }
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
        // Expose the declared type to @str::parseNum so it can infer the parse function.
        const prev_var_type = self.pending_var_type;
        self.pending_var_type = if (vd.type_ann) |ta| ta.name.lexeme else null;
        defer self.pending_var_type = prev_var_type;
        // Register xi window variable so method calls can be remapped.
        const is_xi_win  = isXiWindowCall(vd.value);
        const is_xi_font = isXiFontCall(vd.value);
        const is_xi_gif  = isXiGifCall(vd.value);
        // img may be wrapped in catch expr — check inner call
        const raw_val_emit = if (vd.value.* == .catch_expr) vd.value.catch_expr.subject else vd.value;
        const is_xi_img  = isXiImgCall(raw_val_emit);
        if (is_xi_win)  self.recordXiVar(vd.name.lexeme);
        if (is_xi_font) self.recordXiFontVar(vd.name.lexeme);
        if (is_xi_img)  self.recordXiImgVar(vd.name.lexeme);
        if (is_xi_gif)  self.recordXiGifVar(vd.name.lexeme);
        // For @xi::img wrapped in catch: emit _xiLoadImg(path) catch _XiImg{}
        if (is_xi_img and vd.value.* == .catch_expr) {
            try self.writer.writeAll("_xiLoadImg(");
            const img_args = raw_val_emit.call_expr.args;
            if (img_args.len > 0) {
                if (img_args[0].* == .string_lit) {
                    try self.emitExpr(img_args[0]);
                    try self.writer.writeAll("[0..]");
                } else {
                    try self.emitExpr(img_args[0]);
                }
            }
            try self.writer.writeAll(") catch _XiImg{}");
        } else {
            try self.emitExpr(vd.value);
        }
        try self.writer.writeAll(";\n");
        // xi window vars get a defer cleanup.
        if (is_xi_win) {
            try self.writeIndent();
            try self.writer.print("defer _xiDestroyWindow(&{s});\n", .{vd.name.lexeme});
        }
        // font, img, gif defers are managed explicitly by the user via obj.free()
        // Register plain str vars in the cross-scope registry so inner-scope
        // code (e.g. inside for bodies) can detect them via isStrExpr.
        const is_str_type = if (vd.type_ann) |ta|
            std.mem.eql(u8, ta.name.lexeme, "str") and !ta.is_array
        else
            vd.value.* == .string_lit;
        if (is_str_type and self.str_var_count < self.str_var_names.len) {
            self.str_var_names[self.str_var_count] = vd.name.lexeme;
            self.str_var_count += 1;
        }

        // @list allocates an ArrayList — emit a paired defer to deinit it
        // and register the var name so outer-scope checks can find it.
        if (isListCall(vd.value)) {
            self.recordListVar(vd.name.lexeme);
            // Only emit defer inside a function body (indent_level > 0).
            // Top-level list vars are file-scope globals — defer is not valid there.
            if (self.indent_level > 0) {
                try self.writeIndent();
                try self.writer.writeAll("defer ");
                try self.writeZigIdent(vd.name.lexeme);
                try self.writer.writeAll(".deinit(std.heap.page_allocator);\n");
            }
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
        // @fs::ls — register the var so .len / [i] auto-unwrap the optional.
        if (isFsLsCall(vd.value)) self.recordLsVar(vd.name.lexeme);
    }

    /// Walk `value` (unwrapping a `try` unary if present) to detect an
    /// `@fs::FileReader::open`, `@fs::FileWriter::open`, etc. call and register
    /// the given variable name in the file-var tracking table.
    fn tryRegisterFileVar(self: *CodeGen, name: []const u8, value: *const ast.Node) void {
        // Unwrap `try expr` or `expr catch …` → look at the inner call.
        const unwrap_try: *const ast.Node = if (value.* == .unary_expr and
            std.mem.eql(u8, value.unary_expr.op.lexeme, "try"))
            value.unary_expr.operand
        else
            value;
        const inner: *const ast.Node = if (unwrap_try.* == .catch_expr)
            unwrap_try.catch_expr.subject
        else
            unwrap_try;

        if (inner.* != .call_expr) return;
        const ce = inner.call_expr;
        if (ce.callee.* != .ns_builtin_expr) return;
        const nb = ce.callee.ns_builtin_expr;
        if (!std.mem.eql(u8, nb.namespace.lexeme, "@fs")) return;
        if (nb.path.len != 2) return;
        const class  = nb.path[0].lexeme;
        const method = nb.path[1].lexeme;



        if (!std.mem.eql(u8, method, "open")) return;

        if (std.mem.eql(u8, class, "file_reader")) {
            self.recordFileVar(name, .file_reader);
        } else if (std.mem.eql(u8, class, "file_writer")) {
            self.recordFileVar(name, .file_writer);
        } else if (std.mem.eql(u8, class, "byte_reader")) {
            const kind: FileVarKind = if (ce.args.len > 1 and isFsEndianBig(ce.args[1]))
                .byte_reader_big else .byte_reader_little;
            self.recordFileVar(name, kind);
        } else if (std.mem.eql(u8, class, "byte_writer")) {
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

    /// Emit a range bound expression.  Integer literals are emitted verbatim;
    /// other expressions are wrapped in `@intCast(…)` so Zig infers `usize`.
    fn emitRangeBound(self: *CodeGen, bound: *const ast.Node) anyerror!void {
        if (bound.* == .int_lit) {
            try self.emitExpr(bound);
        } else {
            try self.writer.writeAll("@intCast(");
            try self.emitExpr(bound);
            try self.writer.writeByte(')');
        }
    }

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
        } else if (fs.iterable.* == .range_expr) {
            // `for _ => 0..len { }` → `for (0..len) |_| { }`
            // Zig requires `usize` bounds; wrap non-literal ends with @intCast.
            const r = fs.iterable.range_expr;
            try self.emitRangeBound(r.start);
            try self.writer.writeAll(if (r.inclusive) "..=" else "..");
            if (r.end) |end| try self.emitRangeBound(end);
            if (fs.idx != null) try self.writer.writeAll(", 0..");
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
            // @getArgs() / getArgs() → [][]u8, elements are strings
            if (vd.value.* == .call_expr) {
                const ce = vd.value.call_expr;
                const is_get_args = (ce.callee.* == .builtin_expr and
                    std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@getArgs")) or
                    (ce.callee.* == .ident_expr and
                    std.mem.eql(u8, ce.callee.ident_expr.lexeme, "getArgs"));
                if (is_get_args) return "{s}";
            }
            return "{any}";
        }
        return "{any}";
    }

    /// `while cond { body }` / `while cond => do_expr { body }`
    /// → `while (cond) { }` / `while (cond) : (do_expr) { }`
    fn emitWhileStmt(self: *CodeGen, ws: ast.WhileStmt) anyerror!void {
        // xi: detect `while win.loop` to inject _xiPollEvents at top of body.
        var xi_poll_var: ?[]const u8 = null;
        if (ws.cond.* == .field_expr) {
            const wcf = ws.cond.field_expr;
            if (wcf.object.* == .ident_expr and
                self.isXiVar(wcf.object.ident_expr.lexeme) and
                std.mem.eql(u8, wcf.field.lexeme, "loop"))
            {
                xi_poll_var = wcf.object.ident_expr.lexeme;
            }
        }
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
        if (xi_poll_var) |wn| {
            try self.writeIndent();
            if (self.isXiRefVar(wn)) try self.writer.print("_xiPollEvents({s});\n", .{wn})
            else                     try self.writer.print("_xiPollEvents(&{s});\n", .{wn});
        }
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
        // Loop init is always `var` — the update expression mutates it.
        // For comptime-typed values (int/float literals) we emit an explicit
        // type so Zig can create a proper runtime variable.
        if (ls.init.* == .var_decl) {
            const vd = ls.init.var_decl;
            try self.writeIndent();
            try self.writer.writeAll("var ");
            try self.writeZigIdent(vd.name.lexeme);
            if (vd.type_ann) |ta| {
                try self.writer.writeAll(": ");
                try self.emitTypeAnn(ta);
            } else if (vd.value.* == .int_lit) {
                try self.writer.writeAll(": usize");
            } else if (vd.value.* == .float_lit) {
                try self.writer.writeAll(": f64");
            }
            try self.writer.writeAll(" = ");
            try self.emitExpr(vd.value);
            try self.writer.writeAll(";\n");
        } else {
            try self.emitStmt(ls.init);
        }
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
        // Fast form: `subject catch expr` → Zig `subject catch expr`
        // Numeric-cast subjects need the same unwrapping as the full form.
        if (ce.fast_default) |def| {
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
                            try self.writer.writeAll(", 10) catch ");
                            try self.emitExpr(def);
                            return;
                        }
                    }
                    const float_casts = [_][]const u8{ "@f32", "@f64", "@f128" };
                    for (float_casts) |cast| {
                        if (std.mem.eql(u8, bname, cast)) {
                            try self.writer.print("std.fmt.parseFloat({s}, ", .{cast[1..]});
                            try self.emitExpr(cc.args[0]);
                            try self.writer.writeAll(") catch ");
                            try self.emitExpr(def);
                            return;
                        }
                    }
                }
            }
            try self.emitExpr(ce.subject);
            try self.writer.writeAll(" catch ");
            try self.emitExpr(def);
            return;
        }
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
        // `_ = ident` discard: skip when `ident` is already used elsewhere in
        // the current block (Zig 0.15 rejects "pointless discard" in that case).
        if (expr.* == .binary_expr) {
            const be = expr.binary_expr;
            if (std.mem.eql(u8, be.op.lexeme, "=") and
                be.left.* == .ident_expr and
                std.mem.eql(u8, be.left.ident_expr.lexeme, "_") and
                be.right.* == .ident_expr)
            {
                if (identUsedInBlock(be.right.ident_expr.lexeme, self.current_block)) return;
            }
        }
        // @sys::waist(ms) — emit block directly (no trailing ';')
        if (expr.* == .call_expr) {
            const ce = expr.call_expr;
            if (ce.callee.* == .ns_builtin_expr) {
                const nb = ce.callee.ns_builtin_expr;
                if (std.mem.eql(u8, nb.namespace.lexeme, "@sys") and
                    nb.path.len == 1 and
                    std.mem.eql(u8, nb.path[0].lexeme, "waist"))
                {
                    try self.writeIndent();
                    if (self.uses_xi) {
                        try self.writer.writeAll("{ const _wt0 = c.SDL_GetTicks(); while (c.SDL_GetTicks() -% _wt0 < @as(u32, @intCast(");
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("))) { var _wev: c.SDL_Event = undefined; while (c.SDL_PollEvent(&_wev) != 0) {} c.SDL_Delay(1); } }\n");
                    } else {
                        try self.writer.writeAll("{ const _wt0 = std.time.milliTimestamp(); while (std.time.milliTimestamp() - _wt0 < @as(i64, @intCast(");
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("))) {} }\n");
                    }
                    return;
                }
            }
        }
        // @sys::cli("cmd {x}") — run shell command with @pf-style interpolation
        if (expr.* == .call_expr) {
            const ce = expr.call_expr;
            if (ce.callee.* == .ns_builtin_expr) {
                const nb = ce.callee.ns_builtin_expr;
                if (std.mem.eql(u8, nb.namespace.lexeme, "@sys") and
                    nb.path.len == 1 and
                    std.mem.eql(u8, nb.path[0].lexeme, "cli"))
                {
                    try self.emitSysCliStmt(ce.args);
                    return;
                }
            }
        }
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
        // ── @xi win.default — context-sensitive: close arm stops loop, others no-op ──
        if (expr.* == .field_expr) {
            const fe = expr.field_expr;
            if (fe.object.* == .ident_expr and self.isXiVar(fe.object.ident_expr.lexeme) and
                std.mem.eql(u8, fe.field.lexeme, "default"))
            {
                // In close arm: stop the loop. In min/max: OS handles it, no-op.
                if (self.xi_current_arm != null and std.mem.eql(u8, self.xi_current_arm.?, "close")) {
                    const wn = fe.object.ident_expr.lexeme;
                    try self.writeIndent();
                    try self.writer.print("{s}.running = false;\n", .{wn});
                }
                return;
            }
        }
        // ── @xi method calls that emit multi-statement blocks ─────────────
        // These can't use the normal `expr;` pattern because Zig forbids `{...};`.
        if (expr.* == .call_expr) {
            const ce = expr.call_expr;
            if (ce.callee.* == .field_expr) {
                const cfe = ce.callee.field_expr;
                if (cfe.object.* == .ident_expr and self.isXiVar(cfe.object.ident_expr.lexeme)) {
                    const method = cfe.field.lexeme;
                    if (std.mem.eql(u8, method, "fps")) {
                        const wn = cfe.object.ident_expr.lexeme;
                        try self.writeIndent();
                        try self.writer.print("{s}.target_fps = @intCast(", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll(");\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "center")) {
                        const win_name = cfe.object.ident_expr.lexeme;
                        try self.writeIndent();
                        try self.writer.print("{{ _ = c.SDL_SetWindowPosition({s}.window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED); }}\n", .{win_name});
                        return;
                    }
                    if (std.mem.eql(u8, method, "show")) {
                        // SDL_WINDOW_SHOWN at creation — no-op
                        return;
                    }
                    if (std.mem.eql(u8, method, "clearbg")) {
                        try self.writeIndent();
                        try self.writer.writeAll("_xiClearBg(");
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeByte(')');
                        try self.writer.writeAll(";\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "text")) {
                        // New API: win.text(fnt_var, msg, x, y)  — fnt_var is a _XiFont
                        // Old API: win.text(font_name_str, msg, x, y, size, color) — _xiDrawSysText
                        const is_font_var = ce.args.len > 0 and
                            ce.args[0].* == .ident_expr and
                            self.isXiFontVar(ce.args[0].ident_expr.lexeme);
                        if (is_font_var) {
                            const fname = ce.args[0].ident_expr.lexeme;
                            try self.writeIndent();
                            if (self.isXiRefVar(fname)) try self.writer.writeAll("_xiDrawFontText(")
                            else                        try self.writer.writeAll("_xiDrawFontText(&");
                            try self.writer.writeAll(fname);
                            try self.writer.writeAll(", ");
                            if (ce.args.len > 1) {
                                const txt = ce.args[1];
                                if (txt.* == .string_lit) { try self.emitExpr(txt); try self.writer.writeAll("[0..]"); }
                                else try self.emitExpr(txt);
                            }
                            for (ce.args[2..]) |a| { try self.writer.writeAll(", "); try self.emitExpr(a); }
                            try self.writer.writeAll(");\n");
                            return;
                        }
                        // Old string-based API: win.text(font_name_str, msg, x, y, size, color)
                        try self.writeIndent();
                        try self.writer.writeAll("_xiDrawSysText(");
                        // msg = args[1]
                        if (ce.args.len > 1) {
                            const txt = ce.args[1];
                            if (txt.* == .string_lit) {
                                try self.emitExpr(txt);
                                try self.writer.writeAll("[0..]");
                            } else {
                                try self.emitExpr(txt);
                            }
                        }
                        // x, y, size, color = args[2..]
                        for (ce.args[2..]) |a| {
                            try self.writer.writeAll(", ");
                            try self.emitExpr(a);
                        }
                        // font = args[0]
                        try self.writer.writeAll(", ");
                        if (ce.args.len > 0) {
                            const fnt = ce.args[0];
                            if (fnt.* == .string_lit) {
                                try self.emitExpr(fnt);
                                try self.writer.writeAll("[0..]");
                            } else {
                                try self.emitExpr(fnt);
                            }
                        }
                        try self.writer.writeAll(");\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "img")) {
                        if (ce.args.len > 0 and ce.args[0].* == .ident_expr and
                            self.isXiImgVar(ce.args[0].ident_expr.lexeme))
                        {
                            const iname = ce.args[0].ident_expr.lexeme;
                            try self.writeIndent();
                            if (self.isXiRefVar(iname)) try self.writer.writeAll("_xiDrawImg(")
                            else                        try self.writer.writeAll("_xiDrawImg(&");
                            try self.writer.writeAll(iname);
                            try self.writer.writeAll(", ");
                            if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                            try self.writer.writeAll(", ");
                            if (ce.args.len > 2) try self.emitExpr(ce.args[2]);
                            try self.writer.writeAll(");\n");
                            return;
                        }
                        return; // no-op if not a known img var
                    }
                    if (std.mem.eql(u8, method, "gif")) {
                        if (ce.args.len > 0 and ce.args[0].* == .ident_expr and
                            self.isXiGifVar(ce.args[0].ident_expr.lexeme))
                        {
                            const gname = ce.args[0].ident_expr.lexeme;
                            try self.writeIndent();
                            if (self.isXiRefVar(gname)) try self.writer.writeAll("_xiDrawGif(")
                            else                        try self.writer.writeAll("_xiDrawGif(&");
                            try self.writer.writeAll(gname);
                            try self.writer.writeAll(", ");
                            if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                            try self.writer.writeAll(", ");
                            if (ce.args.len > 2) try self.emitExpr(ce.args[2]);
                            try self.writer.writeAll(");\n");
                            return;
                        }
                        return;
                    }
                    // ── New window control statements ────────────────────────
                    const wn = cfe.object.ident_expr.lexeme;
                    if (std.mem.eql(u8, method, "size")) {
                        try self.writeIndent();
                        try self.writer.print("c.SDL_SetWindowSize({s}.window, @intCast(", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("), @intCast(");
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll("));\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "minsize")) {
                        try self.writeIndent();
                        try self.writer.print("c.SDL_SetWindowMinimumSize({s}.window, @intCast(", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("), @intCast(");
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll("));\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "maxsize")) {
                        try self.writeIndent();
                        try self.writer.print("c.SDL_SetWindowMaximumSize({s}.window, @intCast(", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("), @intCast(");
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll("));\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "pos")) {
                        try self.writeIndent();
                        try self.writer.print("c.SDL_SetWindowPosition({s}.window, @intCast(", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("), @intCast(");
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll("));\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "fullscreen")) {
                        try self.writeIndent();
                        try self.writer.print("_ = c.SDL_SetWindowFullscreen({s}.window, c.SDL_WINDOW_FULLSCREEN_DESKTOP);\n", .{wn});
                        return;
                    }
                    if (std.mem.eql(u8, method, "resize")) {
                        try self.writeIndent();
                        try self.writer.print("c.SDL_SetWindowResizable({s}.window, if (", .{wn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll(") c.SDL_TRUE else c.SDL_FALSE);\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "monitor")) {
                        try self.writeIndent();
                        try self.writer.writeAll("{ var _xmr: c.SDL_Rect = undefined; _ = c.SDL_GetDisplayBounds(@intCast(");
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.print("), &_xmr); c.SDL_SetWindowPosition({s}.window, _xmr.x + @divTrunc(_xmr.w - {s}.screen_w, 2), _xmr.y + @divTrunc(_xmr.h - {s}.screen_h, 2)); }}\n", .{wn, wn, wn});
                        return;
                    }
                }
                // ── img.load() / img.scale() as statements ───────────────────
                if (cfe.object.* == .ident_expr and self.isXiImgVar(cfe.object.ident_expr.lexeme)) {
                    const imn = cfe.object.ident_expr.lexeme;
                    const method = cfe.field.lexeme;
                    if (std.mem.eql(u8, method, "load")) {
                        try self.writeIndent();
                        if (self.isXiRefVar(imn)) try self.writer.print("_xiReloadImg({s}, ", .{imn})
                        else                      try self.writer.print("_xiReloadImg(&{s}, ", .{imn});
                        if (ce.args.len > 0) {
                            if (ce.args[0].* == .string_lit) { try self.emitExpr(ce.args[0]); try self.writer.writeAll("[0..]"); }
                            else try self.emitExpr(ce.args[0]);
                        }
                        try self.writer.writeAll(");\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "scale")) {
                        try self.writeIndent();
                        try self.writer.print("{s}._dw = @intCast(", .{imn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("); ");
                        try self.writer.print("{s}._dh = @intCast(", .{imn});
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll(");\n");
                        return;
                    }
                }
                // ── gif.delay() / gif.loop() / gif.load() / gif.scale() as statements ──
                if (cfe.object.* == .ident_expr and self.isXiGifVar(cfe.object.ident_expr.lexeme)) {
                    const gn = cfe.object.ident_expr.lexeme;
                    const method = cfe.field.lexeme;
                    if (std.mem.eql(u8, method, "delay")) {
                        try self.writeIndent();
                        try self.writer.print("{s}.user_delay = @intCast(", .{gn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll(");\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "loop")) {
                        try self.writeIndent();
                        try self.writer.print("{s}.loop_en = ", .{gn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll(";\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "load")) {
                        try self.writeIndent();
                        if (self.isXiRefVar(gn)) try self.writer.print("_xiReloadGif({s}, ", .{gn})
                        else                     try self.writer.print("_xiReloadGif(&{s}, ", .{gn});
                        if (ce.args.len > 0) {
                            if (ce.args[0].* == .string_lit) { try self.emitExpr(ce.args[0]); try self.writer.writeAll("[0..]"); }
                            else try self.emitExpr(ce.args[0]);
                        }
                        try self.writer.writeAll(");\n");
                        return;
                    }
                    if (std.mem.eql(u8, method, "scale")) {
                        try self.writeIndent();
                        try self.writer.print("{s}._dw = @intCast(", .{gn});
                        if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                        try self.writer.writeAll("); ");
                        try self.writer.print("{s}._dh = @intCast(", .{gn});
                        if (ce.args.len > 1) try self.emitExpr(ce.args[1]);
                        try self.writer.writeAll(");\n");
                        return;
                    }
                }
            }
        }
        try self.writeIndent();
        try self.emitExpr(expr);
        try self.writer.writeAll(";\n");
    }

    /// Recursively walk a `@cin >> x >> y` chain (left-recursive) and emit
    /// a uniquely-named stack buffer + `readUntilDelimiterOrEof` for each `>>`.
    /// When the target variable has an explicit numeric type declaration
    /// (e.g. `x : i32 = undef`), the raw string is parsed to that type.
    fn emitCinChain(self: *CodeGen, node: *const ast.Node) anyerror!void {
        if (node.* == .builtin_expr) return; // base: bare @cin — nothing to emit
        const be = node.binary_expr;
        try self.emitCinChain(be.left); // earlier reads first
        try self.writeIndent();
        const n = self.cin_counter;
        self.cin_counter += 1;

        // Look up the target variable's declared type for automatic coercion.
        var numeric_type: ?[]const u8 = null;
        var is_float = false;
        if (be.right.* == .ident_expr) {
            if (findDeclType(be.right.ident_expr.lexeme, self.current_block)) |tt| {
                const int_types = [_][]const u8{
                    "i8", "i16", "i32", "i64", "i128",
                    "u8", "u16", "u32", "u64", "u128", "isize", "usize",
                };
                const flt_types = [_][]const u8{ "f32", "f64", "f128" };
                for (int_types) |t| { if (std.mem.eql(u8, tt, t)) { numeric_type = tt; break; } }
                if (numeric_type == null) {
                    for (flt_types) |t| { if (std.mem.eql(u8, tt, t)) { numeric_type = tt; is_float = true; break; } }
                }
            }
        }

        try self.writer.print("var _cin_buf_{d}: [4096]u8 = undefined;\n", .{n});
        try self.writeIndent();

        if (numeric_type) |nt| {
            // Two-step: read raw string, then parse to numeric type.
            try self.writer.print(
                "const _cin_raw_{d} = (try std.fs.File.stdin().deprecatedReader().readUntilDelimiterOrEof(&_cin_buf_{d}, '\\n')) orelse \"\";\n",
                .{ n, n },
            );
            try self.writeIndent();
            try self.emitExpr(be.right);
            if (is_float) {
                try self.writer.print(
                    " = std.fmt.parseFloat({s}, std.mem.trim(u8, _cin_raw_{d}, &std.ascii.whitespace)) catch 0;\n",
                    .{ nt, n },
                );
            } else {
                try self.writer.print(
                    " = std.fmt.parseInt({s}, std.mem.trim(u8, _cin_raw_{d}, &std.ascii.whitespace), 10) catch 0;\n",
                    .{ nt, n },
                );
            }
        } else {
            // Default: assign the raw []const u8 string slice.
            try self.emitExpr(be.right);
            try self.writer.print(
                " = (try std.fs.File.stdin().deprecatedReader().readUntilDelimiterOrEof(&_cin_buf_{d}, '\\n')) orelse \"\";\n",
                .{n},
            );
        }
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

    /// Write the inner content of a string literal (surrounding `"` already stripped).
    /// `\{` → `{{` (Zig fmt literal brace) when `escape_braces` is true, else `\{` → `{`.
    /// `\}` → `}}` when `escape_braces` is true, else `\}` → `}`.
    /// All other escape sequences are forwarded unchanged.
    fn writeStringContent(self: *CodeGen, s: []const u8, escape_braces: bool) !void {
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '\\' and i + 1 < s.len) {
                const next = s[i + 1];
                if (next == '{') {
                    if (escape_braces) try self.writer.writeAll("{{") else try self.writer.writeByte('{');
                    i += 2;
                    continue;
                }
                if (next == '}') {
                    if (escape_braces) try self.writer.writeAll("}}") else try self.writer.writeByte('}');
                    i += 2;
                    continue;
                }
            }
            try self.writer.writeByte(s[i]);
            i += 1;
        }
    }

    /// Emit a Zcythe string literal lexeme (with surrounding `"`) as a Zig string literal.
    /// When `escape_braces` is true, `\{` / `\}` in the source become `{{` / `}}` in the
    /// output (correct for Zig `std.fmt` format strings).  Otherwise they become `{` / `}`.
    fn emitStringLit(self: *CodeGen, lexeme: []const u8, escape_braces: bool) !void {
        try self.writer.writeByte('"');
        try self.writeStringContent(lexeme[1 .. lexeme.len - 1], escape_braces);
        try self.writer.writeByte('"');
    }

    // Explicit anyerror!void required to break the inference cycle:
    //   emitExpr → emitBinaryExpr → emitExpr
    //   emitExpr → emitFunExpr → emitBlockStmts → … → emitExpr
    fn emitExpr(self: *CodeGen, node: *const ast.Node) anyerror!void {
        switch (node.*) {
            .int_lit      => |t|  try self.writer.writeAll(t.lexeme),
            .float_lit    => |t|  try self.writer.writeAll(t.lexeme),
            .string_lit   => |t|  try self.emitStringLit(t.lexeme, false),
            .char_lit     => |t|  try self.writer.writeAll(t.lexeme),
            .ident_expr   => |t|  try self.writeZigIdent(t.lexeme),
            .enum_lit     => |t| {
                try self.writer.writeByte('.');
                try self.writeZigIdent(t.lexeme);
            },
            .builtin_expr => |t| {
                // `@args` used as a bare expression (no call) — expand to alloc call.
                if (std.mem.eql(u8, t.lexeme, "@args") or
                    std.mem.eql(u8, t.lexeme, "@getArgs"))
                {
                    try self.writer.writeAll("try std.process.argsAlloc(std.heap.page_allocator)");
                } else {
                    try self.writer.writeAll(t.lexeme);
                }
            },
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
            .range_expr      => |r| {
                try self.emitExpr(r.start);
                try self.writer.writeAll(if (r.inclusive) "..=" else "..");
                if (r.end) |end| try self.emitExpr(end);
            },
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
        // Array subscript: encoded as binary_expr with op.kind == .l_bracket.
        if (be.op.kind == .l_bracket) {
            // @fs::ls vars are `?[]_ZcyDirEntry` — unwrap before indexing and
            // cast index to usize in case it's a smaller int type.
            if (be.left.* == .ident_expr and self.isLsVar(be.left.ident_expr.lexeme)) {
                try self.emitExpr(be.left);
                try self.writer.writeAll(".?[@as(usize, @intCast(");
                try self.emitExpr(be.right);
                try self.writer.writeAll("))]");
                return;
            }
            try self.emitExpr(be.left);
            try self.writer.writeByte('[');
            try self.emitExpr(be.right);
            try self.writer.writeByte(']');
            return;
        }
        const op = be.op.lexeme;
        // `x == undef` / `x != undef` — `undef` used as a null sentinel in
        // comparisons; emit `null` rather than `undefined` (Zig can't compare
        // to `undefined` at runtime but can compare optional types to `null`).
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=")) {
            const left_undef  = (be.left.*  == .ident_expr   and std.mem.eql(u8, be.left.ident_expr.lexeme,    "undef")) or
                                (be.left.*  == .builtin_expr and std.mem.eql(u8, be.left.builtin_expr.lexeme,  "@undef"));
            const right_undef = (be.right.* == .ident_expr   and std.mem.eql(u8, be.right.ident_expr.lexeme,   "undef")) or
                                (be.right.* == .builtin_expr and std.mem.eql(u8, be.right.builtin_expr.lexeme, "@undef"));
            if (left_undef or right_undef) {
                try self.emitExpr(if (left_undef) be.right else be.left);
                try self.writer.writeByte(' ');
                try self.writer.writeAll(op);
                try self.writer.writeAll(" null");
                return;
            }
        }
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
        // Add parens around a sub-binary-expression only when its operator binds
        // *looser* than the parent operator — i.e. when omitting parens would
        // change the meaning.  Subscript expressions never need extra parens.
        const parent_prec = binOpPrec(op);
        const left_needs_parens = be.left.* == .binary_expr and
            be.left.binary_expr.op.kind != .l_bracket and
            binOpPrec(be.left.binary_expr.op.lexeme) < parent_prec;
        if (left_needs_parens) {
            try self.writer.writeByte('(');
            try self.emitExpr(be.left);
            try self.writer.writeByte(')');
        } else {
            try self.emitExpr(be.left);
        }
        try self.writer.writeByte(' ');
        try self.writer.writeAll(remapOp(op));
        try self.writer.writeByte(' ');
        const right_needs_parens = be.right.* == .binary_expr and
            be.right.binary_expr.op.kind != .l_bracket and
            binOpPrec(be.right.binary_expr.op.lexeme) < parent_prec;
        if (right_needs_parens) {
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
        // @input / @sec_input always return []const u8
        if (node.* == .call_expr) {
            const ce = node.call_expr;
            if (ce.callee.* == .builtin_expr) {
                const _n = ce.callee.builtin_expr.lexeme;
                if (std.mem.eql(u8, _n, "@input") or std.mem.eql(u8, _n, "@sec_input"))
                    return true;
            }
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
        // Fall back to cross-scope registry (populated as vars are emitted).
        for (self.str_var_names[0..self.str_var_count]) |sn| {
            if (std.mem.eql(u8, sn, name)) return true;
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

        // ── @rl:: in non-call position ────────────────────────────────────────
        // `@rl::Color::ray_white` → `rl.Color.ray_white`
        // `@rl::KeyboardKey::space` → `rl.KeyboardKey.space`
        if (std.mem.eql(u8, ns, "@rl")) {
            try self.writer.writeAll("rl");
            for (nb.path) |seg| {
                try self.writer.writeByte('.');
                try self.writer.writeAll(seg.lexeme);
            }
            return;
        }

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

    /// Handle rl alias convenience constructors (vec2, rect, color, key, etc.).
    /// Returns true if fn_name was a known convenience call and was emitted.
    fn emitRlConvenienceCall(self: *CodeGen, fn_name: []const u8, args: []*ast.Node) !bool {
        // key(Name) → rl.KeyboardKey.<snake>
        if (std.mem.eql(u8, fn_name, "key")) {
            try self.writer.writeAll("rl.KeyboardKey.");
            if (args.len > 0) {
                const kn = if (args[0].* == .ident_expr) args[0].ident_expr.lexeme else "unknown";
                try writeRlSnakeCase(self.writer, kn);
            }
            return true;
        }
        // btn(Name) → rl.MouseButton.<snake>
        if (std.mem.eql(u8, fn_name, "btn")) {
            try self.writer.writeAll("rl.MouseButton.");
            if (args.len > 0) {
                const kn = if (args[0].* == .ident_expr) args[0].ident_expr.lexeme else "unknown";
                try writeRlSnakeCase(self.writer, kn);
            }
            return true;
        }
        // gamepad(Name) → rl.GamepadButton.<snake>
        if (std.mem.eql(u8, fn_name, "gamepad")) {
            try self.writer.writeAll("rl.GamepadButton.");
            if (args.len > 0) {
                const kn = if (args[0].* == .ident_expr) args[0].ident_expr.lexeme else "unknown";
                try writeRlSnakeCase(self.writer, kn);
            }
            return true;
        }
        // vec2(x, y) → rl.Vector2{ .x = x, .y = y }
        if (std.mem.eql(u8, fn_name, "vec2")) {
            try self.writer.writeAll("rl.Vector2{ .x = @as(f32, ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll("), .y = @as(f32, ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll(") }");
            return true;
        }
        // vec3(x, y, z) → rl.Vector3{ .x=x, .y=y, .z=z }
        if (std.mem.eql(u8, fn_name, "vec3")) {
            try self.writer.writeAll("rl.Vector3{ .x = @as(f32, ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll("), .y = @as(f32, ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll("), .z = @as(f32, ");
            if (args.len > 2) try self.emitExpr(args[2]);
            try self.writer.writeAll(") }");
            return true;
        }
        // vec4(x, y, z, w) → rl.Vector4{ .x=x, .y=y, .z=z, .w=w }
        if (std.mem.eql(u8, fn_name, "vec4")) {
            try self.writer.writeAll("rl.Vector4{ .x = @as(f32, ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll("), .y = @as(f32, ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll("), .z = @as(f32, ");
            if (args.len > 2) try self.emitExpr(args[2]);
            try self.writer.writeAll("), .w = @as(f32, ");
            if (args.len > 3) try self.emitExpr(args[3]);
            try self.writer.writeAll(") }");
            return true;
        }
        // rect(x, y, w, h) → rl.Rectangle{ .x=x, .y=y, .width=w, .height=h }
        if (std.mem.eql(u8, fn_name, "rect")) {
            try self.writer.writeAll("rl.Rectangle{ .x = @as(f32, ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll("), .y = @as(f32, ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll("), .width = @as(f32, ");
            if (args.len > 2) try self.emitExpr(args[2]);
            try self.writer.writeAll("), .height = @as(f32, ");
            if (args.len > 3) try self.emitExpr(args[3]);
            try self.writer.writeAll(") }");
            return true;
        }
        // color(r, g, b) / color(r, g, b, a) → rl.Color{...}
        if (std.mem.eql(u8, fn_name, "color")) {
            try self.writer.writeAll("rl.Color{ .r = @as(u8, ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll("), .g = @as(u8, ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll("), .b = @as(u8, ");
            if (args.len > 2) try self.emitExpr(args[2]);
            try self.writer.writeAll("), .a = @as(u8, ");
            if (args.len > 3) try self.emitExpr(args[3]) else try self.writer.writeAll("255");
            try self.writer.writeAll(") }");
            return true;
        }
        // cam2d(offset, target, rot, zoom) → rl.Camera2D{...}
        if (std.mem.eql(u8, fn_name, "cam2d")) {
            try self.writer.writeAll("rl.Camera2D{ .offset = ");
            if (args.len > 0) try self.emitExpr(args[0]);
            try self.writer.writeAll(", .target = ");
            if (args.len > 1) try self.emitExpr(args[1]);
            try self.writer.writeAll(", .rotation = @as(f32, ");
            if (args.len > 2) try self.emitExpr(args[2]) else try self.writer.writeAll("0");
            try self.writer.writeAll("), .zoom = @as(f32, ");
            if (args.len > 3) try self.emitExpr(args[3]) else try self.writer.writeAll("1");
            try self.writer.writeAll(") }");
            return true;
        }
        return false;
    }

    /// Emit an `@ns::path(args)` call expression.
    fn emitNsBuiltinCall(self: *CodeGen, nb: ast.NsBuiltinExpr, args: []*ast.Node) !void {
        const ns = nb.namespace.lexeme;

        // ── @input::type("prompt") — typed input returning an error union ────
        // The caller provides explicit `catch` handling; we emit the bare
        // parse call (no `try`, no `catch 0`) so errors propagate.
        //   @input::i32("Enter: ")  → std.fmt.parseInt(i32, _zcyInput("Enter: "), 10)
        //   @input::f64("Enter: ")  → std.fmt.parseFloat(f64, _zcyInput("Enter: "))
        //   @input::str("Enter: ")  → _zcyInput("Enter: ")
        if ((std.mem.eql(u8, ns, "@input") or std.mem.eql(u8, ns, "@sec_input")) and nb.path.len == 1) {
            const _read_fn = if (std.mem.eql(u8, ns, "@sec_input")) "_zcySecInput" else "_zcyInput";
            const type_name = nb.path[0].lexeme;
            const int_types = [_][]const u8{
                "i8","i16","i32","i64","i128","u8","u16","u32","u64","u128","usize","isize",
            };
            const flt_types = [_][]const u8{ "f32", "f64", "f128" };
            for (int_types) |t| {
                if (std.mem.eql(u8, type_name, t)) {
                    try self.writer.print("std.fmt.parseInt({s}, {s}(", .{t, _read_fn});
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll("), 10)");
                    return;
                }
            }
            for (flt_types) |t| {
                if (std.mem.eql(u8, type_name, t)) {
                    try self.writer.print("std.fmt.parseFloat({s}, {s}(", .{t, _read_fn});
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    try self.writer.writeByte(')');
                    return;
                }
            }
            if (std.mem.eql(u8, type_name, "str")) {
                try self.writer.writeAll(_read_fn);
                try self.writer.writeByte('(');
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @rl:: — Zcythe raylib convenience builtins ───────────────────────
        if (std.mem.eql(u8, ns, "@rl") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;
            if (try self.emitRlConvenienceCall(fn_name, args)) return;
            // Fallback: @rl::anyFunc(args) → rl.anyFunc(args)
            try self.writer.writeAll("rl.");
            try self.writer.writeAll(fn_name);
            try self.writer.writeByte('(');
            for (args, 0..) |a, i| {
                if (i > 0) try self.writer.writeAll(", ");
                try self.emitExpr(a);
            }
            try self.writer.writeByte(')');
            return;
        }

        // ── @str:: — string operations ────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@str") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;
            // @str::cat(a, b) → a = try std.mem.concat(alloc, u8, &.{a, b})
            // Emits as an assignment expression; caller adds `;`
            // If `b` is a string subscript (dict[i] → u8), wrap in &[_]u8{b}
            // so it satisfies []const u8 element type of std.mem.concat.
            if (std.mem.eql(u8, fn_name, "cat") and args.len >= 2) {
                const b = args[1];
                const b_is_char = b.* == .binary_expr and b.binary_expr.op.kind == .l_bracket
                    and self.isStrExpr(b.binary_expr.left);
                try self.emitExpr(args[0]);
                try self.writer.writeAll(" = std.mem.concat(std.heap.page_allocator, u8, &.{");
                try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (b_is_char) try self.writer.writeAll("&[_]u8{");
                try self.emitExpr(b);
                if (b_is_char) try self.writer.writeByte('}');
                try self.writer.writeAll("}) catch @panic(\"out of memory\")");
                return;
            }
        }

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
        if (std.mem.eql(u8, ns, "@sys") and nb.path.len == 1) {
            const _sfn = nb.path[0].lexeme;
            if (std.mem.eql(u8, _sfn, "exit") or std.mem.eql(u8, _sfn, "ex")) {
                try self.writer.writeAll("std.process.exit(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, _sfn, "time_ms")) {
                try self.writer.writeAll("std.time.milliTimestamp()");
                return;
            }
            if (std.mem.eql(u8, _sfn, "time_ns")) {
                try self.writer.writeAll("@as(i64, @intCast(std.time.nanoTimestamp()))");
                return;
            }
            if (std.mem.eql(u8, _sfn, "sleep")) {
                try self.writer.writeAll("std.Thread.sleep(@as(u64, @intCast(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(")) * 1_000_000)");
                return;
            }
        }

        // ── @alo:: — heap allocation ─────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@alo") and nb.path.len == 1) {
            const _seg = nb.path[0].lexeme;
            if (std.mem.eql(u8, _seg, "str")) {
                // @alo::str(s) → try std.heap.page_allocator.dupe(u8, s)
                try self.writer.writeAll("try std.heap.page_allocator.dupe(u8, ");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, _seg, "dat") or
                std.mem.eql(u8, _seg, "struct") or
                std.mem.eql(u8, _seg, "cls"))
            {
                // @alo::dat(T) / @alo::struct(T) / @alo::cls(T)
                // → try std.heap.page_allocator.create(T)
                try self.writer.writeAll("try std.heap.page_allocator.create(");
                if (args.len > 0) try self.emitTypeExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @mem:: — Zig allocator handles ───────────────────────────────────
        if (std.mem.eql(u8, ns, "@mem") and nb.path.len == 1) {
            const _seg = nb.path[0].lexeme;
            if (std.mem.eql(u8, _seg, "page_alo")) {
                try self.writer.writeAll("std.heap.page_allocator");
                return;
            }
            if (std.mem.eql(u8, _seg, "gen_purp_alo")) {
                try self.writer.writeAll("std.heap.GeneralPurposeAllocator(.{})");
                return;
            }
            if (std.mem.eql(u8, _seg, "arena_alo")) {
                try self.writer.writeAll("std.heap.ArenaAllocator");
                return;
            }
            if (std.mem.eql(u8, _seg, "fix_buf_alo")) {
                try self.writer.writeAll("std.heap.FixedBufferAllocator");
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
                if (std.mem.eql(u8, seg, "is_file")) {
                    try self.writer.writeAll("_zcyFsIsFile(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, seg, "is_dir")) {
                    try self.writer.writeAll("_zcyFsIsDir(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, seg, "ls")) {
                    // @fs::ls(path) → ?[]_ZcyDirEntry (null on error)
                    try self.writer.writeAll("_zcyFsLs(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, seg, "mkdir")) {
                    // Create directory (and parents) — silently ignore errors.
                    try self.writer.writeAll("std.fs.cwd().makePath(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll(") catch {}");
                    return;
                }
                if (std.mem.eql(u8, seg, "mkfile")) {
                    // Create a file (truncate if exists) — silently ignore errors.
                    try self.writer.writeAll("(blk: { const _zcyF = std.fs.cwd().createFile(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll(", .{}) catch break :blk; _zcyF.close(); })");
                    return;
                }
                if (std.mem.eql(u8, seg, "del")) {
                    // Recursively delete a file or directory tree.
                    try self.writer.writeAll("std.fs.cwd().deleteTree(");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll(") catch {}");
                    return;
                }
                if (std.mem.eql(u8, seg, "rename")) {
                    // Rename / move within the same filesystem.
                    try self.writer.writeAll("std.fs.rename(std.fs.cwd(), ");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll(", std.fs.cwd(), ");
                    if (args.len > 1) try self.emitExpr(args[1]);
                    try self.writer.writeAll(") catch {}");
                    return;
                }
                if (std.mem.eql(u8, seg, "mov")) {
                    // Move a file or directory (alias for rename on same fs).
                    try self.writer.writeAll("std.fs.rename(std.fs.cwd(), ");
                    if (args.len > 0) try self.emitExpr(args[0]);
                    try self.writer.writeAll(", std.fs.cwd(), ");
                    if (args.len > 1) try self.emitExpr(args[1]);
                    try self.writer.writeAll(") catch {}");
                    return;
                }
            }
            if (nb.path.len == 2) {
                const class  = nb.path[0].lexeme;
                const method = nb.path[1].lexeme;

                if (std.mem.eql(u8, method, "open")) {
                    if (std.mem.eql(u8, class, "file_reader")) {
                        try self.writer.writeAll("std.fs.cwd().openFile(");
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                    if (std.mem.eql(u8, class, "file_writer")) {
                        try self.writer.writeAll("std.fs.cwd().createFile(");
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                    if (std.mem.eql(u8, class, "byte_reader") or
                        std.mem.eql(u8, class, "byte_writer"))
                    {
                        const open_fn = if (std.mem.eql(u8, class, "byte_reader"))
                            "std.fs.cwd().openFile(" else "std.fs.cwd().createFile(";
                        try self.writer.writeAll(open_fn);
                        if (args.len > 0) try self.emitExpr(args[0]);
                        try self.writer.writeAll(", .{})");
                        return;
                    }
                }
            }
        }

        // ── @omp:: — OpenMP runtime bindings ────────────────────────────────
        if (std.mem.eql(u8, ns, "@omp") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;
            if (std.mem.eql(u8, fn_name, "set_threads")) {
                try self.writer.writeAll("_omp.omp_set_num_threads(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, fn_name, "max_threads")) {
                try self.writer.writeAll("_omp.omp_get_max_threads()");
                return;
            }
            if (std.mem.eql(u8, fn_name, "num_threads")) {
                try self.writer.writeAll("_omp.omp_get_num_threads()");
                return;
            }
            if (std.mem.eql(u8, fn_name, "thread_id")) {
                if (self.omp_thread_id_var) |v|
                    try self.writer.writeAll(v)
                else
                    try self.writer.writeAll("_omp.omp_get_thread_num()");
                return;
            }
            if (std.mem.eql(u8, fn_name, "wtime")) {
                try self.writer.writeAll("_omp.omp_get_wtime()");
                return;
            }
            if (std.mem.eql(u8, fn_name, "in_parallel")) {
                try self.writer.writeAll("(_omp.omp_in_parallel() != 0)");
                return;
            }
        }

        // ── @sodium:: — libsodium bindings ──────────────────────────────────
        if (std.mem.eql(u8, ns, "@sodium") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;

            // @sodium::hash(pw) → Argon2id password hash → []const u8
            if (std.mem.eql(u8, fn_name, "hash")) {
                try self.writer.writeAll("(blk: { var _h: [128:0]u8 = std.mem.zeroes([128:0]u8); const _pw = ");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(
                    "; _ = _sodium.crypto_pwhash_str(&_h, _pw.ptr, @as(c_ulonglong, _pw.len)," ++
                    " _sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE, _sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE);" ++
                    " break :blk std.heap.page_allocator.dupe(u8, std.mem.sliceTo(&_h, 0)) catch @as([]const u8, \"\"); })"
                );
                return;
            }

            // @sodium::hash_auth(plain, hash) → bool
            if (std.mem.eql(u8, fn_name, "hash_auth")) {
                try self.writer.writeAll("(blk: { var _hv: [128:0]u8 = std.mem.zeroes([128:0]u8); const _plain = ");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll("; const _hash = ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeAll(
                    "; const _hn = @min(_hash.len, 127); @memcpy(_hv[0.._hn], _hash[0.._hn]);" ++
                    " break :blk (_sodium.crypto_pwhash_str_verify(&_hv, _plain.ptr, @as(c_ulonglong, _plain.len)) == 0); })"
                );
                return;
            }

            // @sodium::enc_file(path, key) — encrypts file in-place
            if (std.mem.eql(u8, fn_name, "enc_file")) {
                try self.writer.writeAll("_sodiumEncFile(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }

            // @sodium::dec_file(path, key) — decrypts file in-place
            if (std.mem.eql(u8, fn_name, "dec_file")) {
                try self.writer.writeAll("_sodiumDecFile(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @kry:: — pure-Zig crypto (PBKDF2-HMAC-SHA512 + AES-256-GCM) ─────
        if (std.mem.eql(u8, ns, "@kry") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;

            // @kry::hash(pw) → _kryHash(pw)  → "hex(salt)$hex(key)"
            if (std.mem.eql(u8, fn_name, "hash")) {
                try self.writer.writeAll("_kryHash(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }

            // @kry::hash_auth(pw, stored) → _kryHashAuth(pw, stored)  → bool
            if (std.mem.eql(u8, fn_name, "hash_auth")) {
                try self.writer.writeAll("_kryHashAuth(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }

            // @kry::enc_file(path, pw) — AES-256-GCM encrypt in-place
            if (std.mem.eql(u8, fn_name, "enc_file")) {
                try self.writer.writeAll("_kryEncFile(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }

            // @kry::dec_file(path, pw) — AES-256-GCM decrypt in-place
            if (std.mem.eql(u8, fn_name, "dec_file")) {
                try self.writer.writeAll("_kryDecFile(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @xi:: — built-in graphics framework (SDL2+OpenGL backend) ───────
        if (std.mem.eql(u8, ns, "@xi") and nb.path.len == 1) {
            const fn_name = nb.path[0].lexeme;

            // @xi::window(w, h, title) — init SDL2 window, return _XiWin struct
            if (std.mem.eql(u8, fn_name, "window")) {
                try self.writer.writeAll("_xiInitWindow(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(", ");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeAll(", ");
                if (args.len > 2) {
                    const title_arg = args[2];
                    if (title_arg.* == .string_lit) {
                        try self.emitExpr(title_arg);
                    } else {
                        try self.writer.writeAll("@as([*:0]const u8, @ptrCast(");
                        try self.emitExpr(title_arg);
                        try self.writer.writeAll(".ptr))");
                    }
                }
                try self.writer.writeByte(')');
                return;
            }

            // @xi::font(name, style, fg, bg, size) — load font handle
            if (std.mem.eql(u8, fn_name, "font")) {
                try self.writer.writeAll("_xiLoadFont(");
                // arg0: font name (string)
                if (args.len > 0) {
                    if (args[0].* == .string_lit) { try self.emitExpr(args[0]); try self.writer.writeAll("[0..]"); }
                    else try self.emitExpr(args[0]);
                }
                try self.writer.writeAll(", ");
                // arg1: style string
                if (args.len > 1) {
                    if (args[1].* == .string_lit) { try self.emitExpr(args[1]); try self.writer.writeAll("[0..]"); }
                    else try self.emitExpr(args[1]);
                }
                try self.writer.writeAll(", ");
                // arg2: fg color
                if (args.len > 2) try self.emitExpr(args[2]) else try self.writer.writeAll("_XiColors.white");
                try self.writer.writeAll(", ");
                // arg3: bg color
                if (args.len > 3) try self.emitExpr(args[3]) else try self.writer.writeAll("_XiColors.clear");
                try self.writer.writeAll(", ");
                // arg4: size
                if (args.len > 4) try self.emitExpr(args[4]) else if (args.len > 2) try self.emitExpr(args[2]);
                try self.writer.writeByte(')');
                return;
            }

            // @xi::img(path) — load image (returns anyerror!_XiImg)
            if (std.mem.eql(u8, fn_name, "img")) {
                try self.writer.writeAll("_xiLoadImg(");
                if (args.len > 0) {
                    if (args[0].* == .string_lit) { try self.emitExpr(args[0]); try self.writer.writeAll("[0..]"); }
                    else try self.emitExpr(args[0]);
                }
                try self.writer.writeByte(')');
                return;
            }

            // @xi::gif(path) — load animated GIF
            if (std.mem.eql(u8, fn_name, "gif")) {
                try self.writer.writeAll("_xiLoadGif(");
                if (args.len > 0) {
                    if (args[0].* == .string_lit) { try self.emitExpr(args[0]); try self.writer.writeAll("[0..]"); }
                    else try self.emitExpr(args[0]);
                }
                try self.writer.writeByte(')');
                return;
            }

            // @xi::monitors() — count of connected displays
            if (std.mem.eql(u8, fn_name, "monitors")) {
                try self.writer.writeAll("@as(i32, @intCast(c.SDL_GetNumVideoDisplays()))");
                return;
            }
            // @xi::monitor_width(n) — width of display n
            if (std.mem.eql(u8, fn_name, "monitor_width")) {
                try self.writer.writeAll("blk: { var _xr: c.SDL_Rect = undefined; _ = c.SDL_GetDisplayBounds(@intCast(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll("), &_xr); break :blk @as(i32, @intCast(_xr.w)); }");
                return;
            }
            // @xi::monitor_height(n) — height of display n
            if (std.mem.eql(u8, fn_name, "monitor_height")) {
                try self.writer.writeAll("blk: { var _xr: c.SDL_Rect = undefined; _ = c.SDL_GetDisplayBounds(@intCast(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll("), &_xr); break :blk @as(i32, @intCast(_xr.h)); }");
                return;
            }
            // @xi::pri_monitor(n) — true if n is the primary display (display 0)
            if (std.mem.eql(u8, fn_name, "pri_monitor")) {
                try self.writer.writeByte('(');
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(" == 0)");
                return;
            }

            // @xi::color(r, g, b, a) — color constructor
            if (std.mem.eql(u8, fn_name, "color")) {
                try self.writer.writeAll("_XiColor{ .r = @as(u8, @intCast(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeAll(")), .g = @as(u8, @intCast(");
                if (args.len > 1) try self.emitExpr(args[1]);
                try self.writer.writeAll(")), .b = @as(u8, @intCast(");
                if (args.len > 2) try self.emitExpr(args[2]);
                try self.writer.writeAll(")), .a = @as(u8, @intCast(");
                if (args.len > 3) try self.emitExpr(args[3]) else try self.writer.writeAll("255");
                try self.writer.writeAll(")) }");
                return;
            }
        }

        // ── @fflog:: ─────────────────────────────────────────────────────────
        if (std.mem.eql(u8, ns, "@fflog") and nb.path.len == 1) {
            if (std.mem.eql(u8, nb.path[0].lexeme, "init")) {
                try self.writer.writeAll("_FfLog.init(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @sqlite:: — SQLite3 bindings ────────────────────────────────────
        if (std.mem.eql(u8, ns, "@sqlite") and nb.path.len == 1) {
            if (std.mem.eql(u8, nb.path[0].lexeme, "open")) {
                try self.writer.writeAll("_Sqlite3.open(");
                if (args.len > 0) try self.emitExpr(args[0]);
                try self.writer.writeByte(')');
                return;
            }
        }

        // ── @qt:: — Qt5/Qt6 widget bindings ──────────────────────────────────────
        if (std.mem.eql(u8, ns, "@qt") and nb.path.len == 1) {
            const method = nb.path[0].lexeme;
            if (std.mem.eql(u8, method, "app")) {
                try self.writer.writeAll("_QtApp{ .app = _zqt_c.zqt_app_create() }");
                return;
            }
            if (std.mem.eql(u8, method, "window")) {
                try self.writer.writeAll("_QtWindow{ .win = _zqt_c.zqt_window_create(");
                if (args.len > 0) { try self.writer.writeAll("_zqt_dupeZ("); try self.emitExpr(args[0]); try self.writer.writeAll(")"); }
                if (args.len > 1) { try self.writer.writeAll(", @intCast("); try self.emitExpr(args[1]); try self.writer.writeAll(")"); }
                if (args.len > 2) { try self.writer.writeAll(", @intCast("); try self.emitExpr(args[2]); try self.writer.writeAll(")"); }
                try self.writer.writeAll(") }");
                return;
            }
            if (std.mem.eql(u8, method, "label")) {
                try self.writer.writeAll("_QtLabel{ .widget = _zqt_c.zqt_label_create(");
                if (args.len > 0) { try self.writer.writeAll("_zqt_dupeZ("); try self.emitExpr(args[0]); try self.writer.writeAll(")"); }
                try self.writer.writeAll(") }");
                return;
            }
            if (std.mem.eql(u8, method, "button")) {
                try self.writer.writeAll("_QtButton{ .widget = _zqt_c.zqt_button_create(");
                if (args.len > 0) { try self.writer.writeAll("_zqt_dupeZ("); try self.emitExpr(args[0]); try self.writer.writeAll(")"); }
                try self.writer.writeAll(") }");
                return;
            }
            if (std.mem.eql(u8, method, "input")) {
                try self.writer.writeAll("_QtInput{ .widget = _zqt_c.zqt_lineedit_create() }");
                return;
            }
            if (std.mem.eql(u8, method, "checkbox")) {
                try self.writer.writeAll("_QtCheckbox{ .widget = _zqt_c.zqt_checkbox_create(");
                if (args.len > 0) { try self.writer.writeAll("_zqt_dupeZ("); try self.emitExpr(args[0]); try self.writer.writeAll(")"); }
                try self.writer.writeAll(") }");
                return;
            }
            if (std.mem.eql(u8, method, "spinbox")) {
                try self.writer.writeAll("_QtSpinbox{ .widget = _zqt_c.zqt_spinbox_create(");
                if (args.len > 0) { try self.writer.writeAll("@intCast("); try self.emitExpr(args[0]); try self.writer.writeAll(")"); }
                if (args.len > 1) { try self.writer.writeAll(", @intCast("); try self.emitExpr(args[1]); try self.writer.writeAll(")"); }
                try self.writer.writeAll(") }");
                return;
            }
            if (std.mem.eql(u8, method, "vbox")) {
                try self.writer.writeAll("_QtVBox{ .layout = _zqt_c.zqt_vbox_create() }");
                return;
            }
            if (std.mem.eql(u8, method, "hbox")) {
                try self.writer.writeAll("_QtHBox{ .layout = _zqt_c.zqt_hbox_create() }");
                return;
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
        // ── @xi method calls: win.fps(n), win.center(), win.clearbg(c), etc. ──
        if (ce.callee.* == .field_expr) {
            const cfe = ce.callee.field_expr;
            if (cfe.object.* == .ident_expr and self.isXiVar(cfe.object.ident_expr.lexeme)) {
                const obj_name = cfe.object.ident_expr.lexeme;
                const method = cfe.field.lexeme;
                if (std.mem.eql(u8, method, "fps")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "center")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "show")) {
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "clearbg")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "text")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "img")) {
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "border")) {
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "gif")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
                if (std.mem.eql(u8, method, "width")) {
                    try self.writer.print("blk: {{ var _xw: c_int = 0; var _xh: c_int = 0; c.SDL_GetWindowSize({s}.window, &_xw, &_xh); break :blk @as(i32, @intCast(_xw)); }}", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "height")) {
                    try self.writer.print("blk: {{ var _xw: c_int = 0; var _xh: c_int = 0; c.SDL_GetWindowSize({s}.window, &_xw, &_xh); break :blk @as(i32, @intCast(_xh)); }}", .{obj_name});
                    return;
                }
                // Statement-only methods — suppress as void in expression context
                if (std.mem.eql(u8, method, "size") or
                    std.mem.eql(u8, method, "minsize") or
                    std.mem.eql(u8, method, "maxsize") or
                    std.mem.eql(u8, method, "pos") or
                    std.mem.eql(u8, method, "fullscreen") or
                    std.mem.eql(u8, method, "resize") or
                    std.mem.eql(u8, method, "monitor"))
                {
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
            }
            // ── @xi font method calls ─────────────────────────────────────────
            if (cfe.object.* == .ident_expr and self.isXiFontVar(cfe.object.ident_expr.lexeme)) {
                const obj_name = cfe.object.ident_expr.lexeme;
                const method = cfe.field.lexeme;
                if (std.mem.eql(u8, method, "free")) {
                    if (self.isXiRefVar(obj_name)) try self.writer.print("_xiDestroyFont({s})", .{obj_name})
                    else                           try self.writer.print("_xiDestroyFont(&{s})", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "width")) {
                    try self.writer.writeAll("_xiFontWidth(&");
                    try self.writer.writeAll(obj_name);
                    try self.writer.writeAll(", ");
                    if (ce.args.len > 0) {
                        if (ce.args[0].* == .string_lit) { try self.emitExpr(ce.args[0]); try self.writer.writeAll("[0..]"); }
                        else try self.emitExpr(ce.args[0]);
                    }
                    try self.writer.writeByte(')');
                    return;
                }
                if (std.mem.eql(u8, method, "height")) {
                    try self.writer.writeAll("_xiFontHeight(&");
                    try self.writer.writeAll(obj_name);
                    try self.writer.writeAll(", ");
                    if (ce.args.len > 0) {
                        if (ce.args[0].* == .string_lit) { try self.emitExpr(ce.args[0]); try self.writer.writeAll("[0..]"); }
                        else try self.emitExpr(ce.args[0]);
                    }
                    try self.writer.writeByte(')');
                    return;
                }
            }
            // ── @xi img method calls ──────────────────────────────────────────
            if (cfe.object.* == .ident_expr and self.isXiImgVar(cfe.object.ident_expr.lexeme)) {
                const obj_name = cfe.object.ident_expr.lexeme;
                const method = cfe.field.lexeme;
                if (std.mem.eql(u8, method, "free")) {
                    if (self.isXiRefVar(obj_name)) try self.writer.print("_xiDestroyImg({s})", .{obj_name})
                    else                           try self.writer.print("_xiDestroyImg(&{s})", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "width")) {
                    try self.writer.print("{s}._w", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "height")) {
                    try self.writer.print("{s}._h", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "load") or std.mem.eql(u8, method, "scale")) {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
            }
            // ── @xi gif method calls ──────────────────────────────────────────
            if (cfe.object.* == .ident_expr and self.isXiGifVar(cfe.object.ident_expr.lexeme)) {
                const obj_name = cfe.object.ident_expr.lexeme;
                const method = cfe.field.lexeme;
                if (std.mem.eql(u8, method, "free")) {
                    if (self.isXiRefVar(obj_name)) try self.writer.print("_xiDestroyGif({s})", .{obj_name})
                    else                           try self.writer.print("_xiDestroyGif(&{s})", .{obj_name});
                    return;
                }
                if (std.mem.eql(u8, method, "delay") or std.mem.eql(u8, method, "loop") or
                    std.mem.eql(u8, method, "load") or std.mem.eql(u8, method, "scale"))
                {
                    // Handled as statement in emitExprStmt
                    try self.writer.writeAll("@as(void, {})");
                    return;
                }
            }
        }

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
            if (std.mem.eql(u8, name, "@getArgs") or std.mem.eql(u8, name, "@args")) {
                // @args / @getArgs() → try std.process.argsAlloc(std.heap.page_allocator)
                try self.writer.writeAll("try std.process.argsAlloc(std.heap.page_allocator)");
                return;
            }
            if (std.mem.eql(u8, name, "@cout")) {
                // @cout used as a function call rather than with <<; not supported.
                try self.writer.writeAll("@compileError(\"use @cout << expr, not @cout()\")");
                return;
            }
            if (std.mem.eql(u8, name, "@sysexit")) {
                // @sysexit(code) — legacy alias, prefer @sys::ex(code)
                try self.writer.writeAll("std.process.exit(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@alo")) {
                // @alo(T, N) → try std.heap.page_allocator.alloc(T, N)
                try self.writer.writeAll("try std.heap.page_allocator.alloc(");
                if (ce.args.len > 0) try self.emitTypeExpr(ce.args[0]);
                if (ce.args.len > 1) { try self.writer.writeAll(", "); try self.emitExpr(ce.args[1]); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@free")) {
                // @free(ptr) → std.heap.page_allocator.free(ptr)
                try self.writer.writeAll("std.heap.page_allocator.free(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@list")) {
                // @list(T) → std.ArrayListUnmanaged(T){} (Zig 0.15: unmanaged, no stored allocator)
                try self.writer.writeAll("std.ArrayListUnmanaged(");
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
            if (std.mem.eql(u8, name, "@sec_input")) {
                // @sec_input("prompt") → _zcySecInput("prompt")
                try self.writer.writeAll("_zcySecInput(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@assert")) {
                try self.writer.writeAll("try std.testing.expect(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@assert_eq")) {
                try self.writer.writeAll("try std.testing.expectEqual(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                if (ce.args.len > 1) { try self.writer.writeAll(", "); try self.emitExpr(ce.args[1]); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@assert_str")) {
                try self.writer.writeAll("try std.testing.expectEqualStrings(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                if (ce.args.len > 1) { try self.writer.writeAll(", "); try self.emitExpr(ce.args[1]); }
                try self.writer.writeByte(')');
                return;
            }
            if (std.mem.eql(u8, name, "@str")) {
                // @str(expr) → convert any value to a heap-allocated string.
                // Emits: (std.fmt.allocPrint(std.heap.page_allocator, "{}", .{expr}) catch "?")
                try self.writer.writeAll("(std.fmt.allocPrint(std.heap.page_allocator, \"{}\", .{");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeAll("}) catch \"?\")");
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
                        if (ce.args.len > 0 and isInputCall(ce.args[0])) {
                            // @i32(@input("...")) → implicit try: propagate parse error
                            try self.writer.print("try std.fmt.parseInt({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeAll(", 10)");
                        } else if (ce.args.len > 0 and self.isStrExpr(ce.args[0])) {
                            try self.writer.print("(std.fmt.parseInt({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeAll(", 10) catch 0)");
                        } else {
                            try self.writer.print("_zcyToInt({s}, ", .{zig_type});
                            if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                            try self.writer.writeByte(')');
                        }
                        return;
                    }
                }
                for (float_casts) |cast| {
                    if (std.mem.eql(u8, name, cast)) {
                        const zig_type = cast[1..];
                        if (ce.args.len > 0 and isInputCall(ce.args[0])) {
                            // @f32(@input("...")) → implicit try: propagate parse error
                            try self.writer.print("try std.fmt.parseFloat({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeByte(')');
                        } else if (ce.args.len > 0 and self.isStrExpr(ce.args[0])) {
                            try self.writer.print("(std.fmt.parseFloat({s}, ", .{zig_type});
                            try self.emitExpr(ce.args[0]);
                            try self.writer.writeAll(") catch 0)");
                        } else {
                            try self.writer.print("_zcyToFloat({s}, ", .{zig_type});
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
                // Only remap .add() → .append() for known @list variables.
                // Qt layouts also use .add() but have their own Zig method.
                const obj_is_list = fe.object.* == .ident_expr and
                    self.isKnownListVar(fe.object.ident_expr.lexeme);
                if (obj_is_list) {
                    try self.emitExpr(fe.object);
                    try self.writer.writeAll(".append(std.heap.page_allocator");
                    for (ce.args) |arg| {
                        try self.writer.writeAll(", ");
                        try self.emitExpr(arg);
                    }
                    try self.writer.writeAll(") catch @panic(\"OOM\")");
                    return;
                }
                // Fall through to generic field-call emit below.
            }
            // list.remove(i) → _ = list.swapRemove(i)  (swapRemove returns the displaced element)
            if (std.mem.eql(u8, fe.field.lexeme, "remove")) {
                try self.writer.writeAll("_ = ");
                try self.emitExpr(fe.object);
                try self.writer.writeAll(".swapRemove(");
                if (ce.args.len > 0) try self.emitExpr(ce.args[0]);
                try self.writer.writeByte(')');
                return;
            }
            // list.clear() → list.clearRetainingCapacity()
            if (std.mem.eql(u8, fe.field.lexeme, "clear")) {
                try self.emitExpr(fe.object);
                try self.writer.writeAll(".clearRetainingCapacity()");
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

        // Regular function call.
        // For rl.* calls: auto-coerce `str` variables to [:0]const u8 via
        // _zcyRlStr(), since raylib functions expect null-terminated C strings.
        // String literals coerce automatically in Zig, so only wrap runtime strs.
        const is_rl_call = ce.callee.* == .field_expr and
            isRlCalleeRoot(ce.callee.field_expr.object);

        // Intercept rl.<convenience>(args) alias calls — same codegen as @rl::<convenience>
        if (is_rl_call and ce.callee.* == .field_expr) {
            const method = ce.callee.field_expr.field.lexeme;
            if (try self.emitRlConvenienceCall(method, ce.args)) return;
        }

        try self.emitExpr(ce.callee);
        try self.writer.writeByte('(');
        for (ce.args, 0..) |arg, i| {
            if (i > 0) try self.writer.writeAll(", ");
            if (is_rl_call and self.isStrExpr(arg) and arg.* != .string_lit) {
                try self.writer.writeAll("_zcyRlStr(");
                try self.emitExpr(arg);
                try self.writer.writeByte(')');
            } else {
                try self.emitExpr(arg);
            }
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
        // Emit format string — replace bare `{}` with a type-appropriate specifier:
        // strings → `{s}`, everything else → `{}` (or `{any}` for unknowns).
        if (args[0].* == .string_lit) {
            const raw = args[0].string_lit.lexeme;
            const inner = raw[1 .. raw.len - 1]; // strip outer quotes
            try self.writer.writeByte('"');
            var ph_idx: usize = 0; // which positional arg (0 = args[1])
            var pos: usize = 0;
            while (pos < inner.len) {
                if (inner[pos] == '{' and pos + 1 < inner.len and inner[pos + 1] == '}') {
                    // bare `{}` — pick specifier based on corresponding arg
                    const arg_node: ?*ast.Node = if (ph_idx + 1 < args.len) args[ph_idx + 1] else null;
                    const is_str_arg = if (arg_node) |a|
                        self.isStrExpr(a) or a.* == .call_expr
                    else false;
                    if (is_str_arg) {
                        try self.writer.writeAll("{s}");
                    } else {
                        try self.writer.writeAll("{}");
                    }
                    ph_idx += 1;
                    pos += 2;
                } else {
                    try self.writer.writeByte(inner[pos]);
                    pos += 1;
                }
            }
            try self.writer.writeByte('"');
        } else {
            try self.emitExpr(args[0]);
        }
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
            // \{ → {{ (literal brace in Zig fmt output)
            if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '{') {
                try self.writer.writeAll("{{");
                i += 2;
                continue;
            }
            if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '}') {
                try self.writer.writeAll("}}");
                i += 2;
                continue;
            }
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

    /// Emit a block that runs a shell command built from a @pf-style format string.
    ///
    /// Single-arg form:  @sys::cli("cmd {x}")   — {ident} placeholders interpolated
    /// Multi-arg form:   @sys::cli("cmd {}", x) — positional {} placeholders
    ///
    /// Emits:
    ///   {
    ///       var _cli_buf: [4096]u8 = undefined;
    ///       const _cli_cmd = std.fmt.bufPrint(&_cli_buf, "<fmt>", .{<args>}) catch "";
    ///       var _cli_argv = [_][]const u8{ "sh", "-c", _cli_cmd };
    ///       var _cli_child = std.process.Child.init(&_cli_argv, std.heap.page_allocator);
    ///       _ = _cli_child.spawnAndWait() catch {};
    ///   }
    fn emitSysCliStmt(self: *CodeGen, args: []*ast.Node) !void {
        try self.writeIndent();
        try self.writer.writeAll("{\n");
        self.indent_level += 1;

        try self.writeIndent();
        try self.writer.writeAll("var _cli_buf: [4096]u8 = undefined;\n");
        try self.writeIndent();
        try self.writer.writeAll("const _cli_cmd = std.fmt.bufPrint(&_cli_buf, ");

        if (args.len == 0) {
            // No args — emit empty command.
            try self.writer.writeAll("\"\", .{}) catch \"\";\n");
        } else if (args.len == 1 and args[0].* == .string_lit and containsInterpolation(args[0].string_lit.lexeme)) {
            // Single-arg interpolated form: "cmd {x}" → transform {x} → {s}/{d}/…
            const raw = args[0].string_lit.lexeme;
            const s = raw[1 .. raw.len - 1]; // strip quotes
            // Pass 1: emit transformed format string.
            try self.writer.writeByte('"');
            var i: usize = 0;
            while (i < s.len) {
                if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '{') {
                    try self.writer.writeAll("{{");
                    i += 2;
                    continue;
                }
                if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '}') {
                    try self.writer.writeAll("}}");
                    i += 2;
                    continue;
                }
                if (s[i] == '{') {
                    const start = i + 1;
                    var j = start;
                    while (j < s.len and s[j] != '}') j += 1;
                    if (j < s.len) {
                        const spec = s[start..j];
                        if (isInterpolationIdent(spec)) {
                            const fmt = interpFmt(spec);
                            try self.writer.writeByte('{');
                            if (fmt.len > 0) {
                                try self.emitZigFmtSpec(fmt, "d");
                            } else {
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
            try self.writer.writeByte('"');
            // Pass 2: emit argument list.
            try self.writer.writeAll(", .{");
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
                            try self.writeDottedIdent(interpIdent(spec));
                            first = false;
                            i = j + 1;
                            continue;
                        }
                    }
                }
                i += 1;
            }
            try self.writer.writeAll("}) catch \"\";\n");
        } else {
            // Multi-arg form: @sys::cli("cmd {}", x) — pass format + args through.
            if (args[0].* == .string_lit) {
                const raw = args[0].string_lit.lexeme;
                const inner = raw[1 .. raw.len - 1];
                try self.writer.writeByte('"');
                var ph_idx: usize = 0;
                var pos: usize = 0;
                while (pos < inner.len) {
                    if (inner[pos] == '{' and pos + 1 < inner.len and inner[pos + 1] == '}') {
                        const arg_node: ?*ast.Node = if (ph_idx + 1 < args.len) args[ph_idx + 1] else null;
                        const is_str_arg = if (arg_node) |a|
                            self.isStrExpr(a) or a.* == .call_expr
                        else false;
                        if (is_str_arg) {
                            try self.writer.writeAll("{s}");
                        } else {
                            try self.writer.writeAll("{}");
                        }
                        ph_idx += 1;
                        pos += 2;
                    } else {
                        try self.writer.writeByte(inner[pos]);
                        pos += 1;
                    }
                }
                try self.writer.writeByte('"');
            } else {
                try self.emitExpr(args[0]);
            }
            try self.writer.writeAll(", .{");
            for (args[1..], 0..) |arg, idx| {
                if (idx > 0) try self.writer.writeAll(", ");
                try self.emitExpr(arg);
            }
            try self.writer.writeAll("}) catch \"\";\n");
        }

        try self.writeIndent();
        try self.writer.writeAll("var _cli_argv = [_][]const u8{ \"sh\", \"-c\", _cli_cmd };\n");
        try self.writeIndent();
        try self.writer.writeAll("var _cli_child = std.process.Child.init(&_cli_argv, std.heap.page_allocator);\n");
        try self.writeIndent();
        try self.writer.writeAll("_ = _cli_child.spawnAndWait() catch {};\n");

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writer.writeAll("}\n");
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
                .call_expr => |ce| blk2: {
                    // sqlite col_str / col_name return []const u8 → "{s}"
                    if (ce.callee.* == .field_expr) {
                        const f = ce.callee.field_expr.field.lexeme;
                        if (std.mem.eql(u8, f, "col_str") or std.mem.eql(u8, f, "col_name") or
                            std.mem.eql(u8, f, "errmsg"))
                            break :blk2 "{s}";
                        // col_int / col_i64 / col_f64 → numeric
                        if (std.mem.eql(u8, f, "col_int") or std.mem.eql(u8, f, "col_i64") or
                            std.mem.eql(u8, f, "col_f64") or std.mem.eql(u8, f, "col_count"))
                            break :blk2 "{d}";
                        // Qt label/button/input .text() → string
                        if (std.mem.eql(u8, f, "text")) break :blk2 "{s}";
                        // Qt spinbox .value() → numeric
                        if (std.mem.eql(u8, f, "value")) break :blk2 "{d}";
                    }
                    break :blk2 "{any}";
                },
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
                // Nesting-aware scan for matching }
                var j = inner_start;
                var depth: usize = 0;
                while (j < s.len) {
                    const c = s[j];
                    if (c == '(' or c == '[' or c == '{') {
                        depth += 1;
                    } else if (c == ')' or c == ']') {
                        if (depth > 0) depth -= 1;
                    } else if (c == '}') {
                        if (depth == 0) break;
                        depth -= 1;
                    }
                    j += 1;
                }
                if (j < s.len) {
                    const spec = s[inner_start..j];
                    const is_simple = isInterpolationIdent(spec);
                    const is_complex = !is_simple and spec.len > 0 and
                        (spec[0] == '@' or std.ascii.isAlphabetic(spec[0]) or spec[0] == '_');
                    if (is_simple or is_complex) {
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
                        if (is_simple) {
                            const _ident = interpIdent(spec);
                            try self.writeDottedIdent(_ident);
                        } else {
                            try self.emitPfRawExpr(spec);
                        }
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

    /// Emit a complex @pf placeholder expression with text-level builtin substitutions.
    /// Used when the placeholder content is not a simple ident/field-path.
    fn emitPfRawExpr(self: *CodeGen, text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) {
            // alias.method() — translate any registered @zcy.* import alias.
            if (std.ascii.isAlphabetic(text[i]) or text[i] == '_') {
                if (self.lookupAliasNs(text[i..])) |match| {
                    // Scan the method name after the dot.
                    const dot_pos = i + match.alias_len; // position of '.'
                    var j = dot_pos + 1;
                    while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_')) j += 1;
                    const method = text[dot_pos + 1 .. j];
                    // Only handle zero-arg calls here: alias.method()
                    if (j + 1 < text.len and text[j] == '(' and text[j + 1] == ')') {
                        try self.emitPfAliasMethod(match.ns, method);
                        i = j + 2; // skip past ')'
                        continue;
                    }
                }
            }
            if (text[i] == '@') {
                if (std.mem.startsWith(u8, text[i..], "@rng(")) {
                    try self.writer.writeAll("_zcyRng(");
                    i += "@rng(".len;
                    continue;
                }
                // @omp::xxx() substitutions for string-literal interpolation.
                if (std.mem.startsWith(u8, text[i..], "@sys::time_ms()")) {
                    try self.writer.writeAll("std.time.milliTimestamp()");
                    i += "@sys::time_ms()".len;
                    continue;
                }
                if (std.mem.startsWith(u8, text[i..], "@sys::time_ns()")) {
                    try self.writer.writeAll("@as(i64, @intCast(std.time.nanoTimestamp()))");
                    i += "@sys::time_ns()".len;
                    continue;
                }
                if (std.mem.startsWith(u8, text[i..], "@omp::max_threads()")) {
                    try self.writer.writeAll("_omp.omp_get_max_threads()");
                    i += "@omp::max_threads()".len;
                    continue;
                }
                if (std.mem.startsWith(u8, text[i..], "@omp::num_threads()")) {
                    try self.writer.writeAll("_omp.omp_get_num_threads()");
                    i += "@omp::num_threads()".len;
                    continue;
                }
                if (std.mem.startsWith(u8, text[i..], "@omp::thread_id()")) {
                    if (self.omp_thread_id_var) |v|
                        try self.writer.writeAll(v)
                    else
                        try self.writer.writeAll("_omp.omp_get_thread_num()");
                    i += "@omp::thread_id()".len;
                    continue;
                }
                if (std.mem.startsWith(u8, text[i..], "@omp::wtime()")) {
                    try self.writer.writeAll("_omp.omp_get_wtime()");
                    i += "@omp::wtime()".len;
                    continue;
                }
            }
            try self.writer.writeByte(text[i]);
            i += 1;
        }
    }

    /// Emit the Zig equivalent of `alias.method()` inside a @pf string interpolation.
    fn emitPfAliasMethod(self: *CodeGen, ns: []const u8, method: []const u8) !void {
        if (std.mem.eql(u8, ns, "@omp")) {
            if (std.mem.eql(u8, method, "max_threads")) {
                try self.writer.writeAll("_omp.omp_get_max_threads()");
            } else if (std.mem.eql(u8, method, "num_threads")) {
                try self.writer.writeAll("_omp.omp_get_num_threads()");
            } else if (std.mem.eql(u8, method, "thread_id")) {
                if (self.omp_thread_id_var) |v|
                    try self.writer.writeAll(v)
                else
                    try self.writer.writeAll("_omp.omp_get_thread_num()");
            } else if (std.mem.eql(u8, method, "wtime")) {
                try self.writer.writeAll("_omp.omp_get_wtime()");
            } else if (std.mem.eql(u8, method, "in_parallel")) {
                try self.writer.writeAll("(_omp.omp_in_parallel() != 0)");
            } else {
                // Unknown omp method — emit _omp.omp_<method>()
                try self.writer.print("_omp.omp_{s}()", .{method});
            }
        }
        // Other namespaces: fall through (unlikely to need @pf interpolation)
    }

    fn emitFieldExpr(self: *CodeGen, fe: ast.FieldExpr) !void {
        // ── @fs::ls vars — auto-unwrap optional with `.?` ────────────────────
        if (fe.object.* == .ident_expr and self.isLsVar(fe.object.ident_expr.lexeme)) {
            try self.emitExpr(fe.object);
            try self.writer.writeAll(".?.");
            try self.writer.writeAll(fe.field.lexeme);
            return;
        }
        // ── @xi field chains ────────────────────────────────────────────────
        // win.color.X → _XiColors.X
        if (fe.object.* == .field_expr) {
            const inner = fe.object.field_expr;
            if (inner.object.* == .ident_expr and self.isXiVar(inner.object.ident_expr.lexeme)) {
                if (std.mem.eql(u8, inner.field.lexeme, "color")) {
                    try self.writer.writeAll("_XiColors.");
                    try self.writer.writeAll(fe.field.lexeme);
                    return;
                }
                if (std.mem.eql(u8, inner.field.lexeme, "keyval")) {
                    try self.writer.writeAll("_XiKeyval.");
                    try self.writer.writeAll(fe.field.lexeme);
                    return;
                }
                if (std.mem.eql(u8, inner.field.lexeme, "key")) {
                    const wn3 = inner.object.ident_expr.lexeme;
                    if (std.mem.eql(u8, fe.field.lexeme, "char")) {
                        try self.writer.print("{s}.key_char", .{wn3});
                    } else if (std.mem.eql(u8, fe.field.lexeme, "code")) {
                        try self.writer.print("{s}.key_pressed", .{wn3});
                    }
                    return;
                }
            }
        }
        // win.loop → win.running (SDL2 _XiWin struct field)
        if (fe.object.* == .ident_expr and
            self.isXiVar(fe.object.ident_expr.lexeme))
        {
            if (std.mem.eql(u8, fe.field.lexeme, "loop")) {
                const wn2 = fe.object.ident_expr.lexeme;
                try self.writer.print("{s}.running", .{wn2});
                return;
            }
            // win.default — handled in emitExprStmt (context-sensitive); no-op in expr context
            if (std.mem.eql(u8, fe.field.lexeme, "default")) return;
        }
        // @os.platform → @import("builtin").os.tag == .platform
        if (fe.object.* == .builtin_expr and
            std.mem.eql(u8, fe.object.builtin_expr.lexeme, "@os"))
        {
            try self.writer.writeAll("@import(\"builtin\").os.tag == .");
            try self.writer.writeAll(fe.field.lexeme);
            return;
        }
        // `arr[i].*` → `arr[i]`: slice-element access — no pointer deref in Zig.
        // Check before emitting the object so we can skip the dot entirely.
        if (fe.field.kind == .star and
            fe.object.* == .binary_expr and
            fe.object.binary_expr.op.kind == .l_bracket)
        {
            try self.emitExpr(fe.object);
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

/// Scan `block` for an explicit VarDecl of `name` and return its type name
/// (e.g. "i32", "f64").  Returns null if not found or no explicit type ann.
fn findDeclType(name: []const u8, block: ast.Block) ?[]const u8 {
    for (block.stmts) |stmt| {
        if (stmt.* != .var_decl) continue;
        const vd = stmt.var_decl;
        if (!std.mem.eql(u8, vd.name.lexeme, name)) continue;
        if (vd.type_ann) |ta| return ta.name.lexeme;
    }
    return null;
}

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
    if (ce.callee.* == .builtin_expr) {
        const lex = ce.callee.builtin_expr.lexeme;
        return std.mem.eql(u8, lex, "@getArgs") or std.mem.eql(u8, lex, "@args");
    }
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
    // Check whether any placeholder needs multi-call emission:
    // field-access identifiers OR complex expressions (subscripts, calls, etc.)
    const s = raw[1 .. raw.len - 1];
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '{') {
            const inner_start = i + 1;
            // Nesting-aware scan for matching }
            var j = inner_start;
            var depth: usize = 0;
            while (j < s.len) {
                const c = s[j];
                if (c == '(' or c == '[' or c == '{') {
                    depth += 1;
                } else if (c == ')' or c == ']') {
                    if (depth > 0) depth -= 1;
                } else if (c == '}') {
                    if (depth == 0) break;
                    depth -= 1;
                }
                j += 1;
            }
            if (j < s.len) {
                const spec = s[inner_start..j];
                if (isInterpolationIdent(spec)) {
                    // Field-access → needs multi-call
                    if (std.mem.indexOfScalar(u8, interpIdent(spec), '.') != null) return true;
                } else if (spec.len > 0 and
                    (spec[0] == '@' or std.ascii.isAlphabetic(spec[0]) or spec[0] == '_')) {
                    // Complex expression → needs multi-call
                    return true;
                }
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
/// Return true when `name` is referenced anywhere in `block`:
/// - as an ident_expr in any expression node, or
/// - as a `{name…` interpolation token inside any string_lit (for @pf).
/// Used to decide whether `_ = name` is a "pointless discard" in Zig.
fn identUsedInBlock(name: []const u8, block: ast.Block) bool {
    for (block.stmts) |stmt| {
        if (identUsedInNode(name, stmt)) return true;
    }
    return false;
}

fn identUsedInNode(name: []const u8, node: *const ast.Node) bool {
    switch (node.*) {
        .ident_expr   => |t|  return std.mem.eql(u8, t.lexeme, name),
        .string_lit   => |t|  return stringContainsInterp(t.lexeme, name),
        // Don't recurse into var_decl.value: the throwaway `_ = name` stmt itself
        // would always count as a "use" otherwise, making the suppression fire
        // unconditionally.  We only look for active expression usages.
        .var_decl     => return false,
        .expr_stmt    => |e|  return identUsedInNode(name, e),
        .ret_stmt     => |rs| return identUsedInNode(name, rs.value),
        .binary_expr  => |be| return identUsedInNode(name, be.left) or identUsedInNode(name, be.right),
        .unary_expr   => |ue| return identUsedInNode(name, ue.operand),
        .call_expr    => |ce| {
            if (identUsedInNode(name, ce.callee)) return true;
            for (ce.args) |a| if (identUsedInNode(name, a)) return true;
            return false;
        },
        .field_expr   => |fe| return identUsedInNode(name, fe.object),
        .array_lit    => |al| {
            for (al.elems) |e| if (identUsedInNode(name, e)) return true;
            return false;
        },
        .if_stmt      => |is| {
            if (identUsedInNode(name, is.cond)) return true;
            if (identUsedInBlock(name, is.then_blk)) return true;
            if (is.else_blk) |eb| if (identUsedInBlock(name, eb)) return true;
            return false;
        },
        .for_stmt     => |fs| {
            if (identUsedInNode(name, fs.iterable)) return true;
            return identUsedInBlock(name, fs.body);
        },
        .while_stmt   => |ws| {
            if (identUsedInNode(name, ws.cond)) return true;
            return identUsedInBlock(name, ws.body);
        },
        else          => return false,
    }
}

/// Check if a string literal's content contains `{name` (Zcythe @pf interpolation syntax).
fn stringContainsInterp(literal: []const u8, name: []const u8) bool {
    // literal includes surrounding quotes; scan for `{name` inside.
    var i: usize = 1; // skip opening quote
    while (i + name.len < literal.len) : (i += 1) {
        if (literal[i] == '{' and std.mem.startsWith(u8, literal[i + 1 ..], name)) return true;
    }
    return false;
}

fn isEmparrCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    return ce.callee.* == .builtin_expr and
        std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@emparr");
}

fn isListCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    return ce.callee.* == .builtin_expr and
        std.mem.eql(u8, ce.callee.builtin_expr.lexeme, "@list");
}

/// Return true when node is a `@fflog::init(...)` call.
/// FfLog vars must be `var` because open/close/wr take `*_FfLog`.
fn isFflogInitCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@fflog") and
        nb.path.len == 1 and
        std.mem.eql(u8, nb.path[0].lexeme, "init");
}

/// Return true when node is a `@fs::ls(...)` call.
fn isFsLsCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@fs") and
        nb.path.len == 1 and
        std.mem.eql(u8, nb.path[0].lexeme, "ls");
}


/// Return true when node is a `@sqlite::open(...)` call.
/// Sqlite3 vars must be `var` because close/exec/prepare take `*_Sqlite3`.
fn isSqliteOpenCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@sqlite") and
        nb.path.len == 1 and
        std.mem.eql(u8, nb.path[0].lexeme, "open");
}

/// Return true when node is a `db.prepare(...)` call (field_expr callee named "prepare").
/// _Sqlite3Stmt vars must be `var` because step/finalize/reset take `*_Sqlite3Stmt`.
fn isSqliteStmtCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .field_expr) return false;
    return std.mem.eql(u8, ce.callee.field_expr.field.lexeme, "prepare");
}

/// Return true when node is any `@qt::*(...)` constructor call.
/// All Qt wrapper vars must be `var` because all methods take `*Self`.
fn isQtCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    return std.mem.eql(u8, ce.callee.ns_builtin_expr.namespace.lexeme, "@qt");
}

/// Return true if `name` is ever used as a method receiver (`name.method(...)`)
/// anywhere in `block`, recursively searching nested while/for/loop/if bodies.
fn isMethodReceiverInBlock(name: []const u8, block: ast.Block) bool {
    for (block.stmts) |stmt| {
        if (nodeHasMethodReceiver(name, stmt)) return true;
    }
    return false;
}

fn nodeHasMethodReceiver(name: []const u8, node: *const ast.Node) bool {
    switch (node.*) {
        .expr_stmt => |e| return nodeHasMethodReceiver(name, e),
        .call_expr => |ce| {
            if (ce.callee.* == .field_expr) {
                const fe = ce.callee.field_expr;
                if (fe.object.* == .ident_expr and
                    std.mem.eql(u8, fe.object.ident_expr.lexeme, name))
                    return true;
            }
            return false;
        },
        .while_stmt => |ws| {
            if (nodeHasMethodReceiver(name, ws.cond)) return true;
            return isMethodReceiverInBlock(name, ws.body);
        },
        .for_stmt   => |fs| return isMethodReceiverInBlock(name, fs.body),
        .loop_stmt  => |ls| return isMethodReceiverInBlock(name, ls.body),
        .if_stmt    => |is| {
            if (nodeHasMethodReceiver(name, is.cond)) return true;
            if (isMethodReceiverInBlock(name, is.then_blk)) return true;
            if (is.else_blk) |eb| return isMethodReceiverInBlock(name, eb);
            return false;
        },
        else => return false,
    }
}

/// Return true when `node` is a bare `@input` or `@sec_input` call expression.
/// Used to detect `@i32(@input(...))` / `@i32(@sec_input(...))` and emit an implicit `try` parse.
fn isInputCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .builtin_expr) return false;
    const n = ce.callee.builtin_expr.lexeme;
    return std.mem.eql(u8, n, "@input") or std.mem.eql(u8, n, "@sec_input");
}

/// Return true if `name` ever appears as the left-hand side of an assignment
/// (`=`, `+=`, `-=`, `*=`, `/=`) anywhere in `block`, including inside nested
/// while/for/loop/if bodies (but not inside nested fn_decl scopes).
fn isReassignedInBlock(name: []const u8, block: ast.Block) bool {
    for (block.stmts) |stmt| {
        switch (stmt.*) {
            .expr_stmt => |expr| {
                // @str::cat(name, ...) counts as mutation of its first argument
                if (expr.* == .call_expr) {
                    const ce = expr.call_expr;
                    if (ce.callee.* == .ns_builtin_expr) {
                        const nb = ce.callee.ns_builtin_expr;
                        if (std.mem.eql(u8, nb.namespace.lexeme, "@str") and
                            nb.path.len == 1 and
                            std.mem.eql(u8, nb.path[0].lexeme, "cat") and
                            ce.args.len >= 1 and
                            ce.args[0].* == .ident_expr and
                            std.mem.eql(u8, ce.args[0].ident_expr.lexeme, name)) return true;
                    }
                }
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
                // Direct: `name = …`
                if (be.left.* == .ident_expr and
                    std.mem.eql(u8, be.left.ident_expr.lexeme, name)) return true;
                // Field mutation: `name.x = …` / `name.x.y = …`
                if (exprRootIdent(be.left)) |root| {
                    if (std.mem.eql(u8, root, name)) return true;
                }
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

/// Return true when the program has an explicit `@import(rl = @zcy.raylib)`.
/// If so, `emitImportDecl` will already emit `const rl = @import("raylib");`
/// and the auto-import in the preamble must be suppressed to avoid duplicates.
fn programHasRlImport(prog: ast.Program) bool {
    for (prog.items) |item| {
        if (item.* != .expr_stmt) continue;
        const e = item.expr_stmt;
        if (e.* != .call_expr) continue;
        if (e.call_expr.callee.* != .builtin_expr) continue;
        if (!std.mem.eql(u8, e.call_expr.callee.builtin_expr.lexeme, "@import")) continue;
        for (e.call_expr.args) |arg| {
            if (arg.* != .binary_expr) continue;
            const be = arg.binary_expr;
            if (!std.mem.eql(u8, be.op.lexeme, "=")) continue;
            // rhs must be a field_expr: @zcy.raylib
            if (be.right.* != .field_expr) continue;
            const fe = be.right.field_expr;
            if (fe.object.* != .builtin_expr) continue;
            if (!std.mem.eql(u8, fe.object.builtin_expr.lexeme, "@zcy")) continue;
            if (std.mem.eql(u8, fe.field.lexeme, "raylib")) return true;
        }
    }
    return false;
}

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

/// Return true when the program uses `@omp::` or `@zcy.openmp` anywhere.
/// Used to emit `const _omp = @cImport(@cInclude("omp.h"));` in the preamble.
pub fn programUsesOmp(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesOmp(item)) return true;
    return false;
}

fn blockUsesOmp(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesOmp(s)) return true;
    return false;
}

fn nodeUsesOmp(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@omp"),
        .omp_parallel    => true,
        .omp_for         => true,
        .call_expr       => |ce| blk: {
            if (nodeUsesOmp(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesOmp(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesOmp(be.left) or nodeUsesOmp(be.right),
        .unary_expr   => |ue| nodeUsesOmp(ue.operand),
        .var_decl     => |vd| nodeUsesOmp(vd.value),
        .ret_stmt     => |rs| nodeUsesOmp(rs.value),
        .expr_stmt    => |es| nodeUsesOmp(es),
        .field_expr   => |fe| nodeUsesOmp(fe.object),
        .defer_stmt   => |ds| nodeUsesOmp(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesOmp(is_.cond)) break :blk true;
            if (blockUsesOmp(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesOmp(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesOmp(ws.cond) or blockUsesOmp(ws.body),
        .for_stmt     => |fs| nodeUsesOmp(fs.iterable) or blockUsesOmp(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesOmp(ls.init) or nodeUsesOmp(ls.cond) or nodeUsesOmp(ls.update)) break :blk true;
            break :blk blockUsesOmp(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesOmp(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesOmp(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl      => |fd| blockUsesOmp(fd.body),
        .main_block   => |mb| blockUsesOmp(mb.body),
        .block        => |b|  blockUsesOmp(b),
        .fun_expr     => |fe| blockUsesOmp(fe.body),
        else => false,
    };
}

/// Return true when the program uses `@sodium::` or `@zcy.sodium` anywhere.
/// Used to emit `const _sodium = @cImport(@cInclude("sodium.h"));` in the preamble.
pub fn programUsesSodium(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesSodium(item)) return true;
    return false;
}

fn blockUsesSodium(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesSodium(s)) return true;
    return false;
}

fn nodeUsesSodium(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@sodium"),
        .call_expr       => |ce| blk: {
            if (nodeUsesSodium(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesSodium(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesSodium(be.left) or nodeUsesSodium(be.right),
        .unary_expr   => |ue| nodeUsesSodium(ue.operand),
        .var_decl     => |vd| nodeUsesSodium(vd.value),
        .ret_stmt     => |rs| nodeUsesSodium(rs.value),
        .expr_stmt    => |es| nodeUsesSodium(es),
        .field_expr   => |fe| nodeUsesSodium(fe.object),
        .defer_stmt   => |ds| nodeUsesSodium(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesSodium(is_.cond)) break :blk true;
            if (blockUsesSodium(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesSodium(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesSodium(ws.cond) or blockUsesSodium(ws.body),
        .for_stmt     => |fs| nodeUsesSodium(fs.iterable) or blockUsesSodium(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesSodium(ls.init) or nodeUsesSodium(ls.cond) or nodeUsesSodium(ls.update)) break :blk true;
            break :blk blockUsesSodium(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesSodium(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesSodium(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesSodium(fd.body),
        .main_block => |mb| blockUsesSodium(mb.body),
        .block      => |b|  blockUsesSodium(b),
        .fun_expr   => |fe| blockUsesSodium(fe.body),
        else => false,
    };
}

/// Return true when the program uses `@fflog::` anywhere.
/// Used to emit the `_FfLog` struct in the preamble.
pub fn programUsesFflog(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesFflog(item)) return true;
    return false;
}

fn blockUsesFflog(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesFflog(s)) return true;
    return false;
}

fn nodeUsesFflog(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@fflog"),
        .call_expr       => |ce| blk: {
            if (nodeUsesFflog(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesFflog(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesFflog(be.left) or nodeUsesFflog(be.right),
        .unary_expr   => |ue| nodeUsesFflog(ue.operand),
        .var_decl     => |vd| nodeUsesFflog(vd.value),
        .ret_stmt     => |rs| nodeUsesFflog(rs.value),
        .expr_stmt    => |es| nodeUsesFflog(es),
        .field_expr   => |fe| nodeUsesFflog(fe.object),
        .defer_stmt   => |ds| nodeUsesFflog(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesFflog(is_.cond)) break :blk true;
            if (blockUsesFflog(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesFflog(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesFflog(ws.cond) or blockUsesFflog(ws.body),
        .for_stmt     => |fs| nodeUsesFflog(fs.iterable) or blockUsesFflog(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesFflog(ls.init) or nodeUsesFflog(ls.cond) or nodeUsesFflog(ls.update)) break :blk true;
            break :blk blockUsesFflog(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesFflog(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesFflog(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesFflog(fd.body),
        .main_block => |mb| blockUsesFflog(mb.body),
        .block      => |b|  blockUsesFflog(b),
        .fun_expr   => |fe| blockUsesFflog(fe.body),
        else => false,
    };
}

/// Return true when the program uses `@sqlite::` anywhere.
/// Used to emit the `_Sqlite3` struct in the preamble.
pub fn programUsesSqlite(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesSqlite(item)) return true;
    return false;
}

fn blockUsesSqlite(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesSqlite(s)) return true;
    return false;
}

fn nodeUsesSqlite(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@sqlite"),
        .call_expr       => |ce| blk: {
            if (nodeUsesSqlite(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesSqlite(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesSqlite(be.left) or nodeUsesSqlite(be.right),
        .unary_expr   => |ue| nodeUsesSqlite(ue.operand),
        .var_decl     => |vd| nodeUsesSqlite(vd.value),
        .ret_stmt     => |rs| nodeUsesSqlite(rs.value),
        .expr_stmt    => |es| nodeUsesSqlite(es),
        .field_expr   => |fe| nodeUsesSqlite(fe.object),
        .defer_stmt   => |ds| nodeUsesSqlite(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesSqlite(is_.cond)) break :blk true;
            if (blockUsesSqlite(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesSqlite(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesSqlite(ws.cond) or blockUsesSqlite(ws.body),
        .for_stmt     => |fs| nodeUsesSqlite(fs.iterable) or blockUsesSqlite(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesSqlite(ls.init) or nodeUsesSqlite(ls.cond) or nodeUsesSqlite(ls.update)) break :blk true;
            break :blk blockUsesSqlite(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesSqlite(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesSqlite(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesSqlite(fd.body),
        .main_block => |mb| blockUsesSqlite(mb.body),
        .block      => |b|  blockUsesSqlite(b),
        .fun_expr   => |fe| blockUsesSqlite(fe.body),
        else => false,
    };
}

/// Return true when the program uses `@qt::` anywhere.
/// Used to emit the Qt wrapper structs in the preamble.
pub fn programUsesQt(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesQt(item)) return true;
    return false;
}

fn blockUsesQt(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesQt(s)) return true;
    return false;
}

fn nodeUsesQt(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@qt"),
        .call_expr       => |ce| blk: {
            if (nodeUsesQt(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesQt(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesQt(be.left) or nodeUsesQt(be.right),
        .unary_expr   => |ue| nodeUsesQt(ue.operand),
        .var_decl     => |vd| nodeUsesQt(vd.value),
        .ret_stmt     => |rs| nodeUsesQt(rs.value),
        .expr_stmt    => |es| nodeUsesQt(es),
        .field_expr   => |fe| nodeUsesQt(fe.object),
        .defer_stmt   => |ds| nodeUsesQt(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesQt(is_.cond)) break :blk true;
            if (blockUsesQt(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesQt(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesQt(ws.cond) or blockUsesQt(ws.body),
        .for_stmt     => |fs| nodeUsesQt(fs.iterable) or blockUsesQt(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesQt(ls.init) or nodeUsesQt(ls.cond) or nodeUsesQt(ls.update)) break :blk true;
            break :blk blockUsesQt(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesQt(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesQt(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesQt(fd.body),
        .main_block => |mb| blockUsesQt(mb.body),
        .block      => |b|  blockUsesQt(b),
        .fun_expr   => |fe| blockUsesQt(fe.body),
        else => false,
    };
}

/// Return true when the expression is an `@xi::window(…)` call.
fn isXiWindowCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@xi") and
           nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "window");
}

/// Return true when the expression is an `@xi::font(…)` call.
fn isXiFontCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@xi") and
           nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "font");
}

/// Return true when the expression is an `@xi::img(…)` call (direct, not catch-wrapped).
fn isXiImgCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@xi") and
           nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "img");
}

/// Return true when the expression is an `@xi::gif(…)` call.
fn isXiGifCall(node: *const ast.Node) bool {
    if (node.* != .call_expr) return false;
    const ce = node.call_expr;
    if (ce.callee.* != .ns_builtin_expr) return false;
    const nb = ce.callee.ns_builtin_expr;
    return std.mem.eql(u8, nb.namespace.lexeme, "@xi") and
           nb.path.len == 1 and std.mem.eql(u8, nb.path[0].lexeme, "gif");
}

/// Return true when the program uses `@xi::` anywhere.
pub fn programUsesXi(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesXi(item)) return true;
    return false;
}

fn blockUsesXi(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesXi(s)) return true;
    return false;
}

fn nodeUsesXi(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@xi"),
        .xi_draw_block   => true,
        .xi_event_block  => true,
        .call_expr       => |ce| blk: {
            if (nodeUsesXi(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesXi(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesXi(be.left) or nodeUsesXi(be.right),
        .unary_expr   => |ue| nodeUsesXi(ue.operand),
        .var_decl     => |vd| nodeUsesXi(vd.value),
        .ret_stmt     => |rs| nodeUsesXi(rs.value),
        .expr_stmt    => |es| nodeUsesXi(es),
        .field_expr   => |fe| nodeUsesXi(fe.object),
        .defer_stmt   => |ds| nodeUsesXi(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesXi(is_.cond)) break :blk true;
            if (blockUsesXi(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesXi(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesXi(ws.cond) or blockUsesXi(ws.body),
        .for_stmt     => |fs| nodeUsesXi(fs.iterable) or blockUsesXi(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesXi(ls.init) or nodeUsesXi(ls.cond) or nodeUsesXi(ls.update)) break :blk true;
            break :blk blockUsesXi(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesXi(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesXi(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesXi(fd.body),
        .main_block => |mb| blockUsesXi(mb.body),
        .block      => |b|  blockUsesXi(b),
        .fun_expr   => |fe| blockUsesXi(fe.body),
        else => false,
    };
}

/// Return true when the program uses `@kry::` or `@zcy.kry` anywhere.
/// Used to emit crypto helper functions in the preamble.
pub fn programUsesKry(prog: ast.Program) bool {
    for (prog.items) |item| if (nodeUsesKry(item)) return true;
    return false;
}

fn blockUsesKry(block: ast.Block) bool {
    for (block.stmts) |s| if (nodeUsesKry(s)) return true;
    return false;
}

fn nodeUsesKry(node: *const ast.Node) bool {
    return switch (node.*) {
        .ns_builtin_expr => |nb| std.mem.eql(u8, nb.namespace.lexeme, "@kry"),
        .call_expr       => |ce| blk: {
            if (nodeUsesKry(ce.callee)) break :blk true;
            for (ce.args) |a| if (nodeUsesKry(a)) break :blk true;
            break :blk false;
        },
        .binary_expr  => |be| nodeUsesKry(be.left) or nodeUsesKry(be.right),
        .unary_expr   => |ue| nodeUsesKry(ue.operand),
        .var_decl     => |vd| nodeUsesKry(vd.value),
        .ret_stmt     => |rs| nodeUsesKry(rs.value),
        .expr_stmt    => |es| nodeUsesKry(es),
        .field_expr   => |fe| nodeUsesKry(fe.object),
        .defer_stmt   => |ds| nodeUsesKry(ds.expr),
        .if_stmt      => |is_| blk: {
            if (nodeUsesKry(is_.cond)) break :blk true;
            if (blockUsesKry(is_.then_blk)) break :blk true;
            if (is_.else_blk) |eb| if (blockUsesKry(eb)) break :blk true;
            break :blk false;
        },
        .while_stmt   => |ws| nodeUsesKry(ws.cond) or blockUsesKry(ws.body),
        .for_stmt     => |fs| nodeUsesKry(fs.iterable) or blockUsesKry(fs.body),
        .loop_stmt    => |ls| blk: {
            if (nodeUsesKry(ls.init) or nodeUsesKry(ls.cond) or nodeUsesKry(ls.update)) break :blk true;
            break :blk blockUsesKry(ls.body);
        },
        .switch_stmt  => |ss| blk: {
            if (nodeUsesKry(ss.subject)) break :blk true;
            for (ss.arms) |arm| if (blockUsesKry(arm.body)) break :blk true;
            break :blk false;
        },
        .fn_decl    => |fd| blockUsesKry(fd.body),
        .main_block => |mb| blockUsesKry(mb.body),
        .block      => |b|  blockUsesKry(b),
        .fun_expr   => |fe| blockUsesKry(fe.body),
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

/// Return the root identifier name of a (possibly nested) field_expr or index
/// expression, or null if the root is not a plain identifier.
/// Used by isReassignedInBlock to detect `name.field = …` as a mutation of `name`.
fn exprRootIdent(node: *const ast.Node) ?[]const u8 {
    return switch (node.*) {
        .ident_expr  => |t|  t.lexeme,
        .field_expr  => |fe| exprRootIdent(fe.object),
        .unary_expr  => |ue| exprRootIdent(ue.operand),
        // Subscript `name[idx]` — encoded as binary_expr with op.kind == .l_bracket
        .binary_expr => |be| if (be.op.kind == .l_bracket) exprRootIdent(be.left) else null,
        else         => null,
    };
}

// ─── Raylib call helpers (file-scope) ────────────────────────────────────────

/// Return true if the root object of a field_expr callee chain is `rl`.
/// Used to detect rl.func() calls so str args can be coerced to [:0]const u8.
fn isRlCalleeRoot(node: *const ast.Node) bool {
    return switch (node.*) {
        .ident_expr => |t| std.mem.eql(u8, t.lexeme, "rl"),
        .field_expr => |fe| isRlCalleeRoot(fe.object),
        else => false,
    };
}

/// Write `name` (PascalCase or camelCase) as snake_case to `writer`.
/// Used by @rl::key / @rl::btn to convert user-friendly names to raylib enum values.
/// Examples: Space → space, LeftShift → left_shift, F1 → f1, Up → up.
fn writeRlSnakeCase(writer: std.io.AnyWriter, name: []const u8) !void {
    for (name, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c) and !std.ascii.isUpper(name[i - 1])) {
            try writer.writeByte('_');
        }
        try writer.writeByte(std.ascii.toLower(c));
    }
}

/// Return true when `node` is an `ident_expr` whose lexeme is the Zcythe
/// `@undef` / `undef` sentinel (maps to Zig `undefined` in decls, `null` in comparisons).
fn isUndefExpr(node: *const ast.Node) bool {
    if (node.* == .ident_expr)   return std.mem.eql(u8, node.ident_expr.lexeme,   "undef");
    if (node.* == .builtin_expr) return std.mem.eql(u8, node.builtin_expr.lexeme, "@undef");
    return false;
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
            const inner_start = i + 1;
            // Nesting-aware scan for matching }
            var j = inner_start;
            var depth: usize = 0;
            while (j < s.len) {
                const c = s[j];
                if (c == '(' or c == '[' or c == '{') {
                    depth += 1;
                } else if (c == ')' or c == ']') {
                    if (depth > 0) depth -= 1;
                } else if (c == '}') {
                    if (depth == 0) break;
                    depth -= 1;
                }
                j += 1;
            }
            if (j < s.len and inner_start < j) {
                const spec = s[inner_start..j];
                // Simple ident/field-path placeholder
                if (isInterpolationIdent(spec)) return true;
                // Complex expression placeholder (starts with letter, _, or @)
                if (spec[0] == '@' or std.ascii.isAlphabetic(spec[0]) or spec[0] == '_') return true;
            }
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
    // Advance through ident chars, `.` (field access like `p.name`),
    // and `[N]` subscripts (like `buf[0]` or `buf[0].field`).
    var i: usize = 1;
    while (i < spec.len) {
        if (spec[i] == '_' or std.ascii.isAlphanumeric(spec[i])) {
            i += 1;
        } else if (spec[i] == '.' and i + 1 < spec.len and
                   (std.ascii.isAlphabetic(spec[i + 1]) or spec[i + 1] == '_'))
        {
            i += 1; // include the '.'
        } else if (spec[i] == '[') {
            // Allow ident[N] subscript with a non-negative integer index.
            i += 1; // consume '['
            if (i >= spec.len or !std.ascii.isDigit(spec[i])) return false;
            while (i < spec.len and std.ascii.isDigit(spec[i])) i += 1;
            if (i >= spec.len or spec[i] != ']') return false;
            i += 1; // consume ']'
            // Allow trailing `.*` deref — stripped in emit ([]T access needs no deref).
            if (i + 1 < spec.len and spec[i] == '.' and spec[i + 1] == '*') i += 2;
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
/// Handles dotted paths (`p.name`) and subscript notation (`buf[0]`).
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
        } else if (spec[i] == '[') {
            // Include [N] subscript in the ident path.
            i += 1;
            while (i < spec.len and std.ascii.isDigit(spec[i])) i += 1;
            if (i < spec.len and spec[i] == ']') i += 1;
            // Stop before `.*` deref suffix — emit only the subscript, not the deref.
            if (i + 1 < spec.len and spec[i] == '.' and spec[i + 1] == '*') break;
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

test "@cin >> i32 var emits parseInt coercion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    x : i32 = undef
        \\    @cin >> x
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "std.fmt.parseInt(i32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "_cin_raw_0") != null);
}

test "@cin >> f64 var emits parseFloat coercion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    v : f64 = undef
        \\    @cin >> v
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "std.fmt.parseFloat(f64,") != null);
}

test "@fs::mkdir/mkfile/del/rename/mov emit correct Zig calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main {
        \\    p := @fs::path("a")
        \\    @fs::mkdir(p)
        \\    @fs::mkfile(p)
        \\    @fs::del(p)
        \\    @fs::rename(p, "b")
        \\    @fs::mov(p, "c")
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "makePath(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "createFile(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "deleteTree(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "std.fs.rename(std.fs.cwd(),") != null);
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

test "\\{ in @pf format string emits {{ in Zig" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main { @pf("use \{ and \} for sets\n") }
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "use {{ and }} for sets") != null);
}

test "@i32(@input) emits try std.fmt.parseInt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main { n := @i32(@input("Enter: ")) @pl(n) }
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "try std.fmt.parseInt(i32,") != null);
}

test "@input::i32 emits bare std.fmt.parseInt for catch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\@main { n := @input::i32("Enter: ") catch |e| { _ => 0 } @pl(n) }
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "std.fmt.parseInt(i32, _zcyInput(") != null);
    // Must NOT have a leading `try` (user provides catch)
    try std.testing.expect(std.mem.indexOf(u8, out, "try std.fmt.parseInt(i32") == null);
}

// ── Class declarations (Cls.zcy) ─────────────────────────────────────────────

test "cls basic empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const out = try parseAndEmit(arena.allocator(), &buf, "cls Basic {}");
    try std.testing.expect(std.mem.indexOf(u8, out, "pub const Basic = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "};") != null);
}

test "cls fields pub and private" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Person { pub name: str, age: i32, }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub name: []const u8,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "age: i32,") != null);
}

test "cls @init and @deinit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Foo { @init {} @deinit {} }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn init(self: *@This()) void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn deinit(self: *@This()) void {") != null);
}

test "cls public method with self" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Foo { pub fn greet() {} }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn greet(self: *@This()) void {") != null);
}

test "cls private method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Foo { fn helper() {} }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    // private method: no 'pub' prefix
    try std.testing.expect(std.mem.indexOf(u8, out, "fn helper(self: *@This()) void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn helper") == null);
}

test "cls ovrd fun method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Walker { ovrd fun walking() {} }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn walking(self: *@This()) void {") != null);
}

test "cls method with return type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Counter { pub fn get() -> i32 { ret 0 } }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn get(self: *@This()) i32 {") != null);
}

test "cls extends with pub base" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Child : pub Parent {}";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub _base: Parent,") != null);
}

test "cls extends private base" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Child : Base {}";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "_base: Base,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub _base") == null);
}

test "cls implements-only (::) emits comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Window :: Keyboard {}";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "// implements: Keyboard") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub const Window = struct {") != null);
}

test "cls extends and implements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Person : pub Human : Talk, Walk {}";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub const Person = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub _base: Human,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "// implements: Talk, Walk") != null);
}

test "cls method body uses self" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src = "cls Counter { count: i32, pub fn inc() { self.count += 1 } }";
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn inc(self: *@This()) void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "self.count += 1;") != null);
}

test "cls full — Cls.zcy Person" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const src =
        \\cls Person : pub Human : Talk, Walk, Run {
        \\    pub name: str,
        \\    secret: str,
        \\    @init {}
        \\    @deinit {}
        \\    ovrd fun walking() {}
        \\}
    ;
    const out = try parseAndEmit(arena.allocator(), &buf, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub const Person = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub _base: Human,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "// implements: Talk, Walk, Run") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub name: []const u8,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "secret: []const u8,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn init(self: *@This()) void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "pub fn deinit(self: *@This()) void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn walking(self: *@This()) void {") != null);
}
