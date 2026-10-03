# Forget the Version an Edited Set Was Read As

[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
fills `version` and `data_sha` from the payload it read. Once a member
moves, those two describe a payload that no longer exists – and a set
exists to be cited, so a stale version is a wrong statement rather than
a missing one. Left in place when nothing moved: there the object still
describes exactly the stored version, and dropping a true fact would
cost the common "refresh found nothing" case its citability for no
reason.

## Usage

``` r
.datom_forget_set_identity(x)
```

## Arguments

- x:

  The edited `datom_set`.

## Value

`x`, with `version` and `data_sha` emptied when it had them.

## Details

**Spelled `x["f"] <- list(NULL)`, never `x$f <- NULL`**, which would
REMOVE the element and change `names(x)`. A read set may legitimately
report a `NULL` version, so the field exists and is empty rather than
being absent.

A set never written has both fields empty already, so this changes
nothing there.
