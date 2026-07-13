# Pre-CRAN Mechanical Fixes — Tasks

Issue [#74](https://github.com/amashadihossein/datom/issues/74). One item = one chunk = one
commit (code + tests + this file). Run full `devtools::test()` before each commit and record
the count in the commit message.

- [x] **A. PAT plumbing** — threaded `pat` through `datom_pull()`, `.datom_sync_metadata()`
  (pull + push), `.datom_gov_clone_init()` (new `pat` param) + `datom_clone()` caller. Tests
  capture the credentials/pat arg (gov clone, datom_pull, sync_metadata). Acceptance grep
  returns only definitions. Tests 1933.
- [ ] **B. session_token in namespace check** — pass `session_token` (+ `endpoint`) to the
  `.datom_s3_client()` built in `datom_init_repo()`. Mock-assert token passed.
- [ ] **C. rel_key literal prefix strip** — replace regex `sub()` with `startsWith()` +
  `substring()`. Round-trip test with `"my.data+v1"`.
- [ ] **D. size_bytes overflow** — `as.numeric()` in `.datom_update_manifest_entry()`. Test
  `size_bytes = 3e9`.
- [ ] **E. clone git identity** — `.datom_git_ensure_local_identity()` after `git2r::clone()`
  in `datom_clone()`. Test with temp HOME, no gitconfig.
- [ ] **F. upstream tracking (verify-first)** — failing test first; fix in `.datom_git_push()`
  or close as not-a-bug with a note here.
- [ ] **G. SHA validator** — add `.datom_validate_sha()`; call in `datom_get_lineage()`,
  `datom_parent()`, `.datom_read_parquet()`. Traversal-string tests. (Coordinates with #72.)
- [ ] **H. developer conn prefix cross-check** — add prefix comparison in
  `.datom_get_conn_developer()`, normalized. Wrong-prefix store rejected.
- [ ] **I. mask AWS secrets fully** — `reveal_prefix` param on `.datom_mask_secret()`; print
  methods pass FALSE for `secret_key`/`session_token`. Update print tests.
- [ ] **J. release housekeeping** — `.Rbuildignore` NEWS line, LICENSE year, SECURITY.md
  pointer + plaintext-credentials warning, cran-comments refresh (full `--as-cran` rerun
  contingent on #72).

## Spec completion
- [ ] Run full suite + `R CMD check` (as-cran mechanical sanity); harvest learnings; update
  `dev/README.md`; PR with `Closes #74`.
