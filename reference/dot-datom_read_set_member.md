# Normalize One Member Record Read Back from a Payload

Normalizes representation in `id` and `tags`, then makes the one refusal
the read owns: an `id` field that is not a single non-empty string after
normalization aborts as a malformed document, naming the member.

## Usage

``` r
.datom_read_set_member(m, at, name)
```

## Arguments

- m:

  One parsed member record.

- at:

  Position label used in error messages, e.g. `"members[[2]]"`.

- name:

  The set's name, for error messages.

## Value

The member record, normalized.

## Details

**Why `id` is refused where a tag value is tolerated.** `id` values are
spliced into storage keys and compared against project names, and
[`.datom_validate_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_members.md)
enforces that contract on **write only** – so the read is the only place
a payload's `id` is ever checked. Normalizing without refusing would
silently accept a document
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
cannot produce, and a caller comparing a list against a string would
conclude that a member of this project belongs to another one.

Fields outside the four are left alone rather than refused: a newer
datom may have added one, and this build never reads it.
