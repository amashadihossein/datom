# Apply Every Upgrade Step from a Declared Version to Current

The dispatcher. Runs each step from `declared` up to
`.datom_supported_schema` in order, then records the version it reached.

## Usage

``` r
.datom_manifest_upgrade(manifest, declared)
```

## Arguments

- manifest:

  Parsed manifest document (a named list).

- declared:

  Declared schema version, as returned by
  [`.datom_check_schema_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_schema_version.md).

## Value

The document in current shape, declaring the version it reached.

## Details

`declared` is a parameter rather than something read off the document,
because the only correct source for it is
[`.datom_check_schema_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_schema_version.md),
which returns it after refusing a document this build cannot convert.
Taking it as an argument is what makes "check first, then upgrade"
structural: there is no way to call this without having obtained the
number from the check.

Identity on a document already at the current version – zero steps run.
A document declaring a version *above* current is returned untouched
too, since no step exists for it; that state is unreachable through the
check, which aborts first.
