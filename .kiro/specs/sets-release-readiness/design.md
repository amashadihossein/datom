# Design -- sets release readiness

Requirements: `requirements.md`. Source issue: [#114](https://github.com/amashadihossein/datom/issues/114).

---

## 1. Read first

Before touching anything here, read these three. They are short and each one prevents a specific
mistake this spec is prone to.

| File | What it stops you doing |
|---|---|
| `dev/e2e-sets.R` header | Re-deriving the offline walk. The credentialed script covers what that one *cannot*, and the header says exactly what that is, in its CAVEAT block |
| `dev/e2e-solo-s3.R` | Hand-rolling sandbox setup. It already solves credentials, per-run isolation and teardown |
| `dev/dev-sandbox.R` | Reimplementing `sandbox_store()` / `sandbox_up()` / `sandbox_down()`, which are the reusable half |

And one fact that shapes every documentation decision here: **`^dev$` is in `.Rbuildignore`.** Nothing
under `dev/` reaches an installed package. The previous spec satisfied its documentation requirement by
writing to two files that do not ship, and nobody noticed until a reader asked where the vignette was.

## 2. The three pieces, and why the order is fixed

```
credentialed E2E  --(observed transcripts)-->  vignette  --(a destination to point at)-->  terse NEWS
```

Each arrow is a dependency, not a preference.

* The vignette must show output somebody watched. Writing it before the script exists means composing
  plausible output, which no check in this repo can catch (R2.4).
* NEWS can only be cut once the reasoning has somewhere to live (R3.2). Cutting first deletes the only
  copy of an explanation.

So a task that finishes late does not block the others' *value*, but reordering them produces
documentation that is confidently wrong.

## 3. The credentialed script

### 3.1 Reuse, and the one gap in what is reusable

`dev/dev-sandbox.R` supplies the scaffolding: `sandbox_store()` builds a store from bucket/prefix/region,
`sandbox_up()` creates the GitHub repo through `datom_init_repo()` and optionally seeds example data,
`sandbox_down()` tears down. `dev/e2e-solo-s3.R` shows the shape: a timestamped `stamp`, a per-run
`prefix` and `repo_name`, everything inside `tryCatch` with teardown in the exit path.

**The gap: `sandbox_up()` cannot create a product repo.** It calls `datom_init_repo()` with `path`,
`project_name`, `store`, `create_repo` and `repo_name`, and passes no `mode` or `set`. A set write
refuses a repo that does not declare `mode: product` and name its set, so the script cannot get off the
ground through the sandbox as it stands.

**Decision: add `mode` and `set` passthrough to `sandbox_up()`**, defaulting to `NULL` so every existing
caller is unaffected. Two lines in `.sandbox_defaults()` and two in the `datom_init_repo()` call.

Chosen over having the sets script call `datom_init_repo()` directly, for a reason beyond tidiness: the
owner's stated purpose is **kicking the tires**, and a sandbox that cannot produce a product repo cannot
be used for that interactively. The passthrough is the difference between one script working and the
whole sandbox tooling understanding the second artifact kind.

`dev/` is not shipped, so this is dev tooling rather than package behaviour, and R4.1 is not touched.

### 3.2 What the script asserts, and what it deliberately leaves to the offline one

The claim of this script is **the entry path and real storage**, not the set semantics. Semantics are
already pinned by 4292 unit tests and 51 offline claims; repeating them here buys nothing and makes the
script slow to read.

| Asserted here | Why it cannot be asserted offline |
|---|---|
| `datom_init_repo(mode = "product", set = ...)` writes a config a set write accepts | the offline script writes that file by hand |
| `datom_get_conn()` opens a connection that a set write accepts | same -- the offline script builds `datom_conn` directly |
| the config-format gate runs at connection time on a real repo | never exercised, for the same reason |
| `ref.json` resolution reaches the right bucket and prefix | there is no ref indirection in the offline local fixture |
| a set's `project` field is the repo's **own** declared name | the offline fixture's connection label and config agree by construction, so the two cannot be told apart |
| a storage-only reader with no clone and **no PAT** resolves the set from S3 | offline covers the shape against a local directory; S3 is where the claim is actually made |
| one member's data fetched from S3 through the citation | same |
| teardown removes repo, clone and objects | there is nothing remote to remove offline |

It still walks the full lifecycle (R1.3) because the **sequence** is what integration failures live in,
but each step asserts the integration fact rather than re-asserting the semantics.

### 3.3 Failing early on missing credentials

R1.6 wants a clear failure before any work. So: check `GITHUB_PAT` and the AWS credentials **first**,
before the store is built, and abort naming which one is missing and what scope it needs. The cost of
getting this wrong is a half-created GitHub repo and objects under a prefix nobody will look at again.

### 3.4 Teardown, and the trap in it

`tryCatch` with teardown on both paths, so a failed assertion still cleans up. **The trap is a teardown
that silently does nothing**: `sandbox_down()` reports success whether or not there was anything to
remove, so the assertion that matters is a **listing after teardown** (AC3), not a return value. This is
the guard-test rule applied to cleanup -- and it is exactly the shape that bit the predecessor spec
four times (`.github/copilot-instructions.md` rule 2a).

## 4. The vignette

### 4.1 One article, not two

**Decision: one.** Two would repeat the setup, and the editing half only makes sense to somebody who has
seen the building half. If it outgrows a single comfortable read, split it then -- a split planned in
advance tends to produce two half-articles.

**Proposed name: `vignettes/citable-sets.Rmd`**, sitting alongside `getting-started`, `start-on-s3` and
`source-lineage` as a user-facing how-to rather than a `design-*` article. The name is a low-stakes
choice; if a better one turns up while writing, take it.

### 4.2 Shape

Why before how (R2.2), so the first screen contains no function call. It picks up where
`vignette("start-on-s3")` leaves off (R2.8): the reader already has a study onboarded at
`s3://<bucket>/<study>/datom/`, and this article makes a citable product from it.

1. **The problem.** A result was built from twenty tables. Months later, half of them have new
   versions. "Which exact data produced this result" has no answer anyone wrote down.
2. **What a set is.** A citable list of exact data versions, with a name and a version of its own.
   Not a copy of the data -- a list of pointers.
3. **A second repo for the product.** The onboarding repo from `start-on-s3` holds raw data; it will
   not hold a set (it onboards, it does not build). So create a product repo beside it -- same bucket,
   a prefix like `adam` -- in its own working directory (R2.9, Case A). This is the step the one-repo
   draft was missing, and it is where the reader learns why there are two.
4. **Build the set.** `datom_assemble_set()` -> `datom_add_member()` -> `datom_write_set()`, citing the
   onboarded tables by version. Labels introduced as the way you find members later, not decoration.
5. **Cite it, and read it from elsewhere.** A reader with storage access and no git clone resolves the
   set -- the property that makes it worth having, and one a reader will not guess.
6. **An input moves.** A new month lands in the onboarding repo; `datom_update_members()` repoints the
   set, reports what moved before writing, and a refresh that finds nothing writes nothing.
7. **Retire one.** `datom_remove_members()`, and that a repoint plus a drop land in one commit message.
8. **What a set does not do** (R2.6): holds no data, never drifts to "latest", changes nothing about
   its members. Plus the **one-level rule** (R2.5) -- a set can cite another set, and reading it hands
   back a pointer rather than opening it, so cost does not compound. One closing sentence points at the
   cross-study, cross-bucket pool as a later article (Case B), with no detail (R2.9).
9. **Teardown**, matching `start-on-s3`'s: delete both repos and both prefixes, so a reader following
   along on real infrastructure is not left paying for it.

Language throughout is plain (R2.10): "a citable list of exact data versions", "one entry in that
list", never the spec's own vocabulary. The transcripts come from the credentialed run's output
(R2.4), which uses this exact layout, so they can be pasted rather than composed.

### 4.3 Chunks are not evaluated, and that is a constraint on honesty

`eval = FALSE` matches the existing vignettes and keeps credentials out of the build. It also means
**nothing verifies the output shown** -- so the output must come from a run somebody watched, and the
task record names which run produced which block (AC8). The failure this prevents is a transcript that
reads perfectly and does not match the software.

## 5. `NEWS.md`

### 5.1 The method: a mapping table, built before anything is deleted

For each claim in the development block, write down where it goes **first**:

| Destination | What belongs there |
|---|---|
| stays in NEWS | what changed, whether it breaks, what to do |
| roxygen | per-verb behaviour, refusals, return shape -- much is already there |
| the vignette | cross-cutting narrative: the artifact-kind model, the lifecycle, the upgrade consequence |
| nowhere -> **stays in NEWS** | R3.2. Verbose beats deleted |

The table goes in the task's DONE record, which is what makes AC9 checkable: the claim is not "it got
shorter" but "every removal has a destination".

### 5.2 Where a reader lands first

The two upgrade-critical items -- the `artifacts` rename and the writer refusals -- go to the top (R3.3).
Everything else is ordered after them. A reader who stops reading after two items must have hit the two
that can cost them data discovery.

### 5.3 The convention, so this does not recur

R3.6 puts it in `.github/copilot-instructions.md`: NEWS states what changed, whether it breaks, and what
to do; reasoning goes to roxygen or a vignette; **never cite `dev/` or `.kiro/` from NEWS**, because
neither ships. That last clause is the durable lesson from this spec, and it is the one a future release
will otherwise repeat.

---

## 6. Invariants

* **I1** No file under `R/` changes behaviour. Roxygen prose may move; code does not.
* **I2** No NEWS entry and no vignette cross-reference points at `dev/` or `.kiro/` (R3.5).
* **I3** Every output block in the vignette was observed in a real run, and the record says which.
* **I4** Nothing is removed from NEWS without a named destination.
* **I5** The credentialed script is never added to CI and never runs during `R CMD check`.
* **I6** Teardown is verified by listing what remains, never by a teardown function's return value.
* **I7** `dev/e2e-sets.R` keeps working, unchanged, with no credentials.

## 7. Correctness properties

* **P1** The credentialed script exits non-zero on a deliberately broken claim (AC2).
* **P2** A set written through the real entry path is readable by a storage-only connection with no
  clone and no PAT (AC5, AC6).
* **P3** After teardown, listing the prefix, the GitHub repos and the local base directory finds nothing
  from the run (AC3).
* **P4** With `GITHUB_PAT` unset, the script aborts before creating anything (AC4).
* **P5** `R CMD check --as-cran` stays 0E/0W with the vignette added (AC7).
* **P6** Every claim removed from NEWS is locatable in roxygen or the vignette (AC9).

## 8. Rejected alternatives

| Option | Why not |
|---|---|
| Extend `dev/e2e-sets.R` to take credentials when present | Its value is being runnable by anyone with nothing configured. A branch on credentials makes the offline path the untested one |
| Run the credentialed script in CI | It creates and deletes real repos and objects. CI does not have those credentials by deliberate choice, and giving it them widens the blast radius of a workflow edit |
| Evaluate the vignette against a local backend so output is generated at build time | Tempting, and it would make output self-verifying -- but the vignette's subject is the storage-only reader and the real entry path, which a local fixture cannot show. A vignette that quietly demonstrates something narrower than it claims is worse than one that shows observed output |
| Move NEWS detail into `dev/datom_specification.md` | It does not ship. This is the exact mistake being corrected |
| Assign the version and write the release heading here | A release decision with its own moving parts (`DESCRIPTION`, `cran-comments.md`, CRAN-SUBMISSION). R3.7 keeps it out |
