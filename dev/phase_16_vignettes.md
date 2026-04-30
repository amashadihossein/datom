# Phase 16: Vignette Overhaul

**Status**: Active -- Chunk 3 complete; Chunk 4 next (Article 7 + Design Notes D2/D3/D4/D6)
**Branch**: `phase/16-vignettes` (created 2026-04-29)
**Depends on**: Phase 15 closed (2026-04-29). Phase 17 (`datom_summary`, `datom_projects`) is a prerequisite for Chunk 5.

## Progress log

- **2026-04-29 (Chunk 0)**: Phase activated. Branch created. Phase doc moved from Drafts to Active in `dev/README.md`.
- **2026-04-29 (Chunk 1 spot-check)**: Locked git+GitHub-mandatory as a Design Principle (recorded in `.github/copilot-instructions.md`, `dev/datom_specification.md`, and the Locked decisions section below). Option A from the spot-check; Options B (bare-repo) and C (no-remote mode) explicitly rejected.
- **2026-04-29 (Chunk 1)**: Complete. Simulator extended (LB + AE), `datom_example_data()` gains `"lb"`/`"ae"`, 17 new tests (1360/1360 passing), Articles 1-3 written, resume scripts 2-3 written, `README.Rmd` rewritten as the grabber, three old vignettes deleted, `_pkgdown.yml` gains `articles:` block. R CMD check: 0E/0W/1 pre-existing NOTE. pkgdown::build_site clean. Discovered: `tests/testthat/test-conn.R:742` is occasionally flaky in the full-suite run (bare-repo race condition, pre-existing); not caused by Chunk 1.
- **2026-04-29 (Chunk 2)**: Complete. Design Notes D1 (`design-datom-model.Rmd`) and D5 (`design-version-shas.Rmd`) written. `_pkgdown.yml` gains `Design` articles group. pkgdown::build_site clean. No code changes; tests untouched.
- **2026-04-29 (Chunk 3)**: Complete. Articles 4 (`promoting-to-s3.Rmd`), 5 (`handing-off.Rmd`), 6 (`second-engineer.Rmd`) written. Resume scripts 4--6 added. `_pkgdown.yml` Get Started group extended to 6 articles. Phase doc gains a Future Work section recording Phase 18 (`datom_migrate_data()`) and the gov-store-migration design problem -- both spawned by Article 4's honest treatment of the local->S3 boundary. AWS creds via `keyring` (parallels GitHub PAT pattern); reader role demonstrated by Article 5 in a different R session. Concurrent-write recovery in Article 6 is `datom_pull()` + retry. No code changes; tests untouched.

---

## Goal

Replace the current three vignettes (`clinical-data-versioning.Rmd`, `team-collaboration.Rmd`, `credentials.Rmd`) with a **progressive, continuous user journey** that climbs from a single clinical data engineer's first extract all the way to a portfolio manager governing many studies — and ends with a forward-looking article framing datom's place in the daapr stack.

Bonus: a parallel set of **Design Notes** that document the foundational concepts (ref/dispatch indirection, two-repo split, content-addressed versioning, immutability, always-migration-ready storage) for readers who want to understand *why*.

---

## Context

### Audience (from the user, 2026-04-27)

datom is the **foundational layer** for the daapr ecosystem. Higher-level packages (dpbuild, dpdeploy, dpi) will eventually own the data-product-builder and data-consumer experiences and ship their own vignettes. For datom itself:

**Primary readers** — clinical data engineers and managers
- Receive EDC extracts, run sync, manage versioning
- Set up governance, register/decommission studies
- Audit history, troubleshoot conflicts, assign access

**Secondary readers** — statisticians/analysts and data product builders
- Today they may use datom directly (read versioned tables)
- Tomorrow they spend most of their time in dpbuild/dpi
- datom vignettes give them foundational orientation, not full workflows

The vignette set should make the **engineer/manager** workflow the spine, and treat the consumer side as one stop along that spine — important enough to demonstrate, but not the destination.

### Why a single continuous journey

Today's three vignettes are good in parts but read as independent documents. A new user has no clear entry point and no path through the features. The new structure tells **one story** — STUDY-001 over six months — where each article picks up where the prior one left off and earns one new capability.

Each article opens with a "Where we left off" recap and a **resumable setup block** so a reader landing on article 5 directly can rebuild the prior state in one line (`source(system.file("vignette-setup", "resume_article_5.R", package = "datom"))`). Linear readers get continuity; jump-in readers get a working start.

