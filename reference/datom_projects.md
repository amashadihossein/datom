# List Projects Registered in the Governance Repo

Returns a data frame with one row per project registered in the shared
governance repo. Useful for managers and auditors who need to see the
portfolio without having to clone every data repo.

## Usage

``` r
datom_projects(x)
```

## Arguments

- x:

  A `datom_conn` or a `datom_store` with a governance component.

## Value

A data frame, sorted by `name`, with columns: `name` (character),
`data_backend` (character), `data_root` (character), `data_prefix`
(character; NA when absent), `registered_at` (character ISO8601 from
clone mtime; NA on storage path).

## Details

Accepts either a `datom_conn` (typically the developer's existing
connection – reads the local gov clone) or a `datom_store` (lets a
caller enumerate the portfolio before connecting to any specific
project).

Read path:

- If a local gov clone is available (developer or any caller whose
  `gov_local_path` exists on disk), `projects/` is listed from disk and
  each `ref.json` is read locally. No network calls.

- Otherwise the gov storage client is used: `projects/` is listed and
  each `projects/{name}/ref.json` is fetched.

Corrupt registry entries (missing `ref.json`, unreadable JSON) emit a
warning and are skipped – one bad project does not take down the
listing.

## Examples

``` r
# A governance store backed by a local directory. Projects are registered
# into it by the companion governance package (datomanager), so a freshly
# created governance store lists an empty portfolio.
tmp <- tempfile("datom-example-")
gov <- datom_store_local(file.path(tmp, "gov-storage"))
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33655fd357/gov-storage.

store <- datom_store(
  governance   = gov,
  data         = datom_store_local(file.path(tmp, "storage")),
  gov_repo_url = "https://github.com/example/acme-gov"
)
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33655fd357/storage.

datom_projects(store)
#> [1] name          data_backend  data_root     data_prefix   registered_at
#> <0 rows> (or 0-length row.names)

unlink(tmp, recursive = TRUE)
```
