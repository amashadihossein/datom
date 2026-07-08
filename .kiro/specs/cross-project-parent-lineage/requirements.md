# Requirements Document

## Introduction

This feature makes cross-project parents first-class in `datom` lineage.
It originated from GitHub issue #52, where `datom_write()` could not
resolve a parent's `data_sha`. Rather than ship the minimal same-project
fix, the design pivots to a single exported constructor, `datom_parent()`,
as the only supported way to declare a parent. The constructor eagerly
reads the parent's versioned metadata snapshot from a caller-supplied
connection, extracts the authoritative `data_sha`, captures the parent's
`source_lineage`, and returns a pure-data, serializable record with no live
connection retained. Same-project and cross-project parents become
identical in form.

Consequential changes:

1. `datom_write()` requires fully resolved `datom_parent()` records and
   rejects raw parent lists that lack `data_sha`. It no longer performs any
   in-line storage-read enrichment of `parents`.
2. `datom_write()` derives the derived table's `source_lineage` itself, as
   the deduplicated union of its parents' captured `source_lineage`. Each
   table's metadata therefore carries its own flattened lineage (the set of
   imported roots) directly, so lineage lookups remain traversal-free. The
   per-parent `source_lineage` is used only transiently at write time to
   compute that union; it is NOT duplicated into the recorded `parents[]`
   entries, which stay lean (`source, table, version, data_sha`).
3. `datom_validate_lineage()` is removed. Because `datom_write()` derives
   `source_lineage` at write time and lineage is version-pinned, a recompute
   equals the recorded value in all normal operation, so a dedicated
   validator adds little and its name overstates the guarantee. Any lineage
   inspection or ad hoc consistency check is composed from existing reads
   (`datom_get_parents()`, `datom_get_lineage()`) plus a small exported
   union helper. Because the caller reads each parent through the
   appropriate connection, this composition naturally honors the
   one-connection-per-project model without any multi-connection plumbing
   inside datom.

This is a pre-release package (v0.0.0.9001), so breaking the `parents`
contract and removing `datom_validate_lineage()` are acceptable. Downstream
producers (dp_dev / dpbuild) must adopt `datom_parent()`; that migration is
tracked separately and is out of scope here.

## Glossary

- **Datom_Parent_Constructor**: The exported function
  `datom_parent(conn, table, version)` that resolves and returns a parent
  lineage record.
- **Parent_Record**: The pure-data, serializable list returned by the
  Datom_Parent_Constructor, containing `source`, `table`, `version`,
  `data_sha`, and `source_lineage`. Contains no live connection. Its
  `source_lineage` is consumed at write time to compute the derived table's
  union and is not persisted inside the recorded parent entry.
- **Recorded_Parent_Entry**: The persisted form of a parent in a derived
  table's metadata, containing exactly `source`, `table`, `version`, and
  `data_sha`. Does not include `source_lineage`.
- **Datom_Writer**: The exported function `datom_write()` that persists a
  table and records its lineage in metadata.
- **Conn**: A `datom_conn` object scoped to a single project's store,
  carrying `project_name` and `backend` and used by the storage dispatch
  layer. Each project has its own `Conn`; datom swaps connections per
  project and never expects one connection to reach across project stores.
- **Data_Sha**: A SHA-256 over a table's data (parquet), used as the data
  addressing and access-management unit; parquet is stored at
  `{table}/{data_sha}.parquet`.
- **Version**: The `metadata_sha`, a SHA over the metadata object (which
  itself includes `data_sha`); version to `data_sha` is a 1:1 relationship.
- **Metadata_Snapshot**: The versioned metadata JSON stored at key
  `{table}/.metadata/{version}.json` in a project's store.
- **Source_Lineage**: A list of flat, transitive non-derived (imported)
  source descriptors, each with `project`, `table`, and `version_sha`. It
  contains only imported roots, never intermediate derived generations.
- **Lineage_Union_Invariant**: The property, maintained at every write, that
  a derived table's `Source_Lineage` equals the deduplicated union of its
  parents' `Source_Lineage`. Because it holds at every prior write, each
  parent's recorded `Source_Lineage` is already fully flattened, so a
  one-level union over immediate parents covers all roots.
