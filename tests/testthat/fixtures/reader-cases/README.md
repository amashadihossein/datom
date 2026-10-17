# Shared reader cases

Small datom stores written by R datom, each saved with the result any reader must produce. R datom's test suite runs every one (`test-reader-cases.R`), and so does the Python reader ([amashadihossein/datom-py](https://github.com/amashadihossein/datom-py)), which fetches this folder from a pinned commit of this repo. A reader passes when it reads what R reads and refuses what R refuses.

For now this README is the written read contract. The rules each case exercises are the route cards in `dev/datom_pathways.md`: "Given table + version, read data", "Given a repo, decide whether this build can read it", and "Given a set + version, resolve its members".

## What a case is

```
<case-name>/
  case.json     what to call and the expected result
  storage.zip   a datom store exactly as R datom wrote it (and edited, for refusal cases)
```

`storage.zip` unpacks to a `datom/` folder: the folder a reader's local store points at holds it, so the store root is wherever you unpack the zip. It is a zip rather than a folder because every datom store has `.metadata/` folders, and `R CMD check` flags hidden folders in a package. Being binary also means git cannot change the line endings of files that are hashed byte for byte.

A case's store holds only the artifacts its call touches, plus the project manifest, to keep the cases small.

`case.json`:

| Field | Meaning |
|---|---|
| `description` | What the case is about |
| `generated_with` | The datom version that wrote it |
| `call` | What to run: `op` plus its arguments |
| `expect` | What R datom returned on this storage |
| `edited` | For cases made by editing the written files: what was changed |

Operations (`call.op`) and their arguments:

| `op` | Arguments | R | Python |
|---|---|---|---|
| `read_table` | `name`, `version` | `datom_read()` | `datom.read()` |
| `read_set` | `name`, `version` | `datom_get_set()` | `datom.get_set()` |
| `fetch_member` | `set`, `set_version`, `member`, `tags`, `version` | `datom_fetch_member()` | `datom.fetch_member()` |
| `history` | `name`, `n` | `datom_history()` | `datom.history()` |
| `list` | none | `datom_list()` | `datom.list_artifacts()` |

The project name is always `STUDY_001`. `version: null` means the current version.

A successful table read expects `version` (the full recorded id), `data_sha` (which data file was chosen), `nrow`, `ncol`, `colnames` and `arrow_types`. Types are compared by name rather than values: both languages read the same file bytes, and the hash check proves they are the same bytes. Names are as R arrow prints them. pyarrow prints two kinds differently, so a reader outside R rewrites them before comparing:

- **Factor (dictionary) columns.** pyarrow adds `ordered=0`, which R arrow leaves out, and spells `ordered=1` as `ordered`.
- **Labelled columns.** R arrow stores them as an R-only extension type, which the cases record as its storage type (`double`). Outside R the column is that storage type.

A refusal expects `{"ok": false, "error": "<name>"}`, using a name from the table below.

## Never edited once committed

A committed case is never regenerated or edited. New behaviour gets a new case. This keeps every future version of both readers honest about every old store, and is the rule for every fixture here (`../README.md`).

## Error names

Each language-neutral name maps to one R condition class. R's test checks the error's **own** class (its first), so an error re-wrapped on the way out fails. The mapping is `rc_error_class()` in `helper-reader-cases.R`; keep it and this table in step.

| Case error | R condition class | Python |
|---|---|---|
| `schema_unsupported` | `datom_schema_unsupported` | `SchemaUnsupported` |
| `schema_invalid` | `datom_schema_invalid` | `SchemaInvalid` |
| `kind_mismatch` | `datom_artifact_kind_conflict` | `KindMismatch` |
| `integrity_mismatch` | `datom_parquet_integrity_failure` (tables), `datom_set_integrity_failure` (sets) | `IntegrityMismatch` |
| `document_sha_missing` | `datom_set_document_sha_missing` | `DocumentShaMissing` |
| `set_member_malformed` | `datom_set_member_malformed` | `SetMemberMalformed` |
| `member_ambiguous` | `datom_member_ambiguous` | `MemberAmbiguous` |
| `member_not_found` | `datom_member_not_found` | `MemberNotFound` |
| `version_not_found` | `datom_version_not_found` | `VersionNotFound` |
| `version_ambiguous` | `datom_version_ambiguous` | `VersionAmbiguous` |
| `invalid_address` | `datom_invalid_sha` | `InvalidAddress` |

Warnings: `governance_attached` (a plain warning in R, matched by its message; `GovernanceAttachedWarning` in Python). It appears in a successful case's `expect.warnings`.

## Adding a case

1. Add a `make_case(...)` call to `dev/reader-cases/generate.R`. A new error name also needs a row in the table above and in `rc_error_class()`.
2. Install the datom under development (`devtools::install()`), then run `Rscript dev/reader-cases/generate.R` from the package root. It adds the new case and leaves the others alone. It stops if a refusal does not carry the class the table names.
3. Run `devtools::test(filter = "reader-cases")`.
4. In the Python reader, bump the pinned commit in its own commit. If it cannot handle the case yet, it lists the case as skipped with the reason, never silently.
