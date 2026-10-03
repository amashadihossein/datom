# Push the Data Repo to Its Remote

Pushes the current branch of the data repo clone, through the same path
datom's own writes use – so it inherits pull-before-push, upstream
tracking, and the on-a-branch guard.

## Usage

``` r
datom_repo_push(conn)
```

## Arguments

- conn:

  A `datom_conn` object with `role = "developer"` and a local repo path
  (`conn$path`).

## Value

Invisibly `TRUE`.

## Details

**Convergent, not imperative.** Nothing to push is an informational
no-op rather than an error, so calling it twice is safe and "make sure
the remote has everything" is a legal standalone operation.

This is the other half of
[`datom_repo_commit()`](https://amashadihossein.github.io/datom/reference/datom_repo_commit.md)`(push = FALSE)`.
Without it, "push what I already committed" would only be expressible as
*another commit attempt* – and since `paths = NULL` is add-all, a caller
who merely wanted to push would risk committing whatever work in
progress the tree happened to hold.

## See also

[`datom_repo_commit()`](https://amashadihossein.github.io/datom/reference/datom_repo_commit.md),
[`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md)

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

  # Commit now, push later.
  writeLines("notes", file.path(tmp, "repo", "NOTES.md"))
  datom_repo_commit(conn, "Add notes", push = FALSE)
  datom_repo_push(conn)

  # Convergent: a second call has nothing to do and says so.
  datom_repo_push(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a761a7d75b3/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a761a7d75b3/repo
#> ✔ Committed "597111a" on "master": Add notes
#> ✔ Pushed "master" to the data remote.
#> ℹ Nothing to push -- "master" matches the remote.
```
