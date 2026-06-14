# Requirements Document

_Scope: **datom side** of the GOV_SEAM lift-out._

## Introduction

The GOV_SEAM lift-out is one atomic, coordinated change across two R packages. This
document specifies the changes **owned by `datom`** (the platform layer): removing the
governed write surface that moves to `datomanager`, extracting the data-side teardown
helper that stays in `datom`, and decoupling data-repo initialization from gov
registration. After the lift-out, `datom` must remain fully functional without
`datomanager` installed.

The changes here are mostly subtractive (removing helpers and exports that relocate) plus
two additive items that stay in `datom` (`datom_repo_delete()` extraction, and the
decoupling of `datom_init_repo()`). The complementary additions in `datomanager` are
specified in `datomanager/.kiro/specs/gov-seam-liftout/requirements.md`.

## Cross-Package Contract

The durable, bidirectional invariants that bind `datom` and `datomanager` — dependency
direction, prefix-equals-package, cross-package call discipline, the two-repos invariant,
the commit-message audit contract, and the `datom_conn` interface contract — are specified
in `contract.md` in this spec folder (source of truth). This document covers only the
one-time, datom-owned migration changes. Where a requirement below realizes datom's side of
a contract invariant, it cites the contract clause (for example, C1, C6).

## Glossary

- **Datom_Package**: The `datom` R package — the platform layer providing data read/write,
  versioning, git sync, and the `datom_storage_*` / `datom_repo_*` exports.
- **Datomanager_Package**: The `datomanager` R package — the governance layer that Imports
  Datom_Package.
- **GOV_SEAM_Write_Helper**: An internal (`.datom_gov_*`) function that writes to the gov
  repo or gov storage. There are nine, all relocating to Datomanager_Package.
- **Gov_Read_Helper**: An internal or exported function that reads gov state without writing
  it. These stay in Datom_Package.
- **Gov_Clone**: The local working copy of the governance repository.
- **Data_Repo**: A project's data repository (its `project.yaml` and data clone).
- **Solo_Project**: A project whose location authority is `project.yaml` in the Data_Repo;
  no governance attached.
- **Governed_Project**: A project whose location authority is `ref.json` in the gov repo.
- **datom_repo_delete**: The Datom_Package function that deletes the data GitHub repo and
  local clone; carries a `confirm` interlock and a `force_gov_attached` guard.

## Requirements

### Requirement 1: Remove the GOV_SEAM write helpers from datom

**User Story:** As a datom maintainer, I want the nine GOV_SEAM write helpers removed from
datom, so that the governed write surface is owned solely by datomanager.

#### Acceptance Criteria

1. THE Datom_Package SHALL NOT contain, after the lift-out, any of the nine
   GOV_SEAM_Write_Helper functions `.datom_gov_commit()`, `.datom_gov_push()`,
   `.datom_gov_pull()`, `.datom_gov_write_dispatch()`, `.datom_gov_write_ref()`,
   `.datom_gov_register_project()`, `.datom_gov_unregister_project()`,
   `.datom_gov_record_migration()`, or `.datom_gov_destroy()`.
2. THE Datom_Package SHALL retain in `R/utils-gov.R` only Gov_Read_Helper functions after
   the nine write helpers are removed.
3. THE Datom_Package SHALL NOT contain, after the lift-out, any internal caller within
   Datom_Package that references a removed GOV_SEAM_Write_Helper by name.

### Requirement 2: Remove the five exported gov functions from datom

**User Story:** As a datom maintainer, I want the five exported gov functions removed from
datom, so that they no longer occupy the `datom_*` public surface.

#### Acceptance Criteria

1. THE Datom_Package SHALL NOT export `datom_init_gov()` after the lift-out.
2. THE Datom_Package SHALL NOT export `datom_attach_gov()` after the lift-out.
3. THE Datom_Package SHALL NOT export `datom_decommission()` after the lift-out.
4. THE Datom_Package SHALL NOT export `datom_sync_dispatch()` after the lift-out.
5. THE Datom_Package SHALL NOT export `datom_pull_gov()` after the lift-out.
6. THE Datom_Package SHALL NOT retain in its `NAMESPACE` an export entry for any of the
   five removed function names.

### Requirement 3: Extract datom_repo_delete to stay in datom

