# Read a datom Table

Unified read function with dispatch via `dispatch.json`. Reads from S3
metadata cache for data readers.

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

  Optional context for dispatch (e.g., "default", "cached").

- ...:

  Additional parameters forwarded to routed function.

## Value

Data frame or routed function result.

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
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33323bcd82/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b33323bcd82/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
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
