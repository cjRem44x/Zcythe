# TODO

## Classes (Beta → Stable)

- [ ] Compile-time interface enforcement — verify all interface methods are implemented
- [ ] Method overloading support (`fn name` with different signatures)
- [ ] Proper virtual dispatch for `ovrd fun` across inheritance chains
- [ ] Static class members (`pub val NAME :: value` inside `cls`)
- [ ] Class generics / comptime type parameters
- [ ] `@init` parameter support (`@init(args) { ... }`)

## Language

- [ ] Generics / comptime type parameters for top-level `fn` and `dat`
- [ ] Multi-return values (tuple returns)
- [ ] Destructuring assignment (`a, b := some_tuple`)
- [ ] Enum methods (`enum X { ... fn name() {} }`)
- [ ] Pattern matching on `dat` / `cls` in `switch`
- [ ] String interpolation via `@pf` inside expressions (not just statements)
- [ ] `@comptime` blocks for compile-time evaluation

## Standard Library

- [ ] `@str::` namespace expansion (`split`, `trim`, `contains`, `replace`, `starts_with`, `ends_with`)
- [ ] `@map(K, V)` — hash map builtin
- [ ] `@set(T)` — hash set builtin
- [ ] `@fs::copy(src, dst)` — copy file
- [ ] `@fs::read_all(path)` — shorthand for open + rall + close
- [ ] `@fs::write_all(path, data)` — shorthand for open + w + close
- [ ] `@json::` namespace — basic JSON encode/decode
- [ ] `@net::` namespace — HTTP client (`@net::get`, `@net::post`)

## Tooling

- [ ] `zcy fmt` — auto-formatter for `.zcy` source files
- [ ] `zcy check` — type-check only (no emit), fast feedback loop
- [ ] `zcy doc` — extract doc-comments and emit HTML/Markdown docs
- [ ] LSP server for editor integration
- [ ] Better compiler error messages with source location and suggestions

## Packages

- [ ] `zcy add <owner/repo>` — support arbitrary GitHub packages beyond raylib
- [ ] Lock file (`zcy.lock`) for reproducible builds
- [ ] `zcy update` — update all pinned packages
- [ ] Private/local package path support

## @xi:: Graphics

- [ ] `win.mouse { click/move/scroll => {} }` — full mouse event block
- [ ] `win.draw_line`, `win.draw_ellipse` — additional primitives
- [ ] Sprite sheet / texture atlas support
- [ ] `@xi::sound` — basic audio playback (SDL_mixer)
- [ ] Multi-window support

## Fixes / Polish

- [ ] Improve `@list` to support slicing and iteration with index (`for i, e => list {}`)
- [ ] `@heap` block refinement — cleaner allocation lifecycle
- [ ] Audit all error names in `ZcyErrs.md` against current Zig error set
- [ ] `zcy sac` — support multi-file standalone compile with shared modules
