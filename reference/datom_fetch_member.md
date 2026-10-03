# Get the Data Behind One Member of a Set

Returns what one
[member](https://amashadihossein.github.io/datom/reference/datom-package.md)
of a set points at, at the exact version the set records: a data frame
for a table, another set for a set. Name the member, as in
`datom_fetch_member(conn, x, "dm")`, and pass a connection to that
member's own project.

## Usage

``` r
datom_fetch_member(conn, x, member, tags = NULL, version = NULL)
```

## Arguments

- conn:

  A `datom_conn` from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md),
  scoped to the **member's** project.

- x:

  A `datom_set` from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

- member:

  The member to fetch: its name, a member record, or a link.

- tags:

  Optional named list of labels narrowing an ambiguous name, e.g.
  `list(release = "baseline")`. A member matches when it carries every
  label listed.

- version:

  Optional version, or a prefix of one, narrowing an ambiguous name.

## Value

Whatever the member points at: a data frame for a `table` member, a
`datom_set` for a `set` member.

## Details

`x$members[[i]]$fetch(conn)` does the same thing.

This is kind dispatch at the **member** level, which is the only level
it belongs at. Iterating members, a caller cannot know each one's kind
in advance; at the top level they named one artifact they chose, which
is why
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
and
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
stay separate verbs.

## Naming a member

`member` accepts the three shapes a caller actually holds, so a console
call and a loop use one verb:

|  |  |
|----|----|
| What you pass | Where it comes from |
| a name | you read the set and know what you want |
| a member record | [`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md), or `x$members[[i]]` |
| a link | `x$members[[i]]$fetch`, or a leaf of [`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md) |

**A name is not a key.** The same artifact at two versions is a legal
pair of members – a current table beside a locked baseline, say – so an
ambiguous name aborts and lists the candidates rather than answering
with the first. Narrow with `tags`, which is the navigation axis, or pin
one exactly with `version`. Both narrow a name only; supplied beside a
record or a link they are refused rather than quietly ignored.

## Which connection to pass

The one for the **member's** project. Access in datom is per project and
not conjunctive: reading a set needs the set's project only, and
resolving a member is a separate, deliberate step. Same-project members
resolve through the connection you already have.

A member's project is **not** checked against the connection's before
the fetch, and that is deliberate: a connection's project name is a
label the caller supplied and nothing compares it against the repo, so a
mismatch is ordinary rather than wrong. When a fetch fails and the two
names differ, the error says which project the member's own writer
recorded, so the ordinary cause is named instead of presenting as a
missing object.

## See also

[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
to see every member and its labels,
[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
for a navigable view.

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

  members <- list(
    datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
                 tags = list(type = "input")),
    datom_member(conn, "lb", datom_history(conn, "lb")$version[1],
                 tags = list(type = "output", domain = c("safety", "labs")))
  )
  datom_write_set(conn, members)

  x <- datom_get_set(conn, "example_product")

  # By name, and the same fetch by the link the read already put on it.
  print(head(datom_fetch_member(conn, x, "dm")))
  print(head(datom_fetch_member(conn, x, x$members[[1]]$fetch)))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd7163de64/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd7163de64/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote "lb" (full): "b2937781"
#> ✔ Wrote set "example_product" (2 members): "ca1deaa7"
#> # A tibble: 6 × 12
#>   STUDYID   DOMAIN USUBJID SUBJID   AGE AGEU  SEX   RACE  ETHNIC COUNTRY RFSTDTC
#>   <chr>     <chr>  <chr>    <int> <int> <chr> <chr> <chr> <chr>  <chr>   <chr>  
#> 1 STUDY-001 DM     STUDY-…      1    71 YEARS F     BLAC… NOT H… USA     2026-0…
#> 2 STUDY-001 DM     STUDY-…      2    27 YEARS M     ASIAN HISPA… CAN     2026-0…
#> 3 STUDY-001 DM     STUDY-…      3    35 YEARS M     OTHER HISPA… CAN     2026-0…
#> 4 STUDY-001 DM     STUDY-…      4    68 YEARS M     WHITE NOT H… USA     2026-0…
#> 5 STUDY-001 DM     STUDY-…      5    43 YEARS M     WHITE NOT H… USA     2026-0…
#> 6 STUDY-001 DM     STUDY-…      6    60 YEARS F     ASIAN NOT H… CAN     2026-0…
#> # ℹ 1 more variable: DMDTC <chr>
#> # A tibble: 6 × 12
#>   STUDYID   DOMAIN USUBJID SUBJID   AGE AGEU  SEX   RACE  ETHNIC COUNTRY RFSTDTC
#>   <chr>     <chr>  <chr>    <int> <int> <chr> <chr> <chr> <chr>  <chr>   <chr>  
#> 1 STUDY-001 DM     STUDY-…      1    71 YEARS F     BLAC… NOT H… USA     2026-0…
#> 2 STUDY-001 DM     STUDY-…      2    27 YEARS M     ASIAN HISPA… CAN     2026-0…
#> 3 STUDY-001 DM     STUDY-…      3    35 YEARS M     OTHER HISPA… CAN     2026-0…
#> 4 STUDY-001 DM     STUDY-…      4    68 YEARS M     WHITE NOT H… USA     2026-0…
#> 5 STUDY-001 DM     STUDY-…      5    43 YEARS M     WHITE NOT H… USA     2026-0…
#> 6 STUDY-001 DM     STUDY-…      6    60 YEARS F     ASIAN NOT H… CAN     2026-0…
#> # ℹ 1 more variable: DMDTC <chr>
```
