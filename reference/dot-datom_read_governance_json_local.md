# Read governance.json from Local Git Clone

Reads and validates `{path}/.datom/governance.json`. Returns NULL when
the file is absent (project is not gov-attached). Aborts on malformed
JSON or failed schema validation.

## Usage

``` r
.datom_read_governance_json_local(path)
```

## Arguments

- path:

  Absolute path to the root of the local data git clone.

## Value

Parsed list or NULL.
