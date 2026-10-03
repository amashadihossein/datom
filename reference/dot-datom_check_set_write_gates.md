# Refuse a Set Write the Repo Has Not Declared

Checks that read the clone's `.datom/project.yaml` directly, all of them
before anything is hashed or written:

## Usage

``` r
.datom_check_set_write_gates(conn, name = NULL)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

- name:

  The set name the caller supplied, or `NULL` to take the repo's
  declared one.

## Value

The resolved set name.

## Details

1.  The config's declared format must be one this build can read
    ([`.datom_check_project_schema()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_project_schema.md)).
    It runs first because the two checks below read fields *out of* this
    file: a future format that renamed or moved `set:` would make check
    3 report "this repo declares `mode: product` but names no set" and
    send the user to hand-edit a file that is already correct. An
    actionable-looking message that is wrong is worse than no answer.
    The connection-time gate does not make this one redundant – the file
    can be hand-edited or pulled between opening a connection and
    writing through it, which is the same reason the
    forward-compatibility door is re-run after a route's own pull.

2.  The repo must declare `mode: product`. A set written into a repo
    that does not is a set with no declared owner, which defeats the one
    below it too.

3.  The set's name must be the one the repo declares under `set:`. This
    is what makes "one repo = one set = one product" true rather than
    aspirational, and it is the precondition the self-reference refusal
    depends on – that refusal needs the set's own identity, and this is
    where it is established.

**Read from `project.yaml`, not from the connection.** Only
`min_writer_version` rides on a `datom_conn`; `mode` and `set` are read
here, at the one place that needs them, so nothing has to be threaded
through connection construction for two fields with one consumer. If a
later caller wants them on the conn it is a move with one call site to
update, rather than a decision to reopen.

**`datom_init_repo(mode = "product", set = <name>)` is what declares
both fields**, so the supported route into this check is a repo created
that way. It shipped inert one release earlier, on purpose: a build that
can *notice* the declaration has to exist before anything writes it, or
the declaration reaches installs that walk straight past it.
Hand-editing the file still works and some fixtures do it, which is also
what a repo created before that argument existed needs.
