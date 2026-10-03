# Human Label for a Connection's Storage Backend

The word to put in a user-facing message for the backend a connection
uses: `"S3"`, `"local"`, or the raw backend name for anything not in the
table.

## Usage

``` r
.datom_backend_label(conn)
```

## Arguments

- conn:

  A `datom_conn` object, or anything carrying a `backend` field.

## Value

A single string.

## Details

**One table, not five.** This mapping was written out at four call sites
and was about to be written at a fifth, which is the shape of the defect
the artifact-kind predicate produced: the same rule copied per site,
until one copy lost a term. There is nothing to disagree about here yet,
which is exactly when it is cheap to make disagreement impossible.
