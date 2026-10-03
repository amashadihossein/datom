# A Member's `id`, or an Abort Saying the Pointer Cannot Be Resolved

Checks only what resolution needs, and deliberately does **not** call
[`.datom_validate_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_members.md):
that is the write-side contract, and it refuses an `id` field a newer
datom added – which the read deliberately carries. Using it here would
make an unknown field readable but unfetchable, which is a reads-limp
violation arriving by a side door.

## Usage

``` r
.datom_member_id(record, what = "member")
```

## Arguments

- record:

  A member record.

- what:

  Noun for the message.

## Value

The `id` map.
