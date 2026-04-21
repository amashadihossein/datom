# Phase 14: Public Release Preparation

**Status**: Planned
**Branch**: `phase/14-public-release-prep` (to be created from `main`)
**Goal**: Make the `datom` repository ready to flip from private to public on GitHub — scrub stale names, fix licensing metadata, add standard open-source files, and set up CI so public contributors see a working project.

## Context

The repo has been private through Phases 1–13. All core functionality is in place (1177 tests passing, S3 + local backends, two-component store model). Before the repository becomes publicly visible, a handful of residual issues from the `tbit → datom` rename and the pre-release posture need to be cleaned up, and a few conventional open-source scaffolding files should be added.

### Read first

- [.github/copilot-instructions.md](.github/copilot-instructions.md) — operational discipline
- [dev/README.md](dev/README.md) — phase workflow + completion procedure
- [LICENSE](LICENSE), [.Rbuildignore](.Rbuildignore), [README.Rmd](README.Rmd) — the core files getting touched

### Invariants (must-never)

- **Do not commit any credentials** (AWS keys, GitHub PATs, SSH keys). Verify every new file.
- **Do not break `devtools::check()`** — must remain clean at phase end.
- **Do not break E2E**. Re-run [dev/e2e-test.R](dev/e2e-test.R) and [dev/e2e-test-local.R](dev/e2e-test-local.R) after Chunk 4.
- **Do not reshape public API**. This phase is scaffolding + metadata only; if an API change is tempting, file it as backlog.

## Findings from pre-phase survey

