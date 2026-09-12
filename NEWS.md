# datom (development version)

## The manifest's artifact list is renamed **[breaking]**

`.metadata/manifest.json` and `.datom/manifest.json` now list artifacts under
**`artifacts`** rather than `tables`, and every entry carries a `kind` field
(`"table"` for everything datom writes today). One namespace typed by `kind`,
rather than a second node beside the first: storage keys are `{name}/...`
whatever the artifact is, so two artifacts sharing a name would write the same
objects, and a single keyed list makes that a collision instead of a state
something has to police.

* **Existing repos keep working, and no manual migration is needed.** A manifest
  written before this change carries no format number, which datom reads as
  version 1 and converts as it goes. A **read** converts in memory and leaves
  the file untouched, so a reader with storage access and no git clone is never
  stuck. A **write** converts the file itself, then records the format it
  reached -- so a repo is never half in one shape and half in the other, and the
  counters cover every artifact that was already there rather than only the one
  just written.

* **UPGRADE EVERYONE WHO SHARES A REPO BEFORE YOU WRITE TO IT.** The compatibility
  above runs one way: a new build reads an old repo. The reverse does not hold.
  After a single write from this version, the manifest declares the new format,
  and an older datom looks for the artifact list under a key that is no longer
  there -- so `datom_list()` returns an empty frame and `datom_summary()` and
  `datom_status()` report zero, **without an error**. `datom_read()` is
  unaffected: the data path never reads the manifest, so a collaborator who
  knows a table name and version can still read it. What they lose is the
  ability to discover what the repo holds.

  A write that converts a repo now says so and names that consequence.
  `datom_validate(fix = TRUE)` converts the copy in storage too, which is worth
  knowing because it reads as a repair rather than as a format change.

* **`datom_list()` gains a `kind` column**, on populated rows and on both of its
  empty results. Its empty results also gain **`current_data_sha`**, which
  populated rows have always carried and they had always omitted -- so
  `rbind()` of two listings no longer fails when one of them is empty. Both
  columns arrive together, in this one release, rather than the second one
  costing a later break of its own. With `include_versions = TRUE` the empty
  result carries `version_count` as well, so the two forms of the call each
  agree with themselves.

* **`datom_summary()` gains `set_count`** beside `table_count`, and prints it.
  `table_count`, `total_versions` and `total_size_bytes` keep the meanings they
  had: tables only. No existing counter changed what it counts.

* **`datom_status()`'s table count now counts tables**, not every artifact, so
  the number keeps matching the label it prints.

* Three return-value fields still named `tables` are **unchanged**:
  `datom_status()$tables`, `datom_validate()$tables` and the per-table results
  from `datom_sync()`. Only the manifest key moved.

## Format numbers, and the write that gets refused

* **Every manifest and every per-artifact metadata document now declares a
  `schema_version`.** Stamping it costs nothing: it takes no part in version
  identity, so no artifact gains a version for being stamped. A manifest created
  from scratch declares the format immediately, before it holds anything.

* **A write into a repo whose format this build does not know is refused at the
  door** -- before any hashing, any local file write and any commit, so a
  refusal leaves nothing half-written. This is the damaging direction and no
  reader-side check can cover it, because the older build is the one writing.
  The refusal covers every write route, including the one that mirrors the
  whole manifest to storage without touching a single artifact.

* The refusal message now says whether the build cannot *read* or cannot *write*
  the format it met.

## A field this version does not recognise is no longer deleted

Writing a table rebuilds its metadata document and its row in the manifest from
scratch. Until now that quietly discarded any field the running version had
never heard of -- which is what a document written by a newer datom looks like
after you pull it. Such a field now survives the rewrite, wherever it sits: a
table's own metadata document, its row in the manifest, the fields beside the
manifest's artifact list, and an entry in its version history.

* **Only unrecognised fields are carried.** A field datom does know still
  behaves as before, including going away when the write does not set it. So a
  table that was imported from a file and is later written straight from a data
  frame stops claiming a source format, rather than keeping a stale one.

* **Version identity is unaffected.** A carried field is attached after the
  version has been computed, so a document holding one mints no new version by
  itself and no existing version moves.

