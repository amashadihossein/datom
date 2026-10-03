# Build the Metadata Document for a Set Write

A set's `metadata.json` is a collapsed version of a table's:
`schema_version`, `kind`, `data_sha`, `hash_algo`, `document_sha`,
`project`, `created_at`, `datom_version`, and no more. Everything a
table carries that describes a rectangle (`nrow`, `ncol`, `colnames`),
the provenance axis (`table_type`, `parents`, `source_lineage`), the
stored-parquet facts (`parquet_sha`, `size_bytes`) and the user-metadata
channel (`custom`) are all **omitted, not nulled** – a set's members and
its user metadata both live in the payload as tags, and no counter reads
a set's byte size.

## Usage

``` r
.datom_build_set_metadata(payload, document_sha = NULL, project = NULL)
```

## Arguments

- payload:

  The set payload: a list with `members` (an unnamed list of member
  records) and optional set-level `tags`. Must already be tidied and
  validated – this builder hashes what it is given.

- document_sha:

  SHA-256 of the stored payload bytes, or NULL. Declared either way,
  mirroring how
  [`.datom_build_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_build_metadata.md)
  declares `parquet_sha` for
  [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  to populate: the byte hash is not knowable until the payload has been
  serialized, and it is excluded from `metadata_sha`, so the deferred
  assignment cannot move a version. **Nothing computes one until the set
  write path exists**, so today it arrives NULL from every caller.

  **The write path must populate it before writing the document.**
  `jsonlite` does not omit a NULL element – it writes
  [`{}`](https://rdrr.io/r/base/Paren.html), which reads back as an
  empty list rather than an absent key. `parquet_sha` never hits this
  because its only two outcomes are a real hash or
  `meta$parquet_sha <- NULL`, and assigning NULL *removes* the element.
  A field left declared-and-unpopulated through a write would satisfy a
  names-only field-set check while carrying an empty object, so assert
  on the written bytes where the field set matters.

- project:

  The name of the project whose namespace this set is being written
  into, from the writing repo's own `.datom/project.yaml`. Same field
  and same only-when-non-NULL treatment as
  [`.datom_build_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_build_metadata.md)'s
  `project`.

## Value

Named list of exactly the fields a set's `metadata.json` carries, named
in the description above. Deliberately not stated as a count: the count
was written down in six places and went stale in all of them the first
time a field was added.

## Details

Kept beside
[`.datom_build_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_build_metadata.md)
on purpose: the two documents are close enough that a field copied from
the wrong one is easy to miss, and two of the values here are exactly
that kind of trap.

- `data_sha` comes from
  [`.datom_canonical_set_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_set_hash.md),
  the `datom-sv1` identity engine, **not** from the table hash. Computed
  here rather than passed in, so a caller cannot hand a set a
  table-regime hash.

- `hash_algo` is the literal `"datom-sv1"`. The encoder embeds that
  string inside the digest but nothing stamps the field, so the builder
  must. A copied `"datom-cv1"` would leave a set claiming one regime
  while hashing under the other, and no hash comparison would notice.
