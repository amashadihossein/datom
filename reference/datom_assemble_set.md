# Start Assembling a Set

Returns an empty set, to be filled in with
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
and written with
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md):

## Usage

``` r
datom_assemble_set(conn, name = NULL, tags = NULL)
```

## Arguments

- conn:

  A `datom_conn` from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
  for the product repo. Its project name is recorded as the set's
  project; nothing else is kept.

- name:

  The set's name. `NULL` (the default) leaves it to the write, which
  takes the name the repo declares under `set:` in `.datom/project.yaml`
  – the usual case, since one repo holds one set.

- tags:

  Optional named list of set-level text labels, e.g. a description.

## Value

A `datom_set` with no version and no members.

## Details

    datom_assemble_set(conn, tags = list(description = "ADaM datasets")) |>
      datom_add_member("adsl", v_adsl, tags = list(type = "output"),
                       conn = conn) |>
      datom_add_member("dm", v_dm, tags = list(type = "input"),
                       conn = conn_src) |>
      datom_write_set(conn = conn)

The equivalent single call – a
[`list()`](https://rdrr.io/r/base/list.html) of
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
results passed to
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
– remains fully supported and is the better fit for a build script. What
this path adds is **where an error surfaces**: a malformed member aborts
on the line that declared it and names that member, instead of aborting
once the whole list has been assembled and indexed.

## One kind of set

What comes back is a `datom_set`, the same kind of object
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
returns, only with no version yet. So every verb that takes a set takes
this one:
[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md),
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md),
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
and the rest.

**It holds no connection.** A connection may carry a credential, so it
is passed on each call that needs one rather than kept in a value that
can be printed or saved: `conn =` on
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
for a member given by name, and `conn` on
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md).
The connection given here is used only to record which project the set
belongs to; the write checks that it is the project it is written into.

## Set-level tags

Supplied here rather than by a third verb, because they are facts about
the collection rather than about any member. Editing them later is plain
R – `x$tags$description <- "..."` – and the same grammar applies as to a
member's tags: text only, one label or several.

## See also

[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
to add one member,
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
to write the result,
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
for the single-call form.

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

  v_dm <- datom_history(conn, "dm")$version[1]
  v_lb <- datom_history(conn, "lb")$version[1]

  x <- datom_assemble_set(
    conn,
    tags = list(description = "Example product for STUDY-001")
  ) |>
    datom_add_member("dm", v_dm, tags = list(type = "input"), conn = conn) |>
    datom_add_member("lb", v_lb, tags = list(type = "output"), conn = conn)

  print(datom_list_members(x))
  x |> datom_write_set(conn = conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd19969a22/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd19969a22/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> ✔ Wrote "lb" (full): "b2937781"
#> ℹ Nothing has been written. Write the set with `datom_write_set(conn, x)`.
#> ℹ Nothing has been written. Write the set with `datom_write_set(conn, x)`.
#>   name         project
#> 1   dm example_project
#> 2   lb example_project
#>                                                            version  kind  key
#> 1 b5cbba4501f518d7bbe1eaf4f0c236895b12d63677b9f75b9388b715055c832e table type
#> 2 b2937781f1a79b31ae3230b13aa573de64b944d1962f67d158a7aaccdc647677 table type
#>    value
#> 1  input
#> 2 output
#> ✔ Wrote set "example_product" (2 members): "9fbcadb3"
```
