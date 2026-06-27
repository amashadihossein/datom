# Requirements Document

_Scope: **datom vignette suite** cleanup following the GOV_SEAM lift-out._

> **Execution note:** This spec is intended to be executed with **GitHub Copilot**, not Kiro.
> Kiro authored it and has switched its active work to the `datomanager` package. The
> cross-package preservation step (Bucket C below) is **already done** on the datomanager
> side — the two gov articles are parked at
> `datomanager/dev/vignettes-from-datom/` with a `NOTE.md`. This spec's datom-side tasks may
> therefore delete the datom copies safely.

## Introduction

After the GOV_SEAM lift-out (`gov-seam-liftout` spec, landed 2026-06-20), datom no longer
owns the governance write surface. Five exports were removed and now belong to `datomanager`:
`datom_init_gov`, `datom_attach_gov`, `datom_pull_gov`, `datom_sync_dispatch`,
`datom_decommission`. datom retained gov **reads** plus the data-side helpers
(`datom_repo_attach_governance`, `datom_repo_delete`, `datom_projects`).

The vignette suite was **not** updated. Every cloud article sets `eval = FALSE`, so the
package and pkgdown site still build, but the rendered articles document removed functions
as if they were datom's. This phase makes the published pkgdown site immediately accurate
with a **minimal, gov-free vignette set**, while **preserving** the deferred gov-interface
stories for re-integration once datomanager's gov API is functional.

This is a documentation-only phase: no `R/` source changes, no NAMESPACE changes.

## Glossary

- **Bucket A / B / C**: the three vignette dispositions defined below -- keep & render, defer
  & exclude, hand off to datomanager.
- **Solo_Project**: a datom project with `governance = NULL`; location authority is
  `project.yaml`. No gov clone, no `ref.json` in a gov repo.
- **Removed export**: one of the five functions deleted from datom by the `gov-seam-liftout`
  spec (`datom_init_gov`, `datom_attach_gov`, `datom_pull_gov`, `datom_sync_dispatch`,
  `datom_decommission`).
- **Parked / deferred**: relocated verbatim into build-ignored `dev/vignettes-deferred/`,
  removed from `_pkgdown.yml`, content untouched, awaiting rework against datomanager's API.
- **Rendered set**: the articles pkgdown actually builds into the site -- after this phase,
  exactly Bucket A.

## Goal

A datom that can be **published now** with a small, correct, gov-free vignette suite, plus a
clean parking scheme that preserves the narrative arc of every deferred article so the
cross-package story can be reassembled later.

## Vignette Disposition (authoritative classification)

Three buckets. The full rationale and per-file edits are in `design.md`.

### Bucket A — Keep & render (fix in place; gov-free, works today)

| Vignette | Action |
|----------|--------|
| `first-extract.Rmd` | Fix teardown: `datom_decommission()` -> `datom_repo_delete()` (solo path). Fix dead cross-links to deferred articles. |
| `month-2-arrives.Rmd` | Keep (resume_article_2.R is solo/local, gov-free). Verify, fix any dead cross-links. |
| `folder-of-extracts.Rmd` | Keep (resume_article_3.R). Verify gov-free, fix dead cross-links. |
| `start-on-s3.Rmd` | **NEW.** S3-native solo project, no local-to-S3 migration, no governance. The "I'm already sold, start here" path. |
| `source-lineage.Rmd` | Keep. Rewrite setup chunk to drop the `gov = datom_store_s3(...)` component (use `governance = NULL`). |
| `looking-ahead.Rmd` | Keep. Reword gov framing to forward-looking / companion-package terms. |
| `design-datom-model.Rmd` | Keep. Light reword of conceptual gov mentions. |
| `design-version-shas.Rmd` | Keep as-is (gov-free). |
| `design-serverless.Rmd` | Keep. Reword gov mentions to architectural / forward-looking (no removed-function calls present). |
| `README.Rmd` | Reword 3 gov mentions; ensure landing page accurate. Re-knit to `README.md`. |

### Bucket B — Defer & exclude from rendering (park, preserve arc)

Move the `.Rmd` (and the resume scripts tied only to deferred articles) into the
build-ignored `dev/vignettes-deferred/`, and remove their `_pkgdown.yml` entries. They stay
in the repo, intact, for rework once datomanager's gov API lands.

- `promoting-to-s3.Rmd` (the local->S3 **migration** story; superseded for the published site
  by `start-on-s3.Rmd`; its migration arc is re-integrated later when gov is ready)
