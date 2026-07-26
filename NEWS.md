# datom 0.1.0

Initial CRAN release. `datom` provides version-controlled data management for
reproducible scientific and clinical workflows — tables are tracked as code in
git while actual data lives in cloud storage (S3) or a local filesystem backend.

datom is experimental: the API may change without a deprecation cycle until it
reaches a stable release.

## Table identity: the `datom-cv1` canonical hash

Table identity is defined by a canonical hash of a table's **values**
(`datom-cv1`), not by the bytes of its parquet serialization. Hashing the
serialization tied identity to the writer: an `arrow` upgrade or a different
compression default produced different bytes for identical data, and therefore
a spurious new version. See
`vignette("design-version-shas")` for the model and the identity decisions.

* **Pre-release `data_sha` values change, and there is no migration path.**
  Any table written by a pre-release build carries a `data_sha` computed by the
  old algorithm. Those values are not recomputed, converted, or reconciled —
  pilots should re-onboard their data. Reads of pre-existing metadata still
  work (the new stored-object integrity check is skipped when the older
  metadata carries no `parquet_sha`), but content identity is not comparable
  across the change.
* Three SHAs are now recorded per table: `data_sha` (content identity),
  `metadata_sha` (the version you pass to `datom_read(version = )`), and
  `parquet_sha` (the stored object's SHA-256, verified on read before parsing).
  `original_file_sha` continues to record input-file provenance for tables
  onboarded by `datom_sync()`.
* `metadata.json` gains `hash_algo`, `parquet_sha`, and `column_hashes` — an
  ordered per-column digest index from which `data_sha` can be re-derived
  without downloading data.

### Deliberate narrowings

Three capabilities were narrowed on purpose. Each has a specific recourse.

* **List and exotic columns are refused, with advice.** A column must be
  `logical`, `integer`, `double`, `character`, `factor`, `Date`, `POSIXct`,
  `difftime`/`hms`, `data.table::ITime`/`IDate`, `bit64::integer64`, or a
  labelled vector over one of those. List columns (including nested data
  frames, blobs, and `POSIXlt`), `complex`, `raw`, `sf` geometry, `units`, and
  `zoo`/`chron` columns now abort the write, naming every offending column at
  once and stating how to convert each one. A refusal leaves no git, storage,
  or manifest state behind. New export `datom_check_hashable()` reports the
  same advice as a pre-flight check.
* **`datom_sync()` accepts only allowlisted formats.** Flat tabular files
  only: `csv`, `tsv`, `txt`, `psv`, `parquet`, `sas7bdat`, `xpt`, `sav`,
  `zsav`, `por`, `dta`, `xls`, `xlsx`. `.rds`, `.json`, and `.xml` are no
  longer imported directly; `datom_sync_manifest()` flags them
  `unsupported_format` and still processes their allowlisted siblings. Read
  such a source yourself and pass the data frame to `datom_write()` — note
  that this makes the table *derived*, so it has no `original_file_sha` and
  input-file change detection does not apply to it.
* **The internal `sort_columns` / `sort_rows` options are removed.** Row and
  column order are significant, and nothing is sorted: sorting would need a
  collation order, which is locale-dependent, reintroducing exactly the
  platform dependence the canonical hash exists to remove. Sort explicitly
  before writing if order should not matter.

## Core read/write/version

* `datom_write()` — write a data frame as a versioned parquet table with
  automatic SHA-based deduplication. When `parents` is supplied it takes
  resolved `datom_parent()` records and derives the table's `source_lineage`
  as the deduplicated union of their lineages; the public `source_lineage`
  argument has been removed.
* `datom_read()` — read the current or any historical version of a table. The
  downloaded object is verified against its recorded `parquet_sha` before
  parsing, so corruption or tampering aborts rather than returning data.
* `datom_check_hashable()` — pre-flight check for the table contract: reports
  per column whether `datom_write()` can hash it and, when it cannot, exactly
  how to fix it. Pure — no connection, store, or network.
* `datom_history()` — view the full version history of a table.
* `datom_list()` — list tables in a project with optional glob filtering.

## Sync

* `datom_sync_manifest()` — build a sync manifest from a directory of files,
  detecting new, changed, and unchanged tables.
* `datom_sync()` — execute the manifest to write all new/changed tables in one
  pass.

## Query & lineage

* `datom_get_lineage()` / `datom_get_parents()` — retrieve parent and source
  lineage for a table version; parent entries carry `source`, `table`,
  `version`, and `data_sha`.
* `datom_parent()` — resolve a parent table against a connection into a
  pure-data lineage record, capturing the parent's authoritative `data_sha`
  and `source_lineage`. Same-project and cross-project parents are declared
  identically; pass the records to `datom_write(parents = ...)`.
* `datom_lineage_union()` — deduplicated union of `source_lineage` lists
  (by `{project, table, version_sha}`); the building block of the composable
  recipe for recomputing and checking a table's lineage.
* `datom_validate_lineage()` was removed before release. Lineage consistency
  is now a composable recipe: `datom_get_parents()`, per-parent
  `datom_get_lineage(depth = "source")`, and `datom_lineage_union()`, compared
  against the recorded `source_lineage`.
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
