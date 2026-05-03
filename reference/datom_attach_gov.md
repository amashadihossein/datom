# Attach Governance to an Existing Project

Promotes a no-governance datom project to gov-attached status. After
this call, the project participates in the governance layer: its
dispatch and ref are registered under `projects/{name}/` in the shared
gov repo,
[`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
and friends can discover it, and migration is enabled (Phase 19).

## Usage

``` r
datom_attach_gov(
  conn,
  gov_store,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  create_repo = FALSE,
  repo_name = NULL,
  github_org = NULL,
  private = TRUE
)
```

## Arguments

- conn:

  A `datom_conn` object for a developer role. Must come from a
  no-governance project (i.e. `is.null(conn$gov_root)`). Idempotent
  re-call is supported only for matching `gov_repo_url`.

- gov_store:

  A governance store component
  ([`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
  or
  [`datom_store_local()`](https://amashadihossein.github.io/datom/reference/datom_store_local.md)).
  Where dispatch/ref/migration_history files are mirrored.

- gov_repo_url:

  GitHub remote URL for the shared governance repo. Mutually exclusive
  with `create_repo = TRUE`. Use
  [`datom_init_gov()`](https://amashadihossein.github.io/datom/reference/datom_init_gov.md)
  first if no gov repo exists in your organisation yet.

- gov_local_path:

  Optional override for the local gov clone directory. Defaults to a
  sibling of the data clone, named after the gov repo.

- create_repo:

  If `TRUE`, create a fresh GitHub repo for governance via the API and
  seed it. Mutually exclusive with `gov_repo_url`.

- repo_name:

  GitHub repo name when `create_repo = TRUE`.

- github_org:

  GitHub organisation slug (when `create_repo = TRUE`).

- private:

  Whether the created repo should be private (default `TRUE`). Ignored
  when `create_repo = FALSE`.

## Value

A fresh `datom_conn` with governance fields populated. The input `conn`
becomes stale; rebind to the returned value.

## Details

This is the on-ramp from the lightweight gov-on-demand mode to the full
two-tier model. Typical trigger: promoting from a local/laptop
filesystem backend to a shared S3 bucket.

Once attached, governance cannot be detached. There is no
`datom_detach_gov()`. Calling `datom_attach_gov()` on an
already-attached project is a no-op (idempotent) provided `gov_repo_url`
matches what is already recorded; mismatched URL is a hard error (no
swap).

## Examples

``` r
if (FALSE) { # \dontrun{
# Started with a no-gov project on a laptop
conn <- datom_get_conn(path = ".", store = my_no_gov_store)

# Promote when ready to share with a team
gov_s3 <- datom_store_s3(bucket = "acme-gov", access_key = "...", secret_key = "...")
conn <- datom_attach_gov(
  conn,
  gov_store = gov_s3,
  gov_repo_url = "https://github.com/acme/acme-gov.git"
)
} # }
```
