# Deferred vignettes (parked after the GOV_SEAM lift-out)

These articles are **parked, not deleted**. They are preserved verbatim (no content edits)
under `dev/` so they are excluded from the package build and the pkgdown site (the `^dev$`
rule in `.Rbuildignore`), while keeping their narrative arc intact for reassembly later.

## Why they are here

After the `gov-seam-liftout` spec (landed 2026-06-20), datom no longer owns the governance
**write** surface. Five exports were removed from datom and now belong to the `datomanager`
companion package:

- `datom_init_gov`
- `datom_attach_gov`
- `datom_pull_gov`
- `datom_sync_dispatch`
- `datom_decommission`

Every article below documents that governance interface (attach/portfolio/handoff/migration)
or a design concept that only exists once governance is attached. They cannot render
correctly against current datom because they reference removed functions. Rather than rewrite
them blind, we park them verbatim and re-integrate them as a **rewrite against datomanager's
real gov API** once it ships. This directory is the source of truth for that future rework.

> **Do not edit these files in place** to "fix" the removed-function calls. The rewrite
> happens later, against datomanager's API, as its own unit of work. Editing here would lose
> the verbatim arc this parking scheme exists to preserve.

## What was parked

### Articles (9)

| File | Original `_pkgdown.yml` group | Journey title |
|------|-------------------------------|---------------|
| `promoting-to-s3.Rmd` | Scale Up | S3 Setup and Promotion |
| `handing-off.Rmd` | Scale Up | Handing Off to a Statistician |
| `second-engineer.Rmd` | Scale Up | A Second Engineer Joins |
| `credentials-in-practice.Rmd` | Reference | Credentials in Practice |
| `buckets-and-prefixes.Rmd` | Reference | Buckets and Prefixes |
| `design-ref-json.Rmd` | Design | ref.json and Always-Migration-Ready Storage |
| `design-governance-json.Rmd` | Design | governance.json and the Dual-Pointer Pattern |
| `design-dispatch.Rmd` | Design | dispatch.json and Self-Serve Access |
| `design-two-repos.Rmd` | Design | Two Repositories: Governance vs. Data |

### Resume scripts, under `vignette-setup/`

The `resume_article_N.R` chain let a reader jump into article N without running the prior
articles. The whole chain now lives here: the rendered Get Started articles no longer source
a resume script (the sourcing UX was pulled until `datomanager` is ready), so
`resume_article_2.R` and `resume_article_3.R` were moved out of `inst/vignette-setup/`
alongside the rest. `inst/vignette-setup/` keeps only `datom.css` (still linked by the
rendered articles).

| Script | Rebuilds the state for |
|--------|------------------------|
| `resume_article_2.R` | Article 2 (`month-2-arrives`) -- parked here |
| `resume_article_3.R` | Article 3 (`folder-of-extracts`) -- parked here |
| `resume_article_4.R` | Article 4 (`promoting-to-s3`) -- parked here |
| `resume_article_5.R` | Article 5 (`handing-off`) -- parked here |
| `resume_article_6.R` | Article 6 (`second-engineer`) -- parked here |
| `resume_article_7.R` | Article 7 (`governing-a-portfolio`) -- handed off (see below) |
| `resume_article_8.R` | Article 8 (`auditing-reproducibility`) -- handed off (see below) |

`resume_article_7.R` and `_8.R` support the two articles that were **handed off** to
datomanager (Bucket C, below). datom keeps the resume scripts because they are part of the
datom resume chain and will be needed when the journey is reassembled.

## The full user journey (for reassembly)

The original suite told one story: STUDY_001 over six months. Ordering, with disposition:

1. `first-extract` -- stays (rendered)
2. `month-2-arrives` -- stays (rendered; `resume_article_2.R` parked here)
3. `folder-of-extracts` -- stays (rendered; `resume_article_3.R` parked here)
4. `promoting-to-s3` -- **parked here** (`resume_article_4.R`)
5. `handing-off` -- **parked here** (`resume_article_5.R`)
6. `second-engineer` -- **parked here** (`resume_article_6.R`)
7. `governing-a-portfolio` -- **handed off to datomanager** (`resume_article_7.R` parked here)
8. `auditing-reproducibility` -- **handed off to datomanager** (`resume_article_8.R` parked here)
9. `looking-ahead` -- **parked here** (daapr/ecosystem framing pulled from the
   rendered site until the stack is integrated; no resume script)
10. `credentials-in-practice` -- **parked here** (Reference track, no resume script)

Standalone Design track (not part of the numbered journey):
`design-datom-model` (stays), `design-version-shas` (stays), `design-ref-json` (parked),
`design-governance-json` (parked), `design-dispatch` (parked), `design-two-repos` (parked),
`design-serverless` (stays).

## Handed off to datomanager (not in this directory)

Two pure-governance articles were removed from datom entirely and preserved on the
datomanager side at `datomanager/dev/vignettes-from-datom/` (with a `NOTE.md`):

- `governing-a-portfolio.Rmd`
- `auditing-reproducibility.Rmd`

## Reassembly checklist (future work, once datomanager's gov API lands)

1. Rewrite each parked article against datomanager's gov functions (renamed `gov_*` surface).
2. Decide whether the migration arc (`promoting-to-s3`) re-enters as a datom article or moves
   to datomanager; the rendered datom site already covers the gov-free S3 start via
   `start-on-s3`.
3. Restore the relevant resume scripts to `inst/vignette-setup/` (or datomanager's equivalent).
4. Re-add the articles to whichever package's `_pkgdown.yml` owns them.
