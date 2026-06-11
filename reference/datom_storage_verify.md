# Verify a Copy Between Two datom Storage Namespaces

Checks that objects in `to_conn`'s datom namespace match their
counterparts in `from_conn`. Two verification modes are available:

## Usage

``` r
datom_storage_verify(
  from_conn,
  to_conn,
  keys = NULL,
  mode = c("structural", "content")
)
```

## Arguments

- from_conn:

  A `datom_conn` object (source / reference).

- to_conn:

  A `datom_conn` object (destination to verify).

- keys:

  Character vector of relative keys (after `{prefix}/datom/`) to verify.
  `NULL` (default) verifies every key returned by
  `datom_storage_list(from_conn)`. Pass a subset to verify a sample.

- mode:

  `"structural"` (default) or `"content"`. See above.

## Value

A data frame with columns:

- `key` (character): relative storage key.

- `ok` (logical): `TRUE` if the object passed verification.

- `issue` (character): description of the mismatch, or `NA` if `ok`.
  Returns a zero-row data frame if `keys` is empty.

## Details

- **`"structural"` (default)**: Confirms each destination object exists
  and its byte size matches the source. Fast – one `HEAD`/stat per
  object, no byte transfer. Catches truncated or missing objects, which
  is the dominant copy failure mode.

- **`"content"`**: Re-reads destination bytes, recomputes the SHA-256
  hash, and compares against the source hash. Expensive (full
  re-download for remote backends) but gives true bit-level integrity.
  Use for regulated or paranoid runs.

## See also

[`datom_storage_copy()`](https://amashadihossein.github.io/datom/reference/datom_storage_copy.md),
[`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md)

## Examples

``` r
if (FALSE) { # \dontrun{
copied <- datom_storage_copy(from_conn, to_conn)
# Verify all copied objects structurally (default, fast)
results <- datom_storage_verify(from_conn, to_conn)
all(results$ok)

# Verify a subset with full content hash
results <- datom_storage_verify(from_conn, to_conn,
                                keys  = copied$key[1:10],
                                mode  = "content")
} # }
```
