# Which of the Three Shapes a Member Argument Arrived In

A caller naming one member holds one of three things, and every verb
that takes a member accepts all three: a **name**, a **member record**
(what
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
returns, and what stripping a read set's links produces), or a **link**
(a member's `fetch` element, or a leaf of
[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)).

## Usage

``` r
.datom_member_shape(member, arg = "member")
```

## Arguments

- member:

  The value the caller passed.

- arg:

  Argument name for the message.

## Value

A list of `shape` (a phrase naming what arrived) and `record` (the
member record, or `NULL` when a name arrived).

## Details

This is the shape dispatch alone, deliberately without the lookup. What
a **name** means differs by verb – to
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
it is a member of the set already in hand, to
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md)
it is an artifact to look up in the project's storage – so handing the
name back to the caller is what lets one dispatch serve both without
either searching the wrong thing.

The refusal of `tags` / `version` beside a record or a link is left to
each caller too: both refuse, and the reason differs enough to word
differently (narrowing a search versus declaring a member twice).
`shape` is the phrase to name it by, so the two messages at least agree
on what the caller passed.