### What we keep / drop from existing vignettes

**Keep**
- Clinical narrative + simulated STUDY-001 dataset (`datom_example_data()`, `datom_example_cutoffs()`)
- Roles table (developer/reader) + pull-before-push discipline → folded into article 6
- Store anatomy explanation → folded into article 10

**Drop / rewrite**
- Any non-clinical framing (verify `README.Rmd` too)
- "Under the Hood" sections referencing removed features (env-var bridge, STS) — already in backlog as "Vignette content refresh"
- Long upfront credential setup in article 1 — replaced with `datom_store_local()` for zero-config first success

---

## Decisions (locked at planning time)

1. **Manager-facing audit/reproducibility article (Article 8)** — included; this is the strongest sales pitch for clinical-regulated environments.
2. **Forward-looking daapr-stack article (Article 9)** — included now, with the explicit understanding it will need revision once dpbuild/dpi ship. Acceptable maintenance cost.
3. **Bonus utilities** — handled in a separate **Phase 17** between Chunks 4 and 5 (option (a) from planning). Keeps Phase 16 a pure docs phase. Phase 17 scope: `datom_summary()` and `datom_projects()` only. Anything else (`datom_diff`, `datom_reproduce`) deferred to its own phase.
4. **Design Notes location** — `vignettes/` (shipped + indexed by pkgdown), grouped under a "Design" sidebar section. The audience for "why is there a `ref.json`?" is exactly the user reading the package docs.
5. **Simulator extension** — extend `data-raw/simulate_study_data.R` with LB (lab) and AE (adverse events) domains so article 3's `datom_sync()` walks across heterogeneous tables.
6. **Resumable setup scripts** — live in `inst/vignette-setup/` so they work for installed-package users via `system.file()`.

---

## Article Plan — User Journey (Track A)

The thread: *"You are the data engineer for STUDY-001. Extracts arrive monthly. Over six months, your responsibilities grow."*

| # | Title | Altitude | Persona | State at start | New capability |
|---|---|---|---|---|---|
| 1 | First Extract | Single engineer | Engineer | Empty dir | `datom_store_local`, `datom_init_gov`, `datom_init_repo`, `datom_write`, `datom_read` |
| 2 | Month 2 Arrives | Single engineer | Engineer | State of #1 | Change detection, `datom_history()`, version-pinned reads |
| 3 | A Folder of Extracts | Single engineer | Engineer | State of #2 | `datom_sync()`, `datom_status()`, `datom_validate()` |
| 4 | Promoting to S3 | Team + cloud | Engineer | State of #3 (local) | `datom_store_s3()`, `create_repo=TRUE`, `ref.json` indirection (light) |
| 5 | Handing Off to a Statistician | Team + cloud | Engineer → Reader | State of #4 | Reader role, parallel R session, version pinning for reproducibility |
| 6 | A Second Engineer Joins | Team + cloud | Engineer | State of #5 | `datom_clone()`, `datom_pull()`, conflict recovery |
| 7 | Governing a Study Portfolio | Manager view | Manager | State of #6 + STUDY-002 | `datom_init_gov()`, registry, `datom_pull_gov()`, `datom_decommission()`, `datom_projects()` |
| 8 | Auditing & Reproducibility | Manager view | Manager | State of #7 | `datom_history()` deep dive, `datom_validate()` across projects, regulator-request walkthrough |
| 9 | Looking Ahead: datom in the daapr Stack | Manager view | All | — | Substrate framing; what belongs upstack |
| 10 | Credentials in Practice | Reference | All | — | Stores, keyring, dev vs reader; replaces today's `credentials.Rmd` |

### Continuity rules

- All articles use the same `study_001_data/` directory and the same `STUDY_001` project name.
- Articles 1–3 use the **local backend** — zero AWS/GitHub setup needed for first success.
- Article 4 is the moment credentials become unavoidable. Article 10 is its reference.
- Each article 2–10 opens with: (a) a one-line "Where we left off" recap, (b) a `system.file("vignette-setup", "resume_article_N.R", ...)` block, (c) the new work.

---

## Article Plan — Design Notes (Track B)

Reference-style. Each links back to the user-journey article where the concept first surfaced.