- **Lineage_Union_Helper**: An exported function (e.g.
  `datom_lineage_union()`) that takes a list of `Source_Lineage` lists and
  returns their deduplicated union.
- **Lineage_Reads**: The existing exported reads `datom_get_parents()` and
  `datom_get_lineage()` used to inspect a table's recorded parents and
  `source_lineage`.
- **Storage_Reader**: The internal dispatch helper
  `.datom_storage_read_json(conn, key)` that routes reads on `conn$backend`.
- **Parent_Validator**: An internal helper (e.g. `.datom_validate_parents()`)
  that validates the structure of a list of Parent_Records, mirroring
  `.datom_validate_source_lineage()`.

## Requirements

### Requirement 1: Parent record construction from a connection

**User Story:** As a data pipeline developer, I want a single constructor to
declare a parent from a connection, so that same-project and cross-project
parents are resolved identically and safely.

#### Acceptance Criteria

1. THE Datom_Parent_Constructor SHALL accept exactly three arguments: a
   `Conn`, a `table` name, and a `version`.
2. IF the `Conn` argument is not a `datom_conn` object, THEN THE
   Datom_Parent_Constructor SHALL halt construction and return an error
   indicating an invalid connection argument, without reading from the
   `Conn` store.
3. IF the `table` argument is not a single non-empty validated string, THEN
   THE Datom_Parent_Constructor SHALL halt construction and return an error
   indicating an invalid table argument, without reading from the `Conn`
   store.
4. IF the `version` argument is not a single non-empty string, THEN THE
   Datom_Parent_Constructor SHALL halt construction and return an error
   indicating an invalid version argument, without reading from the `Conn`
   store.
5. WHEN the Datom_Parent_Constructor is invoked with valid arguments and a
   reachable parent, THE Datom_Parent_Constructor SHALL read the
   Metadata_Snapshot from the `Conn` store at key
   `{table}/.metadata/{version}.json` using the Storage_Reader.
6. IF the read at key `{table}/.metadata/{version}.json` fails or the
   Metadata_Snapshot does not exist, THEN THE Datom_Parent_Constructor SHALL
   halt construction and return an error indicating the snapshot could not
   be read, without returning a Parent_Record.
7. WHEN the Metadata_Snapshot is read, THE Datom_Parent_Constructor SHALL
   extract `data_sha` from the Metadata_Snapshot.
8. IF the Metadata_Snapshot exists but does not contain a `data_sha` field,
   THEN THE Datom_Parent_Constructor SHALL halt construction and return an
   error indicating the snapshot is missing `data_sha`, without returning a
   Parent_Record.
9. WHEN the Metadata_Snapshot is read and contains a `source_lineage` field,
   THE Datom_Parent_Constructor SHALL capture the parent's `source_lineage`
   from the Metadata_Snapshot into the Parent_Record.
10. IF the Metadata_Snapshot is read and does not contain a `source_lineage`
    field, THEN THE Datom_Parent_Constructor SHALL set the Parent_Record's
    `source_lineage` to NULL.
11. THE Datom_Parent_Constructor SHALL set `source` to `conn$project_name`.
12. WHEN construction succeeds, THE Datom_Parent_Constructor SHALL return a
    Parent_Record containing exactly the fields `source`, `table`,
    `version`, `data_sha`, and `source_lineage`.
13. THE Datom_Parent_Constructor SHALL exclude any live `Conn` from the
    returned Parent_Record.
14. THE Datom_Parent_Constructor SHALL return a Parent_Record that is
    serializable as pure data.

### Requirement 2: Fail-fast on unreachable or nonexistent parents

**User Story:** As a data steward, I want parent construction to fail when a
parent cannot be read, so that unreachable or nonexistent parents are never
silently recorded.

#### Acceptance Criteria

1. THE Datom_Parent_Constructor SHALL accept exactly three arguments (conn,
   table, version) and SHALL NOT accept a `data_sha` argument.
2. THE Datom_Parent_Constructor SHALL derive `data_sha` solely from the
   Metadata_Snapshot located at `{table}/.metadata/{version}.json`.