* Nothing changes for a repo whose documents this version fully understands,
  which is every repo it wrote itself.

## A write stops when this version cannot account for the repo

Carrying an unfamiliar field forward keeps a write from destroying information.
It does not make the write correct: this version would still recompute the
document's version identity from the fields it knows, reaching a different
answer from the version that wrote it, on content that never moved. So the write
now stops instead. Reads still degrade gracefully where they can -- **reads limp,
writes stop.**

Everything below runs before any hashing, any local file write and any commit, so
a refusal leaves nothing half-written. It covers every route that writes,
including the two that are easy to overlook: the one that mirrors the whole
manifest to storage without touching a single artifact, and
`datom_validate(fix = TRUE)`, which reads as a repair but publishes this repo's
documents to storage just the same. Nothing changes for a repo whose documents
this version fully understands, which is every repo it wrote itself.

* **A top-level field this version cannot classify refuses the write**, naming
  the field. Checked on the manifest, on each of its artifact entries, and on
  each artifact's own `metadata.json` -- always the copy in your git checkout,
  which is where a colleague's newer document arrives when you pull. `custom` is
  classified as a whole, so your own metadata keys are never affected however
  exotic.

  This is the check that catches an **added or renamed** field, where the format
  number deliberately does not move. It is the reason a release that adds any
  field to a datom document asks everyone who writes to that repo to upgrade,
  cosmetic additions included -- a false refusal costs one person an install, a
  miss costs corrupted data.

* **A repo may declare the oldest datom it accepts writes from.** Set
  `min_writer_version` in `.datom/project.yaml` and an older writer is refused,
  naming the version needed. The field is optional and **absent means no limit**,
  so no existing repo changes behaviour. It covers the two cases the field check
  structurally cannot see, because neither introduces a new name: a change in
  what an existing field *means*, and a block for a reason that is not about
  format at all.

  Reading the field ships now even though nothing sets it yet, because the
  looking has to be inside the version being stopped. A purpose-built way to
  raise it comes later; a hand-edited value works in the meantime.

* **A manifest whose artifact list this version cannot reach is not
  overwritten.** If the list is still missing after the format conversion has
  run, the file belongs to a lineage this version cannot produce, and replacing
  it with a shape this version invented would be worse than stopping. A repo
  written before the rename is not affected: the conversion reaches its list, so
  the forward path proceeds as it always did.

* **All of these bind from this version forward only.** 0.1.0, 0.1.1 and 0.1.2
  have none of them and none can be added to a version already released. If you
  share a repo with an older install, upgrading it is the only protection there
  is.

## A repo whose index this version cannot read is still listed, not reported empty

The mirror of the section above, on the reading side. A manifest whose artifact
list this version cannot use looks exactly like a repo with nothing in it --
`datom_list()` returns no rows, `datom_summary()` and `datom_status()` report
zero, and none of them errors. That is now replaced by a reconstruction and a
warning.

* **The artifact index is rebuilt from storage** when the list is missing after
  the format conversion has run, or when the manifest declares a format newer
  than this version understands. Every fact in the manifest is also recorded in
  the per-artifact documents it summarises, so it can be reassembled: one
  storage listing plus each artifact's own `metadata.json` and
  `version_history.json`.

* **It says so, once**, naming which copy of the manifest was rebuilt and
  pointing at the upgrade. A repair that succeeds silently is itself a silent
  degradation.

* **Nothing is written.** The reconstruction lasts for that session only, on both
  copies of the manifest and at every role -- a read that quietly rewrote your
  repo's index would be a larger surprise than the one it is fixing. The
  recorded copy is repaired by the next ordinary write.

* **Reported versions are the recorded ones.** Each rebuilt row takes its version
  from the artifact's own history rather than recomputing a hash, so a rebuilt
  listing can never point at a version that does not exist.

* **Two things still fail rather than being reconstructed.** A manifest that will
  not parse, or that declares something which is not a format number at all,
  keeps failing visibly -- reconstructing it would turn a damaged repo into a
  plausible-looking one. And an artifact's own `metadata.json` is never rebuilt
  from anything: it is the source of truth, so a document declaring a format this
  version does not understand still stops the read.