| # | Title | Concepts | Anchored to |
|---|---|---|---|
| D1 | The datom Model: Code in Git, Data in Cloud | Metadata/data split; immutability; content-addressed parquet | Article 1 |
| D2 | `ref.json` and Always-Migration-Ready Storage | Indirection layer; bucket migration without rewriting history; role-aware ref reads | Article 4 |
| D3 | `dispatch.json` and Self-Serve Access | Why dispatch is separate from ref; multi-backend future | Article 5 |
| D4 | Two Repos: Governance vs. Data | Phase-15 split rationale; `# GOV_SEAM:` contract; companion-package handoff | Article 7 |
| D5 | Version SHAs: Data SHA vs. Metadata SHA | JSON canonical form, volatile-field exclusion, dedup guard | Article 2 |
| D6 | Serverless & Distributed by Design | No central service; git + object store as only infra; permissions, audit, backup implications | Article 7 |

---

## Chunks

| Chunk | Content | Phase 15 dep | Phase 17 dep |
|---|---|---|---|
| 1 | Simulator LB/AE extension + regenerated extdata + Articles 1–3 + `resume_article_2.R`, `resume_article_3.R` + **`README.Rmd` rewrite** | No | No |
| 2 | Design Notes D1, D5 | No | No |
| 3 | Articles 4–6 + `resume_article_4.R` … `resume_article_6.R` | Yes | No |
| 4 | Article 7 + `resume_article_7.R` + Design Notes D2, D3, D4, D6 | Yes | No |
| 5 | Articles 8–9 + `resume_article_8.R` | Yes | Yes |
| 6 | Article 10 + `_pkgdown.yml` reorg + final pkgdown build | Yes | Yes |

### Locked design decisions (Chunk 1 spot-check, 2026-04-29)

