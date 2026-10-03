# The Commit Message a Set Write Uses

A set write commits `Update {name}`, which says nothing in `git log`.
When the object being written carries an edit log and the caller passed
no `message`, the default names what changed instead – every action in
the log, so a chained `update |> remove` produces one message describing
both.

## Usage

``` r
.datom_set_commit_messages(name, message, edits)
```

## Arguments

- name:

  The set's name.

- message:

  The caller's `message`, or `NULL`.

- edits:

  The edit log carried by the object being written, or `NULL`.

## Value

A list of `history` (a single line, or `NULL` to leave the existing
default in place) and `commit`.

## Details

Two messages, because they go to two places. The **subject** is recorded
as the version's `commit_message`, where one line is what
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
can show. The **commit** gets the subject plus the full list, with whole
versions rather than prefixes: git is the durable record, so
completeness belongs there rather than on screen.

An explicit `message` always wins, and a log of the wrong shape is
ignored rather than trusted – it is an attribute, so a caller can put
anything there.
