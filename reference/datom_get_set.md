# Read a datom Set

Returns a
[set](https://amashadihossein.github.io/datom/reference/datom-package.md)'s
members and labels, at its current version or a past one. It reads no
table data: to get the data behind a member, use
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md).
Works with reader connections.

## Usage

``` r
datom_get_set(conn, name, version = NULL)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md),
  scoped to the set's project. A storage-only connection with no git
  clone is enough.

- name:

  The set's name.

- version:

  Optional version (`metadata_sha`, or a prefix of one). `NULL` reads
  the current version.

## Value

A `datom_set`: a list of `name`, `project`, `version` (possibly `NULL`),
`data_sha`, `tags` and `members`.

## Details

Reading a set requires access to the set's own project only. A member is
a pointer, and resolving it is a separate, deliberate step – so a
50-member product is readable by someone entitled to none of its
members.

## What comes back

References and labels, and no data at all – which is why the verb is
`get` rather than `read`.

A `datom_set`: `name`, `project`, `version`, `data_sha`, `tags` and
`members`. The four identifying facts are there so that a caller who
passed `version = NULL` can still say which version they got, because a
set exists to be cited. `version` is the version **recorded** in the
history, so an 8-character prefix goes in and the full version comes
back.

`members` is a flat, **unnamed** list in payload order. Not name-keyed,
and the reason is not style: the same artifact at two different versions
is a legal pair of members, two projects may both hold a `dm`, and R's
`$` partial-matches on lists – so a name-keyed list would answer
plausibly and wrongly. The unique key is the full `id`.

One of the four identifying facts has a limit worth knowing before you
cite it:

- **`version` can be `NULL`.** It is the version *recorded* in
  `version_history.json` for the state `metadata.json` describes, and a
  truncated or partly-synced history records no such entry. A
  manufactured version would be a wrong statement rather than a missing
  one, so the field is left empty and
  [`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
  owns the inconsistency. A version-pinned read always reports one,
  since the entry is what it resolved through.

`project` is the name the set's **own metadata** records – the
declaration of the repo that wrote it, not the name on your connection.
It falls back to the connection's name only for a set written by a datom
that predates the field, which no released build ever was. Each
**member** carries its own recorded `id$project` for the same reason,
resolved through a slightly longer route because that value is durable
and hashed rather than displayed.

## Resolving a member

Each member is `id` (`project`, `name`, `kind`, `version`), its optional
`tags`, and `fetch`:

    x <- datom_get_set(conn, "study001-adam")
    dm <- x$members[[1]]$fetch(conn)

`fetch` resolves whatever the pointer points at: a table member yields
data, a set member yields another `datom_set`. **A link pins the version
it was read at** – it is a citation, not a subscription, so it never
drifts to the latest. Pass a connection scoped to the member's own
project; same-project members resolve through the connection you already
have.

Two reads of the same set are **not**
[`identical()`](https://rdrr.io/r/base/identical.html), because closures
compare by environment. Compare `m[c("id", "tags")]` instead, or use
`identical(a, b, ignore.environment = TRUE)`.

## Integrity, and what is not rechecked

The stored payload is verified against the recorded `document_sha`
**before it is parsed**, and a version that records no `document_sha` is
an error rather than a skipped check. `data_sha` is not recomputed: it
is the address the payload was fetched from, so it would catch nothing
the byte hash did not, and it would refuse a payload written by a newer
datom. Nothing in the payload is re-canonicalized – what you are shown
is what was cited.

## See also

[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
to write one,
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
to declare a member,
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
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

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  member <- datom_member(
    conn, "dm", datom_history(conn, "dm")$version[1],
    tags = list(type = "input")
  )
  datom_write_set(conn, list(member),
                  tags = list(description = "Example product"))

  x <- datom_get_set(conn, "example_product")
  print(x)

  # Resolve one member to its data. The link pins the version it was read at.
  print(head(x$members[[1]]$fetch(conn)))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a76285937f5/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a76285937f5/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote set "example_product" (1 member): "99e7bed7"
#> 
#> ── datom set: "example_product" 
#> • Project: "example_project"
#> • Version: "99e7bed7b70e33f690caf80849e46a6710fc191ecf7e1922692be2ab48ae7d90"
#> • Members: 1
#> • Tags: description=Example product
#>   • dm (table) type=input
#> ℹ Fetch a member with `datom_fetch_member(conn, x, "dm")`.
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
