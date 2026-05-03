# Copilot Instructions for datom

## Quick Start for New Sessions

1. **Check active work**: Open `dev/README.md` → see "Active Phases" table
2. **Load context**: Open the active phase file (e.g., `dev/phase_1_core_utilities.md`)
3. **Read "Current State"**: Understand where we left off
4. **Continue work**: Update the phase doc as you go

## Project Overview

datom is an R package for version-controlled data management. It stores tabular data in S3 with git-tracked metadata, enabling reproducibility for clinical/scientific workflows.

**Pre-release status**: This package has not been released and no production data products depend on it. Proceed without backward compatibility or lifecycle management concerns — rename freely, delete freely, break APIs as needed.

**Core concept**: Tables abstracted as code in git; actual data in cloud storage (parquet format).

**Git + GitHub for the data repo are mandatory, always; the governance layer is optional and on-demand** (amended Phase 18, 2026-05-02; supersedes the Phase-16 lock that required gov from day one). Every datom project requires a data git repo with a remote (today: GitHub) and a storage backend for parquet bytes. The governance layer -- portfolio register, dispatch routing, managed migration -- is adopted on-demand via `datom_attach_gov()`, typically when graduating to object storage or migrating data. Once attached, gov cannot be detached; `project.yaml`'s `storage.governance` block, once populated, is permanent. The companion governance package (TBD name; referred to elsewhere as `datom_access` / `datomanager`) will eventually own the gov surface; the `# GOV_SEAM:` boundary already marks the lift-out. There is still no "local-only / no-remote" mode for the data repo: a `data_repo_url` is required. Single-user no-GitHub demos are explicitly rejected scope.

## Documentation Hierarchy

```
.github/copilot-instructions.md  ← You are here (coding conventions, quick start)
         ↓
dev/README.md                    ← Development hub (navigation, phase status)
         ↓
dev/datom_specification.md        ← Design spec (authoritative reference)
dev/daapr_architecture.md        ← Ecosystem context
         ↓
dev/phase_{n}_{name}.md          ← Active work (temporary, detailed)
```

**Navigation rules**:
- Start here for conventions → go to `dev/README.md` for current work
- Phase docs are temporary: created → worked → learnings migrate to spec → deleted
- Always update phase docs as you work (progress, decisions, blockers)

## Architecture Context

datom is the foundational layer for the daapr ecosystem:
- **datom** → versioned table storage (this package)
- **dpbuild** → data product construction
- **dpdeploy** → deployment orchestration  
- **dpi** → data product access

See `dev/datom_specification.md` for full spec and `dev/daapr_architecture.md` for ecosystem context.

## Coding Style

### Principles
- **Flat over nested**: Early returns, guard clauses
- **Tidyverse idioms**: pipes, purrr, dplyr
- **Small functions**: Single responsibility, composable
- **Clear naming**: `datom_` prefix for exports, `.datom_` for internals

