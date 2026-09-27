# Tasks -- vignettes sets arc

**Branch**: `spec/vignettes-sets-arc`, from `dev` at `5082793`. PRs into `dev`.
**Test baseline**: 4292 (no `R/` change expected; confirm before the PR).
**Order**: 1 -> 2 -> 3 -> 4 -> 5. Transcripts (4) need both vignettes' code final (1, 2) and the
runner (3). One commit per task.

## Where things stand

Spec written and approved 2026-09-26. Tasks 1-3 done; next is task 4, the owner's credentialed run.

---

- [x] **1. Rewrite `vignettes/start-on-s3.Rmd` (code and prose)** &nbsp; **[DONE 2026-09-26]**
  - Brief section 4, items 1-8, plus A7, A9, A10.
  - One `secrets` chunk (keyring -> `Sys.setenv`), one `settings` chunk; everything after reads
    those. One CI sentence so `SECURITY.md`'s pointer still lands (AC-S).
  - Names per brief 3.3; every call names its arguments.
  - Layout `study001/imported/datom/`; one line on the `datom/` folder.
  - New "What next" section: continue to citable-sets, or tear down.
  - Teardown: `datom_storage_delete_prefix()` then `datom_repo_delete(confirm = project_imported)`.
  - Every chunk labelled (design 3). Output blocks left as `#> [pending run]` -- **no hand-typed
    output**.

  **DONE RECORD.** Renders; purl emits all 17 labels; tests 4292 unchanged. Choices made beyond the
  brief: (1) dropped the brief's `study` setting, since nothing used it; (2) added `git2r`/`rio`/`keyring`
  to Requirements -- `datom_sync()` fails without `rio` and neither vignette said so; (3) a
  `keyring-setup` chunk (skipped by the runner, like `secrets`); (4) argument naming applies to datom
  calls and `write.csv()`; single-argument base helpers (`Sys.getenv()`, `nrow()`) stay positional, as
  in the brief's own examples; (5) month-3 batch written with a loop over the four domains.

- [x] **2. Rewrite `vignettes/citable-sets.Rmd` (code and prose)** &nbsp; **[DONE 2026-09-26]**
  - Brief section 5, plus A1-A5, A8, A9.
  - Opens: link to "Starting on S3", same-session note (A4), aim, info box.
  - v1 inputs only; v2 derive + append output + `include_paths = "R"`; use (structure, list,
    history, read v1); refresh with all four domains at month 4 -> v3 (design 2 sequence); access;
    teardown both projects.
  - Reader conns for every fetch.
  - Chunks labelled; output blocks `#> [pending run]`.

  **DONE RECORD.** Renders and purls. **Dry-run offline** (local store and bare git remotes standing
  in for S3 and GitHub, vignette chunks v1 -> refresh executed verbatim from purl): v1 4 members, v2
  5 members with `liver_flags` 25 rows, refresh repoints 4 inputs, re-derives, repoints the output,
  one write. Cannot test S3 or the GitHub API -- that is task 4. Found and fixed: `datom_sync()`
  returns the manifest visibly, so every bare call printed a wide data frame after the messages; both
  vignettes now assign it (`synced <-`). Choices: both liver-safety connections are built at setup so
  every read uses a reader; imported reads use `conn_read_imported` throughout, including
  `datom_list()` and `datom_member()`; citable-sets' `teardown` chunk deletes both projects. Example
  data has **no** ALT/AST above the upper limit at any cutoff (max 0.91 x ULN), so `ELEVATED` is all
  `FALSE`; the prose makes no claim about results.

- [x] **3. `dev/e2e-vignettes-s3.R` -- runs the vignettes' own code** &nbsp; **[DONE 2026-09-26]**
  - Design section 3. Verify offline first that purl + split + special-chunk handling works (a dry
    parse, no network), then hand over.

  **DONE RECORD.** Two backends: `local` masks `datom_store_s3()`, `datom_store()` and
  `datom_init_repo()` in the chunks' environment so a folder and bare git repos stand in for S3 and
  GitHub; `s3` is the real run. Chunks are knitted one at a time into
  `../datom-test/vignettes-e2e/transcript-<backend>.md` in the vignettes' own `#>` format, ASCII
  (`cli.unicode = FALSE`). **Local run: SUCCESS**, all 27 chunks plus teardown, storage and clones
  verified empty after. **Failure path checked** on a throwaway copy with one chunk replaced by
  `stop()`: exit 1, transcript kept up to the failing chunk, nothing torn down. The `s3` path is
  **not** exercised -- that is task 4. Found while reading the local transcript, and fixed in the
  vignettes: `datom_history()` printed full 64-character hashes and the committer's name and email,
  and `datom_list_members()` wrapped to three blocks; both now show selected columns, histories with
  `short_hash = TRUE`. Also found: Rscript did not exit after finishing unless stdin was closed, so
  the documented command ends in `< /dev/null`. AC-A6 now names the two substitutions a real run
  forces (bucket name, GitHub account).

- [ ] **4. Credentialed run (owner) and transcripts in**
  - Owner runs the script with `GITHUB_PAT`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
    `DATOM_E2E_BUCKET` set. Agent replaces every `[pending run]` from the transcript (AC-A6).
  - Any output that contradicts the prose: fix the prose, never the output.

- [ ] **5. Close out**
  - `R CMD check --as-cran` 0E/0W (AC-B); test count unchanged.
  - Grep: no `dev/`/`.kiro/` cites, no `conn`/`imported`/`product`/`dev_dir` object names, no
    unnamed arguments (brief section 6).
  - `dev/README.md` completed-phase row; harvest any learning to `dev/engineering-notes.md`.
  - PR into `dev`.
