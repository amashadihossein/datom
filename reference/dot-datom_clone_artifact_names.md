# The Artifacts Present in the Local Clone

Enumerates the artifact directories in the git checkout by the one
signal that identifies them: a directory holding a `metadata.json`.
Deliberately independent of the manifest, so it still answers correctly
when the manifest is the document under suspicion.

## Usage

``` r
.datom_clone_artifact_names(conn)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

## Value

Character vector of artifact names, possibly empty.

## Details

Two callers, and they must agree. The data-side metadata sync mirrors
exactly these artifacts to storage, and the write-entry check inspects
exactly the documents that route is about to write – so discovering them
twice, in two spellings, is how the door ends up checking a different
set than the one that gets written.

The directory filter is the pre-existing one: dotfiles out, plus the
fixed list of non-artifact directories a joint repo carries (`R/`,
`tests/`, `renv/`, and so on). It is a convenience rather than the
discriminator – `metadata.json` is what actually decides – which is why
a foreign directory not on the list is tolerated rather than misread
(R14.2).
