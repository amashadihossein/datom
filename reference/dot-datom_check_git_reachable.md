# Validate Git Remote Reachability

Checks that the data git remote URL is reachable and that credentials
work. Called at conn-construction time in
[`.datom_get_conn_developer()`](https://amashadihossein.github.io/datom/reference/dot-datom_get_conn_developer.md)
alongside
[`.datom_check_data_reachable()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_data_reachable.md).

## Usage

``` r
.datom_check_git_reachable(conn)
```

## Arguments

- conn:

  A `datom_conn` object. Uses `conn$data_repo_url` and
  `conn$github_pat`.

## Value

Invisible TRUE on success. Warns on network error (offline use ok).

## Details

Failure behaviour:

- No `data_repo_url`: returns invisibly (structural pass, no network
  needed).

- HTTPS, auth failure (HTTP 401/403): hard abort pointing to
  `github_pat`.

- HTTPS, URL not found (HTTP 404): hard abort.

- HTTPS, network error (timeout/DNS): warn-only (offline-tolerant).

- SSH, any error: warn-only (cannot reliably distinguish "no agent" from
  "offline").

- SSH, success: invisible TRUE.
