# Package index

## Key terms

What datom’s words mean: project, store, connection, table, version, set

- [`datom`](https://amashadihossein.github.io/datom/reference/datom-package.md)
  [`datom-package`](https://amashadihossein.github.io/datom/reference/datom-package.md)
  : datom: A Unified Framework for Versioned, Traceable Tabular Data

## Connection & Setup

Create connections, initialize repositories

- [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  : Create a New datom Project
- [`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md)
  : Clone a datom Repository
- [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
  : Get a Pointer to a datom Project
- [`print(`*`<datom_conn>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_conn.md)
  : Print a datom Connection

## Store Objects

Create and inspect storage configuration objects

- [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)
  : Create a datom Store
- [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
  : Create an S3 Store Component
- [`datom_store_s3_creds()`](https://amashadihossein.github.io/datom/reference/datom_store_s3_creds.md)
  : Create a Credentials-Only S3 Store Component
- [`datom_store_local()`](https://amashadihossein.github.io/datom/reference/datom_store_local.md)
  : Create a Local Filesystem Store Component
- [`is_datom_store()`](https://amashadihossein.github.io/datom/reference/is_datom_store.md)
  : Check if Object is a datom Store
- [`is_datom_store_s3()`](https://amashadihossein.github.io/datom/reference/is_datom_store_s3.md)
  : Check if Object is an S3 Store Component
- [`is_datom_store_s3_creds()`](https://amashadihossein.github.io/datom/reference/is_datom_store_s3_creds.md)
  : Check if Object is a Credentials-Only S3 Store Component
- [`is_datom_store_local()`](https://amashadihossein.github.io/datom/reference/is_datom_store_local.md)
  : Check if Object is a Local Store Component
- [`print(`*`<datom_store>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_store.md)
  : Print a datom Store
- [`print(`*`<datom_store_s3>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_store_s3.md)
  : Print an S3 Store Component
- [`print(`*`<datom_store_s3_creds>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_store_s3_creds.md)
  : Print a Credentials-Only S3 Store Component
- [`print(`*`<datom_store_local>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_store_local.md)
  : Print a Local Store Component

## Read & Write

Read and write versioned tables

- [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
  : Read a datom Table
- [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  : Save a Data Frame as a datom Table
- [`datom_check_hashable()`](https://amashadihossein.github.io/datom/reference/datom_check_hashable.md)
  : Check Whether a Table Can Be Hashed by datom

## Sets

Write and read a versioned, citable set of artifacts, and declare its
members

- [`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
  : Declare a Member of a Set
- [`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
  : Save a Set as a New Version
- [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  : Read a datom Set
- [`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
  : Get the Data Behind One Member of a Set
- [`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
  : List a Set's Members and Their Labels
- [`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
  : Group a Set's Members into a Navigable View
- [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
  : Start Assembling a Set
- [`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
  : Add One Member to a Set
- [`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
  : Repoint a Set's Members at Newer Versions
- [`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md)
  : Drop Members from a Set
- [`print(`*`<datom_set>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_set.md)
  : Print a datom Set
- [`print(`*`<datom_link>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_link.md)
  : Print a Member Link

## Query & Status

List tables, view history, check status

- [`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
  : List the Tables and Sets in a Project
- [`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
  : Summarize a datom Project
- [`print(`*`<datom_summary>`*`)`](https://amashadihossein.github.io/datom/reference/print.datom_summary.md)
  : Print a datom_summary
- [`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
  : List Projects Registered in the Governance Repo
- [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
  : Show Version History
- [`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md)
  : Show Repository Status
- [`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md)
  : Get Parent Lineage for a Table
- [`datom_get_lineage()`](https://amashadihossein.github.io/datom/reference/datom_get_lineage.md)
  : Show a Table's Original Sources or Direct Inputs
- [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
  : Name an Input for a Table You Are About to Write
- [`datom_lineage_union()`](https://amashadihossein.github.io/datom/reference/datom_lineage_union.md)
  : Union and Deduplicate source_lineage Lists

## Sync Operations

Batch sync from files, scan manifests, sync metadata to S3

- [`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md)
  : Pull Latest Changes from Remote
- [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
  : Bring New and Changed Files Into a Project
- [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
  : Preview What a Sync Will Change

## Validation

Validate repository structure and git-S3 consistency

- [`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
  : Validate Git-Storage Consistency
- [`is_valid_datom_repo()`](https://amashadihossein.github.io/datom/reference/is_valid_datom_repo.md)
  : Check if Path is a Valid datom Repository

## Storage Extension API

Low-level storage and data-repo primitives for package developers
(e.g. datomanager). End users should use datom_read / datom_write /
datom_repo_delete instead.

- [`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md)
  : List All Objects in a datom Storage Namespace
- [`datom_storage_read_json()`](https://amashadihossein.github.io/datom/reference/datom_storage_read_json.md)
  : Read a JSON Document from a datom Storage Namespace
- [`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md)
  : Delete All Objects Under a datom Storage Prefix
- [`datom_storage_copy()`](https://amashadihossein.github.io/datom/reference/datom_storage_copy.md)
  : Copy All Objects Between Two datom Storage Namespaces
- [`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md)
  : Verify a Copy Between Two datom Storage Namespaces
- [`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)
  : Rewrite the Data Store Pointer in project.yaml
- [`datom_repo_attach_governance()`](https://amashadihossein.github.io/datom/reference/datom_repo_attach_governance.md)
  : Write the Data-Side Governance Attachment Record
- [`datom_repo_commit()`](https://amashadihossein.github.io/datom/reference/datom_repo_commit.md)
  : Commit Content in the Data Repo
- [`datom_repo_push()`](https://amashadihossein.github.io/datom/reference/datom_repo_push.md)
  : Push the Data Repo to Its Remote

## Teardown

Permanently remove a project’s data repo and local clone

- [`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)
  : Delete the Data GitHub Repository and Local Clone

## Example Data

Bundled clinical trial data for examples and vignettes

- [`datom_example_data()`](https://amashadihossein.github.io/datom/reference/datom_example_data.md)
  : Load Example Clinical Trial Data
- [`datom_example_cutoffs()`](https://amashadihossein.github.io/datom/reference/datom_example_cutoffs.md)
  : Monthly Cutoff Dates for Example Study
