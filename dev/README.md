# datom Development Hub

## Workflow model (read first): spec = phase

A unit of multi-step work is a **Kiro spec** under `.kiro/specs/{feature}/`:
`requirements.md` (goal + acceptance), `design.md` (context, invariants, correctness
properties), `tasks.md` (the chunk breakdown + status). **The spec replaces the legacy
`dev/phase_{n}_{name}.md` phase doc.**

Everything in this document still applies — just remap the terms:

| Legacy term (used below) | Now |
|---|---|
| phase doc `dev/phase_*.md` | the spec `.kiro/specs/{feature}/` |
| Chunks table / Progress Log | `tasks.md` (checkboxes) + commit history |
| Active Phases | Active Specs |
| "delete the phase doc" on completion | **specs persist — never deleted** |

A "chunk" = one task (or a small related group) in `tasks.md` = one commit. All branch,
test-before-commit, chunk-checkpoint, and review discipline below is unchanged. Works the
same in Kiro (native specs) and Copilot (read/maintain the same `.kiro/specs/` files).

## Documentation Hierarchy

This folder contains all development documentation following a hierarchical chain:

```
.github/copilot-instructions.md     ← Entry point for AI/developers
         ↓
dev/README.md                       ← This file: navigation hub
         ↓
dev/datom_specification.md           ← Design spec (authoritative, evolves slowly)
dev/datom_pathways.md               ← Canonical route map across metadata/gov/storage/access
dev/daapr_architecture.md           ← Ecosystem context
dev/datomanager_scope.md             ← datomanager companion package scope (gov lifecycle + migration)
dev/datomanager_overview.md          ← datomanager access enforcement design (roles, grants, IAM; forward-looking)
         ↓
.kiro/specs/{feature}/              ← Active work: requirements.md, design.md, tasks.md
```

## Documentation Lifecycle

### Units of Work (Specs)

A unit of work is a **Kiro spec** under `.kiro/specs/{feature}/` (see Workflow model at top):

1. **Created** when starting a feature (requirements → design → tasks)
2. **Updated continuously** as development proceeds (task status in `tasks.md`)
3. **Completed** when all tasks are checked off and acceptance criteria met
4. **Persists**: the spec stays as durable documentation; additional durable learnings → spec/architecture docs and `dev/engineering-notes.md`

### What Goes Where

| Content Type | Location | Lifecycle |
|--------------|----------|-----------|
| Coding style, conventions | `.github/copilot-instructions.md` | Permanent |
| Architecture, API design | `dev/datom_specification.md` | Permanent, evolves |
| Canonical lookup/traversal routes | `dev/datom_pathways.md` | Permanent, evolves with schema/routing changes |
| Ecosystem context | `dev/daapr_architecture.md` | Permanent |
| Current work, tasks, decisions | `.kiro/specs/{feature}/` | Persists |
| Implementation gotchas discovered | `dev/engineering-notes.md` | Persists |

## Branching During CRAN Submission

