# Show Version History

Returns the versions of a table or set, newest first (the 10 most recent
by default): when each was saved, by whom, and with what message. Pass a
value from the `version` column to
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md),
or to
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
for a set, to read that version back.

## Usage

``` r
datom_history(conn, name, n = 10, short_hash = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- n:

  Maximum number of versions to return. Default 10.

- short_hash:

  If TRUE, truncates version and data SHA columns to 8 characters for
  readability. Default FALSE, so the `version` column can be passed
  straight to
  [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md).

## Value

Data frame with columns: version, data_sha, timestamp, author,
commit_message, commit_sha.

## A version is content, not code

A datom version answers one question: *is this the same content and
declared metadata?* Nothing code-derived enters it. So **a change that
alters no content mints no new version**, and this is the behaviour most
often reported as a bug.

Concretely: you refactor your build script, re-run it, and get
byte-identical data. The write is a no-op, `datom_history()` shows the
same version it showed before, and its `commit_sha` still points at the
**earlier** commit – the one that first produced that content, which
does not contain the code you are looking at. That is the recorded value
doing its job. It names a commit that provably produces the version; it
does not name every commit that could.

The commit is deliberately not part of the version. A set exists to be
cited, and if a comment fix minted a new product version, "v47" would
stop meaning anything.

## Where `commit_sha` comes from

It is **derived, never authored** – no argument anywhere sets it. The
copy in your clone does not carry it and cannot: `version_history.json`
is committed *inside* the commit that would name it. Only the copy in
storage has it, and it is there for readers who have no clone. With a
clone, `git log -p {name}/set.json` answers the same question directly.

`NA` means the value is not recorded and could not be worked out from
this repo's git history – a shallow clone or rewritten history,
typically, or a version written by a datom too old to record it.

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

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  print(datom_history(conn, "dm"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a7674c4b5af/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a7674c4b5af/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#>                                                            version
#> 1 b5cbba4501f518d7bbe1eaf4f0c236895b12d63677b9f75b9388b715055c832e
#>                                                           data_sha
#> 1 71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538
#>              timestamp                author commit_message
#> 1 2026-10-03T21:06:15Z datom <datom@noreply>      Update dm
#>                                 commit_sha
#> 1 8599ebdbc359d30d014e2892e3f2ddfd421812c1
```
