# Empty Manifest Skeleton

The one shape of an empty manifest. Callers that need a manifest when
none exists yet build it here rather than inline, so a later change to
the manifest's shape has a single place to land.

## Usage

``` r
.datom_manifest_skeleton(project_name = NULL)
```

## Arguments

- project_name:

  Project name, or `NULL` to omit the field (callers that only need
  somewhere to look up entries have no project name to hand).

## Value

A list with `schema_version`, `project_name` (when supplied),
`artifacts` and `summary`.

## Details

`artifacts` is a **named** empty list on purpose: `jsonlite` serializes
an empty bare list as a JSON array (`[]`) and an empty named list as an
object ([`{}`](https://rdrr.io/r/base/Paren.html)), and a manifest's
artifact block must be an object. Inert today, since nothing writes a
manifest that still has zero entries, and correct for the one case where
it would.

The skeleton declares `schema_version` itself, so no repo ever exists in
a state that declares no format at all – not even between being created
and receiving its first artifact. This covers only the
built-from-nothing path: a document read from disk in an older shape
gets its version from
[`.datom_manifest_upgrade()`](https://amashadihossein.github.io/datom/reference/dot-datom_manifest_upgrade.md)
instead, because the skeleton is unreachable whenever a manifest file
exists.
