# Add This Edit's Rows to Whatever Log the Object Already Carries

**One log for every edit verb, appended to rather than replaced, and
that is what makes a chain of edits produce one honest commit message.**
With a verb owning its own attribute, `update |> remove |> write`
commits a message naming the repoints and silent about the removal – and
a destructive edit is the one a `git log` reader most wants named. So an
entry says which action it records, and a third editing verb costs an
action value rather than a new attribute.

## Usage

``` r
.datom_append_edits(x, rows)
```

## Arguments

- x:

  The edited object.

- rows:

  A data frame of new entries, carrying
  [`.datom_edit_log_fields()`](https://amashadihossein.github.io/datom/reference/dot-datom_edit_log_fields.md).

## Value

`x`, with the log extended.

## Details

The log is an **attribute** rather than a field, following the link's
carried member record: the write reads `tags` and `members` off a set
and nothing else, so an attribute cannot reach the payload by
construction.

Repointing a member and then removing it leaves **both** entries. That
is an honest history of the edits and slightly odd in a commit message;
collapsing them would mean one verb reasoning about the other's rows.

Three actions are written: `repoint` by
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md),
`remove` by
[`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md),
and `add` by
[`datom_add_member()`](https://amashadihossein.github.io/datom/reference/datom_add_member.md).
