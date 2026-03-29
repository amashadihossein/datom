# tbit Development Hub

## Documentation Hierarchy

This folder contains all development documentation following a hierarchical chain:

```
.github/copilot-instructions.md     ← Entry point for AI/developers
         ↓
dev/README.md                       ← This file: navigation hub
         ↓
dev/tbit_specification.md           ← Design spec (authoritative, evolves slowly)
dev/daapr_architecture.md           ← Ecosystem context
dev/tbitaccess_overview.md          ← tbitaccess sister package context (forward-looking)
         ↓
dev/phase_{n}_{name}.md             ← Active development plans (temporary)
         ↓
dev/phase_{n}_{name}/               ← Sub-phase plans if needed (temporary)
    └── subphase_{m}_{name}.md
```

## Documentation Lifecycle

### Active Development Plans

Phase plans are **temporary working documents**:

1. **Created** when starting a phase
2. **Updated continuously** as development proceeds (progress, decisions, blockers)
3. **Completed** when all acceptance criteria met
4. **Archived**: Persistent learnings → spec/architecture docs, then delete phase file

### What Goes Where

| Content Type | Location | Lifecycle |
|--------------|----------|-----------|
| Coding style, conventions | `.github/copilot-instructions.md` | Permanent |
| Architecture, API design | `dev/tbit_specification.md` | Permanent, evolves |
| Ecosystem context | `dev/daapr_architecture.md` | Permanent |
| Current work, decisions | `dev/phase_*.md` | Temporary |
| Implementation details discovered | Migrate to spec, then delete | — |

## Current Development State

### Active Phases

| Phase | Status | File |
|-------|--------|------|
| Phase 9: Rename tbit → datom | In progress | `dev/phase_9_rename_tbit_to_datom.md` |

### Completed Phases

| Phase | Completed | Tests | Summary |
|-------|-----------|-------|---------|
| Phase 7: Multi-Developer Collaboration | 2026-03-28 | 964 | S3 namespace safety check in `tbit_init_repo()`, pull-before-push discipline (`.tbit_git_pull`, `.tbit_check_git_current`), `tbit_pull()` export (git-only, no S3 refresh — git is source of truth), `tbit_clone()` export, team collaboration vignette, credentials vignette, `project_name` in manifest, `.force` bypass, `tbit_validate()` project_name cross-check |
| Phase 8: Metadata Enrichment & Table Types | 2026-03-28 | 905 | `table_type`, `size_bytes`, `parents`, `original_file_sha` in version_history, `tbit_get_parents()`, `endpoint` param, `.access/` namespace safety. Post-phase bug fixes: manifest update in `tbit_write`, `tbit_init_repo` S3 push, idempotent SHA computation (JSON canonical form, volatile field exclusion, version_history dedup guard) |
| Phase 6: Sync & Validation | 2026-02-15 | 130 | tbit_sync_manifest, tbit_sync (rio import), tbit_sync_routing, tbit_validate (git-S3 consistency), tbit_status |
| Phase 5: Read/Write Workflows | 2026-02-15 | 143 | tbit_read (version resolution), tbit_write (change detection, parquet+metadata), .tbit_sync_metadata, tbit_list, tbit_history |
| Phase 4.5: S3 Refactor | 2026-02-15 | 99 | Refactored S3 utils from (s3_client, bucket, s3_key) to (conn, s3_key), added mock_tbit_conn helper |
| Phase 4: Connection & Init | 2026-02-15 | 115 | tbit_conn S3 class, tbit_get_conn (developer/reader), tbit_init_repo, credential derivation |
| Phase 3: Git Operations | 2026-02-14 | 47 | git2r wrappers: check, author, branch, commit, push (fetch+merge+push) |
| Phase 2: S3 Operations | 2026-02-10 | 99 | S3 client, upload/download/exists, JSON read/write, redirect resolution |
| Phase 1: Core Utilities | 2026-02-09 | 131 | SHA, paths, name validation, repo validation |

### Developer Tooling

**dev/dev-sandbox.R**: Automated setup/teardown for testing workflows

- `sandbox_up()`: Creates GitHub repo + runs `tbit_init_repo()` + populates with example data
- `sandbox_down()`: Wipes S3 namespace + deletes GitHub repo + removes local directory
- `sandbox_reset()`: Full teardown + setup in one call
- Replaces manual 5-step workflow (create repo, walk vignette, delete S3, delete repo, delete local)
- Requires `gh` CLI, AWS credentials, `GITHUB_PAT`

### Backlog (Deferred Features)

Items discovered during development but intentionally deferred. Review periodically.

| Item | Discovered In | Reason Deferred | Priority |
|------|---------------|-----------------|----------|
| Derived tbit path convention (raw at top, derived in dp subfolder) | Phase 1 | dpbuild concern — tbit handles via prefix param | Low (dpbuild) |
| renv::init() in tbit_init_repo | Phase 4 | Adds complexity, tangential to core data versioning | Low |
| Redirect resolution in tbit_get_conn | Phase 4 | Needs S3 read infra tested end-to-end | Medium (Phase 5) |
| Manifest manipulation APIs (descriptions, staging, QA tagging) | Phase 7 | Two-step scan+sync is sufficient; richer manifest APIs belong in a sister package or future tbit release | Medium |

