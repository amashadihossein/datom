# Select the Artifacts of One Kind

The one place the artifact list is filtered by `kind`. Four counters
need it – two in the manifest's stored `summary` block, plus the numbers
[`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
and
[`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md)
count for themselves – and a predicate written out at each of them is a
predicate that can differ at one of them.

## Usage

``` r
.datom_artifacts_of_kind(artifacts, kind)
```

## Arguments

- artifacts:

  The manifest's `artifacts` list, or `NULL`.

- kind:

  `"table"` or `"set"`.

## Value

The entries of that kind, names preserved.

## Details

**An entry that is not a named list is skipped rather than
dereferenced.** The upgrade step deliberately passes such an entry
through untouched, because it has no shape to convert; without the check
here, that preserved entry reaches `entry$kind` and aborts with "\$
operator is invalid for atomic vectors".
[`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md)
is the one that must not do that: it exists to describe a connection
when the manifest cannot be trusted, and this count sits outside the
error handling that gives it that tolerance. A hand-edited manifest is
exactly the document most likely to reach it.

Skipping is not the same as tolerating a **missing** `kind`, which stays
deliberately uncounted: a typed entry with no type means the conversion
was skipped, and a visibly wrong count is the intended signal for that.