3. IF the Metadata_Snapshot at `{table}/.metadata/{version}.json` is not
   found, THEN THE Datom_Parent_Constructor SHALL abort without returning a
   Parent_Record and SHALL raise an error identifying the table, the
   version, and `conn$project_name`.
4. IF the Metadata_Snapshot at `{table}/.metadata/{version}.json` is present
   but cannot be read or parsed, THEN THE Datom_Parent_Constructor SHALL
   abort without returning a Parent_Record and SHALL raise an error
   indicating that the snapshot could not be read or parsed.
5. IF the Metadata_Snapshot at `{table}/.metadata/{version}.json` is
   readable but its `data_sha` field is missing or empty, THEN THE
   Datom_Parent_Constructor SHALL abort without returning a Parent_Record
   and SHALL raise an error indicating that `data_sha` is absent from the
   snapshot.

### Requirement 3: Cross-project parents are first-class and identical in form

**User Story:** As a multi-project data engineer, I want cross-project
parents declared the same way as same-project parents, so that there is no
special-case logic to learn or maintain.

#### Acceptance Criteria

1. WHEN a caller declares a same-project parent by passing a `Conn` scoped
   to that project's store, THE Datom_Parent_Constructor SHALL produce a
   Parent_Record resolved against that `Conn`.
2. WHEN a caller declares a cross-project parent by passing a `Conn` scoped
   to a different project's store, THE Datom_Parent_Constructor SHALL
   produce a Parent_Record resolved against that `Conn`.
3. THE Datom_Parent_Constructor SHALL produce a Parent_Record with identical
   fields, field types, and structure regardless of whether the passed
   `Conn` is scoped to the same project or a different project.
4. THE Datom_Parent_Constructor SHALL derive the Parent_Record's `source`
   field exclusively from the passed `Conn`'s `project_name` value, and
   SHALL NOT compare project names to select a resolution path.
5. THE Datom_Parent_Constructor SHALL bind a parent to its `Conn` exactly
   once, at construction time, and SHALL NOT retain that `Conn` in the
   returned Parent_Record.
6. IF the passed `Conn` is `NULL`, is not a `Conn` object, or is not scoped
   to a valid project store, THEN THE Datom_Parent_Constructor SHALL reject
   the declaration, return an error indicating the `Conn` is invalid, and
   produce no Parent_Record.

### Requirement 4: Datom_Writer accepts only resolved parent records

**User Story:** As a data pipeline developer, I want `datom_write()` to
require resolved parent records, so that lineage is always complete and
auditable at write time.

#### Acceptance Criteria

1. WHEN `datom_write()` is invoked with `parents` non-NULL, THE Datom_Writer
   SHALL accept `parents` only as a list of one or more Parent_Records
   produced by the Datom_Parent_Constructor (`datom_parent()`), where each
   Parent_Record contains a non-NULL, non-empty `data_sha` field.
2. IF any supplied parent entry is missing the `data_sha` field, or its
   `data_sha` is NULL or an empty string, THEN THE Datom_Writer SHALL abort
   before persisting any data, return an error naming `datom_parent()` as
   the remedy, and leave storage and the local repository unchanged.
3. THE Datom_Writer SHALL NOT read any parent Metadata_Snapshot to enrich
   `parents` with `data_sha`.
4. THE Datom_Writer SHALL NOT auto-resolve parents, perform `$source` path
   resolution, or perform project-name matching.
5. THE Datom_Writer SHALL NOT reintroduce the superseded
   `parent_conns` / match-by-`project_name` mechanism.

### Requirement 5: Derived source_lineage and recorded metadata shape

**User Story:** As an auditor, I want each derived table to carry its own
flattened lineage and lean parent edges, so that provenance is durable and
independently readable without traversal or bloat.

#### Acceptance Criteria

1. WHEN the Datom_Writer persists a derived table with a non-empty list of
   Parent_Records, THE Datom_Writer SHALL compute the table's
   `source_lineage` as the deduplicated union of the parents'
   `source_lineage` values, deduplicating by the composite key
   {project, table, version_sha}.
