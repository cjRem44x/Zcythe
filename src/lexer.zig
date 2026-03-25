//! Zcythe Lexer  –  src/lexer.zig
//!
//! Converts a Zcythe source string into a flat stream of `Token` values.
//! Each token carries:
//!   • `kind`   – syntactic category (see `TokenKind`)
//!   • `lexeme` – a zero-copy slice into the original source buffer
//!   • `loc`    – 1-based (line, col) of the first character
//!
//! All tokens share the lifetime of the source slice passed to `Lexer.init`.
//! Individual `next()` calls perform no heap allocation; `collectAlloc` is
//! the only function that allocates.
//!
//! Typical usage:
//! ```
//!     var lex = Lexer.init(source);
//!     while (true) {
//!         const tok = lex.next();
//!         if (tok.kind == .eof) break;
//!         // process tok …
//!     }
//! ```

const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════
//  Token kinds
// ═══════════════════════════════════════════════════════════════════════════

/// Every distinct syntactic category the lexer can produce.
pub const TokenKind = enum {

    // ── Literals ──────────────────────────────────────────────────────────
    int_lit,    // 42  0  128
    float_lit,  // 3.14  0.5
    string_lit, // "hello"
    char_lit,   // 'A'

    // ── Names ─────────────────────────────────────────────────────────────
    ident,   // foo  Bar  _x  (not a keyword)
    builtin, // @main  @pl  @import  (@ followed by an identifier)

    // ── Keywords ──────────────────────────────────────────────────────────
    kw_fn,     // fn
    kw_fun,    // fun  (used with ovrd in class methods)
    kw_ret,    // ret
    kw_if,     // if
    kw_else,   // else
    kw_struct, // struct
    kw_cls,    // cls
    kw_dat,    // dat  (data-only struct)
    kw_pub,    // pub
    kw_ovrd,   // ovrd
    kw_for,    // for
    kw_loop,   // loop  (C-style counted loop)
    kw_while,  // while
    kw_try,    // try
    kw_catch,  // catch
    kw_switch, // switch
    kw_defer,  // defer
    kw_unn,    // unn   (tagged union)
    kw_imu,    // imu   (immutable pointer / field modifier)
    kw_enum,   // enum
    kw_undef,  // undef (maps to Zig `undefined`)
    kw_elif,   // elif  (else-if chain)
    kw_null,   // NULL  (null pointer sentinel)
    kw_self,   // self
    kw_any,    // any
    kw_and,    // and  (logical AND — alias for &&)
    kw_or,     // or   (logical OR  — alias for ||)
    kw_not,    // not  (logical NOT — alias for !)

    // ── Multi-character operators ──────────────────────────────────────────
    decl_mut,   // :=   mutable implicit-type declaration
    decl_immut, // ::   immutable implicit-type declaration (also cls implements)
    arrow,      // ->   return-type arrow
    fat_arrow,  // =>   "in" / "do" arrow (for/while loops, imports)
    range_in,   // ..=  inclusive range
    range_ex,   // ..   exclusive range
    plus_eq,    // +=
    minus_eq,   // -=
    star_eq,    // *=
    slash_eq,   // /=
    eq_eq,      // ==
    bang_eq,    // !=
    lt_eq,      // <=
    gt_eq,      // >=
    amp_amp,    // &&
    pipe_pipe,  // ||
    lshift,     // <<   stream-out / left-shift
    rshift,     // >>   stream-in / right-shift

    // ── Single-character operators ─────────────────────────────────────────
    colon,    // :
    question, // ?  nullable-return marker
    bang,     // !  error-return marker
    plus,     // +
    minus,    // -
    star,     // *
    slash,    // /
    eq,       // =
    lt,       // <
    gt,       // >
    pipe,     // |
    amp,      // &
    dot,      // .

    // ── Delimiters ─────────────────────────────────────────────────────────
    l_brace,   // {
    r_brace,   // }
    l_paren,   // (
    r_paren,   // )
    l_bracket, // [
    r_bracket, // ]

    // ── Punctuation ────────────────────────────────────────────────────────
    comma,     // ,
    semicolon, // ;

    // ── Meta ───────────────────────────────────────────────────────────────
    comment, // # … (includes the '#', runs to end of line)
    eof,     // end of input
    invalid, // unrecognised character

    /// Returns true for all `kw_*` variants.
    pub fn isKeyword(self: TokenKind) bool {
        const v = @intFromEnum(self);
        return v >= @intFromEnum(TokenKind.kw_fn) and
               v <= @intFromEnum(TokenKind.kw_or);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
//  Source location
// ═══════════════════════════════════════════════════════════════════════════

/// 1-based line and column of the first byte of a token.
pub const Loc = struct {
    line: u32,
    col:  u32,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Token
// ═══════════════════════════════════════════════════════════════════════════

/// A single lexical unit produced by the Lexer.
pub const Token = struct {
    kind:   TokenKind,
    /// Zero-copy slice into the original source buffer.
    lexeme: []const u8,
    /// Position of the first character (1-based line, col).
    loc:    Loc,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Lexer
// ═══════════════════════════════════════════════════════════════════════════

pub const Lexer = struct {
    /// Full source text.  Not owned; must outlive this Lexer and all Tokens
    /// it produces (Token.lexeme slices point into this buffer).
    src:  []const u8,
    /// Current byte index into `src`.
    pos:  usize,
    /// Current 1-based line number.
    line: u32,
    /// Current 1-based column number.
    col:  u32,

    // ─── Construction ──────────────────────────────────────────────────────

    /// Create a new Lexer positioned at the start of `src`.
    pub fn init(src: []const u8) Lexer {
        return .{ .src = src, .pos = 0, .line = 1, .col = 1 };
    }

    // ─── Private helpers ───────────────────────────────────────────────────

    /// Return the current character without consuming it (returns 0 at EOF).
    inline fn peek(self: *const Lexer) u8 {
        if (self.pos >= self.src.len) return 0;
        return self.src[self.pos];
    }

    /// Return the character one position ahead without consuming (0 at EOF).
    inline fn peekAhead(self: *const Lexer) u8 {
        const nxt = self.pos + 1;
        if (nxt >= self.src.len) return 0;
        return self.src[nxt];
    }

    /// Consume and return the current character.
    /// Automatically increments `line` on newlines and `col` otherwise.
    fn advance(self: *Lexer) u8 {
        const c = self.src[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.col  = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    /// Consume the current character only when it equals `expected`.
    /// Returns true if the character was consumed.
    fn match(self: *Lexer, expected: u8) bool {
        if (self.pos >= self.src.len) return false;
        if (self.src[self.pos] != expected) return false;
        _ = self.advance();
        return true;
    }

    /// Skip all ASCII whitespace (space, tab, CR, LF).
    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.src.len) {
            switch (self.src[self.pos]) {
                ' ', '\t', '\r', '\n' => _ = self.advance(),
                else => break,
            }
        }
    }

    /// Build a Token whose lexeme is the source span [start, self.pos).
    inline fn makeToken(self: *const Lexer, kind: TokenKind, start: usize, loc: Loc) Token {
        return .{ .kind = kind, .lexeme = self.src[start..self.pos], .loc = loc };
    }

    // ─── Character classification ──────────────────────────────────────────

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    /// Valid identifier start: a-z, A-Z, or _.
    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    /// Valid identifier continuation: isAlpha or 0-9.
    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    // ─── Keyword lookup ────────────────────────────────────────────────────

    /// Return the keyword TokenKind for `word`, or `.ident` if not a keyword.
    fn lookupKeyword(word: []const u8) TokenKind {
        if (std.mem.eql(u8, word, "fn"))     return .kw_fn;
        if (std.mem.eql(u8, word, "fun"))    return .kw_fun;
        if (std.mem.eql(u8, word, "ret"))    return .kw_ret;
        if (std.mem.eql(u8, word, "if"))     return .kw_if;
        if (std.mem.eql(u8, word, "else"))   return .kw_else;
        if (std.mem.eql(u8, word, "struct")) return .kw_struct;
        if (std.mem.eql(u8, word, "cls"))    return .kw_cls;
        if (std.mem.eql(u8, word, "dat"))    return .kw_dat;
        if (std.mem.eql(u8, word, "pub"))    return .kw_pub;
        if (std.mem.eql(u8, word, "ovrd"))   return .kw_ovrd;
        if (std.mem.eql(u8, word, "for"))    return .kw_for;
        if (std.mem.eql(u8, word, "loop"))   return .kw_loop;
        if (std.mem.eql(u8, word, "while"))  return .kw_while;
        if (std.mem.eql(u8, word, "try"))    return .kw_try;
        if (std.mem.eql(u8, word, "catch"))  return .kw_catch;
        if (std.mem.eql(u8, word, "switch")) return .kw_switch;
        if (std.mem.eql(u8, word, "defer"))  return .kw_defer;
        if (std.mem.eql(u8, word, "unn"))    return .kw_unn;
        if (std.mem.eql(u8, word, "imu"))    return .kw_imu;
        if (std.mem.eql(u8, word, "enum"))   return .kw_enum;
        if (std.mem.eql(u8, word, "undef"))  return .kw_undef;
        if (std.mem.eql(u8, word, "elif"))   return .kw_elif;
        if (std.mem.eql(u8, word, "NULL"))   return .kw_null;
        if (std.mem.eql(u8, word, "self"))   return .kw_self;
        if (std.mem.eql(u8, word, "any"))    return .kw_any;
        if (std.mem.eql(u8, word, "and"))    return .kw_and;
        if (std.mem.eql(u8, word, "or"))     return .kw_or;
        if (std.mem.eql(u8, word, "not"))    return .kw_not;
        return .ident;
    }

    // ─── Scanning helpers ──────────────────────────────────────────────────

    /// Scan an integer or float literal.
    /// Caller must have already consumed the first digit.
    /// A dot followed by a digit promotes the result to float_lit.
    fn scanNumber(self: *Lexer, start: usize, loc: Loc) Token {
        // Consume remaining integer digits.
        while (isDigit(self.peek())) _ = self.advance();

        // A '.' immediately followed by a digit starts the fractional part.
        if (self.peek() == '.' and isDigit(self.peekAhead())) {
            _ = self.advance(); // consume '.'
            while (isDigit(self.peek())) _ = self.advance();
            return self.makeToken(.float_lit, start, loc);
        }

        return self.makeToken(.int_lit, start, loc);
    }

    /// Scan a double-quoted string literal.
    /// Caller must have already consumed the opening `"`.
    /// Handles `\"` and `\\` escape sequences; other escapes pass through.
    fn scanString(self: *Lexer, start: usize, loc: Loc) Token {
        while (self.pos < self.src.len and self.peek() != '"') {
            if (self.peek() == '\\') _ = self.advance(); // skip escape prefix
            _ = self.advance();
        }
        if (self.pos < self.src.len) _ = self.advance(); // consume closing '"'
        return self.makeToken(.string_lit, start, loc);
    }

    /// Scan a single-quoted character literal.
    /// Caller must have already consumed the opening `'`.
    fn scanChar(self: *Lexer, start: usize, loc: Loc) Token {
        while (self.pos < self.src.len and self.peek() != '\'') {
            if (self.peek() == '\\') _ = self.advance(); // skip escape prefix
            _ = self.advance();
        }
        if (self.pos < self.src.len) _ = self.advance(); // consume closing '\''
        return self.makeToken(.char_lit, start, loc);
    }

    /// Scan an identifier or keyword.
    /// Caller must have already consumed the first character.
    fn scanIdent(self: *Lexer, start: usize, loc: Loc) Token {
        while (isAlphaNumeric(self.peek())) _ = self.advance();
        const word = self.src[start..self.pos];
        return .{ .kind = lookupKeyword(word), .lexeme = word, .loc = loc };
    }

    // ─── Public API ────────────────────────────────────────────────────────

    /// Return the next Token from the source.
    /// After the source is exhausted every subsequent call returns `.eof`.
    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();

        // End of input.
        if (self.pos >= self.src.len) {
            return .{ .kind = .eof, .lexeme = "", .loc = .{ .line = self.line, .col = self.col } };
        }

        const start = self.pos;
        const loc   = Loc{ .line = self.line, .col = self.col };
        const c     = self.advance();

        return switch (c) {

            // ── Line comment: # …  (runs to end of line) ──────────────────
            '#' => blk: {
                while (self.pos < self.src.len and self.peek() != '\n')
                    _ = self.advance();
                break :blk self.makeToken(.comment, start, loc);
            },

            // ── Builtin: @ident ────────────────────────────────────────────
            '@' => blk: {
                while (isAlphaNumeric(self.peek())) _ = self.advance();
                break :blk self.makeToken(.builtin, start, loc);
            },

            // ── String literal ─────────────────────────────────────────────
            '"' => self.scanString(start, loc),

            // ── Character literal ──────────────────────────────────────────
            '\'' => self.scanChar(start, loc),

            // ── Numeric literal ────────────────────────────────────────────
            '0'...'9' => self.scanNumber(start, loc),

            // ── Identifier / keyword ───────────────────────────────────────
            'a'...'z', 'A'...'Z', '_' => self.scanIdent(start, loc),

            // ── Colon family:  :  :=  :: ───────────────────────────────────
            ':' => if (self.match('='))
                        self.makeToken(.decl_mut,   start, loc)
                   else if (self.match(':'))
                        self.makeToken(.decl_immut, start, loc)
                   else
                        self.makeToken(.colon, start, loc),

            // ── Dot family:  .  ..  ..= ────────────────────────────────────
            '.' => blk: {
                if (self.peek() == '.') {
                    _ = self.advance();
                    if (self.match('=')) break :blk self.makeToken(.range_in, start, loc);
                    break :blk self.makeToken(.range_ex, start, loc);
                }
                break :blk self.makeToken(.dot, start, loc);
            },

            // ── Minus family:  -  -=  -> ───────────────────────────────────
            '-' => if (self.match('>'))
                        self.makeToken(.arrow,    start, loc)
                   else if (self.match('='))
                        self.makeToken(.minus_eq, start, loc)
                   else
                        self.makeToken(.minus, start, loc),

            // ── Equals family:  =  ==  => ──────────────────────────────────
            '=' => if (self.match('='))
                        self.makeToken(.eq_eq,     start, loc)
                   else if (self.match('>'))
                        self.makeToken(.fat_arrow, start, loc)
                   else
                        self.makeToken(.eq, start, loc),

            // ── Bang family:  !  != ────────────────────────────────────────
            '!' => if (self.match('='))
                        self.makeToken(.bang_eq, start, loc)
                   else
                        self.makeToken(.bang, start, loc),

            // ── Less-than family:  <  <=  << ───────────────────────────────
            '<' => if (self.match('<'))
                        self.makeToken(.lshift, start, loc)
                   else if (self.match('='))
                        self.makeToken(.lt_eq,  start, loc)
                   else
                        self.makeToken(.lt, start, loc),

            // ── Greater-than family:  >  >=  >> ───────────────────────────────
            '>' => if (self.match('>'))
                        self.makeToken(.rshift, start, loc)
                   else if (self.match('='))
                        self.makeToken(.gt_eq,  start, loc)
                   else
                        self.makeToken(.gt,     start, loc),

            // ── Plus family:  +  += ────────────────────────────────────────
            '+' => if (self.match('='))
                        self.makeToken(.plus_eq, start, loc)
                   else
                        self.makeToken(.plus, start, loc),

            // ── Star family:  *  *= ────────────────────────────────────────
            '*' => if (self.match('='))
                        self.makeToken(.star_eq, start, loc)
                   else
                        self.makeToken(.star, start, loc),

            // ── Slash family:  /  /= ───────────────────────────────────────
            '/' => if (self.match('='))
                        self.makeToken(.slash_eq, start, loc)
                   else
                        self.makeToken(.slash, start, loc),

            // ── Pipe family:  |  || ────────────────────────────────────────
            '|' => if (self.match('|'))
                        self.makeToken(.pipe_pipe, start, loc)
                   else
                        self.makeToken(.pipe, start, loc),

            // ── Ampersand family:  &  && ───────────────────────────────────
            '&' => if (self.match('&'))
                        self.makeToken(.amp_amp, start, loc)
                   else
                        self.makeToken(.amp, start, loc),

            // ── Single-character tokens ────────────────────────────────────
            '?' => self.makeToken(.question,  start, loc),
            '{' => self.makeToken(.l_brace,   start, loc),
            '}' => self.makeToken(.r_brace,   start, loc),
            '(' => self.makeToken(.l_paren,   start, loc),
            ')' => self.makeToken(.r_paren,   start, loc),
            '[' => self.makeToken(.l_bracket, start, loc),
            ']' => self.makeToken(.r_bracket, start, loc),
            ',' => self.makeToken(.comma,     start, loc),
            ';' => self.makeToken(.semicolon, start, loc),

            // ── Unknown ────────────────────────────────────────────────────
            else => self.makeToken(.invalid, start, loc),
        };
    }

    /// Collect every token (including the terminal `.eof`) into a
    /// heap-allocated slice.  The caller owns the returned memory and must
    /// free it via `allocator.free(slice)`.
    pub fn collectAlloc(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var list: std.ArrayListUnmanaged(Token) = .{};
        errdefer list.deinit(allocator);
        while (true) {
            const tok = self.next();
            try list.append(allocator, tok);
            if (tok.kind == .eof) break;
        }
        return list.toOwnedSlice(allocator);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════════════════════

test "eof on empty source" {
    var lex = Lexer.init("");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.eof, tok.kind);
}

test "eof is idempotent" {
    var lex = Lexer.init("");
    _ = lex.next();
    const tok = lex.next(); // second call must also be eof
    try std.testing.expectEqual(TokenKind.eof, tok.kind);
}

test "line comment" {
    var lex = Lexer.init("# this is a comment");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.comment, tok.kind);
    try std.testing.expectEqualStrings("# this is a comment", tok.lexeme);
}

test "comment stops at newline" {
    var lex = Lexer.init("# comment\nx");
    _ = lex.next(); // comment
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.ident, tok.kind);
    try std.testing.expectEqualStrings("x", tok.lexeme);
}

test "integer literal" {
    var lex = Lexer.init("42");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.int_lit, tok.kind);
    try std.testing.expectEqualStrings("42", tok.lexeme);
}

test "float literal" {
    var lex = Lexer.init("3.145");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.float_lit, tok.kind);
    try std.testing.expectEqualStrings("3.145", tok.lexeme);
}

