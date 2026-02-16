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

## Don'ts

- No nested if-else chains
- No for loops (use purrr)
- No credentials in code
- No `access.json` (renamed to `routing.json`)