- `handing-off.Rmd`
- `second-engineer.Rmd`
- `credentials-in-practice.Rmd`
- `buckets-and-prefixes.Rmd`
- `design-ref-json.Rmd`
- `design-governance-json.Rmd`
- `design-dispatch.Rmd`
- `design-two-repos.Rmd`
- Resume scripts `resume_article_4.R` .. `resume_article_8.R` (tied to deferred articles).
  Keep `resume_article_2.R` and `resume_article_3.R` (used by Bucket A).

### Bucket C — Hand off to datomanager (datom-side removal only)

Already preserved at `datomanager/dev/vignettes-from-datom/`. datom side just removes the
copies and their `_pkgdown.yml` entries.

- `governing-a-portfolio.Rmd`
- `auditing-reproducibility.Rmd`

## Requirements

### Requirement 1: Published site shows only accurate, gov-free articles

**User Story:** As a maintainer about to publish datom, I want the pkgdown site to render
only articles that are correct against the current datom API, so that no reader sees a
removed function presented as datom's.

#### Acceptance Criteria

1. THE rendered pkgdown site SHALL contain only the Bucket A articles.
2. NO rendered article SHALL reference any of the five removed exports (`datom_init_gov`,
   `datom_attach_gov`, `datom_pull_gov`, `datom_sync_dispatch`, `datom_decommission`).
3. NO rendered article SHALL contain a cross-link (`<name>.html`) to a deferred or moved
   article; such links SHALL be repointed to a surviving article or removed.
4. `_pkgdown.yml` SHALL list only Bucket A articles, with section titles that no longer
   imply datom owns governance.

### Requirement 2: A gov-free S3 starting story exists

**User Story:** As a user who is already sold on datom and does not want to dabble locally
first, I want a vignette that initializes a project directly on S3, so that I can start in
object storage without a migration step.

#### Acceptance Criteria

1. THE Datom_Package SHALL include a new vignette that creates a Solo_Project whose data
   store is `datom_store_s3(...)` and whose `governance` is `NULL`.
2. THE new vignette SHALL NOT call any gov function and SHALL NOT depend on a migration
   from a local backend.
3. THE new vignette SHALL use `datom_repo_delete()` for teardown.
4. THE new vignette SHALL be authored so the future managed-migration arc (deferred
   `promoting-to-s3.Rmd`) can be reattached without contradicting it (start-on-S3 and
   migrate-to-S3 are complementary entry points, per the existing story architecture).

### Requirement 3: Deferred articles are preserved, not deleted

**User Story:** As a maintainer, I want every deferred gov-interface article preserved with
its narrative arc intact, so that re-integration after datomanager ships is a rewrite, not a
rewrite-from-memory.

#### Acceptance Criteria

1. EACH Bucket B vignette SHALL be relocated to `dev/vignettes-deferred/` (build-ignored via
   the existing `^dev$` `.Rbuildignore` rule).
2. THE resume scripts tied only to deferred articles (`resume_article_4.R` ..
   `resume_article_8.R`) SHALL be relocated alongside them (e.g.
   `dev/vignettes-deferred/vignette-setup/`) and removed from `inst/`.
3. `resume_article_2.R` and `resume_article_3.R` SHALL remain in `inst/vignette-setup/`
   (Bucket A depends on them).
4. NO Bucket B file SHALL be edited for content in this phase (script refactor is explicitly
   deferred); they are moved verbatim.
5. A short `dev/vignettes-deferred/README.md` SHALL record the parking rationale, the
   original `_pkgdown.yml` grouping, and the journey-arc ordering so the suite can be
   reassembled.

### Requirement 4: Gov articles handed to datomanager are removed from datom

**User Story:** As a maintainer, I want the two pure-governance articles removed from datom,
so that datom's docs cover only datom.

#### Acceptance Criteria

1. THE Datom_Package SHALL NOT contain `vignettes/governing-a-portfolio.Rmd` or
   `vignettes/auditing-reproducibility.Rmd` after this phase.
2. Removal SHALL proceed only because the verbatim copies already exist at
   `datomanager/dev/vignettes-from-datom/` (preservation precondition is satisfied).
3. THE `_pkgdown.yml` SHALL NOT reference either removed article.

### Requirement 5: Package and site build green

**User Story:** As a maintainer, I want the package and site to build cleanly after the
cleanup, so that publishing is a non-event.

#### Acceptance Criteria

1. `devtools::build_vignettes()` (or `R CMD build`) SHALL complete with no error and no
   non-ASCII warning on the surviving vignettes.
2. `pkgdown::build_site()` SHALL complete with no error and no "missing topic" / broken
   article-link failure.
3. THE existing full `devtools::test()` suite count SHALL be unchanged (documentation-only
   phase; no test should be added or lost).
4. NO file under `R/` and NO line of `NAMESPACE` SHALL change in this phase.
