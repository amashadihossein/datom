# datom 0.1.0

Initial CRAN release. `datom` provides version-controlled data management for
reproducible scientific and clinical workflows — tables are tracked as code in
git while actual data lives in cloud storage (S3) or a local filesystem backend.

## Core read/write/version

* `datom_write()` — write a data frame as a versioned parquet table with
  automatic SHA-based deduplication.
* `datom_read()` — read the current or any historical version of a table.
* `datom_history()` — view the full version history of a table.
* `datom_list()` — list tables in a project with optional glob filtering.

## Sync

* `datom_sync_manifest()` — build a sync manifest from a directory of files,
  detecting new, changed, and unchanged tables.
* `datom_sync()` — execute the manifest to write all new/changed tables in one
  pass.

## Query & lineage

* `datom_get_lineage()` / `datom_get_parents()` — retrieve parent and source
  lineage for a table version.
* `datom_validate_lineage()` — verify that declared lineage is consistent with
  stored metadata.
* `datom_status()` — show connection, table, git, and input-file status.
* `datom_summary()` — compact project overview (backend, table count, versions,

  last write).
* `datom_projects()` — list all projects registered in a governance repository.

## Storage management

* `datom_storage_list()` — enumerate objects in a project namespace.
* `datom_storage_copy()` — copy all objects between two storage backends.
* `datom_storage_verify()` — verify object integrity after a copy or migration.
* `datom_storage_delete_prefix()` — delete objects under a prefix.

## Repository & governance

* `datom_init_repo()` — one-time project setup (folder structure, git, initial
  push).
* `datom_clone()` — clone an existing project for a new team member.
* `datom_pull()` — pull latest commits from the data (and optionally governance)
  repository.
* `datom_get_conn()` — establish a connection to an existing project.
* `datom_repo_set_data_store()` — update the storage backend for a project.
* `datom_repo_delete()` — tear down a project (storage + GitHub repo).
* `datom_repo_attach_governance()` — attach a governance layer to a solo
  project.
* `datom_validate()` / `is_valid_datom_repo()` — structural validation of the
  local repository.

## Store constructors

* `datom_store()` — composite store bundling governance + data + git config.
* `datom_store_s3()` — S3 backend store component.
* `datom_store_s3_creds()` — credentials-only S3 component (for readers).
* `datom_store_local()` — local filesystem backend store component.
* Predicates: `is_datom_store()`, `is_datom_store_s3()`,
  `is_datom_store_s3_creds()`, `is_datom_store_local()`.

## Example data

* `datom_example_data()` — bundled clinical-trial-style data (DM, EX, LB, AE
  domains) with optional date cutoff filtering.
* `datom_example_cutoffs()` — six monthly cutoff dates for vignette
  reproducibility.
