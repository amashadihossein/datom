# Everything a Write Must Clear Before It Starts

The one entry sequence for every write route. Ordered, and the order
matters:

## Usage

``` r
.datom_check_write_entry(conn, artifact = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- artifact:

  Name of the single artifact this write touches, or `NULL` to check
  every artifact present in the clone.

## Value

Invisibly `NULL`. Aborts on any refusal.

## Details

1.  **The floor** – refuse if this repo has declared this build too old.

2.  **The manifest, read through the one shared reader**, which checks
    the declared format and then converts an older document in memory.
    Refusing a format from the future has to happen before the
    conversion, because there is no conversion step for a version this
    build has never heard of.

3.  **The shape the conversion reached.** If the artifact list is still
    absent after the chain has run, this document belongs to a lineage
    this build cannot produce – refuse rather than overwrite it in an
    older shape.

4.  **The vocabulary**, on the manifest's top level, on each of its
    artifact entries, and on each per-artifact metadata document this
    write will touch.

**Why step 3 is worded as "still absent after the chain" and not
"absent".** A current build meeting a pre-rename repo finds no artifact
list either, and a rule that refused on that would deadlock the very
upgrade it exists to protect: no repo could ever move forward. The
discriminator is not the key, it is whether the chain can *reach* the
shape. Note the deliberate asymmetry with the reader, which will one day
*rebuild* on this same condition – same evidence, opposite response,
because reads limp and writes stop.

**Which per-artifact documents get checked depends on the route**, which
is why `artifact` exists. A table write or a metadata-only sync touches
one artifact; the mirror-everything route touches all of them, and it is
the route with no artifact name in its arguments at all. Both cases
enumerate through
[`.datom_clone_artifact_names()`](https://amashadihossein.github.io/datom/reference/dot-datom_clone_artifact_names.md),
the same helper the mirror route itself uses, so the door cannot end up
inspecting a different set than the one that gets written.

**Callable more than once, and one route calls it twice.** Nothing here
mutates anything, so re-running it is free. The metadata-only route
pulls from the remote as its first act – after this check has already
read the clone – so a collaborator's newer document can arrive in that
pull; that route runs the sequence again afterwards. See
[`.datom_sync_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_sync_metadata.md).
