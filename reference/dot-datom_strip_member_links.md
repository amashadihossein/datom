# Drop the `$fetch` Link a Read Puts on Every Member

The one step that makes read-modify-write possible. A member record is
payload-shaped – exactly `id` plus optional `tags` – and
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
adds a callable `fetch` to each one, which both
[`.datom_validate_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_members.md)
and the sv1 encoder refuse. Removing it here means neither of them needs
a carve-out for a field that must never reach a payload.

## Usage

``` r
.datom_strip_member_links(members)
```

## Arguments

- members:

  A member list.

## Value

The member list with any callable `fetch` element removed.

## Details

**Only a function is dropped.** A hand-built `fetch = "junk"` is left in
place so the validator reports it; stripping by name would turn a typo
into a silent success.
