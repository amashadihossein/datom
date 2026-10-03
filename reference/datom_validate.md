# Validate Git-Storage Consistency

Checks that git metadata matches S3 storage for all tables and
repo-level files. Reports mismatches as a structured result.

## Usage

``` r
datom_validate(conn, fix = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- fix:

  If `TRUE`, attempts to fix inconsistencies by syncing data-side
  metadata (manifest + per-artifact metadata) to storage, and by
  restoring a **set's** payload when storage has lost it – git holds
  `{name}/set.json`, so those bytes are recoverable. A restore happens
  only when the stored object is absent and only when the clone's bytes
  hash to the `document_sha` already recorded; a stored payload is never
  overwritten and its recorded hash is never recomputed.

  A missing **table** payload (`data_missing_s3`) cannot be repaired:
  the parquet bytes are never in the clone. Those tables are named in a
  warning and need
  [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  re-run with the source data.

## Value

A list with:

- valid:

  Logical — `TRUE` if everything is consistent.

- repo_files:

  Data frame of repo-level file checks.

- tables:

  Data frame of per-artifact checks, one row per artifact of either
  kind, with a `kind` column. Named `tables` for compatibility.

- fixed:

  Logical — `TRUE` if `fix = TRUE` was applied.

## What is checked per artifact

Both kinds of artifact are checked, and the payload check branches on
kind: a table's payload is a parquet object, a set's is a JSON document
at `{name}/{data_sha}.json`. A **set** is checked further, because a
payload whose members have gone is a citation that no longer resolves:

- every member's pinned version must still exist in this project's
  storage. **One level deep only** – a member that is itself a set is
  confirmed to exist and its own member list is never opened, so the
  cost of validating a set never depends on the tree beneath it.
  Validating an inner set is a separate call against that set's own
  project.

- a member recorded as belonging to **another project** is checked as a
  well-formed pointer only. This connection sees one namespace, so an
  existence check there would report every cross-project member as
  rotten.

- the set must record the hash of its stored payload, without which no
  reader can verify it.

Statuses reported in the `tables` frame: `metadata_missing_s3`,
`history_missing_s3`, `data_missing_s3`, `members_unresolvable`,
`document_sha_missing`, and `kind_unsupported` for an artifact whose
metadata declares a kind this version of datom does not know – reported
rather than fatal, with that row's payload left unchecked.

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage.
if (requireNamespace("git2r", quietly = TRUE)) {
  tmp <- tempfile("datom-example-")
  remote <- file.path(tmp, "remote.git")
  dir.create(remote, recursive = TRUE)
  git2r::init(remote, bare = TRUE)

  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token", # role selector; a local remote needs none
    data_repo_url = remote,
    validate = FALSE
  )
  datom_init_repo(file.path(tmp, "repo"), "example_project", store)
  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  datom_validate(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a7652b4d039/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a7652b4d039/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ℹ No governance attached -- skipping dispatch/ref/migration_history checks.
#> ✔ All checks passed. Git and S3 are consistent.
```