test "int followed by range is not float" {
    // '0..' must produce int_lit then range_ex, NOT float_lit
    var lex = Lexer.init("0..");
    try std.testing.expectEqual(TokenKind.int_lit,  lex.next().kind);
    try std.testing.expectEqual(TokenKind.range_ex, lex.next().kind);
}

test "string literal" {
    var lex = Lexer.init("\"hello world\"");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.string_lit, tok.kind);
    try std.testing.expectEqualStrings("\"hello world\"", tok.lexeme);
}

test "string with escape" {
    var lex = Lexer.init("\"hello\\nworld\"");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.string_lit, tok.kind);
}

test "char literal" {
    var lex = Lexer.init("'B'");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.char_lit, tok.kind);
    try std.testing.expectEqualStrings("'B'", tok.lexeme);
}

test "identifier" {
    var lex = Lexer.init("my_var");
    const tok = lex.next();
    try std.testing.expectEqual(TokenKind.ident, tok.kind);
    try std.testing.expectEqualStrings("my_var", tok.lexeme);
}

test "underscore is a valid identifier" {
    var lex = Lexer.init("_");
    try std.testing.expectEqual(TokenKind.ident, lex.next().kind);
}

test "keywords" {
    const Case = struct { src: []const u8, kind: TokenKind };
    const cases = [_]Case{
        .{ .src = "fn",     .kind = .kw_fn     },
        .{ .src = "fun",    .kind = .kw_fun    },
        .{ .src = "ret",    .kind = .kw_ret    },
        .{ .src = "if",     .kind = .kw_if     },
        .{ .src = "else",   .kind = .kw_else   },
        .{ .src = "struct", .kind = .kw_struct },
        .{ .src = "cls",    .kind = .kw_cls    },
        .{ .src = "dat",    .kind = .kw_dat    },
        .{ .src = "pub",    .kind = .kw_pub    },
        .{ .src = "ovrd",   .kind = .kw_ovrd   },
        .{ .src = "for",    .kind = .kw_for    },
        .{ .src = "loop",   .kind = .kw_loop   },
        .{ .src = "while",  .kind = .kw_while  },
        .{ .src = "try",    .kind = .kw_try    },
        .{ .src = "catch",  .kind = .kw_catch  },
        .{ .src = "self",   .kind = .kw_self   },
        .{ .src = "any",    .kind = .kw_any    },
        .{ .src = "elif",   .kind = .kw_elif   },
        .{ .src = "NULL",   .kind = .kw_null   },
    };
    for (cases) |tc| {
        var lex = Lexer.init(tc.src);
        try std.testing.expectEqual(tc.kind, lex.next().kind);
    }
}

