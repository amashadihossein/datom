# Copilot Instructions for datom

## Quick Start for New Sessions

1. **Check active work**: Open `dev/README.md` → see the "Active Specs" table.
2. **Load context**: Open the active spec under `.kiro/specs/{feature}/` — read `requirements.md`, `design.md`, and `tasks.md`.
3. **Find your place**: In `tasks.md`, the next unchecked task is where to resume.
4. **Continue work**: As you complete each task, check it off in `tasks.md` in the **same commit** as its code, and update the `dev/README.md` Active Specs status line. See "Workflow model — spec = phase" under Operational Discipline.

## Project Overview

datom is an R package for version-controlled data management. It stores tabular data in S3 with git-tracked metadata, enabling reproducibility for clinical/scientific workflows.

**Compatibility posture**: datom is `lifecycle: experimental` (0.1.0 under/after CRAN review, no reverse dependencies). The distinction that governs a change is failure mode, not compatibility: breaking a behavior loudly (user upgrades, gets a clear error, fixes their code) is acceptable at this stage; silently degrading or disabling an integrity/verification check is not acceptable at any stage. Don't default to "rename/delete freely" reasoning — check whether a change can be made to fail loudly instead of silently before treating it as a free rename.

**Core concept**: Tables abstracted as code in git; actual data in cloud storage (parquet format).

**Git + GitHub for the data repo are mandatory, always; the governance layer is optional and on-demand** (amended Phase 18, 2026-05-02; supersedes the Phase-16 lock that required gov from day one). Every datom project requires a data git repo with a remote (today: GitHub) and a storage backend for parquet bytes. The governance layer -- portfolio register, dispatch routing, managed migration -- is adopted on-demand via `datom_attach_gov()`, typically when graduating to object storage or migrating data. Once attached, gov cannot be detached; `project.yaml`'s `storage.governance` block, once populated, is permanent. The companion governance package (`datomanager`) will eventually own the gov surface; the `# GOV_SEAM:` boundary already marks the lift-out. See `dev/datomanager_scope.md` for full scope. There is still no "local-only / no-remote" mode for the data repo: a `data_repo_url` is required. Single-user no-GitHub demos are explicitly rejected scope.

## Documentation Hierarchy

```
.github/copilot-instructions.md  ← You are here (coding conventions, quick start)
         ↓
dev/README.md                    ← Development hub (navigation, spec status)
         ↓
dev/datom_specification.md        ← Design spec (authoritative reference)
dev/datom_pathways.md             ← Canonical routes across metadata/gov/storage/access
dev/daapr_architecture.md        ← Ecosystem context
dev/engineering-notes.md         ← Gotchas & pitfalls (read before editing R/)
         ↓
.kiro/specs/{feature}/           ← Active work (spec: requirements / design / tasks)
```

**Navigation rules**:
- Start here for conventions → go to `dev/README.md` for current work
- Before designing a new lookup/traversal path, check `dev/datom_pathways.md` for an existing canonical route
- Units of work are Kiro specs under `.kiro/specs/{feature}/` (requirements → design → tasks); they persist as durable documentation
- Keep `tasks.md` status current as you work; durable learnings migrate to the spec docs / `dev/engineering-notes.md`

## Architecture Context

datom is the foundational layer for the daapr ecosystem:
- **datom** → versioned table storage (this package)
- **dpbuild** → data product construction
- **dpdeploy** → deployment orchestration  
- **dpi** → data product access

See `dev/datom_specification.md` for full spec and `dev/daapr_architecture.md` for ecosystem context.

## Coding Style

### Principles
- **Flat over nested**: Early returns, guard clauses
- **Tidyverse idioms**: pipes, purrr, dplyr
- **Small functions**: Single responsibility, composable
- **Clear naming**: `datom_` prefix for exports, `.datom_` for internals

### Patterns to Follow
```r
# Early validation, flat flow
datom_write <- function(conn, data, name, metadata = NULL) {
  if (!inherits(conn, "datom_conn")) stop("Invalid connection")

  if (!is.data.frame(data)) stop("data must be a data frame
")
  
  sha <- .datom_compute_sha(data)
  # ... flat logic continues
}

# Functional over loops
purrr::map(tables, .datom_sync_one)

# Glue for strings
cli::cli_alert_success("Wrote {name} ({sha})")
```

### Packages to Use
- `fs::` for filesystem
- `glue::glue()` for strings
- `cli::` for user messages
- `purrr::` for iteration
- `arrow::` for parquet I/O
- `digest::` for SHA computation
- `yaml::` for config files

