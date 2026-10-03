# Refuse the File-Import Path on a Product Repo

A `mode: product` repo **builds** its artifacts: derived tables written
from data frames, and one set collecting them. It never onboards source
files, so the two import verbs refuse instead of answering. Before this
they answered unhelpfully – `input_files/` exists and is empty on such a
repo, so the scan reported "no files found" and handed back a zero-row
frame, which describes a repo with nothing to import rather than a repo
that does not import.

## Usage

``` r
.datom_refuse_import_on_product(verb, context)
```

## Arguments

- verb:

  Name of the sync verb being refused, for the message.

- context:

  What
  [`.datom_sync_context()`](https://amashadihossein.github.io/datom/reference/dot-datom_sync_context.md)
  read, so one call makes one gated parse.

## Value

Invisibly `NULL`. Aborts with class `datom_import_on_product` when the
repo declares `mode: product`.

## Details

**Read from the file, not from the connection**, and the rule behind
that is worth carrying: a check that **authorises a write** must see the
config as it is *now*, because a hand edit or a pull can replace it
after the connection was built. Only
[`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md),
which reports rather than decides, reads the mode off the connection. A
future site applies the same test: does it authorise a write? Then it
reads the file.

**Three steps in one place, and the middle one is easy to leave out.**
Parsing this file makes this a new *gated* parse: every site that reads
`.datom/project.yaml` checks its declared format first, or a build that
cannot interpret the file acts on fields it has misread. Skipping that
step here would reopen exactly that hole, on a path that writes.

**Called from both sync verbs, not only the first.**
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
takes a manifest data frame, so a caller can hand it rows that a
refusing
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
would never have produced.

**Above the input-file scan, never in its empty branch.** A product repo
with a file dropped into `input_files/` by accident would otherwise be
imported, which is the thing this exists to prevent; the unhelpful no-op
only happened when the directory was empty.

Both verbs have a set route on a product repo, reached by passing
`sources =`, so the message names that route rather than only the write
verbs.