test "keyword prefix is not a keyword" {
    // "fns" starts with "fn" but must lex as ident, not kw_fn
    var lex = Lexer.init("fns");
    try std.testing.expectEqual(TokenKind.ident, lex.next().kind);
}

test "builtin tokens" {
    const cases = [_][]const u8{ "@main", "@pl", "@import", "@getArgs", "@init", "@deinit" };
    for (cases) |src| {
        var lex = Lexer.init(src);
        const tok = lex.next();
        try std.testing.expectEqual(TokenKind.builtin, tok.kind);
        try std.testing.expectEqualStrings(src, tok.lexeme);
    }
}

test "declaration operators" {
    // :=  mutable implicit
    { var lex = Lexer.init(":="); try std.testing.expectEqual(TokenKind.decl_mut,   lex.next().kind); }
    // ::  immutable implicit
    { var lex = Lexer.init("::"); try std.testing.expectEqual(TokenKind.decl_immut, lex.next().kind); }
    // :   plain colon (explicit-type annotation)
    { var lex = Lexer.init(":");  try std.testing.expectEqual(TokenKind.colon,      lex.next().kind); }
}

test "range operators" {
    { var lex = Lexer.init("..");  try std.testing.expectEqual(TokenKind.range_ex, lex.next().kind); }
    { var lex = Lexer.init("..="); try std.testing.expectEqual(TokenKind.range_in, lex.next().kind); }
}

