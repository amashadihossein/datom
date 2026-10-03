# Say What the Set Sync Preview Found

One summary line, then one warning per group of rows or members the
caller has to know about, each with its remedy.

## Usage

``` r
.datom_report_sync_preview(
  result,
  n_sources,
  ambiguous_lines,
  ambiguous_first,
  unpassed,
  gone,
  unversioned
)
```

## Arguments

- result:

  The preview frame.

- n_sources:

  How many sources were mapped.

- ambiguous_lines:

  One line per member behind an `ambiguous` row.

- ambiguous_first:

  The name of the first ambiguous artifact, for the remedy, or `NULL`.

- unpassed, gone:

  Member rows (`project`, `name`, `kind`, `version`) for members of a
  project not passed, and members whose artifact is no longer listed in
  their source.

- unversioned:

  `"name in project"` for artifacts whose manifest entry records no
  current version.

## Value

Invisibly `NULL`.
