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

## Details

Mapping from arguments to key, for reference:

    ("proj", "customers", "abc123.parquet")
      -> "proj/datom/customers/abc123.parquet"

    ("proj", "customers", ".metadata", "metadata.json")
      -> "proj/datom/customers/.metadata/metadata.json"

    ("proj", ".metadata", "dispatch.json")
      -> "proj/datom/.metadata/dispatch.json"

    (NULL, "customers", "abc123.parquet")
      -> "datom/customers/abc123.parquet"
