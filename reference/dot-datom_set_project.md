# Which Project a Set Reports Itself As Belonging To

Two steps, not the three
[`.datom_declared_project()`](https://amashadihossein.github.io/datom/reference/dot-datom_declared_project.md)
uses: the set's own metadata document, then the connection's name. See
the call site in
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
for why the manifest step is deliberately absent here.

## Usage

``` r
.datom_set_project(current, conn)
```

## Arguments

- current:

  The set's `metadata.json`, as already read by the set read.

- conn:

  The connection the set was read through.

## Value

A single string, or whatever the connection carries.