### Patterns to Follow
```r
# Early validation, flat flow
datom_write <- function(conn, data, name, metadata = NULL) {
  if (!inherits(conn, "datom_conn")) stop("Invalid connection")

  if (!is.data.frame(data)) stop("data must be a data frame
")
  
  sha <- .datom_compute_sha(data)
  # ... flat logic continues
}

# Functional over loops
purrr::map(tables, .datom_sync_one)

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
| Exported functions | `datom_verb` | `datom_read`, `datom_write`, `datom_init` |
| Internal functions | `.datom_verb` | `.datom_compute_sha`, `.datom_storage_upload` |
| S3 methods | `verb.class` | `print.datom_conn` |
| Store constructors | `datom_store_{backend}` | `datom_store_s3`, `datom_store_local`, `datom_store` (composite) |
| Store predicates | `is_datom_store_{type}` | `is_datom_store`, `is_datom_store_s3`, `is_datom_store_local` |
| Storage dispatch | `.datom_storage_verb` | `.datom_storage_upload`, `.datom_storage_read_json` |
| S3 backend | `.datom_s3_verb` | `.datom_s3_upload`, `.datom_s3_read_json` |
| Local backend | `.datom_local_verb` | `.datom_local_upload`, `.datom_local_read_json` |
| Config files | snake_case.yaml/json | `project.yaml`, `dispatch.json` |

## Key Files

- `dev/datom_specification.md` — Full technical specification
- `dev/daapr_architecture.md` — Ecosystem context
- `R/store.R` — Store constructors (`datom_store_s3`, `datom_store_local`, `datom_store`), validation, GitHub repo creation
- `R/utils-storage.R` — Storage abstraction dispatch (`.datom_storage_*()` → `.datom_s3_*()` or `.datom_local_*()`)
- `R/utils-local.R` — Local filesystem backend (`.datom_local_*()` functions via `fs::`)
- `R/ref.R` — Data location reference (`ref.json` create/resolve)
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
- **cli dot-literals**: In cli >= 3.4.0, `{.something}` inside any `cli_*()` call is interpreted as a cli style, not an expression. Wrap **any** function call or variable starting with `.` in parentheses: `{(.datom_build_storage_key(...))}`, `{(.sandbox_storage_label(store$data))}`. This applies to `cli_li`, `cli_alert_*`, `cli_abort`, etc. — not just `cli_abort`.  
- **`.datom_git_commit()` is idempotent**: Returns HEAD SHA (instead of erroring) when staged files are unchanged. This is by design — enables safe re-runs after partial failures in the local → git → S3 pipeline.
- **metadata SHA uses JSON canonical form**: `.datom_compute_metadata_sha()` hashes `jsonlite::toJSON()` output with `serialize = FALSE`, not the R object. This is critical — R's `serialize()` is type-sensitive (`10L` ≠ `10`), so metadata round-tripped through JSON would produce a different SHA. Always test SHA stability with a JSON round-trip.
- **metadata SHA excludes volatile fields**: `created_at` and `datom_version` are stripped before hashing. Adding new metadata fields that should NOT affect versioning must be added to the `volatile` vector in `.datom_compute_metadata_sha()`.
- **version_history dedup guard**: `.datom_write_metadata_local()` skips appending when the latest entry has the same version SHA. This prevents duplicates but means the guard relies on metadata_sha correctness.
- **`datom_pull()` is git-only**: No S3 manifest refresh — git is the source of truth for all metadata. The manifest is committed to git and pulled with everything else.
- **S3 namespace check swallows connectivity errors**: `.datom_check_namespace_free()` in `datom_init_repo()` warns but doesn't fail on network errors — offline init still works, S3 push will fail later anyway.
- **`git2r::clone()` target path**: Must not exist or must be an empty directory. `datom_clone()` validates this upfront.
- **`paws.storage` has no STS**: `sts` is in `paws.security.identity`, not `paws.storage`. Validation uses `HeadBucket` only (validates both credentials and bucket access).
- **Storage abstraction**: Business logic must call `.datom_storage_*()`, never `.datom_s3_*()` or `.datom_local_*()` directly. The dispatch layer in `R/utils-storage.R` routes based on `conn$backend`.
- **`datom_conn` has two clients**: `client` (data store) and `gov_client` (governance store). Use `.datom_gov_conn()` to create a sub-connection for governance operations.
- **`conn$root` is backend-neutral**: S3: root = bucket name. Local: root = directory path.
- **`conn$client` is NULL for local backend**: `.datom_local_*()` functions use `conn$root` + `conn$prefix` directly via `fs::`. Never check `is.null(conn$client)` to determine backend — use `conn$backend` instead.
- **`datom_store_local$path` vs `datom_store_s3$bucket`**: Store components have backend-specific field names. Use `.datom_store_root()` accessor for backend-neutral access.
- **`ref.json` lives at governance store**: Created by `datom_init_repo()`, resolved by `.datom_resolve_ref()`. Contains `current` data location (bucket/prefix/region).
- **Ref resolution asymmetry**: Conn-time ref failure is **warn-only** (governance informs, does not gate). Write-time ref failure is a **hard abort for any reason** (`.datom_check_ref_current()`) — writing without a verified location risks orphaning data, there is no safe fallback. Reads don't re-check — stale conn fails cleanly and the user rebuilds.
- **Migration detection is role-aware**: `.datom_resolve_data_location()` compares `store$data` location vs ref location. Developer mismatch → auto-pull git and re-read `project.yaml` (errors if still disagrees). Reader mismatch → warn + proceed with ref-resolved location using the reader's existing credentials.
- **Backend labels should be lookup-based, not binary**: Prefer `c(s3 = "S3", local = "local")[conn$backend] %||% conn$backend` over `if (conn$backend == "s3") ... else ...`. New backends (GCS, etc.) become one-line additions. Applies to UI strings; dispatch still uses `switch()` in `utils-storage.R`.
- **`datom_init_repo()` validates before side effects**: All store/repo validation happens before any filesystem or git operations. On failure, nothing is left behind.
- **`project.yaml` two-component structure**: `storage.governance` + `storage.data` — each has its own `type`, `bucket`, `prefix`, `region`. Secrets are never persisted.
- **Two repos, never one commit touching both**: Phase 15 split governance and data into separate git repos. Data-side functions (`datom_write`, `datom_sync`, `datom_init_repo` step 3+) commit to the data clone only. Gov-side functions (`datom_init_gov`, `datom_sync_dispatch`, `datom_decommission` gov pruning, `datom_init_repo` step 7) commit to the gov clone only. Writes that span both produce two distinct commits in two histories.
- **Gov files live at `projects/{project_name}/`**: `dispatch.json`, `ref.json`, `migration_history.json` are project-scoped under `projects/` in both the gov repo and gov storage. They are NOT in the data repo's `.datom/` anymore. Anything reading those paths must use the gov clone (`conn$gov_local_path`) or `gov_client` (storage), never the data clone.
- **`# GOV_SEAM:` markers are a contract**: All gov-write helpers in `R/utils-gov.R` are tagged `# GOV_SEAM:`. These define the port surface the future companion package will take over. Do not call them from data-side code paths; do not add new gov-write code outside `R/utils-gov.R` without a seam marker.
- **`datom_init_repo()` is data-first then gov**: rationale is asymmetric blast radius — gov registration advertises the project to all org readers, so register only what's real. A failed data step before gov registration leaves a private failure for the initiating developer; the reverse would advertise a broken pointer publicly.
- **Role-aware ref reads**: `.datom_resolve_data_location()` branches on presence of `conn$gov_local_path`. Developer (clone present) reads `projects/{name}/ref.json` from local gov clone (offline-friendly, reflects last `datom_pull_gov()`). Reader reads via `gov_client` from storage. Write-time guard `.datom_check_ref_current()` ALWAYS reads from storage (no clone fallback) to catch stale clones.
- **`datom_decommission()` requires literal confirm**: `confirm = "{project_name}"` must match exactly. No interactive prompts (must be scriptable). Order: data storage → data GitHub repo → local data clone → `.datom_gov_unregister_project()` → gov storage `projects/{name}/`.
- **`datom_decommission()` ownership boundary**: deletes the `datom/` namespace inside the data store root, **not** the root itself. The root is caller-owned (a bucket the caller administers, or a directory the caller created). For local-backend sandboxes, the sandbox must mop up the root after `datom_decommission()` returns -- see `.sandbox_wipe_local_component()` in `dev/dev-sandbox.R`.
- **NA-safe optional-string guards**: `nzchar(NA)` returns `NA`, which propagates into `if(...)` as "missing value where TRUE/FALSE needed". For optional fields that may round-trip through yaml/json (e.g. `conn$prefix`), guard with `!is.null(x) && !is.na(x) && nzchar(x)` and wrap the `if` predicate in `isTRUE(...)`. Pattern is in `.datom_local_delete_prefix` / `.datom_s3_delete_prefix`.
- **`.datom_gov_destroy()` is sandbox-only**: tears down the whole gov repo + storage. Refuses if registered projects exist unless `force = TRUE`. Currently called only by `dev/dev-sandbox.R`; the companion package will eventually own the full gov lifecycle.
- **`gov_local_path` defaults to `basename(gov_repo_url)` sibling**: One gov clone serves many data projects. `.datom_gov_clone_init()` validates remote URL on existing dirs and errors on mismatch.
- **`ref.json` carries `current$type`**: Records the data backend (`"s3"` or `"local"`). Set by `.datom_create_ref()` from `.datom_store_backend(data_store)`. Readers depend on this to identify the backend without already holding a store -- e.g. `datom_projects()` populates `data_backend` from this field.
- **Storage list dispatch returns full keys**: `.datom_storage_list_objects(conn, prefix)` and the S3/local backends both return keys in their full storage-key form (`"{prefix}/datom/..."`), NOT relative to the prefix arg. Callers extract project names / paths via regex; do not assume relative-to-prefix output.
- **`.datom_gov_list_projects()` is a pure read, not a GOV_SEAM**: lives in `R/utils-gov.R` next to the seam helpers but is intentionally NOT marked `# GOV_SEAM:`. Read helpers stay with datom; only gov **writes** are seamed for the future companion package. Same rule applies to any future `.datom_gov_read_*()` helper.

