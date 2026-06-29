CRAN readiness: fix blockers, metadata, and examples

Workstream A — Mechanical blockers (Req 1-3):
- Move glue and yaml from Suggests to Imports (used unconditionally)
- Add utils to Imports (utils:: calls in 8 files)
- Import %||% from rlang via @importFrom (used in 17 files, no base R floor)
- Regenerate NAMESPACE

Workstream B — Metadata & docs (Req 4, 6-9):
- Bump version 0.0.0.9001 -> 0.1.0
- Single-quote software names in DESCRIPTION ('git', 'GitHub', 'S3')
- Fix LICENSE.md copyright holder to match AUTHORS@R
- Rewrite NEWS.md as user-facing 0.1.0 release notes (remove Phase narrative)
- Add cran-comments.md template + .Rbuildignore entry

Workstream C — Examples (Req 5):
- Add genuinely runnable examples to store constructors/predicates and
  is_valid_datom_repo() (~12 exported functions, was zero)
- Add \dontrun{} examples with local-backend setup for all connection-based
  functions (init, write, read, list, history, sync, status, validate,
  summary, lineage, clone, pull, get_conn, projects, repo_*, storage_*)
- Convert all existing \dontrun{} to documented self-contained examples
- Zero \dontrun -> \donttest: datom_init_repo pushes to a live GitHub
  remote (no offline mode), so \dontrun is the CRAN-correct tag

Spec: .kiro/specs/cran-readiness/ (requirements, design, tasks)
devtools::check() passes: 0 errors | 0 warnings | 0 notes
