# datomanager — Companion Governance Package Scope

> **Purpose**: Scopes the creation of `datomanager`, the companion R package for governance
> teams. This is a persistent vision/planning document, not a phase doc. Update it as
> decisions solidify. For the access enforcement design (roles, grants, IAM), see
> `dev/datomanager_overview.md`.
>
> **Status**: Pre-creation. No code exists yet. datom still owns the full GOV_SEAM surface.
> See `dev/README.md` Backlog for activation priority.

---

## What is datomanager?

`datomanager` is a companion R package for governance teams. It owns two surfaces:

1. **Gov lifecycle writes**: the `# GOV_SEAM:` tagged helpers in datom — project
   registration, decommission, dispatch, migration records.
2. **Access enforcement**: roles, grants, and IAM-backed S3 access point provisioning
   (described in `dev/datomanager_overview.md`).

Governance teams own both. Starting as one package is correct; split later if concerns
grow sufficiently distinct.

**Dependency direction**: `datomanager` Imports `datom`. datom does NOT import or know
about datomanager. Users of datom without datomanager continue to get the full data
management surface; they just cannot perform governance write operations (which currently
means: you get an error if you try to call gov-only commands without a gov store attached).

**Scope in one sentence**: datomanager owns the gov repo lifecycle (init, register,
decommission, destroy), data migration (`gov_migrate_data()`), and access enforcement
(roles, grants, IAM). datom retains all reads.

---

## Naming Convention: prefix = package

A function's prefix tells you which package owns it and which authority model is in play.
This removes the ambiguity of a single verb behaving differently -- or being masked at the
R namespace level -- depending on governance state.

| Prefix | Package | Surface |
|---|---|---|
| `datom_*` | datom | Platform mechanics, **all reads**, and solo-project self-serve writes (including data-repo relocate and teardown). |
| `gov_*` | datomanager | Governed lifecycle **writes** (init, attach, register, decommission, dispatch, migrate). |
| `access_*` | datomanager (future; may split) | Access enforcement (roles, grants, IAM). See `datomanager_overview.md`. |

**The rule in one line**: the prefix is the package. No symbol is ever exported by two
packages, so there is no masking and no "which package's function is this?" at the call
site.

**Subtlety -- gov reads stay `datom_*`.** `gov_` does not mean "anything touching
governance"; it means "a datomanager-owned governed *write*." datom **reads** gov and keeps
its prefix: `datom_projects()`, `datom_summary()`, `datom_pull()` (data repo) are all
`datom_*`. datomanager **writes** gov.

### Rename map (applied at lift-out, not now)

The gov functions currently in datom are renamed when they move to datomanager. The
renames are free (pre-release) and land as part of the mechanical lift-out.

| Today (datom) | After lift-out (datomanager) |
|---|---|
| `datom_init_gov()` | `gov_init()` |
| `datom_attach_gov()` | `gov_attach()` |
| `datom_decommission()` | `gov_decommission()` (see decommission split below) |
| `datom_sync_dispatch()` | `gov_sync_dispatch()` |
| `datom_pull_gov()` | `gov_pull()` |
| *(new, never in datom)* | `gov_migrate_data()` |

Side effect: today's confusing pair `datom_pull` (data) vs `datom_pull_gov` (gov) becomes
`datom_pull` vs `gov_pull` -- the prefix disambiguates what the `_gov` suffix was straining
to do.

---

## Authority Principle: data-repo mutations always route through datom

**Vocabulary -- two kinds of project, named by their authority.** The prefix names the
package; this noun names the *thing you are holding*:

- a **solo project** -- `project.yaml` (in the data repo) is the location authority. datom
  alone provides the **complete** lifecycle: relocate bytes and tear the project down. No
  datomanager needed. (Phase 18 already calls `datom_store(governance = NULL)` the "solo"
  path.)
- a **governed project** -- `ref.json` (in the gov repo) is the authority. The governed
  verbs live in datomanager and orchestrate datom's helpers; **datomanager never touches
  the data repo directly.** `gov_attach()` promotes a solo project to a governed one (one
  way -- gov is sticky once attached).

