# Phase 21: Governance-First Connection UX (`governance.json`)

**Status**: Chunk 3 complete; Chunk 4 next
**Started**: 2026-05-23
**Issue**: GitHub #24
**Branch**: `phase/21-governance-first-connection`

---

## 1. Goal

Two outcomes, one mechanism:

1. **Solve issue #24**: a reader of a gov-attached project should not need to be told the data bucket/prefix/region. Governance is the source of truth for data location; the connection path resolves it.
2. **Close the gov-discovery gap**: a reader (or any client) holding only data-store coordinates should be able to discover that governance exists, where it lives, and route through it. Pulls double-duty for the "gov was attached after I last connected" case and the "gov itself moved" case.

The package UX is intentionally bifurcated:

| Project state | Data location source | What user supplies |
|---------------|----------------------|--------------------|
| Gov attached | `ref.json` at gov storage | Credentials only (data + gov) and `project_name` |
| No gov | `store$data` location | Full data store coordinates (root, prefix, region, credentials) |

---

## 2. Core Design: `governance.json`

### 2.1 What it is

A small JSON file that records "this data store is gov-attached, and here is where gov lives." Lives at **two locations**:

- Git copy: `{data_repo}/.datom/governance.json` (canonical)
- Storage mirror: `{prefix}/datom/.metadata/governance.json` at the **data** store (read by reader / serverless clients)

Mirroring pattern is identical to `manifest.json`: git is canonical, storage is a derived mirror written by the same writer in the same commit step.

### 2.2 Schema

```json
{
  "gov_repo_url": "https://github.com/acme/datom-gov.git",
  "gov_storage": {
    "type": "s3",
    "root": "acme-gov",
    "prefix": null,
    "region": "us-east-1"
  },
  "attached_at": "2026-05-23T14:00:00Z"
}
```

Fields:

- `gov_repo_url` -- HTTPS clone URL of the governance git repo.
- `gov_storage.type` -- `"s3"` or `"local"`.
- `gov_storage.root` -- bucket (s3) or directory (local).
- `gov_storage.prefix` -- optional string, may be `null`.
- `gov_storage.region` -- present iff `type == "s3"`.
- `attached_at` -- ISO 8601 UTC timestamp from `datom_attach_gov()` or `datom_init_repo()` (when gov supplied at init).

**Never contains** credentials, `gov_local_path`, or any per-machine state.

### 2.3 Why split it out of `project.yaml`

- `project.yaml` is git-only (review surface, per-project config); we keep it git-only.
- `governance.json` is the **cross-store indirection pointer**, the dual of `ref.json`. It needs to be readable from the data store, so it's mirrored to storage.
- No duplication in git: `storage.governance` and `repos.governance` blocks are **removed** from `project.yaml`. The presence of `.datom/governance.json` is the no-gov vs gov-attached signal.
- `gov_local_path` was the only per-machine field; it leaves persisted state entirely and becomes runtime-only (store override or computed default via `.datom_resolve_or_default_gov_path()` minus its yaml arm).

### 2.4 Discovery flows after this phase