**User Story:** As a datom user, I want data-side teardown to remain in datom, so that
solo-project teardown works without datomanager and governed teardown can reuse it.

#### Acceptance Criteria

1. THE Datom_Package SHALL export `datom_repo_delete()` performing data-side teardown:
   deletion of the data GitHub repo and the local clone.
2. WHEN `datom_repo_delete()` is called, THE datom_repo_delete SHALL require the `confirm`
   argument to be a single, non-missing, non-`NULL` character string exactly equal
   (case-sensitive, no surrounding-whitespace trimming) to the conn's `project_name` before
   performing any deletion, and SHALL NOT prompt for confirmation in a non-interactive
   session.
3. IF `datom_repo_delete()` is called with a `confirm` argument that is missing, `NULL`, not
   a single character string, or not exactly equal to the conn's `project_name`, THEN THE
   datom_repo_delete SHALL abort with an error indicating the confirmation value did not
   match the project name, leaving the data GitHub repo and the local clone intact.
4. IF `force_gov_attached` is `FALSE` and the conn is a Governed_Project, THEN THE
   datom_repo_delete SHALL abort with an error indicating the project is governed and
   directing the user to use `gov_decommission()`, leaving the data GitHub repo and the
   local clone intact, regardless of whether the session is interactive.
5. WHEN `datom_repo_delete()` is called with `force_gov_attached = TRUE` and the `confirm`
   argument satisfies criterion 2, THE datom_repo_delete SHALL proceed with data-side
   teardown on a Governed_Project conn.
6. THE datom_repo_delete SHALL default the `force_gov_attached` argument to `FALSE`.
7. WHEN the confirmation and governance guards in criteria 2-4 pass and the data GitHub repo
   or the local clone does not exist, THE datom_repo_delete SHALL continue teardown of the
   remaining existing target and report which targets were absent without raising an error.
8. WHEN the confirmation and governance guards in criteria 2-4 pass and both the data GitHub
   repo and the local clone exist, THE datom_repo_delete SHALL delete both targets and
   return an indication that data-side teardown completed successfully.

### Requirement 4: Decouple data-repo initialization from gov registration

**User Story:** As a datom user, I want `datom_init_repo()` to initialize only the data
repo, so that data-repo setup is independent of governance.

#### Acceptance Criteria

1. WHEN `datom_init_repo()` is called, THE Datom_Package SHALL initialize the Data_Repo
   without invoking any GOV_SEAM_Write_Helper.
2. THE Datom_Package SHALL NOT perform gov registration as part of `datom_init_repo()`.
3. WHEN `datom_init_repo()` completes successfully, THE Datom_Package SHALL leave the
   project as a Solo_Project with `project.yaml` as its location authority and no governance
   attached.
4. IF `datom_init_repo()` is called with a gov store argument, THEN THE Datom_Package SHALL
   initialize the project as a Solo_Project and SHALL NOT perform gov registration from that
   argument.

### Requirement 5: Retain gov read surface in datom

**User Story:** As a datom user, I want datom to keep reading gov state, so that portfolio
and location-resolution reads continue to work after the write surface relocates.

#### Acceptance Criteria

1. THE Datom_Package SHALL retain the gov read functions `datom_projects()` and
   `datom_pull()` as `datom_*` exports (contract C2).
2. THE Datom_Package SHALL retain the Gov_Read_Helper functions
   `.datom_gov_clone_exists()`, `.datom_gov_clone_open()`, `.datom_gov_clone_init()`,
   `.datom_gov_validate_remote()`, `.datom_gov_list_projects()`, and
   `.datom_gov_project_path()`.
3. THE Datom_Package SHALL retain the `R/ref.R` resolver functions
   `.datom_resolve_ref()`, `.datom_resolve_ref_from_clone()`, `.datom_check_ref_current()`,
   and `.datom_resolve_data_location()`.
4. THE Datom_Package SHALL read gov state (ref, dispatch, project listing) in conformance
   with the gov storage layout and serialization so that objects written by
   Datomanager_Package are read correctly (contract C8).

### Requirement 6: datom remains functional without datomanager

**User Story:** As a datom user, I want datom to work without datomanager installed, so that
the platform ships and operates independently.

#### Acceptance Criteria