The noun makes error messages read naturally:
*"`gov_sync_dispatch()` requires a governed project -- run `gov_attach()` first."* The
prefix tells you which package owns the verb; the noun tells you which kind of project the
verb applies to. ("solo" is preferred over "local" because `local` already names a storage
*backend* in datom -- `datom_store_local` -- and "a local project" would be misread as
"a project on the local filesystem backend.")

Which authority is in force determines which package owns a mutating verb. Every data-repo
mutation datomanager needs is exposed as a datom-owned `datom_repo_*` helper. This preserves
the two-repos invariant uniformly: gov code commits only to the gov clone; data-repo writes
always go through datom.

| datom data-side helper | Does | Solo (self-serve) | Governed (via datomanager) |
|---|---|---|---|
| `datom_storage_copy()` / `datom_storage_delete_prefix()` | Move / delete the data **namespace** | relocate / teardown | `gov_migrate_data()` / `gov_decommission()` |
| `datom_repo_set_data_store()` | Rewrite `storage.data` in `project.yaml`; commit + push data repo | completes a relocate | `gov_migrate_data()` step 7 |
| `datom_repo_delete()` | Delete the data **GitHub repo** + local clone | completes a teardown | `gov_decommission()` data-side |

**Verb pairs** (prefix carries the authority model; the verb is the honest word for the act):

| Act | Solo project (datom) | Governed project (datomanager) |
|---|---|---|
| move data | `datom_relocate_data()` (or compose `storage_copy` + `repo_set_data_store`) | `gov_migrate_data()` |
| tear down | `datom_repo_delete()` (+ `storage_delete_prefix`) | `gov_decommission()` |

This resolves the decommission asymmetry: `datom_decommission()` does **not** move
wholesale to datomanager. Its data-side teardown (delete GitHub repo + local clone) extracts
to `datom_repo_delete()`, which **stays in datom** and is also the complete solo-project
teardown. `gov_decommission()` in datomanager calls `datom_repo_delete()` +
`datom_storage_delete_prefix()` for the data side, then performs only the gov unregister +
gov-storage cleanup itself -- never touching the data repo directly. Same step-7 discipline,
applied to teardown.

**Footgun guard.** Because `datom_repo_delete()` is also the mechanism `gov_decommission()`
calls, it cannot blindly refuse on gov-attached conns. It carries the `confirm = project_name`
interlock plus an explicit `force_gov_attached = FALSE`: an interactive gov user is stopped
with "use `gov_decommission()`"; datomanager opts through visibly by passing `TRUE`. Explicit
parameter, not hidden behavior.

---

## What Moves from datom to datomanager

### Exported functions (5) -- renamed on the way out

| datom today | datomanager | Current file | Notes |
|---|---|---|---|
| `datom_init_gov()` | `gov_init()` | `R/conn.R` | Gov repo creation + skeleton push |
| `datom_attach_gov()` | `gov_attach()` | `R/conn.R` | Promotes a solo project to a governed one |
| `datom_decommission()` | `gov_decommission()` | `R/decommission.R` | Gov teardown only; data-side teardown stays in datom as `datom_repo_delete()` (see Authority Principle) |
| `datom_sync_dispatch()` | `gov_sync_dispatch()` | `R/sync.R` | Writes dispatch.json to gov |
| `datom_pull_gov()` | `gov_pull()` | `R/sync.R` | Pulls gov clone from remote |

### New data-side helpers that STAY in datom (extracted, not moved)

These are the `datom_repo_*` helpers the Authority Principle requires. They are new datom
exports created during the split so datomanager never mutates the data repo directly.

| Helper | Does | Replaces (inline today in) |
|---|---|---|
| `datom_repo_set_data_store()` | Rewrite `storage.data` in `project.yaml`; commit + push data repo | (new -- migration step 7) |
| `datom_repo_delete()` | Delete data GitHub repo + local clone | `datom_decommission()` steps 2-3 |

### Internal GOV_SEAM helpers (all in `R/utils-gov.R`, write-only block)

