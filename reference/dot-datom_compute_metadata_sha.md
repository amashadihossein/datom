# Compute SHA-256 of Metadata

Sorts fields by C-locale byte order (`method = "radix"`) before hashing
so the result is deterministic regardless of field insertion order
**and** regardless of the host's `LC_COLLATE` (default collation sorts
differ between `C` and e.g. `en_US.UTF-8`, which would otherwise make
the same metadata hash differently on different machines).

## Usage

``` r
.datom_compute_metadata_sha(metadata)
```

## Arguments

- metadata:

  Named list of metadata fields.

## Value

Character SHA-256 hash.

## Details

Volatile fields are excluded so that identical semantic content always
produces the same SHA regardless of when or how it was serialized:
`created_at` and `datom_version` (write-time provenance), `parquet_sha`
and `size_bytes` (stored-object byte facts – both drift with the arrow
version and must not re-enter identity), and `column_hashes` (a
deterministic function of the same values that already fix `data_sha`).
`original_file_sha` and `hash_algo` remain in the semantic set – a new
source file or a new hash algorithm legitimately defines a new version.

Hashes a JSON canonical form rather than the R object directly. This
ensures that metadata read back from JSON (e.g., from S3) produces the
same SHA as metadata built in-memory, despite R type differences
(integer vs double, character vector vs list) introduced by JSON
round-tripping.
