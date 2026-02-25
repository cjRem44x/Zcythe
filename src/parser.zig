//! Zcythe Parser  –  src/parser.zig
//!
//! Recursive-descent parser that converts a flat token stream into an AST.
//! The caller owns all memory via a provided arena allocator; freeing the
//! arena releases the entire tree.
//!
//! Typical usage:
//! ```zig
//!     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//!     defer arena.deinit();
//!     var p = Parser.init(arena.allocator(), source);
//!     const root = try p.parse();
//!     // use root (AST valid until arena.deinit())
//! ```

const std   = @import("std");
const lexer = @import("lexer.zig");
const ast   = @import("ast.zig");

const Lexer     = lexer.Lexer;
const Token     = lexer.Token;
const TokenKind = lexer.TokenKind;

// ═══════════════════════════════════════════════════════════════════════════
//  Error set
// ═══════════════════════════════════════════════════════════════════════════

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Parser
// ═══════════════════════════════════════════════════════════════════════════

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer:     Lexer,
    current:   Token,
    peek:      Token,

    // ─── Construction ──────────────────────────────────────────────────────

    /// Advance the lexer past any comment tokens and return the next real token.
    fn nextNonComment(lex: *Lexer) Token {
        var tok = lex.next();
        while (tok.kind == .comment) tok = lex.next();
        return tok;
    }

    /// Create a Parser positioned at the first two non-comment tokens of `src`.
    pub fn init(allocator: std.mem.Allocator, src: []const u8) Parser {
        var lex     = Lexer.init(src);
        const cur   = nextNonComment(&lex);
        const peek_ = nextNonComment(&lex);
        return .{
            .allocator = allocator,
            .lexer     = lex,
            .current   = cur,
            .peek      = peek_,
        };
    }

    // ─── Helpers ───────────────────────────────────────────────────────────

    /// Consume `current`, shift `peek` to `current`, load a new peek.
    /// Returns the consumed token.
    fn advance(self: *Parser) Token {
        const prev   = self.current;
        self.current = self.peek;
        self.peek    = nextNonComment(&self.lexer);
        return prev;
    }

    /// Consume and return `current` if its kind matches; else return an error.
    fn expect(self: *Parser, kind: TokenKind) !Token {
        if (self.current.kind == .eof)  return error.UnexpectedEof;
        if (self.current.kind != kind)  return error.UnexpectedToken;
        return self.advance();
    }

    /// Allocate a single Node on the arena and initialise it with `value`.
    fn node(self: *Parser, value: ast.Node) !*ast.Node {
        const n = try self.allocator.create(ast.Node);
        n.* = value;
        return n;
    }

    // ─── Public entry point ────────────────────────────────────────────────

    /// Parse the full source and return the root `program` node.
    pub fn parse(self: *Parser) !*ast.Node {
        var items: std.ArrayListUnmanaged(*ast.Node) = .{};
        while (self.current.kind != .eof) {
            try items.append(self.allocator, try self.parseTopItem());
        }
        return self.node(.{ .program = .{
            .items = try items.toOwnedSlice(self.allocator),
        }});
    }

    // ─── Top-level items ───────────────────────────────────────────────────

    fn parseTopItem(self: *Parser) !*ast.Node {
        switch (self.current.kind) {
            .builtin => {
                if (std.mem.eql(u8, self.current.lexeme, "@main"))
                    return self.parseMainBlock();
                if (std.mem.eql(u8, self.current.lexeme, "@import")) {
                    const expr = try self.parseExpr();
                    return self.node(.{ .expr_stmt = expr });
                }
                return error.UnexpectedToken;
            },
            .kw_fn => return self.parseFnDecl(),
            .eof   => return error.UnexpectedEof,
            else   => return error.UnexpectedToken,
        }
    }

    fn parseMainBlock(self: *Parser) !*ast.Node {
        _ = try self.expect(.builtin); // @main
        const body = try self.parseBlock();
        return self.node(.{ .main_block = .{ .body = body } });
    }

    fn parseFnDecl(self: *Parser) !*ast.Node {
        _ = try self.expect(.kw_fn);
        const name   = try self.expect(.ident);
        _ = try self.expect(.l_paren);
        const params = try self.parseParamList();
        _ = try self.expect(.r_paren);

        var ret_type: ?ast.TypeAnn = null;
        if (self.current.kind == .arrow) {
            _ = self.advance();
            ret_type = try self.parseTypeAnn();
        }

        const body = try self.parseBlock();
        return self.node(.{ .fn_decl = .{
            .name     = name,
            .params   = params,
            .ret_type = ret_type,
            .body     = body,
        }});
    }

    fn parseParamList(self: *Parser) ![]ast.Param {
        var params: std.ArrayListUnmanaged(ast.Param) = .{};
        if (self.current.kind == .r_paren)
            return params.toOwnedSlice(self.allocator);

        try params.append(self.allocator, try self.parseParam());
        while (self.current.kind == .comma) {
            _ = self.advance();
            if (self.current.kind == .r_paren) break; // trailing comma
            try params.append(self.allocator, try self.parseParam());
        }
        return params.toOwnedSlice(self.allocator);
    }

    fn parseParam(self: *Parser) !ast.Param {
        const name = try self.expect(.ident);
        var type_ann: ?ast.TypeAnn = null;
        if (self.current.kind == .colon) {
            _ = self.advance();
            type_ann = try self.parseTypeAnn();
        }
        return .{ .name = name, .type_ann = type_ann };
    }

    fn parseTypeAnn(self: *Parser) !ast.TypeAnn {
        var is_array = false;
        if (self.current.kind == .l_bracket) {
            _ = self.advance();
            _ = try self.expect(.r_bracket);
            is_array = true;
        }
        const name = try self.expect(.ident);
        return .{ .name = name, .is_array = is_array };
    }

    // ─── Block & statements ────────────────────────────────────────────────

    fn parseBlock(self: *Parser) !ast.Block {
        _ = try self.expect(.l_brace);
        var stmts: std.ArrayListUnmanaged(*ast.Node) = .{};
        while (self.current.kind != .r_brace) {
            if (self.current.kind == .eof) return error.UnexpectedEof;
            try stmts.append(self.allocator, try self.parseStmt());
        }
        _ = try self.expect(.r_brace);
        return .{ .stmts = try stmts.toOwnedSlice(self.allocator) };
    }

    fn parseStmt(self: *Parser) !*ast.Node {
        // ret statement
        if (self.current.kind == .kw_ret) return self.parseRetStmt();

        // if / else statement
        if (self.current.kind == .kw_if) return self.parseIfStmt();

        // Variable declaration: IDENT followed by :=, ::, or :
        if (self.current.kind == .ident) {
            const pk = self.peek.kind;
            if (pk == .decl_mut or pk == .decl_immut or pk == .colon)
                return self.parseVarDecl();
        }

        return self.parseExprStmt();
    }

    fn parseRetStmt(self: *Parser) !*ast.Node {
        _ = try self.expect(.kw_ret);
        const value = try self.parseExpr();
        return self.node(.{ .ret_stmt = .{ .value = value } });
    }

    fn parseIfStmt(self: *Parser) (ParseError || std.mem.Allocator.Error)!*ast.Node {
        _ = try self.expect(.kw_if);
        // Parens around the condition are optional: `if (x)` and `if x` both work.
        const parens = self.current.kind == .l_paren;
        if (parens) _ = self.advance();
        const cond = try self.parseExpr();
        if (parens) _ = try self.expect(.r_paren);

        // then-branch: block `{ … }` or single statement
        const then_blk: ast.Block = if (self.current.kind == .l_brace)
            try self.parseBlock()
        else blk: {
            const stmt = try self.parseStmt();
            const arr  = try self.allocator.alloc(*ast.Node, 1);
            arr[0] = stmt;
            break :blk .{ .stmts = arr };
        };

        // optional else-branch
        var else_blk: ?ast.Block = null;
        if (self.current.kind == .kw_else) {
            _ = self.advance();
            else_blk = if (self.current.kind == .l_brace)
                try self.parseBlock()
            else blk: {
                const stmt = try self.parseStmt();
                const arr  = try self.allocator.alloc(*ast.Node, 1);
                arr[0] = stmt;
                break :blk .{ .stmts = arr };
            };
        }

        return self.node(.{ .if_stmt = .{
            .cond     = cond,
            .then_blk = then_blk,
            .else_blk = else_blk,
        }});
    }

    fn parseVarDecl(self: *Parser) !*ast.Node {
        const name = try self.expect(.ident);

        var kind: ast.VarKind      = undefined;
        var type_ann: ?ast.TypeAnn = null;

        switch (self.current.kind) {
            .decl_mut => {
                _ = self.advance();
                kind = .mut_implicit;
            },
            .decl_immut => {
                _ = self.advance();
                kind = .immut_implicit;
            },
            .colon => {
                _ = self.advance();
                type_ann = try self.parseTypeAnn();
                switch (self.current.kind) {
                    .eq => {
                        _ = self.advance();
                        kind = .mut_explicit;
                    },
                    .colon => {
                        _ = self.advance();
                        kind = .immut_explicit;
                    },
                    else => return error.UnexpectedToken,
                }
            },
            else => return error.UnexpectedToken,
        }

        const value = try self.parseExpr();
        return self.node(.{ .var_decl = .{
            .name     = name,
            .kind     = kind,
            .type_ann = type_ann,
            .value    = value,
        }});
    }

    fn parseExprStmt(self: *Parser) !*ast.Node {
        const expr = try self.parseExpr();
        return self.node(.{ .expr_stmt = expr });
    }

    // ─── Expression parsing (operator-precedence ladder) ──────────────────

    fn parseExpr(self: *Parser) !*ast.Node {
        return self.parseAssignment();
    }

    // assignment → logical (('=' | '+=' | '-=' | '*=' | '/=') logical)?
    fn parseAssignment(self: *Parser) !*ast.Node {
        var left = try self.parseLogical();
        switch (self.current.kind) {
            .eq, .plus_eq, .minus_eq, .star_eq, .slash_eq => {
                const op    = self.advance();
                const right = try self.parseLogical();
                left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
            },
            else => {},
        }
        return left;
    }

    // logical → equality (('&&' | '||') equality)*
    fn parseLogical(self: *Parser) !*ast.Node {
        var left = try self.parseEquality();
        while (self.current.kind == .amp_amp or self.current.kind == .pipe_pipe) {
            const op    = self.advance();
            const right = try self.parseEquality();
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // equality → relational (('==' | '!=') relational)*
    fn parseEquality(self: *Parser) !*ast.Node {
        var left = try self.parseRelational();
        while (self.current.kind == .eq_eq or self.current.kind == .bang_eq) {
            const op    = self.advance();
            const right = try self.parseRelational();
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // relational → stream (('<' | '>' | '<=' | '>=') stream)*
    fn parseRelational(self: *Parser) !*ast.Node {
        var left = try self.parseStream();
        while (self.current.kind == .lt  or self.current.kind == .gt or
               self.current.kind == .lt_eq or self.current.kind == .gt_eq)
        {
            const op    = self.advance();
            const right = try self.parseStream();
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // stream → additive (('<<' | '>>') additive (':' fmt_spec)?)*
    //
    // `expr : fmt_spec` after a stream operand attaches a user format hint
    // (e.g. `y:.3f`) and produces a `fmt_expr` node consumed by the codegen.
    // The spec runs until the next `<<`, `>>`, `}`, `)`, `,`, or EOF.
    fn parseStream(self: *Parser) !*ast.Node {
        var left = try self.parseAdditive();
        while (self.current.kind == .lshift or self.current.kind == .rshift) {
            const op = self.advance();
            var right = try self.parseAdditive();
            // Optional inline format spec:  expr : .3f
            if (self.current.kind == .colon) {
                _ = self.advance(); // consume ':'
                var spec: std.ArrayListUnmanaged(u8) = .{};
                while (true) {
                    switch (self.current.kind) {
                        .lshift, .rshift, .r_brace, .r_paren, .comma, .eof => break,
                        else => {
                            try spec.appendSlice(self.allocator, self.current.lexeme);
                            _ = self.advance();
                        },
                    }
                }
                const spec_str = try spec.toOwnedSlice(self.allocator);
                right = try self.node(.{ .fmt_expr = .{ .value = right, .spec = spec_str } });
            }
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // additive → multiplicative (('+' | '-') multiplicative)*
    fn parseAdditive(self: *Parser) !*ast.Node {
        var left = try self.parseMultiplicative();
        while (self.current.kind == .plus or self.current.kind == .minus) {
            const op    = self.advance();
            const right = try self.parseMultiplicative();
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // multiplicative → unary (('*' | '/') unary)*
    fn parseMultiplicative(self: *Parser) !*ast.Node {
        var left = try self.parseUnary();
        while (self.current.kind == .star or self.current.kind == .slash) {
            const op    = self.advance();
            const right = try self.parseUnary();
            left = try self.node(.{ .binary_expr = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    // unary → ('-' | '!') unary | postfix
    fn parseUnary(self: *Parser) !*ast.Node {
        if (self.current.kind == .minus or self.current.kind == .bang) {
            const op      = self.advance();
            const operand = try self.parseUnary();
            return self.node(.{ .unary_expr = .{ .op = op, .operand = operand } });
        }
        return self.parsePostfix();
    }

    // postfix → primary ('(' arg_list? ')' | '.' IDENT)*
    fn parsePostfix(self: *Parser) !*ast.Node {
        var left = try self.parsePrimary();
        while (true) {
            if (self.current.kind == .l_paren) {
                _ = self.advance();
                const args = try self.parseArgList();
                _ = try self.expect(.r_paren);
                left = try self.node(.{ .call_expr = .{ .callee = left, .args = args } });
            } else if (self.current.kind == .dot) {
                _ = self.advance();
                const field = try self.expect(.ident);
                left = try self.node(.{ .field_expr = .{ .object = left, .field = field } });
            } else {
                break;
            }
        }
        return left;
    }

    fn parseArgList(self: *Parser) (ParseError || std.mem.Allocator.Error)![] *ast.Node {
        var args: std.ArrayListUnmanaged(*ast.Node) = .{};
        if (self.current.kind == .r_paren)
            return args.toOwnedSlice(self.allocator);

        try args.append(self.allocator, try self.parseExpr());
        while (self.current.kind == .comma) {
            _ = self.advance();
            if (self.current.kind == .r_paren) break; // trailing comma
            try args.append(self.allocator, try self.parseExpr());
        }
        return args.toOwnedSlice(self.allocator);
    }

    // primary → INT_LIT | FLOAT_LIT | STRING_LIT | CHAR_LIT
    //         | BUILTIN
    //         | IDENT
    //         | IDENT '{' struct_fields? '}'
    //         | '{' (expr (',' expr)*)? '}'
    //         | '(' expr ')'
    //
    // Explicit error set required to break the inference cycle:
    //   parsePrimary → parseExpr → … → parsePrimary
    fn parsePrimary(self: *Parser) (ParseError || std.mem.Allocator.Error)!*ast.Node {
        switch (self.current.kind) {
            .int_lit    => return self.node(.{ .int_lit    = self.advance() }),
            .float_lit  => return self.node(.{ .float_lit  = self.advance() }),
            .string_lit => return self.node(.{ .string_lit = self.advance() }),
            .char_lit   => return self.node(.{ .char_lit   = self.advance() }),
            .builtin    => return self.node(.{ .builtin_expr = self.advance() }),

            .ident => {
                const tok = self.advance();
                // struct literal: IDENT '{'
                if (self.current.kind == .l_brace) {
                    _ = self.advance(); // consume '{'
                    const fields = try self.parseStructFields();
                    _ = try self.expect(.r_brace);
                    return self.node(.{ .struct_lit = .{ .type_name = tok, .fields = fields } });
                }
                return self.node(.{ .ident_expr = tok });
            },

            .l_brace => {
                _ = self.advance(); // consume '{'
                var elems: std.ArrayListUnmanaged(*ast.Node) = .{};
                if (self.current.kind != .r_brace) {
                    try elems.append(self.allocator, try self.parseExpr());
                    while (self.current.kind == .comma) {
                        _ = self.advance();
                        if (self.current.kind == .r_brace) break; // trailing comma
                        try elems.append(self.allocator, try self.parseExpr());
                    }
                }
                _ = try self.expect(.r_brace);
                return self.node(.{ .array_lit = .{
                    .elems = try elems.toOwnedSlice(self.allocator),
                }});
            },

            .l_paren => {
                _ = self.advance(); // consume '('
                const inner = try self.parseExpr();
                _ = try self.expect(.r_paren);
                return inner; // no wrapper node — grouping is structural only
            },

            .kw_fun => {
                _ = self.advance(); // consume `fun`
                _ = try self.expect(.l_paren);
                const params = try self.parseParamList();
                _ = try self.expect(.r_paren);
                var ret_type: ?ast.TypeAnn = null;
                if (self.current.kind == .arrow) {
                    _ = self.advance();
                    ret_type = try self.parseTypeAnn();
                }
                const body = try self.parseBlock();
                return self.node(.{ .fun_expr = .{
                    .params   = params,
                    .ret_type = ret_type,
                    .body     = body,
                }});
            },

            .eof  => return error.UnexpectedEof,
            else  => return error.UnexpectedToken,
        }
    }

    // struct_fields → '.' IDENT '=' expr (',' '.' IDENT '=' expr)*
    fn parseStructFields(self: *Parser) (ParseError || std.mem.Allocator.Error)![]ast.StructField {
        var fields: std.ArrayListUnmanaged(ast.StructField) = .{};
        if (self.current.kind == .r_brace)
            return fields.toOwnedSlice(self.allocator);

        // First field
        _ = try self.expect(.dot);
        const name  = try self.expect(.ident);
        _ = try self.expect(.eq);
        const value = try self.parseExpr();
        try fields.append(self.allocator, .{ .name = name, .value = value });

        // Remaining fields
        while (self.current.kind == .comma) {
            _ = self.advance();
            if (self.current.kind == .r_brace) break; // trailing comma
            _ = try self.expect(.dot);
            const fname  = try self.expect(.ident);
            _ = try self.expect(.eq);
            const fvalue = try self.parseExpr();
            try fields.append(self.allocator, .{ .name = fname, .value = fvalue });
        }
        return fields.toOwnedSlice(self.allocator);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════════════════════

test "empty @main block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main {}");
    const root = try p.parse();
    try std.testing.expect(root.* == .program);
    const items = root.program.items;
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expect(items[0].* == .main_block);
    try std.testing.expectEqual(@as(usize, 0), items[0].main_block.body.stmts.len);
}

test "@main with @pl call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src =
        \\@main {
        \\    @pl("Hello World")
        \\}
    ;
    var p    = Parser.init(arena.allocator(), src);
    const root = try p.parse();
    const stmts = root.program.items[0].main_block.body.stmts;
    try std.testing.expectEqual(@as(usize, 1), stmts.len);
    // The statement is an expr_stmt wrapping a call_expr
    try std.testing.expect(stmts[0].* == .expr_stmt);
    try std.testing.expect(stmts[0].expr_stmt.* == .call_expr);
    const call = stmts[0].expr_stmt.call_expr;
    try std.testing.expect(call.callee.* == .builtin_expr);
    try std.testing.expectEqualStrings("@pl", call.callee.builtin_expr.lexeme);
    try std.testing.expectEqual(@as(usize, 1), call.args.len);
    try std.testing.expect(call.args[0].* == .string_lit);
}

test "var decl: mut implicit (:=)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { x := 32 }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("x", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.mut_implicit, d.kind);
    try std.testing.expect(d.type_ann == null);
    try std.testing.expect(d.value.* == .int_lit);
}

test "var decl: immut implicit (::)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { PI :: 3.145 }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("PI", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.immut_implicit, d.kind);
    try std.testing.expect(d.type_ann == null);
    try std.testing.expect(d.value.* == .float_lit);
}

test "var decl: mut explicit (: T =)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { y : str = \"hello\" }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("y", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.mut_explicit, d.kind);
    try std.testing.expect(d.type_ann != null);
    try std.testing.expectEqualStrings("str", d.type_ann.?.name.lexeme);
    try std.testing.expect(!d.type_ann.?.is_array);
    try std.testing.expect(d.value.* == .string_lit);
}

test "var decl: immut explicit (: T :)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { FOO : str : \"Bar\" }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("FOO", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.immut_explicit, d.kind);
    try std.testing.expect(d.type_ann != null);
    try std.testing.expectEqualStrings("str", d.type_ann.?.name.lexeme);
    try std.testing.expect(!d.type_ann.?.is_array);
    try std.testing.expect(d.value.* == .string_lit);
}

test "var decl: array mutable (: []T =)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { int_arr : []i32 = {1,2,3} }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("int_arr", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.mut_explicit, d.kind);
    try std.testing.expect(d.type_ann != null);
    try std.testing.expect(d.type_ann.?.is_array);
    try std.testing.expectEqualStrings("i32", d.type_ann.?.name.lexeme);
    try std.testing.expect(d.value.* == .array_lit);
    try std.testing.expectEqual(@as(usize, 3), d.value.array_lit.elems.len);
}

test "var decl: array immutable (: []T :)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { names : []str : {\"John\", \"Joe\"} }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const d = stmt.var_decl;
    try std.testing.expectEqualStrings("names", d.name.lexeme);
    try std.testing.expectEqual(ast.VarKind.immut_explicit, d.kind);
    try std.testing.expect(d.type_ann != null);
    try std.testing.expect(d.type_ann.?.is_array);
    try std.testing.expectEqualStrings("str", d.type_ann.?.name.lexeme);
    try std.testing.expect(d.value.* == .array_lit);
    try std.testing.expectEqual(@as(usize, 2), d.value.array_lit.elems.len);
}

test "fn decl without type annotations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "fn add(a, b) { ret a+b }");
    const root = try p.parse();
    const fn_node = root.program.items[0];
    try std.testing.expect(fn_node.* == .fn_decl);
    const f = fn_node.fn_decl;
    try std.testing.expectEqualStrings("add", f.name.lexeme);
    try std.testing.expectEqual(@as(usize, 2), f.params.len);
    try std.testing.expectEqualStrings("a", f.params[0].name.lexeme);
    try std.testing.expect(f.params[0].type_ann == null);
    try std.testing.expectEqualStrings("b", f.params[1].name.lexeme);
    try std.testing.expect(f.params[1].type_ann == null);
    try std.testing.expect(f.ret_type == null);
    try std.testing.expectEqual(@as(usize, 1), f.body.stmts.len);
    const ret = f.body.stmts[0];
    try std.testing.expect(ret.* == .ret_stmt);
    try std.testing.expect(ret.ret_stmt.value.* == .binary_expr);
    try std.testing.expectEqual(lexer.TokenKind.plus, ret.ret_stmt.value.binary_expr.op.kind);
}

test "fn decl with typed params and return type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = "fn add(a: i32, b: i32) -> i32 { ret a + b }";
    var p    = Parser.init(arena.allocator(), src);
    const root = try p.parse();
    const f = root.program.items[0].fn_decl;
    try std.testing.expectEqualStrings("add", f.name.lexeme);
    try std.testing.expectEqual(@as(usize, 2), f.params.len);
    try std.testing.expect(f.params[0].type_ann != null);
    try std.testing.expectEqualStrings("i32", f.params[0].type_ann.?.name.lexeme);
    try std.testing.expect(!f.params[0].type_ann.?.is_array);
    try std.testing.expect(f.params[1].type_ann != null);
    try std.testing.expectEqualStrings("i32", f.params[1].type_ann.?.name.lexeme);
    try std.testing.expect(f.ret_type != null);
    try std.testing.expectEqualStrings("i32", f.ret_type.?.name.lexeme);
    try std.testing.expect(!f.ret_type.?.is_array);
}

test "operator precedence: a + b * c" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { a + b * c }");
    const root = try p.parse();
    // expr_stmt → binary_expr(+, ident(a), binary_expr(*, ident(b), ident(c)))
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .expr_stmt);
    const outer = stmt.expr_stmt;
    try std.testing.expect(outer.* == .binary_expr);
    try std.testing.expectEqual(lexer.TokenKind.plus, outer.binary_expr.op.kind);
    try std.testing.expect(outer.binary_expr.left.* == .ident_expr);
    const inner = outer.binary_expr.right;
    try std.testing.expect(inner.* == .binary_expr);
    try std.testing.expectEqual(lexer.TokenKind.star, inner.binary_expr.op.kind);
    try std.testing.expect(inner.binary_expr.left.* == .ident_expr);
    try std.testing.expect(inner.binary_expr.right.* == .ident_expr);
}

test "field access chain: obj.field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { obj.field }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .expr_stmt);
    try std.testing.expect(stmt.expr_stmt.* == .field_expr);
    const fe = stmt.expr_stmt.field_expr;
    try std.testing.expect(fe.object.* == .ident_expr);
    try std.testing.expectEqualStrings("obj",   fe.object.ident_expr.lexeme);
    try std.testing.expectEqualStrings("field", fe.field.lexeme);
}

test "function call with args: add(1, 2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { add(1, 2) }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .expr_stmt);
    try std.testing.expect(stmt.expr_stmt.* == .call_expr);
    const call = stmt.expr_stmt.call_expr;
    try std.testing.expect(call.callee.* == .ident_expr);
    try std.testing.expectEqualStrings("add", call.callee.ident_expr.lexeme);
    try std.testing.expectEqual(@as(usize, 2), call.args.len);
    try std.testing.expect(call.args[0].* == .int_lit);
    try std.testing.expect(call.args[1].* == .int_lit);
}