**Reader, gov-attached, gov-first (issue #24's ergonomic win):**

```
user provides: gov_store credentials + project_name + data credentials
  -> read ref.json from gov storage
  -> get data location (root/prefix/region/type)
  -> construct data client using user-supplied data credentials at ref location
  -> return conn
```

**Reader, gov-attached, data-first (serverless / "I only have data bucket"):**

```
user provides: data_store credentials (root/prefix/region) + project_name
  -> read governance.json from data storage
  -> if present: warn "This project has governance attached. Connection
                 resolved using supplied coordinates, which may become
                 stale after a data migration. Upgrade by passing
                 governance = datom_store_*(...) -- location is
                 auto-resolved." then proceed with supplied coordinates.
  -> if absent: project is no-gov, use data_store as-is
```

**Developer (path + store):**

```
read .datom/project.yaml + .datom/governance.json (if present) from local clone
  -> if governance.json present: gov-attached -> ref.json bootstrap
  -> if absent: no-gov -> use store$data directly
  -> if governance.json present but store$governance is NULL:
     -> error directing user to add governance to their store
  -> if governance.json absent but store$governance is set:
     -> warn that store gov will be ignored; may indicate stale clone (datom_pull)
```

---

## 3. Critical Evaluation of Issue #24

The bug is real: today's reader path requires fully-specified `store$data` even when `ref.json` could provide it. But the issue's proposed fix (drop `store$data` when gov is present) is too narrow.

What this phase adds beyond #24:

1. **State-driven, not role-driven.** The gov-vs-no-gov rule applies to developers too, not just readers.
2. **Credentials vs location are separable.** `ref.json` and `governance.json` carry location only. Credentials remain runtime-only.
3. **Serverless / minimal-bootstrap case** falls out for free once `governance.json` exists at the data store.
4. **`gov_local_path` cleanup**: removed from persisted state (was awkward -- per-machine absolute path in git).

---

## 4. Invariants (Must Never Violate)

1. **Secrets**: no credentials in `governance.json`, `ref.json`, `project.yaml`, `manifest.json`, git remotes, logs, or unmasked print output.
2. **Canonical source**: git is canonical for `governance.json`. Storage mirror is derived. Disagreement is resolved by rewriting storage from git.
3. **No silent location guessing for writes**: `.datom_check_ref_current()` keeps its hard-abort behavior at write time.
4. **No-gov projects do not get `governance.json`.** Absence at both locations is the no-gov signal.
5. **`gov_local_path` is never persisted** -- not in git, not in storage, not in any datom-written file.
6. **Dispatch layer**: business logic stays on `.datom_storage_*()`, never `.datom_s3_*()` / `.datom_local_*()` directly.
7. **Backend-neutral UI**: backend-aware messages use lookup tables, not `if (backend == "s3")` chains.

---

## 5. Read-First Map (For Any Chunk)

Before editing, open these in order:

1. [.github/copilot-instructions.md](.github/copilot-instructions.md) -- gotchas, secret handling, style rules.
2. [R/conn.R](R/conn.R) lines 1-200 -- `new_datom_conn()`, `datom_get_conn()`, developer/reader path branches.
3. [R/conn.R](R/conn.R) lines 310-640 -- `datom_init_repo()` (project.yaml + manifest write + push).
4. [R/conn.R](R/conn.R) lines 811-1115 -- `datom_attach_gov()` (current writer of `storage.governance`/`repos.governance`).
5. [R/ref.R](R/ref.R) -- `.datom_create_ref()`, `.datom_resolve_data_location()`, `.datom_check_ref_current()`.
6. [R/store.R](R/store.R) lines 1-150 -- `datom_store()` constructor, validation rules.
7. [R/utils-path.R](R/utils-path.R) lines 1-50 -- `.datom_build_storage_key()` semantics.
8. [R/sync.R](R/sync.R) -- existing manifest mirror pattern; mirror `governance.json` the same way.

---

## 6. Chunks

Each chunk is sized for one focused session. **Every chunk-completing commit must** (a) flip the Status cell below, (b) update the Status header line at top of this doc, (c) append a Progress Log entry, (d) update [dev/README.md](dev/README.md) Active Phases row.

| # | Name | Scope | Tests | Status |
|---|------|-------|-------|--------|
| 1 | `governance.json` writer/reader primitives | New file [R/governance_json.R](R/governance_json.R) with builder + local + storage I/O helpers. Pure helpers, no callers yet. | `test-governance_json.R`: schema round-trip, missing file, malformed JSON, secret-leakage guard. | ✅ done |
| 2 | Write `governance.json` from `datom_init_repo()` and `datom_attach_gov()` | Wire writers into the existing flows. Remove `storage.governance` and `repos.governance` writes. | Extend `test-conn.R`: assert governance.json on disk + in storage; assert yaml has no governance keys. | ✅ done |
| 3 | Read `governance.json` in `datom_get_conn()` developer path | Replace yaml-based gov detection with `governance.json` reads. Enforce the four-state matrix in §2.4. | Extend `test-conn.R`: four-state matrix; cross-check; both backends. | ✅ done |
| 4 | Read `governance.json` in `datom_get_conn()` reader path | Support gov-first (issue #24 happy path) and data-first (serverless). Warn (not error) on data-first into a gov-attached project; proceed with supplied coordinates. | Extend `test-conn.R`: both entry styles, both backends, no-gov and gov-attached. | ⏳ next |
| 5 | Refactor `ref.json` bootstrap (core of issue #24) | `.datom_resolve_data_location()` becomes a bootstrap source when `store$data` is credentials-only. Validator behavior unchanged for fully-specified `store$data`. | New tests: ref bootstraps from gov; credentials-only data store builds working conn; ref read failure path. | ☐ todo |
| 6 | Credentials-only data store shape | Allow NULL location on `datom_store_s3()` / `datom_store_local()` iff composite store has governance. Cross-validate. | Constructor tests: NULL location accepted iff gov present; rejected otherwise. | ☐ todo |
| 7 | `datom_decommission()` + `gov_local_path` removal | Decommission deletes governance.json from both locations. Remove `gov_local_path` from every persisted location. | Decommission tests; new regression test asserting no datom-written file contains `gov_local_path`. | ☐ todo |
| 8 | Mirror sync helper + repair story | Internal `.datom_sync_governance_json()` helper for repair after partial failures. Document in spec. | Sync test: mutate storage copy, run sync, assert restored from git copy. | ☐ todo |
| 9 | Docs + vignettes | Update handing-off, credentials-in-practice, design-ref-json; add design-governance-json; update spec and copilot-instructions. | `devtools::check()` clean; pkgdown build clean. | ☐ todo |
| 10 | E2E + audit | Full `devtools::test()` (record count). Sandbox E2E covering all six flows in §6 Chunk 10 notes. Phase Completion Procedure. | Full suite + E2E transcript in Progress Log. | ☐ todo |

---

## 7. Per-Chunk Implementation Notes

### Chunk 1 -- `governance.json` primitives

File: new [R/governance_json.R](R/governance_json.R)

Signatures:

```r
# Pure builder. gov_repo_url is on the composite datom_store, gov_store is the
# component (datom_store_s3 / datom_store_local).
.datom_create_governance_json <- function(gov_repo_url, gov_store,
                                          attached_at = NULL) -> list
# returns: list(gov_repo_url, gov_storage = list(type, root, prefix, region),
#               attached_at)
# attached_at defaults to format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Local git-copy I/O
.datom_write_governance_json_local <- function(path, content) -> invisible(NULL)
# writes to fs::path(path, ".datom", "governance.json")
# via jsonlite::write_json(auto_unbox = TRUE, pretty = TRUE)

.datom_read_governance_json_local <- function(path) -> list or NULL
# fs::path(path, ".datom", "governance.json")
# returns NULL if file absent; aborts on malformed JSON with cli message that
# names the path.

# Storage mirror I/O (via .datom_storage_* dispatch)
.datom_storage_write_governance_json <- function(conn, content) -> invisible(NULL)
# storage key passed to dispatch: ".metadata/governance.json"
# .datom_build_storage_key inserts the prefix + "datom/" automatically.

.datom_storage_read_governance_json <- function(conn) -> list or NULL
# returns NULL on "not found" (backend-aware); aborts on malformed JSON or
# non-not-found storage errors.

.datom_storage_delete_governance_json <- function(conn) -> invisible(NULL)
```

Implementation notes:

- Use `.datom_storage_*()` dispatch, never `.datom_s3_*()` directly (invariant 6).
- For not-found detection in the storage reader, mirror the pattern used by other manifest/dispatch reads in [R/query.R](R/query.R) and [R/summary.R](R/summary.R) (both backends have their own 404/missing-file shapes).
- Schema validation in readers: assert `gov_repo_url` is a non-empty string; `gov_storage$type %in% c("s3", "local")`; `gov_storage$root` non-empty. Do NOT require `region` when type is `local`. Abort with a cli message naming the source path/key.
- Use `cli::cli_abort()` and `cli::cli_warn()`; never `stop()` / `warning()`.

Tests (new file `tests/testthat/test-governance_json.R`):

1. Round-trip local: `build -> write_local -> read_local` -- compare field-by-field (JSON type coercion makes `expect_identical` fragile).
2. Round-trip storage: `build -> storage_write -> storage_read` using a mock conn that exercises both s3 and local backends. Look at existing tests for the right mock helper (`mock_datom_conn`, see `tests/testthat/helper-*.R` or `test-utils-storage.R`).
3. `read_local` returns NULL when file absent.
4. `read_storage` returns NULL when key absent.
5. Malformed JSON file -> error mentioning the path.
6. Field-presence validation: missing `gov_repo_url`, `gov_storage`, `gov_storage$type`, `gov_storage$root` each produce a clear error.
7. Backend-specific: `type = "local"` content omits `region`; reader accepts it.
8. **Secret-leakage guard**: assert that `names(content)` and `names(content$gov_storage)` contain none of `"pat"`, `"token"`, `"secret"`, `"access_key"`, `"password"`, `"session_token"` (case-insensitive regex over the flat name list).

Manual smoke walkthrough snippet (paste into console after `devtools::load_all()`):

```r
gov <- datom_store_s3(bucket = "acme-gov", prefix = NULL, region = "us-east-1",
                      access_key = "fake", secret_key = "fake")
content <- .datom_create_governance_json(
  gov_repo_url = "https://github.com/acme/datom-gov.git",
  gov_store    = gov
)
tmp <- fs::path(tempfile()); fs::dir_create(fs::path(tmp, ".datom"))
.datom_write_governance_json_local(tmp, content)
cat(readLines(fs::path(tmp, ".datom", "governance.json")), sep = "\n")
roundtrip <- .datom_read_governance_json_local(tmp)
stopifnot(identical(content$gov_repo_url, roundtrip$gov_repo_url))
```

### Chunk 2 -- Wire writers

Edit [R/conn.R](R/conn.R):

**`datom_init_repo()`** (around lines 460-540):
- Remove `storage_block$governance <- gov_yaml` (~L468).
- Remove `repos_block$governance <- list(remote_url = ..., local_path = ...)` (~L483).
- After the `yaml::write_yaml(...)` line: if `has_gov`, build governance.json content and call `.datom_write_governance_json_local(path, content)`.
- In the `git2r::add(repo, c(...))` list (~L569): when `has_gov`, include `".datom/governance.json"`.
- In the data-storage mirror step (~L621, sits alongside the manifest mirror write): when `has_gov`, also call `.datom_storage_write_governance_json(data_conn, content)`. Wrap in the same `tryCatch` as the manifest mirror -- on failure, abort with the same recovery hint pattern (re-run `datom_attach_gov()` is idempotent and resyncs).

**`datom_attach_gov()`** (around lines 925-1075):
- Idempotency check at the top: change `already_attached <- !is.null(conn$gov_root) || !is.null(cfg$storage$governance)` (~L925) to use local file presence: `fs::file_exists(fs::path(conn$path, ".datom", "governance.json"))` OR `!is.null(conn$gov_root)`.
- Remove `cfg$storage$governance <- gov_yaml` (~L1065).
- Remove `cfg$repos$governance <- list(...)` (~L1066).
- Remove the storage-ordering block for governance (~L1071-L1080); keep only `data` + `max_file_size_gb`.
- After `yaml::write_yaml(...)`: build governance.json content and call `.datom_write_governance_json_local(conn$path, content)`.
- In the `.datom_git_commit(...)` call: change `files = ".datom/project.yaml"` to `files = c(".datom/project.yaml", ".datom/governance.json")`.
- After `.datom_git_push(...)`: write the storage mirror via `.datom_storage_write_governance_json(fresh_conn, content)`. On failure, abort with hint "re-run `datom_attach_gov()` to retry".

**`.datom_get_conn_developer()`** (around L515):
- Remove the `storage$governance` references in the cross-check; the yaml cross-check becomes data-only (it already extracts `storage$data %||% storage`; just drop the governance arm if any).

Tests:

```r
test_that("project.yaml never contains storage.governance after attach_gov", {
  # ... after attach, read yaml back ...
  expect_null(cfg$storage$governance)
  expect_null(cfg$repos$governance)
})

test_that("attach_gov writes governance.json to local clone and storage", {
  expect_true(fs::file_exists(fs::path(path, ".datom", "governance.json")))
  # mirror present at storage too
})
```

### Chunk 3 -- Developer-path reader

Edit [R/conn.R](R/conn.R) `.datom_get_conn_developer()` (around L1370):

Introduce a small detection helper at the top of the function (or in `R/governance_json.R`):

```r
.datom_detect_gov_attachment_dev <- function(path) {
  # Reads .datom/governance.json from local clone; returns parsed list or NULL.
  # No storage fallback in dev path: a stale clone is the user's problem
  # (datom_pull()), not something to paper over.
  .datom_read_governance_json_local(path)
}
```

Replace any `cfg$storage$governance` / `cfg$repos$governance` usage with a call to this helper.

Enforce this four-state matrix (place inside `.datom_get_conn_developer()` after store extraction):

| governance.json present | store$governance | Action |
|------------------------|------------------|--------|
| no | no | no-gov; proceed |
| no | yes | warn: "no governance attached to this project; gov credentials will be ignored. Run `datom_attach_gov()` if you intend to attach." then proceed treating store as no-gov. |
| yes | no | abort: "this project is gov-attached. Add `governance = datom_store_*(...)` to your store. Location is auto-resolved; supply credentials only." Echo `gov_repo_url` and `gov_storage` from governance.json. |
| yes | yes | proceed. Cross-check `governance.json$gov_repo_url == store$gov_repo_url`; mismatch -> abort with `datom_pull()` hint. |

Tests: build the four cases against an init'd repo (with and without `attach_gov` having run). Cover both s3 and local backends for the "yes/yes" case.

### Chunk 4 -- Reader-path reader

Edit `.datom_get_conn_reader()` in [R/conn.R](R/conn.R) (around L1475):

Two entry styles:

**Style A: gov-first** (`store$governance` non-NULL)
- Skip governance.json read.
- Resolve via `ref.json` (Chunk 5 makes this a bootstrap source).
- If `store$data` is credentials-only, fill location from ref.

**Style B: data-first** (`store$governance` NULL, `store$data` has root)
- Build a temporary data conn (the existing `.datom_build_init_conn()` does this).
- Read `governance.json` from data storage via `.datom_storage_read_governance_json(temp_conn)`.
- If present: **warn** (do not abort) -- message: "This project has governance attached. Your connection was resolved using the coordinates you supplied, which may become stale after a data migration. To stay current, rebuild your store with `governance = datom_store_*(...)` and pass credentials only -- location is auto-resolved. Governance: {gov_repo_url}." Then return the temp conn (warn-and-proceed).
- If absent: no-gov; return the temp conn (becomes the real conn).

Tests:
- Style A happy path against an attached project.
- Style A credentials-only data store (introduces Chunk 6 dependency -- order chunks so this test lands in Chunk 6 if needed).
- Style B happy path against a no-gov project.
- Style B against a gov-attached project: expect a **warning** (not an error) containing `gov_repo_url`; assert conn is returned and usable.

### Chunk 5 -- `ref.json` as bootstrap

Edit `.datom_resolve_data_location()` in [R/ref.R](R/ref.R) (around L225):

Current behavior compares ref to `store$data` root; warns/errors on mismatch.

New behavior, branch on `store$data` root presence:

- **`store$data` has root**: same as today (validator/redirect).
- **`store$data` is credentials-only** (root NULL -- introduced in Chunk 6): no comparison; return ref location as-is. Caller fills in location from this.

Adjust callers in [R/conn.R](R/conn.R) at L1415 (developer path) and L1482 (reader path):

- After resolving `ref_location`, if `.datom_store_root(store$data)` is NULL, build an `effective_data_store` by cloning `store$data` and populating its root/prefix/region from `ref_location`. Pass that to `.datom_build_init_conn()`.
- If `store$data` had a root and `ref_location` differs, keep today's migration warning behavior.

Tests:
- Credentials-only store + ref -> conn has correct root/prefix/region.
- Credentials-only store + ref read failure -> hard error (no fallback because there is no fallback location).
- Fully-specified store + matching ref -> unchanged behavior.
- Fully-specified store + diverging ref -> existing migration warning/auto-pull path.

### Chunk 6 -- Credentials-only data store

Edit [R/store.R](R/store.R) `datom_store_s3()` (search for the existing constructor) and `datom_store_local()`.

Changes:

1. Allow `bucket = NULL` (s3) and `path = NULL` (local). Validation: if NULL, also `prefix` and `region` must be NULL (no half-specified location).
2. Tag the resulting object with `location_supplied <- !is.null(bucket)` (or `path`). Store on the object as a field (cleanest) or class attribute.
3. Update `.datom_store_root()`, `.datom_store_region()` to return NULL when location not supplied; `.datom_store_backend()` continues to work (driven by class).
4. Composite `datom_store()` (in same file, around L40): when any component reports `location_supplied = FALSE`, require `governance` non-NULL. Otherwise abort: "Credentials-only stores require governance; pass `governance = datom_store_*(...)` or supply full location."
5. `print.datom_store_s3()` / `print.datom_store_local()`: mask unsupplied root/prefix/region as `"<resolved from governance>"`.

Tests in `test-store.R`:
- `datom_store_s3(bucket = NULL, prefix = NULL, region = NULL, access_key = ..., secret_key = ...)` -> valid component.
- `datom_store_s3(bucket = NULL, prefix = "x", ...)` -> error: "half-specified location".
- Composite with credentials-only data + governance = NULL -> error.
- Composite with credentials-only data + governance = full -> valid.
- Print method masks unsupplied fields.

### Chunk 7 -- Decommission + `gov_local_path` cleanup

`datom_decommission()` (search `R/` for the function):

- Add filesystem delete of `.datom/governance.json` and include in the final git commit.
- Add `.datom_storage_delete_governance_json(conn)` call alongside the existing manifest cleanup.

`gov_local_path` removal sweep:

```sh
grep -rn 'gov_local_path\|local_path' R/
```

For each hit:
- In `datom_init_repo()` (~L478, repos block): drop the field.
- In `datom_attach_gov()` (~L1066, repos block): drop the field.
- In `.datom_get_conn_developer()`: keep runtime resolution via `.datom_resolve_or_default_gov_path(store, path)`; remove any reads from yaml.
- `.datom_resolve_or_default_gov_path()` (in [R/store.R](R/store.R)): keep store-override + sibling-of-data default; if there was a yaml-arm in any caller, delete it.

Print methods:
- `print.datom_conn`: keep the `gov_local_path` line (runtime field; informative).
- `print.datom_store`: keep the `gov_local_path` line (user-supplied override).

Regression test:

```r
test_that("no datom-written file persists gov_local_path", {
  # init + attach_gov
  files_to_scan <- c(
    fs::path(path, ".datom", "project.yaml"),
    fs::path(path, ".datom", "governance.json"),
    fs::path(path, ".datom", "manifest.json")
  )
  for (f in files_to_scan) {
    txt <- paste(readLines(f), collapse = "\n")
    expect_false(grepl("gov_local_path|local_path", txt, ignore.case = TRUE))
  }
})
```

### Chunk 8 -- Mirror sync helper

New internal helper (in [R/governance_json.R](R/governance_json.R)):

```r
.datom_sync_governance_json <- function(conn) {
  # Reads .datom/governance.json from local clone; writes to storage mirror.
  # Errors if local copy absent (caller bug: do not call for no-gov projects).
}
```

Wire-in: do NOT add a public export. The `datom_attach_gov()` recovery hint already says "re-run datom_attach_gov() (idempotent)". This helper is for future internal use (e.g., a future explicit repair command).

Test: mutate storage copy in place, call `.datom_sync_governance_json()`, assert storage matches git copy.

### Chunk 9 -- Docs + vignettes

Files:

- [vignettes/handing-off.Rmd](vignettes/handing-off.Rmd): engineer sends gov repo URL + project name + (out-of-band) gov credentials + data credentials. NOT data bucket/prefix/region. Update the "what the engineer sends" list to three items, not four.
- [vignettes/credentials-in-practice.Rmd](vignettes/credentials-in-practice.Rmd): document credentials-only `datom_store_s3()` shape.
- [vignettes/design-ref-json.Rmd](vignettes/design-ref-json.Rmd): add a "see also" pointing to design-governance-json.
- NEW [vignettes/design-governance-json.Rmd](vignettes/design-governance-json.Rmd): explain the dual-pointer pattern (`ref.json` at gov tells you where data lives; `governance.json` at data tells you where gov lives). Mirror the structure of design-ref-json.Rmd.
- [dev/datom_specification.md](dev/datom_specification.md): Configuration files table (add `governance.json`); Connection sections; Storage Structure ASCII tree; Secret Handling table.
- [.github/copilot-instructions.md](.github/copilot-instructions.md): add a gotcha entry: "governance.json mirror -- git canonical, storage derived; mirror in same step as manifest."
- [_pkgdown.yml](_pkgdown.yml): only if new exports added (lean: no new exports).

ASCII guard at end of chunk:
```sh
LC_ALL=C grep -lr '[^[:print:][:space:]]' R/*.R vignettes/*.Rmd
```

### Chunk 10 -- E2E + audit

E2E paths via `dev/dev-sandbox.R` (extend as needed):

1. No-gov init + write + read: governance.json absent in both locations.
2. No-gov -> `datom_attach_gov()`: governance.json appears in both locations.
3. Reader, gov-first, credentials-only data store (issue #24 happy path): connects and reads.
4. Reader, data-first, no gov in store, against gov-attached project: gets clear error with `gov_repo_url` in message.
5. Developer pulls after teammate attached gov: governance.json appears in clone; cross-check passes.
6. `datom_decommission()`: governance.json removed from both locations.

Final audit:

- Full `devtools::test()`; record count in commit message.
- ASCII guard run.
- `devtools::check()` clean.
- pkgdown build clean.
- Phase Completion Procedure (from `dev/README.md`): migrate persistent learnings to spec + copilot-instructions; remove from Active Phases; add to Completed Phases; delete this phase doc; PR + merge + branch delete.

---

## 8. Acceptance Criteria (Phase-Level)

1. A gov-attached reader can construct a connection by supplying gov credentials + project_name + data credentials only -- no data root/prefix/region.
2. A reader holding only data credentials against a gov-attached project gets a **warning** (not an error) that the connection may become stale after migration, and the connection succeeds using the supplied coordinates.
3. A no-gov reader still requires data root/prefix/region.
4. `governance.json` is written to both git and data storage by `datom_init_repo()` (when gov supplied) and `datom_attach_gov()`.
5. `project.yaml` no longer contains `storage.governance` or `repos.governance`.
6. `gov_local_path` does not appear in any datom-written file (git or storage).
7. Cross-store gov move (gov bucket changes) is recoverable: write new `governance.json` at data store, readers re-bootstrap correctly.
8. Existing developer flows continue to work; cross-check between local `governance.json` and `store$governance` is enforced.
9. `devtools::test()` passes with count recorded in the final commit.
10. E2E sandbox transcript demonstrates flows 1-6 from Chunk 10.

---

## 9. Open Questions (Settle Before / During Chunk 1)

- **OQ1**: `.datom_storage_read_governance_json()` public-ish or internal-only? Lean: internal-only.
- **OQ2**: Storage key path: `.metadata/governance.json` (sits next to `manifest.json`). Confirm in Chunk 1.
- **OQ3**: Schema version field? Lean: no, pre-release.
- **OQ4**: Cache reads within a session? Lean: no.
- **OQ5** (Chunk 6): credentials-only sentinel -- NULL root vs explicit marker. Lean: NULL.

---

## 10. Model Escalation Cues

- **After Chunk 1**: design spot-check if schema or helper surface drifted from §2.
- **After Chunk 6**: design spot-check on credentials-only `datom_store_*()` -- public API surface.
- **After Chunk 8**: purity audit across conn.R / ref.R / governance_json.R / store.R -- many files touched.
- **Before Phase Completion** (Chunk 10): test coverage review of the gov-attached / no-gov / credentials-only matrix.

---

## 11. Progress Log

- **2026-05-23 (Chunk 1)**: Added `R/governance_json.R` with `.datom_create_governance_json()`, `.datom_write_governance_json_local()`, `.datom_read_governance_json_local()`, `.datom_storage_write_governance_json()`, `.datom_storage_read_governance_json()`, `.datom_storage_delete_governance_json()`, `.datom_sync_governance_json()`, `.datom_validate_governance_json()`. 30 new tests (all pass); full suite 1637 passing, 0 failures. Note: `datom_store_s3(validate = FALSE)` required in tests to skip HeadBucket network call. Path normalisation (`fs::path_norm`) applied in builder to avoid double-slash on macOS tempdir paths.
- **2026-05-23 (Chunk 2)**: Wired `governance.json` writers into `datom_init_repo()` and `datom_attach_gov()`. Removed `storage.governance` / `repos.governance` blocks from `project.yaml` writes; those coordinates now live exclusively in `governance.json`. Idempotency check in `datom_attach_gov()` changed from `cfg$storage$governance` yaml-presence to `fs::file_exists(.datom/governance.json)`. Storage mirror written after git push in both functions (warn-only on failure). Updated `test-conn.R`: replaced all `cfg$storage$governance` / `cfg$repos$governance` assertions with `governance.json` file + field assertions; removed governance blocks from `create_test_datom_repo()` helper yaml. Commit `4a6f407`. Full suite 1639 passing, 0 failures.
- **2026-05-23 (Chunk 3)**: Implemented governance.json four-state matrix in `.datom_get_conn_developer()`. Read `governance.json` from local clone via `.datom_read_governance_json_local()`. Four states: (no/no) proceed; (no/set) warn + treat-as-no-gov; (yes/no) abort with gov_repo_url + gov_storage echoed; (yes/yes) proceed + cross-check URL when `store$gov_repo_url` is set. `effective_gov_store` passed to `.datom_build_init_conn()` instead of `store$governance`. `gov_local_path` derivation gated on `!is.null(effective_gov_store)`. Added 5 four-state matrix tests (local backend; path normalization fix for macOS double-slash). Commit `c0f0e29`. Full suite 1648 passing, 0 failures.

- **2026-05-23 (Chunk 2)**: Wired governance.json writers into `datom_init_repo()` and `datom_attach_gov()`. Removed `storage.governance` and `repos.governance` blocks from `project.yaml` writes in both functions. `datom_init_repo()` writes `.datom/governance.json` and includes it in `git2r::add()` when `has_gov && nzchar(store$gov_repo_url)`; mirrors to data storage. `datom_attach_gov()` idempotency check now uses `fs::file_exists(.datom/governance.json) || !is.null(conn$gov_root)`; reads existing URL from `governance.json` (not yaml); commits both `project.yaml` and `governance.json`; mirrors to data storage via `attach_conn`. Updated `test-conn.R`: removed yaml governance block assertions; replaced with governance.json file/field assertions; `create_test_datom_repo()` helper stripped of governance yaml. Full suite 1639 passing, 0 failures.
