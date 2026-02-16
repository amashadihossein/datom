# Phase 3: Git Operations

**Status**: 🟢 In Progress  
**Started**: 2026-02-10  
**Target**: Internal git utility functions for commit, push, branch, and author  
**Estimated Effort**: 3-4 days

---

## Objective

Build and test the internal git utility functions. These wrap `git2r` to provide commit, push, branch detection, and author retrieval — the git side of the "git commits metadata, S3 stores data" architecture.

---

## Design Decisions

### git2r stays in Suggests

Data readers need only S3 (no git). Git operations are data-developer-only. Keep `git2r` in Suggests and check availability at runtime:

```r
.tbit_check_git2r <- function() {
  if (!requireNamespace("git2r", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg git2r} is required for git operations.",
      "i" = "Install with {.code install.packages(\"git2r\")}"
    ))
  }
}
```

### Error wrapping pattern

Consistent with Phase 2 S3 utilities — wrap git2r errors with tbit context:

```r
tryCatch(
  git2r::commit(...),
  error = function(e) cli::cli_abort("Failed to commit: {e$message}")
)
```

### Testing approach

- **Unit tests**: Create temporary git repos via `git2r::init()` in test fixtures
- **No mocking preferred**: git2r operations are fast and local — real repos in `withr::local_tempdir()`
- **Edge cases**: Detached HEAD, no remote, nothing to commit, merge conflicts

---

## Scope

### In Scope

| File | Functions | Description |
|------|-----------|-------------|
| `R/utils-git.R` | `.tbit_check_git2r()` | Runtime check for git2r availability |
| | `.tbit_git_author(path)` | Get name + email from git config |
| | `.tbit_git_branch(path)` | Get current branch name |
| | `.tbit_git_commit(path, files, message)` | Stage files + commit, return SHA |
| | `.tbit_git_push(path)` | Pull-before-push with conflict detection |

### Out of Scope

- Connection class (`tbit_conn`) — Phase 4
- S3 operations — Phase 2 (done)
- Merge conflict resolution (manual per spec)
- Remote setup (assumed pre-configured)

---

## Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | Git info (read-only) | `.tbit_check_git2r()`, `.tbit_git_author()`, `.tbit_git_branch()` | ✅ Done |
| 2 | Git commit | `.tbit_git_commit()` | ✅ Done |
| 3 | Git push | `.tbit_git_push()` | ✅ Done |

---

## Current Chunk

All chunks complete. Phase ready for `devtools::check()` and finalization.

---

## Current State

All git utility functions implemented and tested (47 tests, 272 total suite).

### Completed Chunks

1. **Git info (read-only)** — `.tbit_check_git2r()`, `.tbit_git_author()`, `.tbit_git_branch()`
2. **Git commit** — `.tbit_git_commit()` — stage + commit, returns SHA
3. **Git push** — `.tbit_git_push()` — fetch + merge + push with conflict detection

### Decisions Made

- git2r stays in Suggests (data readers don't need it)
- Real temp repos for testing (no mocking git2r)
- Consistent error wrapping with cli::cli_abort
- `git2r::merge()` requires `upstream_ref$name` (string), not the branch object
- Push uses first remote found (typically "origin")
- Fetch + merge pattern (not pull) for explicit control
- If no upstream branch yet, skips merge and just pushes

### Blockers

_None_

### Deferred Items

| Item | Why Deferred | Notes |
|------|--------------|-------|
| _None_ | | |

---

## Session Log

| Date | Summary | Next Steps |
|------|---------|------------|
| 2026-02-10 | Phase 3 created, chunk queue defined | Implement Chunk 1 |
| 2026-02-14 | Chunks 1-3 implemented + tested (47 tests, 272 total) | `devtools::check()`, finalize phase |

---

## Completion Checklist

- [ ] All acceptance criteria met
- [ ] All tests passing
- [ ] `devtools::check()` clean
- [ ] All chunks committed
- [ ] Final push to remote
- [ ] Any API decisions documented in `tbit_specification.md`
- [ ] Deferred items moved to `dev/README.md` backlog
- [ ] Phase doc deleted
- [ ] README.md updated
