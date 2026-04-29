# Delete All Files Under a Local Storage Prefix

Removes the directory at `root/{prefix}/datom/{prefix_key}` and
everything inside it. A missing prefix is a no-op.

## Usage

``` r
.datom_local_delete_prefix(conn, prefix_key = NULL)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- prefix_key:

  Relative prefix (after `prefix/datom/`).

## Value

Invisibly, 1L if the directory was removed, 0L if not found.
