# Check Whether an S3 Namespace is Free

Checks for the existence of `.metadata/manifest.json` in the target S3
namespace. If found, the namespace is occupied by an existing datom
project. Returns `TRUE` if the namespace is free. Aborts with an
actionable error if occupied, showing the existing project name when
possible.

## Usage

``` r
.datom_check_namespace_free(conn)
```

## Arguments

- conn:

  A `datom_conn` object (typically a temporary conn built by
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  before the repo is fully initialised).

## Value

Invisible `TRUE` if the namespace is free.

## Details

Uses `head_object` first (cheap) and only reads the manifest (via
`get_object`) when the namespace is occupied, to extract the project
name for the error message.