### Naming Conventions
| Type | Convention | Example |
|------|------------|---------|
| Exported functions | `datom_verb` | `datom_read`, `datom_write`, `datom_init` |
| Internal functions | `.datom_verb` | `.datom_compute_sha`, `.datom_storage_upload` |
| S3 methods | `verb.class` | `print.datom_conn` |
| Store constructors | `datom_store_{backend}` | `datom_store_s3`, `datom_store_local`, `datom_store` (composite) |
| Store predicates | `is_datom_store_{type}` | `is_datom_store`, `is_datom_store_s3`, `is_datom_store_local` |
| Storage dispatch | `.datom_storage_verb` | `.datom_storage_upload`, `.datom_storage_read_json` |
| S3 backend | `.datom_s3_verb` | `.datom_s3_upload`, `.datom_s3_read_json` |
| Local backend | `.datom_local_verb` | `.datom_local_upload`, `.datom_local_read_json` |
| Config files | snake_case.yaml/json | `project.yaml`, `dispatch.json` |

## Key Files

- `dev/datom_specification.md` — Full technical specification
- `dev/datom_pathways.md` — Quick route map for canonical lookups and traversals
- `dev/daapr_architecture.md` — Ecosystem context
- `R/store.R` — Store constructors (`datom_store_s3`, `datom_store_local`, `datom_store`), validation, GitHub repo creation
- `R/utils-storage.R` — Storage abstraction dispatch (`.datom_storage_*()` → `.datom_s3_*()` or `.datom_local_*()`)
- `R/utils-local.R` — Local filesystem backend (`.datom_local_*()` functions via `fs::`)
- `R/ref.R` — Data location reference (`ref.json` create/resolve)
- `R/` — Source code (organized by domain)
- `tests/testthat/` — Tests mirror R/ structure

## User Types

1. **Data developers**: git + S3 access, create/update data
2. **Data readers**: S3 only, consume versioned data

Auto-detected via `github_pat` on the `datom_store()` object.

## Secret Handling Principle

datom receives secrets explicitly at runtime; it never discovers, persists, or treats secrets as project state. Users may source secret values from `keyring`, standard environment variables, CI secret stores, or other mechanisms, but those values must enter datom through store constructors such as `datom_store()` and `datom_store_s3()`. Environment variables are a caller-side convenience, not datom's internal credential contract.

- Never write PATs, access keys, secret keys, or session tokens to `project.yaml`, metadata JSON, manifests, `ref.json`, `dispatch.json`, git remotes, logs, or printed objects.
- Runtime objects may carry secrets only in memory and must mask them in `print()` methods.
- Downstream helpers (e.g. git credential helpers) must use the explicit value passed from `conn` / `store`. **No env-var fallback inside datom** -- if no explicit value is available, the helper returns NULL / unauthenticated. Callers who rely on env vars must read them themselves and pass the value to the store constructor.

## Schema Evolution and Forward Compatibility

Added 2026-08-23, from the datom-sets spec. The goal this serves: **code that worked once keeps
working.** A pinned analysis should not stop reading a repo because someone else upgraded datom.

**Forward compatibility is a writer-side problem.** A new build can always read old files, because
it knows both shapes. An old build can only read new files if the writer left it something it
already understands. Nothing can be retrofitted into a package that is already installed and locked
in an `renv.lock`, so a "converter for old readers" is not buildable -- the converter would have to
ship inside the build that predates the change.

