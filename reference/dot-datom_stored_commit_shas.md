# The `commit_sha` Storage Already Holds, by Version

**Nothing there and could not look are separate answers, and only one of
them is safe to pass over in silence.** The first write of an artifact
has no stored history, which is ordinary and silent. A stored copy that
exists and will not read is the opposite: the values only storage had
are now unknown, and the caller is about to replace that file wholesale
– so an entry git cannot attribute loses a good value. Collapsing the
two into "no known values" makes the loss invisible in exactly the case
where it is unrecoverable, which is why this returns the distinction
rather than just a map.

## Usage

``` r
.datom_stored_commit_shas(conn, name)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Artifact name.

## Value

A list with `shas` (named character vector, `commit_sha` named by
version, empty when there are none) and `unreadable` (`TRUE` when
storage holds a copy this call could not read).

## Details

The existence probe is what separates them. Its own failure counts as
*could not look*, never as absence: an unreachable store cannot report
that a file is missing.

A stored copy that reads but holds no usable pair is an absence, not a
failure – the document was inspected and had nothing to contribute.
