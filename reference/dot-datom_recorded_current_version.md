# The Version Storage Recorded for an Artifact's Current State

Picks the `version_history.json` entry that describes `metadata.json`,
and returns the `version` **recorded** on it.

## Usage

``` r
.datom_recorded_current_version(meta, history)
```

## Arguments

- meta:

  The artifact's parsed `metadata.json`.

- history:

  The artifact's parsed `version_history.json`, a list of entries, or
  `NULL`.

## Value

The recorded version string, or `NULL` when the history records nothing
usable – in which case the rebuilt row simply carries no version, rather
than a manufactured one.

## Details

**Never recomputed, and that is the point of this function existing at
all.** Hashing `metadata.json` here would reach for the identity code in
precisely the scenario a rebuild is for – a repo touched by a build
whose field classification differs from this one's – and publish a
`current_version` matching no version in the recorded history. An index
pointing at a version that does not exist is worse than the empty list
it replaced.

Which entry describes the current state is not simply the newest one.
History is prepended newest-first, but a write that reverts to content
already in the history appends nothing, so the current state can be an
older entry. The selection therefore narrows by recorded fields only:

1.  Entries whose `data_sha` equals the current document's. One match
    settles it – this is the revert case, and it is why the newest entry
    alone is wrong.

2.  Several matches means metadata-only versions of the same content;
    the one whose `timestamp` equals the document's `created_at` is the
    current one, since a version's history entry copies that field
    verbatim.

3.  Anything still ambiguous takes the newest candidate. That is a
    choice between two entries that both describe the current
    **content**, so the worst case is naming the wrong one of two
    versions of the same bytes.

**No match at all returns `NULL`, and it deliberately does not fall back
to the newest entry.** No match means the history does not record the
state `metadata.json` describes – a truncated or partly-synced history.
The newest entry there is a version of *different content*, so naming it
would be a wrong statement rather than a missing one, and a row already
tolerates carrying no version.
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
owns the inconsistency. This is the same trade the carry-forward rule
makes in `R/forward-compat.R`: a stale claim that outlives what it
described is worse than an absent one.
