# One Display Line Per Edited Member, Grouped by Project

Grouped by project because that is the axis connections are supplied
along, so a surprise in the grouping is a surprise about which
connection served what. A removal has no connection behind it, but it
keeps the same grouping so one message can hold both kinds of entry.

## Usage

``` r
.datom_edit_lines(edits, abbreviate = TRUE)
```

## Arguments

- edits:

  The edit log.

- abbreviate:

  Whether to shorten versions to 8 characters (the console) or leave
  them whole (a commit message, where git is the durable record).

## Value

A character vector of lines.
