# Changelog

## datom 0.1.0

Initial CRAN release. `datom` provides version-controlled data
management for reproducible scientific and clinical workflows — tables
are tracked as code in git while actual data lives in cloud storage (S3)
or a local filesystem backend.

datom is experimental: the API may change without a deprecation cycle
until it reaches a stable release.

### Core read/write/version

- [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  — write a data frame as a versioned parquet table with automatic
  SHA-based deduplication. When `parents` is supplied it takes resolved
  [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
  records and derives the table’s `source_lineage` as the deduplicated
  union of their lineages; the public `source_lineage` argument has been
  removed.
- [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
  — read the current or any historical version of a table.
- [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
  — view the full version history of a table.
- [`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
  — list tables in a project with optional glob filtering.

### Sync

- [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
  — build a sync manifest from a directory of files, detecting new,
  changed, and unchanged tables.
- [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
  — execute the manifest to write all new/changed tables in one pass.

### Query & lineage

- [`datom_get_lineage()`](https://amashadihossein.github.io/datom/reference/datom_get_lineage.md)
  /
  [`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md)
  — retrieve parent and source lineage for a table version; parent
  entries carry `source`, `table`, `version`, and `data_sha`.

- [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
  — resolve a parent table against a connection into a pure-data lineage
  record, capturing the parent’s authoritative `data_sha` and
  `source_lineage`. Same-project and cross-project parents are declared
  identically; pass the records to `datom_write(parents = ...)`.

- [`datom_lineage_union()`](https://amashadihossein.github.io/datom/reference/datom_lineage_union.md)
  — deduplicated union of `source_lineage` lists (by
  `{project, table, version_sha}`); the building block of the composable
  recipe for recomputing and checking a table’s lineage.

- `datom_validate_lineage()` was removed before release. Lineage
  consistency is now a composable recipe:
  [`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md),
  per-parent `datom_get_lineage(depth = "source")`, and
  [`datom_lineage_union()`](https://amashadihossein.github.io/datom/reference/datom_lineage_union.md),
  compared against the recorded `source_lineage`.

- [`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md)
  — show connection, table, git, and input-file status.

- [`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
  — compact project overview (backend, table count, versions,

  last write).

- [`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
  — list all projects registered in a governance repository.

### Storage management

- [`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md)
  — enumerate objects in a project namespace.
- [`datom_storage_copy()`](https://amashadihossein.github.io/datom/reference/datom_storage_copy.md)
  — copy all objects between two storage backends.
- [`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md)
  — verify object integrity after a copy or migration.
- [`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md)
  — delete objects under a prefix.

### Repository & governance

- [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  — one-time project setup (folder structure, git, initial push).
- [`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md)
  — clone an existing project for a new team member.
- [`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md)
  — pull latest commits from the data (and optionally governance)
  repository.
- [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
  — establish a connection to an existing project.
- [`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)
  — update the storage backend for a project.
- [`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)
  — tear down a project (storage + GitHub repo).
- [`datom_repo_attach_governance()`](https://amashadihossein.github.io/datom/reference/datom_repo_attach_governance.md)
  — attach a governance layer to a solo project.
- [`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
  /
  [`is_valid_datom_repo()`](https://amashadihossein.github.io/datom/reference/is_valid_datom_repo.md)
  — structural validation of the local repository.

### Store constructors

- [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)
  — composite store bundling governance + data + git config.
- [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
  — S3 backend store component.
- [`datom_store_s3_creds()`](https://amashadihossein.github.io/datom/reference/datom_store_s3_creds.md)
  — credentials-only S3 component (for readers).
- [`datom_store_local()`](https://amashadihossein.github.io/datom/reference/datom_store_local.md)
  — local filesystem backend store component.
- Predicates:
  [`is_datom_store()`](https://amashadihossein.github.io/datom/reference/is_datom_store.md),
  [`is_datom_store_s3()`](https://amashadihossein.github.io/datom/reference/is_datom_store_s3.md),
  [`is_datom_store_s3_creds()`](https://amashadihossein.github.io/datom/reference/is_datom_store_s3_creds.md),
  [`is_datom_store_local()`](https://amashadihossein.github.io/datom/reference/is_datom_store_local.md).

### Example data

- [`datom_example_data()`](https://amashadihossein.github.io/datom/reference/datom_example_data.md)
  — bundled clinical-trial-style data (DM, EX, LB, AE domains) with
  optional date cutoff filtering.
- [`datom_example_cutoffs()`](https://amashadihossein.github.io/datom/reference/datom_example_cutoffs.md)
  — six monthly cutoff dates for vignette reproducibility.