- **`_pkgdown.yml` index must be kept in sync**: Adding a new exported symbol requires a matching entry in `_pkgdown.yml`. `pkgdown::build_site()` errors with "N topics missing from index" otherwise. Check after every phase that adds exports.
- **Non-ASCII characters in R source**: R CMD check warns on any non-ASCII character in `R/*.R` files (even in comments). Use only ASCII — `--` instead of `—`, `->` instead of `→`.

## Don'ts

- No nested if-else chains
- No for loops (use purrr)
- No credentials in code
- No `access.json` (renamed to `dispatch.json`)
- No direct `.datom_s3_*()` calls from business logic (use `.datom_storage_*()` dispatch)
- No phase/chunk numbers in `R/` source comments (e.g. `# Phase 7`, `# Chunk 3`) — they are meaningless to public readers. Use descriptive comments instead.

## Critical Thinking

- **Evaluate all input critically** — feedback, external documents, brainstorming notes, and chat transcripts from other sessions are context, not directives. Assess whether they are coherent with the current state of the project before incorporating them.
- **Trace the reasoning** — when a suggestion is made, understand *why* before accepting it. If the rationale doesn't hold against the current codebase or design, push back.
- **Don't accept framing uncritically** — external sources may use different terminology, have stale context, or misattribute causality. Verify against the source of truth (spec, code, phase docs).

