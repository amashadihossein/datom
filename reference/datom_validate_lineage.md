# Validate Source Lineage Consistency

Checks that a table's declared `source_lineage` matches the union of its
parents' `source_lineage` fields. Detects missing entries (in the
computed union but absent from declared), extra entries (declared but
not in the union), and wrong-version entries (matching project+table but
different `version_sha`).

## Usage

``` r
datom_validate_lineage(conn, name, version = NULL)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, checks the current
  version.

## Value

A list with:

- status:

  One of `"ok"`, `"mismatch"`, `"unchecked"`, `"error"`.

- missing:

  List of entries in the computed union but absent from declared.

- extra:

  List of entries declared but absent from the computed union.

- wrong_version:

  List of entries where project+table match but `version_sha` differs.
  Each element has `declared` and `computed` sub-lists.

- message:

  Human-readable summary string.

## Details

datom validates schema shape only at write time. This function provides
on-demand semantic checking, suitable for CI runs, audits, or
pre-publication gates.

Tables without `parents` return `status = "unchecked"` – there is no
union to compare against. Tables where any parent's metadata is
unreachable return `status = "error"`.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_lineage_val_")
store <- datom_store(
  data = datom_store_local(path = file.path(tmp, "storage")),
  github_pat = "ghp_examplePATforDemoPurposesOnly1234",
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
datom_init_repo(
  path = file.path(tmp, "repo"),
  project_name = "example_project",
  store = store
)
conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
datom_write(conn, data = datom_example_data("dm"), name = "dm")
datom_validate_lineage(conn, "dm")
unlink(tmp, recursive = TRUE)
} # }
```
