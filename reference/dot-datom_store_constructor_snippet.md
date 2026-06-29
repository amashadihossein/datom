# Build a Store-Constructor Snippet for a Component

Renders a copy/paste `datom_store_local(...)` or `datom_store_s3(...)`
call string for a store component, for embedding in a generated README.
Secrets are shown as placeholders.

## Usage

``` r
.datom_store_constructor_snippet(component)
```

## Arguments

- component:

  A store component (`datom_store_local`, `datom_store_s3`, or
  `datom_store_s3_creds`).

## Value

Character scalar — an R constructor call as text.