- **Git + GitHub are mandatory from Article 1 onward.** No "no-credentials" framing. Every article (and the README's primary example) requires `GITHUB_PAT` set up via `keyring` in 3 lines. The local backend (`datom_store_local()`) means parquet bytes live in a directory — it does **not** mean git is optional. Articles 1–3 use `create_repo = TRUE` with the local backend (GitHub for metadata, filesystem for data); Article 4 adds S3 for data. This decision is now in `.github/copilot-instructions.md` and `dev/datom_specification.md` as a Design Principle. (Option A from the Chunk 1 spot-check; Options B and C explicitly rejected.)
- **Filenames**: plain (e.g. `first-extract.Rmd`), no numeric prefixes. Sidebar order is owned by `_pkgdown.yml`, so reordering later is a YAML edit.
- **Working directory**: vignettes default to `tempdir()` subdirs (`study_dir`, `store_path`); each article shows a one-line override comment for `~/study_001_data` if the reader wants persistence.
- **Article 1 capability budget**: `datom_store_local()`, `datom_init_repo()`, `datom_write()`, `datom_read()` only. `datom_list`/`datom_status` defer to Article 3.
- **Resume scripts** (`inst/vignette-setup/resume_article_N.R`):
  - Take no arguments; honor env vars `DATOM_VIGNETTE_DIR`, `DATOM_VIGNETTE_STORE_PATH`; default to `tempdir()`.
  - Idempotent — re-run is a no-op if state is already at end-of-article-(N-1).
  - Self-contained: only `datom`, `fs`, base R, and shipped `datom_example_*` helpers. No network for resume scripts 2–3.
  - Return `invisible(list(conn = ..., study_dir = ..., store_path = ...))` so power users can `state <- source(...)$value`.
  - Use `cli::cli_alert_info()` to echo each rebuild step.
- **All vignette chunks `eval = FALSE` for IO**. Chunk option default set at top of each article via `knitr::opts_chunk$set(eval = FALSE)`.
- **README is the grabber**: rewrites in Chunk 1 (moved up from Chunk 6). Shows `datom_store_local()` → `datom_init_repo()` → `datom_write()` (twice, to demonstrate duplicate detection) → `datom_list()` → `datom_read()`. Closes with one-paragraph "next steps" pointing to the S3 + governance articles. No AWS/GitHub in the README's primary example.
- **Simulator LB/AE shape**:
  - LB: ~700 rows, 3–5 lab tests per subject per visit (CHEM/HEMA), `LBDTC` between enrollment and study end.
  - AE: ~80 rows, 0–3 events per subject (Poisson-ish), `AESTDTC` post-enrollment, severity + relationship coded.
  - Written to `inst/extdata/lb.csv` / `ae.csv`. `datom_example_data()` gains `"lb"` and `"ae"` choices.

**Recommended escalation moments** (per copilot-instructions Model Escalation):
- **Chunk 1 design spot-check** before writing — get the resumable-setup pattern reviewed; it's the cross-cutting pattern that all 10 articles inherit.
- **Chunk 6 coverage review** before phase completion — verify every exported function appears in at least one article.

---

## Acceptance Criteria

1. Ten user-journey articles + six design notes ship in `vignettes/`.
2. `_pkgdown.yml` groups them: "Get Started" (articles 1–3), "Scale Up" (4–6), "Govern" (7–9), "Reference" (10), "Design" (D1–D6).
3. Each article 2–10 has a working `inst/vignette-setup/resume_article_N.R`. Running it from a clean R session with a clean working dir reproduces the prior article's end state.
4. Every exported datom function appears in at least one article (verified via grep against `NAMESPACE`).
5. `devtools::check()` clean. `pkgdown::build_site()` builds without "topic missing from index" errors.
6. The current three vignettes are deleted (their useful content has been folded in).
7. `README.Rmd` (and rendered `README.md`) updated to link the new article order.
8. E2E sanity: pick one mid-journey article (suggest Article 5) and walk it end-to-end against `dev/dev-sandbox.R` — confirm the resume script + new work both succeed.

---

## Invariants — Read Before Each Chunk

- **No non-clinical examples.** No customers, no sales, no e-commerce. STUDY-001 only (with STUDY-002 introduced in Article 7 for the portfolio view).
- **No phase/chunk numbers in user-facing text.** Articles refer to each other by title or number-in-series, not by phase artifacts.
- **No `eval=TRUE` chunks** that hit S3 or git. All `eval=FALSE`. Resumable setup scripts are runnable but not executed during build.
- **Resumable setup scripts must be idempotent.** Running twice in the same dir must not fail or corrupt state.
- **Each article earns exactly one new capability.** If a chunk is sprawling, split the article.
- **Design Notes must not duplicate user-journey content.** They explain *why*, not *how*.

---

## Open Items / To Decide During Work

- **Resume scripts: fresh-jump-in vs. continuity-only.** Chunk 1 ships continuity-only resume scripts: they require the prior article's local state to exist (default `tempdir()` within session, or `DATOM_VIGNETTE_DIR=~/...` across sessions) and abort with instructions otherwise. A true fresh-jump-in (run resume for article 5 from a clean machine and have it call `datom_init_gov(create_repo = TRUE)` etc.) collides with GitHub's "repo already exists" check across sessions. Two ways to fix later: (a) suffix repo names with a hash of the local path so each path gets its own remote, or (b) detect existing remotes and switch to `gov_repo_url`/`data_repo_url` mode. Deferred.
- Article 9 (daapr stack): how speculative is too speculative? Lean: only describe interfaces datom already exposes; describe upstack packages by name + role only, not by API surface.
- Article 7's introduction of STUDY-002: spin up a second simulated study or just narrate it? Lean: narrate (one-line `datom_init_repo()` for STUDY-002, no real data) -- keeps the article focused on governance, not data.
- pkgdown sidebar grouping labels: confirm "Get Started / Scale Up / Govern / Reference / Design" reads well on the rendered site.

---

## Future Work (spawned during this phase)

These are out of scope for Phase 16 but are referenced from its articles and should become their own phases:

- **Phase 18 (planned): `datom_migrate_data()`.** A first-class API to copy parquet bytes from one data store to another (local -> S3, S3 bucket -> S3 bucket, future GCS, etc.) without resetting project history. The plumbing already exists (`ref.json` `previous` slot, `migration_history.json`, conn-time mismatch detection at `R/conn.R:1037`). What's missing is a single orchestrator that copies bytes, rewrites `ref.json`, appends migration history, rewrites `project.yaml`'s `storage.data` block, and commits the gov repo. Article 4 explicitly defers to this future capability and chooses the decommission-and-replay path instead.
- **Phase 19-ish: governance store migration.** A harder design problem -- the gov store is the root of trust and is referenced directly by user code (`datom_get_conn(store=...)`), so swapping it has no `ref.json` analogue today. Likely requires a discovery convention (gov-pointer file at a well-known location, or org-wide config). No code today; not yet specified.

---

## Notes

- This is the first phase planned while another phase (15) is still open. The user explicitly approved this exception because Phase 16 is doc-only and Phase 15 is blocked on user testing time. Chunks 3+ are gated on Phase 15 close to enforce serialization on code-touching work.
- Phase 17 (utility helpers) is small enough that it should slot in between Chunk 4 and Chunk 5 of this phase without ceremony. Plan its doc when Chunk 4 is closing.
