# Design Document

## Overview

This design prepares the `datom` R package for its first CRAN submission by resolving
`R CMD check --as-cran` blockers, addressing reviewer-rejection-class issues, and polishing
metadata. The work divides into three sequential workstreams that can each be committed
independently.

**Workstream A — Mechanical blockers** (Req 1–3): dependency declarations + NAMESPACE.
**Workstream B — Metadata & docs** (Req 4, 6–9): version bump, DESCRIPTION text, license,
NEWS, cran-comments.
**Workstream C — Examples** (Req 5): the largest effort; converting `\dontrun{}` to
runnable/`\donttest{}` and adding examples to undocumented exports.

Requirement 10 (ORCID / CITATION) is optional and deferred to maintainer preference.
Requirement 11 (CI-executable vignettes) is explicitly out of scope.

## Architecture / Approach

No new modules, packages, or runtime behaviors are introduced. All changes are to
package metadata (DESCRIPTION, NAMESPACE, LICENSE/LICENSE.md), documentation (roxygen
headers in `R/*.R`, NEWS.md, cran-comments.md), and one roxygen directive in
`R/datom-package.R`.

### Workstream A — Dependency & NAMESPACE fixes

**Files changed:** `DESCRIPTION`, `R/datom-package.R`, `NAMESPACE` (regenerated).

| Change | Rationale |
|--------|-----------|
| Move `glue` from Suggests → Imports | Used unconditionally on core paths (ref.R, repo.R, utils-path.R, projects.R) |
| Move `yaml` from Suggests → Imports | Used unconditionally on core paths (conn.R, repo.R, ref.R) |
| Add `utils` to Imports | `utils::` qualified calls in 8 files; required by CRAN even for base-shipped packages |
| Add `#' @importFrom rlang %||%` to `R/datom-package.R` | Resolves the operator for all 17 files via collation; avoids pinning R ≥ 4.4.0 |

The `@importFrom` directive is placed in `R/datom-package.R` (the canonical location for
package-wide imports per tidyverse convention, where `@importFrom rlang .data` already
lives). After editing, `roxygen2::roxygenise()` regenerates the NAMESPACE.

**Invariants:**
- `git2r` and `rio` remain in Suggests (they are properly guarded with `requireNamespace()`).
- No source code changes — only metadata and the roxygen directive.
- NAMESPACE is never hand-edited; it is always regenerated.

### Workstream B — Metadata & documentation polish

**Files changed:** `DESCRIPTION`, `LICENSE.md`, `NEWS.md`, `cran-comments.md` (new),
`.Rbuildignore`.

#### DESCRIPTION edits (Req 4, 7)

```
Version: 0.1.0
Title: Version-Controlled Data Management for Reproducible Workflows
Description: Provides version-controlled data management by abstracting tables
    as code in 'git' while storing actual data in cloud storage ('S3'). Enables
    setting up cloud-based repositories via 'GitHub', syncing data with automatic
    versioning, tracking complete data lineage, and accessing any historical
    version for reproducibility. Designed for clinical and scientific workflows
    where reproducibility is paramount.
```

Software names `git`, `GitHub`, `S3` are single-quoted per CRAN policy. The Title does not
currently contain any of these names, so only the Description field changes.

#### License consistency (Req 8)

`LICENSE` already says `COPYRIGHT HOLDER: Afshin Mashadi-Hossein` which matches `Authors@R`.
`LICENSE.md` says `Copyright (c) 2025 datom authors` — update to
`Copyright (c) 2025 Afshin Mashadi-Hossein` for consistency.

#### NEWS.md rewrite (Req 9)

Replace the entire Phase-narrative content with a user-facing `# datom 0.1.0` entry.
Structure:
- Brief package purpose statement (one paragraph).
- Feature groups: Core (write/read/version), Sync, Query & lineage, Storage management,
  Governance attachment, Example data.