2. WHEN the Datom_Writer persists a derived table with parents, THE
   Datom_Writer SHALL record the computed `source_lineage` in the derived
   table's own metadata.
3. WHEN the Datom_Writer records parents for a derived table, THE
   Datom_Writer SHALL record each parent as a Recorded_Parent_Entry
   containing exactly `source`, `table`, `version`, and `data_sha`.
4. THE Datom_Writer SHALL NOT persist any parent's `source_lineage` inside a
   Recorded_Parent_Entry.
5. WHEN the Datom_Writer records lineage for a derived table, THE
   Datom_Writer SHALL record the identical `parents` entries and
   `source_lineage` in both the derived table's local metadata and its
   versioned Metadata_Snapshot in the store.
6. IF the Datom_Writer persists a table with a NULL or empty `parents`
   argument, THEN THE Datom_Writer SHALL record no `parents` entries and
   SHALL NOT derive a parents-based `source_lineage` for that table.
7. WHERE a caller supplies an explicit `source_lineage` argument alongside
   non-NULL `parents`, THE Datom_Writer SHALL treat the derived union as
   authoritative and SHALL NOT require the caller to precompute
   `source_lineage`.

### Requirement 6: Data_Sha authoritativeness and audit invariant

**User Story:** As a security-conscious data owner, I want `data_sha` to
always come from the parent's own store, so that the access-management unit
cannot be forged by a caller.

#### Acceptance Criteria

1. THE Datom_Parent_Constructor SHALL set the Parent_Record `data_sha` to a
   value byte-for-byte identical to the `data_sha` field of the parent's
   Metadata_Snapshot read from the `Conn` store, and SHALL derive `data_sha`
   from no other source.
2. IF the parent's Metadata_Snapshot cannot be read or fails structural
   validation, THEN THE Datom_Parent_Constructor SHALL abort without
   returning a Parent_Record, so that no parent lineage is recorded.
3. THE Datom_Writer SHALL persist, for each Recorded_Parent_Entry, a
   `data_sha` value byte-for-byte identical to the `data_sha` carried by the
   corresponding Parent_Record, and SHALL obtain the persisted `data_sha`
   from no source other than the Parent_Record.
4. THE Datom_Parent_Constructor SHALL expose no parameter or argument
   through which a caller can supply, override, or influence `data_sha`.

### Requirement 7: Parent record structural validation

**User Story:** As a maintainer, I want parent records validated for shape
before use, so that malformed lineage is caught with a clear error.

#### Acceptance Criteria

1. WHEN the Datom_Writer receives a non-NULL `parents` argument, THE
   Parent_Validator SHALL verify that `parents` is an unnamed list (a list
   of entry lists, not a named list).
2. WHEN the Parent_Validator validates each parent entry, THE
   Parent_Validator SHALL verify that the entry is itself a list and that
   its fields `source`, `table`, `version`, and `data_sha` are each a single
   non-empty string.
3. IF `parents` is a named list, THEN THE Parent_Validator SHALL abort with
   an error indicating that `parents` must be a list of entry lists and not
   a named list, and SHALL NOT write any datom.
4. IF any parent entry is not a list, or is missing any of the fields
   `source`, `table`, `version`, or `data_sha`, or has any of those fields
   as a value that is not a single non-empty string, THEN THE
   Parent_Validator SHALL abort with an error identifying the first invalid
   entry by its position and the specific field or reason for failure, and
   SHALL NOT write any datom.
5. WHERE a parent entry carries a non-NULL, non-empty `source_lineage`
   field, THE Parent_Validator SHALL validate that field using the existing
   `source_lineage` structural rules and SHALL treat a NULL or empty
   `source_lineage` as valid.

### Requirement 8: Lineage union helper

**User Story:** As a data engineer, I want a canonical helper to union
`source_lineage` lists, so that composing lineage from multiple parents is
consistent and I do not reimplement deduplication.

#### Acceptance Criteria

1. THE Lineage_Union_Helper SHALL accept a list of zero or more
   `Source_Lineage` lists.
