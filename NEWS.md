# datom (development version)

This release adds a second kind of artifact -- a **set**, which is a citable list
of exact data versions -- and renames one key in the manifest to make room for it.
The rename is the only breaking change, and what it breaks is *discovery*, not
access. Read the first two sections before upgrading a shared repo.

See `vignette("citable-sets")` for what sets are for and how to build one.

## Before you upgrade: the manifest's artifact list is renamed **[breaking]**

`.metadata/manifest.json` and `.datom/manifest.json` now list artifacts under
**`artifacts`** rather than `tables`, and every entry carries a `kind`.

* **Existing repos keep working, and there is no manual migration.** A manifest
  written before this change carries no format number; datom reads that as
  version 1 and converts it. A read converts in memory and leaves the file alone,
  so a reader with storage access and no clone is never stuck. A write converts
  the file and records the format it reached, so a repo is never half in one shape
  and half in the other.
* **Upgrade everyone who shares a repo before anyone writes to it.** The
  compatibility above runs one way. After a single write from this version an
  older datom looks for the artifact list under a key that is no longer there, so
  `datom_list()` returns an empty frame and `datom_summary()` and `datom_status()`
  report zero -- **without an error**. `datom_read()` is unaffected: the data path
  never reads the manifest, so a collaborator who knows a table name and version
  can still read it. What they lose is the ability to see what the repo holds.
* A write that converts a repo now says so and names that consequence.
  `datom_validate(fix = TRUE)` converts the copy in storage too, which is worth
  knowing because it reads as a repair rather than as a format change.
* `datom_list()` gains a `kind` column, and its empty result gains
  `current_data_sha` (and `version_count` with `include_versions = TRUE`), so
  `rbind()` of two listings no longer fails when one is empty.
  `datom_summary()` gains `set_count`. `datom_status()`'s table count now counts
  tables rather than every artifact.
* Three return-value fields still named `tables` are **unchanged**:
  `datom_status()$tables`, `datom_validate()$tables`, and the per-table results
  from `datom_sync()`. Only the manifest key moved.

## Before you upgrade: a write is refused when this build cannot account for the repo

Every manifest and every per-artifact metadata document now declares a
`schema_version`. Stamping it mints no new version for anything.

A write stops **at the door** -- before any hashing, any local file write and any
commit, so a refusal leaves nothing half-written -- when this build meets a repo
it cannot fully account for: the repo declares a minimum datom version above this
one, the manifest declares a format this build does not know, or any document
carries a top-level field this build cannot classify.

* **Reads and writes respond differently to the same evidence, on purpose.** A
  reader that meets a manifest it cannot use warns once and rebuilds the listing
  from storage rather than reporting an empty repo. A writer in the same position
  refuses. A reader that limps still answers the question it was asked; a writer
  that limps produces a file nobody agreed on.
* A too-new **per-artifact** document is refused at any role, because nothing can
  rebuild it.
* **All of this binds 0.1.1 and later.** 0.1.0 has no schema check, no field
  check and no version floor, and none can be added to a build that has shipped.
  If a 0.1.0 writer exists in your group, upgrading it is the only remedy.
* A field this build does not recognise is **preserved** rather than deleted, in
  per-artifact metadata, manifest entries, the manifest top level and
  version-history entries. So a document written by a newer datom survives a
  round trip through an older one.
* `project.yaml` now declares its own format number, separate from the repo's, so
  a manifest format bump can never refuse a config whose shape never changed. An
  unrecognised key in that file is still tolerated.

## New: citable sets

A **set** is a named, versioned list of pointers at exact versions of other
artifacts, plus free-text labels. It stores no data of its own, and reading one
needs access to the set's own project only -- so a fifty-table product can be
citable by someone entitled to none of the tables. `vignette("citable-sets")`
walks the whole arc.

