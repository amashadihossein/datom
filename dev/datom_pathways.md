# datom Pathway Map

This document is a quick lookup for canonical routes through datom's architecture. It is not the source of truth for schemas or APIs; it points to the route the design expects developers and companion packages to use.

Use this before adding a new lookup path, helper, index, or metadata field. If a route already exists here, prefer using or hardening that route over opening a parallel path.

## Maintenance Rule

Any change to metadata schema, storage layout, governance refs, lineage, access control, role resolution, migration, or decommissioning must do one of two things:

1. Update the relevant route card in this document.
2. Explicitly note "no pathway impact" in the phase progress log or PR description.

Each route card should stay short. Put detailed schema and algorithm changes in `dev/datom_specification.md`; this document should name the intended path and point to the canonical functions or files.

## Route Cards

### Given table + version, read data

**Question:** I have a table name and a datom version. Which parquet object should be read?

**Canonical route:**

1. Treat `version` as metadata_sha.
2. Open `{table}/.metadata/{version}.json` when the exact version is supplied, or use `{table}/.metadata/version_history.json` when resolving display/history state.
3. Read `data_sha` from the metadata/history entry.
4. Fetch `{table}/{data_sha}.parquet` from the data store.

**Primary functions/files:** `datom_read()`, `.datom_resolve_version()`, `metadata.json`, `{metadata_sha}.json`, `version_history.json`.

**Do not:** Try to infer metadata_sha from data_sha unless the route explicitly starts from `version_history.json`.

### Given data_sha, find metadata versions

**Question:** I have a content hash. Which datom versions used these bytes?

**Canonical route:**

1. Open `{table}/.metadata/version_history.json`.
2. Filter entries where `data_sha` matches.
3. Use each matching `version` as the metadata_sha.

**Primary functions/files:** `version_history.json`, `datom_history()`.

**Why this matters:** `metadata_sha -> data_sha` is a direct lookup through metadata. `data_sha -> metadata_sha` is many-to-one and only cheap because `version_history.json` records `data_sha` in each entry.

**Do not:** Scan all `{table}/.metadata/{metadata_sha}.json` snapshots unless recovering from a missing/corrupt history file.

### Given derived table, find raw source inputs

**Question:** Which raw source versions contributed to this derived table?

**Canonical route:**

1. Open the table's current or versioned metadata snapshot.
2. Read `source_lineage`.
3. Treat each `{project, table, version_sha}` entry as a terminal raw-source leaf.

**Primary functions/files:** `datom_get_lineage(depth = "source")`, `metadata.json`, `{metadata_sha}.json`.

**Do not:** Traverse recursively through `source_lineage`. Imported tables contain a self-entry by design.

### Given table, walk parent graph

**Question:** What derived tables or parent versions led to this table?

**Canonical route:**

1. Open the table's current or versioned metadata snapshot.
2. Read `parents`.
3. For each parent, use `parents[].version` as metadata_sha and open `{parent_table}/.metadata/{version}.json`.
4. Repeat only through `parents`.

**Primary functions/files:** `datom_get_lineage(depth = "parents")`, `datom_validate_lineage()`, `parents`.

**Do not:** Use `source_lineage` as a graph edge. It is a flattened source attribution list, not a traversal graph.

### Given user + table, decide read access

**Question:** Can this reader access a table, especially a derived table?

**Canonical route:**

1. Resolve the project and data location through governance when governance is attached.
2. Open the requested table's metadata snapshot.
3. Read `source_lineage`.
4. Check each `{project, table, version_sha}` against the policy registry, where `version_sha` is data_sha.
5. Call `datom_read()` only after all source entries are authorized.

**Primary functions/files:** Future datomaccess access gate, `.datom_resolve_ref()`, `ref.json`, `source_lineage`.

**Do not:** Authorize derived table access using only the derived table's own data_sha. Permissions must cover the raw source lineage.

### Given store + project, resolve data location

**Question:** Where should reads and writes look for this project's data bytes and metadata mirror?

**Canonical route:**

1. If governance is attached, resolve `projects/{project}/ref.json` from the governance store or local governance clone according to role.
2. Compare the resolved location with the data store supplied by the caller.
3. Developer mismatch: pull data git and re-read `project.yaml`.
4. Reader mismatch: warn and proceed with the ref-resolved location using the reader's credentials.
5. Write-time guard always reads `ref.json` from storage before writing.

**Primary functions/files:** `.datom_resolve_data_location()`, `.datom_check_ref_current()`, `ref.json`, `project.yaml`.

**Do not:** Treat a caller-supplied bucket/prefix as authoritative after governance is attached.

### Given store credentials, determine reader vs developer role

**Question:** Should the connection use developer or reader behavior?

**Canonical route:**

1. Developer role requires explicit git/GitHub capability plus a local data path.
2. Reader role uses storage credentials only and resolves data location from governance when available.
3. Presence of `github_pat` changes role expectations; do not pass it to reader-only store objects.

**Primary functions/files:** `datom_store()`, `datom_store_s3()`, `datom_store_s3_creds()`, `datom_get_conn()`.

**Do not:** Infer backend or role from `conn$client` being NULL. Use explicit backend/role fields and constructors.

### Given migration need, switch data location

**Question:** How should a project move to a new data store or prefix?

**Canonical route:**

1. Copy data bytes and metadata mirror to the new data location.
2. Update governance `ref.json` to point to the new location.
3. Record migration history in governance.
4. Let readers resolve the new location from governance.

**Primary functions/files:** Future `datom_migrate_data()`, `ref.json`, `migration_history.json`, `datom_attach_gov()`.

**Do not:** Change only `project.yaml` or only storage contents. Governance `ref.json` is the routing authority after governance is attached.

### Given decommission request, remove project safely

**Question:** What is the safe deletion order for a datom project?

**Canonical route:**

1. Require literal confirmation matching the project name.
2. Delete the project's `datom/` namespace inside the data store root.
3. Delete the data GitHub repo.
4. Delete the local data clone.
5. Unregister the project from governance.
6. Delete governance storage under `projects/{project}/`.

**Primary functions/files:** `datom_decommission()`, `.datom_gov_unregister_project()`.

**Do not:** Delete the storage root itself. Buckets/directories are caller-owned; datom owns only its namespace.