# Tasks -- sets release readiness

**Source issue**: [#114](https://github.com/amashadihossein/datom/issues/114).
**Branch**: `spec/sets-release-readiness`, cut from `dev`. **PRs into `dev`, not `main`.**
**Test baseline**: **4292** at spec start (FAIL 0 / WARN 0 / SKIP 0). Report the count in every commit
message; it must never drop.

---

## Where things stand

**Nothing is started.** The spec was written 2026-09-21, immediately after `datom-sets` merged into
`dev` (PR [#97](https://github.com/amashadihossein/datom/pull/97)).

**Start here.** Branch `spec/sets-release-readiness` at `origin/dev` (`688c7ac`), working tree clean,
4292 tests, `R CMD check --as-cran` 0/0/0, and `dev/check-spec.R` passing **for `datom-sets`** -- that
script is scoped to that spec and gives a misleading result against this one, which
`requirements.md` explains at the end. Read `design.md` section 1 first -- three short files, each of
which prevents a specific mistake.

**The execution order is fixed and the reason is in `design.md` section 2**: the script produces the
transcripts the vignette shows, and the vignette is the destination NEWS needs before anything can be
cut from it. Reordering does not just delay value, it produces documentation that is confidently wrong.

```
1 -> 2 -> 3 -> 4
```

**Three decisions are already taken in `design.md`**, so do not reopen them without a reason: one
vignette rather than two (4.1), `sandbox_up()` gains `mode`/`set` passthrough rather than the script
calling `datom_init_repo()` directly (3.1), and the credentialed script asserts the **integration**
facts rather than re-asserting set semantics the offline script already covers (3.2).

**Two owner questions are open in `requirements.md`**, both with defaults, so silence is safe: the
bucket and repo naming for the credentialed run, and how aggressively NEWS is cut.

---

- [ ] **1. `sandbox_up()` learns the second artifact kind**

  The smallest possible first step, and it unblocks everything else in task 2. `sandbox_up()`
  (`dev/dev-sandbox.R`) calls `datom_init_repo()` with no `mode` or `set`, so it cannot create a repo a
  set write will accept.

  - Add `mode = NULL` and `set = NULL` to `.sandbox_defaults()` and pass both through to
    `datom_init_repo()`. **Defaulting to NULL is what keeps every existing caller unaffected** -- and
    `datom_init_repo()` already refuses `set` without `mode`, so a half-supplied pair fails at the door
    rather than producing a repo that looks fine until the first set write.
  - Confirm by hand that `sandbox_up(..., mode = "product", set = "x")` produces a
    `.datom/project.yaml` carrying both fields, and that an ordinary `sandbox_up()` call produces a file
    with **neither key present** -- not `mode: ~`. The distinction is real: a declared empty value and
    an absent key are different documents, and the package's own constructor works around exactly this
    (`R/conn.R`, the note about `list()` versus assignment).
  - `dev/` is not shipped, so this is dev tooling. **No test count change is expected.**
  - _Requirements: R1.1. Design: 3.1. Invariants: I1 (no `R/` behaviour change)._

- [ ] **2. The credentialed end-to-end script**

  New `dev/e2e-sets-s3.R`: the set surface against a real GitHub repo and a real S3 bucket, in the style
  of `dev/e2e-solo-s3.R`, reusing `sandbox_store()` / `sandbox_up()` / `sandbox_down()`.

  - **Assert the integration facts, not the semantics** -- the table in `design.md` 3.2 lists exactly
    which, and why each one cannot be asserted offline. Re-asserting what the 4292 unit tests and the
    51 offline claims already pin makes the script slow to read and buys nothing.
  - **Credentials checked first**, before the store is built, naming the missing one and the scope it
    needs (R1.6). Getting this wrong leaves a half-created repo and orphaned objects.
  - **Teardown on both exit paths**, and **verified by listing what remains** rather than by
    `sandbox_down()`'s return value. `sandbox_down()` reports success whether or not there was anything
    to remove, which is the same shape of defect the guard-test rule exists for
    (`.github/copilot-instructions.md` rule 2a).
  - **Every claim asserted, non-zero exit on any mismatch** (R1.4), same contract as `dev/e2e-sets.R`.
    Then **break one claim on purpose and watch it exit non-zero** -- AC2, and the standard this project
    holds coverage to.
  - **Run it.** This is a script whose entire purpose is to be run: "it exists" is not the deliverable.
    The transcript goes in the DONE record (AC1), along with the listing that proves teardown (AC3).
  - **If a claim fails because datom is wrong**, that is a defect with its own issue -- do not adjust the
    script until it passes (R1.8).
  - Not added to CI, and not run by `R CMD check` (R1.7, I5).
  - _Requirements: R1 (all). Design: 3. Acceptance: AC1, AC2, AC3, AC4, AC5, AC6. Properties: P1, P2,
    P3, P4._

- [ ] **3. The vignette that ships**

  New `vignettes/citable-sets.Rmd`, listed in `_pkgdown.yml`. Shape is in `design.md` 4.2 -- seven
  sections, why before how, no function call on the first screen.

  - **Every output block comes from a run somebody watched**, task 2's or the offline script's, and the
    DONE record says which produced which (AC8, I3). Chunks are `eval = FALSE` like the existing
    vignettes, so **nothing verifies the output** -- that is the whole risk, and a composed transcript
    is invisible to every check in this repo.
  - Two properties a reader will otherwise assume wrongly, both required explicitly: **nesting resolves
    one level** (R2.5) and **a citation never drifts to latest** (R2.6).
  - `R CMD check --as-cran` stays 0E/0W with the vignette added (AC7, P5).
  - _Requirements: R2 (all). Design: 4. Acceptance: AC7, AC8. Properties: P5._

- [ ] **4. `NEWS.md` goes terse, and the convention is written down**

  - **Build the mapping table before deleting anything** (`design.md` 5.1): for every claim in the
    development block, name its destination -- stays, roxygen, vignette, or nowhere. **Nowhere means it
    stays** (R3.2, I4). The table goes in the DONE record, because AC9's claim is "every removal has a
    destination", not "it got shorter".
  - **The `artifacts` rename and the writer refusals go first** (R3.3). A reader who stops after two
    items must have hit the two that can cost them discovery of their own data.
  - Every kept claim points at `vignette()` or `?verb` (R3.4). **Nothing points at `dev/` or `.kiro/`**
    (R3.5, I2, AC10) -- neither ships, which is the mistake this spec exists to correct.
  - Leave the block headed "development version": assigning a version is a release decision with its own
    moving parts (R3.7).
  - Write the convention into `.github/copilot-instructions.md` (R3.6, AC11), including the never-cite-
    `dev/` clause, which is the durable lesson here.
  - _Requirements: R3 (all). Design: 5. Acceptance: AC9, AC10, AC11. Properties: P6._

- [ ] **5. Spec Completion Procedure**

  - Full suite green at 4292 or above; `R CMD check --as-cran` 0E/0W; `dev/check-spec.R` still passing
    **for `datom-sets`**, run with no argument. It does not gate this spec and reports a **false pass**
    against it -- the reasoning is in `requirements.md` under the note on that script. Do not point it
    at this spec, and do not fix what it says there.
  - Harvest durable learnings: gotchas to `dev/engineering-notes.md`, conventions to
    `.github/copilot-instructions.md`, deferrals to the `dev/README.md` Backlog **with the
    needs-an-issue decision made** (that lifecycle step was added 2026-09-20).
  - `dev/README.md`: move the spec Active -> Completed with date, test count and summary. **The spec
    persists -- do not delete it.**
  - PR into `dev`, merge. **Leave the branch** unless the owner says otherwise -- the last spec's branch
    was kept deliberately to avoid accidental deletion.
  - _Requirements: R4. Acceptance: AC12._

---

## Decisions

Record decisions as they are made, so a fresh session does not relitigate them.

| Date | Decision | Where |
|---|---|---|
| 2026-09-21 | **Spec created, cut from `dev` rather than continuing on `spec/datom-sets`.** That branch is merged, its PR is closed, and its records describe a finished spec; new commits on it would produce a PR whose diff is already-merged commits plus new ones. The branch itself is **kept** rather than deleted, at the owner's request, to avoid an accidental loss -- it can go later, and every commit on it is reachable from `dev`'s merge commit either way. | this file |
| 2026-09-21 | **One spec covering all three gaps rather than three specs.** They chain: the credentialed run produces the transcripts the vignette shows, and the vignette is the destination NEWS needs before anything can be cut. Splitting them would let the NEWS work start first, which is the one ordering that produces confidently wrong documentation. | `design.md` 2 |
| 2026-09-21 | **The vignette's chunks stay `eval = FALSE`, matching the existing six.** It keeps credentials out of the build and raises no CRAN problem -- at the cost that nothing verifies the output shown, which is why observed-run provenance is a requirement (R2.4) rather than a preference. Evaluating against a local backend was considered and rejected: the vignette's subject is the storage-only reader and the real entry path, which a local fixture cannot show, so it would quietly demonstrate something narrower than it claims. | `design.md` 4.3, 8 |
