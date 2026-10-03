# Name an Input for a Table You Are About to Write

Use before
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
when the table you are writing was made from other datom tables. Each
call names one input – one table at one exact version – and returns a
note that
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
saves with the new table, so its
[lineage](https://amashadihossein.github.io/datom/reference/datom-package.md)
records what it was made from. For several inputs, make one call each
and pass them together as a list to `parents`. If the inputs are members
of a set, pass the set as `x` and name several tables at once; each gets
the version the set pins.

## Usage

``` r
datom_parent(conn, table, version = NULL, x = NULL, tags = NULL)
```

## Arguments

- conn:

  A `datom_conn` scoped to the parent's project store, from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- table:

  Parent table name (single non-empty validated string). With `x`, a
  character vector of one or more member names.

- version:

  Parent version (metadata_sha; single non-empty string). Exactly one of
  `version` and `x` is required.

- x:

  Optional `datom_set` from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  (or one being built) whose members supply the versions. Exactly one of
  `version` and `x` is required.

- tags:

  Optional named list of labels narrowing a member name the set holds
  more than once, e.g. `list(type = "input")`. Only with `x`.

## Value

Without `x`, a list with exactly `source`, `table`, `version`,
`data_sha`, and `source_lineage`. `source` is the project the parent's
own metadata says it belongs to, falling back to the project manifest
and then to the connection's name (see
[`.datom_declared_project()`](https://amashadihossein.github.io/datom/reference/dot-datom_declared_project.md))
– **not** simply the name on `conn`, which on a reader connection is an
unverified label and which `source` cannot afford, since it is part of
the declaring table's version. `source_lineage` is `NULL` when the
snapshot carries none. With `x`, an unnamed list of such records, one
per `table`, in the order given.

## Details

The parent's data fingerprint is read from the parent's own saved
record; you cannot supply it, so a lineage entry cannot claim data the
parent never had. The record is plain data with no connection inside, so
it can be saved and reused.

Same-project and cross-project parents are declared identically – the
only difference is which connection is passed. `source` is always
derived from the connection's `project_name`.

## Taking the version from a set

When the inputs of a derivation are members of a set, pass the set as
`x` instead of a `version`: each `table` is looked up among the set's
members and declared at the version the set pins. That keeps the parents
a derived table records in step with the set it is derived through,
without looking each version up by hand.

The member is chosen exactly as
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
chooses it. A name held by two members – a current table beside a locked
baseline, say – stops and lists both; narrow with `tags`. A member that
is itself a set stops too, since only a table can be a parent.

With `x`, `table` may name several tables and the result is **always a
list** of parent records, even for one table, so it can be passed
straight to the `parents` argument of
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md).
Without `x` the result is one record, as it always was.

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

  # Resolve a parent declaration to pass to the parents argument of
  # datom_write.
  print(datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a76e39ffd/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a76e39ffd/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> $source
#> [1] "example_project"
#> 
#> $table
#> [1] "dm"
#> 
#> $version
#> [1] "b5cbba4501f518d7bbe1eaf4f0c236895b12d63677b9f75b9388b715055c832e"
#> 
#> $data_sha
#> [1] "71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538"
#> 
#> $source_lineage
#> NULL
#> 
```
