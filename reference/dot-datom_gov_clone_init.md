# Initialise Gov Clone (Clone If Missing, Reuse If Present)

Ensures a valid gov clone exists at `gov_local_path`:

## Usage

``` r
.datom_gov_clone_init(gov_repo_url, gov_local_path)
```

## Arguments

- gov_repo_url:

  GitHub URL of the governance repo (e.g.,
  `"https://github.com/org/acme-gov.git"`).

- gov_local_path:

  Absolute path where the gov clone should live.

## Value

Invisible `gov_local_path` (character).

## Details

- If the path does **not** exist: clones `gov_repo_url` into
  `gov_local_path`.

- If the path exists and is a git repo with matching remote URL: reuses
  it silently (idempotent).

- If the path exists with a **different** remote URL: hard abort
  (collision).

- If the path exists but is **not** a git repo: hard abort.
