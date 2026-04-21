# Build S3 Object Key

Constructs S3 keys from path components, inserting the `datom/` segment
per the storage structure convention.

## Usage

``` r
.datom_build_storage_key(prefix = NULL, ...)
```

## Arguments

- prefix:

  Optional S3 prefix (e.g., "project-alpha"). NULL if none.

- ...:

  Path segments after the `datom/` segment (e.g., table name, file name,
  ".metadata").

## Value

Character string S3 key.

## Examples

``` r
if (FALSE) { # \dontrun{
# Data file
.datom_build_storage_key("proj", "customers", "abc123.parquet")
# → "proj/datom/customers/abc123.parquet"

# Table metadata
.datom_build_storage_key("proj", "customers", ".metadata", "metadata.json")
# → "proj/datom/customers/.metadata/metadata.json"

# Repo-level metadata
.datom_build_storage_key("proj", ".metadata", "dispatch.json")
# → "proj/datom/.metadata/dispatch.json"

# No prefix
.datom_build_storage_key(NULL, "customers", "abc123.parquet")
# → "datom/customers/abc123.parquet"
} # }
```
