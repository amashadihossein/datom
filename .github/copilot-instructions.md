# Copilot Instructions for tbit

## Quick Start for New Sessions

1. **Check active work**: Open `dev/README.md` → see "Active Phases" table
2. **Load context**: Open the active phase file (e.g., `dev/phase_1_core_utilities.md`)
3. **Read "Current State"**: Understand where we left off
4. **Continue work**: Update the phase doc as you go

## Project Overview

tbit is an R package for version-controlled data management. It stores tabular data in S3 with git-tracked metadata, enabling reproducibility for clinical/scientific workflows.

**Core concept**: Tables abstracted as code in git; actual data in cloud storage (parquet format).

## Documentation Hierarchy

```
.github/copilot-instructions.md  ← You are here (coding conventions, quick start)
         ↓
dev/README.md                    ← Development hub (navigation, phase status)
         ↓
dev/tbit_specification.md        ← Design spec (authoritative reference)
dev/daapr_architecture.md        ← Ecosystem context
         ↓
dev/phase_{n}_{name}.md          ← Active work (temporary, detailed)
```

**Navigation rules**:
- Start here for conventions → go to `dev/README.md` for current work
- Phase docs are temporary: created → worked → learnings migrate to spec → deleted
- Always update phase docs as you work (progress, decisions, blockers)

## Architecture Context

tbit is the foundational layer for the daapr ecosystem:
- **tbit** → versioned table storage (this package)
- **dpbuild** → data product construction
- **dpdeploy** → deployment orchestration  
- **dpi** → data product access

See `dev/tbit_specification.md` for full spec and `dev/daapr_architecture.md` for ecosystem context.

## Coding Style

### Principles
- **Flat over nested**: Early returns, guard clauses
- **Tidyverse idioms**: pipes, purrr, dplyr
- **Small functions**: Single responsibility, composable
- **Clear naming**: `tbit_` prefix for exports, `.tbit_` for internals

### Patterns to Follow
```r
# Early validation, flat flow
tbit_write <- function(conn, data, name, metadata = NULL) {
  if (!inherits(conn, "tbit_conn")) stop("Invalid connection")

  if (!is.data.frame(data)) stop("data must be a data frame
")
  
  sha <- .tbit_compute_sha(data)
  # ... flat logic continues
}

# Functional over loops
purrr::map(tables, .tbit_sync_one)

# Glue for strings
cli::cli_alert_success("Wrote {name} ({sha})")
```

### Packages to Use
- `fs::` for filesystem
- `glue::glue()` for strings
- `cli::` for user messages
- `purrr::` for iteration
- `arrow::` for parquet I/O
- `digest::` for SHA computation
- `yaml::` for config files

### Naming Conventions
| Type | Convention | Example |
|------|------------|---------|
| Exported functions | `tbit_verb` | `tbit_read`, `tbit_write`, `tbit_init` |
| Internal functions | `.tbit_verb` | `.tbit_compute_sha`, `.tbit_sync_s3` |
| S3 methods | `verb.class` | `print.tbit_conn` |
| Config files | snake_case.yaml/json | `project.yaml`, `routing.json` |

## Key Files

- `dev/tbit_specification.md` — Full technical specification
- `dev/daapr_architecture.md` — Ecosystem context
- `R/` — Source code (organized by domain)
- `tests/testthat/` — Tests mirror R/ structure

## User Types

1. **Data developers**: git + S3 access, create/update data
2. **Data readers**: S3 only, consume versioned data

Auto-detected via `GITHUB_PAT` presence.

## Gotchas

- **cli pluralization**: `{?s}` requires a quantity reference immediately before it (e.g., `{length(x)} variable{?s}`). Without the quantity, cli throws a confusing error.
- **git2r::default_signature()**: Fails on freshly `git2r::init()`'d repos that lack local config. Always call `git2r::config(repo, user.name = ..., user.email = ...)` after init.
- **git2r::merge()**: Expects a string (branch name), not a branch object. Use `upstream_ref$name`.
- **cli dot-literals**: In cli >= 3.4.0, `{.something}` inside `cli_abort()` is interpreted as a cli style, not an expression. Wrap internal function calls starting with `.` in parentheses: `{(.tbit_build_s3_key(...))}`.  
- **`.tbit_git_commit()` is idempotent**: Returns HEAD SHA (instead of erroring) when staged files are unchanged. This is by design — enables safe re-runs after partial failures in the local → git → S3 pipeline.
- **metadata SHA uses JSON canonical form**: `.tbit_compute_metadata_sha()` hashes `jsonlite::toJSON()` output with `serialize = FALSE`, not the R object. This is critical — R's `serialize()` is type-sensitive (`10L` ≠ `10`), so metadata round-tripped through JSON would produce a different SHA. Always test SHA stability with a JSON round-trip.
- **metadata SHA excludes volatile fields**: `created_at` and `tbit_version` are stripped before hashing. Adding new metadata fields that should NOT affect versioning must be added to the `volatile` vector in `.tbit_compute_metadata_sha()`.
- **version_history dedup guard**: `.tbit_write_metadata_local()` skips appending when the latest entry has the same version SHA. This prevents duplicates but means the guard relies on metadata_sha correctness.

## Don'ts

- No nested if-else chains
- No for loops (use purrr)
- No credentials in code
- No `access.json` (renamed to `routing.json`)

## Operational Discipline

These patterns are non-negotiable for every session:

1. **Read before writing**: Always read the relevant source functions AND their callers before editing. Trace the full call chain — don't edit based on the phase doc description alone.
2. **Full test suite before every commit**: Run `devtools::test()` (unfiltered) and verify the total count. Report the count in every commit message. If the count drops, something was lost.
3. **One logical change per commit**: Don't bundle unrelated fixes. Squash related incremental commits before pushing if they tell a cleaner story as one.
4. **Simplicity over cleverness**: If a change doesn't alter behavior, don't add it. When in doubt, do less. Actively resist complexity that exists only for marginally better UX or edge-case coverage.
5. **E2E after phase completion**: Unit tests are necessary but not sufficient. Before marking a phase complete, run real end-to-end workflows via `dev/dev-sandbox.R` to catch integration bugs.
6. **Fix bugs immediately**: When E2E reveals a bug, fix it before moving to the next phase. Don't defer bugs that affect correctness.
