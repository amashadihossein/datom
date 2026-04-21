# Initialize a datom Repository

One-time setup for data developers. Creates folder structure,
initializes git with remote, sets up configuration files, and pushes to
S3.

## Usage

``` r
datom_init_repo(
  path = ".",
  project_name,
  store,
  create_repo = FALSE,
  repo_name = project_name,
  max_file_size_gb = 1000,
  git_ignore = c(".Rprofile", ".Renviron", ".Rhistory", ".Rapp.history", ".Rproj.user/",
    ".DS_Store", "*.csv", "*.tsv", "*.rds", "*.txt", "*.parquet", "*.sas7bdat", ".RData",
    ".RDataTmp", "*.html", "*.png", "*.pdf", ".vscode/", "rsconnect/"),
  .force = FALSE
)
```

## Arguments

- path:

  Path to the project folder. Defaults to current directory.

- project_name:

  Project name, used for S3 namespace and git repo.

- store:

  A `datom_store` object (from
  [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)).
  Must have role `"developer"` (i.e., `github_pat` provided).

- create_repo:

  If `TRUE`, create a GitHub repo via API. Mutually exclusive with
  providing `remote_url` on the store.

- repo_name:

  GitHub repo name when `create_repo = TRUE`. Defaults to
  `project_name`. Useful when the project name (e.g., `"STUDY_001"`)
  isn't a good GitHub repo name.

- max_file_size_gb:

  Maximum file size limit in GB. Default 1000 (1TB).

- git_ignore:

  Character vector of patterns to add to .gitignore.

- .force:

  If `TRUE`, skip the S3 namespace safety check. Use only for
  intentional takeover of an existing S3 namespace. Default `FALSE`.

## Value

Invisible TRUE on success.
