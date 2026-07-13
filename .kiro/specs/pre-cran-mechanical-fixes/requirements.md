# Pre-CRAN Mechanical Fixes — Requirements

Tracks GitHub issue [#74](https://github.com/amashadihossein/datom/issues/74).

## Goal

Land a batch of contract-neutral defect fixes before the first CRAN submission.
None change the on-disk format, so they are independent of each other and of the
datom-cv1 hashing rework (#72). This issue is recommended to land first.

Line numbers in the issue refer to `main` at issue-creation time; always locate by
function name first since lines drift.

## Items

- **A. Pass the GitHub PAT on all git paths.** `.datom_git_pull()` / `.datom_git_push()`
  accept `pat` but several callers omit it, so private repos fail.
  1. `datom_pull()` (`R/sync.R`) — pass `pat = conn$github_pat`.
  2. `.datom_sync_metadata()` (`R/utils-sha.R`) — pass `pat = conn$github_pat` on both
     pull and push.
  3. `.datom_gov_clone_init()` (`R/utils-gov.R`) — add `pat = NULL` param, pass to
     `.datom_git_credentials()`; caller `datom_clone()` (`R/conn.R`) passes
     `pat = store$github_pat`.
  - Acceptance: `grep -rn "\.datom_git_pull(\|\.datom_git_push(" R/ | grep -v "pat ="`
    returns only the definitions.

- **B. Namespace-safety check drops `session_token` (and `endpoint`).**
  `datom_init_repo()` (`R/conn.R`) builds the check client with only access/secret key;
  STS temporary creds make HeadObject fail and the guard is silently skipped. Pass
  `session_token` (and `endpoint` if available) to `.datom_s3_client()`.

- **C. `.datom_storage_rel_key()` treats the prefix as a regex.** `R/storage.R` uses
  `sub(paste0("^", ns_root), "", full_key)`, which breaks for prefixes with regex
  metacharacters. Replace with a `startsWith()` + `substring()` literal strip.

- **D. Integer overflow for tables > 2 GB in the manifest.**
  `.datom_update_manifest_entry()` (`R/sync.R`) uses `as.integer(m$size_bytes)`, which is
  NA above 2^31. Use `as.numeric()`. Leave `version_count` as integer.

- **E. `datom_clone()` never ensures a local git identity.** After a successful
  `git2r::clone()`, call `.datom_git_ensure_local_identity()` so the first `datom_write()`
  after a clone does not fail on a host with no global git config.

- **F. Upstream tracking never set after `datom_init_repo()` — verify and fix.**
  `git2r::push()` does not set upstream; `.datom_git_pull()` / `.datom_check_git_current()`
  no-op when upstream is NULL. First write a failing test; if it passes on current code,
  close as not-a-bug. Otherwise fix in `.datom_git_push()`: set upstream after a
  successful push (fetch first so the remote-tracking ref exists), wrapped in tryCatch →
  cli_warn.

- **G. Validate `version`/SHA-like inputs (path traversal on local backend).** Add
  `.datom_validate_sha()` to `R/utils-validate.R`; call it in `datom_get_lineage()`
  (`R/query.R`), `datom_parent()` (`R/lineage.R`), and `.datom_read_parquet()` (for
  `data_sha`). 6–64 lowercase hex. NB: coordinates with #72's `.datom_read_parquet()` edits.

- **H. Developer conn cross-check ignores the prefix.** `.datom_get_conn_developer()`
  (`R/conn.R`) compares `project.yaml` root against the store root but not the prefix.
  Add prefix comparison, normalizing both sides with `.datom_normalize_prefix()`.

- **I. Mask AWS secret keys fully.** `.datom_mask_secret()` (`R/store.R`) shows the first 4
  chars — fine for PATs, real entropy for AWS keys. Add `reveal_prefix` param (or mask
  all fully) and reveal nothing for `secret_key` / `session_token`.

- **J. Release housekeeping.**
  - Remove `^NEWS\.md$` from `.Rbuildignore`.
  - LICENSE `YEAR: 2025` → `2026` (and `LICENSE.md`).
  - `SECURITY.md`: fix the dangling `vignette("credentials")` pointer; add a warning that
    `datom_store` objects carry plaintext credentials (avoid `saveRDS()`/`.RData`).
  - `cran-comments.md`: re-run `R CMD check --as-cran` after the above (and after #72),
    refresh text. (Full `--as-cran` rerun depends on #72; do mechanical parts now.)

## Acceptance criteria

- `R CMD check --as-cran`: 0 errors, 0 warnings, 0 notes locally. (Contingent on #72 for
  the final rerun; mechanical fixes here must not introduce new problems.)
- Full test suite passes with the fail-closed network guard active (no
  `DATOM_ALLOW_REAL_NETWORK`).
- New tests for A–I present and passing.
- `grep -rn "\.datom_git_pull(\|\.datom_git_push(" R/ | grep -v "pat ="` returns only the
  definitions.

## Notes

- Contract-neutral: no on-disk format changes.
- Companion to #72; land this first.
