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
  providing `data_repo_url` on the store.

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

## Details

Initializes the **data repository only**. The project is left as a solo
project: `project.yaml` is the location authority, no `governance.json`
/ `dispatch.json` / `ref.json` is written, and `project.yaml` omits the
`storage.governance` and `repos.governance` blocks. A governance store
component on `store`, if present, is ignored here. Governance is
attached later via the governance layer (`gov_attach()`).

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage.
if (requireNamespace("git2r", quietly = TRUE)) {
  tmp <- tempfile("datom-example-")
  remote <- file.path(tmp, "remote.git")
  dir.create(remote, recursive = TRUE)
  git2r::init(remote, bare = TRUE)

  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token", # role selector; a local remote needs none
    data_repo_url = remote,
    validate = FALSE
  )

  datom_init_repo(
    path = file.path(tmp, "repo"),
    project_name = "example_project",
    store = store
  )
  print(list.files(file.path(tmp, "repo"), all.files = TRUE, no.. = TRUE))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3321439a04/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3321439a04/repo
#> [1] ".datom"      ".git"        ".gitignore"  "README.md"   "input_files"
```