test "arrow operators" {
    { var lex = Lexer.init("->"); try std.testing.expectEqual(TokenKind.arrow,     lex.next().kind); }
    { var lex = Lexer.init("=>"); try std.testing.expectEqual(TokenKind.fat_arrow, lex.next().kind); }
}

test "compound assignment operators" {
    const Case = struct { src: []const u8, kind: TokenKind };
    const cases = [_]Case{
        .{ .src = "+=", .kind = .plus_eq  },
        .{ .src = "-=", .kind = .minus_eq },
        .{ .src = "*=", .kind = .star_eq  },
        .{ .src = "/=", .kind = .slash_eq },
    };
    for (cases) |tc| {
        var lex = Lexer.init(tc.src);
        try std.testing.expectEqual(tc.kind, lex.next().kind);
    }
}

test "comparison operators" {
    const Case = struct { src: []const u8, kind: TokenKind };
    const cases = [_]Case{
        .{ .src = "==", .kind = .eq_eq   },
        .{ .src = "!=", .kind = .bang_eq },
        .{ .src = "<=", .kind = .lt_eq   },
        .{ .src = ">=", .kind = .gt_eq   },
        .{ .src = "<<", .kind = .lshift    },
        .{ .src = ">>", .kind = .rshift    },
        .{ .src = "&&", .kind = .amp_amp   },
        .{ .src = "||", .kind = .pipe_pipe },
    };
    for (cases) |tc| {
        var lex = Lexer.init(tc.src);
        try std.testing.expectEqual(tc.kind, lex.next().kind);
    }
}

