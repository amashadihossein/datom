# Which Members Does This Call Refer To?

The plural selector both edit verbs share.
[`.datom_find_member()`](https://amashadihossein.github.io/datom/reference/dot-datom_find_member.md)
resolves exactly **one** member and aborts on an ambiguous name, which
is right for a fetch and only half of what an edit needs: an edit
legitimately acts on many.

## Usage

``` r
.datom_select_members(
  members,
  member = NULL,
  tags = NULL,
  version = NULL,
  version_arg = "version"
)
```

## Arguments

- members:

  The set's member list.

- member:

  A name, a member record, a `datom_link`, or `NULL` for all.

- tags:

  Optional label filter.

- version:

  Optional version, or a prefix of one.

- version_arg:

  The calling verb's name for `version`, for messages.

## Value

An integer vector of positions in `members`, never empty.

## Details

Three routes, and the difference between them is how many members they
can return:

|                    |                                                  |
|--------------------|--------------------------------------------------|
| What arrives       | What comes back                                  |
| no `member`        | every member, narrowed by `tags` and `version`   |
| a name             | exactly one, aborting when the name is ambiguous |
| a record or a link | exactly the member carrying that `id`            |

**An explicitly named member that is ambiguous aborts**, and that is not
in tension with the caller who sweeps: a sweep can honour "refresh
everything" while skipping a name it cannot choose between, whereas a
caller who named one member asked for something that cannot be done, so
it is a user error and the narrowing arguments are what resolve it. The
abort comes from
[`.datom_find_member()`](https://amashadihossein.github.io/datom/reference/dot-datom_find_member.md)
rather than from a second copy of that message.

`tags` and `version` narrow a **name** or a sweep. Supplied beside a
record or a link they are refused rather than ignored, because ignoring
them would act on a different member than the one asked for and report
success.