test "struct literal: Person{.name = \"John\", .age = 32}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = "@main { p := Person{.name = \"John\", .age = 32} }";
    var p    = Parser.init(arena.allocator(), src);
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const val = stmt.var_decl.value;
    try std.testing.expect(val.* == .struct_lit);
    const sl = val.struct_lit;
    try std.testing.expectEqualStrings("Person", sl.type_name.lexeme);
    try std.testing.expectEqual(@as(usize, 2), sl.fields.len);
    try std.testing.expectEqualStrings("name", sl.fields[0].name.lexeme);
    try std.testing.expect(sl.fields[0].value.* == .string_lit);
    try std.testing.expectEqualStrings("age", sl.fields[1].name.lexeme);
    try std.testing.expect(sl.fields[1].value.* == .int_lit);
}

test "array literal: {1, 2, 3}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p    = Parser.init(arena.allocator(), "@main { x := {1, 2, 3} }");
    const root = try p.parse();
    const stmt = root.program.items[0].main_block.body.stmts[0];
    try std.testing.expect(stmt.* == .var_decl);
    const val = stmt.var_decl.value;
    try std.testing.expect(val.* == .array_lit);
    try std.testing.expectEqual(@as(usize, 3), val.array_lit.elems.len);
    for (val.array_lit.elems) |elem| {
        try std.testing.expect(elem.* == .int_lit);
    }
}
