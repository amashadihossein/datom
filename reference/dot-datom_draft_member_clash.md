# Is This Member Already in the Set, and Is It the Same Member?

Answers the question the write answers twice, one step earlier, so a
repeat lands on the line that introduced it.

## Usage

``` r
.datom_draft_member_clash(members, record)
```

## Arguments

- members:

  The set's members so far, with their links stripped.

- record:

  The record about to be added.

## Value

A list with `status` – `"new"`, `"duplicate"` or `"conflict"` – and, for
the last two, `at`: the position of the member already in the set.

## Details

**Both of the write's rules are here, and they are deliberately
different rules.**
[`.datom_order_set_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_order_set_members.md)
drops an **exact** repeat – same `id` *and* same tags – silently,
because the digest it dedupes on covers tags. The same `id` with
**different** tags survives that and is then refused by
[`.datom_check_set_payload()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_set_payload.md),
because merging the labels and picking one entry both guess. So an exact
repeat is a duplicate to skip, and a same-version disagreement is an
error.

**The comparison uses the write's own two mechanisms rather than
restating them**: the `project` / `name` / `version` key the payload
check keys on, and the `datom-sv1` member digest the dedup keys on.
[`identical()`](https://rdrr.io/r/base/identical.html) on the two
records is the spelling to avoid, and it fails in the direction that
refuses working input: the encoder sorts a tag map's keys and encodes
each value as a sorted, deduplicated **set**, so `domain = c("a", "b")`
and `c("b", "a")` are one member to the write and to the digest, while
[`identical()`](https://rdrr.io/r/base/identical.html) reads them as a
disagreement and aborts.

That is also why nothing needs tidying first. Every spelling the write's
tidy step collapses is a spelling the digest is already blind to, so a
record can be compared – and stored in the set – exactly as the caller
supplied it.
