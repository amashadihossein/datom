# Design Document

## Overview

This design prepares the `datom` R package for its first CRAN submission by resolving
`R CMD check --as-cran` blockers, addressing reviewer-rejection-class issues, and polishing
metadata. No new runtime behavior, modules, or functions are introduced — all changes target
package metadata, documentation, and namespace declarations.

The work divides into three sequential workstreams that can each be committed independently:

- **Workstream A — Mechanical blockers** (Req 1–3): dependency declarations + NAMESPACE.
- **Workstream B — Metadata & docs** (Req 4, 6–9): version bump, DESCRIPTION text, license,
  NEWS, cran-comments.
- **Workstream C — Examples** (Req 5): the largest effort; converting `\dontrun{}` to
  runnable examples where possible, adding `@examples` blocks to all exports, using the
  correct CRAN tag (`\dontrun{}` for network/credential-gated, bare for offline-capable).

Requirement 10 (ORCID / CITATION) is optional and deferred to maintainer preference.
Requirement 11 (CI-executable vignettes) is explicitly out of scope.

## Architecture

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
| Add `utils` to Imports | `utils::` qualified calls in 8+ files; required by CRAN even for base-shipped packages |
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

`LICENSE` says `COPYRIGHT HOLDER: Afshin Mashadi-Hossein` which matches `Authors@R`.
`LICENSE.md` must say `Copyright (c) 2025 Afshin Mashadi-Hossein` (not "datom authors").

#### NEWS.md rewrite (Req 9)

Replace all Phase-narrative content with a user-facing `# datom 0.1.0` entry. Structure:
- Brief package purpose statement (one paragraph).
- Feature groups: Core read/write/version, Sync, Query & lineage, Storage management,
  Repository & governance, Store constructors, Example data.
- No phase numbers, no removed functions, no internal development narrative.

#### cran-comments.md (Req 6)

Template with placeholders for the maintainer to fill after running `R CMD check --as-cran`.
Standard structure: test environments, check result summary, downstream dependencies.
Add `^cran-comments\.md$` to `.Rbuildignore` so it doesn't ship in the tarball.

### Workstream C — Examples

This is the largest workstream. The exported symbols (from NAMESPACE) are classified into
three example categories based on whether they can execute in CRAN's check environment.

#### Classification of exports

```mermaid
graph TD
    A[Exported function] --> B{Needs network/credentials/remote?}
    B -->|No| C{Needs git2r or git identity?}
    B -->|Yes| D["\\dontrun{} — cannot execute offline"]
    C -->|No| E["Bare runnable example"]
    C -->|Yes| D
```

**Key architectural constraint:** `datom_init_repo()` calls `.datom_git_push()` which
requires a live GitHub remote. There is **no offline / no-remote mode** — a `data_repo_url`
is mandatory by design. Every function that operates on a `datom_conn` therefore requires a
live GitHub remote + storage backend and **cannot execute** in CRAN's check environment.

Additionally, `\donttest{}` examples **are executed** by `R CMD check --as-cran` (the
`--run-donttest` flag is active by default). This means `\donttest{}` is NOT safe for
credential/network-gated functions.

#### Final classification

| Category | Tag | Functions |
|----------|-----|-----------|
| **Genuinely runnable** | bare `@examples` | Store constructors with `validate = FALSE` or local-only: `datom_store_local`, `datom_store`, `datom_store_s3`, `datom_store_s3_creds`; all predicates: `is_datom_store`, `is_datom_store_s3`, `is_datom_store_s3_creds`, `is_datom_store_local`; filesystem check: `is_valid_datom_repo`; bundled data: `datom_example_data`, `datom_example_cutoffs` |
| **Cannot execute** | `\dontrun{}` | All conn-based functions: `datom_init_repo`, `datom_write`, `datom_read`, `datom_list`, `datom_history`, `datom_sync_manifest`, `datom_sync`, `datom_status`, `datom_validate`, `datom_summary`, `datom_get_parents`, `datom_get_lineage`, `datom_validate_lineage`, `datom_clone`, `datom_pull`, `datom_get_conn`, `datom_projects`, `datom_repo_set_data_store`, `datom_repo_delete`, `datom_repo_attach_governance`, `datom_storage_list`, `datom_storage_delete_prefix`, `datom_storage_copy`, `datom_storage_verify` |
| **Print methods** | (via dispatch) | `print.datom_conn`, `print.datom_store`, `print.datom_store_local`, `print.datom_store_s3`, `print.datom_store_s3_creds`, `print.datom_summary` — exercised implicitly by their parent examples |

**Deviation from Requirement 5.1:** Req 5.1 ("no `\dontrun{}`") is not fully achievable
given the architecture. `\dontrun{}` is the correct, CRAN-permitted tag for
credential/network-gated examples. The realized improvement is that ~12 exported functions
now have genuinely runnable examples (previously zero did). Full runnability of the
connection workflow is only possible via the deferred CI-credentials work (Req 11).

#### Example writing conventions

- Each `@examples` block is self-contained (no reliance on external state).
- `\dontrun{}` bodies are written as coherent, complete usage demonstrations so they read as
  documentation even though they are not executed.
- No credentials or real secrets in any example — all placeholder values are obviously fake
  (e.g., `"AKIAIOSFODNN7EXAMPLE"`, `"https://github.com/user/project"`).
- Cleanup (`unlink`) is explicit in runnable examples that create temp files.
- Every exported function gets an `@examples` block — no exceptions.

## Components and Interfaces

No new components or interfaces are introduced. This work modifies existing package
infrastructure files:

