# GOV_SEAM Lift-out — Cross-Package Contract

> **Source of truth.** This copy lives in `datom/.kiro/specs/gov-seam-liftout/contract.md`
> and is the authoritative version. A mirror exists at
> `datomanager/.kiro/specs/gov-seam-liftout/contract.md` carrying a provenance note. If
> either copy changes, reconcile both in the same change.

## Purpose

The GOV_SEAM lift-out is one atomic, coordinated change across two independently developed
R packages — `datom` (platform) and `datomanager` (governance). Each package carries its
own `requirements.md` describing the changes it owns. This contract captures the **durable,
bidirectional invariants** that bind the two packages together. Unlike the one-time
migration steps in each `requirements.md`, these invariants persist after the lift-out and
constrain all future development of both packages.

Each invariant states the obligation on each side. Both packages' specs reference this
document.

## Parties

- **Datom_Package** — the `datom` R package (platform layer; owns all reads and the
  `datom_storage_*` / `datom_repo_*` exports).
- **Datomanager_Package** — the `datomanager` R package (governance layer; Imports
  Datom_Package; owns `gov_*` and future `access_*`).

## Shared Glossary

- **Gov_Clone**: The local working copy of the governance repository. Gov writes commit
  only to this clone.
- **Data_Repo**: A project's data repository (its `project.yaml` and data clone). Only
  Datom_Package mutates the Data_Repo.
- **Solo_Project**: A project whose location authority is `project.yaml` in the Data_Repo;
  no governance attached.
- **Governed_Project**: A project whose location authority is `ref.json` in the gov repo.
- **Conn_Interface_Contract**: The `datom_conn` fields Datomanager_Package reads —
  `gov_local_path`, `gov_root`, `gov_prefix`, `gov_region`, `gov_backend`, `gov_client`,
  `github_pat`, `project_name`, `backend`, `root`, `prefix`, `region`.
- **Cross_Package_Call**: A call from Datomanager_Package into Datom_Package, made through
  an exported `datom::datom_*()` symbol.

## Contract Invariants

### C1: One-way dependency direction

**Datom_Package obligations**

1. THE Datom_Package SHALL NOT declare Datomanager_Package in the `Imports`, `Depends`,
   `Suggests`, `Enhances`, or `LinkingTo` fields of its `DESCRIPTION`.
2. THE Datom_Package SHALL NOT reference the `datomanager` namespace in any file under `R/`
   or `tests/` via `datomanager::`, `datomanager:::`, `library(datomanager)`,
   `require(datomanager)`, `requireNamespace("datomanager")`, or
   `loadNamespace("datomanager")`.
3. THE Datom_Package SHALL NOT contain, in any file under `R/`, conditional logic that
   detects the presence of Datomanager_Package via `requireNamespace`, `installed.packages`,
   `loadNamespace`, or `find.package`.
4. THE Datom_Package SHALL NOT, in any vignette or executable `man/*.Rd` example that runs
   during `R CMD check`, load or call Datomanager_Package; harmless prose mentions of the
   name are permitted.

**Datomanager_Package obligations**

5. THE Datomanager_Package SHALL declare `datom` in the `Imports` field of its
   `DESCRIPTION`.

### C2: Prefix equals package, no symbol masking

**Datom_Package obligations**

1. THE Datom_Package SHALL export, as its public surface, only symbols whose names begin
   with the prefix `datom_`, and SHALL export no symbol whose name begins with `gov_` or
   `access_`.
2. THE Datom_Package SHALL retain the `datom_` prefix on the gov-read exports
   `datom_projects()` and `datom_pull()` and on the data-side teardown export
   `datom_repo_delete()`, each of which keeps the `datom_` prefix even though it relates to
   governance state.

**Datomanager_Package obligations**

3. THE Datomanager_Package SHALL export, as its public surface, only symbols whose names
   begin with `gov_` or `access_`, and SHALL export no symbol whose name begins with
   `datom_`.

**Joint obligations**

4. THE set of exported symbol names of Datom_Package and the set of exported symbol names
   of Datomanager_Package SHALL have an empty intersection.
5. WHEN both packages are attached in the same R session, THE R session SHALL report no
   masking of one package's exported symbol by an exported symbol of the other package.

### C3: Cross-package calls use exported symbols only

**Datomanager_Package obligations**

1. THE Datomanager_Package SHALL, in every Cross_Package_Call within its `R/` source files,
   invoke Datom_Package functionality only through symbols that appear in Datom_Package's
   `NAMESPACE` export list, referenced in the `datom::datom_*()` form.
2. THE Datomanager_Package SHALL NOT use the token `datom:::` in any of its `R/` source
   files.
3. IF a Cross_Package_Call in a Datomanager_Package `R/` source file references a `datom`
   symbol absent from Datom_Package's `NAMESPACE` export list, THEN THE Datomanager_Package
   SHALL be treated as non-conforming to this contract.