| Helper | Purpose |
|---|---|
| `.datom_gov_commit()` | Stage + commit on gov clone |
| `.datom_gov_push()` | Push gov clone to remote |
| `.datom_gov_pull()` | Fetch + fast-forward gov clone |
| `.datom_gov_write_dispatch()` | Write `projects/{name}/dispatch.json` |
| `.datom_gov_write_ref()` | Write `projects/{name}/ref.json` |
| `.datom_gov_register_project()` | Create `projects/{name}/` + initial files |
| `.datom_gov_unregister_project()` | Remove `projects/{name}/` |
| `.datom_gov_record_migration()` | Append to `projects/{name}/migration_history.json` |
| `.datom_gov_destroy()` | Tear down entire gov repo + storage (sandbox-only today) |

### New function in datomanager (Phase 19)

`gov_migrate_data()` -- atomic data-copy + ref.json switch + migration record. Net-new;
born in datomanager (never existed in datom). It orchestrates datom's `datom_storage_*` /
`datom_repo_*` helpers. See Phase 19 draft for design.

---

## What Stays in datom

These remain in datom permanently -- datom always needs to read gov regardless of who writes it.

| Helper | File | Why it stays |
|---|---|---|
| `.datom_gov_clone_exists()` | `R/utils-gov.R` | datom needs to detect gov presence |
| `.datom_gov_clone_open()` | `R/utils-gov.R` | datom reads from the clone |
| `.datom_gov_clone_init()` | `R/utils-gov.R` | datom clones on `datom_clone()` |
| `.datom_gov_validate_remote()` | `R/utils-gov.R` | datom validates remote on open |
| `.datom_gov_list_projects()` | `R/utils-gov.R` | `datom_projects()` is a read |
| `.datom_gov_project_path()` | `R/utils-gov.R` | Path helper used by reads |
| `.datom_resolve_ref()` | `R/ref.R` | Read-time data location resolution |
| `.datom_resolve_ref_from_clone()` | `R/ref.R` | Developer clone-first ref read |
| `.datom_check_ref_current()` | `R/ref.R` | Write-time ref guard (storage always) |
| `.datom_resolve_data_location()` | `R/ref.R` | Role-aware ref resolution |
| `datom_projects()` | `R/conn.R` | Portfolio read (portfolio view stays in datom) |
| `datom_pull()` | `R/sync.R` | Data repo pull (git-only, no gov writes) |

---

## The One Coupling to Resolve

`datom_init_repo()` (stays in datom) currently calls `.datom_gov_register_project()` when
a gov store is supplied. After the split:

- `datom_init_repo()` initializes the data repo only (no gov registration).
- `datomanager::gov_attach()` handles the gov registration step, as it already does for
  post-hoc gov attachment.

This is already structurally clean because Phase 18 made gov optional: `datom_init_repo()`
branches on `!is.null(store$governance)` before calling the registration helpers. The
lift-out just removes that branch from datom and documents that users who want gov from day
one call `gov_attach()` immediately after `datom_init_repo()`.

---

## What datom Must Preserve for datomanager (Interface Contract)

datomanager reads these from `conn` objects created by datom:

| Field | Current | Notes |
|---|---|---|
| `conn$gov_local_path` | character path | Gov clone location |
| `conn$gov_root` | character | Gov storage root (NULL = no gov) |
| `conn$gov_client` | paws s3 client or NULL | Gov storage client |
| `conn$project_name` | character | Used in commit messages, file paths |
| `conn$backend` | `"s3"` or `"local"` | Data backend |
| `conn$root` | character | Data store root (bucket or dir path) |
| `conn$prefix` | character | Data namespace prefix |
| `conn$region` | character or NULL | AWS region |

Do not rename or remove any of these without a coordinated bump with datomanager.

The `datom_conn` S3 class itself is the interface. datomanager creates no new conn types;
it receives conns from `datom_get_conn()` and operates on them.

---

## Package Structure (When Created)

```
datomanager/
  DESCRIPTION          Imports: datom, git2r, paws.storage, fs, yaml, glue, cli, purrr
  NAMESPACE
  R/
    init.R             gov_init(), gov_attach()
    decommission.R     gov_decommission()           # calls datom::datom_repo_delete()
    migrate.R          gov_migrate_data()            # Phase 19
    sync.R             gov_sync_dispatch(), gov_pull()
    utils-gov.R        All .datom_gov_* write helpers (moved from datom)
  tests/testthat/
    test-init.R
    test-decommission.R
    test-migrate.R
    test-sync.R
    test-utils-gov.R   Moved from datom
```