2. WHEN the Lineage_Union_Helper is given one or more `Source_Lineage`
   lists, THE Lineage_Union_Helper SHALL return their union deduplicated by
   the composite key {project, table, version_sha}, with each distinct entry
   appearing exactly once.
3. WHEN the Lineage_Union_Helper is given an empty list or only empty
   `Source_Lineage` lists, THE Lineage_Union_Helper SHALL return an empty
   list.
4. THE Lineage_Union_Helper SHALL preserve each retained entry's fields
   (`project`, `table`, `version_sha`) unchanged.
5. THE Lineage_Union_Helper SHALL be exported and documented with roxygen
   covering its parameter and return value.

### Requirement 9: Composable lineage inspection replaces the validator

**User Story:** As a CI operator or auditor, I want to inspect and, when
needed, recompute a table's lineage from existing reads, so that I do not
need a dedicated validator and cross-project reads use the appropriate
connection per project.

#### Acceptance Criteria

1. THE datom package SHALL remove the exported `datom_validate_lineage()`
   function.
2. WHEN `datom_validate_lineage()` is removed, THE datom package SHALL
   update NAMESPACE, the `_pkgdown.yml` reference index, its tests, and any
   documentation or engineering notes that reference it, so that R CMD check
   and the pkgdown build complete with zero errors.
3. WHEN a caller invokes `datom_get_parents()` on a derived table, THE
   Lineage_Reads SHALL return each recorded parent's `source`, `table`,
   `version`, and `data_sha`, sufficient to select the parent's project
   connection and its pinned version.
4. WHEN a caller invokes `datom_get_lineage()` with `depth = "source"` on a
   table, THE Lineage_Reads SHALL return that table's recorded
   `source_lineage`.
5. THE datom package SHALL provide a documented recipe showing how to
   recompute the parents' `source_lineage` union by reading each parent's
   lineage through the appropriate `Conn` and applying the
   Lineage_Union_Helper, and how to compare it against the derived table's
   recorded `source_lineage`.
6. THE documented recipe SHALL read each parent through a `Conn` scoped to
   that parent's project and SHALL NOT rely on a single `Conn` reaching
   across project stores.

### Requirement 10: Package quality and test isolation

**User Story:** As a package maintainer, I want the feature to meet CRAN
policy and test isolation rules, so that R CMD check stays clean and tests
never touch the network.

#### Acceptance Criteria

1. THE datom package R source SHALL contain only ASCII characters (byte
   values 0-127) in every `R/*.R` file added or modified for this feature.
2. THE datom package R source SHALL keep every line at or below 80
   characters in every `R/*.R` file added or modified for this feature.
3. THE datom package SHALL produce zero errors and zero warnings under R CMD
   check for this feature.
4. WHILE the datom test suite executes, THE datom test suite SHALL mock all
   S3 and HTTP egress such that zero real network requests are issued.
5. IF un-mocked S3 or HTTP egress is attempted during test execution, THEN
   THE datom test suite SHALL abort the affected test with an error
   indicating a network-guard violation and SHALL NOT complete the egress.
6. WHERE a test exercises cross-project parents, THE datom test suite SHALL
   use exactly two distinct mock stores.
7. WHEN a function is exported for this feature, THE datom package SHALL
   register that function in NAMESPACE and list it in the `_pkgdown.yml`
   reference index such that pkgdown site build completes with zero errors.
8. WHEN a function is exported for this feature, THE datom package SHALL
   provide roxygen documentation covering the function's parameters and
   return value.

## Out of Scope

- **A dedicated recursive lineage-audit tool.** Deep, recursive
  re-derivation of the full ancestor graph as a single function is not
  included; callers compose the provided reads and union helper, and a
  bespoke deep audit is a possible future follow-up.
- **Migrating external dp_dev / dpbuild callers** to the
  Datom_Parent_Constructor. The `datom_write()` `parents` contract break is
  intentional (pre-release), and because `datom_write()` now derives
  `source_lineage` from the parent records, downstream producers no longer
  precompute it, but that migration is tracked separately.
- **Governance-based automatic discovery** of a parent project's store
  location. The caller supplies the parent `Conn`.
