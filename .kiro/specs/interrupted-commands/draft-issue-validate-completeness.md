# DRAFT issue, not yet filed: datom_validate() does not check that storage holds every version's documents

Drafted 2026-10-30 from reviews of the interrupted-commands spec (#155), for the owner to review.
Not opened on GitHub; the owner decides whether and when. Once filed, replace this file's pointer in
`design.md` section 12 with the issue number.

---

**Title:** `datom_validate()` does not check that storage holds every version's documents

## What it checks today

For each artifact, `.datom_validate_one_table()` in `R/validate.R` checks that three things exist in
storage: `{name}/.metadata/metadata.json`, `{name}/.metadata/version_history.json`, and the data file
(`{name}/{data_sha}.parquet`, or a set's `{name}/{data_sha}.json`). It reports `metadata_missing_s3`,
`history_missing_s3` and `data_missing_s3`. Snapshots (`{name}/.metadata/{version}.json`) are
checked only for the versions a set pins as members (`members_unresolvable`). From #155 it also
reports `metadata_stale_s3`: the stored `metadata.json` holds a different version from the clone's
last commit.

## What it does not see

1. **The current version's snapshot is missing.** `datom_read(conn, name, version = <current>)`
   fails, while `datom_validate()` says all checks passed.
2. **The stored history lacks the current version.** The file exists, so nothing is reported, but
   a reader's `datom_history()` does not list the version readers are getting.
3. **An older version's snapshot is missing.** Reads that name that version fail, and so does
   following a lineage record that pins it. (A set that pins it is already reported, as
   `members_unresolvable`.)
4. **The stored `metadata.json` describes a version nothing records.** No history entry, manifest
   row or snapshot names the version it hashes to. Readers are told an older version (the history
   is matched by content), and reads pinned to it return the older metadata.

## What repairs them today

From #155, `datom_validate(fix = TRUE)` publishes each artifact from the clone through the one
publish path, so it restores items 1 and 2: the current version's snapshot is rebuilt from the
clone's `metadata.json`, and the history is copied from the clone. Nothing restores items 3 and 4:

- an older snapshot is not in the clone (no datom command writes `{name}/.metadata/` there; checked
  2026-10-30), so it would have to be rebuilt from git, each version's `metadata.json` at the commit
  that introduced it (the commit-by-version lookup in `R/version-commit.R`);
- for item 4, the publish deliberately writes no snapshot and warns, because writing the edited
  document under the recorded version's key would overwrite that version's correct snapshot.

Before #155 the repair restored none of them: its snapshot loop read a clone folder that never
exists. For items 1 and 2 the gap is now in the report only; a user told everything is consistent
has no reason to run the fix.

## How these states arise

After #155, no datom command leaves them: every route uploads the snapshot and history before
`metadata.json`, and `metadata.json` before the manifest; a hand edit of `metadata.json` is reset,
not published. They remain possible from:

- datom 0.2.0's `datom_write(conn, name =)` committing and publishing a hand edit of
  `metadata.json` (item 4; probably the most common source). It recorded no history entry, manifest
  row or snapshot for the edited version (probed 2026-10-30);
- an interrupted write by datom 0.2.0 or earlier, which uploaded `metadata.json` first (items 1
  and 2);
- storage losing a file outside datom (a hand deletion, a lifecycle rule, a partial copy).

## Options to weigh

- **Current snapshot only**: one existence check per artifact, a new status such as
  `snapshot_missing_s3`, which the repair fixes. Cheapest; covers the case readers hit first.
- **History contains the current version**: one read of the stored history per artifact (validate
  reads only existence today).
- **`metadata.json` matches its recorded version** (item 4): recompute the stored document's version
  and compare with the recorded one, both already read. Needs a decision on the fix: record the
  edited version (a history entry, a manifest row, a snapshot), or restore the committed document
  of the recorded version from git.
- **Every version's snapshot**: one existence check per version, or one listing per artifact; cost
  grows with history length. Restoring them means rebuilding from git, as above.

Each new status needs its help text in `?datom_validate`, a NEWS line, and a test that goes red when
the check is removed. Whatever is chosen, `datom_validate()`'s summary should not imply more
coverage than it has.
