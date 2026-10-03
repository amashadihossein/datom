# Append One Member Record to a Set, as an Edit

The three steps every addition takes – a `$fetch` link, the set's
version forgotten, an `add` row in the edit log – in one place, so
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
and the set route of
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
cannot drift apart in what they record. See points 5 and 6 of this
file's header. **It prints nothing**: each caller says "nothing has been
written" once, which for sync means once per call rather than once per
added member.

## Usage

``` r
.datom_set_add_record(x, record)
```

## Arguments

- x:

  A `datom_set`.

- record:

  A member record, already validated and checked for clashes.

## Value

`x`, one member longer.

## Details

The link goes through the shared factory, never inline, so no frame
holding a connection lands on its parent chain.
