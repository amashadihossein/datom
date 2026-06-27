# Design Document

_Scope: **datom vignette suite** cleanup following the GOV_SEAM lift-out._

> **Execution: GitHub Copilot.** Kiro authored this spec and switched to `datomanager`.
> Read `requirements.md` first; the Bucket A/B/C classification there is authoritative.

## Overview

After the GOV_SEAM lift-out, datom no longer owns the governance write surface, but its
vignette suite still documents the five removed exports as if they were datom's. This is a
**documentation-only** phase that (a) trims the rendered pkgdown site to a minimal, gov-free
set, (b) parks the deferred gov-interface articles verbatim under a build-ignored directory
so their narrative arc survives for later rework, and (c) removes two pure-governance
articles that now belong to datomanager (already preserved on that side).

### Context — read first

- The lift-out (`gov-seam-liftout` spec) removed five exports. They no longer exist in datom:
  `datom_init_gov`, `datom_attach_gov`, `datom_pull_gov`, `datom_sync_dispatch`,
  `datom_decommission`. Confirm with `grep -n 'export(' NAMESPACE`.
- datom retained: gov reads, `datom_projects()`, `datom_repo_attach_governance()`,
  `datom_repo_delete()` (solo teardown), the `datom_storage_*` extension API.
- All cloud vignettes set `eval = FALSE`. Nothing executes at build time, so this phase is
  validated by content accuracy + clean `R CMD build` / `pkgdown::build_site()`, not by
  "does the code run".
- `^dev$` is in `.Rbuildignore`. Moving deferred files under `dev/` removes them from both
  the package build and the pkgdown render (pkgdown only renders `vignettes/`).
- The resume-script chain lives in `inst/vignette-setup/resume_article_*.R`.
  `resume_article_2.R` and `_3.R` build a solo/local project (`governance = NULL`) and are
  gov-free. `resume_article_4.R`+ attach governance and support the deferred articles.

## Architecture

Three buckets, processed as independent moves plus one new file:

- **Bucket A (keep & render):** edited in place in `vignettes/`; remain in `_pkgdown.yml`.
- **Bucket B (defer):** `git mv` verbatim into build-ignored `dev/vignettes-deferred/`;
  dropped from `_pkgdown.yml`. Re-integrated in a future phase against datomanager's API.
- **Bucket C (hand off):** `git rm` from datom; the verbatim home is now
  `datomanager/dev/vignettes-from-datom/` (already populated by Kiro).

The published site is therefore a pure function of Bucket A. Because pkgdown renders every
`.Rmd` in `vignettes/` regardless of the index, exclusion is achieved by **relocating files
out of `vignettes/`**, not by editing the index alone.

## Components and Interfaces

### Component 1 -- `start-on-s3.Rmd` (new, Bucket A)

A standalone, gov-free article: "start directly on S3." Model it on `first-extract.Rmd`'s
shape (store -> init -> write -> read -> history -> teardown) but with an S3 data store and
**no governance and no migration**.

Skeleton (illustrative; all chunks `eval = FALSE`):

```r
data_component <- datom_store_s3(
  bucket = "my-datom-bucket",
  prefix = "study-001",
  region = "us-east-1"
)

store <- datom_store(
  governance = NULL,                       # solo: gov is opt-in, added later via datomanager
  data       = data_component,
  github_pat = keyring::key_get("GITHUB_PAT")
)

conn <- datom_init_repo(store = store, project_name = "STUDY_001", create_repo = TRUE)
datom_write(conn, data = datom_example_data("dm"), name = "dm", message = "Initial DM extract")
datom_read(conn, name = "dm")
datom_history(conn, name = "dm")
datom_repo_delete(conn, confirm = "STUDY_001")   # teardown
```

Front matter: `rmarkdown::html_vignette` + `%\VignetteIndexEntry{Starting on S3}`. Narrative:
the entry point for teams already committed to object storage; deliberately omits the
local-first journey. A short forward-pointer notes that **managed migration** (local -> S3,
S3 -> S3) arrives with the governance companion and is documented separately -- keeping the
door open to reattach the deferred `promoting-to-s3.Rmd` arc without contradiction (R2.4). Do
not wire it into the resume-script chain; it stands alone. Confirm `datom_init_repo()`'s
current signature against `R/repo.R` before finalizing.

### Component 2 -- Bucket A in-place fixes

- `first-extract.Rmd`: replace `datom_decommission(conn, confirm = "STUDY_001")` with
  `datom_repo_delete(conn, confirm = "STUDY_001")`. Keep the "delete local before teardown
  breaks the remote ref" caveat (applies to `datom_repo_delete` too). Repoint the two "you'll
  add it in [Promoting to S3]" forward-links (governance attachment is now a companion-package
  concern): soften to prose or point at `start-on-s3.html`.
- `month-2-arrives.Rmd`, `folder-of-extracts.Rmd`: verify no removed-function references, fix
  dead cross-links. Otherwise unchanged.
- `source-lineage.Rmd`: setup store `gov = datom_store_s3(bucket = "my-gov-bucket", ...)` ->
  `governance = NULL`. Lineage content stays (datom-native).
- `looking-ahead.Rmd`: reword the "pair of git repos ... shared governance repo" definition
  and the "portfolio register and decommission discipline" bullet so governance is a
  companion-package capability, not a built-in. Keep the daapr framing.
- `design-datom-model.Rmd`, `design-serverless.Rmd`: reword conceptual gov mentions; verify
  neither calls a removed function.