**Reader compatibility and writer compatibility are separate guarantees.** Only the reader one
survives an addition. An older **reader** never asks for a key it does not know, so an added field is
invisible to it. An older **writer** recomputes identity before writing, so any added field makes it
disagree with the recorded version -- which is why datom **refuses** such a writer outright (see "The
writer refusals" below). Do not reason from "additive changes are free" without saying free *for
whom*.

### The four rules, in decreasing order of what they buy

1. **Additive only, by default.** Add fields; never rename, move, or remove one. This keeps **readers**
   working, which is the guarantee that can be kept. It does **not** keep older writers working -- a
   release that adds any field to a datom-owned document forces a fleet-wide writer upgrade, cosmetic
   additions included. Accepted deliberately: writes are infrequent and done by few people, and a
   false refusal costs one person an install while a miss costs corrupted data.
2. **A field's name and meaning are fixed forever.** Never repurpose. Renaming is the loud version
   of the same violation.
3. **If a break is genuinely unavoidable, dual-write** the old shape alongside the new for a
   declared window. This is the only mechanism that helps builds **already released**, because it
   asks nothing of them. The danger is a **stale** legacy copy, not a leftover one -- an old reader
   consuming an out-of-date file looks like it worked. So: repo-level policy rather than a per-call
   argument, removal as a verb that deletes the copies in the same operation, and the sunset
   recorded inside the legacy file.
4. **`schema_version` is the alarm, not the mechanism.** It exists for when rules 1-3 could not be
   followed. Leaning on it means the guarantee is already gone.

### Stamped always, incremented only on a break

Two separate decisions, routinely confused:

- **Stamp** every manifest and every per-artifact metadata document. It costs nothing (the field is
  in the identity exclusion set, so a stamped file mints no version) and any build can then say what
  shape it holds.
- **Increment** only when a change would break a reader. Breaking: renaming a field or moving it to
  a different parent, removing one, changing what one means or its type, restructuring a container.
  **Not** breaking: adding a field.

Incrementing on an additive change refuses a reader that could have read the file perfectly well.
The call is made at design time, alongside model-escalation flags -- not at implementation time.

**Classify by effect on a reader, not by the shape of the edit.** A content-bearing addition is
reader-safe and writer-breaking: the number must not move, and the writer-side stop comes from the
vocabulary check instead.

**Per-file response.** The number moves for both documents on a break and always describes the shape
the file actually has. What differs is the reader's response, because only one file is rebuildable:
a too-new **manifest** makes a reader warn and rebuild; a too-new **per-artifact metadata** document
makes a reader refuse. Writers refuse in both cases. Do not "simplify" this by freezing the manifest's
number -- a frozen number cannot distinguish a truncated manifest from a future-shaped one, since both
present with the expected key missing.

### The writer refusals

Two mechanisms, **complementary, neither sufficient alone.** Document them together or you oversell
whichever you name.

| Change | Caught by |
|---|---|
| field added | **vocabulary check** -- the number does not move |
| field renamed | vocabulary check, and the number too |
| field removed | **the number** -- the old name is still in an append-only vocabulary, so nothing looks unrecognised |
| type or meaning change | **the number** -- no new name appears |
| container restructured | **the number** -- no new name appears |
| policy block for a non-format reason | **the writer floor** only |

**The vocabulary check**: before writing, a build inspects the top-level keys of each datom-owned
document and refuses if it meets one it cannot classify -- neither in its identity list nor on its
documented excluded list. Evidence-based, so no configuration and no network. `custom` is opaque and
classified as a whole. Chosen over a declared floor as the primary mechanism because **it cannot be
forgotten**: a floor protects a repo only if somebody remembers to raise it.

**The vocabulary list is append-only, and this is the discipline the rest depends on.** Never stop
recognising a name that has ever existed, including names you no longer write; retire by marking, never
by deleting. A build that forgets a name meets an *older* file, fails to classify a key it should know,
and refuses it -- blocking the **upgrade** direction, the one direction that must always work.

**Do not add directional logic to it.** A newer build's vocabulary is a superset of every older one's,
so the check cannot fire on the upgrade path. A guard for that case would be dead code protecting an
unreachable state.

**All write-side refusals bind from 0.1.1 forward only.** 0.1.0 has no schema check, no vocabulary
check and no floor read, and none can be added to a released build. When describing these refusals,
separate the population that can be stopped from the one that cannot -- "an older build writing into a
newer repo" hides that distinction.

**A refusal must leave no partial state.** Every forward-compatibility check runs before any hashing,
any local file write, and any commit. Aborting mid-pipeline leaves a half-finished write, which is
worse than the disagreement being prevented.

`schema_version` is the **contract**; `datom_version` is **provenance**. One schema version spans
many releases, so the schema-to-release mapping must be published in the docs -- it is not inferable
from either field, and it is the only question a refusal message raises.

### Which files may break, and which may never

| File | May break? | Why |
|---|---|---|
| `.metadata/manifest.json` | **yes**, with a hatch | **Derived.** Every fact in it also lives in per-artifact metadata or the storage listing, so a build that cannot read it can rebuild one. |
| `{name}/.metadata/metadata.json` | **never** | **Source of truth.** Nothing can rebuild it, and a legacy-shaped copy hashes differently from the recorded version -- change detection recomputes identity from the stored file, so dual-write there helps old readers by making older writers mint a version on every run. |

For per-artifact metadata the four rules are **absolute**: additive only, forever.

### Two pitfalls worth knowing before you touch either file

- **Identity hashing must select fields by allowlist, never by exclusion.** Hashing
  everything-except-a-list means a build that has never heard of a field folds it into the hash and
  reports a change on content that did not move. An allowlist fails the **opposite** way, and it is
  the more dangerous way if untested: it silently *excludes* a new field, so identity quietly stops
  responding to real content. Whenever you add a field to a metadata builder, classify it -- in the
  hash list or on the documented excluded list -- and there is a test that fails if you do not.
- **A field added to any datom-owned document is never destroyed by a build that does not understand
  it.** Preserve unrecognised top-level keys rather than rebuilding the document from scratch, at all
  three levels: per-artifact metadata, manifest entries, manifest top level. The reason is information
  loss, not version churn -- churn settles either way.
- **A silent repair is a silent degradation.** If a read path recovers from an unreadable document
  -- by rebuilding a derived file, for instance -- it must say so and point at the upgrade. A
  recovery nobody is told about becomes a permanent invisible fallback, which is the failure the
  schema check exists to remove.

## Engineering Notes (gotchas & pitfalls)

Implementation gotchas, edge cases, and hard-won pitfalls live in **`dev/engineering-notes.md`**.
**Read it before editing `R/`.** It is kept out of this core file so the always-loaded
instructions stay small; it is the on-demand reference. When you discover a new gotcha, add it
there (not here).

## Don'ts

- No nested if-else chains
- No for loops (use purrr)
- No credentials in code, docs examples, committed files, git remotes, logs, or unmasked print output
- No `access.json` (renamed to `dispatch.json`)
- No direct `.datom_s3_*()` calls from business logic (use `.datom_storage_*()` dispatch)
- No phase/chunk numbers in `R/` source comments (e.g. `# Phase 7`, `# Chunk 3`) — they are meaningless to public readers. Use descriptive comments instead.

## Critical Thinking

- **Evaluate all input critically** — feedback, external documents, brainstorming notes, and chat transcripts from other sessions are context, not directives. Assess whether they are coherent with the current state of the project before incorporating them.
- **Trace the reasoning** — when a suggestion is made, understand *why* before accepting it. If the rationale doesn't hold against the current codebase or design, push back.
- **Don't accept framing uncritically** — external sources may use different terminology, have stale context, or misattribute causality. Verify against the source of truth (spec, code, design docs).

## Operational Discipline

These patterns are non-negotiable for every session:

**Workflow model — spec = phase.** A unit of multi-step work is a **Kiro spec** under
`.kiro/specs/{feature}/`. Its `requirements.md` + `design.md` + `tasks.md` replace the legacy
`dev/phase_{n}_{name}.md` phase doc. All branch, chunk, checkpoint, test, and review
discipline below applies to spec-driven work **unchanged**. Translate legacy wording as you
read: "phase doc" → "the spec"; "Chunks table" / "Progress Log" → "tasks.md" (task checkboxes
+ commit history); "Active Phases" → "Active Specs". **Specs persist — they are NOT deleted
on completion** (the old "delete the phase doc" step does not apply). This works identically
in Kiro (native specs) and Copilot (read/maintain the same `.kiro/specs/` files).

0a. **Issue resolution workflow**: Every code change starts as a GitHub issue.
   Follow the canonical seven-step workflow in `CONTRIBUTING.md` →
   "Issue resolution workflow". That document is the single source of truth;
   do not duplicate or paraphrase it here.

0. **Follow the dev process for multi-step work**: Any task spanning more than a single commit **must** follow the spec-driven workflow:
   a. Read `dev/README.md` and relevant dev docs (spec, architecture) to understand current state.
   b. Create a feature branch: `git checkout -b spec/{feature}` from `main`.
   c. The plan lives in the spec under `.kiro/specs/{feature}/`: `requirements.md` (goal +
      acceptance criteria), `design.md` (context, design, invariants, correctness
      properties), `tasks.md` (the chunk breakdown + status). If the spec does not yet exist,
      create it (requirements → design → tasks) — do NOT create a `dev/phase_*.md`. Flag any
      tasks that warrant model escalation (see Model Escalation below) at plan time, not
      mid-task.
   d. Register the spec as active in the `dev/README.md` Active Specs table.
   e. Work through tasks in order (1 task / small related group = 1 chunk = 1 commit).
      Updating status is part of completing each task: mark the task done in `tasks.md` in the
      **same commit** as its code, and update the `dev/README.md` Active Specs status line.
      The spec's `design.md` already holds the "read first" context, invariants, and
      correctness properties; add task-specific notes there when a task spans multiple files
      or carries strict must-never rules.
   f. Complete the Spec Completion Procedure (item 7) when done. PR to `main`, merge, delete branch.
   Never jump straight to coding on multi-step work. The spec is the plan AND the audit trail.
1. **Read before writing**: At the start of each chunk, read the relevant source functions AND their callers before editing. Trace the full call chain — don't edit based on the spec's task description alone.
2. **Full test suite before every commit**: Run `devtools::test()` (unfiltered) and verify the total count. Report the count in every commit message. If the count drops, something was lost.
3. **One logical change per commit**: Don't bundle unrelated fixes. Squash related incremental commits before pushing if they tell a cleaner story as one. Scope chunks so this is the natural outcome — if a chunk's scope feels ambiguous before you start, that's a signal to split it.
4. **Simplicity over cleverness**: If a change doesn't alter behavior, don't add it. When in doubt, do less. Actively resist complexity that exists only for marginally better UX or edge-case coverage.
5. **E2E after spec completion**: Unit tests are necessary but not sufficient. Before marking a spec complete, run real end-to-end workflows via `dev/dev-sandbox.R` to catch integration bugs.
5a. **Long text in CLI calls — always use a temp file, first try**: For `gh issue create --body`, `gh pr create --body`, `git commit -F`, or any CLI call that takes multi-line text: write the text to a temp file with `create_file` first, then pass `--body-file /tmp/filename.md` or `git commit -F /tmp/msg.md`. Never attempt the inline heredoc (`<< 'EOF'`) or `--body "..."` form first — shell quoting and terminal emulation always mangle them and risk duplicate side effects (e.g. duplicate issues). For short single-line messages (< 80 chars), inline `--message` / `-m` is fine.
5b. **Check in before implementing**: When the user asks a question (clarifying, exploratory, or directional), answer the question first. Do not implement anything until the user has confirmed the direction. The signal that implementation is wanted is explicit: "go ahead", "do it", "yes", or equivalent — not merely absence of objection.
5d. **Mandatory chunk checkpoint**: After completing and committing a chunk, STOP. Post a one-paragraph summary of what shipped and any decisions made, then ask: "Ready to proceed to Chunk N: [name]?" Do not start the next chunk until the user replies with an explicit go-ahead. This applies even if the next chunk seems obvious or low-risk. Completing a chunk is not permission to start the next one.
5e. **Approval signals are explicit, not contextual**: The following are NOT approval to proceed: silence, a question about the work just done, a comment about model behavior, a request to "queue" a model switch, or any message that does not directly address the next action. Explicit approval looks like: "go ahead", "yes", "do it", "proceed", "continue", or equivalent affirmatives directed at the next step.
5c. **Before retrying any remote-mutating action, verify remote state first**: Before a second attempt at `gh issue create`, `git push`, `gh pr create`, etc., run a read-only check (`gh issue list`, `git log --remotes`, `gh pr list`) to confirm whether the first attempt already succeeded. Acting on stale local evidence is how duplicates happen.
7. **Spec completion is mandatory**: When all tasks are done, harvest durable learnings (API/design → `dev/datom_specification.md`; gotchas/pitfalls → `dev/engineering-notes.md`; conventions → these instructions; deferrals → README Backlog), update the `dev/README.md` Active Specs table, and commit. **Specs persist — do NOT delete them** (this replaces the old "delete the phase doc" rule). Then PR + merge + delete the branch. Do NOT start the next spec until this is done.

## Model Escalation

Most chunks are routine and suited to a default working model. A few narrow moments are high-leverage enough to justify invoking a more capable model:

- **Design spot-check** before committing to a large or cross-cutting chunk.
- **Purity audit** after a refactor that touched many files, to catch drift the chunk-level review missed.
- **Test coverage review** before spec completion, to sanity-check that unit + E2E coverage actually exercises the new behavior.

When you recognize one of these moments, surface a brief recommendation and STOP. Do not proceed until the user responds. Example: "The final chunk touched 6 files across 3 modules. Consider escalating to a more capable model for a purity audit before the Spec Completion Procedure -- want to do that, or proceed as-is?"

A user message that says "queue a model switch" or "switch for chunk N" means: stop work, note the escalation request, and wait. It is NOT approval to continue on the current model.

Flagging escalation moments is mandatory at spec planning time (item 0c above). If a chunk was flagged at planning, the escalation reminder must appear in the chunk checkpoint message (rule 5d) whether or not you judge it necessary by the time you get there.
