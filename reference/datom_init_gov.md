# Initialize a Governance Repository

One-time setup to create a shared governance repository that serves many
data projects in an organisation. Creates the GitHub repo (optionally),
seeds the skeleton (`README.md` + `projects/.gitkeep`), commits, and
pushes.

## Usage

``` r
datom_init_gov(
  gov_store,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  create_repo = FALSE,
  repo_name = NULL,
  github_pat = NULL,
  github_org = NULL,
  private = TRUE
)
```

## Arguments

- gov_store:

  A governance store component (`datom_store_s3` or
  `datom_store_local`). This is the storage backend that individual data
  projects will use to register their dispatch and ref files.

- gov_repo_url:

  GitHub URL of the governance repo. Mutually exclusive with
  `create_repo = TRUE`.

- gov_local_path:

  Local path for the governance clone. When `NULL`, derived from the
  basename of `gov_repo_url` (`.git` suffix stripped) in the current
  directory. When `create_repo = TRUE` and no URL is known yet, set this
  explicitly or let it default to `repo_name`.

- create_repo:

  If `TRUE`, create a GitHub repo via the API and use the returned URL.
  Mutually exclusive with providing `gov_repo_url`.

- repo_name:

  GitHub repo name when `create_repo = TRUE`. Required when
  `create_repo = TRUE`.

- github_pat:

  GitHub personal access token. Required when `create_repo = TRUE`.

- github_org:

  GitHub organisation slug. `NULL` creates the repo under the
  authenticated user account.

- private:

  Whether the created repo should be private. Default `TRUE`. Ignored
  when `create_repo = FALSE`.

## Value

Invisible `gov_repo_url` on success.

## Details

Idempotent: if `gov_local_path` already contains an initialised
governance clone (i.e. `projects/.gitkeep` exists), the function returns
silently without making any changes.