1. WHERE Datomanager_Package is not installed, WHEN any exported `datom_*` function is
   invoked, THE Datom_Package SHALL complete its data management operations, including reads
   of gov state, without raising an error or warning that references Datomanager_Package
   (contract C1).
2. WHERE Datomanager_Package is not installed, WHEN Datom_Package is loaded via
   `library(datom)`, THE Datom_Package SHALL load and attach without producing an error or
   warning.
3. WHERE Datomanager_Package is not installed, IF a gov read function is called and the
   Gov_Clone does not exist, THEN THE Datom_Package SHALL abort with an error indicating the
   gov state is unavailable, without referencing Datomanager_Package and without mutating
   the Data_Repo.

### Requirement 7: Preserve the conn interface for datomanager

**User Story:** As a datom maintainer, I want the `datom_conn` fields preserved across the
lift-out, so that datomanager can read conn state reliably (contract C6).

#### Acceptance Criteria

1. THE Datom_Package SHALL include on every `datom_conn` object, whether the conn
   represents a Solo_Project or a Governed_Project, the twelve fields named exactly
   `gov_local_path`, `gov_root`, `gov_prefix`, `gov_region`, `gov_backend`, `gov_client`,
   `github_pat`, `project_name`, `backend`, `root`, `prefix`, and `region` (gov-scoped
   fields MAY be NULL on a Solo_Project).
2. THE Datom_Package SHALL set each of those twelve fields to the same value type and
   meaning it held before the lift-out, except `gov_backend`, which is newly introduced.
3. THE Datom_Package SHALL set `conn$gov_backend` to the backend (`"s3"` or `"local"`) of
   the governance store component, independent of the data backend (contract C6).
4. THE Datom_Package SHALL resolve the storage backend for gov-scoped operations from the
   governance backend rather than from `conn$backend` (contract C6).
5. THE Datom_Package SHALL expose on `conn$github_pat` the GitHub credential that
   Datomanager_Package uses to authenticate gov-repo pushes (contract C6, C7).

### Requirement 8: datom passes R CMD check clean after the lift-out

**User Story:** As a datom maintainer, I want datom to pass check cleanly, so that the
coordinated change is releasable.

#### Acceptance Criteria

1. WHEN `R CMD check` is run on Datom_Package after the lift-out, THE Datom_Package SHALL
   report zero errors and zero warnings.
2. WHEN `R CMD check` is run on Datom_Package after the lift-out, THE Datom_Package SHALL
   report no check note other than a benign system-time verification note (a note arising
   solely from the build host clock or a future file timestamp, e.g. "unable to verify
   current time").
3. THE Datom_Package SHALL NOT, after the lift-out, retain documentation (`man/*.Rd`) or
   `NAMESPACE` entries for the five removed gov functions or the nine removed write helpers.

### Requirement 9: Relocate datom's tests for the moved write surface

**User Story:** As a datom maintainer, I want tests for the relocated write helpers removed
from datom, so that datom tests only what it still owns.

#### Acceptance Criteria

1. THE Datom_Package SHALL NOT contain, after the lift-out, tests that call or reference, by
   name, any of the nine removed GOV_SEAM_Write_Helper functions.
2. THE Datom_Package SHALL NOT retain tests that exercise the removed GOV_SEAM_Write_Helper
   functions indirectly through `datom_init_repo()`.
3. THE Datom_Package SHALL retain tests covering the retained gov read surface
   (`datom_projects()`, `datom_pull()`, the Gov_Read_Helper functions, and the `R/ref.R`
   resolvers) and the extracted `datom_repo_delete()`.

### Requirement 10: Relinquish the gov git and gov-write surface

**User Story:** As a datom maintainer, I want datom to give up all gov-repo git and gov-write
responsibility, so that datomanager owns it cleanly and datom never reaches into the gov repo.

#### Acceptance Criteria

1. THE Datom_Package SHALL NOT export any function that performs a git operation on the gov
   repo (contract C7).
2. THE Datom_Package SHALL NOT perform any gov-repo git operation after the lift-out; its
   internal git utilities operate only on the Data_Repo (contract C7).
3. THE Datom_Package SHALL NOT provide a gov-storage write function for gov state; after the
   lift-out its gov-storage access is read-only and conforms to the gov storage layout
   (contract C8).
