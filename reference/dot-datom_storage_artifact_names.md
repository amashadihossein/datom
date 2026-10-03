# Artifact Names Present in Storage

Enumerates artifacts from a storage listing, by the one signal that
identifies one: a `{name}/.metadata/metadata.json` object. Deliberately
independent of the manifest, because the manifest is the document under
suspicion whenever this is called.

## Usage

``` r
.datom_storage_artifact_names(conn)
```

## Arguments

- conn:

  A `datom_conn` object.

## Value

Character vector of artifact names, possibly empty. One storage listing,
recursive.

## Details

The clone-side equivalent is
[`.datom_clone_artifact_names()`](https://amashadihossein.github.io/datom/reference/dot-datom_clone_artifact_names.md).
They are not interchangeable and neither can stand in for the other: a
storage-only reader has no clone at all, and the clone can hold an
artifact whose upload has not happened yet.

**The listing returns FULL keys** – including the `{prefix}/datom/`
portion – while every other part of datom's business logic speaks in
keys relative to the datom namespace root. Mixing the two shapes
double-prefixes silently and does not error, so the root is stripped
here, once, against the same builder the backends use.
