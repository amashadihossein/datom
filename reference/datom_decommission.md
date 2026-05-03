# Decommission a datom Project

Permanently removes all storage, git, and governance artefacts for a
project. This is irreversible – data is deleted from storage and the
project is unregistered from the shared governance repo.

## Usage

``` r
datom_decommission(conn, confirm = NULL)
```

## Arguments

- conn:

  A `datom_conn` object (developer role required).

- confirm:

  Character string. Must equal `conn$project_name` exactly. No
  interactive prompts – this must be supplied explicitly to prevent
  accidental decommissioning in scripts.

## Value

Invisible `TRUE` on success.

## Details

Teardown order (each step is warn-and-continue on failure so the
remaining steps still run):

1.  Delete all objects under the data storage namespace.

2.  Delete the data GitHub repo via the GitHub REST API. Requires
    `GITHUB_PAT` with the `delete_repo` scope; skipped with a warning if
    the PAT is unavailable or the local clone has no GitHub remote.

3.  Remove the local data clone directory (`conn$path`).

4.  Unregister the project from the governance repo (git commit + push).
    Skipped when the project has no governance attached
    (`is.null(conn$gov_root)`); also skipped with a warning when gov is
    attached but `conn$gov_local_path` is `NULL`.

5.  Delete the project folder from governance storage
    (`projects/{project_name}/`). Skipped when the project has no
    governance attached.
