# Resolve the Third Argument of [`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md) to a Member Record

One accessor for the three shapes a caller holds, so a console call and
a loop use the same verb: a **name**, a **member record**, or a
**link**.

## Usage

``` r
.datom_member_record(members, member, tags = NULL, version = NULL)
```

## Arguments

- members:

  The set's member list.

- member:

  A name, a member record, or a `datom_link`.

- tags:

  Optional label filter.

- version:

  Optional version, or a prefix of one.

## Value

One member record.

## Details

The shape dispatch itself is
[`.datom_member_shape()`](https://amashadihossein.github.io/datom/reference/dot-datom_member_shape.md),
shared with
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md).
Only the **name** half is here, and it genuinely differs between the two
verbs: a name means "a member of this set" here and "an artifact in this
project's storage" there, so a shared lookup would search the wrong
thing on one of the two routes.

A record with no `fetch` on it is accepted, and that matters: it is the
payload shape – what a caller who built a member with
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
holds, and what stripping a read set's links produces. The accessor keys
on `id` and nothing else, which is what keeps this verb and
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
agreeing about what a member is.

`tags` and `version` narrow a **name**. Supplied beside a record or a
link they are refused rather than ignored, because ignoring them would
resolve a different version than the one asked for and report success.
