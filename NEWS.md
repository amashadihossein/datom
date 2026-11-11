# datom (development version)
* **Upgrade everyone who writes to a repo at the same time.** A write by datom
  0.2.0 or earlier that stops after its push leaves a version with no data
  file, and an upgraded teammate's next write then publishes it, so its reads
  fail. A project such a write has already broken is not rescued: a re-run or
  `datom_validate(fix = TRUE)` can still leave its readers failing (#155).

* **A command that stops partway now finishes when you run it again.** Before,
  a `datom_write()` that broke between its push and its upload left a version
  whose reads failed for good, and nothing could repair it. Now
  `datom_write()`, `datom_write_set()`, `datom_sync()`,
  `datom_validate(fix = TRUE)` and `datom_init_repo()` can stop at any step,
  on a dropped connection or Ctrl-C, and the same call, or the fix its message
  names, finishes the job; each step is tested that way. Every write first
  pulls teammates' commits and finishes its own unfinished version. When two
  people's writes clash only in the project's manifest, datom rebuilds it and
  finishes the merge itself. Readers never see a partly written version, and
  where datom cannot be sure, it stops before changing anything and says what
  to run. The data file now goes into storage first, so a write stopped before
  its commit can leave a data file no version names (#155, "If a write stops
  partway" in `?datom_write`).

* **Breaking:** `datom_write()` refuses a missing value (`NA`), `NaN` or `Inf`
  anywhere in custom metadata: none of them reads back as written, so lookups
  by version failed. Leave the field out (#155, `?datom_write`).

* **Breaking:** datom's own files (`metadata.json`, `version_history.json`,
  `set.json`, `.datom/manifest.json`) are no longer edited by hand. A write of
  that table or set undoes such an edit as unfinished work, other writes stop
  on it, and `datom_write(conn, name =)` no longer commits one: it publishes
  what is committed, and stops on an uncommitted change. Change custom
  metadata with
  `datom_write(conn, data, name, metadata = )` (#155).

* **Breaking:** a write and `datom_sync()` now stop, changing nothing, when
  another table or set has unfinished work, and name
  `datom_validate(fix = TRUE)`. `datom_repo_commit()`,
  `datom_repo_attach_governance()` and `datom_repo_set_data_store()` never
  commit a datom write that stopped before its own commit (#155,
  `?datom_repo_commit`).

* **Breaking:** `datom_sync()` with `continue_on_error = TRUE` no longer always
  gets through every file. It stops after a table whose write failed once it
  had changed the clone (written its files, or committed), or whose write held
  back the manifest; the tables after it come back `"skipped"`, and the message
  says what to run before the same call, with the same preview, finishes them
  (#155, `?datom_sync`).

* **Breaking:** a merge datom did not start (of a local branch, say) stops every
  datom command until you run `datom_pull(conn, finish_merge = TRUE)` or
  `git merge --abort` (#155, `?datom_pull`).

* **Breaking, for scripts that match messages:** the stops for another table or
  set's unfinished work share one class, `datom_unfinished_work` (a blocked
  pull keeps `datom_pull_blocked` too), and every stop before anything is
  published says "Nothing was published.". `datom_init_repo()` in a folder that
  already holds a project refuses before touching the git repo
  (`datom_init_folder_taken`; with `create_repo = TRUE` it no longer creates a
  GitHub repo first), and after a stop past its push it names the repair
  (`datom_init_manifest_failed`). `datom_validate(fix = TRUE)` now lets the
  repair's stops through as errors (a merge in progress, a failed fetch, a
  refused push, a set payload storage will not take) instead of turning them
  into an alert and `fixed = FALSE`; a failure publishing one artifact still
  gives `fixed = FALSE` (#155, `?datom_init_repo`, `?datom_validate`).

* `datom_validate(fix = TRUE)` always runs the repair, which now puts back
  datom's files an interrupted write left uncommitted, pulls, pushes commits
  GitHub lacks, and publishes every table and set. `datom_validate()` reports
  a new status, `manifest_mismatch_s3` (#155, `?datom_validate`).

* `datom_sync_manifest()` compares with the last commit, and has a new status,
  `unpushed`, for a table saved but not pushed; `datom_sync()` finishes it
  (#155, `?datom_sync_manifest`).

* A write with nothing to save no longer pushes your own unpushed commits.
  `datom_repo_push()`, `datom_repo_commit()`, `datom_repo_attach_governance()`
  and `datom_repo_set_data_store()` say when the commits they push hold a datom
  version readers cannot see yet (#155).

* Requires `paws.storage` 0.8.0 or later. Data files are uploaded only if
  absent, with a checksum; an S3-compatible service that rejects either stops
  every write at its first step (#155, `endpoint` in `?datom_get_conn`).

* **Breaking:** `datom_store()` with an `https://` `data_repo_url` and no
  `github_pat` now stops; it used to make a read-only store. Leave out
  `data_repo_url` for a reader. SSH addresses (`git@host:...`, `ssh://`) and
  other schemes (`http://`, `git://`) also stop, with or without a token, and a
  developer whose clone pushes over SSH now stops at `datom_get_conn()`: datom
  does not push with your SSH agent's keys. Use an `https://` address or a
  folder (#134).

* **Breaking:** a store with a folder `data_repo_url` and no token used to be a
  reader; it is now a writer. `datom_get_conn(store =, project_name =)` with no
  `path` stops for it. For a reader, leave out `data_repo_url` (#134).

* You can now write without a GitHub token: any `data_repo_url` makes a writer
  store, and a folder address (a local or network path, or `file://`) needs no
  token. `datom_init_repo(create_repo = TRUE)` creates an empty bare git repo
  at a folder address, and refuses a folder that is not empty or whose parent
  is missing before writing anything. `datom_get_conn()` stops if a folder
  remote is missing, is not a git repo, or cannot be written to. Examples no
  longer pass a placeholder token. See "Writer or reader" in `?datom_store` and
  the new article "Try datom without GitHub or AWS" (#134).

* datom no longer saves a git identity in a repo's own config. Each commit uses
  the identity git itself finds, so a global identity applies from the next
  commit in every repo. Where older datom saved the placeholder
  `datom <datom@noreply>` in a repo, the next write or pull removes it and says
  so. A real identity older datom saved there stays; remove it with
  `git2r::config(git2r::repository(path), user.name = NULL, user.email = NULL)`.
  With no identity anywhere, commits use the placeholder and a note says so once
  per R session (#70, #131). Writers now see that note when they connect with
  `datom_get_conn()`, before the first commit (#144).

* Four read errors now carry a condition class, so code can catch them by
  class rather than by message: `datom_parquet_integrity_failure` (a table's
  stored data fails its hash check), `datom_version_not_found`,
  `datom_version_ambiguous` and `datom_invalid_sha`. Messages are unchanged.
  A malformed member in a stored set now reaches the caller as
  `datom_set_member_malformed`; it used to arrive wrapped as
  `purrr_error_indexed` (#129).

* New `datom_example_file()` writes an example table to a CSV whose lines end
  with `\n` on every system, so the file, and the version datom records for
  it, is the same on Windows, macOS and Linux. The vignettes now use it; with
  `write.csv()`, every version a Windows reader saw differed from the
  article's.
* New "Troubleshooting" article: a short index from common symptoms to the
  article that explains each. "Version SHAs" gains a section on line endings.
* New `datom_find_member()` returns the one member of a set a name refers to --
  its exact version and labels -- with no connection and no storage read, so a
  reader holding only the set can ask what it cites. An ambiguous name stops and
  lists the candidates; narrow with `tags` or `version` (#112,
  `?datom_find_member`).

* A message asking you to upgrade datom now suggests `install.packages("datom")`
  first and GitHub for a development build. The ones about data formats also
  point at the new `?datom_schema`, which lists the datom release that reads
  each format (#103).

* When creating the GitHub repo fails, the error now includes GitHub's own
  explanation. A 403 or 404 adds a hint about the token permissions creation
  needs (classic token: `repo`; fine-grained: Administration, write), except
  when GitHub says the rate limit is used up; a 404 also says the organisation
  name or API URL may be wrong. `datom_store()`'s `validate` checks only that
  the token authenticates, not what it may do (#70, `?datom_store`).
* "Starting on S3" gains a section on using a company GitHub: an organisation,
  GitHub Enterprise Server, or Enterprise Cloud with data residency
  (`*.ghe.com`), which needs its own `github_api_url` (#136, `?datom_store`).
* Messages that point at datomanager for governance now say it is planned and
  not yet released (#136).

* The test suite now passes when suggested packages such as git2r and rio are not
  installed, as in CRAN's "noSuggests" check (#92). Running the tests now needs
  testthat 3.3.0 or later, which skips a test on CRAN when a package it needs is
  missing.

# datom 0.2.0

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
* **`datom_member()`** declares one member. **`datom_assemble_set()`** starts an
  empty set and **`datom_add_member()`** adds one member at a time, to a new set
  or one read back, so a bad version is reported on the line that added it. A
  set in memory holds no connection: pass `conn =` to add a member by name, and
  write with `datom_write_set(conn, x)` or `x |> datom_write_set(conn = conn)`.
* **On a product repo, `datom_sync_manifest(conn, sources = )` and
  `datom_sync(conn, manifest, sources = )` build and refresh the set** the way
  they onboard files elsewhere: map what the source projects hold, review it as
  a data frame, apply it. Tables and sets in a source are handled alike. The
  preview never proposes a removal and says which members it could not check.
  Unlike table sync, applying writes nothing: `datom_write_set()` saves the set.
  See `?datom_sync_manifest` and `?datom_sync`.
* **`datom_parent(conn, table, x = )`** takes the parent's version from the set
  you hold, resolving the name as `datom_fetch_member()` does, and returns a list
  ready for `datom_write(parents = )`. Calls with `version =` are unchanged.
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
* `datom_write_set()` stops before writing anything when a member's recorded
  parents name an input that the set pins at a different version (the output
  was not derived again after its inputs moved), and when the set you pass
  belongs to another repo, by name or by project. See `?datom_write_set`.
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
* A table's metadata **no longer records `column_hashes`**, the per-column
  digests added in 0.1.1. A per-column digest lets anyone who can read the
  metadata confirm a guess about a column's values. Nothing needs doing and no
  version moves; existing files lose the field the next time their table is
  written. See "What metadata reveals about your data" in
  `vignette("design-version-shas")`
  ([#119](https://github.com/amashadihossein/datom/issues/119)).
* `datom_example_data("vs")` returns a vital-signs table for the same 48
  subjects and visits as `lb`. The other four example tables are unchanged.
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
