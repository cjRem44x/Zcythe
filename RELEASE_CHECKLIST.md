# Pre-Release Checklist

**⚠️ IMPORTANT**: This checklist is for **when you're ready to make your first official release**. The project is currently in prototype phase with no versions.

Use this checklist when you're ready to tag version `0.1.0` or similar.

---

## Before First Public Release

### Code Quality
- [ ] All Phase 1 tests passing
- [ ] No known critical bugs
- [ ] Code is reasonably documented
- [ ] No debug/test code in main branches

### Documentation
- [ ] README.md is accurate and complete
- [ ] CONTRIBUTING.md has clear guidelines
- [ ] All major features documented
- [ ] Examples are working and tested
- [ ] Installation instructions verified

### Repository Cleanup
- [ ] Update .gitignore to exclude all build artifacts
- [ ] Remove any personal notes or TODO files
- [ ] Clean up commit history if needed
- [ ] Remove any credentials or sensitive data

### GitHub Setup
- [ ] Repository is public
- [ ] Repository description is clear
- [ ] Topics/tags added (zig, programming-language, compiler, assembly)
- [ ] GitHub Pages enabled (if using for docs)
- [ ] Issues enabled
- [ ] Discussions enabled (optional)

### Legal
- [ ] LICENSE file present and correct
- [ ] Copyright year is current
- [ ] Attribution for any third-party code
- [ ] No license conflicts with dependencies

### Version Preparation
- [ ] Decide on version number (suggest: `0.1.0`)
- [ ] Update CHANGELOG.md with version and date
- [ ] Create git tag for version
- [ ] Write release notes

---

## For Each Future Release

### Pre-Release
- [ ] All tests passing
- [ ] Update version number in relevant files
- [ ] Update CHANGELOG.md
- [ ] Review and close related issues
- [ ] Create release branch if needed

### Documentation
- [ ] Update README with new features
- [ ] Update INSTRUCTION_SET.md status
- [ ] Add examples for new features
- [ ] Update IMPLEMENTATION_STATUS.md

### Testing
- [ ] Run full test suite
- [ ] Test on multiple platforms (Windows, macOS, Linux)
- [ ] Verify examples work
- [ ] Check for memory leaks (if applicable)

### Release
- [ ] Create git tag (`git tag -a v0.X.Y -m "Version 0.X.Y"`)
- [ ] Push tag (`git push origin v0.X.Y`)
- [ ] Create GitHub release
- [ ] Attach binaries (optional for early versions)
- [ ] Write release notes highlighting changes

### Post-Release
- [ ] Announce on relevant channels (if any)
- [ ] Update README badge (if using version badge)
- [ ] Close milestone (if using)
- [ ] Create next milestone

---

## GitHub Release Notes Template

```markdown
# Zcythe v0.X.Y

**⚠️ Early Development**: This is an early release. Expect bugs and breaking changes.

## What's New

- Feature 1
- Feature 2
- Feature 3

## Breaking Changes

- Change 1 (how to migrate)
- Change 2

## Bug Fixes

- Fix 1
- Fix 2

## Documentation

- Doc update 1
- Doc update 2

## Contributors

Thanks to @contributor1, @contributor2 for their contributions!

## Installation

```bash
git clone https://github.com/yourusername/Zcythe.git
cd Zcythe/src/main/zig
zig build-exe test_asm_phase1.zig
```

## Known Issues

- Issue 1 (#issue_number)
- Issue 2

## What's Next

See the [Roadmap](README.md#roadmap) for upcoming features.

---

**Full Changelog**: https://github.com/yourusername/Zcythe/compare/v0.X.Y...v0.X.Z
```

---

## Versioning Guidelines

Following [Semantic Versioning](https://semver.org/):

- **0.x.y** - Pre-1.0 development (breaking changes allowed in minor versions)
- **x.0.0** - Major version (breaking changes)
- **x.y.0** - Minor version (new features, backward compatible)
- **x.y.z** - Patch version (bug fixes)

### First Version Suggestion

- **v0.1.0** - First public prototype
  - Phase 1 complete
  - Basic VM working
  - Documentation in place

### Future Milestones

- **v0.2.0** - Control flow complete (Phase 2)
- **v0.3.0** - Functions complete (Phase 3)
- **v0.5.0** - Parser/assembler working
- **v0.9.0** - Zcythe compiler MVP
- **v1.0.0** - First stable release

---

## Current Status

**Not ready for release yet** - Still in prototype phase.

**What needs to happen before v0.1.0**:
1. Decision: Is Phase 1 sufficient for first release?
2. Clean up any placeholder code
3. Verify all documentation is accurate
4. Test on multiple platforms
5. Write release notes
6. Tag and publish

**Estimated timeline**: When you feel it's ready! No rush.
