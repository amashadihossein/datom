# Requirements -- sets release readiness

**Source issue**: [#114](https://github.com/amashadihossein/datom/issues/114).
**Branch**: `spec/sets-release-readiness`, cut from `dev`. **PRs into `dev`, not `main`** -- 0.1.2 is
with CRAN and `main` stays matching what they received (`dev/README.md`, "Branching During CRAN
Submission").
**Test baseline**: 4292 at spec start (FAIL 0 / WARN 0 / SKIP 0). Report the count in every commit
message; it must never drop.
**Predecessor**: `.kiro/specs/datom-sets/` shipped the feature ([#97](https://github.com/amashadihossein/datom/pull/97),
merged 2026-09-21). That spec is the reference for *why* anything behaves as it does; this one adds
nothing to the behaviour.

---

## The goal, in one sentence

A person who has never seen a set should be able to find out what it is, watch it work on their own
GitHub and S3, and know what upgrading costs them -- without opening `dev/` or the spec.

## Why this is not the previous spec's job

`datom-sets` was measured against acceptance criteria, and it met all of them. Every gap here is
outside that frame:

* its end-to-end script is deliberately offline, which is what makes it runnable in CI and by anyone,
  and is also why it cannot cover repo creation, ref resolution, or a real S3 reader;
* its documentation requirement (R13) named `dev/datom_specification.md`, `dev/datom_pathways.md` and
  `NEWS.md` -- all of which were written, and two of which **do not ship**;
* nothing in that spec or in the project conventions states what `NEWS.md` should look like, so its
  size is not a violation of anything. It is a decision nobody has made yet.

**So this spec's failure mode is different from its predecessor's.** `datom-sets` could ship a wrong
guard. This one can ship a document that is *correct and useless* -- accurate prose nobody reads, or a
transcript that was composed rather than observed. The requirements below are written against that.

---

## R1 -- A credentialed end-to-end run that covers sets

A script under `dev/`, in the style of `dev/e2e-solo-s3.R`, that exercises the set surface against a
**real GitHub repo and a real S3 bucket**.

- **R1.1** It goes through the **real entry path**: `datom_init_repo()` creating the GitHub repo, then
  `datom_get_conn()` opening a connection through it. This is the gap that matters most -- the offline
  script hand-builds a `datom_conn` and writes `.datom/project.yaml` directly, so for sets, connection
  construction, the config-format gate at connection time, and ref resolution have **never run against
  a real store**.
- **R1.2** It covers a **storage-only reader with no clone and no PAT**, reading the set from S3. The
  offline script covers this against a local directory; the claim being tested is that a citation
  resolves for someone with storage credentials only, and S3 is where that claim is actually made.
- **R1.3** It walks the lifecycle, not the verb list: a `mode: product` repo carrying the caller's own
  code and lockfile, inputs written, a set assembled and written with `include_paths`, the set read
  back through the storage-only connection, one member resolved to its data, an input moved, the set
  repointed and a member dropped, written again, and the first version still reading as it did.
- **R1.4** **Every claim is asserted and the script exits non-zero on any mismatch.** Same contract as
  `dev/e2e-sets.R`. A script that prints output for a human to eyeball is not this.
- **R1.5** **Teardown is complete and is part of the script**: the run's `datom/` namespace under its
  prefix, the GitHub repo, and the local clone. The bucket itself is caller-owned and is never deleted.
  A unique per-run prefix isolates concurrent or repeated runs.
- **R1.6** Credentials come from the environment, never from the file: `GITHUB_PAT` with repo
  create/delete scope, and AWS credentials for the bucket. The script states its prerequisites in its
  header and **fails with a clear message when one is missing**, rather than part-way through.
- **R1.7** It is **not** added to CI and not run by `R CMD check`. It costs real resources and needs
  credentials CI does not have. `dev/` is `.Rbuildignore`d, so nothing here reaches the tarball.
- **R1.8** **What it finds, it reports rather than absorbs.** If a claim fails because datom is wrong
  rather than because the script is wrong, that is a defect with its own issue -- not something to be
  worked around inside the script so it goes green.

## R2 -- A vignette that ships

- **R2.1** At least one vignette covering sets, in `vignettes/`, listed in `_pkgdown.yml`.
- **R2.2** It answers **why** before **how**: what a set is for -- a citable name for "these exact
  fifty inputs" -- before any function call appears.
- **R2.3** It shows the arc a product actually has: assemble, write, cite, read back somewhere else,
  an input moves, repoint, drop a retired one, write again. The same shape R1 asserts.
- **R2.4** **Chunks are `eval = FALSE`, matching the existing vignettes**, and the output shown is
  output that was **observed** -- from R1's run or from the offline script -- never composed. A
  vignette that shows a plausible transcript is the failure mode this clause exists to prevent, and it
  is invisible to every check in the repo.
- **R2.5** It names the **one-level rule** explicitly: a member that is itself a set comes back as a
  pointer, and reading a set costs the same whatever sits beneath it. This is the property most likely
  to be assumed away by a reader who expects recursion.
- **R2.6** It states what a set does **not** do: it holds no data, it never drifts to "latest", and
  writing one changes nothing about its members.
- **R2.7** Whether this is one vignette or two -- build a set / cite and edit one -- is a design
  decision, taken in `design.md` rather than here.
- **R2.8** It follows on from `vignette("start-on-s3")` rather than repeating it: the reader is assumed
  to have onboarded a study's data already, and the vignette reuses that store and project instead of
  re-teaching credentials, bucket setup and store construction. It links back in its first paragraph and
  says plainly that `start-on-s3` should be read first.
- **R2.9** It uses the **Case A layout** from `.kiro/specs/datom-sets/design.md` section 20: one study,
  one bucket, onboarding at the study's prefix and the product at a prefix beside it (e.g. `adam`). Not
  a sibling top-level prefix, and not a second bucket. This is the common shape and the one a first
  reader should meet; the cross-study, cross-bucket pool (Case B) is named in a single closing sentence
  as a later article and given no detail here.
- **R2.10** **Plain language, and jargon defined on first use or not used.** No "artifact kind", no
  "canonical", no "namespace", no "invariant" in the prose. A set is "a citable list of exact data
  versions"; a member is "one entry in that list". This is a how-to for a data scientist, not a
  contributor, and the spec's own vocabulary must not leak into it.

## R3 -- `NEWS.md` becomes terse, and the detail has somewhere to go

- **R3.1** The release block states, per change: **what changed, whether it breaks anything, and what
  to do about it.** Reasoning moves out.
- **R3.2** **The destination must exist before anything is cut.** Reasoning goes to roxygen (per-verb
  behaviour, where it substantially already is) or to the vignette (cross-cutting narrative). Anything
  with no destination **stays** -- being verbose is a smaller failure than deleting the only copy.
- **R3.3** The two upgrade-critical items -- the `artifacts` rename and the writer refusals -- are
  where a reader lands first, not buried. Today they sit inside 7,700 words.
- **R3.4** Every claim kept in NEWS carries a pointer to where the detail went: `vignette()` or
  `?verb`.
- **R3.5** **Nothing that is only in `dev/` may be cited as a destination.** `^dev$` is
  `.Rbuildignore`d, so a NEWS entry pointing there points at nothing for the person reading it from an
  installed package. This is the mistake the previous spec made without noticing: R13 was satisfied by
  writing to two files that do not ship.
- **R3.6** The convention itself gets written down, in `.github/copilot-instructions.md`, so the next
  release does not re-accumulate a tome by default.
- **R3.7** The version heading is **out of scope here.** Assigning a version is a release decision and
  drags in `DESCRIPTION`, `cran-comments.md` and the CRAN-SUBMISSION dance. This spec leaves the block
  headed "development version" and merely makes it terse.

## R4 -- What this spec must not do

- **R4.1** **No change to set behaviour.** Not one R file under `R/` changes semantics. Roxygen edits
  that move prose are expected; a behaviour change is a different spec.
- **R4.2** **No test count drop.** 4292 at start. Roxygen-only edits do not move it; a vignette does
  not either.
- **R4.3** `main` is untouched.
- **R4.4** **The offline `dev/e2e-sets.R` is not replaced.** It runs anywhere with no credentials,
  which the credentialed script never will. Two scripts, different jobs.

---

## Acceptance criteria

| # | Criterion |
|---|---|
| **AC1** | The credentialed script exists, and a real run against a real bucket and repo exits 0 with every claim asserted. **The transcript of that run is recorded in the task's DONE record** -- this is a script whose whole purpose is to be run, so "it exists" is not the claim. |
| **AC2** | The same script exits **non-zero** when a claim is made to fail. Verified by deliberately breaking one, as with the offline script. |
| **AC3** | Teardown leaves no GitHub repo, no local clone, and no objects under the run's prefix. Verified by listing after the run, not by reading the teardown code. |
| **AC4** | The script fails with a clear message, before doing any work, when `GITHUB_PAT` or AWS credentials are absent. |
| **AC5** | A set written through `datom_init_repo()` + `datom_get_conn()` -- the path the offline script cannot reach -- reads back correctly, and its `project` field is the repo's own declared name. |
| **AC6** | A storage-only connection with no clone and no PAT resolves the set and fetches one member's data from S3. |
| **AC7** | The vignette builds, is listed in `_pkgdown.yml`, and `R CMD check --as-cran` stays 0 errors / 0 warnings. |
| **AC8** | Every output block in the vignette is traceable to an observed run. The task record names which run produced each. |
| **AC9** | `NEWS.md`'s development block is materially shorter, and every claim removed from it is either present in roxygen or in the vignette. **Checked by listing the removals against their destinations**, not by word count alone. |
| **AC10** | No NEWS entry, and no vignette cross-reference, points at anything under `dev/` or `.kiro/`. |
| **AC11** | The NEWS convention is written in `.github/copilot-instructions.md`. |
| **AC12** | Full suite green at 4292 or above; `R CMD check --as-cran` 0E/0W; `dev/check-spec.R` **still passing for the `datom-sets` spec** -- see the note below. |

**Standing gates**: the full suite before every commit with the count in the message, and
`R CMD check --as-cran` before the PR. Both inherited from `.github/copilot-instructions.md`.

### A note on `dev/check-spec.R`, because it does not gate this spec

Measured 2026-09-21, and it is not what the name suggests: **that script is written for the
`datom-sets` spec specifically**, not for specs in general. Run against this one it reports four
failures that mean nothing here -- it requires the `datom-sv1` encoder pseudocode to appear in all three
files, expects task numbering to start at 0, and its criteria-named-in-tests check matched this spec's
`AC1`-`AC12` against tests belonging to *another* spec's criteria of the same number, reporting 8 of 12
as covered. **That last one is worse than a false negative: it is a false pass.**

So the gate for this spec is that the script **keeps passing for `datom-sets`** -- i.e. nothing done here
breaks it -- and it is run the way it always is, with no argument:

```
Rscript dev/check-spec.R          # defaults to .kiro/specs/datom-sets
```

Do **not** run it against `.kiro/specs/sets-release-readiness` and do not "fix" the failures it reports
there. Generalising it is a real piece of work with its own value, and it belongs in the Backlog rather
than inside a documentation spec.

---

## Open questions for the owner

Each states the default if nothing is said, so silence is safe.

1. **Which bucket and repo name should the credentialed run use?** `dev/e2e-solo-s3.R` defaults to
   bucket `datom-test` with a unique per-run prefix and creates its own GitHub repo. **Default: the
   same bucket, and a repo named for the run** -- one fewer thing to configure, and that bucket already
   exists for this purpose.
2. **One vignette or two?** **Default: one**, covering the whole arc. Two articles would repeat the
   setup, and the editing half only makes sense once the building half is on the page. If it grows past
   a comfortable single read, split it then rather than planning the split now.
3. **How aggressively should NEWS be cut?** **Default: aim for the 0.1.1 block's shape** -- a short
   paragraph per area plus bullets -- rather than a target word count, and let R3.2 stop the cut wherever
   a destination is missing.
