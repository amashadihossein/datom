# Group a Set's Members into a Navigable View

Groups members by the values of the label key(s) named in `by` and
returns a nested list whose leaves are the members' **links**, so
`dp$output$adsl(conn)` works and tab-completes.

## Usage

``` r
datom_structure_members(x, by, missing = "untagged")
```

## Arguments

- x:

  A `datom_set` from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

- by:

  Character vector of one or more label keys to group by, outermost
  first.

- missing:

  Branch name for members carrying no value for an axis key.

## Value

A nested list `length(by) + 1` levels deep: one level per axis, then the
member's own name holding its `datom_link`. An empty list for a set with
no members.

## Details

A pure function of `x` and the axis you ask for: nothing is stored, and
datom takes no position on which hierarchy is the right one. Ask for
`by = c("domain", "type")` and you get a different tree from the same
set, which is that design working rather than being worked around.

## One member, several branches

A member tagged `domain = c("safety", "efficacy")` appears under
**both** `safety` and `efficacy`, so the total number of leaves can
exceed the number of members. That is the point of labels over folders
rather than a quirk of this verb: a folder holds an item in exactly one
place, and a label does not.

## What is refused, and why nothing is dropped

Two requests abort, because the alternative in both cases is a member
the consumer cannot find and cannot see is absent:

- **Two members asking for one leaf name.** Two members may legitimately
  share a name at different versions, and if both carry the same label
  they ask for the same leaf. The abort names both and points at adding
  an axis – `by = c("type", "release")`. The set itself is entirely
  legal; only this projection of it is refused.

- **A `missing` bucket name that is also a real label value.** The
  bucket is a leaf name, so a set where some member genuinely carries
  `type = "untagged"` would merge the real branch into the bucket.
  Refused whatever the members happen to look like, so that whether the
  projection works does not depend on whether a member is currently
  missing the key.

A member that simply lacks the axis key is **not** refused and **not**
dropped: it goes under `missing`, named, because a named bucket is
visible and an omission is not.

## See also

[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
for the flat view,
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
to resolve one member by name.

## Examples

``` r
# Built by hand to show the shape; in practice `x` comes from
# datom_get_set(). adsl carries two domains, so it appears under both.
x <- structure(
  list(
    name = "study001-adam", project = "study001", version = NULL,
    data_sha = NULL, tags = NULL,
    members = list(
      list(
        id = list(project = "study001", name = "adsl", kind = "table",
                  version = strrep("a", 64)),
        tags = list(domain = c("safety", "efficacy"))
      ),
      list(
        id = list(project = "study001", name = "dm", kind = "table",
                  version = strrep("b", 64))
      )
    )
  ),
  class = "datom_set"
)

dp <- datom_structure_members(x, by = "domain")
print(names(dp))
#> [1] "safety"   "efficacy" "untagged"
print(names(dp$safety))
#> [1] "adsl"

# A leaf is a link: call it with a connection to resolve it.
print(dp$safety$adsl)
#> 
#> ── datom link 
#> • Points at: table "adsl" in project "study001"
#> • Version: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
#> • Tags: domain=safety|efficacy
#> ℹ Resolve it with `link(conn)`, using a connection to project "study001".
```
