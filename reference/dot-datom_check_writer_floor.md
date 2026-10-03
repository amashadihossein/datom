# Refuse a Write This Repo Has Declared Too Old

A repo may state the lowest version of datom it accepts writes from. The
field is optional and lives in `project.yaml`; **absent means no
limit**, so no repo written so far changes behaviour.

## Usage

``` r
.datom_check_writer_floor(conn)
```

## Arguments

- conn:

  A `datom_conn` object.

## Value

Invisibly `NULL`. Aborts when the running build is older than the
declared floor.

## Details

It exists for the two cases the vocabulary check structurally cannot
see, because neither introduces a new field name: a change in what an
existing field *means*, and a block for a reason that is not about
format at all ("0.1.4 wrote bad hashes, do not let it write here"). A
version number is the right currency for both – the schema number cannot
carry them, since it does not move for a change that is reader-safe, and
a package version directly answers the question a refusal raises.

**The reading half ships even though nothing sets the field yet**, and
that ordering is the whole point: a build that does not look for the
field can never be bound by it. This is exactly why no released datom
can be stopped from writing – the looking has to be inside the build
being stopped. Setting the field is a separate, later mechanism, and it
owns the guard that whoever raises a floor must already satisfy it.

A value that will not parse as a version **aborts** rather than being
ignored. Treating a malformed floor as no floor would turn a typo in a
policy field into a silently disabled policy.