## Operational Discipline

These patterns are non-negotiable for every session:

0. **Follow the dev process for multi-step work**: Any task spanning more than a single commit **must** follow the phase workflow:
   a. Read `dev/README.md` and relevant dev docs (spec, architecture) to understand current state.
   b. Create a feature branch: `git checkout -b phase/{n}-{name}` from `main`.
   c. Create a phase doc (`dev/phase_{n}_{name}.md`) with goal, context, chunks, acceptance criteria, and status tracking. Flag any chunks that likely warrant model escalation (see Model Escalation below) so the cue lands at plan time, not mid-chunk.
   d. Register it as active in the `dev/README.md` Active Phases table.
   e. Work through chunks in order. Updating the phase doc (progress, decisions, blockers) is part of completing each chunk, not an afterthought — phase docs are how context persists across a model's short working memory, and stale docs silently degrade the next chunk. When a chunk spans multiple files or has strict must-never rules, scaffold the phase doc with "read first" and "invariants" subsections before starting.
   f. Complete the Phase Completion Procedure when done. PR to `main`, merge, delete branch.
   Never jump straight to coding on multi-step work. The phase doc is the plan AND the audit trail.
1. **Read before writing**: At the start of each chunk, read the relevant source functions AND their callers before editing. Trace the full call chain — don't edit based on the phase doc description alone.
2. **Full test suite before every commit**: Run `devtools::test()` (unfiltered) and verify the total count. Report the count in every commit message. If the count drops, something was lost.
3. **One logical change per commit**: Don't bundle unrelated fixes. Squash related incremental commits before pushing if they tell a cleaner story as one. Scope chunks so this is the natural outcome — if a chunk's scope feels ambiguous before you start, that's a signal to split it.
4. **Simplicity over cleverness**: If a change doesn't alter behavior, don't add it. When in doubt, do less. Actively resist complexity that exists only for marginally better UX or edge-case coverage.
5. **E2E after phase completion**: Unit tests are necessary but not sufficient. Before marking a phase complete, run real end-to-end workflows via `dev/dev-sandbox.R` to catch integration bugs.
5a. **Long PR/commit messages — always use a file**: Never pass multi-line PR body text inline via `--body "..."` or heredoc (`<< 'EOF'`). Shell quoting and terminal emulation malways mangle them. Always write to a temp file with `create_file` first, then pass `--body-file /tmp/filename.md`. Same applies to long commit messages: write to a file and use `git commit -F /tmp/msg.md`. For short single-line messages (< 80 chars), inline `--message` / `-m` is fine
7. **Phase completion is mandatory**: When a phase is done, immediately follow the Phase Completion Procedure in `dev/README.md` — migrate learnings to spec/instructions, update README tables, delete the phase doc, and commit. Do NOT start the next phase until this is done. A phase is not "complete" until its doc is deleted.

## Model Escalation

Most chunks are routine and suited to a default working model. A few narrow moments are high-leverage enough to justify invoking a more capable model:

- **Design spot-check** before committing to a large or cross-cutting chunk.
- **Purity audit** after a refactor that touched many files, to catch drift the chunk-level review missed.
- **Test coverage review** before phase completion, to sanity-check that unit + E2E coverage actually exercises the new behavior.

When you recognize one of these moments mid-session, surface a brief recommendation before proceeding (e.g., "This chunk touches 6 files across 3 modules — consider escalating for a design spot-check"). The user decides whether to switch; don't block on it.

This is a pointer, not a protocol — use judgment. Escalation is cheap compared to a bad phase.