- `design-version-shas.Rmd`: no change expected (gov-free); verify.
- `README.Rmd`: reword gov mentions, re-knit to `README.md` (`devtools::build_readme()`).

### Component 3 -- Bucket B parking (defer, verbatim)

`git mv` the nine Bucket B vignettes into `dev/vignettes-deferred/` and the five gov-tied
resume scripts into `dev/vignettes-deferred/vignette-setup/` (see Data Models for the tree).
Do not edit contents (Property 2). Remove the moved articles' `_pkgdown.yml`
entries. Add `dev/vignettes-deferred/README.md` recording original grouping, journey order,
and the "blocked on datomanager gov API" note.

### Component 4 -- Bucket C removal (datom side only)

Precondition (Property 3): `datomanager/dev/vignettes-from-datom/` contains
`governing-a-portfolio.Rmd`, `auditing-reproducibility.Rmd`, `NOTE.md`. With that satisfied,
`git rm` the two datom copies and remove their `_pkgdown.yml` entries. Do not park a second
copy in datom.

### Component 5 -- `_pkgdown.yml` articles restructure

Rendered set = Bucket A only. Proposed grouping (titles avoid implying datom owns gov):

```yaml
articles:
  - title: "Get Started"
    desc: "Your first datom project: simulate, version, read."
    navbar: ~
    contents: [first-extract, month-2-arrives, folder-of-extracts]
  - title: "Start on S3"
    desc: "Begin directly in object storage."
    contents: [start-on-s3]
  - title: "Lineage & Roadmap"
    desc: "Trace data lineage; where datom sits in the daapr stack."
    contents: [source-lineage, looking-ahead]
  - title: "Design"
    desc: "Why datom is shaped the way it is."
    contents: [design-datom-model, design-version-shas, design-serverless]
```

The `reference:` (function index) section is **unchanged** -- no exports changed.

## Data Models

This phase manipulates files, not data structures. The target tree:

```
vignettes/                         # rendered (Bucket A)
  first-extract.Rmd  month-2-arrives.Rmd  folder-of-extracts.Rmd
  start-on-s3.Rmd (new)
  source-lineage.Rmd  looking-ahead.Rmd
  design-datom-model.Rmd  design-version-shas.Rmd  design-serverless.Rmd

inst/vignette-setup/               # kept (Bucket A deps)
  resume_article_2.R  resume_article_3.R  datom.css

dev/vignettes-deferred/            # parked (Bucket B, build-ignored)
  README.md
  promoting-to-s3.Rmd  handing-off.Rmd  second-engineer.Rmd
  credentials-in-practice.Rmd  buckets-and-prefixes.Rmd
  design-ref-json.Rmd  design-governance-json.Rmd  design-dispatch.Rmd  design-two-repos.Rmd
  vignette-setup/
    resume_article_4.R .. resume_article_8.R

# removed from datom (Bucket C) -> datomanager/dev/vignettes-from-datom/
  governing-a-portfolio.Rmd  auditing-reproducibility.Rmd
```

## Correctness Properties

### Property 1: Docs-only

No edits to `R/`, no edits to `NAMESPACE`, no test added or removed. If a task seems to
require an `R/` change, stop -- it is out of scope. **Validates: Requirements 5.4**

### Property 2: Preserve arc

Bucket B/C files are moved verbatim; their gov calls are NOT fixed in this phase (the rewrite
happens later against datomanager's real API). **Validates: Requirements 3.4, 4.2**

### Property 3: Preservation precondition

Bucket C datom copies are deleted only because the verbatim copies already exist at
`datomanager/dev/vignettes-from-datom/`. **Validates: Requirements 4.2**

### Property 4: ASCII only

Vignettes contain only ASCII (`--`, `->`, `...`, straight quotes). Check:
`LC_ALL=C grep -lr '[^[:print:][:space:]]' vignettes/*.Rmd`. **Validates: Requirements 5.1**

### Property 5: No dangling links

No surviving article links to a moved article's `.html`. **Validates: Requirements 1.3**

## Error Handling

- If `datomanager/dev/vignettes-from-datom/` is missing or incomplete, **STOP** before Task 2
  and restore it; never delete the only copy of a Bucket C article (Property 3).
- If `git status` shows any change under `R/` or `NAMESPACE`, revert it -- the phase is
  mis-scoped at that point (Property 1).
- If `pkgdown::build_site()` reports a broken article link, the dead-link sweep (Property 5)
  was incomplete; fix the link rather than deleting the target reference blindly.

## Testing Strategy

Verification checklist (maps to Requirement 5):

1. `LC_ALL=C grep -rn 'datom_init_gov\|datom_attach_gov\|datom_pull_gov\|datom_sync_dispatch\|datom_decommission' vignettes/` returns nothing.
2. `grep -rn '<moved-article>.html' vignettes/` returns nothing (all Bucket B/C basenames).
3. ASCII check (Property 4) clean.
4. `devtools::build_vignettes()` / `R CMD build` clean.
5. `pkgdown::build_site()` clean -- no missing-topic or broken-article-link error.
6. `devtools::test()` count unchanged vs the Task 0 baseline.
7. `git status` shows zero changes under `R/` and `NAMESPACE` (Property 1).

### Out of scope

- Rewriting any deferred article against datomanager's API (future phase).
- Refactoring the resume-script chain (explicitly deferred by the requester).
- Re-authoring a datom-only audit story (noted in datomanager's `NOTE.md` as a future option).
- Any `R/` or `NAMESPACE` change.