**Backlog lifecycle**:
1. Discovered during phase work → add here with context
2. When planning next phase → review for inclusion
3. If promoting to spec → move to `tbit_specification.md` "Deferred to v2" section
4. If abandoned → delete with brief note why

### Phase Roadmap

| Phase | Name | Dependencies | Est. Effort |
|-------|------|--------------|-------------|
| 1 | Core Utilities | None | 1 week |
| 2 | S3 Operations | Phase 1 | 1 week |
| 3 | Git Operations | Phase 1 | 1 week |
| 4 | Connection & Init | Phases 1-3 | 1 week |
| 5 | Read/Write Workflows | Phase 4 | 1-2 weeks |
| 6 | Sync & Validation | Phase 5 | 1 week |
| 7 | Multi-Developer Collaboration | Phases 1-6 | 1-2 weeks |
| 8 | Metadata Enrichment & Table Types | Phases 1-6 (parallel w/ 7) | 1 week |

## Quick Context for New Sessions

When starting a new development session:

1. Check **Active Phases** table above
2. Open the active phase file
3. Read the **Current Chunk** section
4. Continue from where we left off

---

## Collaborative Development Workflow

Within each phase, we work in **chunks** — small, testable units of work.

### Chunk Lifecycle

```
1. DESIGN    → Propose scope, functions, acceptance criteria
                 ↓
              User approves or adjusts
                 ↓
2. DEVELOP   → Implement code + tests
                 ↓
              User reviews, runs tests, QA
                 ↓
3. FEEDBACK  → User confirms or requests changes
                 ↓
              Iterate until approved
                 ↓
4. COMPLETE  → Mark chunk done, pick next chunk
```

### Chunk Size Guidelines

- **1-3 functions** per chunk (testable in one session)
- **Clear boundary** — chunk should work independently
- **User can QA** — real tests they can run

### Communication Pattern

At each stage, I will:

| Stage | I Provide | You Provide |
|-------|-----------|-------------|
| DESIGN | Proposed functions, signatures, tests | Approval or adjustments |
| DEVELOP | Implementation + test file + debug snippet | Run tests, step through, try it out |
| FEEDBACK | Respond to issues | Confirm done or request changes |

### Chunk Delivery Checklist

After each chunk is implemented, I deliver **four things in order**:

1. **Write tests** — full test coverage for the chunk's functions
2. **Run tests** — execute and fix until all pass (green suite)
3. **Minimalist walkthrough snippet** — a clean, self-contained R snippet for you to paste into the console and step through interactively (use `debugonce()` to drop into any function)
4. **Commit after walkthrough** — once you've kicked the tires and confirmed it works, I commit with a concise message (e.g., `"Phase 4 Chunk 2: tbit_conn class"`), then you push

### QA Methods

- **Run tests**: `devtools::test(filter = "chunk_name")`
- **Debug walkthrough**: Step through with breakpoints or `browser()`
- **Try interactively**: Playground snippets provided with each chunk

### Code Style for Debuggability

To support step-through debugging:

- **Meaningful intermediates**: Avoid long pipe chains; use named variables
- **Small functions**: Each does one thing, easy to step into
- **Playground snippets**: Each chunk includes copy-paste code to try interactively

### Git Commit Cadence

Within chunks:

- **Commit frequently**: After each logical unit (function + test, fix, etc.)
- **Push at milestones**: Chunk complete, phase complete, or good stopping point
- **Message format**: `[Phase N Chunk M] Brief description`

Example:
```bash
# Within Chunk 1
git add R/utils-sha.R tests/testthat/test-utils-sha.R
git commit -m "[Phase 1 Chunk 1] Implement .tbit_compute_data_sha with tests"

# More work...
git add R/utils-sha.R tests/testthat/test-utils-sha.R
git commit -m "[Phase 1 Chunk 1] Add metadata SHA with alphabetic sorting"

# Chunk complete
git push  # ← Good milestone
```

## Maintenance Rules

1. **Always update phase docs** as you work (decisions, progress, blockers)
2. **Create sub-phases** for tasks taking >2-3 sessions
3. **Never let phase docs go stale** — if context changes, update immediately
4. **Archive promptly** — don't accumulate completed phase files
5. **Update this README** when phase status changes
6. **Capture deferrals immediately** — when you skip something, document it
7. **Review backlog** before starting each phase

## Phase Completion Procedure

When a phase is done, perform these steps **in order before starting the next phase**:

1. **Harvest persistent content** from the phase doc:
   - Design decisions that affect the overall API → migrate to `dev/tbit_specification.md`
   - Coding patterns/conventions discovered → migrate to `.github/copilot-instructions.md`
   - Ecosystem learnings → migrate to `dev/daapr_architecture.md`
   - Deferred items → move to the **Backlog** table in this README

2. **Update this README**:
   - Move phase from Active → Completed table (with date, test count, summary)
   - Update backlog if needed

3. **Delete the phase doc** — it should contain nothing worth keeping at this point

4. **Commit the cleanup** — one commit for the doc housekeeping

**Rule**: No phase doc should survive past its completion. If it feels hard to delete,
that means persistent content hasn't been migrated yet — do that first.
