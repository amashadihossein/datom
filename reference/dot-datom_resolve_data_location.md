# Resolve Data Location via Ref (Conn-Time Helper)

Called during
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
for both readers and developers when a governance store is present.
Reads `ref.json` from governance, detects migration (store\$data
location != ref location), and returns the ref-resolved location.

## Usage

``` r
.datom_resolve_data_location(store, role, path = NULL, endpoint = NULL)
```

## Arguments

- store:

  A `datom_store` object with governance component.

- role:

  `"developer"` or `"reader"`.

- path:

  Local repo path (developers only; NULL for readers).

- endpoint:

  Optional S3 endpoint URL.

## Value

A named list with `root`, `prefix`, `region` from the ref, or NULL if no
governance store is present (skip ref resolution).

## Details

**Developer migration**: auto-pulls git, re-reads project.yaml. Errors
if project.yaml still disagrees after pull.

**Reader migration**: warns that the store config is stale, proceeds
with ref-resolved location.
