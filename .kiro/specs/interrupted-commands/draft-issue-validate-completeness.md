# DRAFT issue, not yet filed: datom_validate() does not check that storage holds every version's documents

Drafted 2026-10-30 from a review of the interrupted-commands spec (#155), for the owner to review.
Not opened on GitHub; the owner decides whether and when. Once filed, replace this file's pointer in
`design.md` section 12 with the issue number.

---

**Title:** `datom_validate()` does not check that storage holds every version's documents

## What it checks today

For each artifact, `.datom_validate_one_table()` in `R/validate.R` checks that three things exist in
storage: `{name}/.metadata/metadata.json`, `{name}/.metadata/version_history.json`, and the data file
(`{name}/{data_sha}.parquet`, or a set's `{name}/{data_sha}.json`). It reports `metadata_missing_s3`,
`history_missing_s3` and `data_missing_s3`. Snapshots (`{name}/.metadata/{version}.json`) are
checked only for the versions a set pins as members (`members_unresolvable`).

## What it does not see

1. **The current version's snapshot is missing.** `datom_read(conn, name, version = <current>)`
   fails, while `datom_validate()` says all checks passed.
2. **The stored history lacks the current version.** The file exists, so nothing is reported, but
   a reader's `datom_history()` does not list the version readers are getting.
3. **An older version's snapshot is missing.** Reads that name that version fail, and so does
   following a lineage record that pins it. (A set that pins it is already reported, as
   `members_unresolvable`.)

`datom_validate(fix = TRUE)` already repairs all three, because it copies the clone's history and
every snapshot in the clone. The gap is in the report: a user is told everything is consistent, so
has no reason to run the fix.

## How these states arise

After #155, no datom command leaves them: every route uploads the snapshot and history before
`metadata.json`, and `metadata.json` before the manifest. They remain possible from:

- an interrupted write by datom 0.2.0 or earlier, which uploaded `metadata.json` first;
- storage losing a file outside datom (a hand deletion, a lifecycle rule, a partial copy).

## Options to weigh

- **Current snapshot only**: one existence check per artifact, a new status such as
  `snapshot_missing_s3`. Cheapest; covers the case readers hit first.
- **History contains the current version**: one read of the stored history per artifact (validate
  reads only existence today).
- **Every version's snapshot**: one existence check per version, or one listing per artifact. Cost
  grows with history length.

Each new status needs its help text in `?datom_validate`, a NEWS line, and a test that goes red when
the check is removed. Whatever is chosen, `datom_validate()`'s summary should not imply more
coverage than it has.
