# Check `project.yaml`'s Declared Format

The same reader-side check every other datom-owned document gets, pinned
to the config file's own ceiling (`.datom_project_schema`) rather than
the repo-wide one. Absent means v1, which is every repo written so far,
so no existing repo changes behaviour.

## Usage

``` r
.datom_check_project_schema(cfg, source, operation = c("read", "write"))
```

## Arguments

- cfg:

  Parsed `project.yaml` (a named list).

- source:

  Path of the config file, named in the refusal message.

- operation:

  What the caller was about to do. `"read"` (the default) is what
  connection construction passes – opening a connection is neither a
  read nor a write, and "this build cannot read" is literally true of
  the config file. `"write"` is for the set-write gates, which read this
  file to decide whether a write may proceed.

## Value

Invisible resolved version as an integer. Aborts otherwise.

## Details

**Why the file needs a declared format at all.** `project.yaml` carries
fields a writer must *obey*, not merely fields it may read:
`min_writer_version` already, and `mode` / `set` for a product repo. A
build that does not recognise such a field walks past it and acts as
though the repo had never asked for anything – so the file needs a way
to say "this repo needs a newer datom", and a number is that way.

**A number here, a vocabulary check there, and the two are not
interchangeable.** The vocabulary check that guards the manifest and
per-artifact metadata draws its power from those documents being
machine-written: an unrecognised key there *is* evidence a newer datom
wrote it. `project.yaml` is hand-edited – storage migrations, prefixes,
descriptions, private notes – so an unrecognised key is as likely a
typo, and refusing on one would block every write in the repo until
somebody found it. Never point the vocabulary check at this file; an
unrecognised key here stays tolerated, and there is a test that says so.

**This wrapper exists so the pairing of file and ceiling cannot be
forgotten.** A bare `supported =` argument at each call site is the same
shape as the artifact-kind predicate that was written out at four sites
and lost a tolerance at one of them. Callers pass the parsed config; the
ceiling is not theirs to choose.
