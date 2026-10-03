# Drop Members from a Set

Removes the members you select and returns the set without them.
**Nothing is written**: the object comes back edited, and the set is
stored only when you pass the result to
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md).

## Usage

``` r
datom_remove_members(x, member = NULL, tags = NULL, version = NULL)
```

## Arguments

- x:

  A `datom_set`, from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  or
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md).

- member:

  The member to drop, as its name, a member record, or a link. Optional
  only when `tags` or `version` selects on its own.

- tags:

  Optional named list of labels selecting members, e.g.
  `list(status = "draft")`. A member matches when it carries every label
  listed.

- version:

  Optional version, or a prefix of one, selecting the members pinned at
  it.

## Value

`x` without the selected members, its `version` and `data_sha` emptied
because they described a payload it no longer holds, and what was
dropped appended to its `datom_edits` attribute – which
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
turns into the commit message.

## Details

It exists because the hand-rolled version is silently wrong. Filtering a
member list by name drops **every** version of that name, so a set
holding a live table beside a deliberately frozen baseline loses both;
removing by position removes a different member the day somebody adds
one.

## Why there is no connection argument

Not an oversight. Removing a member only has to **find** a pointer the
set already holds, while adding or repointing one has to **resolve** it
– read the artifact's metadata, confirm its kind, record the project
that wrote it. So this verb does no IO at all and needs no credentials,
which is also why it is the one edit verb that works on a set read
through a storage-only connection with no clone.

## Selecting what to drop

A selection is **required**. `datom_remove_members(x)` would mean
removing every member, which the writer refuses anyway, so it aborts
instead of building a payload the write then rejects. The safe default
for a destructive verb is nothing – the opposite of
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md),
where the safe default is everything because a refresh is idempotent.

Select by name, by a member record, or by a link, and narrow with `tags`
or `version`; `tags` or `version` on their own select every member they
match, so `tags = list(status = "draft")` drops the labelled ones.

Three things it refuses rather than doing quietly:

|  |  |
|----|----|
| What you asked for | Why it stops |
| a name matching more than one member | that is the silently-wrong spelling this verb replaces – it would drop a frozen baseline along with the live table |
| a selection matching nothing | it is a typo, and [`Filter()`](https://rdrr.io/r/base/funprog.html) reports success for it |
| every member | a set with no members cannot be written, and the refusal belongs on the line that emptied it |

**An ambiguous name refuses here while
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
skips it**, and the asymmetry is the consequence rather than a taste:
skipping a repoint leaves a valid pinned version behind, while skipping
a removal silently does nothing at all.

## See also

[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
to repoint members instead,
[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
to see what a set holds,
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
to store the result.

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
  # A product repo declares itself as one and names the single set it owns.
  datom_init_repo(file.path(tmp, "repo"), "example_project", store,
                  mode = "product", set = "example_product")

  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  datom_write(conn, data = datom_example_data("lb"), name = "lb")
  datom_write_set(conn, list(
    datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
                 tags = list(type = "input")),
    datom_member(conn, "lb", datom_history(conn, "lb")$version[1],
                 tags = list(status = "draft"))
  ))

  x <- datom_get_set(conn, "example_product")

  # By label, which is the selection that does not depend on position.
  x <- datom_remove_members(x, tags = list(status = "draft"))
  print(datom_list_members(x))

  datom_write_set(conn, x)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a767515f97/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a767515f97/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote "lb" (full): "b2937781"
#> ✔ Wrote set "example_product" (2 members): "ddaf905c"
#> ✔ Dropped 1 member; 1 remains.
#> project example_project:
#>   lb  dropped, was b2937781
#> ℹ Nothing has been written. Write the set with `datom_write_set(conn, x)`.
#>   name         project
#> 1   dm example_project
#>                                                            version  kind  key
#> 1 b5cbba4501f518d7bbe1eaf4f0c236895b12d63677b9f75b9388b715055c832e table type
#>   value
#> 1 input
#> ✔ Wrote set "example_product" (1 member): "5c776f28"
```
