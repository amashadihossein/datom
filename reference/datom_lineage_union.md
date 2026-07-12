# Union and deduplicate source_lineage lists

Takes a list of zero or more `source_lineage` lists and returns their
deduplicated union. Each entry is a list with `project`, `table`, and
`version_sha`. Deduplication uses the composite key
`paste(project, table, version_sha, sep = "\t")`, so each distinct entry
appears exactly once and retained entries are returned unchanged.

## Usage

``` r
datom_lineage_union(lineages)
```

## Arguments

- lineages:

  A list of `source_lineage` lists (each itself a list of entries with
  `project`, `table`, `version_sha`). `NULL` members are treated as
  empty.

## Value

A deduplicated list of `source_lineage` entries, or an empty list when
there is nothing to union.

## Details

`NULL` members are tolerated (a parent may carry
`source_lineage = NULL`) and treated as an empty contribution. Empty
input, or a list containing only empty lineage lists, returns an empty
list.

This helper is the building block of the composable lineage recompute
recipe. To check that a derived table's recorded `source_lineage`
matches its parents, read each parent through a connection scoped to
that parent's project and union their lineages:


    # conn_c is scoped to the derived table's project.
    parents <- datom_get_parents(conn_c, "c")

    # One connection per project, keyed by each parent's `source`. Never
    # reach across project stores with a single connection.
    conns <- list(project_a = conn_a, project_b = conn_b)

    # Read each parent's lineage through its own project connection.
    parent_sls <- lapply(parents, function(p) {
      datom_get_lineage(conns[[p$source]], p$table, version = p$version,
                        depth = "source")
    })

    recomputed <- datom_lineage_union(parent_sls)
    recorded   <- datom_get_lineage(conn_c, "c", depth = "source")
    identical(recomputed, recorded)

## Examples

``` r
sl1 <- list(list(project = "p", table = "t", version_sha = "a"))
sl2 <- list(list(project = "p", table = "t", version_sha = "a"))
datom_lineage_union(list(sl1, sl2))
#> [[1]]
#> [[1]]$project
#> [1] "p"
#> 
#> [[1]]$table
#> [1] "t"
#> 
#> [[1]]$version_sha
#> [1] "a"
#> 
#> 
```
