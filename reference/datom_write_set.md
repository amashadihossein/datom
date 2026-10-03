# Save a Set as a New Version

Saves a
[set](https://amashadihossein.github.io/datom/reference/datom-package.md):
a named list of exact versions of tables (or other sets), plus labels,
that you can cite with one version string. A set holds no data, so
saving one copies nothing. Saving the same members and labels again
creates no new version.

## Usage

``` r
datom_write_set(
  conn,
  members,
  tags = NULL,
  name = NULL,
  message = NULL,
  include_paths = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md),
  scoped to the product repo (developer role).

- members:

  A list of member records from
  [`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md),
  each pinning one artifact version and optionally carrying its own tags
  – or a `datom_set`, from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  or
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md),
  edited or not. Hand-assembled lists are refused.

- tags:

  Optional named list of set-level text labels – facts about the
  collection itself, such as a description. Same grammar as a member's
  tags: a value is one string or several, text only.

- name:

  The set's name. Defaults to the `set:` field in `.datom/project.yaml`;
  when supplied it must equal it.

- message:

  Optional commit message. Omitted, it is `Update {name}` – except for a
  set edited with
  [`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md),
  [`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
  or
  [`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md),
  where the default names the members added, moved or dropped, with
  their versions. So a set assembled in steps gets
  `Update {name}: add N members` on its first write. Pass `x` rather
  than `x$members` to get that, since the change list travels with the
  object.

- include_paths:

  Optional character vector of repo-relative paths – your own code,
  `renv.lock`, build state – staged into the **same commit** as the set.
  Never mirrored to storage: the storage namespace holds datom artifacts
  and nothing else. See the section below.

## Value

Invisibly, a list with `name`, `data_sha`, `metadata_sha` (the version),
`member_count` (the count after normalisation), `action` (`"none"` or
`"full"`) and `commit_sha`.

## Details

One repo holds one set. The repo declares which, in
`.datom/project.yaml`:

    mode: product
    set: study001-adam

Both are checked before anything is hashed or written, so a repo that
has not declared itself a product repo is refused with nothing left
behind.

## What a set carries, and what it does not

User metadata is **tags**, and there is no `metadata =` parameter: a
description is a tag, and a second channel for the same thing would be
two places to look. There is no view or navigation configuration either
– a folder-like hierarchy is a projection a consumer computes over tags,
and any number of them cost nothing precisely because none is stored.

A set records **no** `parents` and **no** `source_lineage`. Members are
references, not derivation: lineage flows through tables, and the set is
how you *found* a table rather than how data reached it.

## Versions, and what moves one

The version covers the **whole payload**, members and tags alike. So
editing a tag or a description mints a new version, which is intended: a
set exists to be citable, and "same citation, different labels" would be
a lie to whoever cited it. What does **not** mint a version is a purely
syntactic edit – reordering tag values or members, repeating a label, or
writing a single label as a one-element array. Those are normalised on
the way in, so re-writing an identical payload is a no-op.

**Your code does not move a version either, even though it travels in
the same commit** (see `include_paths` below). Refactor your build
script, re-run it, get the same members and tags, and nothing is minted:
the write is the usual no-op.
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
then shows the version it showed before, with a `commit_sha` pointing at
the commit that **first** produced that payload – a commit that does not
contain the code you just wrote. That is the recorded value doing its
job rather than going stale; see
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
for why the commit is deliberately not part of the version.

## Where the payload lives

Two copies, at two deliberately different addresses. Git holds
`{name}/set.json` at one stable path, modified in place, so git carries
the history and `git diff` between two versions shows which members
changed. Storage holds the same bytes content-addressed at
`{name}/{data_sha}.json`, so a reader with no clone can fetch an exact
version. Any past version is still reconstructible from the clone alone
with `git show <commit>:{name}/set.json`.

## Carrying your code and environment into the same commit

`include_paths` stages paths you name into the **one** commit that
carries the payload and its metadata. So checking out a set version's
commit yields the data pointers, the logic that produced them **and**
the environment they ran in – one clone, one checkout, the whole
product. The joint version is **structural**: nothing records a link
between the set and your files, because the commit *is* the link.

    datom_write_set(conn, members,
                    include_paths = c("R", "dp", "renv.lock"))

Four refusals, all of them before anything is hashed or written, so a
refusal leaves nothing behind: a path that does not exist, a path
outside the clone, a path datom owns (`.datom/`, the set, any artifact
directory), and a path `.gitignore` excludes. The last one matters
because git stages an ignored path silently and without complaint, which
would leave the set version claiming a commit that omits exactly the
file you named. Refusals win over the no-op below, since they are
settled before change detection runs.

**An unchanged set is still a no-op, however dirty those paths are.** No
commit, no version, and a message pointing at
[`datom_repo_commit()`](https://amashadihossein.github.io/datom/reference/datom_repo_commit.md),
which is the verb for committing your own content at a moment you chose.
A data write that quietly committed work in progress is the thing
datom's explicit file lists exist to prevent, and idempotency must not
become a side door into it.

## Outputs must be built from the inputs the set pins

A table written with `parents` records which versions it was derived
from. When a set lists such a table and also lists one of its parents,
the write checks they agree: if the set pins the parent at a different
version from the one the table was built from, and not at that version
too, the write stops and names the member, the parent and both versions.
Nothing is written. Re-derive the output with `datom_parent(x = )`,
which takes the versions from the set, or move the input with
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md).

Only tables in the set's own project are checked, and a parent the set
does not list is not checked. A set carrying one table at two versions
(a live copy beside a frozen baseline) passes as long as one of them is
the version used. Each such member's recorded metadata is read from
storage; if it cannot be read – a version that does not exist, or
storage that cannot be reached – the write stops too.

## Editing a set that already exists

Read it, change it, write it back. `members` accepts a `datom_set` from
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
directly, so the loop needs no unpacking:

    x <- datom_get_set(conn, "study001-adam")
    x$members <- c(x$members, list(datom_member(conn, "lb", v)))
    datom_write_set(conn, x)

The set's own `tags` come along with it unless `tags` is supplied, so a
read-append-write cannot silently drop the description. Passing
`x$members` instead works too, and there `tags` is yours to carry.

A set built in steps with
[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
and
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
is written the same way, and pipes into the write:

    x |> datom_write_set(conn = conn)

## A set is written into its own repo

A `datom_set` records its name and the project it belongs to. Both are
checked before anything is hashed or written: a set named for another
repo's declared set, or belonging to another project, stops the write.
Writing it anyway would move it into this repo's project without saying
so – the name check alone would miss that, since two product repos may
declare the same set name. A `name` argument that disagrees with the
set's own name stops it too. A plain list of member records carries
neither, so neither is checked.

## See also

[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
to declare a member,
[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
to build a set a member at a time,
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
for tables.

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

  # A set points at versions that already exist.
  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  datom_write(conn, data = datom_example_data("lb"), name = "lb")

  members <- list(
    datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
                 tags = list(type = "input")),
    datom_member(conn, "lb", datom_history(conn, "lb")$version[1],
                 tags = list(type = "output", domain = c("safety", "labs")))
  )

  datom_write_set(
    conn, members,
    tags = list(description = "Example product for STUDY-001")
  )

  print(datom_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd4ef0dc2f/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd4ef0dc2f/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote "lb" (full): "b2937781"
#> ✔ Wrote set "example_product" (2 members): "23342acf"
#>              name  kind current_version current_data_sha         last_updated
#> 1              dm table        b5cbba45         71a93ffa 2026-10-03T18:04:42Z
#> 2              lb table        b2937781         87f206ab 2026-10-03T18:04:42Z
#> 3 example_product   set        23342acf         3fee45a0 2026-10-03T18:04:42Z
```
