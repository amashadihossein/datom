# Create a Local Filesystem Store Component

Constructs a validated local filesystem storage component for use as
either the governance or data component of a `datom_store`. Validates
that the path exists (or is creatable) and is writable.

## Usage

``` r
datom_store_local(path, prefix = NULL, validate = TRUE)
```

## Arguments

- path:

  Directory path for the store root.

- prefix:

  Key prefix within the root (e.g., `"project/"`). NULL for no prefix.

- validate:

  If `TRUE` (default), validate that `path` exists and is writable. Set
  to `FALSE` for tests or deferred creation.

## Value

A `datom_store_local` object.
