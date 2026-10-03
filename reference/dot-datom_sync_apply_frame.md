# A Preview Frame Checked for Shape and Values, as Plain Text Columns

Columns and values only, never where the frame came from: a subset or a
hand-built frame is as good as the preview itself. Every check runs
before any read.

## Usage

``` r
.datom_sync_apply_frame(manifest)
```

## Arguments

- manifest:

  What the caller passed.

## Value

A data frame of the six preview columns, each character.

## Details

Values are checked only on the rows apply acts on (`new`, `changed`);
the others do nothing, so a hand-trimmed `not_checked` row is harmless.
A short `version_from` would otherwise fail the exact comparison later
and stop as stale, naming the wrong problem.
