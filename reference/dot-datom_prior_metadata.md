# The Metadata Document Already in the Clone, If Any

Reads `{name}/metadata.json` from the local git checkout, for the one
purpose of finding fields to carry forward. Returns `NULL` when there is
no such file or it will not parse – both mean there is nothing to
preserve, and neither is this function's business to report: a brand-new
artifact legitimately has no prior document, and an unparseable one
fails moments later on its own terms.

## Usage

``` r
.datom_prior_metadata(conn, name)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

- name:

  Artifact name.

## Value

The parsed document, or `NULL`.

## Details

**The clone's copy, not storage's.** Three reasons, any one sufficient:
it is the file being overwritten, so preserving its own content is the
claim being made; it is a local file read rather than a network round
trip; and it is where a pull from a collaborator on a newer datom lands.
Storage cannot legitimately hold a newer document than the clone,
because git is written first and gates the storage mirror – if it does,
that is drift, and
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
owns drift.