> **STATUS 2026-09-08 -- 0.1.1 IS RELEASED; 0.1.2 IS SUBMITTED AND AWAITING CRAN.** So the freeze
> still holds, for the same reason it always did: if CRAN asks for another fix, `main` must reflect
> exactly what they received. Verified state, so nobody has to re-derive it: `main` is at `cb60007`,
> which is the commit submitted as 0.1.2; `dev` (`17a84ce`, in the `../datom-cran-depends` worktree) is
> level with it; **`spec/datom-sets` is now AHEAD of both** -- it took the 0.1.2 fix via
> `main -> dev -> spec/datom-sets` and has since accumulated Task 6's work, so "level with `main`" is
> no longer true of it and a cold reader should take its head from `git log` rather than from this
> line, which only claims to track `main` and `dev`;
> tag `v0.1.1` exists on the remote at `1eaee26` with its GitHub release published; **no `v0.1.2` tag
> or release yet, and there must not be one until CRAN accepts** -- the tag is created by the release
> step, not by hand. `CRAN-SUBMISSION` for 0.1.2 sits untracked in the **`../datom-cran-fix`**
> worktree, which is therefore the checkout that must publish the release and **must not be removed
> before then**. The 0.1.1 acceptance ran in the documented order (publish first, then merge), and
> the ordering hazards in "`CRAN-SUBMISSION`" below are what made that necessary -- they apply
> unchanged to 0.1.2.
>
> **What 0.1.2 was.** CRAN's check farm reported `tests` ERROR on four Linux flavors after accepting
> 0.1.1: test fixtures hardcoded `refs/heads/master` when pushing to a throwaway remote, and
> `git2r::init()` honours git's `init.defaultBranch`, so on a machine configured for any other name
> the fixture pushed a branch that had never been created. 26 failures, all the same error, all
> during setup. Test-only -- no `R/` file changed. Issues
> [#106](https://github.com/amashadihossein/datom/issues/106) and
> [#108](https://github.com/amashadihossein/datom/issues/108), PRs #107, #109, #110. **The step 3
> route below (fix on `main`, rebuild, resubmit the same version) did NOT apply**, because a released
> version cannot be resubmitted -- it needed a patch bump, which is now the precedent for any
> post-acceptance defect.
>
> **Three tools silently misbehave in a git worktree, where `.git` is a FILE rather than a
> directory.** All three bit during the 0.1.2 fix and all three fail without saying anything, so
> check for them rather than trusting a green run: `R CMD build` sweeps `.git` into the tarball
> (fixed -- `^\.git$` is now in `.Rbuildignore`); `devtools::submit_cran()` skips writing
> `CRAN-SUBMISSION` entirely, because `devtools:::uses_git()` is a directory test, and it also
> swallows its own "don't forget to tag this release" reminder (the 0.1.2 record in
> `../datom-cran-fix` was reconstructed by hand from the built tarball's timestamp and `main`'s head);
> and the `.gitignore` rule for `CRAN-SUBMISSION` exists **only on `spec/datom-sets`**, so on a
> `main` checkout the artifact is untracked and unignored -- never `git add .` there. See
> `dev/engineering-notes.md`.
>
> **OWNER INTENT, stated 2026-09-01: `dev` becomes PERMANENT.** The target pattern is
> `feature -> dev -> main`, with `dev` as the testing ground / alpha source rather than a
> submission-freeze device. So **"delete the `dev` branch" in Acceptance step 4 is ON HOLD** -- do not
> run it. The rest of this section still describes how things work today and stays until the new
> pattern is designed and written down (release cadence, what `main` means when it is no longer the
> only long-lived branch, and where pkgdown deploys from are the parts that need deciding, not just
> the branch names).
>
> **WHAT IS ON `dev` AND NOT ON `main` CHANGED IN KIND ON 2026-09-21, and the next release plan has to
> account for it.** Until then it was documentation-only: a derived-columns section in
> `vignettes/design-version-shas.Rmd` (the only one that ships in the package), this branching section,
> a 3-line specification correction, a 1-line conventions edit, and the 0.1.2 bookkeeping in this
> block. `dev` now also carries the **whole `datom-sets` feature** -- thirteen new exports, a second
> artifact kind, and a **breaking** change to the manifest's artifact list, plus the
> forward-compatibility machinery that makes that rename survivable. So `dev` is no longer a
> documentation delta ahead of a released `main`; it is the next release. Two consequences worth
> writing down rather than rediscovering: the version number on `dev` still says 0.1.2, which is what
> CRAN holds, so whoever prepares the next submission bumps it and writes the NEWS heading that the
> development block currently lacks; and the breaking manifest change means the release notes' upgrade
> warning is aimed at a real population -- everyone sharing a repo has to upgrade before anyone writes
> to it.
>
> **`main` is protected and takes only PRs**, enforced for admins, with `ubuntu-latest (release)` and
> `pkgdown` as required status checks (strict). This was verified rather than assumed during the
> 0.1.2 fix, so a "commit the fix directly on `main`" reading of step 3 below is not available in
> practice -- use a short-lived branch and a PR. A related permission limit worth knowing before
> planning any CI change: pushing anything under `.github/workflows/` needs a token scope that also
> grants the ability to rewrite CI, and CI runs with repository secrets, so that scope was
> deliberately **not** acquired. Workflow edits go through GitHub's web editor, which authenticates
> with the browser session instead (that is how #109 landed).

When a version has been submitted to CRAN and is awaiting acceptance, we freeze
`main` and develop on a long-lived `dev` branch.

### Why

If CRAN requests a surgical fix, we need `main` to reflect exactly what was
submitted so the fix can be applied cleanly and resubmitted without dragging in
unrelated work. Meanwhile, feature development continues on `dev` as the
single aggregation point.

### Branch roles

| Branch | Purpose | Who merges into it |
|--------|---------|-------------------|
| `main` | Frozen at the submitted state. pkgdown deploys from here. `install_github()` installs from here. | Only: (a) CRAN-requested fixes, or (b) `dev` merge after acceptance. |
| `dev` | Aggregator for ongoing work while submission is in flight. | Feature branches PR into `dev`. |
| `issue-{N}-*` / `spec/*` | Feature branches, same as before. | PR into **`dev`** (not `main`) during submission freeze. |

### Workflow

1. **Normal development (no pending submission):** feature branches off `main`,
   PR into `main`. The `dev` branch does not exist or is deleted.

2. **Submission pending:**
   - `dev` is created off `main` at the submitted commit.
   - Feature branches branch off `dev` and PR into `dev`.
   - `main` is not touched unless CRAN requests a fix.

3. **CRAN requests a fix:**
   - Fix is committed directly on `main` (or via a short-lived branch off
     `main`).
   - Rebuild tarball from `main`, resubmit.
   - Merge the fix into `dev` so they don't diverge:
     `git checkout dev && git merge main`.

4. **Acceptance:**
   - **Publish the release FIRST, before merging** -- `usethis::use_github_release()` from a
     `main` checkout that still has the `CRAN-SUBMISSION` artifact beside it. Order matters:
     see "CRAN-SUBMISSION" below for why doing it after the merge can silently tag the wrong
     commit.
   - Merge `dev` into `main`: `git checkout main && git merge dev`.
   - ~~Delete the `dev` branch (local + remote).~~ **ON HOLD as of 2026-09-01 -- do not run this.**
     See the STATUS block at the top of this section: `dev` is becoming permanent.
   - ~~Resume normal workflow (feature branches off `main`).~~ Same hold: the target is
     `feature -> dev -> main`.

### Constraints

- **pkgdown** always deploys from `main`. Vignette previews during development
  require a local build (`pkgdown::build_site()`).
- **GitHub default branch** stays `main` — this is what `install_github()`
  resolves and what new clones check out.
- **`CRAN-SUBMISSION`** is an untracked, transient artifact -- see the next section. (An earlier
  version of this line said it "on `main` records the submitted SHA", which was never true: the
  file has never been committed on any branch.)

### `CRAN-SUBMISSION`

**What it is.** `devtools::submit_cran()` writes it next to `DESCRIPTION`, recording the version,
the submission timestamp, and the SHA of the commit that was submitted. It is a **handoff
artifact**, not a record meant to live in the repo: `usethis::use_github_release()` reads it to
populate the release notes and **deletes it on success**. The durable record of a submission is
therefore the **GitHub release and its tag**, which point at the submitted commit.

**Rules.**

- **Never committed.** It is in `.gitignore` (and `.Rbuildignore`), so no branch can sweep it into
  a commit via `git add .`. Nothing is lost by that, because it was never tracked in the first
  place and the release is the real record. Deliberate exception if one is ever wanted:
  `git add -f`.
- **Written only by `devtools::submit_cran()` run from `main`**, which is the only branch whose
  tree matches what CRAN received. Never hand-edited, never regenerated from a feature branch.
- **Never deleted by hand** while a submission is pending -- `use_github_release()` removes it as
  part of publishing.

**Two hazards, both silent.**

1. **Absent file means "HEAD is the submitted state".** usethis says so explicitly: with no
   `CRAN-SUBMISSION` present it assumes the current SHA, version, and NEWS *are* the submitted
   ones. Run `use_github_release()` after merging `dev` into `main` and the release names the
   **merge commit** rather than the commit CRAN actually received. Hence the ordering in
   Acceptance step 4: publish, then merge.
2. **The artifact lives in whichever working directory `submit_cran()` ran in**, and that is not
   necessarily where `main` is checked out later. If it is missing at release time, check other
   worktrees (`git worktree list`) before assuming it was never created -- and cross-check the SHA
   against the record below.

**Record for the pending 0.1.1 submission** (belt to the artifact's braces, since the artifact
is untracked by design and this file is not):

| Version | Submitted (UTC) | SHA | Artifact location |
|---|---|---|---|
| 0.1.1 | 2026-08-21 23:39:19 | `1eaee2660f9d4d19d0d5fec979bba4617a1bc776` (`main` head, "Declare Depends: R (>= 4.1.0) explicitly (#99)") | consumed 2026-09-07 by `use_github_release()`; durable record is tag `v0.1.1` |
| 0.1.2 | 2026-09-08 04:11:41 | `cb60007f59c5274b8f816c6422ee5ca86e0ac5f3` (`main` head, "Correct the check-results section of cran-comments for 0.1.2 (#110)") | the `../datom-cran-fix` worktree, uncommitted -- **reconstructed by hand**, see below |

Add a row here at each submission. It costs one line and it is the thing that makes the release
verifiable if the artifact goes missing.

**It went missing for 0.1.2, which is why this table now earns its keep.** `submit_cran()` ran from a
git **worktree**, and the step that writes the artifact (`devtools:::flag_release()`) begins
`if (!uses_git(pkg$path)) return(invisible())` where `uses_git()` tests for a `.git` **directory**.
In a worktree `.git` is a file, so the step exited silently -- no artifact, and no "don't forget to
tag this release" reminder either, since that message sits one line above the write in the same
function. The submission itself was unaffected; only the local bookkeeping was skipped. The 0.1.2
record was rebuilt from `main`'s head (verified unmoved and level with `origin/main`) and the built
tarball's mtime in the R temp directory, then confirmed parseable by `usethis:::get_release_data()`.
**Check for the artifact after every `submit_cran()` run from a worktree**, or run the submission
from a normal clone instead.

---

## Current Development State

### Active Specs

Units of work are **Kiro specs** under `.kiro/specs/{feature}/` (see Workflow model at top).

| Spec | Started | Status | Location |
|------|---------|--------|----------|
| sets-release-readiness | 2026-09-21 | **SPEC WRITTEN, NOTHING STARTED.** Issue [#114](https://github.com/amashadihossein/datom/issues/114). `datom-sets` shipped the feature and met every one of its acceptance criteria; this spec closes the distance between "correct" and "a person can find it, try it, and trust it". **Three gaps, and they chain.** (1) **No credentialed end-to-end run covers sets.** `dev/e2e-sets.R` is offline by design and gets there by hand-building the connection and writing `.datom/project.yaml` directly -- so for sets, repo creation, `datom_get_conn()`, the connection-time config gate, `ref.json` resolution and a real storage-only S3 reader have never run. (2) **Nothing a user installs explains what a set is for.** `^dev$` is Rbuildignored, so the specification and pathways documents written for the last spec **are not in the package**; an installed datom offers man pages for all thirteen verbs, NEWS, and six vignettes that never mention sets. There is no narrative route in. (3) **The NEWS development block is 792 lines and 7,700 words, against 48 for the last real release** -- so the two upgrade-critical items, the `artifacts` rename and the writer refusals, are buried in exactly the document a reader consults before upgrading. **The order is fixed rather than preferred**: the credentialed run produces transcripts the vignette shows, and the vignette is the destination NEWS needs before anything can be cut from it -- cutting first deletes the only copy of an explanation. **The failure mode here differs from its predecessor's**: that spec could ship a wrong guard, this one can ship a document that is correct and useless, so two requirements exist purely against that -- every vignette output block must come from a run somebody watched (chunks are `eval = FALSE`, so nothing verifies them), and nothing may be removed from NEWS without a named destination. **One decision already taken that is worth knowing**: `sandbox_up()` gains `mode`/`set` passthrough so the sandbox tooling can create a product repo at all -- today it cannot, which means the tire-kicking the owner asked for is not currently possible interactively. **Out of scope**: any change to set behaviour, the version assignment and release heading, and `main`. | [.kiro/specs/sets-release-readiness/](../.kiro/specs/sets-release-readiness/) |

The `datom-sets` spec completed 2026-09-21 -- see Completed Phases below. Specs persist as
documentation under `.kiro/specs/`; they are not deleted on completion, so the full requirements,
design and task records for anything listed there are still on disk.

### Drafts (queued, not active)

| Draft | Doc | Captured | Notes |
|-------|-----|----------|-------|
| datomanager Phase 19: gov_migrate_data() | [draft_managed_migration.md](draft_managed_migration.md) | 2026-05-02 | Governed migration verb. Requires gov; atomic copy + `ref.json` switch + `migration_history.json` record; cross-backend s3<->local. datom Phase 22 (storage extension API) shipped 2026-06-10 -- the six `datom_storage_*` / `datom_repo_*` exports are the stable platform surface Phase 19 calls into. datomanager package scaffold is the remaining prerequisite. See draft for Phase 19 spec and acceptance criteria. |

### Completed Phases

| Phase | Completed | Tests | Summary |
|-------|-----------|-------|---------|
| Spec: datom-sets | 2026-09-21 | 4292 | Issue [#89](https://github.com/amashadihossein/datom/issues/89): **a second artifact kind.** A **set** is a versioned, citable list of pointers at exact versions of other artifacts plus free-text labels, so "product v47" is one string that resolves to the fifty inputs it was built from, each pinned. A set stores no data of its own, and reading one needs access to the set's project only -- which is what lets a fifty-member product be citable by someone entitled to none of its members. **Thirteen new exports**: `datom_member()`, `datom_write_set()`, `datom_get_set()`, `datom_assemble_set()`, `datom_add_member()`, `datom_fetch_member()`, `datom_list_members()`, `datom_structure_members()`, `datom_update_members()`, `datom_remove_members()`, `datom_repo_commit()`, `datom_repo_push()`, `datom_storage_read_json()`, plus three print methods. **Identity is its own regime, `datom-sv1`** -- a hash over the parsed payload with no serializer in the identity path, every collection sorted and deduped in C-locale order, no Unicode normalization, no numeric primitive, and a standalone reference script (`dev/datom_sv1_reference.R`) the package is tested byte-for-byte against on x86_64 and arm64. Stored-byte integrity is `document_sha`, a set's counterpart to `parquet_sha`, and a missing one is an error rather than a skipped check. **One breaking change**: the manifest's artifact list moved from `tables` to `artifacts` and every entry carries a `kind`, one namespace typed by kind rather than two sibling nodes -- because storage keys are `{name}/...` whatever the artifact is, so two artifacts sharing a name would write the same objects. Existing repos convert as they are read, with no manual migration; the exposure is **discovery, not access**, since the data path never reads the manifest. **The forward-compatibility machinery that made the rename survivable shipped with it**, and is the part most likely to outlive the sets themselves: every datom-owned document declares a `schema_version`; a build meeting a document too new for it refuses rather than reporting an empty repo; a write into a repo this build cannot account for is stopped at the door, above the first hash and the first file write, so a refusal leaves nothing half-written; a field this build cannot classify survives a write at four levels instead of being deleted; and a manifest whose artifact list cannot be reached is **rebuilt from storage with one warning** for a reader while a writer is refused -- the reads-limp / writes-stop split, same evidence and opposite responses. Identity hashing became an allowlist ([#100](https://github.com/amashadihossein/datom/issues/100)) with every existing hash byte-identical, which is what made adding a field affordable at all. **Also shipped**: a `mode: product` repo can commit the caller's own code and `renv.lock` in the **same commit** as a set write, so checking out a version yields the pointers plus what produced them; every version now records the commit that produced it, in the storage copy of its history only, derived and never authored; a stored `project` name now comes from the repo's own config rather than from a connection label; validation branches on kind and can restore a set's payload from git when storage has lost it. **Two exports land the ability to edit a set that already exists**, neither of which touches a stored document -- they hand the edited set back, and both append to one record of what changed so a chained edit produces one commit message naming all of it. **Coverage standard**: all 37 behavioural acceptance criteria were watched going red on a deliberate break of the behaviour they claim, 81 probes in five batches, with the table of what-was-broken/what-reddened kept in the task record; `dev/check-spec.R` now fails when a criterion is named nowhere under `tests/`. That sweep found one shipped test that could not fail four separate ways, which is now the canonical case in `dev/engineering-notes.md`. The criteria list was then **re-derived by an independent session given the requirements and nothing else**, and matched. New `dev/e2e-sets.R`, 51 asserted claims, fully offline, walking assemble -> write -> read with no clone -> an input moves -> repoint and drop -> write again; its exit code verified by breaking the package. Tests 2460 -> **4292**, `R CMD check --as-cran` 0/0/0 with examples, tests and vignettes run. **Pathway impact: yes** -- four new route cards and the read route gained a kind branch. Deferred with issues: [#111](https://github.com/amashadihossein/datom/issues/111), [#112](https://github.com/amashadihossein/datom/issues/112). | [.kiro/specs/datom-sets/](../.kiro/specs/datom-sets/) |
| Spec: datom-cv1-identity | 2026-07-26 | 2443 | Issue [#72](https://github.com/amashadihossein/datom/issues/72): **table identity redefined** as a canonical hash of a table's *values* (`datom-cv1`) instead of a digest of its parquet bytes -- serialization-based identity moved with the writer, so an `arrow` upgrade minted spurious versions. **Changes the on-disk contract; no migration path (pre-release).** Three SHAs now: `data_sha` (content identity, also the storage address), `metadata_sha` (the version), `parquet_sha` (stored-object integrity, verified on read *before* parsing). `original_file_sha` is file provenance, not identity. New `R/hashable.R` holds the single column classifier + single recourse source that the hash gate, the encoder, the new export `datom_check_hashable()`, and the vignette recourse table all bind to, so advice cannot drift from behavior. Also: `metadata_sha` field ordering switched to `method = "radix"` (locale-independent) with `parquet_sha`/`column_hashes`/`size_bytes` added to the volatile set; `column_hashes` persisted as an ordered per-column index (`data_sha` re-derivable from it, and the anchor for #73's `datom_diff`); full-history version dedup (no duplicate `version`, so `datom_read(version=)` can never be ambiguous); `parquet_sha` carry-forward on `metadata_only` and reuse-without-overwrite on revert-to-older; ingestion allowlist for `datom_sync` (flat tabular only); `file_sha` -> `original_file_sha` nomenclature sweep. **Deliberate narrowings** (recorded in NEWS): list/exotic columns refused with recourse, `.json`/`.rds` no longer imported directly, internal `sort_columns`/`sort_rows` removed (sorting needs a locale-dependent collation order). 452 new tests including the S1-S6 identity-contract integration suite on a zero-mock local-backend fixture (`test-identity-contract.R`) and 17 tagged correctness properties. `R CMD check --as-cran` 0E/0W/1 pre-existing NOTE. Vignettes `design-version-shas` + `getting-started` rewritten; new offline walkthrough `dev/e2e-cv1-identity.R`. **Pathway impact:** read route gains an integrity gate, no new lookup -- `dev/datom_pathways.md` updated. |
| Spec: pre-cran-mechanical-fixes | 2026-07-14 | 1991 | Issue [#74](https://github.com/amashadihossein/datom/issues/74): ten contract-neutral pre-CRAN defect fixes (A-J), no on-disk format change. **A** thread `pat` through all git pull/push callers (`datom_pull`, `.datom_sync_metadata`, `.datom_gov_clone_init` + `datom_clone`) so private repos work. **B** pass `session_token` to the `datom_init_repo()` namespace-check S3 client (STS creds no longer skip the "namespace occupied" guard). **C** `.datom_storage_rel_key()` strips the prefix literally (`startsWith`/`substring`), fixing regex-metachar prefixes. **D** `size_bytes` via `as.numeric()` (>2GB no longer NA-poisons the manifest summary). **E** `datom_clone()` sets a local git identity (first write after clone no longer fails on a no-gitconfig host). **F** confirmed-real bug: `.datom_git_push()` now sets upstream tracking after push (fetch + `branch_set_upstream`, warn-only on failure) so `datom_pull()`/stale-guard stop silently no-op'ing on the initializing dev's machine. **G** new `.datom_validate_sha()` (6-64 hex) guards `version`/`data_sha` splicing in `datom_get_lineage`/`datom_parent`/`.datom_read_parquet` against local-backend path traversal. **H** developer conn now cross-checks prefix (not just root), normalized, so wrong-prefix stores are rejected. **I** `.datom_mask_secret(reveal_prefix=)` fully masks AWS `secret_key`/`session_token` in print methods. **J** NEWS.md ships (`.Rbuildignore`), LICENSE 2025->2026, SECURITY.md link repointed + plaintext-cred warning. Local R CMD check 0E/0W/1 benign NOTE. **No pathway impact.** **Deferred:** cran-comments.md refresh + full `--as-cran` on all four environments -> combined pre-submission step after #72 (companion hashing rework). |
| Spec: vignettes-gov-liftout | 2026-06-27 | 1873 | Vignette-suite cleanup after the GOV_SEAM lift-out (docs-only; **no `R/`/NAMESPACE changes**). Trimmed the rendered pkgdown site to a minimal gov-free set. **Bucket A** (kept/fixed): `first-extract`, `month-2-arrives`, `folder-of-extracts`, `source-lineage`, `looking-ahead`, `design-datom-model`, `design-version-shas`, `design-serverless`, + new **`start-on-s3.Rmd`** (gov-free S3-native start; complements local-first `first-extract`). In-place fixes: `datom_decommission()` -> `datom_repo_delete()`, `gov =` store component dropped, gov framing reworded to companion-package/on-demand terms, all dead cross-links repointed. **Bucket B** (parked verbatim, build-ignored): 9 gov-interface vignettes + `resume_article_4-8.R` moved to `dev/vignettes-deferred/` with a parking README (reassembly map) -- blocked on datomanager's gov API. **Bucket C** (handed off): `governing-a-portfolio` + `auditing-reproducibility` `git rm`'d from datom (byte-identical copies preserved at `datomanager/dev/vignettes-from-datom/`). `_pkgdown.yml` `articles:` restructured to Bucket-A-only (9 indexed == 9 on disk); `reference:` untouched. All 7 verification checks pass (no removed-export refs, no dead links, ASCII clean, R CMD build clean, pkgdown clean, test count 1873 unchanged, R/+NAMESPACE clean). **No pathway impact.** |
| Spec: gov-seam-liftout (datom side) | 2026-06-20 | 1873 | GOV_SEAM lift-out, datom side. Removed the governed **write** surface (5 exports: `datom_init_gov`, `datom_attach_gov`, `datom_decommission`, `datom_sync_dispatch`, `datom_pull_gov`; 9 `.datom_gov_*` write helpers) — it now lives in `datomanager`. datom retains all gov **reads** (`datom_projects`, `datom_pull` (data-repo-only), the six gov-read helpers, `R/ref.R` resolvers). Additive: `gov_backend` 12th conn field + `.datom_conn_for(conn,"gov")` resolves gov dispatch from it (C6); new export `datom_repo_attach_governance()` (C4-compliant data-side `governance.json` write for `datomanager::gov_attach()`); internal `.datom_sync_data_metadata()` split from `datom_sync_dispatch` (data-only half; called by `datom_validate(fix=TRUE)` + `datom_write(NULL,NULL)`). `datom_init_repo()` decoupled from gov registration (solo-only). Added `dev/e2e-solo-local.R` (solo init→write→read→`datom_repo_delete`, passing). R CMD check 0E/0W/1 benign NOTE; dev version 0.0.0.9001. **No pathway impact** (route shapes unchanged). Companion-package starter code recoverable from git history before the merge. |

### Completed Phases (legacy)

| Phase | Completed | Tests | Summary |
|-------|-----------|-------|---------|
| Phase 22: Storage Extension API | 2026-06-10 | 1897 | Six exports: `datom_storage_list`, `datom_storage_delete_prefix`, `datom_storage_copy` (all 4 backend combos), `datom_storage_verify` (structural + content modes), `datom_repo_set_data_store` (read-modify-write `project.yaml`), `datom_repo_delete` (extracted from `datom_decommission`; gov guard). New files: `R/storage.R`, `R/repo.R`. `datom_decommission()` refactored to call `datom_repo_delete()`. 197 new tests. pkgdown + NAMESPACE clean. Spec updated with Storage Extension API section. |
| Phase 21: Governance-First Connection UX | 2026-05-29 | 1700 | Closes issue #24. Two deliverables: (1) `governance.json` dual-pointer file -- written to `.datom/governance.json` (git canonical) + `{prefix}/datom/.metadata/governance.json` (storage mirror) by `datom_init_repo()` and `datom_attach_gov()`; read back by the developer four-state matrix and reader data-first probe; cleaned up by `datom_decommission()`. (2) `datom_store_s3_creds(access_key, secret_key)` credentials-only S3 component -- readers on gov-attached projects no longer need to know the data bucket/prefix/region; location is resolved from `ref.json` at conn time. New exports: `datom_store_s3_creds()`, `is_datom_store_s3_creds()`. New vignette: `design-governance-json.Rmd` (dual-pointer pattern, schema, lifecycle). Updated vignettes: `handing-off.Rmd` (engineer handoff reduced to 2 items), `credentials-in-practice.Rmd` (`datom_store_s3_creds` section). Spec updated with `governance.json` schema + `datom_store_s3_creds` entry. E2E assertion blocks added to `e2e-test-local.R` (Flows 1-6). |
| Phase 20: Source Lineage | 2026-05-12 | 1602 | Transitive source lineage field in metadata.json. `datom_sync()` auto-populates a self-entry for imported tables. `datom_write()` structural mandate: `source_lineage` required when `parents` is non-null. New exports: `datom_get_lineage(depth = "source" | "parents")` (single-read, no DAG walk) and a dedicated lineage validator (union parents' lineages, diff against declared). Spec updated; vignette "Tracing Data Lineage" added; dpbuild lineage contract documented in daapr_architecture.md. (Superseded by the cross-project-parent-lineage phase: the dedicated validator and the `source_lineage` caller-mandate were removed; `datom_write()` now derives `source_lineage` from the parents' union; parents carry `data_sha`; the composable recompute recipe replaces the validator: `datom_get_parents()` + per-parent `datom_get_lineage(depth = "source")` + `datom_lineage_union()`.) |
| Phase 18: Governance on-demand | 2026-05-03 | 1528 | Made governance optional and on-demand. New flow: `datom_store(governance = NULL)` for solo projects; `datom_attach_gov()` for the promotion moment (typically alongside S3 migration). `datom_init_repo()` writes `project.yaml` without `storage.governance` when no gov store supplied. Gov-only commands (`datom_projects`, `datom_pull_gov`, `datom_sync_dispatch`) emit a uniform "no governance attached -- use `datom_attach_gov()`" error. `.datom_conn_for(conn, scope)` accessor replaces `.datom_gov_conn()` for all scope-switching. `datom_decommission()` no-gov branch skips gov teardown cleanly (latent bug fixed: local no-gov conns no longer accidentally delete `cwd/projects/{name}`). Vignettes rewritten: Article 1 drops gov entirely; Article 4 introduces `datom_attach_gov()` paired with S3 promotion. README primary example is no-gov. Sandbox learns `attach_gov = FALSE` mode and `sandbox_promote_gov()` helper. Acceptance criteria 1-10 all met. |
| Phase 16: Vignette overhaul | 2026-05-11 | 1530 | Replaced the legacy three vignettes with a 10-article user-journey track (STUDY-001 over six months: first extract -> monthly cadence -> bulk sync -> S3 promotion -> reader handoff -> second engineer -> portfolio governance -> audit/reproducibility -> daapr-stack outlook -> credentials reference) plus a 6-article design-notes track (D1 datom model; D2 ref.json; D3 dispatch.json; D4 two-repo split; D5 version SHAs; D6 serverless). All article IO chunks `eval = FALSE`; jump-in readers get continuity via `inst/vignette-setup/resume_article_N.R` (idempotent, env-var-overridable). Simulator extended with LB + AE domains. `_pkgdown.yml` reorganized into Get Started / Scale Up / Govern / Reference / Design groups. Coverage review confirms all 28 exports appear in at least one article. Phase-16 continuation (May 11): fixed two real package bugs surfaced by live-running the vignettes (datom_attach_gov synthetic data snapshot had empty root -- backend field mismatch; fixed in R/conn.R with regression test); added `buckets-and-prefixes.Rmd` convention article (Pattern A: bucket-per-study, empty prefix for raw; named prefixes for derived; dedicated gov bucket); aligned all 17 vignettes to Pattern A defaults and ASCII-only source (R CMD check safe); fixed broken `credentials.html` link in `looking-ahead`; expanded `credentials-in-practice` to 3 credential options; issued #19 (init_gov CWD default) and #20 (init_gov idempotence local-only). |
| Phase 17: Portfolio helpers | 2026-05-02 | 1416 | Added two manager/audit-facing helpers: `datom_summary(conn)` (single-project one-liner; reads `.metadata/manifest.json`; S3 class with print method; developer path includes data git remote URL) and `datom_projects(x)` (portfolio listing; accepts `datom_conn` or `datom_store`; returns data frame with name/data_backend/data_root/data_prefix/registered_at; clone-first read with storage fallback; corrupt entries warn-and-skip). Internal additions: storage list dispatch (`.datom_storage_list_objects` + `.datom_s3_list_objects` mirroring existing local helper); `.datom_gov_list_projects()` pure-read helper in `R/utils-gov.R` (NOT a `GOV_SEAM` -- reads stay with datom, only gov writes are seamed). Pre-release schema bump: added `current$type` field to `ref.json` so readers can identify the data backend without already holding a store. Unblocks Phase 16 Chunks 5-6. |
| Phase 15: Separate Gov Repo (+ audit cleanup) | 2026-04-29 | 1343 | Split governance and data into two independent git repos with separate histories, remotes, and local clones. New shared governance repo (one per organization / gov bucket) holds `projects/{name}/{ref,dispatch,migration_history}.json`; data repo holds tables + manifest. New exports: `datom_init_gov()`, `datom_decommission()`, `datom_pull_gov()`. Refactored: `datom_init_repo()` (data-first, gov-register), `datom_clone()` + `datom_pull()` (two-repo), `datom_sync_dispatch()` (commits on gov). Breaking: `remote_url` -> `data_repo_url`. New `# GOV_SEAM:` contract isolates gov-write helpers in `R/utils-gov.R` for future companion-package handoff. Role-aware ref reads (developer reads from local clone, reader from storage; write-time guard always hits storage). Sandbox supports scoped teardown (`scope = "all" \| "project" \| "gov"`). **Pre-CRAN audit cleanup** folded in (5 chunks): hard-abort on post-push gov/manifest failures with gov-clone rollback (C1+C2); `datom_decommission()` repo deletion via `httr2` instead of `gh` CLI (H1); backend-blind UI in `datom_sync_dispatch()`, symmetric pull errors, dropped dead pre-Phase-15 fallback (H2-H4+L3); deduped `gov_local_path` resolution / `datom_init_gov()` config / `.datom_gov_unregister_project()` commit logic (M1+M3+M4+M5); style polish (L1+L2+L4+L5). E2E-driven fixes: NA-safe prefix guards in `.datom_local_delete_prefix` / `.datom_s3_delete_prefix`; sandbox mops up data store root after decommission (caller-owned root principle); idempotent `gh repo` deletion in sandbox teardown. |
| Phase 14: Public Release Prep | 2026-04-21 | 1177 | Pre-public cleanup: fix LICENSE/`.Rbuildignore` (`tbit` rename remnants), add `NEWS.md`, drop CRAN badge, fix R CMD check warning (non-ASCII in `R/ref.R`), add `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, issue/PR templates, GitHub Actions (R-CMD-check + pkgdown), untrack `dev/archive/` + `dev/datomaccess_overview.md` via `.gitignore`, scrub Phase/Chunk refs from `R/` comments, centralize `dev/dev-sandbox.R` credentials to `Sys.getenv()`, fix `_pkgdown.yml` missing `datom_store_local` entries. |
| Phase 13: Reader Ref Resolution | 2026-04-21 | 1177 | Conn-time ref resolution wired into both `_get_conn_reader` and `_get_conn_developer` (S3 + local). New helpers: `.datom_resolve_data_location()`, `.datom_check_data_reachable()`, `.datom_check_ref_current()`. Developer migration mismatch → auto-pull git + re-read `project.yaml`. Reader mismatch → warn + proceed with ref-resolved location. Reachability check (HeadBucket / `dir_exists`) gates conn creation. Conn-time ref failure is warn-only; write-time ref failure is a hard abort (prevents orphaned data). `datom_status` and sandbox UI now backend-aware (`Tables on S3`/`Tables on local`, `Data:`/`Governance:` labels instead of hardcoded `s3://`). `.sandbox_wipe_local_component()` added so `sandbox_down()` handles local backends too. Named-lookup pattern adopted for backend UI labels (anticipates GCS/other backends). |
| Phase 12: Filesystem Backend | 2026-04-19 | 1153 | `datom_store_local()` constructor, `.datom_local_*()` backend functions (`utils-local.R`), dispatch wiring (`switch` arms in `utils-storage.R`), `conn$bucket`→`conn$root` rename, `new_datom_conn(backend=)`, `datom_init_repo()`/`datom_get_conn()` local paths, `project.yaml` type:local, `.datom_store_backend/root/region()` accessors, `.datom_build_init_conn()` helper, `ref.json` backend-neutral, README template backend-neutral, E2E test script (`dev/e2e-test-local.R`), `sandbox_store_local()`, `devtools::check()` clean. |
| Phase 11: Routing Separation | 2026-04-18 | 1039 | `routing.json` → `dispatch.json`, credential wiring (no env var bridge), gov/data store split, storage abstraction layer (`.datom_storage_*()` dispatch), `ref.json` replaces `.redirect.json`, conn fields `client`/`gov_client`/`backend`, `.datom_build_storage_key()`, spec + copilot-instructions updated, README updated, sandbox fixed, `devtools::check()` clean. E2E passes. |
| Phase 10: Store Abstraction | 2026-04-18 | 1083 | `datom_store_s3()` + `datom_store()` constructors, `.datom_create_github_repo()` via httr2, `datom_init_repo(store=, create_repo=TRUE, repo_name=)`, `datom_get_conn(store=)`, `datom_clone(path, store)`, two-component `project.yaml` (governance+data), `.datom_install_store()` env-var bridge, HeadBucket validation (STS removed — not in paws.storage), print methods with masked secrets, vignettes rewritten. `devtools::check()` clean. | Full package rename: all function prefixes (`datom_`/`.datom_`), S3 class (`datom_conn`), env vars (`DATOM_`), S3 path segment, `.datom/` config dir, metadata field (`datom_version`), package identity, docs. `devtools::check()` clean. |
| Phase 7: Multi-Developer Collaboration | 2026-03-28 | 964 | S3 namespace safety check in `datom_init_repo()`, pull-before-push discipline (`.datom_git_pull`, `.datom_check_git_current`), `datom_pull()` export (git-only, no S3 refresh — git is source of truth), `datom_clone()` export, team collaboration vignette, credentials vignette, `project_name` in manifest, `.force` bypass, `datom_validate()` project_name cross-check |
| Phase 8: Metadata Enrichment & Table Types | 2026-03-28 | 905 | `table_type`, `size_bytes`, `parents`, `original_file_sha` in version_history, `datom_get_parents()`, `endpoint` param, `.access/` namespace safety. Post-phase bug fixes: manifest update in `datom_write`, `datom_init_repo` S3 push, idempotent SHA computation (JSON canonical form, volatile field exclusion, version_history dedup guard) |
| Phase 6: Sync & Validation | 2026-02-15 | 130 | datom_sync_manifest, datom_sync (rio import), datom_sync_routing, datom_validate (git-S3 consistency), datom_status |
| Phase 5: Read/Write Workflows | 2026-02-15 | 143 | datom_read (version resolution), datom_write (change detection, parquet+metadata), .datom_sync_metadata, datom_list, datom_history |
| Phase 4.5: S3 Refactor | 2026-02-15 | 99 | Refactored S3 utils from (s3_client, bucket, s3_key) to (conn, s3_key), added mock_datom_conn helper |
| Phase 4: Connection & Init | 2026-02-15 | 115 | datom_conn S3 class, datom_get_conn (developer/reader), datom_init_repo, credential derivation |
| Phase 3: Git Operations | 2026-02-14 | 47 | git2r wrappers: check, author, branch, commit, push (fetch+merge+push) |
| Phase 2: S3 Operations | 2026-02-10 | 99 | S3 client, upload/download/exists, JSON read/write, redirect resolution |
| Phase 1: Core Utilities | 2026-02-09 | 131 | SHA, paths, name validation, repo validation |

### Developer Tooling

**dev/check-spec.R**: Mechanical consistency checks for a Kiro spec

- `Rscript dev/check-spec.R [spec-dir]` (defaults to `.kiro/specs/datom-sets`). Base R only, no
  package dependencies. Exit 0 clean, 1 on any failure, so it works as a gate.
- Nine checks, each one derived from a defect that actually shipped into a spec and had to be
  caught by a human reader. (This list read "six" until 2026-08-23, having missed two additions --
  which is the same staleness class the checks exist to catch, in the document describing them.)

  | Check | Catches |
  |---|---|
  | dangling references | an `R*`/`I*`/`P*`/`AC*` token that resolves to nothing after renumbering |
  | orphaned criteria | an AC / invariant / property defined but referenced by no task -- i.e. unimplemented |
  | task numbering | task numbers not contiguous from 0 |
  | task acceptance coverage | a task with no `Acceptance:` clause |
  | code citations | a `R/file.R:NNN` **or `tests/testthat/test-file.R:NNN`** reference pointing outside the file, or resolving to nothing (every line in the cited range blank). Test files were added 2026-09-09, because Task 22 has to name the individual assertions it flips and the nine it must not touch, and a stale number there sends the reader to the wrong assertion in a file of a thousand lines. It found three stale citations on the round that added it, and was verified by planting a wrong number and confirming a FAIL. |
  | superseded wording | retired phrasing surviving as a **live instruction** rather than marked historical |
  | duplicated content agrees | the same fact stated in several files with the copies disagreeing, or one copy deleted; plus any hardcoded AC upper bound; plus **the execution order** (`18 -> 19 -> ...`), which is written out three times -- the spec's state block, Phase E's preamble, and the status cell in this file. Added 2026-09-10 after adding Task 23 swept one copy and left two saying the order ended at Task 7, caught by a reader. Copies are compared against each other, never against an expected sequence, since the order changes legitimately. This is the one clause that reads `dev/README.md`, because that is where the third copy lives. Verified by reintroducing the exact defect. |
  | ascii | non-ASCII that will trip `R CMD check` once the prose is copied into roxygen or NEWS |
  | task cross-references | a `Task N` mention with no such task -- the usual cause is a half-swept renumber |

- **When to run it**: at each chunk checkpoint, next to reporting the test count. A `PostFileSave`
  hook would fire constantly mid-draft and train you to ignore it.
- `SPEC_CHECK_SHOW_CITATIONS=1` prints every cited code line so a reviewer can confirm it says what
  the spec claims. **The citation check catches the blatant half only, and the split is worth
  knowing**: a citation whose whole range is blank now **fails** the run (added 2026-08-28, after an
  insertion into `R/utils-sha.R` staled five citations while all nine checks passed -- two had drifted
  onto blank lines and were reported only in the verbose output, without failing). A citation that
  drifted onto a **real but unrelated** line still passes, because no mechanical check can tell that a
  comment is not the constant the spec claims. So after any insertion into `R/`, re-derive by content
  with the verbose flag; a green run is not evidence. Two exemptions, both deliberate: a range whose
  *first* line is blank but which spans real content is fine, and a citation appearing only inside a
  dated Decisions row is exempt, since those are frozen and some exist to record a number that was
  already wrong.
- **Maintenance rule**: the `retired` denylist is the only part that needs upkeep. When a design
  decision is reversed, add its old phrasing there -- that is what turns "we removed this" into
  "and it cannot come back silently".
- **What it cannot do**: reasoning defects. In the review round that prompted it, these checks would
  have caught about half the findings; the rest were things like "a required payload field has no
  public parameter" and "the integrity gate has no acceptance criterion". It reduces review load, it
  does not replace review. The script says so on every run.

**dev/e2e-cv1-identity.R**: Offline `datom-cv1` identity walkthrough and smoke test

- `Rscript dev/e2e-cv1-identity.R` -- **no GitHub PAT, no AWS, no network**. Builds a real git
  repo with a local bare remote plus a real `backend = "local"` store in `tempdir()`.
- Three sections: the table contract (`datom_check_hashable()` on a clean and an offending
  table), what is and is not identity (container class, storage type, factor levels, tzone,
  NaN/`-0`, `NA_real_`, row/column order, NFC vs NFD, last-bit doubles -- each line labelled
  with its expected verdict), and a real project walking full -> metadata_only re-export ->
  skipped re-scan -> new content -> revert (no duplicate version, no re-upload) -> a flipped
  byte (read refuses) -> an unhashable table refused with no state left behind.
- Every claim is asserted (22 of them); the script exits non-zero on any mismatch, so it
  doubles as a smoke test.
- **Caveat**: the conn is assembled directly rather than via `datom_init_repo()` /
  `datom_get_conn()` (that is what removes the PAT requirement), so `project.yaml`, GitHub repo
  creation, and ref resolution are NOT exercised. Use `dev/e2e-solo-local.R` for those -- it
  goes through the public entry points and does need a PAT.

**dev/dev-sandbox.R**: Automated setup/teardown for testing workflows

- `sandbox_up()`: Creates GitHub repo + runs `datom_init_repo()` + populates with example data
- `sandbox_down()`: Wipes S3 namespace + deletes GitHub repo + removes local directory
- `sandbox_reset()`: Full teardown + setup in one call
- Replaces manual 5-step workflow (create repo, walk vignette, delete S3, delete repo, delete local)
- Requires `gh` CLI, AWS credentials, `GITHUB_PAT`

### Backlog (Deferred Features)

Items discovered during development but intentionally deferred. Review periodically.

| Item | Discovered In | Reason Deferred | Priority |
|------|---------------|-----------------|----------|
| `datom_write()` parent `data_sha` enrichment fails for same-project parents (issue #52) | gov-seam-liftout (E2E) | Pre-existing path bug: the lookup prepends `p$source` (project name) but same-project tables have no project segment. Benign (write succeeds, `validate_lineage()` unaffected). Fix tracked in [#52](https://github.com/amashadihossein/datom/issues/52). | Medium |
| renv::init() in datom_init_repo | Phase 4 | Adds complexity, tangential to core data versioning | Low |
| Manifest manipulation APIs (descriptions, staging, QA tagging) | Phase 7 | Two-step scan+sync is sufficient; richer manifest APIs belong in a sister package or future datom release | Medium |
| datomanager package creation | Phase 15 | Companion governance package (settled name: `datomanager`). Scope doc: `dev/datomanager_scope.md`. Owns GOV_SEAM write surface (renamed `gov_*` on lift-out) + `gov_migrate_data()` (Phase 19). datom Phase 22 (storage extension API) complete 2026-06-10; datomanager scaffold is the remaining gate. Effort: ~2 days for lift-out, then Phase 19. **Starter code for the gov-write reimplementation:** the tried-and-tested helper bodies + their tests are preserved in datom git history at the commit just before the `gov-seam-liftout` merge -- retrieve with `git show <sha>:R/utils-gov.R`, `git show <sha>:R/decommission.R`, `git show <sha>:tests/testthat/test-utils-gov.R` (find `<sha>` via `git log --oneline -- R/utils-gov.R`). Reimplement behavior-equivalent with git2r + **its own storage IO for the gov namespace only** (corrected 2026-08-18: an earlier wording said "own storage IO" without qualification, which contradicts the **Authority Principle** in `dev/datomanager_scope.md` -- "data-repo mutations always route through datom ... datomanager never touches the data repo directly". datomanager owns the gov repo and gov storage; every **data-side** write goes through a purpose-built datom export: `datom_storage_copy/verify/list/delete_prefix`, `datom_repo_set_data_store`, `datom_repo_delete`, `datom_repo_attach_governance`); contract C5 (commit strings) + C8 (storage layout) pin the observable behavior. | High (next major) |
| Public `datom_storage_write_json()` (JSON write on the Storage Extension API) | datom-sets spec, Task 3 (2026-08-18) | **Dropped from the spec, not merely postponed.** It was requested in [#89](https://github.com/amashadihossein/datom/issues/89) so a downstream package could write *its own document* into datom's namespace -- that document was a set, and `datom_write_set()` now writes sets as first-class artifacts, so no consumer remains. Exporting it anyway would cut against the Authority Principle above, whose expression is a purpose-built verb per need rather than a generic byte channel (`datom_repo_attach_governance()` is the precedent: datom gave datomanager a named export instead of a generic write for the `governance.json` data-side mirror). Retired with it: R12.4a's managed-key refusal list, I14, AC23. **Revival trigger**: datomanager needs to write JSON into **its own gov namespace** and would otherwise reimplement s3/local dispatch. That is a *different* export -- gov-scoped, no managed-key rules -- so **re-derive the refusal list rather than inheriting R12.4a's**; the analysis is preserved verbatim in `requirements.md` R12.4a as the starting point. Adding an export later is additive; removing one after release is breaking, which is why the default was to not ship it. | Low (trigger-driven) |
| ~~**Identity hashing: denylist -> allowlist**~~ ([#100](https://github.com/amashadihossein/datom/issues/100)) -- **SHIPPED 2026-08-28 as datom-sets Task 19.** The pairing with #98 suggested below did **not** happen and should not: #98 changes the hashed bytes, so it moves every recorded identity, while Task 19's whole claim was that none moved. | datom-sets spec, E2 design audit (2026-08-23) | **Pair with [#98](https://github.com/amashadihossein/datom/issues/98)** -- same function, different defect (#98 removes the JSON emitter from the identity path; this fixes field selection), so one identity-affecting change to verify instead of two. The function hashes every field in a metadata document minus a fixed exclusion list (`R/utils-sha.R:415-416`). A denylist cannot be forward-compatible: a build that has never heard of a field cannot know it was meant to ignore it, so it folds the field into the hash, disagrees with the recorded version, and reports a change on content that did not move -- **on every run, not once**. So today *any* new metadata field costs every older build a spurious version forever. Remedy: hash an explicit named list and ignore anything else. **Set the list to exactly the fields hashed today and every existing identity is byte-identical**, so it is behaviour-preserving now and forward-compatible later; optional fields (`parents`, `source_lineage`, `original_file_sha`, `custom`) need marking as optional since they are conditionally present. Honest limit: it makes *bookkeeping* additions free, which is the common case, not *semantic* ones -- a field that genuinely is content must be in the hash either way. Touches the function every artifact's identity depends on, so it wants the cv1 golden suite green before and after and a test that a document carrying an unknown field hashes identically to one without it. | High (unblocks the forward-compatibility guarantee) |
| ~~**Self-healing manifest read + persist `original_format`**~~ ([#101](https://github.com/amashadihossein/datom/issues/101)) -- **SHIPPED 2026-09-10 as datom-sets Task 22.** Two departures from the sketch below, both deliberate: it triggers on a **too-new declared format** as well as on an absent artifact key, and it writes nothing at **any** role rather than only for a storage-only reader | datom-sets spec, E2 design audit (2026-08-23) | Two halves, one issue. **Order after [#100](https://github.com/amashadihossein/datom/issues/100)**: persisting a metadata field is only free once identity hashing uses an allowlist. (a) When the artifact key a build expects is **absent**, rebuild the index from a storage listing instead of concluding the repo is empty. Trigger on **absent, not empty**: an empty list is what a new repo looks like and what a truncated file looks like, so rebuilding on empty costs a listing per call on healthy repos and hides corruption; a post-rename repo is distinguishable because the expected key is missing entirely. Two constraints -- a storage-only reader can only rebuild **in memory for that session** (no git, must not write to storage), and it must **warn once** pointing at the upgrade, because a silent repair is a silent degradation. (b) `original_format` is written into the manifest entry (`R/sync.R:753`) and **never** into per-artifact metadata, making it the one field a rebuild would lose; persisting it makes the rebuild lossless, and it is additive so free once identity hashing uses an allowlist. Payoff: any future rename of the artifact key is survivable for every build from that release onward, with no dual-write and no legacy copies. Applies to **derived** files only -- per-artifact metadata cannot self-heal (see `.github/copilot-instructions.md`, "Which files may break"). | High (paired with the allowlist item) |
| **`datom_repo_set_data_store()` is under-tested around the config file it rewrites** | datom-sets spec, Task 11 review (2026-09-17) | **Not a missing feature -- a coverage gap that has produced a finding in two consecutive review rounds**, which is the signal worth acting on rather than fixing one symptom at a time. Round one: the verb parsed `project.yaml` and never checked its declared format, while committing and pushing the result to everyone sharing the repo. Round two: its test asserts only that two fields survive the rewrite, so a refactor from read-modify-write to rebuilding the document would silently drop most of the file. Both were fixed at the point of discovery. What is deferred is the review of the verb as a whole: it is the only writer of that file besides repo creation, it commits and pushes, and its tests were written before the file carried anything a writer must obey (a minimum writer version, a format number, and shortly a project mode and set name). Worth going through once with the question "what happens to each key in that file", rather than waiting for a third round to name the third gap. | Medium (two findings in two rounds; no known live defect) |
| **A by-name member lookup that stops at the record** ([#112](https://github.com/amashadihossein/datom/issues/112)) | datom-sets spec, Task 17 docs pass (2026-09-20) | **The safe way to ask which version a member is pinned at currently requires downloading what it points at.** Three routes exist and none of them is both safe and cheap: the listing and a hand-rolled filter both go **silently plural** when a name is cited twice -- which is legal and deliberate, a live cut beside a locked baseline -- while `datom_fetch_member()` refuses correctly on the ambiguity and then, once narrowed, fetches the data. Measured on a fixture: 20 rows pulled to learn a 64-character string, and on a real product it is however large that table is. **It also breaks a property sets are built for**: the fetch needs a connection scoped to the *member's own* project, so a reader entitled to the set and none of its members -- the case a 50-member product is designed to support -- has only the plural route. `.datom_find_member()` already does exactly the right thing with no connection and no storage read, including the refusal with both candidates named; it is internal. **Deferred on scope, not merit**: the owner's condition was "export it if no rename is needed", and the dot prefix means a rename across 5 call sites in 2 files, plus roxygen, NAMESPACE, a pkgdown row, five tests and their probes -- which is behaviour landing in the task that exists to close a spec. The verb should return the **record**, not the version string, because a record composes with `datom_fetch_member()`, `datom_remove_members()` and `datom_update_members()`, all of which already accept one. | Medium (no data loss; a correctness trap in user code plus an access asymmetry) |
| **Two acceptance statements in the datom-sets requirements have no id, so nothing gates their tests** ([#111](https://github.com/amashadihossein/datom/issues/111)) | datom-sets spec, Task 17's independent criteria re-derivation (2026-09-20) | **Not a coverage gap -- a gating gap, and it is the inverse of the failure the new build check catches.** An independent session re-derived the criteria list from `requirements.md` alone and matched Task 16's exactly, but it also found two acceptance statements written in prose beside their requirements with no `AC` number: a written set's metadata carries exactly the fields R1.3 lists, asserted with `setequal()` on the written file, and a hand-assembled member list is refused with a message pointing at `datom_member()`. **Both have real tests today** (`tests/testthat/test-write-set.R:878` and `:498`), so nothing is unasserted -- but `dev/check-spec.R` check 10 walks `AC` ids, so deleting either test fails nothing. Not fixed in Task 17 because giving them ids means **two** edits, not one: defining the criteria, and referencing them from an already-closed task's acceptance line, since check 2 fails an AC no task references. Do it at the next spec that touches set writing, when a live task can own them. | Low (tested, merely ungated) |
| **A vignette for the cross-study, pooled product (Case B)** | sets-release-readiness spec (2026-09-23) | The `citable-sets` vignette covers **Case A** from `.kiro/specs/datom-sets/design.md` section 20 -- one study, one bucket, a product at a prefix beside the onboarded data. That is the common shape and the right first read. **Case B** is the advanced one: a product that pools several studies living in several buckets, where the credentials used must be tied to a role with access to all of them, and where members carry a project name that a future access layer resolves to a location. Section 20.3 already works through the topology and confirms it needs no governance attached. Deferred deliberately, not because it is hard but because it should build on a reader who has done Case A first -- the same reason `citable-sets` builds on `start-on-s3`. **A natural third article after that**: composing a set whose members are themselves sets (the one-level rule is what makes this cheap), which the owner has line of sight on but has not scheduled. None of the three needs new behaviour; they are documentation of shapes the code already supports. | Low (Case A ships first; Case B when there is a reader who wants it) |
| **`dev/check-spec.R` is written for one spec, and gives a FALSE PASS against any other** | sets-release-readiness spec setup (2026-09-21) | The name and the CLI argument both suggest a general spec linter; it is not one. Run against a second spec it reports four failures that mean nothing there -- it requires the `datom-sv1` encoder pseudocode in all three files and expects task numbering to start at 0 -- and, worse, **its criteria-named-in-tests check matches that spec's `AC<n>` against tests belonging to a different spec's criteria of the same number**, so it reported 8 of 12 criteria as covered when none were. A false failure is noise; a false pass is the thing this script exists to prevent. Deferred rather than fixed because the fix is a real piece of work with several judgement calls (which checks are universal, how a spec declares its own encoder-rule set or opts out, how the criteria check learns which test directory belongs to which spec) and it does not belong inside a documentation spec. **Cheap interim mitigation if this bites sooner**: make the script refuse a spec directory other than the one it was written for, naming this row -- a loud refusal is strictly better than a quiet wrong answer. | Medium (no live defect; a false pass is waiting for whoever points it at spec number two) |
| **Dual-write as a repo-level compatibility policy** ([#102](https://github.com/amashadihossein/datom/issues/102)) | datom-sets spec, E2 design audit (2026-08-23) | **Spec it; do not build it until a break actually needs it.** The escape hatch of last resort: the writer emits the previous shape alongside the current one for a declared window. It is the **only** mechanism that helps builds already released, since it asks nothing of them. Design constraints, all driven by the fact that the danger is a **stale** legacy copy rather than a leftover one (an old reader consuming an out-of-date file looks like it worked): repo-level config in `project.yaml`, **not** a per-call argument, so every write honours it and one forgetful call cannot strand a copy; turning it off **deletes** the legacy copies in the same operation; the sunset release recorded **inside** the legacy file so anything reading it can tell it is scheduled to disappear. Scope limit: **derived files only.** Dual-writing per-artifact metadata backfires -- a legacy-shaped copy hashes differently from the recorded version, so older writers mint a version on every run; it would help old readers by breaking old writers. Chosen over the richer alternative (a declarative transform file travelling with the repo) whose full reasoning is in the spec's rejected-alternatives table: the interpreter would have to ship in the build that predates the change, and its mapping format would be frozen the day it shipped. | Medium (trigger-driven -- build it when a break is unavoidable) |
| **Publish the schema-version to package-version mapping** ([#103](https://github.com/amashadihossein/datom/issues/103)) | datom-sets spec, E2 design audit (2026-08-23) | Docs only. One schema version spans many releases, so neither `schema_version` (the contract) nor `datom_version` (provenance) answers the only question a refusal message raises: *which datom do I need?* A table in the package documentation mapping each schema version to the release range that reads it. Add the row at each schema bump; the bump is rare by policy, so upkeep is near zero. | Medium (ship alongside the first release that carries `schema_version`) |
| **Writer floor: the raising verb and its tooling** | datom-sets spec, E2 design round (2026-08-23) | The **reading half SHIPPED 2026-09-09** as datom-sets Task 21: `min_writer_version` in `project.yaml`, absent meaning no limit, compared against the running build at the write entry, with a malformed value refused rather than read as no floor. It shipped first because it cannot be retrofitted -- a build that does not look for the field can never be bound by it, which is exactly why nothing can stop a 0.1.0 writer. Deferred here: a **purpose-built verb** to raise the floor (a normal commit cannot validate that the raiser satisfies the new value, and the R15 precedent in the spec is named verbs over generic writes), plus tooling and docs. **This row now also owns AC36(c)** -- "setting a floor above the setting build's own version is refused" is a guard on the setter, so it has nothing to bind to until the setter exists; Task 21 recorded the gap rather than faking it. The floor is the **escape hatch**, not the primary mechanism -- the vocabulary check is primary because it cannot be forgotten. Its own trigger cases, recorded so a later reader knows why it exists: a **meaning** change that adds no field, and a policy block for a non-format reason ("0.1.4 wrote bad hashes"). | Low (trigger-driven) |
| **Ease recovery from a push-rejected write, and make it rarer** ([#105](https://github.com/amashadihossein/datom/issues/105)) | datom-sets spec, Task 18 (2026-08-26) | A rejected push leaves a local commit, untouched storage, and a git merge conflict in machine-generated JSON -- recoverable, but only with git literacy a data developer may not have. **The finding that reframes it**: `.datom_check_git_current()` is called from exactly **one** place, `datom_sync()`; `datom_write()` never calls it. So the main write path writes files, commits, and only then pulls inside `.datom_git_push()` -- discovering divergence *after* manufacturing it. A fast-forward before the commit makes the push a fast-forward with no merge at all, so much of this is an **ordering artifact**, not inherent to offline work. Also `datom_status()` reports uncommitted files and the branch but **not** ahead/behind, so nobody can see it coming. Five options, filed as one issue because they trade off against each other: **(1)** ahead/behind in `datom_status()` -- near-free, `ahead_behind()` is already used, `[[1]]` is ahead; **(2)** fast-forward-only pull at `datom_write()`'s door -- highest leverage on likelihood, never auto-merge, stop before doing work rather than after committing, and **cheapest inside the datom-sets Task 21 window** since that entry sequence already fetches; **(3)** `datom_repo_resolve()`, the recovery verb -- take the remote copy of datom's derived files, complete the merge, report that the write should be re-run; safe to automate *because* those files are derived, and it must **refuse** when a conflicted path is not datom-owned (Task 13's `include_paths` commits user code, so that boundary is load-bearing) plus dry-run by default; **(4)** decompose the repo-wide `.metadata/manifest.json` into per-artifact entry files so two writers of *different* tables stop colliding -- right idea, wrong release, and deferral is bounded rather than compounding because #101's rebuild plus the 0.1.1 upgrade chain make it one more upgrade step later; **(5)** warn at write entry when the base is unverifiable, the honest complement to #104's loosening. **What stays hard and is not worth engineering away**: two people writing the same table from stale bases must have someone decide the version ordering. datom can only make the *mechanical* half mechanical. Residual after all five: genuinely offline, or a race between pull and push. | Medium (1 + 5 near-free; 3 is the main deliverable; 4 trigger-driven) |
| Backend rename: `local` -> `filesystem` | Phase 18 | "Local" implies laptop disk, but the backend supports network mounts and cloud-mounted FS too. Atomic schema bump touching store constructor, predicate, dispatch arms, `project.yaml`, `ref.json`. Defer until there's a second compelling reason to touch the schema. | Low |
| `gov_migrate_data()` (managed migration) | Phase 15 | Today migration is manual (`aws s3 sync` + `datom_sync_dispatch()`). Atomic data-copy + ref.json update + `.datom_gov_record_migration()` deferred. Lives in datomanager (Phase 19); calls datom `datom_storage_*` / `datom_repo_*` helpers (all six now exported in Phase 22). | Medium |
| Restore `ubuntu-latest (devel)` in `.github/workflows/R-CMD-check.yaml` | Phase 17 | Disabled 2026-05-02 because Posit PPM has no R-devel Linux binaries; every PR paid a 15-25 min source-compile tax for arrow / paws.storage / friends. Restore as part of the pre-CRAN checklist (CRAN expects devel to pass). | Pre-CRAN |
| CODEOWNERS automation on `projects/{name}/` | Phase 15 | Self-serve project ownership; belongs in companion package, not datom. | Low (companion) |
| Gov repo concurrency primitives | Phase 15 | Pull-before-push handles current contention. Advisory locks deferred until contention is observed. | Low |

**Backlog lifecycle**:
1. Discovered during phase work → add here with context
2. **Decide whether it also needs a GitHub issue, and default to yes when it names work with a
   finished state somebody else could pick up.** This table is the reasoning; an issue is the
   reminder. Keep it table-only when the row records a decision *not* to do something, when it
   belongs to a package that does not exist yet, or when it is a note about how to work rather than
   a change to make — anything else has no reader, because this table is only ever opened by
   someone already mid-spec. A row whose trigger is "next time we happen to be in this file" is the
   case that most needs an issue, not the case that least needs one. **The row stays either way**,
   with the issue linked from it and the row named in the issue: the table's reasoning is too long
   for an issue body and is the part that rots when it is moved.
3. When planning next phase → review for inclusion
4. If promoting to spec → move to `datom_specification.md` "Deferred to v2" section
5. If abandoned → delete with brief note why

Added 2026-09-20, from Task 17 of the datom-sets spec. Before it, four of roughly seventeen live
rows carried an issue and all four had been filed in one batch out of a single design audit — so
what existed was a habit rather than a rule, and a row's persistence depended on which week it was
discovered.

## Quick Context for New Sessions

When starting a new development session:

1. Check the **Active Specs** table above
2. Open the active spec under `.kiro/specs/{feature}/` (requirements, design, tasks)
3. **Read the state block at the top of `tasks.md`** -- an active spec carries its branch, its PR
   target, the current test count, the next task, and anything still open with the owner there. Then
   find the next unchecked task.
4. Continue from where we left off

If a spec touches `R/`, read `dev/engineering-notes.md` before editing. If it has a
`check-spec.R`-able structure, run `Rscript dev/check-spec.R` as part of each chunk (step 3a of the
Chunk Delivery Checklist).

---

## Collaborative Development Workflow

Within each spec, we work in **chunks** — small, testable units of work (each chunk = one task, or a small related group, in `tasks.md`).

### Chunk Lifecycle

```
1. DESIGN    → Propose scope, functions, acceptance criteria
                 ↓
              User approves or adjusts
                 ↓
2. DEVELOP   → Implement code + tests
                 ↓
              User reviews, runs tests, QA
                 ↓
3. FEEDBACK  → User confirms or requests changes
                 ↓
              Iterate until approved
                 ↓
4. COMPLETE  → Mark chunk done, pick next chunk
```

### Chunk Size Guidelines

- **1-3 functions** per chunk (testable in one session)
- **Clear boundary** — chunk should work independently
- **User can QA** — real tests they can run

### Communication Pattern

At each stage, I will:

| Stage | I Provide | You Provide |
|-------|-----------|-------------|
| DESIGN | Proposed functions, signatures, tests | Approval or adjustments |
| DEVELOP | Implementation + test file + debug snippet | Run tests, step through, try it out |
| FEEDBACK | Respond to issues | Confirm done or request changes |

### Chunk Delivery Checklist

After each chunk is implemented, I deliver **five things in order**:

1. **Write tests** — full test coverage for the chunk's functions
2. **Run tests** — execute and fix until all pass (green suite)
3. **Minimalist walkthrough snippet** — a clean, self-contained R snippet for you to paste into the console and step through interactively (use `debugonce()` to drop into any function)
3a. **Run `Rscript dev/check-spec.R`** — alongside reporting the test count. Structural
   consistency of the spec itself: dangling references, orphaned criteria, tasks with no acceptance
   clause, code citations pointing outside the file, and retired wording surviving as a live
   instruction. It is a gate (exit 1 on failure), and it is not a substitute for reading.
4. **Update the spec as part of the same commit** — every chunk, no exceptions:
   - Check off the completed task(s) in `tasks.md`
   - If the chunk changes metadata schema, storage layout, governance refs, lineage, access control, role resolution, migration, or decommissioning, update `dev/datom_pathways.md` or explicitly record "no pathway impact"
   Also update the `dev/README.md` Active Specs table status line. `tasks.md` + commit history are the audit trail; if they're not updated, the chunk isn't done.
5. **Commit after walkthrough** — once you've kicked the tires and confirmed it works, I commit (code + `tasks.md` status together) with a concise message, then you push

> **`tasks.md` is the at-a-glance dashboard.** Task checkboxes show status at a glance; a fresh session reads `tasks.md` first to find the next unchecked task. Commit history is the detailed audit trail.

### QA Methods

- **Run tests**: `devtools::test(filter = "chunk_name")`
- **Debug walkthrough**: Step through with breakpoints or `browser()`
- **Try interactively**: Playground snippets provided with each chunk

### Code Style for Debuggability

To support step-through debugging:

- **Meaningful intermediates**: Avoid long pipe chains; use named variables
- **Small functions**: Each does one thing, easy to step into
- **Playground snippets**: Each chunk includes copy-paste code to try interactively

### Branch Workflow

Every spec gets its own feature branch:

1. **Create branch**: `git checkout -b spec/{feature}` (from `main`)
2. **Develop on branch**: All commits for the spec go here
3. **PR when complete**: Open a pull request to `main`
4. **Merge + delete**: Squash-merge or merge, then delete the branch

The spec is created/edited *on the branch* (not on `main`). Specs persist after merge — the
Spec Completion Procedure does **not** delete them (this replaces the old phase-doc deletion).

### Git Commit Cadence

Within chunks (on the spec branch):

- **Commit frequently**: After each logical unit (function + test, fix, etc.)
- **Push at milestones**: Task complete, spec complete, or good stopping point
- **Message format**: `{feature}: brief description` (optionally reference the task)

Example:
```bash
# Start the spec branch
git checkout -b spec/store-relocate

# Within the first task
git add R/remotes.R tests/testthat/test-remotes.R
git commit -m "store-relocate: datom_remotes_s3 constructor + validation"

# More work...
git commit -m "store-relocate: .datom_install_remotes + env var bridge"

# Spec complete — PR to main
git push -u origin spec/store-relocate
# Open PR, merge, delete branch
```

## Maintenance Rules

1. **Keep `tasks.md` current** as you work (status, decisions, blockers)
2. **Split large specs** when scope exceeds a few sessions
3. **Never let the spec go stale** — if context changes, update requirements/design immediately
4. **Specs persist** — do not delete them on completion (they are durable documentation)
5. **Update this README** when spec status changes
6. **Capture deferrals immediately** — when you skip something, document it in the Backlog
7. **Review backlog** before starting each spec
8. **Keep pathway map current** — schema/routing changes must update `dev/datom_pathways.md` or record "no pathway impact"

## Spec Completion Procedure (formerly Phase Completion)

When all of a spec's tasks are done, perform these steps **in order before starting the next spec**:

1. **Harvest persistent content** from the phase doc:
   - Design decisions that affect the overall API → migrate to `dev/datom_specification.md`
   - Canonical lookup/traversal route changes → migrate to `dev/datom_pathways.md`
   - Coding patterns/conventions discovered → migrate to `.github/copilot-instructions.md`
   - Ecosystem learnings → migrate to `dev/daapr_architecture.md`
   - Deferred items → move to the **Backlog** table in this README

2. **Update this README**:
   - Move phase from Active → Completed table (with date, test count, summary)
   - Update backlog if needed

3. **Specs persist — do NOT delete them.** (Replaces the old "delete the phase doc" step.)
   The spec under `.kiro/specs/{feature}/` is durable documentation: mark its tasks complete
   and leave it in place. Harvest only *additional* durable learnings into the permanent docs
   per step 1.

4. **PR + merge + delete branch**:
   - Open a PR from `phase/{n}-{name}` to `main`
   - Merge (squash or regular)
   - Delete the feature branch (remote and local)

**Rule**: Kiro specs persist as durable documentation — do not delete them. (Legacy
`dev/phase_*.md` files, if any are ever created, still must not survive past completion —
migrate their content and remove them.)
