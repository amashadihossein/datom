# Requirements Document

datom-cv1 Canonical Hash & Three-SHA Identity

## Introduction

This feature replaces datom's data identity mechanism before the first CRAN release
(`0.1.0`). It tracks GitHub issue
[#72](https://github.com/amashadihossein/datom/issues/72) and is the remaining pre-CRAN
work item. Its contract-neutral companion,
[#74](https://github.com/amashadihossein/datom/issues/74), is merged
(`.kiro/specs/pre-cran-mechanical-fixes/`).

Unlike #74, this work **changes the on-disk contract** — the meaning of `data_sha`, plus
new metadata fields. It therefore cannot wait past `0.1.0`: changing the hash definition
after release would invalidate every `data_sha` in existing projects. Because the package
is pre-release, there is no migration path and no backward-compatibility concern
(pre-release pilots' `data_sha` values change).

The change has three connected parts:

1. **Canonical content hash (`datom-cv1`)** — a new in-memory, I/O-free, order-significant
   hash for tabular data that replaces the current "hash the parquet bytes" `data_sha`.
2. **Three-SHA identity model** — precise definition and wiring of `original_file_sha`
   (raw input bytes), `data_sha` (canonical content), and `parquet_sha` (stored-object
   integrity), across the sync, write, and read paths.
3. **The datom table contract** — an ingestion allowlist, an exported
   `datom_check_hashable()` pre-flight helper backed by a single-source recourse map,
   persisted per-column hashes for a future `datom_diff`, plus golden/reference-parity
   tests and vignette rewrites.

Line numbers in the issue refer to `main` at issue-creation time; always locate by
function name first since lines drift. The issue's revision note is at **rev 7**
(2026-07-15): the `sort_columns` / `sort_rows` options are removed entirely — row and
column order are always significant.

## Glossary

- **original_file_sha**: SHA-256 of the raw bytes of an input artifact. Answers "has this
  input file changed?" Universal (byte-level), language-independent. Present only on the
  imported (sync) path; derived tables never have one. Never used as a storage address.
- **data_sha**: SHA-256 of the canonical logical content of a table, via the `datom-cv1`
  algorithm. Answers "is this the same content?" Guaranteed reproducible within R + renv.
  The **only** storage address, for imported and derived tables alike.
- **parquet_sha**: SHA-256 of the exact stored parquet object bytes. Answers "is the stored
  object intact?" Tied to the arrow version. Integrity only — never an identity value,
  never an address.
- **datom-cv1**: The canonical content hash algorithm defined by this spec, implemented as
  internal `.datom_canonical_hash(data)` in `R/utils-sha.R`, with an executable reference
  implementation at `dev/datom_cv1_reference.R`.
- **Reference_Script**: `dev/datom_cv1_reference.R` — a standalone (base R + `digest`),
  zero-I/O, pure-ASCII executable form of the `datom-cv1` spec plus its self-test.
- **Recourse_Map**: The single source of truth mapping each unsupported column
  class/type to its canonical remediation message, implemented as internal
  `.datom_hash_recourse(x)` and shared by `datom_check_hashable()` and the hash's abort
  path.
- **Ingestion_Allowlist**: The named constant `.datom_import_formats` enumerating the file
  formats `datom_sync` may onboard.
- **Golden_Vector**: A hard-coded expected hex hash for a fixed fixture, computed once on a
  reference platform and re-derived by every CI run to detect platform/version drift.
- **CI_Matrix**: The existing four-environment CI matrix (ubuntu release, ubuntu oldrel,
  windows, macOS).
- **Change_Type**: The classification a write/sync computes — `full`, `metadata_only`, or
  `none`.

## Requirements

---

## Group A — Canonical content hash (`datom-cv1`)

### Requirement 1: Content-based `data_sha` replacing parquet-byte hashing

**User Story:** As a data developer, I want `data_sha` to identify the logical content of a
table rather than its serialized parquet bytes, so that identical data hashes identically
regardless of the arrow version or the R container class (tibble vs data.frame) used to
produce it.

#### Acceptance Criteria

1. THE package SHALL provide an internal function `.datom_canonical_hash(data)` in
   `R/utils-sha.R` that computes `data_sha` from in-memory values only.
2. THE `.datom_canonical_hash` function SHALL perform zero I/O: no parquet write, no CSV
   write, no re-read, no temporary files.
3. THE `.datom_canonical_hash` function SHALL NOT call `as.data.frame()` or any coercion
   helper; it SHALL read columns via `data[[i]]` and `names(data)` and dimensions via
   `nrow(data)` / `ncol(data)`.
4. WHERE two inputs hold equal values but differ only in container class (tibble,
   `grouped_df`, plain data.frame) or data-frame-level attributes/row names, THE
   `.datom_canonical_hash` function SHALL return the same hash.
5. THE `data_sha` computation SHALL NOT invoke arrow, so the installed arrow version
   cannot affect `data_sha` (the stored parquet bytes and `parquet_sha` may differ across
   arrow versions while `data_sha` is identical).
6. THE `.datom_canonical_hash` function SHALL abort when `data` does not satisfy
   `is.data.frame(data)`, and SHALL abort when `data` has zero rows or zero columns.
7. WHEN `.datom_canonical_hash` is run on identical input twice, it SHALL return the same
   hash (determinism).

### Requirement 2: Deterministic, portable per-column encoding and type dispatch

**User Story:** As a data developer, I want each column encoded by a fixed,
platform-independent rule keyed to its semantic type, so that the same content produces the
same `data_sha` across users, machines, locales, operating systems, and time.

#### Acceptance Criteria

1. THE `.datom_canonical_hash` function SHALL compute each column's digest as
   `sha256( utf8(tag) || utf8(colname) || 0x00 || payload )` using
   `digest::digest(..., algo = "sha256", serialize = FALSE)` on raw vectors only.
2. THE per-column type dispatch SHALL be evaluated in this exact order: `bit64::integer64`
   → factor → `Date` (incl. `IDate`) → `POSIXct` → `difftime` (incl. `hms`) →
   `data.table::ITime` → `haven_labelled`/`labelled`/`labelled_spss` → any other classed
   column (refused) → unclassed atomics (logical/integer/double, character) → any other
   type (refused).
3. WHEN a column is logical, integer, or double, THE function SHALL unify it under one tag
   `"num"` as IEEE-754 little-endian doubles, canonicalizing `NaN` payloads to a single
   `NaN`, converting `-0.0` to `+0.0`, and preserving `NA_real_` distinct from `NaN`.
4. WHEN a column is character, THE function SHALL encode a one-byte-per-row NA mask followed
   by NUL-terminated UTF-8 (`enc2utf8`), so that `NA` and `""` are distinguishable, and
   SHALL NOT apply Unicode normalization (NFC and NFD hash differently — documented benign
   limitation).
5. WHEN a column is `bit64::integer64`, THE function SHALL copy its 8-byte bit patterns
   verbatim (tag `"i64"`) with no NaN/zero canonicalization.
6. WHEN a column is a factor, THE function SHALL hash its `as.character` values (tag
   `"chr"`); factor levels and orderedness SHALL NOT be part of identity.
7. WHEN a column is `Date` (including integer-storage Dates and `data.table::IDate`), THE
   function SHALL hash `as.double(unclass(x))` under tag `"date"`.
8. WHEN a column is `POSIXct`, THE function SHALL hash epoch seconds
   (`as.double(unclass(x))`) under tag `"time"`, excluding `tzone` from identity.
9. WHEN a column is `difftime`/`hms`, THE function SHALL hash the numeric payload followed
   by `0x00` and the required `units` string under tag `"drtn"`; `data.table::ITime` SHALL
   be encoded identically with units `"secs"`, so `ITime` and `hms` of the same clock times
   hash equal.
10. WHEN a column is `haven_labelled`/`labelled`/`labelled_spss`, THE function SHALL strip
    class and attributes and fall through to the underlying type; labels SHALL NOT be part
    of identity.
11. THE function SHALL compute the final hash as
    `sha256( "datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digest_hex...) )`.
12. THE `.datom_canonical_hash` function SHALL NOT round doubles to N significant digits and
    SHALL NOT sort rows or columns.
13. THE numeric payload encoding of criterion 3 (including NaN canonicalization and
    −0 → +0) SHALL be a single shared encoder used by the `num`, `date`, `time`, and `drtn`
    tags.

### Requirement 3: Order-significant identity, no sort option (rev 7)

**User Story:** As a data developer, I want row and column order to be part of table
identity with no sort switch, so that a meaningful reorder is never silently masked and
`data_sha` carries no locale/collation dependence.

#### Acceptance Criteria

1. THE `.datom_compute_data_sha()` function SHALL take the signature
   `.datom_compute_data_sha(data)` with no `sort_columns` / `sort_rows` parameters.
2. WHEN two tables differ only in column order, THE `data_sha` SHALL differ.
3. WHEN two tables differ only in row order, THE `data_sha` SHALL differ.
4. THE search `grep -rn "sort_columns\|sort_rows" R/ tests/` SHALL return nothing.
5. THE two existing sort-only tests in `test-utils-sha.R` SHALL be removed and replaced by
   positive assertions that column reorder and row reorder each change the hash.

---

## Group B — Three-SHA identity model and wiring

### Requirement 4: Fixed three-SHA nomenclature everywhere

**User Story:** As a maintainer, I want exactly three SHA field names used consistently, so
that code, metadata, history, manifests, errors, and docs never conflate the three
concepts.

#### Acceptance Criteria

1. THE package SHALL use only the names `original_file_sha`, `data_sha`, and `parquet_sha`
   for these three concepts across code, metadata JSON, `version_history` entries, manifest
   entries, error messages, docs, and vignettes.
2. THE package SHALL NOT introduce the bare, ambiguous name `file_sha`.
3. THE search `grep -rn "file_sha" R/ man/ vignettes/` SHALL match only `original_file_sha`
   and `parquet_sha`.
4. THE storage addressing SHALL use `data_sha` only, for imported and derived tables alike;
   neither `parquet_sha` nor `original_file_sha` SHALL appear in any storage key.

### Requirement 5: `parquet_sha` computation and metadata fields

**User Story:** As a data developer, I want the stored parquet object's integrity hash and
the algorithm/provenance fields recorded in metadata, so that downloads can be verified and
identity provenance is auditable.

#### Acceptance Criteria

1. THE `.datom_build_metadata()` function SHALL add fields `hash_algo = "datom-cv1"`,
   `parquet_sha`, `original_file_sha`, and `column_hashes`.
2. WHERE the table was produced on the imported (sync) path, THE `original_file_sha` field
   SHALL be non-NULL; WHERE the table was derived via `datom_write()` from memory, THE
   `original_file_sha` field SHALL be absent from the metadata (not present with a NULL
   value).
3. THE `datom_write()` function SHALL compute `new_parquet_sha` as
   `digest::digest(file = tmp, algo = "sha256")` after writing the temporary parquet.
4. WHEN `Change_Type` is `full` and no object exists at `<name>/<data_sha>.parquet`, THE
   `datom_write()` function SHALL upload and set `parquet_sha` to `new_parquet_sha`.
5. WHEN `Change_Type` is `full` and an object already exists at that key (content reverted
   to an older version), THE `datom_write()` function SHALL NOT overwrite the stored object
   and SHALL reuse the `parquet_sha` from the most recent history entry carrying this
   `data_sha`; only if none carries one (legacy) SHALL it upload and use `new_parquet_sha`.
6. WHEN `Change_Type` is `metadata_only`, THE `datom_write()` function SHALL set
   `parquet_sha` to the current metadata's `parquet_sha` (the stored object's bytes), not
   `new_parquet_sha`, and SHALL skip the upload.
7. THE `datom_write()` function SHALL set `parquet_sha` before calling
   `.datom_write_metadata_local()` so it persists, and `.datom_write_metadata_local()` SHALL
   include `parquet_sha` in the `version_history.json` entry, alongside continuing to record
   `original_file_sha` in that entry as today (so per-entry file provenance is preserved for
   S3/S4 auditability and the Requirement 5 criterion 5 revert-to-older `parquet_sha`
   history scan).

### Requirement 6: Locale-independent metadata field ordering (A-bis)

**User Story:** As a maintainer, I want `metadata_sha` field ordering to be byte-wise and
locale-independent, so that version identity does not differ across machines with different
locales.

#### Acceptance Criteria

1. THE `.datom_compute_metadata_sha()` function SHALL sort semantic field names with
   `sort(names(semantic), method = "radix")` (C-locale byte order).
2. WHEN `.datom_compute_metadata_sha()` runs under `LC_COLLATE=C` and under
   `en_US.UTF-8` on the same input, it SHALL produce the same hash.

### Requirement 7: Volatile field selection for `metadata_sha`

**User Story:** As a data developer, I want `metadata_sha` to exclude fields that must not
affect version identity, so that arrow-version drift and informational indexes do not cause
spurious versions and re-derivation correctly reports `none`.

#### Acceptance Criteria

1. THE `.datom_compute_metadata_sha()` volatile set SHALL be
   `c("created_at", "datom_version", "parquet_sha", "column_hashes")`.
2. THE `metadata_sha` SHALL exclude `parquet_sha` (so arrow-version byte differences do not
   re-enter identity).
3. THE `metadata_sha` SHALL exclude `column_hashes` (a deterministic function of the same
   values that determine `data_sha`).
4. THE `metadata_sha` SHALL include `original_file_sha` and `hash_algo` (a new source file
   or algorithm legitimately makes a new version).

### Requirement 8: Read-time `parquet_sha` integrity verification

**User Story:** As a data reader, I want a downloaded parquet object verified against its
recorded `parquet_sha` before it is parsed, so that corruption or tampering is caught rather
than silently read.

#### Acceptance Criteria

1. THE `.datom_read_parquet()` function SHALL receive the expected `parquet_sha`: from
   `metadata_list$current$parquet_sha` for current reads, and from `.datom_resolve_version()`
   for version-pinned reads.
2. THE `.datom_resolve_version()` function SHALL be extended to also return the resolved
   entry's `parquet_sha` (returning a list), with both call sites updated.
3. WHEN the expected `parquet_sha` is non-empty and the downloaded file's SHA-256 differs,
   THE `.datom_read_parquet()` function SHALL abort with a message naming the table, key,
   and both hashes and indicating possible corruption or tampering, before calling
   `arrow::read_parquet()`.
4. WHEN the expected `parquet_sha` field is absent (pre-cv1 metadata), THE
   `.datom_read_parquet()` function SHALL skip the check silently and read succeeds.

### Requirement 9: Identity contract behavior across sync/write use cases

**User Story:** As a data developer collaborating through a shared repo, I want the sync and
write paths to classify changes correctly for the documented use cases (S1–S6), so that
unchanged inputs are skipped, re-exports don't duplicate storage, and identical
re-derivations are no-ops.

#### Acceptance Criteria

1. WHEN a pulled manifest records an input's `original_file_sha` as unchanged (S1), THE
   sync path SHALL skip it before any parsing (a no-op).
2. WHEN an input file's bytes AND canonical content both change (S2), THE sync path SHALL
   classify it `full`, upload the new parquet at `<name>/<data_sha>.parquet`, and record a
   new version.
3. WHEN an input file's bytes change but its canonical content is identical (S3
   re-export), THE sync path SHALL classify it `metadata_only`, skip the upload, record the
   new `original_file_sha`, and carry `parquet_sha` forward; a subsequent scan SHALL report
   the file `unchanged`.
4. WHEN a developer syncs an older file whose `data_sha` matches current but whose
   `original_file_sha` differs (S4), THE sync path SHALL classify it `metadata_only`
   without appending a duplicate `version_history` entry (see Requirement 12).
5. WHEN a table is derived and written the first time (S5), THE `data_sha` SHALL address it
   with no `original_file_sha` and `Change_Type` SHALL be `full`.
6. WHEN an identical recipe is re-run producing the same `data_sha` and same parents
   matching current (S6), THE `datom_write()` function SHALL report `none` with no commit,
   upload, or history entry.

---

## Group C — The datom table contract

### Requirement 10: `datom_check_hashable()` pre-flight helper with shared recourse

**User Story:** As a data developer, I want a runnable pre-flight check that tells me which
columns are unsupported and how to fix each one, so that I can prepare data for
`datom_write()` before hitting a write-time error.

#### Acceptance Criteria

1. THE package SHALL export `datom_check_hashable(data)` in a new file `R/hashable.R` and
   list it in `_pkgdown.yml` reference.
2. THE `datom_check_hashable()` function SHALL return (invisibly) a data frame with one row
   per column containing `column`, `class` (collapsed class string or `typeof`), `status`
   (`"ok"`/`"unsupported"`), and `recourse` (`NA` when ok; the canonical message
   otherwise).
3. THE `datom_check_hashable()` function SHALL print a cli report: a `✓` summary when clean
   and a `✗` per offending column with its recourse when not.
4. THE package SHALL provide an internal `.datom_hash_recourse(x)` in the same file that
   returns `NULL` for supported columns or the canonical recourse string otherwise, and
   BOTH `datom_check_hashable()` AND the hash abort path SHALL call this one function.
5. THE `datom_check_hashable()` function SHALL carry runnable examples that require no
   network and no store.

### Requirement 11: All-offenders abort during hashing

**User Story:** As a data developer, I want a single actionable error listing every
unsupported column at once, raised before any state changes, so that a wide table with
several exotic columns produces one clear error and leaves no partial state.

#### Acceptance Criteria

1. THE `.datom_canonical_hash()` function SHALL first scan all columns via
   `.datom_hash_recourse()` and, if any are unsupported, abort exactly once listing every
   offending column with its class and canonical recourse.
2. THE abort message SHALL end with an `"i"` hint directing the user to run
   `datom_check_hashable(data)` or see `vignette('design-version-shas')` — "The datom table
   contract".
3. THE abort SHALL fire during `data_sha` computation (step 1 of `datom_write()`), before
   any git or storage mutation, so a refusal leaves no partial state.
4. THE function SHALL NOT fail one column at a time.
5. WHEN each documented recourse is applied to an offending fixture column, THE resulting
   column SHALL become hashable.

### Requirement 12: Full-history `metadata_sha` dedup guard

**User Story:** As a data developer, I want the version-history append to be deduplicated
against the entire history, so that re-syncing an older-but-content-matching file (S4) does
not create a duplicate version that later makes `datom_read(version=)` ambiguous.

#### Acceptance Criteria

1. BEFORE appending a new entry, THE `.datom_write_metadata_local()` function SHALL scan the
   entire `version_history` for an entry whose `version` equals the new `metadata_sha`.
2. WHEN a matching entry exists anywhere in history, THE function SHALL NOT append a
   duplicate; the current pointer (`metadata.json`) SHALL still be updated.
3. THE `version_history.json` SHALL never contain two entries with the same `version`
   (`metadata_sha`).
4. THE dedup scan SHALL be O(history) with early exit.

### Requirement 13: Ingestion allowlist for `datom_sync`

**User Story:** As a data developer, I want `datom_sync` to onboard only flat tabular file
formats, so that nested (`.json`) or arbitrary (`.rds`) structures cannot enter the sync
path and fail late at hash time.

#### Acceptance Criteria

1. THE package SHALL define a named constant `.datom_import_formats` containing
   `csv`, `tsv`, `txt`, `psv`, `parquet`, `sas7bdat`, `xpt`, `sav`, `zsav`, `por`, `dta`,
   `xls`, `xlsx`.
2. THE `.datom_import_file(file, format)` function SHALL normalize `tolower(format)` and,
   when the format is not in the allowlist, `cli::cli_abort` naming the format and directing
   the user to convert to CSV/parquet or to read it themselves and pass a data frame to
   `datom_write()`. THE exact allowlist abort message text SHALL be treated as canonical and
   pinned in the design doc (the same single-source-of-truth discipline that applies to the
   Recourse_Map also covers the allowlist message).
3. THE `datom_sync_manifest()` function SHALL flag non-allowlisted files up front with
   `status = "unsupported_format"` and the same recourse, and SHALL still process
   allowlisted siblings (one bad file SHALL NOT block the batch).
4. WHEN an allowlisted extension is synced, THE `.datom_import_file()` function SHALL
   dispatch to the correct reader.

---

## Group D — Persisted column index

### Requirement 14: Persist per-column hashes as an ordered array

**User Story:** As a data developer, I want per-column digests stored in metadata in column
order, so that a future `datom_diff` can compare versions without downloading data and
`data_sha` can be cheaply self-checked against the index.

#### Acceptance Criteria

1. THE `.datom_build_metadata()` function SHALL persist `column_hashes` in `metadata.json`
   as an ordered array of `{name, sha}` objects in table column order (the order that feeds
   `data_sha`).
2. THE per-column digests stored SHALL be exactly those computed inside
   `.datom_canonical_hash()` (computed once, used for both `data_sha` and the index), with
   no truncation.
3. WHEN `data_sha` is recomputed as
   `sha256("datom-cv1" || f64le(nrow) || f64le(ncol) || concat(sha...))` from the stored
   `column_hashes` plus dimensions, it SHALL reproduce the stored `data_sha`.
4. THE `column_hashes` field SHALL be excluded from `metadata_sha` (Requirement 7).
5. WHEN two versions differ in exactly one column, THE `column_hashes` arrays SHALL differ
   in exactly that column's entry.

---

## Group E — Tests, reference implementation, and docs

### Requirement 15: Reference implementation and cross-platform goldens

**User Story:** As a maintainer, I want an executable reference spec and hard-coded golden
hashes re-derived on every CI environment, so that any platform, endianness, or
dependency-version sensitivity breaks a test immediately instead of silently changing
identity.

#### Acceptance Criteria

1. THE repository SHALL contain `dev/datom_cv1_reference.R`, a standalone (base R +
   `digest`), zero-I/O implementation plus self-test that takes no sort arguments.
2. THE `dev/datom_cv1_reference.R` file SHALL be pure ASCII:
   `all(as.integer(readBin(f, "raw", file.size(f))) < 128L)` SHALL be TRUE, with all
   Unicode fixtures constructed via `intToUtf8()`.
3. WHEN `Rscript dev/datom_cv1_reference.R` is run, it SHALL exit 0 (all self-test PASS) and
   print portable golden constants.
4. THE test suite SHALL include a parity test asserting that the package's
   `.datom_canonical_hash()` and the script's `datom_canonical_hash()` agree on the full
   fixture set (skipped when the script is absent, e.g. on CRAN where `dev/` is
   Rbuildignored).
5. THE test suite SHALL include a NIST SHA-256 vector golden:
   `digest::digest(charToRaw("abc"), algo = "sha256", serialize = FALSE)` equals
   `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
6. THE test suite SHALL hard-code Golden_Vectors (numeric, integer/logical/double parity,
   character incl. NFC/NFD and CJK, factor, Date variants, POSIXct tzone equality, difftime
   secs vs mins, hms vs ITime, integer64 incl. NaN-bit-space, one mixed data.frame, one
   `.datom_compute_metadata_sha()` golden), and the printed constants from the
   Reference_Script SHALL match those hard-coded in the tests.
7. THE Golden_Vector tests SHALL pass on all four CI_Matrix environments.

### Requirement 16: Property, table-contract, allowlist, and integration tests

**User Story:** As a maintainer, I want behavioral tests for every identity decision, the
recourse map, ingestion allowlist, and the S1/S3/S4 regressions, so that the contract is
enforced and edge cases stay fixed.

#### Acceptance Criteria

1. THE test suite SHALL include property tests: tibble vs data.frame equal (real and
   `class<-`-faked); `haven_labelled`/`labelled_spss`-shaped vs bare equal; `"1"` vs `1`
   differ; `NA` vs `""` differ; `NA_real_` vs `NaN` differ; `0/0` vs `NaN` equal; `-0` vs
   `0` equal; column reorder differs; row reorder differs; metadata field-order determinism
   under `LC_COLLATE=C` vs `en_US.UTF-8`; all-`NA` logical vs all-`NA` character differ.
2. THE test suite SHALL include, for every row of the Recourse_Map, a pair asserting that
   `datom_check_hashable()` flags the column AND `.datom_canonical_hash()` aborts with the
   same recourse; a multi-offender table produces exactly one abort naming all; applying
   each recourse makes the fixture hashable; a clean table reports all `ok`; a refusal
   leaves no git/storage/manifest state.
3. THE test suite SHALL include ingestion-allowlist tests: each allowlisted extension
   dispatches to the expected reader (stubbed); `.json`/`.rds`/`.xml` abort with the format
   recourse; `datom_sync_manifest()` marks an `.rds` as `unsupported_format` and still
   processes a sibling `.csv`.
4. THE test suite SHALL include column-hash/diff-index tests: `column_hashes` present and
   ordered to columns; each entry equals the standalone per-column digest; `data_sha`
   recomputable from `column_hashes` + dims; `metadata_sha` invariant to `column_hashes`
   presence; single-column change → single-entry diff.
5. THE test suite SHALL include identity-contract integration tests (local backend): S1
   skip-before-parse (stub importer, assert zero calls); S3 loop regression; S4
   duplicate-version regression (no duplicate `version` values; `datom_read(version=)`
   resolves without "ambiguous"); `parquet_sha` integrity (corrupt stored byte → tamper
   abort; legacy metadata without field → read succeeds); carry-forward and
   revert-to-older-content behavior; `hash_algo == "datom-cv1"` and imported-path
   `original_file_sha` present after `datom_write()`.
6. THE full test suite SHALL pass with the fail-closed network guard active (no
   `DATOM_ALLOW_REAL_NETWORK`).

### Requirement 17: Documentation, vignettes, and NEWS

**User Story:** As a user, I want the vignettes and release notes to explain the three-SHA
model, the table contract, and the identity decisions, so that I understand what datom
guarantees and how to work within the contract.

#### Acceptance Criteria

1. THE vignettes `design-version-shas.Rmd` and `getting-started.Rmd` SHALL be rewritten
   around the three-SHA nomenclature and identity contract, with a "The datom table
   contract" section covering the framing, the "where this bites" expectation-setting, the
   recourse table, and the ingestion allowlist, using `datom_check_hashable()` as the
   runnable entry point.
2. THE documentation SHALL record the identity decisions: int/dbl/lgl unify; tzone, factor
   levels, labels, NaN payloads, and −0 are not identity; NFC ≠ NFD; row/column order
   significant with no sorting; doubles bit-exact — with the asymmetry rationale.
3. THE documentation SHALL scope the cross-language claim: guaranteed within R + renv; the
   spec is language-implementable; raw-file onboarding identity is language-independent.
4. THE `NEWS.md` SHALL note that pre-release `data_sha` values change with no migration
   path, and record the deliberate narrowings: (a) list/exotic columns are now refused with
   a recourse; (b) `datom_sync` accepts only allowlisted formats (`.json`/`.rds` no longer
   imported directly); (c) the internal `sort_columns`/`sort_rows` options are removed.
5. THE documentation SHALL state the allowlist escape-hatch provenance tradeoff as a rule:
   when a user reads an unsupported source (e.g. `.rds`) themselves and passes the resulting
   data frame to `datom_write()`, the table is derived and has no `original_file_sha`, so
   input-file change detection (S1/S3 semantics) does not apply to that source.

---

## Overall acceptance criteria

- `R CMD check --as-cran`: 0 errors, 0 warnings, 0 notes locally.
- Full test suite passes with the fail-closed network guard active.
- All Golden_Vector tests pass on all four CI_Matrix environments; the NIST vector golden
  and the reference-parity test are present and passing.
- `Rscript dev/datom_cv1_reference.R` exits 0 and its printed constants match the tests'
  hard-coded constants; the script is pure ASCII.
- `.datom_compute_data_sha()` takes no `sort_*` parameters;
  `grep -rn "sort_columns\|sort_rows" R/ tests/` returns nothing.
- `datom_check_hashable()` is exported, documented with runnable examples, listed in
  `_pkgdown.yml`, and shares its recourse strings with the hash abort via
  `.datom_hash_recourse()`.
- Every Recourse_Map row has a passing test pair (flagged by checker AND fixed by its
  recourse); a multi-offender table produces exactly one abort; refusal leaves no state.
- Ingestion allowlist enforced in `.datom_import_file()` and `datom_sync_manifest()`.
- `column_hashes` persisted as an ordered array; `data_sha` recomputable from it + dims;
  excluded from `metadata_sha`.
- `grep -rn "file_sha" R/ man/ vignettes/` matches only `original_file_sha` and
  `parquet_sha`.
- `grep -rn "as.data.frame" R/utils-sha.R` returns nothing.
- `version_history.json` never contains two entries with the same `version`.

## Notes

- **Changes the on-disk contract**; must land before `0.1.0`. No migration path
  (pre-release).
- Coordinates with #74 (merged): #74 item G added `.datom_validate_sha()` calls in
  `.datom_read_parquet()`; this issue's read-time `parquet_sha` verification (Requirement 8)
  extends the same function.
- Downstream: #73 wiring item 11 (`datom_diff`) builds on the `column_hashes` index
  persisted here (Requirement 14).
- The R verification gates (`devtools::test()`, `R CMD check --as-cran`, `Rscript`) are run
  by the maintainer or CI, not in this authoring context; the verification criteria describe
  the expected outcome of those gates rather than assuming they have already run here.
