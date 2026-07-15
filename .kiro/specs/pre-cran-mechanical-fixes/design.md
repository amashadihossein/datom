# Pre-CRAN Mechanical Fixes — Design

Issue [#74](https://github.com/amashadihossein/datom/issues/74). Contract-neutral fixes;
no on-disk format change. Each item is independent and lands as its own chunk/commit.

## Read-first context

- `R/utils-git.R` — `.datom_git_pull(path, pat)`, `.datom_git_push(path, pat, pull_first)`,
  `.datom_git_credentials(remote_url, pat)`, `.datom_git_ensure_local_identity(repo)`.
  Both pull/push already accept `pat`; the fix is caller-side plumbing (A) and an upstream
  set after push (F).
- `R/utils-validate.R` — home for the new `.datom_validate_sha()` (G). Existing style: guard
  clauses + `cli::cli_abort`.
- `R/storage.R` — `.datom_storage_rel_key()` (C) uses `sub(paste0("^", ns_root), ...)`.
- `R/store.R` — `.datom_mask_secret()` (I), print methods.
- `R/conn.R` — `datom_init_repo()` namespace check client build (B), `datom_clone()` (E),
  `.datom_get_conn_developer()` root/prefix cross-check (H).
- `R/sync.R` — `datom_pull()` (A), `.datom_update_manifest_entry()` (D).
- `R/utils-sha.R` — `.datom_sync_metadata()` pull/push (A).
- `R/utils-gov.R` — `.datom_gov_clone_init()` (A).
- `R/query.R` — `datom_get_lineage()` (G).
- `R/lineage.R` — `datom_parent()` (G).
- `R/read_write.R` (or wherever `.datom_read_parquet()` lives) — (G).
- `R/ref.R` — `.datom_normalize_prefix()` (H).

## Per-item design

### A. PAT plumbing
Pure caller plumbing — the credential helper already handles NULL. Add `pat = conn$github_pat`
(or `store$github_pat`) at each omitting call site. `.datom_gov_clone_init()` gains a
`pat = NULL` param threaded to `.datom_git_credentials()`; `datom_clone()` passes
`store$github_pat`.
Invariant: `.datom_git_credentials()` returns NULL when `pat` is NULL/empty, so behaviour
for public repos and existing tests is unchanged.
Tests: stub `git2r::fetch`/`clone` with `mockery::stub`, capture the `credentials` argument,
assert non-NULL when a PAT is present.

### B. session_token in namespace check
`datom_init_repo()` builds a temporary check client via `.datom_s3_client()` with only
access/secret key. Add `session_token = store$data$session_token` (and thread `endpoint` if
already resolvable at that point). Confirm the exact field path on `store$data` while editing.
Test: mock `.datom_s3_client`, assert it receives the session token when the store carries one.

### C. rel_key literal strip
Replace `sub(paste0("^", ns_root), "", full_key)` with:
```r
if (startsWith(full_key, ns_root)) substring(full_key, nchar(ns_root) + 1L) else full_key
```
Test: prefix `"my.data+v1"` round-trips list → rel_key → build_storage_key.

### D. size_bytes overflow
In `.datom_update_manifest_entry()`, change `as.integer(m$size_bytes %||% 0L)` to
`as.numeric(m$size_bytes %||% 0)`. Leave `version_count` integer.
Test: fake metadata.json with `size_bytes = 3e9`; assert manifest entry + summary total are
numeric and not NA.

### E. clone git identity
After successful `git2r::clone(...)` in `datom_clone()`, add
`.datom_git_ensure_local_identity(git2r::repository(as.character(path)))`.
Test: clone from a local bare fixture under `withr::local_envvar` + temp HOME with no
gitconfig; assert local `user.name` is set.

### F. upstream tracking (verify-first)
Write a failing test: init against a local bare remote, push via `.datom_git_push()`, assert
`git2r::branch_get_upstream(git2r::repository_head(repo))` is non-NULL. If it already passes,
close item F as not-a-bug with a spec note. If it fails, fix in `.datom_git_push()` after a
successful push: if upstream is NULL, `git2r::fetch(repo, remote_name, credentials = cred)`
then `git2r::branch_set_upstream(repository_head(repo), paste0(remote_name, "/", branch))`,
wrapped in `tryCatch` → `cli_warn` (upstream failure must not fail the push).

### G. SHA validator
Add to `R/utils-validate.R`:
```r
.datom_validate_sha <- function(x, arg = "version") {
  if (!is.character(x) || length(x) != 1L || is.na(x) ||
      !grepl("^[0-9a-f]{6,64}$", x)) {
    cli::cli_abort("{.arg {arg}} must be 6-64 lowercase hex characters.")
  }
  invisible(x)
}
```
Call in `datom_get_lineage()` (when `version` non-NULL), `datom_parent()`, and
`.datom_read_parquet()` (for `data_sha`). `.datom_resolve_version()` prefix matching stays
untouched — 6-char minimum covers short prefixes.
Tests: `"../../x"` and other traversal strings abort; valid short + full SHAs pass.

### H. developer conn prefix cross-check
In `.datom_get_conn_developer()`, alongside the existing root comparison add a prefix
comparison, normalizing both sides with `.datom_normalize_prefix()` so `NULL`/`""` compare
equal. Same error style as the root mismatch.
Test: two projects, same root, different prefixes; connecting with the wrong-prefix store
aborts.

### I. mask AWS secrets fully
`.datom_mask_secret()` currently reveals the first 4 chars. Add `reveal_prefix = TRUE`
parameter; the print methods pass `reveal_prefix = FALSE` for `secret_key`/`session_token`
(PAT keeps prefix — `ghp_` is public). Update print-method tests.

### J. release housekeeping
- `.Rbuildignore`: remove the `^NEWS\.md$` line.
- `LICENSE` + `LICENSE.md`: `YEAR: 2025` → `2026`.
- `SECURITY.md`: repoint the `vignette("credentials")` link (article no longer ships) to the
  pkgdown article / getting-started credentials section; add a plaintext-credentials warning
  (avoid `saveRDS()`/`.RData` of stores).
- `cran-comments.md`: refresh after the above + #72. Full `--as-cran` rerun on all four
  environments is contingent on #72; note that dependency rather than block on it.

## Invariants / must-never

- No behaviour change for public (no-PAT) repos — `.datom_git_credentials()` NULL contract
  preserved (A, F).
- No on-disk format change anywhere (contract-neutral).
- Secrets never printed unmasked; AWS secret/session fully masked after I.
- Upstream-set failure must never fail a push (F).

## Correctness properties to test

- A: credential object non-NULL when PAT present on every patched call site.
- C: prefixes with regex metacharacters round-trip.
- D: >2GB size stays numeric, non-NA, propagates to summary total.
- E: local `user.name` set after clone on a no-gitconfig host.
- F: upstream non-NULL after init+push (or documented not-a-bug).
- G: traversal strings rejected; valid hex accepted.
- H: wrong-prefix store rejected at developer conn.
- I: AWS secret/session fully masked in print output.

## Pathway impact

None. No metadata schema, storage layout, governance ref, lineage, access control, role
resolution, migration, or decommission route changes. (Record: "no pathway impact".)
