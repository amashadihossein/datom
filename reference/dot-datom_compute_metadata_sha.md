# Compute SHA-256 of Metadata (the datom Version)

Hashes the fields named in `.datom_metadata_identity_fields` and ignores
every other key in the document. See that constant for the
field-by-field classification, for why selection is an allowlist rather
than an exclusion list, and for the obligation that comes with adding a
field to a builder.

## Usage

``` r
.datom_compute_metadata_sha(metadata)
```

## Arguments

- metadata:

  Named list of metadata fields. An unrecognised field is **ignored, not
  refused** – that is what lets this build read a document written by a
  newer datom without reporting a change on content that did not move.
  Refusing such a document is a separate, write-side concern.

## Value

Character SHA-256 hash.

## Details

Hashes a JSON canonical form rather than the R object directly. This
ensures that metadata read back from JSON (e.g., from S3) produces the
same SHA as metadata built in-memory, despite R type differences
(integer vs double, character vector vs list) introduced by JSON
round-tripping.
