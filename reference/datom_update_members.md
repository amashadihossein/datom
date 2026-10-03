# Repoint a Set's Members at Newer Versions

Moves members of a set forward to the versions that are current now, and
returns the set with those pointers changed. **Nothing is written**: the
report you see is the dry run, and the set is stored only when you pass
the result to
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md).

## Usage

``` r
datom_update_members(
  x,
  conn,
  member = NULL,
  tags = NULL,
  version_from = NULL,
  version_to = NULL
)
```

## Arguments

- x:

  A `datom_set`, from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  or
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md).

- conn:

  A `datom_conn` from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md),
  or a list of them – one per project the selected members belong to.

- member:

  Optional: the member to repoint, as its name, a member record, or a
  link. `NULL` (the default) selects every member.

- tags:

  Optional named list of labels narrowing the selection, e.g.
  `list(type = "input")`. A member matches when it carries every label
  listed.

- version_from:

  Optional version, or a prefix of one, narrowing the selection to the
  member pinned at it.

- version_to:

  Optional exact version to move to. `NULL` (the default) means whatever
  that artifact's project reports as current. Requires the selection to
  resolve to a single member.

## Value

`x` with the matching members repointed, and what changed appended to
its `datom_edits` attribute.

## Details

This is the operation a product needs when its inputs move on – a
hundred members of which thirty upstream tables have advanced. Doing it
by hand is list surgery on what
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
returned, and two of the obvious spellings are silently wrong: filtering
members by name drops *every* version of that name, and rebuilding a
pointer from its name plus a new version drops that member's labels.

## Which connection to pass

One per project the set spans, since access in datom is per project. A
set whose members all live in the project that owns it needs only that
one connection; a product drawing on three studies needs three, in a
list.

A set's projects can be listed **offline, with no connection at all**:

    unique(datom_list_members(x)$project)

## Which members move

With no `member`, **every** member – refreshing everything is the common
case and rerunning it changes nothing. Otherwise select one the way
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
does: by name, by a member record, or by a link. `tags` and
`version_from` narrow either a name or the sweep, so
`tags = list(release = "live")` repoints the labelled members and leaves
the rest pinned.

A name that matches more than one member **aborts**, because the request
cannot be honoured as typed; a *sweep* that meets the same pair skips it
and says so, because refusing a whole refresh over one frozen baseline
would make the first update on such a set an error.

## Which version each member moves to

`version_to` omitted, each selected member moves to the version its own
project reports as current, and every move is reported before anything
is written. That is the one place datom infers "newest", and the reason
it is allowed here is in the verb's name: a pointer *constructor*
requires an explicit version
([`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
refuses to guess), while a verb whose whole meaning is *move this
forward* states the time-dependence up front and then says what it
picked. What the set records is still an exact version, so a script that
later reads that set is as reproducible as ever.

`version_to` supplied, the selected member moves to exactly that version
– a rollback to a known-good, or a deliberate step to something that is
not the newest. It requires the selection to resolve to one member,
because one explicit version across several artifacts is not a meaning.
It is also what makes this verb better than removing and re-adding a
member: **the labels come with it**, where re-adding makes you retype
them.

## What it declines to do, and how

|  |  |
|----|----|
| Situation | Response |
| a member's project has no supplied connection | the whole call is refused, naming that project |
| a member's artifact no longer appears in its project | reported, and its pin is left alone |
| two members share a name and a project | both skipped and reported |

The first refuses because whether those members moved is unknowable, and
reporting them as unchanged would state something nothing checked. The
second does not, because the answer *is* known: the pinned version is
immutable and still reads, so the set stays writable.

## What comes back

The set it was handed, with matching members repointed and each moved
member's labels byte-identical to what they were.

When something moved, a `datom_set`'s `version` and `data_sha` are
emptied: they described the payload it was read as, and that is no
longer what the object holds. When nothing moved they are left alone,
because the object still describes exactly that stored version.

The returned object also carries a log of what changed, which
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
uses for the commit message when you pass no `message` of your own – so
`git log` names what moved instead of saying `Update {name}`.
[`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md)
adds to the same log, so editing both ways before you write produces one
message describing both. Passing `x$members` rather than `x` to the
write loses that and nothing else.

## See also

[`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md)
to drop members instead,
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
to store the result,
[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
to see what a set holds,
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
to build a pointer from scratch.

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

  dm <- datom_example_data("dm")
  datom_write(conn, data = dm, name = "dm")
  datom_write_set(conn, list(
    datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
                 tags = list(type = "input"))
  ))

  # The table moves on, so the set now cites an older version of it.
  datom_write(conn, data = dm[-1, , drop = FALSE], name = "dm")

  x <- datom_get_set(conn, "example_product")
  x <- datom_update_members(x, conn)

  # The label came with it, and nothing is stored until the write.
  print(datom_list_members(x))
  datom_write_set(conn, x)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd15f42e8a/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd15f42e8a/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote set "example_product" (1 member): "5c776f28"
#> ✔ Wrote "dm" (full): "e4d6537b"
#> ✔ Repointed 1 member, of 1 selected.
#> project example_project:
#>   dm  b5cbba45 -> e4d6537b
#> ℹ Nothing has been written. Write the set with `datom_write_set(conn, x)`.
#>   name         project
#> 1   dm example_project
#>                                                            version  kind  key
#> 1 e4d6537b918c1b413865d50e7dd4745fd28012f3395ab507f79cb15b5eb0482a table type
#>   value
#> 1 input
#> ✔ Wrote set "example_product" (1 member): "06070474"
```
