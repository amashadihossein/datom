# Commit Content in the Data Repo

Commits changes in the data repo clone and, by default, pushes them.
This is datom's **sanctioned git-mutation surface** for downstream
packages: a build or deployment package commits its own content – code,
`renv.lock`, framework state – through this verb rather than importing
`git2r` and writing to the data repo behind datom's back.

## Usage

``` r
datom_repo_commit(conn, message, paths = NULL, push = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object with `role = "developer"` and a local repo path
  (`conn$path`).

- message:

  Commit message. Required, and used only when a commit is actually
  created.

- paths:

  `NULL` (default) to stage everything `git add .` would stage, or a
  character vector of repo-relative paths to stage exactly those.
  Explicit paths must exist: to record a deletion, use `paths = NULL`.

- push:

  Push after committing (default `TRUE`), through the same path datom's
  own writes use – so it inherits pull-before-push and upstream
  tracking. `push = FALSE` commits only;
  [`datom_repo_push()`](https://amashadihossein.github.io/datom/reference/datom_repo_push.md)
  is the other half of that split.

## Value

Invisibly, the commit SHA; `invisible(NULL)` when no commit was created
(whether or not a push happened).

## Details

**`paths = NULL` means what `git add .` means.** It stages tracked
modifications, deletions and untracked files, minus anything
`.gitignore` excludes. That is the correct semantic for a human-invoked
moment, and it is deliberately the opposite of what datom's own writes
do: a commit created inside
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
stages an explicit file list, because it fires at a moment datom chose
and must never sweep up work in progress.

One consequence of add-all worth knowing rather than discovering: if an
earlier datom write failed after writing local metadata but before
committing, those datom files are dirty and this verb will stage them.
That is left intentional – silently excluding datom's own paths would
make the argument lie about its contract, and the state is exactly what
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
reports and `datom_validate(fix = TRUE)` repairs. It also moves git
*ahead* of storage, which is the safe direction.

**Commit is idempotent, push is convergent, and neither implies the
other.** A clean tree produces no commit and is not an error, so "commit
everything" can be called twice. With `push = TRUE` the push still runs
when the branch is ahead of the remote, even though no commit was
created – otherwise one failed push would leave the remote behind
forever, since every later call finds a clean tree and returns early.

## See also

[`datom_repo_push()`](https://amashadihossein.github.io/datom/reference/datom_repo_push.md),
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)

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
  datom_init_repo(file.path(tmp, "repo"), "example_project", store)
  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  # Content datom does not own, committed through datom.
  dir.create(file.path(tmp, "repo", "R"))
  writeLines("build <- function() NULL", file.path(tmp, "repo", "R", "build.R"))
  datom_repo_commit(conn, "Add build script")

  # Idempotent: a clean tree is a no-op, not an error.
  datom_repo_commit(conn, "Nothing to do")

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd415a50ba/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd415a50ba/repo
#> ✔ Committed "c35507f" on "master": Add build script
#> ℹ Nothing to commit -- no staged changes.
#> ℹ Remote already has every commit on "master".
```