test "source location: first token" {
    var lex = Lexer.init("foo");
    const tok = lex.next();
    try std.testing.expectEqual(@as(u32, 1), tok.loc.line);
    try std.testing.expectEqual(@as(u32, 1), tok.loc.col);
}

test "source location: second line" {
    // "x := 1\ny := 2"
    const src =
        \\x := 1
        \\y := 2
    ;
    var lex = Lexer.init(src);
    _ = lex.next(); // x    line 1
    _ = lex.next(); // :=
    _ = lex.next(); // 1
    const y = lex.next(); // y    line 2 col 1
    try std.testing.expectEqual(@as(u32, 2), y.loc.line);
    try std.testing.expectEqual(@as(u32, 1), y.loc.col);
}

test "hello world snippet" {
    // @main {\n    @pl("Hello World")\n}
    const src =
        \\@main {
        \\    @pl("Hello World")
        \\}
    ;
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .builtin,    // @main
        .l_brace,    // {
        .builtin,    // @pl
        .l_paren,    // (
        .string_lit, // "Hello World"
        .r_paren,    // )
        .r_brace,    // }
        .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "function declaration snippet" {
    // fn add (a, b) { ret a+b }
    const src = "fn add (a, b) { ret a+b }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_fn, .ident, .l_paren, .ident, .comma, .ident, .r_paren,
        .l_brace, .kw_ret, .ident, .plus, .ident, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "variable declarations" {
    // x := 32
    // y : str = "hello"
    // PI :: 3.145
    const src =
        \\x := 32
        \\y : str = "hello"
        \\PI :: 3.145
    ;
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .ident, .decl_mut, .int_lit,           // x := 32
        .ident, .colon, .ident, .eq, .string_lit, // y : str = "hello"
        .ident, .decl_immut, .float_lit,        // PI :: 3.145
        .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "for loop snippet" {
    // for e, i => args, 0.. {
    const src = "for e, i => args, 0.. {";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_for, .ident, .comma, .ident, .fat_arrow,
        .ident, .comma, .int_lit, .range_ex, .l_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "error return type snippet" {
    // fn Foo(arg1, arg2: any) -> any!
    const src = "fn Foo(arg1, arg2: any) -> any!";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_fn, .ident, .l_paren,
        .ident, .comma, .ident, .colon, .kw_any,
        .r_paren, .arrow, .kw_any, .bang, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "collectAlloc" {
    var lex = Lexer.init("x := 1");
    const tokens = try lex.collectAlloc(std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    // x  :=  1  eof  →  4 tokens
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.ident,    tokens[0].kind);
    try std.testing.expectEqual(TokenKind.decl_mut, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.int_lit,  tokens[2].kind);
    try std.testing.expectEqual(TokenKind.eof,      tokens[3].kind);
}

test "invalid character" {
    var lex = Lexer.init("$");
    try std.testing.expectEqual(TokenKind.invalid, lex.next().kind);
}

// ── Arrays (Arrays.zcy) ───────────────────────────────────────────────────────

test "mutable array declaration" {
    // int_arr: []i32 = {1,2,3}
    const src = "int_arr: []i32 = {1,2,3}";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .ident, .colon, .l_bracket, .r_bracket, .ident, // int_arr: []i32
        .eq, .l_brace,                                   // = {
        .int_lit, .comma, .int_lit, .comma, .int_lit,    // 1,2,3
        .r_brace, .eof,                                  // }
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "immutable array declaration" {
    // names :[]str: {"John", "Joe"}  — colon-type-colon immutable form
    const src = "names :[]str: {\"John\", \"Joe\"}";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .ident, .colon, .l_bracket, .r_bracket, .ident, .colon, // names :[]str:
        .l_brace, .string_lit, .comma, .string_lit, .r_brace,   // {"John","Joe"}
        .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Classes (Cls.zcy) ─────────────────────────────────────────────────────────

test "class declaration snippet" {
    // cls Person : pub Human : Talk, Walk {
    const src = "cls Person : pub Human : Talk, Walk {";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_cls, .ident, .colon, .kw_pub, .ident,  // cls Person : pub Human
        .colon, .ident, .comma, .ident,             // : Talk, Walk
        .l_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "class implements shorthand" {
    // cls Window :: Keyboard {}
    const src = "cls Window :: Keyboard {}";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_cls, .ident, .decl_immut, .ident, .l_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "override method snippet" {
    // ovrd fun walking() {}
    const src = "ovrd fun walking() {}";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_ovrd, .kw_fun, .ident, .l_paren, .r_paren, .l_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Data structs (Dats.zcy) ───────────────────────────────────────────────────

test "dat declaration snippet" {
    // dat Person { name: str, age: i32, }
    const src = "dat Person { name: str, age: i32, }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_dat, .ident, .l_brace,
        .ident, .colon, .ident, .comma,
        .ident, .colon, .ident, .comma,
        .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Error handling (Err.zcy) ──────────────────────────────────────────────────

test "catch error handling snippet" {
    // Foo() catch |e| { _ => {} }
    const src = "Foo() catch |e| { _ => {} }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .ident, .l_paren, .r_paren,
        .kw_catch, .pipe, .ident, .pipe,
        .l_brace, .ident, .fat_arrow, .l_brace, .r_brace,
        .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "try error propagation" {
    // try Foo()
    const src = "try Foo()";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_try, .ident, .l_paren, .r_paren, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Imports (Imports.zcy) ─────────────────────────────────────────────────────

test "import snippet" {
    // @import( x = my_file, y = my_file2.my_struct, )
    const src = "@import(\n    x = my_file,\n    y = my_file2.my_struct,\n)";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .builtin, .l_paren,
        .ident, .eq, .ident, .comma,
        .ident, .eq, .ident, .dot, .ident, .comma,
        .r_paren, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Loops (Loops.zcy) ────────────────────────────────────────────────────────

test "traditional loop snippet" {
    // loop i := 0, i < 10, i+=1 { }
    const src = "loop i := 0, i < 10, i+=1 { }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_loop, .ident, .decl_mut, .int_lit, .comma,
        .ident, .lt, .int_lit, .comma,
        .ident, .plus_eq, .int_lit,
        .l_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "while loop snippet" {
    // while some_condition { }
    const src = "while some_condition { }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_while, .ident, .l_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "while-do snippet" {
    // while cond => my_func() { }
    const src = "while cond => my_func() { }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_while, .ident, .fat_arrow, .ident, .l_paren, .r_paren,
        .l_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── HelloWorld extras (HelloWorld.zcy) ───────────────────────────────────────

test "cout stream operator" {
    // @cout << "Hello World\n"
    const src = "@cout << \"Hello World\\n\"";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .builtin, .lshift, .string_lit, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "cout chained with endl" {
    // @cout << "Hello" << @endl
    const src = "@cout << \"Hello\" << @endl";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .builtin, .lshift, .string_lit, .lshift, .builtin, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

test "pf format string" {
    // @pf("{e} ")
    const src = "@pf(\"{e} \")";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .builtin, .l_paren, .string_lit, .r_paren, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Struct (Structs.zcy) ─────────────────────────────────────────────────────

test "struct with self and pub fn" {
    // struct Foo { bar: str, pub fn thing() { self.bar = "x" } }
    const src = "struct Foo { bar: str, pub fn thing() { self.bar = \"x\" } }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .kw_struct, .ident, .l_brace,
        .ident, .colon, .ident, .comma,
        .kw_pub, .kw_fn, .ident, .l_paren, .r_paren,
        .l_brace, .kw_self, .dot, .ident, .eq, .string_lit,
        .r_brace, .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}

// ── Args (Args.zcy) ──────────────────────────────────────────────────────────

test "getArgs and for-print snippet" {
    // args := @getArgs()  for e => args { @pf("{e} ") }
    const src = "args := @getArgs()\nfor e => args { @pf(\"{e} \") }";
    var lex = Lexer.init(src);
    const expected = [_]TokenKind{
        .ident, .decl_mut, .builtin, .l_paren, .r_paren,    // args := @getArgs()
        .kw_for, .ident, .fat_arrow, .ident,                 // for e => args
        .l_brace, .builtin, .l_paren, .string_lit, .r_paren, // { @pf("...") }
        .r_brace, .eof,
    };
    for (expected) |kind| {
        try std.testing.expectEqual(kind, lex.next().kind);
    }
}
