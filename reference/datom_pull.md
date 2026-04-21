# Pull Latest Changes from Remote

Fetches and merges the latest git changes from the remote repository.
This is the recommended entry point at the start of each work session to
ensure the local state is current before syncing or writing tables.

## Usage

``` r
datom_pull(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, a list with:

- `commits_pulled`:

  Integer count of new commits merged.

- `branch`:

  Current branch name.

## Details

Git is the source of truth for all metadata (manifest, dispatch, table
metadata). The manifest and other metadata files live in git and are
pulled along with any other committed changes.

Requires developer role (readers have no git access).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- datom_get_conn("path/to/repo")
datom_pull(conn)
#> ✔ Pulled 2 commits on main.
} # }
```
