# Upgrade a v1 Manifest to v2

v1 is every manifest written before the artifact namespace existed: the
artifact list sits under `tables` and no entry declares what kind of
artifact it is. v2 renames that key to `artifacts` and types every entry
with `kind = "table"`, which is what all of them are – sets did not
exist.

## Usage

``` r
.datom_manifest_upgrade_v1_to_v2(manifest)
```

## Arguments

- manifest:

  Parsed manifest document (a named list) declaring v1.

## Value

The same document in v2 shape. The version is stamped by
[`.datom_manifest_upgrade()`](https://amashadihossein.github.io/datom/reference/dot-datom_manifest_upgrade.md),
not here, so a step is never mistaken for the thing that records the
result.

## Details

The rename is done **in place**
([`names()`](https://rdrr.io/r/base/names.html) assignment rather than
add-then-remove), so the key keeps its position in the document and any
sibling key this build does not recognise survives untouched.

A v1 document with no `tables` key at all is left with no artifact key.
That is deliberate: an absent key and an empty one are different states
– a truncated document versus a repo with nothing in it – and flattening
them here would destroy the distinction a later self-healing read
depends on.

**Frozen.** See the file header.