**Datom_Package obligations**

4. THE Datom_Package SHALL NOT use the token `datomanager:::` in any of its `R/` source
   files.

### C4: Two-repos invariant

**Datomanager_Package obligations**

1. WHEN Datomanager_Package commits gov state, THE Datomanager_Package SHALL write that
   commit only to the Gov_Clone working copy.
2. THE Datomanager_Package SHALL NOT perform any write, commit, deletion, or file mutation
   against the Data_Repo except through an exported `datom::datom_repo_*()` helper.
3. WHEN Datomanager_Package requires a Data_Repo mutation, THE Datomanager_Package SHALL
   perform that mutation through an exported `datom::datom_repo_*()` helper.
4. IF a Data_Repo mutation performed through an exported `datom::datom_repo_*()` helper
   fails, THEN THE Datomanager_Package SHALL abort the operation, return an error indicating
   the data-side mutation did not complete, and leave the Gov_Clone unchanged.

**Datom_Package obligations**

5. THE Datom_Package SHALL expose every Data_Repo mutation that Datomanager_Package needs
   as an exported `datom_repo_*()` helper.

> **Intentional asymmetry.** The data-repo local clone path (`conn$path`) and its companions
> (`data_repo_url`, `github_api_url`, `role`) are deliberately **absent** from the
> Conn_Interface_Contract (C6). Datomanager_Package never operates the Data_Repo directly; it
> passes the whole `conn` to an exported `datom_repo_*()` helper, which reads those fields
> internally. Only the **gov** clone path (`gov_local_path`) is exposed, because
> Datomanager_Package owns gov-repo git (C7). Do not add a data-repo path to C6 — doing so
> would invite a C4 violation.

### C5: Commit-message audit contract

The exact gov-repo commit message strings auditors grep for. The party that performs each
gov commit (Datomanager_Package after the lift-out) owns these obligations; the strings are
fixed and SHALL NOT drift.

1. WHEN a project is registered, THE committing package SHALL commit to the Gov_Clone with
   a message byte-for-byte equal to `Register project {name}`.
2. WHEN a project is unregistered, THE committing package SHALL commit with a message
   byte-for-byte equal to `Unregister project {name}`.
3. WHEN dispatch is written, THE committing package SHALL commit with a message
   byte-for-byte equal to `Update dispatch for {name}`.
4. WHEN a ref is written, THE committing package SHALL commit with a message byte-for-byte
   equal to `Update ref for {name}`.
5. WHEN a migration is recorded, THE committing package SHALL commit with a message
   byte-for-byte equal to `Record migration for {name}: {summary}`.
