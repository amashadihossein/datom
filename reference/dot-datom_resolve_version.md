# Resolve Version to data_sha, Stored-Object Hash and Recorded Version

Given metadata from
[`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md),
resolves a version spec to the corresponding `data_sha` (the storage
address), the recorded stored-object integrity hash, and the version
string as **recorded**. If `version` is NULL, resolves from the current
`metadata.json`; if a metadata_sha string (or a prefix of one), looks it
up in `version_history.json`.

## Usage

``` r
.datom_resolve_version(
  metadata_list,
  version = NULL,
  name = "table",
  field = "parquet_sha"
)
```

## Arguments

- metadata_list:

  Return value of
  [`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md).

- version:

  NULL (current) or a metadata_sha string / prefix.

- name:

  Artifact name (for error messages).

- field:

  Which recorded stored-object hash to resolve: `"parquet_sha"` (a
  table's parquet) or `"document_sha"` (a set's payload).

## Value

Named list with `data_sha` (character), `object_sha` (character or
`NULL`) and `version` (character or `NULL`) for the resolved version.

## Details

**One function, two kinds, one `field` argument.** A table's stored
object is a parquet file pinned by `parquet_sha`; a set's is a JSON
payload pinned by `document_sha`. The question is identical either way –
*which recorded hash pins the version I just resolved* – so a second
copy of this lookup would eventually disagree with this one about prefix
matching or about what an absent hash means. The resolved hash comes
back as `object_sha` regardless, because the caller already knows which
field it asked for.

The `object_sha` may be `NULL`/`""`, and what that means is the caller's
to decide, not this function's. For a table it is **pre-cv1 metadata**
and tells
[`.datom_read_parquet()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_parquet.md)
to skip the integrity check – a grace for legacy metadata, not a gap in
the current writer. For a set there is no legacy population, so the set
read treats it as an error.

`version` is the version **recorded** for the resolved state, never
recomputed: a pinned read echoes the matched history entry's own version
string (so a caller who passed an 8-character prefix gets the full one
back), and an unpinned read takes the current state's recorded version
via
[`.datom_recorded_current_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_recorded_current_version.md).
That helper returns `NULL` when the history records nothing matching the
current document, which is a gap
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
owns – a manufactured version would be a wrong statement rather than a
missing one.
