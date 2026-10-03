# Add One Member to a Set

Declares one member and appends it to a set – an empty one from
[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
or one read back with
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
– validating it immediately: the artifact must exist at the version
given, and its labels must be well formed. The member record is built
through the same path
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
uses, so a set assembled this way is byte-identical to the same set
passed as a list.

## Usage

``` r
datom_add_member(x, member, version = NULL, tags = NULL, conn = NULL)
```

## Arguments

- x:

  A `datom_set`, from
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
  or
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

- member:

  The member to add: an artifact name, a member record, or a link.

- version:

  The version to pin, when `member` is a name. Required there; refused
  beside a record or a link.

- tags:

  Optional named list of text labels for this member, when `member` is a
  name. Refused beside a record or a link, which carry their own.

- conn:

  A `datom_conn` from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
  for the project a **name** is looked up in. Required for a name; not
  used for a record or a link.

## Value

The set, one member longer, with its `version` and `data_sha` emptied
and the addition appended to its `datom_edits` attribute – or unchanged,
when the member was already in it with the same labels.

## Naming a member

`member` accepts the three shapes a caller holds, and the second and
third are not merely convenient:

|  |  |
|----|----|
| What you pass | What it means |
| a name | look this artifact up through `conn` |
| a member record | use it as given – from [`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md), or from a set read back |
| a link | use the member it points at – `x$members[[i]]$fetch`, or a leaf of [`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md) |

**A name is looked up in one project's storage**: the project `conn` is
for. A set holds no connection, so a name always needs `conn`, whichever
project it is in. A record or a link carries its own resolved pointer
and needs no connection at all:

    datom_assemble_set(conn_a) |>
      datom_add_member("dm", v1, conn = conn_a) |>      # this project, by name
      datom_add_member("ae", v2, conn = conn_b) |>      # another project, by name
      datom_add_member(datom_member(conn_b, "vs", v3))  # another project, as a record

**A link is how a consumer cites what they used.** Someone holding only
a projection of a set – a leaf of
[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
– can add exactly the version they read to a new set, without
reconstructing the pointer.

`version` and `tags` describe a member given by **name**. Beside a
record or a link they are refused rather than ignored, because a record
already carries its own version and labels and a second set of them
could only disagree.

## Why the version is required

A member pins one exact version, and there is no way to ask for
"whatever is current". Inferring current would make a build script
produce a **different set** on each run from byte-identical source.
Pinning is what makes the artifact immutable; requiring the pin is what
makes the code reproducible. List versions with
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md).

## Every add is an edit

Adding a member behaves like
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
and
[`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md),
whether the set was just assembled or read back:

- **Nothing is written.** The set is stored only when you pass the
  result to
  [`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md),
  and the call says so.

- **`version` and `data_sha` are emptied**, because they described the
  payload the set was read as. A set never written has neither.

- **The addition is recorded**, so the write's default commit message
  says `add 1 member` beside any repoints or removals made on the same
  object. A freshly assembled set's first write therefore names every
  member it adds.

- **The new member gets a `$fetch` link**, like every member of a set
  read back.

## Adding the same member twice

The two cases differ, and they differ the same way they differ at the
write:

- **The same version with the same labels** is skipped, with a note. The
  write drops an exact repeat anyway, so refusing here would make this
  verb stricter than the equivalent list –
  `Reduce(datom_add_member, records, init = x)` over a generated list
  that happens to repeat would fail where it works today.

- **The same version with different labels** aborts. One version of one
  artifact is one member holding one set of labels, and merging or
  choosing between two sets would guess. The write refuses this too;
  here it names the line that introduced it.

So the member count a set reports is the count the write will produce.
Two different **versions** of one artifact are two members, and both are
kept.

## See also

[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
to start a set,
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
to read one back,
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
to build a record on another connection,
[`datom_update_members()`](https://amashadihossein.github.io/datom/reference/datom_update_members.md)
and
[`datom_remove_members()`](https://amashadihossein.github.io/datom/reference/datom_remove_members.md)
for the other edits.

## Examples

``` r
# Adding by name needs a live connection, so the runnable example lives on
# datom_assemble_set(), which shows the whole pipe.
print(names(formals(datom_add_member)))
#> [1] "x"       "member"  "version" "tags"    "conn"   
```
