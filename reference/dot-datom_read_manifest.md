# Read a Manifest and Check Its Schema Version

The single manifest read. Every reader that takes a manifest *into*
datom goes through this, so the compatibility check happens once and
cannot be softened by a caller's error handling.

## Usage

``` r
.datom_read_manifest(
  conn,
  scope = c("storage", "clone"),
  operation = c("read", "write")
)
```

## Arguments

- conn:

  A `datom_conn` object.

- scope:

  `"storage"` for the copy in data storage (`.metadata/manifest.json`),
  `"clone"` for the git-tracked copy (`.datom/manifest.json`). Both
  exist; they can differ, and which one a caller wants is a real choice
  rather than a default.

- operation:

  What the caller is about to do with the document – `"read"` (default)
  or `"write"`. Passed through to
  [`.datom_check_schema_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_schema_version.md),
  where it only selects a word in the refusal message, so that a write
  stopped at the door does not report the format as one this build
  "cannot read".

## Value

A list with:

- `ok` – `TRUE` when the manifest was read and parsed.

- `absent` – `TRUE` only when the document is *known* not to exist. That
  is decided for `scope = "clone"`, where testing a local path is free.
  For `scope = "storage"` it is always `FALSE`, meaning "not known to be
  absent": separating a missing object from an unreachable store would
  cost an extra request on every read and no caller distinguishes them.

- `manifest` – the parsed document **in current shape**, or `NULL` when
  `ok` is `FALSE`. A document written in an older shape is converted in
  memory on the way through
  ([`.datom_manifest_upgrade()`](https://amashadihossein.github.io/datom/reference/dot-datom_manifest_upgrade.md));
  one whose artifact list this build cannot reach is reconstructed from
  storage
  ([`.datom_rebuild_manifest()`](https://amashadihossein.github.io/datom/reference/dot-datom_rebuild_manifest.md)).
  Neither modifies the file on disk or in storage. So no caller ever
  sees a pre-current shape and none needs a fallback for one.

- `error` – the condition that stopped the read, or `NULL`. The whole
  condition rather than its text, so a caller can re-signal the original
  failure unchanged instead of manufacturing a look-alike.

- `declared` – the version the document declared **before** conversion,
  or `NA_integer_` when nothing was read. Held so a caller that goes on
  to write the converted document can say the format moved, without
  re-deriving the comparison or reading the file twice.

## Details

Two kinds of failure, handled deliberately differently:

- **An IO failure is returned as data** (`ok = FALSE`), because each
  caller has its own policy:
  [`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
  and
  [`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
  abort,
  [`datom_status()`](https://amashadihossein.github.io/datom/reference/datom_status.md)
  reports the manifest unavailable and carries on, and the clone readers
  fall back to an empty manifest when the file does not exist yet.

- **A schema refusal is thrown**, so the "upgrade datom" message reaches
  the user intact. Placed inside a caller's `tryCatch` it would be
  reworded as "could not read manifest" at two sites and downgraded to a
  warning at a third. Throwing from in here means there is no handler
  for a caller to put it inside.

**And one document that is not a failure at all.** When the artifact
list is missing from where this build looks for it – either because the
format is newer than this build knows, or because the key is simply not
there after the conversion has run – the index is **reconstructed from
storage** and a warning says so. The manifest summarises documents that
each hold the same facts, so it is the one datom-owned file with
something to rebuild it from. A **writer** meeting either condition is
refused instead
([`.datom_check_write_entry()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_write_entry.md)):
reads limp, writes stop.