The `R/utils-gov.R` in datom retains only the read helpers after the split. datom gains
`datom_repo_set_data_store()` and `datom_repo_delete()` (data-side helpers; see Authority
Principle).

---

## Phase 19: gov_migrate_data() — First Delivery in datomanager

Phase 19 (draft at `dev/draft_managed_migration.md`) is the first concrete chunk
of datomanager work. Its placement is settled: **datomanager is its home**, not datom.

`gov_migrate_data()` is the governed migration **verb**. It does not move bytes itself
-- it orchestrates by calling down into datom's exported storage extension API
(`datom::datom_storage_copy()`, `datom_storage_verify()`, `datom_storage_list()`,
`datom_storage_delete_prefix()`, `datom_repo_set_data_store()`). datomanager owns only
the governed half: writing `ref.json`, committing to the gov repo, and calling
`.datom_gov_record_migration()`. Those gov writes belong behind the seam.

This split follows the seam between mechanism and policy: moving bytes is a platform
primitive (datom); declaring the new location authoritative is a governance decision
(datomanager).

**Prerequisite -- datom Phase 22**: before Phase 19 can be built, datom must export the
six storage/repo extension functions (`datom_storage_copy`, `datom_storage_verify`,
`datom_storage_list`, `datom_storage_delete_prefix`, `datom_repo_set_data_store`,
`datom_repo_delete`) with stable signatures. See `dev/draft_managed_migration.md` Part A.

**Activation ordering**:
1. Ship datom Phase 22 (export `datom_storage_*` + `datom_repo_set_data_store()` +
   `datom_repo_delete()`).
2. Create datomanager package scaffold (DESCRIPTION, NAMESPACE, skeleton R files).
3. Lift the 9 GOV_SEAM write helpers from datom to datomanager (mechanical move).
4. Lift + rename the 5 exported gov functions to `gov_*` (extract `datom_repo_delete()`
   from `datom_decommission()`'s data-side steps; that helper stays in datom).
5. Decouple `datom_init_repo()` from `.datom_gov_register_project()`.
6. Implement `gov_migrate_data()` in datomanager (Phase 19 chunks), calling datom's
   Phase 22 API.

Steps 2-5 are a 1-2 day mechanical effort. Step 6 is Phase 19's full scope.

---

## Relationship to Access Enforcement

`dev/datomanager_overview.md` describes an access enforcement layer (roles, grants,
IAM-backed S3 access points) that intercepts `datom_read()`. This is **also datomanager**.

Governance teams own both the gov lifecycle (who can register/decommission projects) and
access granting (who can read which tables). datomanager is their single tool. If the two
concerns grow sufficiently distinct in the future, datomanager can be split — but starting
as one package is the right call.

**Relationship summary**:

```
datom              -- data read/write, versioning, git sync (no access enforcement)
                   -- data-side helpers: datom_repo_set_data_store(), datom_repo_delete()
  ↑ Imports
datomanager        -- gov lifecycle: gov_init/attach/decommission/migrate_data
                   -- access enforcement (roles, grants, IAM), intercepts datom_read()
```

datom ships independently and is fully functional without datomanager. datomanager is the
governance team's companion layer, adoptable on-demand via `gov_attach()`.

---

## Commit Message Convention (Preserved from datom)

datomanager must preserve these message strings exactly -- they are part of the gov repo
audit contract and auditors/readers grep the history for them:

| Operation | Message |
|---|---|
| register project | `Register project {name}` |
| unregister project | `Unregister project {name}` |
| write dispatch | `Update dispatch for {name}` |
| write ref | `Update ref for {name}` |
| record migration | `Record migration for {name}: {summary}` |

---

## Effort Estimate

| Step | Effort |
|---|---|
| Package scaffold + DESCRIPTION wiring | half-day |
| Lift GOV_SEAM helpers + exported functions | half-day |
| Test migration (move tests from datom) | half-day |
| Decouple datom_init_repo from gov registration | half-day |
| Phase 19 (gov_migrate_data implementation) | 2-3 sessions |

Total before Phase 19: ~2 days. Phase 19 adds 2-3 sessions on top.
