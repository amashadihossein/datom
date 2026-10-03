# Assign One Leaf Into a Nested List, Creating Branches on the Way

Recursive rather than iterative because the depth is the length of the
axis vector, and `tree[[c("a", "b")]] <- v` fails when the intermediate
list does not exist yet.

## Usage

``` r
.datom_assign_leaf(tree, path, value)
```

## Arguments

- tree:

  The list to assign into.

- path:

  A character vector of branch names, innermost last.

- value:

  The leaf value.

## Value

`tree`, with the leaf assigned.