6. WHEN any message in this contract is formed, THE committing package SHALL substitute
   `{name}` (the project's `project_name`) and `{summary}` by literal string replacement
   only, with no additional prefix, suffix, surrounding whitespace, case change, trimming,
   truncation, or encoding change to the fixed surrounding text.

### C6: Conn interface contract

**Datom_Package obligations**

1. THE Datom_Package SHALL include on every `datom_conn` object, whether the conn
   represents a Solo_Project or a Governed_Project, the twelve Conn_Interface_Contract fields
   named exactly `gov_local_path`, `gov_root`, `gov_prefix`, `gov_region`, `gov_backend`,
   `gov_client`, `github_pat`, `project_name`, `backend`, `root`, `prefix`, and `region`
   (gov-scoped fields MAY be NULL on a Solo_Project).
2. THE Datom_Package SHALL set each Conn_Interface_Contract field to the same value type and
   meaning that field held before the lift-out (except `gov_backend`, which is newly
   introduced), and SHALL NOT rename or remove any of them without a coordinated change with
   Datomanager_Package.
3. THE Datom_Package SHALL set `conn$gov_backend` to the backend (`"s3"` or `"local"`) of
   the governance store component, independent of the data backend, and SHALL resolve the
   storage backend for every gov-scoped operation from the governance backend rather than
   from `conn$backend`.

**Datomanager_Package obligations**

4. THE Datomanager_Package SHALL operate on `datom_conn` objects produced by Datom_Package
   and SHALL NOT define, construct, or return any conn type other than `datom_conn`.
5. THE Datomanager_Package SHALL read conn state only by accessing the Conn_Interface_Contract
   fields by their names, and SHALL select the gov storage backend from `conn$gov_backend`
   (not by inference).
6. IF a `datom_conn` passed to Datomanager_Package omits any of the twelve
   Conn_Interface_Contract fields, THEN THE Datomanager_Package SHALL abort the operation
   with an error indicating which field is missing, without mutating the Gov_Clone or the
   Data_Repo.

### C7: Gov-repo git ownership

Datomanager_Package owns all git operations on the **gov repo**. Datom_Package owns git on
the **Data_Repo** only.

**Datomanager_Package obligations**

1. THE Datomanager_Package SHALL perform every gov-repo git operation (clone refresh, stage,
   commit, push) using its own git tooling (for example `git2r`), operating on the clone at
   `conn$gov_local_path` and authenticating with `conn$github_pat`.
2. THE Datomanager_Package SHALL NOT call any Datom_Package function to perform a gov-repo
   git operation.

**Datom_Package obligations**

3. THE Datom_Package SHALL NOT export any function that performs a git operation on the gov
   repo.
4. THE Datom_Package SHALL NOT perform any gov-repo git operation after the lift-out; its
   internal git utilities operate only on the Data_Repo.

### C8: Gov storage layout and serialization

Gov state is mirrored to gov storage (S3 or local) so readers never need git.
Datomanager_Package writes these objects and Datom_Package reads them, and each package
implements this layout independently. A change to this clause requires a coordinated change
in both packages.

**Storage namespace and keys**

1. Gov objects SHALL live under the gov namespace: for S3, `{gov_prefix}/datom/`, where
   `gov_prefix` is `conn$gov_prefix` stripped of leading/trailing `/` (or `datom/` when
   `gov_prefix` is empty or NULL); for local, the corresponding path relative to
   `conn$gov_root`.
2. For each project, the gov objects SHALL be `projects/{project_name}/dispatch.json`,
   `projects/{project_name}/ref.json`, and `projects/{project_name}/migration_history.json`
   (keys relative to the gov namespace).

**File schemas**

3. `ref.json` SHALL be an object with `current` (an object with `type`, `root`, `prefix`,
   `region`, omitting any field whose value is null) and `previous` (an array of objects
   with `type`, `root`, `prefix`, `region`, `migrated_at`, `sunset_at`).
4. `migration_history.json` SHALL be a JSON array ordered most-recent-first, each entry an
   object that includes at least `occurred_at` (UTC, formatted `YYYY-MM-DDTHH:MM:SSZ`) and
   `event_type`.
5. `dispatch.json` SHALL be the method-routing object in the form Datom_Package's dispatch
   reader consumes.

**Serialization**

6. Each gov file SHALL be UTF-8 JSON, written with scalars unboxed (not length-1 arrays) and
   pretty-printed, such that the value Datomanager_Package writes round-trips to the value
   Datom_Package parses.
7. For each gov file, the copy committed to the Gov_Clone and the copy mirrored to gov
   storage SHALL have equivalent content under this schema.

**Backend signalling**

8. Datomanager_Package SHALL select the gov storage backend from `conn$gov_backend` (C6),
   not by inferring it from the presence of `conn$gov_client` or any other field.

## Synchrony

This contract and the two `requirements.md` files describe **one** coordinated change split
across two repos. They must not drift. This section defines what stays in lock-step and the
rule for keeping it there.

### Mirror reconciliation rule

`contract.md` exists in both spec folders:

- `datom/.kiro/specs/gov-seam-liftout/contract.md` — **source of truth**
- `datomanager/.kiro/specs/gov-seam-liftout/contract.md` — **mirror**

The body (Purpose through Synchrony) SHALL be byte-identical between the two copies. Only
the provenance blockquote at the top differs. When either copy changes, reconcile the other
in the same change.

### Requirement Pairing Map

Each row is a single concern realized on both sides. A change to one cell requires checking
the paired cell(s) and the cited contract clause.

| #  | Concern                              | datom side                | datomanager side             | Contract |
|----|--------------------------------------|---------------------------|------------------------------|----------|
| P1 | Nine GOV_SEAM write helpers          | R1 (remove), R9 (tests)   | R1 (receive), R5 (tests)     | —        |
| P2 | Five gov exports → `gov_*`           | R2 (remove)               | R2 (export)                  | C2       |
| P3 | `datom_repo_delete` + guards         | R3                        | R3.1 (call site)             | C2, C4   |
| P4 | Namespace storage delete             | Phase 22 export (exists)  | R3.2                         | C4       |
| P5 | Init decouple / registration handoff | R4                        | R4 (`gov_attach` registers)  | C5       |
| P6 | Retained gov read surface            | R5                        | consumes via conn            | C1, C6   |
| P7 | datom functional without datomanager | R6                        | —                            | C1       |
| P8 | `datom_conn` interface fields (8)    | R7                        | R2.8                         | C6       |
| P9 | Clean `R CMD check`                  | R8                        | R6                           | —        |
| P10| Commit-message audit strings         | — (no longer writes gov)  | R2, R4                       | C5       |
| P11| Gov-repo git ownership               | R10 (no gov git)          | R1 (own git via git2r)       | C7       |
| P12| Gov storage layout / serialization   | R5 (reads conform)        | R1 (writes conform)          | C8       |
| P13| Conn gov fields (twelve)             | R7                        | R2.8                         | C6       |

### Shared lists that must stay identical

These literal lists appear in more than one place. A change to any one occurrence must be
propagated to all of them:

- **The nine write-helper names** — datom R1.1, datom R9.1, datomanager R1.1, datomanager R5.1.
- **The five gov functions and their `gov_*` rename map** — datom R2, datomanager R2.
- **The twelve `datom_conn` fields** — datom R7.1, contract C6.1 (and the datomanager glossary).
- **The five commit-message strings** — contract C5 (the only place they are defined; both
  specs cite C5 rather than restating them).

### Resolved decisions

- **D1 (was Q1) — gov-clone refresh / `.datom_gov_pull`.** datom's read paths do not require
  a gov-clone fetch: readers read gov **storage** (always current via the mirror),
  developers read the on-disk clone, and the write-time guard re-checks against gov storage.
  Gov-repo git — including any clone refresh — is datomanager-owned (C7). datom retains no
  gov-pull and gains no gov-git export.
- **D2 (was Q2) — boundary is pure separation.** Datomanager_Package reaches into
  Datom_Package for nothing gov-related: gov-repo git via its own tooling (C7); gov storage
  via its own IO conforming to the shared layout (C8). Datom_Package exports no git
  primitives and no gov-storage IO for gov purposes. The only datomanager → datom touchpoints
  are the conn fields (C6) and the data-side `datom_repo_*` / `datom_storage_*` exports used
  by decommission and migration.
- **Implementation consequence.** The nine gov-write helpers are therefore **reimplemented**
  in datomanager (behavior-equivalent per datomanager R1), not copied verbatim — their datom
  bodies call datom-internal git/storage utilities that C3 puts out of bounds.
- **D3 (was Q3) — gov backend is explicit, not inferred.** The conn carries a first-class
  `conn$gov_backend` field (C6) that Datom_Package sets from the governance store component;
  Datomanager_Package selects the gov storage backend from it (C8.8) rather than inferring
  from `gov_client`. Datom_Package also resolves gov-scoped operations from the governance
  backend, closing the prior `.datom_conn_for` (data backend) vs `.datom_build_gov_resolve_conn`
  (gov backend) inconsistency.

### Open synchrony questions (resolve before design)

_None open. The resolved decisions above (D1–D3) capture the design-shaping calls._

### Execution sequence (cross-repo orchestration)

The lift-out is one coordinated change across two repos. This is the canonical ordering;
each repo's `tasks.md` derives from it. Because of pure separation (D2), datomanager never
imports datom's gov internals, so the build-time coupling is loose: datomanager depends only
on datom's conn fields (C6) and the exported `datom_repo_*` / `datom_storage_*` surface.

**Ordering rule.** datom goes first (it must expose the new interface — `gov_backend`,
decoupled `datom_init_repo()`); datomanager goes second. datom's *removals* cannot break
datomanager, which never depended on the removed gov surface.

1. **Spec phase (both repos).** Design + tasks on each side; contract clauses are the
   conformance checkpoints.
2. **datom side (lands first).**
   1. Add `conn$gov_backend`; resolve gov-scoped ops from the gov backend (C6, D3).
   2. Decouple `datom_init_repo()` from gov registration; deprecation warning → `gov_attach()` (datom R4/R5).
   3. Remove the five exported gov functions and the nine internal gov-write helpers; drop/relocate their tests (datom R1, R2, R9, R10).
   4. Confirm `datom_repo_delete` / `datom_repo_set_data_store` guards (exist since Phase 22; datom R3).
   5. NAMESPACE/man cleanup; `R CMD check` clean (datom R8); version bump; migration note for users of the old gov exports.
3. **datomanager side (lands second; against the new datom).**
   1. Pin `Imports: datom (>= <new version>)`.
   2. Implement the nine gov-write behaviors natively — git2r for gov-repo git (C7), own storage IO conforming to the gov storage layout (C8) (datomanager R1).
   3. Implement `gov_init`, `gov_attach` (registration), `gov_decommission` (orchestration), `gov_sync_dispatch`, `gov_pull` (datomanager R2–R4).
   4. Tests incl. `test-utils-gov.R`, registration via `gov_attach()` (datomanager R5); `R CMD check` clean, "Imports: datom not yet used" note clears (datomanager R6).
4. **Cross-repo validation.** Governed lifecycle E2E side by side
   (`gov_init → gov_attach → datom reads → gov_sync_dispatch → gov_decommission`) across the
   data/gov backend matrix (exercises `gov_backend`).
5. **Docs / sync.** Update conventions (both repos), reduce the datom-side design-doc copies
   to pointers (per the README provenance note), refresh roadmaps.