* **`datom_write_set()`** writes one. It needs a repo that declares
  `mode: product` and names its set in `.datom/project.yaml`; one repo owns one
  set. Re-writing identical content is a no-op: no commit, no version, no upload.
* **`datom_get_set()`** reads one back and returns references, not data, which is
  why the verb is `get`. Every member carries a `$fetch(conn)` link that pins the
  version it was read at -- a citation, not a subscription. A member that is
  itself a set comes back as a pointer, so read cost does not grow with depth.
* **`datom_member()`** declares one member. **`datom_assemble_set()`** and
  **`datom_add_member()`** build a set a member at a time, so a bad version is
  reported on the line that added it.
* **`datom_fetch_member()`**, **`datom_list_members()`** and
  **`datom_structure_members()`** get at members: the data, a row per member per
  label, or a view grouped by label. Labels are the navigation axis -- a name is
  not a unique key, since one table at two versions is a legal pair.
* **`datom_update_members()`** and **`datom_remove_members()`** edit a set that
  already exists. Neither writes anything: they hand the edited set back and the
  write is yours. Repointing reports what moved before you write it, keeps each
  member's labels, and mints no version when nothing has moved. Edits made
  together produce one commit message naming all of them.
* A `mode: product` repo can commit your own code and `renv.lock` in the **same
  commit** as the set, with `datom_write_set(include_paths = )`, so checking out a
  set version gives you the data pointers plus what produced them. A product repo
  refuses to onboard files -- it builds its artifacts rather than importing them.
* `datom_validate()` understands both kinds. A set is checked for members whose
  pinned versions still exist and for a recorded payload hash, without descending
  into members that are themselves sets. `fix = TRUE` can restore a set's payload
  from git when storage has lost it.
* Per-artifact metadata now records `kind`, which is part of a version's identity,
  so a table and a set can never share a version string. **Every existing table
  mints one extra version at its next write** because of it; the stored data is
  not re-uploaded, since the content hash does not move.

## New: committing your own content through datom

**`datom_repo_commit()`** and **`datom_repo_push()`** let a downstream package put
its code, lockfile or build state into the data repo without importing `git2r`.

`paths = NULL` means what `git add .` means, which is the **opposite** of what
datom's own writes do -- and that is the point: datom's own commits fire when
datom chose and must never sweep up work in progress, while these fire because
you asked. Commit is idempotent, push is convergent, and a no-op still pushes when
the branch is ahead. See `?datom_repo_commit` for what it will and will not sweep
in.

## Every version now records the commit that produced it

`datom_history()` gains a `commit_sha` column.

The value is worked out by datom, never supplied: from the commit it just made,
or recomputed from git history for a version that has none. Only the copy in
storage carries it -- your clone's copy is committed *inside* the commit that
would name it -- which is right, since the field exists for the reader who has no
clone.

**A version means content, not code**, and this is the part most likely to look
like a bug. Refactor a build script, re-run it, get identical data: no new version
is minted, and the recorded commit still points at an earlier one that does not
contain the code you are looking at. It names a commit that provably produces that
version, not every commit that could.

## Smaller changes

* Every artifact's metadata records a **`project`** field: the name the writing
  repo declares in its own config, not the label on your connection. Two people
  can label the same repo differently, and a citation has to mean one thing. No
  existing artifact gains a version for it.
* New **`datom_storage_read_json()`** on the storage extension API, for reading a
  JSON document out of a project's namespace by relative key.
* A repo whose manifest cannot be read is listed by rebuilding the index from
  storage, with one warning naming the upgrade, rather than reported as empty.
* Identity hashing now selects fields by an explicit list rather than by
  exclusion, so a field this build has never heard of no longer folds into the
  hash and reports a change on content that did not move. Every existing hash is
  unchanged ([#100](https://github.com/amashadihossein/datom/issues/100)).
* `.datom_check_git_current()` no longer compares against stale refs after a
  failed fetch ([#104](https://github.com/amashadihossein/datom/issues/104)).

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
