## Summary

Prepares datom for first CRAN submission by resolving all `R CMD check --as-cran` blockers, addressing reviewer-rejection-class issues, and polishing package metadata.

## Changes

### Workstream A — Mechanical blockers
- Move `glue` and `yaml` from Suggests to Imports (used unconditionally on core paths)
- Add `utils` to Imports (`utils::` calls in 8 files)
- Import `%||%` from rlang via `@importFrom` (used in 17 files, avoids undeclared base R ≥ 4.4 dependency)

### Workstream B — Metadata & docs
- Version bump `0.0.0.9001` → `0.1.0`
- Single-quote software names in DESCRIPTION per CRAN policy
- Fix LICENSE.md copyright holder to match Authors@R
- Rewrite NEWS.md as user-facing release notes (remove internal Phase narrative)
- Add `cran-comments.md` template

### Workstream C — Examples
- Add genuinely runnable examples to ~12 exported functions (store constructors, predicates, `is_valid_datom_repo`)
- Add `\dontrun{}` examples for all connection-based functions (complete local-backend setup patterns)
- Eliminate all undocumented exports

## What was tested

- `devtools::check()`: 0 errors | 0 warnings | 0 notes

## Notes

- `\dontrun{}` (not `\donttest{}`) is used for connection-based examples because `datom_init_repo()` pushes to a live GitHub remote — there is no offline mode. CRAN permits this for credential/network-gated examples.
- Spec persists at `.kiro/specs/cran-readiness/`
