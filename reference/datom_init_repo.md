# Create a New datom Project

Run once to start a new
[project](https://amashadihossein.github.io/datom/reference/datom-package.md).
It creates the project folder (including an `input_files/` folder for
files you want to bring in), sets up git, pushes a first commit to
GitHub – creating the GitHub repository if `create_repo = TRUE` – and
records the new, empty project in storage. The store must carry a GitHub
token; to join a project that already exists, use
[`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md)
instead.

## Usage

``` r
datom_init_repo(
  path = ".",
  project_name,
  store,
  create_repo = FALSE,
  repo_name = project_name,
  max_file_size_gb = 1000,
  mode = NULL,
  set = NULL,
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

- mode:

  Project mode, or `NULL` (the default) for an ordinary data repo that
  onboards source files. The only other accepted value is `"product"`,
  which declares a repo that **builds** its artifacts instead: it holds
  one set, writes derived tables, and refuses the file-import path.
  Absent is not a missing value here – it *is* "ordinary data repo",
  which is why nothing is written to `project.yaml` unless you ask for a
  product.

- set:

  Name of the set a `mode = "product"` repo owns. Required with
  `mode = "product"` and refused without it: one repo holds one set, and
  a product repo that names none passes the mode check and then fails
  every set write, which is a repo that looks initialised and is not.

- git_ignore:

  Character vector of patterns to add to .gitignore.

- .force:

  If `TRUE`, skip the storage namespace safety check. Use only for
  intentional takeover of an existing namespace. Default `FALSE`. Two
  cases it does not cover, both refusals that stand:

  - a namespace that cannot be **reached**, because the manifest upload
    later in this function needs the same storage, so skipping the check
    buys nothing;

  - a `mode = "product"` repo, whose namespace check has no override at
    all – passing `.force` there is an error rather than a no-op, since
    a dropped override leaves you believing you took a namespace over
    when you did not.

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
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a7650202ca9/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a7650202ca9/repo
#> [1] ".datom"      ".git"        ".gitignore"  "README.md"   "input_files"
```
