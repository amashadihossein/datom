# datom 0.1.1

Initial CRAN release. `datom` provides version-controlled data management for
reproducible scientific and clinical workflows — tables are tracked as code in
git while actual data lives in cloud storage (S3) or a local filesystem backend.

datom is experimental: the API may change without a deprecation cycle until it
reaches a stable release.

## Table identity: the `datom-cv1` canonical hash

Table identity is defined by a canonical hash of a table's **values**
(`datom-cv1`), not by the bytes of its parquet serialization. Hashing the
serialization tied identity to the writer: an `arrow` upgrade or a different
compression default produced different bytes for identical data, and therefore
a spurious new version. See
`vignette("design-version-shas")` for the model and the identity decisions.

* **Pre-release `data_sha` values change, and there is no migration path.**
  Any table written by a pre-release build carries a `data_sha` computed by the
  old algorithm. Those values are not recomputed, converted, or reconciled —
  pilots should re-onboard their data.
* Three SHAs are now recorded per table: `data_sha` (content identity),
  `metadata_sha` (the version you pass to `datom_read(version = )`), and
  `parquet_sha` (the stored object's SHA-256, verified on read before parsing).
* `metadata.json` gains `hash_algo`, `parquet_sha`, and `column_hashes` — an
  ordered per-column digest index from which `data_sha` can be re-derived
  without downloading data.

## Deliberate narrowings

Three capabilities were narrowed on purpose relative to pre-release behaviour.

* **List and exotic columns are refused.** A column must be a supported atomic
  type; list columns and exotic classes now abort the write with actionable

  advice. See `datom_check_hashable()` for a pre-flight check.
* **`datom_sync()` accepts only allowlisted formats.** Flat tabular files only
  (csv, tsv, parquet, sas7bdat, xpt, sav, dta, xls, xlsx). Read unsupported
  formats yourself and pass the data frame to `datom_write()`.
* **Internal `sort_columns` / `sort_rows` removed.** Row and column order are
  significant; sort explicitly before writing if order should not matter.

## Full API

See the [reference index](https://amashadihossein.github.io/datom/reference/)
for the complete exported surface at 0.1.0.