### Must-fix (stale / incorrect)
1. `LICENSE` copyright holder says "tbit authors" — stale from pre-rename.
2. `.Rbuildignore` still lists `^tbit\.Rproj$` while the actual file is `datom.Rproj`.
3. [R/read_write.R](R/read_write.R#L34) has a `TODO: Phase 6 will add dispatch via context + dispatch.json` comment — Phase 6 shipped; comment is misleading.
4. README badges include a CRAN status badge, but the package is not on CRAN.
5. No `NEWS.md` — standard for an R package and referenced by pkgdown.

### Missing open-source scaffolding
6. No `CONTRIBUTING.md`.
7. No `CODE_OF_CONDUCT.md`.
8. No `SECURITY.md` (low bar is fine, but useful for a credential-handling tool).
9. No issue templates or PR template under `.github/`.
10. No GitHub Actions workflows (R-CMD-check, pkgdown).

### Dev folder hygiene
11. `dev/dev-sandbox.R`, `dev/e2e-test.R`, `dev/e2e-test-local.R` hardcode personal bucket names (`datom-test`, `datom-gov-test`) and keyring service/user pairs (`"datom-developer"/"remotes"`, `"kol"/"remotes"`). Not secret, but presumes one developer's setup. Worth centralizing defaults so public contributors see one obvious place to edit.
12. `dev/archive/` contains 5 drafting/sprint docs with chat-style headers ("The Gist", "Why Now") and pre-rename language ("tbit → datom rename already in progress"). `dev_guide_v1.md` describes a stale `access.json` design. Zero public value. → **Untrack via gitignore; keep locally.**
13. `dev/datomaccess_overview.md` is a 683-line forward-looking description of a sister package that does not yet exist. Reads as speculative / vaporware to a public visitor. → **Untrack via gitignore; keep locally.**

### Source-comment crumbs (exposed publicly via pkgdown + GitHub)
14. Phase/Chunk scaffolding references inside [R/](R/) source comments:
    - [R/read_write.R](R/read_write.R#L34) — `# TODO: Phase 6 will add dispatch…` (covered in Chunk 1)
    - [R/utils-validate.R](R/utils-validate.R#L56) — `# --- S3 namespace safety (Phase 7) ---`
    - [R/sync.R](R/sync.R#L450) — `# --- stale-state check (Phase 7) ---`
    - [R/utils-sha.R](R/utils-sha.R#L124) — `# Pull before write to ensure fresh state (Phase 7)`
    - [R/store.R](R/store.R#L3) — `# Type-specific constructors: datom_store_s3() (now), datom_store_local() (Phase 12)`
    - [R/validate.R](R/validate.R#L161) + [R/validate.R](R/validate.R#L175) — `pre-Phase 7 manifest` in roxygen (renders on pkgdown reference page)
15. `# Phase N, Chunk M` headers in multiple [tests/testthat/](tests/testthat/) files — ships in source tarball. Lower visibility, optional.
16. [.github/copilot-instructions.md](.github/copilot-instructions.md) is rendered on the public pkgdown site as [docs/copilot-instructions.html](docs/copilot-instructions.html). Content is professional but includes internal-dev sections ("Operational Discipline", "Model Escalation"). Worth a final read-through — not necessarily a delete.

### Verified clean (no action)
- No secrets/keys in tracked files.
- No OS/IDE cruft tracked (`.DS_Store`, `.Rproj.user`, `.Rhistory`, `.RData`).
- `docs/` is gitignored.
- `data-raw/`, `vignettes/`, `inst/` look clean.

## Chunks

### Chunk 1 — Metadata hygiene (must-fix set)
**Scope**: The fast, mechanical fixes.
- Update `LICENSE` copyright holder: `tbit authors` → `Afshin Mashadi-Hossein` (match `DESCRIPTION` author).
- Update `.Rbuildignore`: `^tbit\.Rproj$` → `^datom\.Rproj$`.
- Remove stale `TODO: Phase 6 …` comment in [R/read_write.R](R/read_write.R#L34).
- Remove CRAN badge from [README.Rmd](README.Rmd) and regenerate [README.md](README.md) via `devtools::build_readme()`.
- Create `NEWS.md` with a single top entry: `# datom (development version)` + a short note that the package is pre-release.
- Decide on [cran-comments.md](cran-comments.md): since there's no imminent CRAN release and it's currently content-free, delete it (can be regenerated with `usethis::use_cran_comments()` when CRAN submission is real). Note the rationale in commit message.

**Acceptance**: `devtools::check()` clean; README renders without the CRAN badge; `NEWS.md` exists.

### Chunk 2 — Contributor-facing scaffolding
**Scope**: Standard open-source files. Keep them brief and honest — this is a pre-release research package, not a mature product.
- `CONTRIBUTING.md` — short: reference `dev/README.md` for contributors willing to dig in, but set expectations that the package is pre-release and APIs churn.
- `CODE_OF_CONDUCT.md` — use `usethis::use_code_of_conduct(contact = "amashadihossein@gmail.com")` (Contributor Covenant).
- `SECURITY.md` — minimal: "report privately to <email>; do not open public issues for security concerns." One paragraph is enough.
- `.github/ISSUE_TEMPLATE/bug_report.md` and `feature_request.md` — conventional minimal templates.
- `.github/PULL_REQUEST_TEMPLATE.md` — short checklist (tests pass, NEWS entry if user-facing, etc.).
- Update `.Rbuildignore` to ignore the new top-level OSS files so they don't ship in the tarball (`^CONTRIBUTING\.md$`, `^CODE_OF_CONDUCT\.md$`, `^SECURITY\.md$`, `^\.github$` is already there).

**Acceptance**: `devtools::check()` clean; new files visible on GitHub; no build warnings.

### Chunk 3 — GitHub Actions CI
**Scope**: Public repos without green CI look abandoned. Use the `r-lib/actions` canonicals.
- `.github/workflows/R-CMD-check.yaml` — standard matrix (devel + release on ubuntu-latest, release on macos + windows). Use `usethis::use_github_action("check-standard")` as the starting point.
- `.github/workflows/pkgdown.yaml` — build + deploy to `gh-pages` on push to `main`. Defer enabling GitHub Pages in repo settings to the user (it's a UI action).
- `.github/workflows/test-coverage.yaml` — optional; include only if it's a one-liner via `usethis::use_github_action("test-coverage")`. Skip if it requires extra setup.
- Ensure workflows don't require secrets we don't have (e.g., CODECOV_TOKEN — if skipping coverage, this is moot).

**Note**: Workflows will not run on the phase branch unless we push it; they'll run on PR to `main`. That's fine — that's also the first public-facing validation.

**Acceptance**: Workflows exist and are syntactically valid (yamllint or `gh workflow list` after push). Don't block the phase on workflow green runs against `main`; they will run on the phase PR.

### Chunk 4 — Dev folder + source-comment public-readiness
**Scope**: Clean up visible-but-not-shipped `dev/` tree and scrub scaffolding residue from source comments. **Zero behavior change** — comments and docs only.

**Dev folder**:
- **`dev/archive/`** and **`dev/datomaccess_overview.md`**: untrack from git (remove from remote) but keep locally via `.gitignore`. This preserves records on disk without exposing them publicly.
  1. Add `dev/archive/` and `dev/datomaccess_overview.md` to `.gitignore`.
  2. Run `git rm --cached dev/archive/ -r` and `git rm --cached dev/datomaccess_overview.md` to stop tracking them. Files remain on disk untouched.
  3. Commit — the files disappear from the remote but stay in the local working tree.
- **`dev/dev-sandbox.R`, `dev/e2e-test.R`, `dev/e2e-test-local.R`**: centralize tunables. Ensure `.sandbox_defaults()` is the single source of truth for bucket names, keyring entries, etc., and that `e2e-test*.R` scripts pull from those defaults (or accept explicit args) instead of hardcoding `"datom-test"` etc. inline. Goal: a public contributor reading these files sees **one** obvious place to edit for their environment.

**Source-comment scrubbing** (no behavior change, purely rewording):
- Soften `Phase N` / `Chunk N` references in [R/](R/) comments to descriptive statements. Examples:
  - `# --- S3 namespace safety (Phase 7) ---` → `# --- S3 namespace safety ---`
  - `# Pull before write to ensure fresh state (Phase 7)` → `# Pull before write to ensure fresh state`
  - `R/store.R` header comment referencing "(Phase 12)" → drop the parenthetical
  - Roxygen `pre-Phase 7 manifest` in [R/validate.R](R/validate.R) → `legacy manifest without project_name` (regenerate `man/` with `devtools::document()`)
- `# Phase N, Chunk M` headers in [tests/testthat/](tests/testthat/): **optional** — scrub only if the sweep is quick. Tests rarely get public readership, so low ROI. Default: leave alone unless time permits at end of chunk.
- [.github/copilot-instructions.md](.github/copilot-instructions.md) renders on the public pkgdown site. Read through once and confirm nothing reads as chat-session residue. Default: keep as-is — content is professional and many OSS repos now publish this file.

**Acceptance**:
- `dev/archive/` and `dev/datomaccess_overview.md` no longer tracked by git (confirmed via `git ls-files dev/`); files still present locally.
- Dev scripts still run end-to-end (re-run both E2E scripts).
- `devtools::document()` run after roxygen edits; `devtools::check()` clean.
- No `Phase N` / `Chunk N` references remain in `R/*.R` comments.

### Chunk 5 — Final pass + phase completion
**Scope**: Integration check before flipping the repo public.
- Full `devtools::test()` — confirm test count matches Phase 13 (1177) or higher.
- `devtools::check()` — must be clean.
- `pkgdown::build_site()` locally — visual spot-check.
- Re-run both E2E scripts.
- Migrate learnings from this phase doc into `.github/copilot-instructions.md` and/or `dev/README.md` as appropriate (likely minimal — mostly mechanical work).
- Follow the Phase Completion Procedure in [dev/README.md](dev/README.md): update Active/Completed tables, delete this phase doc, PR + merge + delete branch.
- **After merge**: flip the repo to public in GitHub settings (user action, not a commit).

**Acceptance**: Phase doc deleted, README tables updated, branch merged, repo ready for visibility flip.

## Out of scope (backlog this phase)

- Vignette content refresh (already on backlog — don't expand scope).
- Any API changes or new features.
- CRAN submission prep (separate future phase).
- Setting up GitHub Pages, Codecov accounts, or any other external services — user action after merge.

## Status tracking

- [ ] Chunk 1 — Metadata hygiene
- [ ] Chunk 2 — Contributor scaffolding
- [ ] Chunk 3 — GitHub Actions CI
- [ ] Chunk 4 — Dev folder + source-comment public-readiness
- [ ] Chunk 5 — Final pass + phase completion

## Model escalation candidates

- **Chunk 4** touches many source files (comment scrubs) and the gitignore/untrack step. The comment rewording is mechanical, but run a purity audit (`git grep -n "Phase [0-9]"` against tracked files) at the end of the chunk to confirm no residue remains.
- **Chunk 5** is a good moment for a test-coverage review before closing the phase, given the repo is about to go public.
