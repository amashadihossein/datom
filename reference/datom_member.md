# Declare a Member of a Set

Resolves one artifact version against a single project connection and
returns a pure-data member record to pass to a set write. The record is
a pointer: it names the project, artifact, kind, and version, and
carries no copy of the data. Reading the artifact's versioned metadata
snapshot is what makes the pointer trustworthy – a member can only point
at something that already exists, which is also why a set cannot contain
itself at any depth.

## Usage

``` r
datom_member(conn, name, version, tags = NULL)
```

## Arguments

- conn:

  A `datom_conn` scoped to the **member's** project store, from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Artifact name (single validated string).

- version:

  The artifact version (`metadata_sha`) to pin, e.g. from
  [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md).

- tags:

  Optional named list of text labels for this member. Omitted from the
  record when absent or empty.

## Value

A list with `id` (a list of exactly `project`, `name`, `kind`,
`version`) and, when tags were supplied, `tags`. Pure data: it retains
no connection and is serializable.

## Details

Same-project and cross-project members are declared identically; the
only difference is which connection is passed. `kind` comes from the
snapshot (defaulting to `"table"` for a snapshot written before datom
recorded the field), and `project` comes from the **repo** rather than
from the connection: the artifact's own metadata, else the project
manifest, else the connection's name with a warning saying it is
unverified. That matters because a reader connection's project name is a
label the caller supplied and nothing checks it against the repo, while
this value is hashed into the set's identity and cited afterwards.

Unlike
[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md),
a member carries **no `data_sha`**: the version already pins the
content, and a second copy of that fact would be a second thing to keep
consistent.

## Tags

`tags` is an optional named list of text labels describing this member's
role in the set – what folder structure would otherwise express. A value
may be a single string or several, because the whole point of labels
over folders is that an item can be in more than one category at once:
`list(type = "output", domain = c("safety", "efficacy"))`.

Values are text only: no numbers, booleans, or nesting. Write a numeric
label as a string (`"500"`) and parse it downstream, exactly as you
would a folder name.

Three outcomes, and the difference is whether anything is actually
there:

|  |  |
|----|----|
| What you pass | What happens |
| no `tags` | accepted; the record carries no `tags` |
| `list(domain = character(0))` or `list(domain = NULL)` | the key is dropped, as if never mentioned |
| `list(domain = "")` | refused – a label with no name is almost always an accident |

## See also

[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
for the lineage equivalent.

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

  # Pin the version just written and label its role in the set.
  version <- datom_history(conn, "dm")$version[1]
  print(datom_member(conn, "dm", version, tags = list(type = "input")))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a763a554e94/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a763a554e94/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> $id
#> $id$project
#> [1] "example_project"
#> 
#> $id$name
#> [1] "dm"
#> 
#> $id$kind
#> [1] "table"
#> 
#> $id$version
#> [1] "b5cbba4501f518d7bbe1eaf4f0c236895b12d63677b9f75b9388b715055c832e"
#> 
#> 
#> $tags
#> $tags$type
#> [1] "input"
#> 
#> 
```