| Component | Type | Change |
|-----------|------|--------|
| `DESCRIPTION` | Package metadata | Imports field, Version, Description text |
| `R/datom-package.R` | Package-level roxygen | `@importFrom` directive |
| `NAMESPACE` | Generated | Regenerated via `devtools::document()` |
| `LICENSE.md` | License text | Copyright holder name |
| `NEWS.md` | Changelog | Complete rewrite as release notes |
| `cran-comments.md` | Submission cover letter | New file |
| `.Rbuildignore` | Build exclusion list | Add cran-comments entry |
| `R/*.R` (multiple) | Roxygen headers | `@examples` blocks added/converted |

## Data Models

No data models are introduced or modified. This feature changes only package metadata and
documentation — no runtime data structures, schemas, or storage formats are affected.

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Note: Property-based testing (PBT with generated random inputs) does not apply to this
feature — there are no pure functions, data transformations, or algorithms being written.
The properties below are structural invariants verified by `R CMD check` and manual
inspection rather than by randomized test generation.

### Property 1: No dependency/namespace errors after blocker fixes

*For any* run of `R CMD check --as-cran` after Workstream A is applied, the check SHALL produce 0 ERRORs and 0 WARNINGs attributable to undeclared dependencies or missing namespace imports.

**Validates: Requirements 1.7, 2.2, 3.4**

### Property 2: Every exported function has an examples block

*For any* exported function listed in NAMESPACE, the corresponding `.Rd` man page SHALL contain an `\examples{}` section.

**Validates: Requirements 5.4**

### Property 3: Runnable examples execute without error

*For any* exported function whose `@examples` block is bare (not wrapped in `\dontrun{}`), that example SHALL execute without error in a fresh R session with no network access and no credentials.

**Validates: Requirements 5.2, 5.5**

### Property 4: dontrun is used only where genuinely required

*For any* exported function whose `@examples` block uses `\dontrun{}`, that function SHALL require network access, credentials, or a live git remote to execute — conditions that cannot be met under `R CMD check`.

**Validates: Requirements 5.1, 5.3**

### Property 5: Consistent identity across license and author metadata

*For any* of the files DESCRIPTION (Authors@R), LICENSE, and LICENSE.md, the copyright holder / author identity SHALL be `Afshin Mashadi-Hossein`.

**Validates: Requirements 8.1, 8.2**

## Error Handling

No error handling changes are introduced. All existing `cli::cli_abort()` / `stop()` calls
remain unchanged. The sole "error" surface is `R CMD check` itself — the validation gate —
and errors there are resolved by the metadata/documentation fixes described above.

## Testing Strategy

### Why property-based testing does NOT apply

This feature consists entirely of:
- Metadata file edits (DESCRIPTION, NAMESPACE, LICENSE.md)
- Documentation edits (roxygen `@examples` blocks, NEWS.md)
- A new static file (cran-comments.md)

There are **no pure functions being written**, no data transformations, no algorithms, and no
input/output behavior that varies across inputs. The correctness gate is a single invocation
of `R CMD check --as-cran` — a pass/fail smoke test, not a property that holds across a
range of generated inputs. Property-based testing is therefore not applicable.

### Verification approach

The authoritative validation gate for all requirements is **`R CMD check --as-cran`**
(equivalently `devtools::check()`), run by the maintainer or CI. R is not available in the
development environment, so verification is deferred to the maintainer.

### Verification assertions (smoke tests)

These assertions capture the expected outcome of running the validation gate after all
workstreams are applied:

| ID | Assertion | Validates |
|----|-----------|-----------|
| V1 | After blockers are applied, `R CMD check --as-cran` produces 0 ERRORs and 0 WARNINGs from dependency/namespace issues | Req 1, 2, 3 |
| V2 | No `\dontrun{}` appears in any exported function's documentation **that could instead be a runnable example** (i.e., `\dontrun{}` is only used where genuinely required by network/credential constraints) | Req 5 |
| V3 | Every exported function has an `@examples` block | Req 5.4 |
| V4 | Runnable examples execute without error in a fresh R session with no network and no credentials | Req 5.5 |
| V5 | DESCRIPTION, LICENSE, LICENSE.md, and Authors@R present a consistent identity (`Afshin Mashadi-Hossein`) | Req 8 |

### Unit testing

No new unit tests are required. The existing test suite (1873 tests) must continue to pass
at the same count after every commit — the "test count must not drop" invariant. No test
files are modified.

### Verification checklist for maintainer

1. Run `devtools::document()` — confirm NAMESPACE contains `importFrom(rlang,"%||%")`.
2. Run `devtools::check()` — confirm 0 errors, 0 warnings.
3. Grep for `\\dontrun` in `man/` — confirm it only appears on conn/network-gated functions.
4. Grep for exported functions missing `\examples` in `man/` — confirm none.
5. Inspect `LICENSE`, `LICENSE.md`, `DESCRIPTION` `Authors@R` — confirm consistent holder.
6. Fill in actual test environments and results in `cran-comments.md`.

## Sequencing

The three workstreams are independent and can be done in any order, but the natural
sequence is A → B → C because:
- A is prerequisite-free and the highest priority (fixes check failures).
- B is mostly text editing and quick.
- C is the largest effort and benefits from having the correct NAMESPACE/Imports already
  in place (so example code is coherent).

Within each workstream, changes are committed atomically (one commit per workstream or
logical sub-unit). The final validation (task 12) is performed by the maintainer after all
three workstreams land.

## Out of Scope

- Requirement 10 (ORCID / inst/CITATION) — deferred to maintainer preference at
  submission time.
- Requirement 11 (CI-executable vignettes) — explicitly deferred per requirements.
- Modifying any function body or runtime behavior.
- Adding or modifying unit tests.
