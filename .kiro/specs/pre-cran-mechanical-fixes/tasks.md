# Pre-CRAN Mechanical Fixes — Tasks

Issue [#74](https://github.com/amashadihossein/datom/issues/74). One item = one chunk = one
commit (code + tests + this file). Run full `devtools::test()` before each commit and record
the count in the commit message.

- [x] **A. PAT plumbing** — threaded `pat` through `datom_pull()`, `.datom_sync_metadata()`
  (pull + push), `.datom_gov_clone_init()` (new `pat` param) + `datom_clone()` caller. Tests
  capture the credentials/pat arg (gov clone, datom_pull, sync_metadata). Acceptance grep
  returns only definitions. Tests 1933.
- [x] **B. session_token in namespace check** — pass `session_token = store$data$session_token`
  to the `.datom_s3_client()` built in `datom_init_repo()`. (No `endpoint` threaded: neither
  `datom_init_repo()` nor the store carries one at this point.) Mock-asserts token passed.
  Tests 1935.
- [x] **C. rel_key literal prefix strip** — replaced regex `sub()` with `startsWith()` +
  `substring()` in `.datom_storage_rel_key()`. Round-trip tests with `"my.data+v1"`,
  `"org/(alpha)"`, `"a.b.c"`, NULL. Tests 1943.
- [x] **D. size_bytes overflow** — `as.numeric()` (not `as.integer()`) for `size_bytes` in
  `.datom_update_manifest_entry()`; `version_count` stays integer. Test with `size_bytes = 3e9`
  asserts entry + summary total stay numeric/non-NA. Tests 1947.
- [x] **E. clone git identity** — call `.datom_git_ensure_local_identity()` after the data-repo
  `git2r::clone()` in `datom_clone()`. Test clones under an empty HOME/XDG (no gitconfig) and
  asserts local `user.name`/`user.email` are set. Tests 1949.
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