* **A write meeting either condition still refuses** (see the section above).
  Same evidence, opposite responses: a reader that carries on gives one person
  one session's answers, while a writer that carries on leaves the repo wrong for
  everybody.

* **Imported tables now record their source format in their own metadata**, not
  only on the manifest row -- which is what makes that field recoverable when the
  index is rebuilt. It does not participate in version identity, so no existing
  version changes.

## An artifact's metadata now says which kind of artifact it is

Every `metadata.json` carries `kind`, which is `"table"` for everything a table
write produces. The manifest row has carried it since the rename above; the
artifact's own document is where a check has to read it, because the manifest can
lag a partial write while that document cannot.

* **`kind` is part of the version identity**, and that is the whole point of it.
  Leaving it out is the alternative, and it lets a table and a set whose other
  identifying fields agree mint the same version -- at which point one version
  string names two artifacts.

* **So the first write of each existing table after upgrading records one extra
  version, on content that has not changed.** datom detects a change by
  recomputing the document's identity and comparing it with the recorded one, and
  a document that has gained an identity field hashes differently. This is
  accepted rather than worked around.

  The cost is bounded and in the harmless direction: the content hash
  (`data_sha`) does not move, so the storage address does not move either -- the
  stored parquet is reused, nothing is re-uploaded, and no earlier version is
  altered or invalidated. It happens once per table, at that table's next write.
  A table you never write again is never touched.

# datom 0.1.2

Test-only fix for the CRAN check failures reported against 0.1.1. No package
code changed and no user-facing behaviour changed.

* Test fixtures no longer assume the machine's default git branch is named
  `master`. Fixtures that build a throwaway repository and push it to a local
  stand-in remote spelled the branch out as `refs/heads/master`, but
  `git2r::init()` honours git's `init.defaultBranch` setting -- so on a machine
  configured for any other name the push named a branch that had never been
  created, and 26 tests failed during setup. Branch names are now read from the
  fixture repository. datom's own `.datom_git_push()` already derived the branch
  that way and was unaffected.

# datom 0.1.1

Initial CRAN release. `datom` provides version-controlled data management for
reproducible scientific and clinical workflows — tables are tracked as code in
git while actual data lives in cloud storage (S3) or a local filesystem backend.

datom is experimental: the API may change without a deprecation cycle until it
reaches a stable release.

datom requires R >= 4.1.0.

## Table identity: the `datom-cv1` canonical hash

Table identity is defined by a canonical hash of a table's **values**
(`datom-cv1`), not by the bytes of its parquet serialization. Hashing the
serialization tied identity to the writer: an `arrow` upgrade or a different
compression default produced different bytes for identical data, and therefore
a spurious new version. See
`vignette("design-version-shas")` for the model and the identity decisions.

* **Pre-release `data_sha` values change, and there is no migration path.**
  Any table written by a pre-release build carries a `data_sha` computed by the
  old algorithm. Those values are not recomputed, converted, or reconciled —
  pilots should re-onboard their data.
* Three SHAs are now recorded per table: `data_sha` (content identity),
  `metadata_sha` (the version you pass to `datom_read(version = )`), and
  `parquet_sha` (the stored object's SHA-256, verified on read before parsing).
* `metadata.json` gains `hash_algo`, `parquet_sha`, and `column_hashes` — an
  ordered per-column digest index from which `data_sha` can be re-derived
  without downloading data.

## Deliberate narrowings

Three capabilities were narrowed on purpose relative to pre-release behaviour.

* **List and exotic columns are refused.** A column must be a supported atomic
  type; list columns and exotic classes now abort the write with actionable

  advice. See `datom_check_hashable()` for a pre-flight check.
* **`datom_sync()` accepts only allowlisted formats.** Flat tabular files only
  (csv, tsv, parquet, sas7bdat, xpt, sav, dta, xls, xlsx). Read unsupported
  formats yourself and pass the data frame to `datom_write()`.
* **Internal `sort_columns` / `sort_rows` removed.** Row and column order are
  significant; sort explicitly before writing if order should not matter.

## Full API

See the [reference index](https://amashadihossein.github.io/datom/reference/)
for the complete exported surface at 0.1.0.
