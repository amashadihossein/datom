# Check Local Branch is Current with Remote

Fetches from the remote and compares local HEAD SHA against the upstream
HEAD SHA. If the local branch is behind, aborts with a clear message
telling the developer to pull first.

## Usage

``` r
.datom_check_git_current(path, pat = NULL)
```

## Arguments

- path:

  Repository path.

- pat:

  GitHub personal access token. Passed to
  [`.datom_git_credentials()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_credentials.md).
  NULL means unauthenticated.

## Value

Invisible `TRUE` if the local branch is up to date.

## Details

Does NOT auto-pull - lets the developer decide how to resolve.

If the fetch fails (offline, unreachable remote), this warns and returns
`TRUE` without comparing anything: the cached remote-tracking refs may
be arbitrarily stale, so acting on them would abort an offline developer
for being behind a remote they cannot reach. The backstop is
[`.datom_git_push()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_push.md),
which pulls and aborts if the push is rejected, so a write cannot land
on storage from a stale base.
