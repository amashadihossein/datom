# Requirements -- vignettes sets arc

**Branch**: `spec/vignettes-sets-arc`, cut from `dev` at `5082793`. **PRs into `dev`, not `main`.**
**Scope**: `vignettes/start-on-s3.Rmd`, `vignettes/citable-sets.Rmd`, one new dev script. No `R/`
change.

## Source

The owner's brief is `handoff/vignette-spec-start-on-s3-citable-sets.md` (written with Claude Code,
2026-09-26). **It is the requirements document** and is not restated here. Its sections 2-6
(principles, conventions, per-vignette changes, acceptance checks) apply as written, **except where an
amendment below replaces them**. Amendments were agreed with the owner on 2026-09-26 after the brief
was checked against the code.

## Goal

The two vignettes read as one walk: onboard a study's data to S3 (start-on-s3), then build a
versioned, citable collection of the inputs and the outputs derived from them, then use it and
refresh it when data moves (citable-sets). A new user can follow them without jargon or side remarks.

## Amendments to the brief

| # | Replaces | Amendment |
|---|---|---|
| A1 | 5.5, 5.7 | The derivation script defines a **function** that takes the set in hand, not one that reads the set from storage. Refresh order: move inputs -> derive -> move output -> **one** write (v3). Reason: a script that re-reads the stored set on refresh derives from the old inputs, with no error. |
| A2 | 5.7 last bullet | "The set never mixes new inputs with an old output" is stated as the result of the write-once order, not as something datom enforces. |
| A3 | 5.7 first bullet | The month-4 cut refreshes **all four** domains (`dm`, `ex`, `lb`, `ae` at `2026-04-28`), not `lb` alone. Reason: `lb` alone covers 31 subjects while `dm` still has 25, so `liver_flags` silently loses 6. |
| A4 | 5.0, 6 ("runs on the state start-on-s3 leaves") | citable-sets says up front that it continues **in the same R session** as start-on-s3. No "starting fresh" rebuild block. |
| A5 | 5.5 first bullet | The derivation script is shown in the vignette as a code chunk headed `R/derive_liver_flags.R`; the reader saves it at that path inside `workdir_liver_safety`. Not shipped in `inst/`. |
| A6 | 4.9, 5.11, 6 ("outputs match a real run") | Every output block is copied from one credentialed run of a new dev script that **executes the vignettes' own code**. The owner runs it; the agent has no credentials. |
| A7 | 5.11 third bullet | Sync output: each synced table prints **two** lines -- `Wrote "dm" (full): "<version>"` from the write, then `"dm" synced (changed).` Both appear in transcripts. |
| A8 | 5.5 "Add the output" | At v2 the output member is appended with `x$members <- c(x$members, list(datom_member(...)))`. `datom_add_member()` accepts only a draft from `datom_assemble_set()`, not a set read back. Added to API follow-ups. |
| A9 | 5.9 | Teardown keeps a corrected line: `datom_storage_delete_prefix()` removes only datom's own folder under the prefix, and **asks for no confirmation**. |
| A10 | 3.5 | `governance = NULL` is **omitted** everywhere (it is the default). |

## Additional acceptance checks

On top of the brief's section 6:

- [ ] AC-A1: the refresh section derives from the in-session, already-updated set, and writes the set
      exactly once after both inputs and output have moved.
- [ ] AC-A3: the month-4 cut writes all four domains and the sync shows four changed.
- [ ] AC-A6: every `#>` block in both vignettes is traceable to the captured transcript of one run.
      Allowed edits: truncating long paths or wide tables with `...`. **No value is changed.**
- [ ] AC-S: `SECURITY.md` still points at start-on-s3 for credential handling, so the vignette still
      covers keychain, environment variables and CI (one sentence for CI: set the variables, skip the
      keyring block).
- [ ] AC-L: neither vignette cites `dev/` or `.kiro/` (neither ships).
- [ ] AC-B: `R CMD check --as-cran` builds both vignettes with 0 errors / 0 warnings; test count is
      unchanged (no `R/` change).

## API follow-ups (out of scope, extends brief section 7)

- A verb to add a member to a set read back (today only drafts take `datom_add_member()`).
