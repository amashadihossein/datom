# Compute SHA-256 of Metadata

Sorts fields alphabetically before hashing for deterministic results,
regardless of field insertion order. Volatile fields (`created_at`,
`datom_version`) are excluded so that identical semantic content always
produces the same SHA, regardless of when it was written.

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

Hashes a JSON canonical form rather than the R object directly. This
ensures that metadata read back from JSON (e.g., from S3) produces the
same SHA as metadata built in-memory, despite R type differences
(integer vs double, character vector vs list) introduced by JSON
round-tripping.
