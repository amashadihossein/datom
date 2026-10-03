# Read a datom Table

Returns a table as a data frame: the current version by default, or a
past version when you pass `version` (copy it from
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)).
Works with both developer and reader connections. To read a set, use
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

## Usage

``` r
datom_read(conn, name, version = NULL, context = NULL, ...)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, uses current.

- context:

  Reserved; currently ignored.

- ...:

  Reserved; currently ignored.

## Value

A data frame.

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

  # Current version
  dm <- datom_read(conn, "dm")
  print(head(dm))

  # A specific version, by its identifier -- byte-for-byte the same table
  v <- datom_history(conn, "dm")$version[1]
  print(identical(datom_read(conn, "dm", version = v), dm))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd66c2c91e/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd66c2c91e/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> # A tibble: 6 × 12
#>   STUDYID   DOMAIN USUBJID SUBJID   AGE AGEU  SEX   RACE  ETHNIC COUNTRY RFSTDTC
#>   <chr>     <chr>  <chr>    <int> <int> <chr> <chr> <chr> <chr>  <chr>   <chr>  
#> 1 STUDY-001 DM     STUDY-…      1    71 YEARS F     BLAC… NOT H… USA     2026-0…
#> 2 STUDY-001 DM     STUDY-…      2    27 YEARS M     ASIAN HISPA… CAN     2026-0…
#> 3 STUDY-001 DM     STUDY-…      3    35 YEARS M     OTHER HISPA… CAN     2026-0…
#> 4 STUDY-001 DM     STUDY-…      4    68 YEARS M     WHITE NOT H… USA     2026-0…
#> 5 STUDY-001 DM     STUDY-…      5    43 YEARS M     WHITE NOT H… USA     2026-0…
#> 6 STUDY-001 DM     STUDY-…      6    60 YEARS F     ASIAN NOT H… CAN     2026-0…
#> # ℹ 1 more variable: DMDTC <chr>
#> [1] TRUE
```
