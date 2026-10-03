# Bring New and Changed Files Into a Project

Takes the preview from
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
and saves each new or changed file as a version of a table named after
the file; unchanged files are skipped. This is the usual way to bring
files into datom. To save a data frame you built in R, use
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md).

## Usage

``` r
datom_sync(
  conn,
  manifest,
  continue_on_error = TRUE,
  sources = NULL,
  tags = list(type = "input"),
  x = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- manifest:

  Data frame from
  [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md).
  On an ordinary repo, with columns `name`, `file`, `format`,
  `original_file_sha`, `status`. On a product repo, the set preview:
  `project`, `name`, `kind`, `version_from`, `version_to`, `status`. Any
  subset of its rows will do.

- continue_on_error:

  If `TRUE` (default), continues processing remaining tables when one
  fails. If `FALSE`, stops on first error. Not accepted on a product
  repo, where one failure stops the call and nothing has been written.

- sources:

  On a product repo only, and required there: one `datom_conn`, or a
  list of them, for the projects named by the rows being applied – the
  same connections the preview was built with. Refused on an ordinary
  repo.

- tags:

  On a product repo only: the labels given to members added by `new`
  rows. Default `list(type = "input")`. A repointed member keeps its own
  labels. Refused on an ordinary repo.

- x:

  On a product repo only: the `datom_set` to apply the preview to, from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  or
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md).
  Omitted, the repo's stored set is read, or an empty one used when it
  has never been written. Refused on an ordinary repo.

## Value

On an ordinary repo, the manifest data frame augmented with `result` and
`error` columns. `result` is `"success"`, `"skipped"`, or `"error"`.

On a product repo, the updated `datom_set`, with what changed appended
to its `datom_edits` attribute. Its `version` and `data_sha` are emptied
when any row was applied.

## Details

Reading files needs the rio package (`install.packages("rio")`).

Rows flagged `"unsupported_format"` by
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
are reported as `result = "error"` with the recourse in the `error`
column; the rest of the batch still processes.

On a product repo (`mode: product`) it applies a preview of the repo's
set instead – see "On a product repo" below.

## On a product repo

A product repo owns one set, and this call applies a preview from
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
to it: each `new` row adds a member at `version_to`, labelled with
`tags`, and each `changed` row repoints the member it names from
`version_from` to `version_to`, keeping that member's labels exactly.
Rows of any other status do nothing. Filter the preview first to apply
only part of it – `subset(m, name != "lb")` – or build the frame by hand
with the same columns.

**Nothing is written.** The set comes back edited, and it is stored only
when you pass it to
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md);
the call ends by saying so. The write's default commit message then
names what was added and repointed.

This is the one difference from syncing files, where each table is
written as it syncs. A set is saved in one step, so the edit becomes one
version, and you can look at the set, or add to it, before it does.

Every member added is read from its source first, which confirms the
version exists and records the project that wrote it. The call stops,
before changing anything, when:

- the set has moved since the preview was built – a `changed` row's
  member is no longer at `version_from`, or a `new` row's artifact is
  already in the set. Build the preview again from the current set;

- a row's `kind` or `project` disagrees with the artifact it names;

- a `new` or `changed` row names a project with no connection in
  `sources`, or the same artifact appears in two such rows;

- `sources` includes the repo's own project, whose members are outputs.

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage. File import needs the optional
# rio package.
if (requireNamespace("git2r", quietly = TRUE) &&
    requireNamespace("rio", quietly = TRUE)) {
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

  file.copy(
    system.file("extdata", "dm.csv", package = "datom"),
    file.path(tmp, "repo", "input_files", "dm.csv")
  )

  manifest <- datom_sync_manifest(conn)
  result <- datom_sync(conn, manifest)
  print(result[, c("name", "status", "result")])

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd4d4344a4/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd4d4344a4/repo
#> ℹ Scanned 1 file: 1 new, 0 changed, 0 unchanged.
#> ℹ Syncing 1 table...
#> ✔ Wrote "dm" (full): "dd44c083"
#> ✔ "dm" synced (new).
#> ℹ Sync complete: 1 succeeded, 0 failed, 0 skipped.
#>   name status  result
#> 1   dm    new success
```
