# Tasks -- vignettes sets arc

**Branch**: `spec/vignettes-sets-arc`, from `dev` at `5082793`. PRs into `dev`.
**Test baseline**: 4292 (no `R/` change expected; confirm before the PR).
**Order**: 1 -> 2 -> 3 -> 4 -> 5. Transcripts (4) need both vignettes' code final (1, 2) and the
runner (3). One commit per task.

## Where things stand

Spec written and approved 2026-09-26. Task 1 done; next is task 2.

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

- [ ] **2. Rewrite `vignettes/citable-sets.Rmd` (code and prose)**
  - Brief section 5, plus A1-A5, A8, A9.
  - Opens: link to "Starting on S3", same-session note (A4), aim, info box.
  - v1 inputs only; v2 derive + append output + `include_paths = "R"`; use (structure, list,
    history, read v1); refresh with all four domains at month 4 -> v3 (design 2 sequence); access;
    teardown both projects.
  - Reader conns for every fetch.
  - Chunks labelled; output blocks `#> [pending run]`.

- [ ] **3. `dev/e2e-vignettes-s3.R` -- runs the vignettes' own code**
  - Design section 3. Verify offline first that purl + split + special-chunk handling works (a dry
    parse, no network), then hand over.

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
