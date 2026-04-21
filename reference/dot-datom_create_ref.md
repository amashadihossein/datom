# Create Initial ref.json Content

Builds the initial `ref.json` structure from the data store component.
No `previous` entries on first creation.

## Usage

``` r
.datom_create_ref(data_store)
```

## Arguments

- data_store:

  A `datom_store_s3` component (the data portion of the store).

## Value

A list suitable for JSON serialization.