- Note on pre-release status / API stability disclaimer removed (it's now a release).

#### cran-comments.md (Req 6)

Create a template with placeholders for the maintainer to fill after running
`R CMD check --as-cran`. Structure follows the standard form:

```markdown
## R CMD check results

0 errors | 0 warnings | N notes

* This is a new submission.

## Test environments

* [to be filled: e.g., macOS (local), ubuntu-latest (GHA), windows-latest (GHA)]
* R x.y.z

## Downstream dependencies

None (new package).
```

Add `^cran-comments\.md$` to `.Rbuildignore` so it doesn't ship in the tarball.

### Workstream C — Examples

This is the largest workstream. The 37 exported symbols (from NAMESPACE) break down as:

#### Category 1 — Already have runnable examples (no change needed)
- `datom_example_data()` — reads from `inst/extdata`, runs without network.
- `datom_example_cutoffs()` — pure computation, already runnable.

#### Category 2 — Can have genuinely runnable examples (Local_Backend)

Functions that work against a local datom repo, using `datom_store_local()` +
`withr::with_tempdir()` for a self-contained example that needs no network/creds:

| Function | Example strategy |
|----------|-----------------|
| `datom_store_local()` | Constructor call with a tempdir path |
| `is_datom_store_local()` | Predicate on the above |
| `print.datom_store_local` | Implicit from above |
| `datom_store()` | Composite with `data = datom_store_local(...)`, `governance = NULL` |
| `is_datom_store()` | Predicate on the above |
| `print.datom_store` | Implicit from above |
| `datom_init_repo()` | Init a local repo in tempdir (requires git2r — wrap in `\donttest{}` since git2r is Suggests + needs git configured) |
| `datom_write()` | Write example data to the local repo |
| `datom_read()` | Read it back |
| `datom_list()` | List tables in the local repo |
| `datom_history()` | Show version history |
| `datom_status()` | Show repo status |
| `datom_validate()` | Validate the local repo |
| `is_valid_datom_repo()` | Predicate on the path |
| `datom_sync_manifest()` | Build manifest from inst/extdata CSVs |
| `datom_sync()` | Sync the manifest |
| `datom_summary()` | Summarize the local project |
| `datom_get_parents()` | Show parent lineage |
| `datom_get_lineage()` | Show full lineage |
| `datom_validate_lineage()` | Validate lineage consistency |

**Note on git2r dependency**: `datom_init_repo()` and the write/sync path require `git2r`
(which is in Suggests). Examples that call these must be wrapped in `\donttest{}` because
CRAN check environments may not have `git2r` or a configured git identity. This is
acceptable — `\donttest{}` is explicitly permitted by CRAN for examples that are runnable
but depend on optional infrastructure.

**CORRECTION (post-check finding):** `\donttest{}` examples **are executed** by
`R CMD check --as-cran` (that is exactly what `--run-donttest` does). The connection-based
functions cannot be tagged `\donttest{}` because they would then be run and fail:
`datom_init_repo()` calls `.datom_git_push()` to the data repo's GitHub remote, and there is
**no offline / no-remote mode** (a `data_repo_url` is mandatory by design). Every function
that operates on a `datom_conn` therefore requires a live GitHub remote + storage backend and
**cannot execute** in CRAN's check environment.

The correct, CRAN-acceptable tag for examples that genuinely require credentials/network is
`\dontrun{}`. CRAN permits `\dontrun{}` for exactly this case; reviewers object to
`\dontrun{}` only when an example *could* be made runnable. Here it cannot.

**Final classification:**

- **Genuinely runnable (bare examples, executed by check):** the store constructors
  (`datom_store`, `datom_store_s3`, `datom_store_s3_creds`, `datom_store_local` — all with
  `validate = FALSE` or local dir creation, no network), their predicates
  (`is_datom_store*`), `is_valid_datom_repo()` (pure filesystem check), and the pre-existing
  `datom_example_data()` / `datom_example_cutoffs()`.
- **`\dontrun{}` (cannot execute — needs GitHub remote / S3 / live conn):** everything that
  takes or builds a `datom_conn` — `datom_init_repo`, `datom_write`, `datom_read`,
  `datom_list`, `datom_history`, `datom_sync_manifest`, `datom_sync`, `datom_status`,
  `datom_validate`, `datom_summary`, `datom_get_parents`, `datom_get_lineage`,
  `datom_validate_lineage`, `datom_clone`, `datom_pull`, `datom_get_conn`, `datom_projects`,
  and the `datom_repo_*` / `datom_storage_*` families. The `\dontrun{}` bodies are written as
  self-contained, coherent code (local-backend setup) so they read as complete usage even
  though they are not run.
- Internal helpers (`.datom_build_storage_key`, `.datom_parse_s3_uri`) keep `\dontrun{}` —
  they call non-exported functions that are not on the search path during example runs.

**Deviation from Requirement 5:** Req 5.1 ("no `\dontrun{}`") is not achievable given the
architecture; `\dontrun{}` is the correct tag for the credential/network-gated functions. The
realized improvement is that ~12 exported functions now have genuinely runnable examples
(previously all were `\dontrun{}`). Full runnability of the connection workflow is only
possible via the deferred CI-credentials work (Req 11).

#### Category 3 — Require network/credentials → `\donttest{}`

Functions that require S3 credentials, GitHub API, or network:

| Function | Reason |
|----------|--------|
| `datom_store_s3()` | S3 bucket required |
| `is_datom_store_s3()` | Trivial predicate — can use a mock object, runnable |
| `print.datom_store_s3` | Same |
| `datom_store_s3_creds()` | Credential constructor — can be runnable with fake values |
| `is_datom_store_s3_creds()` | Trivial predicate — runnable |
| `print.datom_store_s3_creds` | Same |
| `datom_clone()` | Needs GitHub remote |
| `datom_pull()` | Needs existing clone with remote |
| `datom_get_conn()` | Can work locally if path-based — `\donttest{}` |
| `datom_projects()` | Needs governance store |
| `datom_repo_set_data_store()` | Needs active conn with remote |
| `datom_repo_delete()` | Destructive, needs remote |
| `datom_repo_attach_governance()` | Needs governance store |
| `datom_storage_list()` | Needs active conn |
| `datom_storage_delete_prefix()` | Destructive, needs active conn |
| `datom_storage_copy()` | Needs two active conns |
| `datom_storage_verify()` | Needs active conn |

**Refinement**: `is_datom_store_s3()`, `is_datom_store_s3_creds()`, and their print methods
can have genuinely runnable examples because the constructors don't validate credentials at
construction time — they just build the S3 object. So these become bare runnable examples
with fake placeholder values (e.g., `access_key = "AKIAIOSFODNN7EXAMPLE"`).

#### Category 4 — print.datom_conn

`print.datom_conn` is an S3 method dispatched implicitly. It doesn't need its own
`@examples` block; the class is demonstrated in other functions' examples.

#### Example placement convention

- Each `@examples` block is self-contained (no reliance on external state).
- `\donttest{}` wraps anything requiring git2r, git identity, or network.
- No `\dontrun{}` anywhere.
- Cleanup (`unlink`) is explicit.

## Correctness Properties

1. **No source-code behavior change.** No function body is modified in any workstream.
   Only metadata (DESCRIPTION, NAMESPACE, LICENSE.md), documentation (roxygen `@examples`,
   NEWS.md, cran-comments.md), and the `@importFrom` directive change.
2. **NAMESPACE is always regenerated.** After editing `R/datom-package.R`, the maintainer
   runs `roxygen2::roxygenise()` (or `devtools::document()`). The NAMESPACE shown in the
   tasks is the expected output, not a hand edit.
3. **Test count must not drop.** No test files are modified; existing tests must still pass
   at the same count after every commit.
4. **`git2r` and `rio` stay in Suggests.** They are properly guarded; moving them would be
   incorrect.
5. **No credentials in examples.** All placeholder values in examples are obviously fake
   (AWS example keys, `https://github.com/fake/repo`). Consistent with the project's
   secret-handling principle.

## Sequencing

The three workstreams are independent and can be done in any order, but the natural
sequence is A → B → C because:
- A is prerequisite-free and the highest priority (fixes check failures).
- B is mostly text editing and quick.
- C is the largest effort and benefits from having the correct NAMESPACE/Imports already
  in place (so example code referencing `%||%` or `glue` is coherent).

## Out of Scope

- Requirement 10 (ORCID / inst/CITATION) — deferred to maintainer preference at
  submission time.
- Requirement 11 (CI-executable vignettes) — explicitly deferred per requirements.
- Modifying any function body or runtime behavior.
- Adding or modifying tests.
