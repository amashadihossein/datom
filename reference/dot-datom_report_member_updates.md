# Say What Moved, What Did Not, and That Nothing Was Written

The report is the deliverable rather than decoration: nothing is
written, so this is the dry run, and it is the only place the caller
sees what an inferred "current" resolved to.

## Usage

``` r
.datom_report_member_updates(changes, gone, skipped_lines, n_selected, n = 20L)
```

## Arguments

- changes:

  The change table, possibly with zero rows.

- gone:

  The selected members whose artifact no longer appears in its project.

- skipped_lines:

  Description lines for members skipped as ambiguous.

- n_selected:

  How many members the call selected.

- n:

  Maximum number of lines to print before truncating.

## Value

Invisibly `NULL`.

## Details

Lines are emitted with
[`cli::cli_verbatim()`](https://cli.r-lib.org/reference/cli_verbatim.html)
because they embed artifact names and label values, and cli reads
`{anything}` in message text as markup – an artifact called `dm{1}`
would be a parse error rather than a line.
