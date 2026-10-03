# Does a Member Carry All the Labels Asked For?

Every key must be present and every value listed under it must be one
the member carries. So `tags = list(domain = "safety")` matches a member
tagged `domain = c("safety", "efficacy")` – narrowing by one label of a
multi-valued tag is the ordinary case, since multi-valued tags are the
point.

## Usage

``` r
.datom_member_has_tags(member, tags)
```

## Arguments

- member:

  A member record.

- tags:

  The filter map.

## Value

`TRUE` or `FALSE`.

## Details

**The member's labels are read through
[`.datom_tag_pairs()`](https://amashadihossein.github.io/datom/reference/dot-datom_tag_pairs.md),
not off the map**, so there is genuinely one access path to a member's
tag values and the duplicate-key hazard documented there cannot be
reintroduced here. A `member$tags[[k]]` read is the same
silent-first-match defect, and it fails in the direction that looks like
missing data: the member is reported not found under a label the
document says it carries.

The filter side is read by position for the same reason, even though
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
refuses a filter with duplicate keys before this runs.
