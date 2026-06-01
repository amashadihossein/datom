# datomanager — Companion Governance Package Scope

> **Purpose**: Scopes the creation of `datomanager`, the companion R package that will own
> datom's governance write surface. This is a persistent vision/planning document, not a
> phase doc. Update it as decisions solidify.
>
> **Status**: Pre-creation. No code exists yet. datom still owns the full GOV_SEAM surface.
> See `dev/README.md` Backlog for activation priority.

---

## What is datomanager?

`datomanager` is a companion R package that takes over ownership of governance **write**
operations that currently live in datom behind the `# GOV_SEAM:` tag. It does NOT cover
access enforcement (roles, grants, IAM) -- that is a separate future concern described in
`dev/datomaccess_overview.md`.

**Dependency direction**: `datomanager` Imports `datom`. datom does NOT import or know
about datomanager. Users of datom without datomanager continue to get the full data
management surface; they just cannot perform governance write operations (which currently
means: you get an error if you try to call gov-only commands without a gov store attached).

**Scope in one sentence**: datomanager owns the gov repo lifecycle (init, register,
decommission, destroy) and data migration (`datom_migrate_data()`). datom retains all reads.

---

## What Moves from datom to datomanager

### Exported functions (5)

| Function | Current file | Notes |
|---|---|---|
| `datom_init_gov()` | `R/conn.R` | Gov repo creation + skeleton push |
| `datom_attach_gov()` | `R/conn.R` | Promotes no-gov project to gov-attached |
| `datom_decommission()` | `R/decommission.R` | Project teardown (data + gov) |
| `datom_sync_dispatch()` | `R/sync.R` | Writes dispatch.json to gov |
| `datom_pull_gov()` | `R/sync.R` | Pulls gov clone from remote |

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

`datom_migrate_data()` -- atomic data-copy + ref.json switch + migration record. Not yet
in datom. datomanager is its first and only home. See Phase 19 draft for design.

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
- `datomanager::datom_attach_gov()` handles the gov registration step, as it already does
  for post-hoc gov attachment.

This is already structurally clean because Phase 18 made gov optional: `datom_init_repo()`
branches on `!is.null(store$governance)` before calling the registration helpers. The
lift-out just removes that branch from datom and documents that users who want gov from day
one call `datom_attach_gov()` immediately after `datom_init_repo()`.

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
    init.R             datom_init_gov(), datom_attach_gov()
    decommission.R     datom_decommission()
    migrate.R          datom_migrate_data()         # Phase 19
    sync.R             datom_sync_dispatch(), datom_pull_gov()
    utils-gov.R        All .datom_gov_* write helpers (moved from datom)
  tests/testthat/
    test-init.R
    test-decommission.R
    test-migrate.R
    test-sync.R
    test-utils-gov.R   Moved from datom
```

The `R/utils-gov.R` in datom retains only the read helpers after the split.

---

## Phase 19: datom_migrate_data() — First Delivery in datomanager

Phase 19 (draft at `dev/draft_phase_19_managed_migration.md`) is the first concrete chunk
of datomanager work. Its placement is settled: **datomanager is its home**, not datom.

`datom_migrate_data()` is a pure gov-write surface (writes `ref.json`, commits to gov repo,
calls `.datom_gov_record_migration()`). It belongs behind the seam.

**Activation ordering**:
1. Create datomanager package scaffold (DESCRIPTION, NAMESPACE, skeleton R files).
2. Lift the 9 GOV_SEAM write helpers from datom to datomanager (mechanical move).
3. Lift the 5 exported functions.
4. Decouple `datom_init_repo()` from `.datom_gov_register_project()`.
5. Implement `datom_migrate_data()` in datomanager (Phase 19 chunks).

Steps 1-4 are a 1-2 day mechanical effort. Step 5 is Phase 19's full scope.

---

## Relationship to Access Enforcement (datomaccess concept)

`dev/datomaccess_overview.md` describes an access enforcement layer (roles, grants,
IAM-backed S3 access points) that intercepts `datom_read()`. That is **not** datomanager.

datomanager owns gov *write* operations (lifecycle management, migration). The access
enforcement concept from datomaccess_overview.md is a separate package (working name still
`datomaccess`) that may be built after datomanager is established.

**Relationship summary**:

```
datom              -- data read/write, versioning, git sync (no access enforcement)
  ↑ Imports
datomanager        -- gov lifecycle writes, project registration, data migration
  ↑ (future)
datomaccess        -- access enforcement (roles, grants, IAM), intercepts datom_read()
```

datom ships independently. datomanager layers gov management on top. datomaccess layers
access control on top of both. Each is optional and adoptable independently.

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
| Phase 19 (datom_migrate_data implementation) | 2-3 sessions |

Total before Phase 19: ~2 days. Phase 19 adds 2-3 sessions on top.
