# Add `commit_sha` to a History on Its Way to Storage

Returns `history` with a `commit_sha` on every entry whose producing
commit is known, and unchanged entries where it is not. Called by each
of the three functions that upload `version_history.json`.

## Usage

``` r
.datom_history_with_commit_shas(
  conn,
  name,
  history,
  version = NULL,
  commit_sha = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

- name:

  Artifact name, of either kind – `version_history.json` is shared.

- history:

  The clone's parsed history, newest-first, as a list of entries.

- version:

  The version this write produced, or `NULL`.

- commit_sha:

  The commit that produced `version`, or `NULL`. A caller that made no
  commit passes `NULL` and every entry is derived.

## Value

`history` with `commit_sha` filled in where it is known.

## Details

Two sources, in this order:

1.  **What storage already holds.** Cheap, and it is the only source for
    a value git can no longer produce.

2.  **Derived from git**, for the entries still missing after step 1 –
    and only then, so a repo whose history is complete pays no git walk.

`version` / `commit_sha` are the write path's shortcut: the caller has
just made the commit that produced that version, so the walk is not
needed for it. They are ignored when storage already records a commit
for that version, since the recorded value is the **first** commit that
introduced it and a later re-upload must not repoint it.

**When step 1 failed rather than found nothing, and something was lost
by it, this says so.** The two states are not interchangeable: nothing
to merge is the ordinary first write, whereas a stored copy that would
not read means the values only storage had are now unknown, and the
upload below replaces the file wholesale. The warning is raised only
when a version actually ends up with no commit – if git could attribute
every one of them, the same values were reconstructed and nothing is
degraded.
