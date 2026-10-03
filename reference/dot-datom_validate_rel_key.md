# Validate a Caller-Supplied Relative Storage Key

Guards a whole key string that a caller composed, as opposed to one
datom built itself from validated parts. The internal key builders in
`R/utils-path.R` need no such check:
[`.datom_validate_name()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_name.md)
admits only `[a-zA-Z0-9_ ()-]` and
[`.datom_validate_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_sha.md)
only hex, so their output cannot contain a `..` segment or a `datom/`
segment. A key arriving through a public export has had no such
filtering.

## Usage

``` r
.datom_validate_rel_key(key, arg = "key")
```

## Arguments

- key:

  Value to validate as a relative storage key.

- arg:

  Name of the calling argument, used in the error message.

## Value

Invisible `key` on success. Aborts otherwise.

## Details

Two distinct failures are caught:

- **Traversal / shape.** A `..` segment or a leading `/` escapes the
  datom namespace on the local backend, where the key is pasted into a
  path and resolved by the filesystem
  ([`.datom_local_path()`](https://amashadihossein.github.io/datom/reference/dot-datom_local_path.md)).
  This applies to reads as much as to writes – reading
  `../../secrets.json` is exactly the sort of probe the guard sweep in
  \#74 existed to close.

- **A full key passed where a relative one belongs.** The two key shapes
  are documented at the top of `R/utils-path.R`; mixing them does not
  error today, it resolves under `{prefix}/datom/{prefix}/datom/...` and
  finds nothing, which reads to the caller as a missing object rather
  than a malformed key. A `datom` path segment is the detectable form,
  and it can never occur in a legitimate relative key because `datom` is
  a reserved artifact name (`.datom_reserved_names`).
