# datom Engineering Notes

> **Purpose**: Implementation gotchas and pitfalls, extracted from
> `.github/copilot-instructions.md` so the always-loaded instruction *core* stays small.
> This is the on-demand reference — **consult it before editing `R/`**. New gotchas and
> pitfalls go here, not in the core instructions.
>
> **How it loads**: Kiro pulls this in via a `fileMatch` steering rule when R files are in
> context; Copilot users reference it from chat when working in `R/`. The core
> `.github/copilot-instructions.md` links here prominently.
>
> **Maintenance**: living doc. Entries are vetted against the *current* code. Where a gotcha
> concerns the governance write surface, the pending `gov-seam-liftout`
> (`.kiro/specs/gov-seam-liftout/`) will relocate that surface to datomanager — those entries
> stay accurate until that change lands.
>
> **Vet note for this extraction**: corrected one stale reference — the gov sub-connection
> helper is now `.datom_conn_for(conn, "gov")`, not the former `.datom_gov_conn()`. Remaining
> entries were carried over unchanged and remain valid against the current codebase; a deeper
> line-by-line re-verification against source is a separate task.
>
> **gov-seam-liftout landed (2026-06-20).** The governance **write** surface (5 exports +
> 9 `.datom_gov_*` write helpers) has been removed from datom and now lives in `datomanager`.
> Entries below that concerned removed functions have been updated to the post-lift-out
> reality. datom keeps all gov **reads** + the data-side helpers (`datom_repo_delete`,
> `datom_repo_attach_governance`).

## Workspace and workflow notes

Standing facts about working in this repo. (The transient `datom-cv1` work-handoff section
that used to sit here was removed at spec completion, 2026-07-26 -- its durable content is
now in `dev/datom_specification.md`, `dev/datom_pathways.md`, the
`.kiro/specs/datom-cv1-identity/` docs, and the Gotchas below.)

**R toolchain is available here.** R 4.5.2 with `devtools`, `arrow`, `digest`, `testthat`,
`mockery`, `withr`, `git2r`, `rio`, `tibble`, `bit64`. Spec text that assumes "R is unavailable
in the authoring environment" is stale -- run the gates yourself. Write the runner to a temp
`.R` file and `Rscript` it; the shell mangles multi-line `Rscript -e`:

```r
options(crayon.enabled = FALSE)
suppressMessages(devtools::load_all(quiet = TRUE))
res <- as.data.frame(testthat::test_dir("tests/testthat",
  reporter = testthat::ListReporter, stop_on_failure = FALSE))
cat("PASS:", sum(res$passed), " FAIL:", sum(res$failed),
    " WARN:", sum(res$warning), " SKIP:", sum(res$skipped), "\n")
```

Full suite runs in ~13s. `R CMD check --as-cran` needs `_R_CHECK_FORCE_SUGGESTS_=false` unless
`covr` is installed, or it ERRORs on the missing suggested package. `gh issue view N` needs
`GH_PAGER=cat` or it hangs.

**Long commit messages: `git commit -F <tempfile>`, never a multi-line `-m`.** This is not a
style preference, it silently corrupts history. Demonstrated at commit `1bef5bd`: a multi-line
`-m` passed through this shell collapsed the entire message into a **742-character subject
line with an empty body**. `git log --oneline` becomes unreadable and the reasoning is no
longer separable from the summary. Write the message to a temp file and `git commit -F` it,
then verify with `git log -1 --pretty=format:"%s"` -- a subject over ~72 chars means it
collapsed.

**Do not pin a branch head in this file.** It went stale three times in four commits on
`spec/datom-cv1-identity` for a structural reason: the commit that records the head changes
the head it just recorded. Read it from `git log --oneline -1`, and find the last code-bearing
commit with `git log --oneline -1 -- R/ man/ tests/ vignettes/`.

**In a git worktree, `.git` is a FILE, and three tools silently misbehave because of it.** Any
tool that decides "is this a git repo?" with a *directory* test gets the wrong answer in a
worktree, and none of the three says so. All bit during the 0.1.2 CRAN fix, worked from
`../datom-cran-fix`:

| Tool | What happens | Status |
|---|---|---|
| `R CMD build` | its built-in exclusion covers a `.git` *directory*, so the pointer file lands in the tarball as `datom/.git`, and `--as-cran` raises "hidden files ... most likely included in error" | fixed -- `^\.git$` added to `.Rbuildignore`, which covers any checkout shape |
| `devtools::submit_cran()` | `devtools:::flag_release()` opens with `if (!uses_git(pkg$path)) return(invisible())` and `uses_git()` is `dir_exists(path(path, ".git"))`, so **no `CRAN-SUBMISSION` is written** -- and the "don't forget to tag this release" reminder, one line above the write, never prints either | not fixable here; **verify the artifact exists after every submission from a worktree**, or submit from a normal clone |
| `.gitignore` for `CRAN-SUBMISSION` | the rule was added on `spec/datom-sets` only (`9600db0`), so on a `main` checkout the artifact is untracked **and unignored** | never `git add .` in the submitting worktree; stage by name |

The common shape: a green run is not evidence, because each failure is a step that quietly did
not happen. The submission itself is unaffected in every case -- only local bookkeeping is
skipped, which is exactly why it goes unnoticed. Recovery for the middle one is mechanical:
rebuild the record from `main`'s head (confirm it has not moved) plus the built tarball's mtime
in the R temp directory, then check `usethis:::get_release_data()` parses it.

## Gotchas

- **`return()` inside a `tryCatch` handler returns from the HANDLER, not the enclosing function --
  and the code after the `tryCatch` still runs.** This shipped as a live defect in
  `.datom_check_git_current()` (#104, fixed 2026-08-26): the fetch-failure handler warned and
  `return(invisible(TRUE))`d, which looked like "give up and pass" but only ended the handler, so
  execution continued and compared `HEAD` against **stale cached** upstream refs -- aborting an
  offline developer for being behind a remote they could not reach. It is silent because the warning
  still prints, so the log looks exactly as intended. The shape that works: have the handler
  **return a value**, then branch on it outside the `tryCatch`
  (`fetched <- tryCatch({...; TRUE}, error = function(e) {...; FALSE}); if (!fetched) return(...)`).
  Worth grepping for whenever a handler's body ends in `return()`.
- **A metadata field name that is CLASSIFIED but not yet WRITTEN is invisible to carry-forward, so
  classifying one early is not free.** The keep-unfamiliar-fields rule
  (`.datom_carry_unknown_fields()`) rescues exactly the names a build **cannot** place -- so the
  moment a name appears in `.datom_metadata_identity_fields` or
  `.datom_metadata_excluded_fields`, the rule stops seeing it. If a document then arrives from a
  newer datom carrying that field, this build rewrites the document without it. On the *not-identity*
  list the loss is **silent**: the field takes no part in `metadata_sha`, so no version moves and
  nothing in the output says anything happened. `document_sha` is the live example and the reason this
  entry exists -- classified by the reader-side schema work before any code produced it, and now the
  one name in the vocabulary that no builder emits. It is safe only because the task that starts
  writing it puts it in `version_history.json`, whose entries are appended to rather than rebuilt.
  **So: classify a field in the same change that starts writing it.** If you genuinely must classify
  earlier, add the name to the exception vector in the classification test
  (`test-utils-sha.R`) with the reason, which is what makes the next person meet the decision instead
  of inheriting it.
- **`R/` is sourced ALPHABETICALLY, so a namespace-level constant may not be built from values
  defined in a file that sorts later.** DESCRIPTION declares no `Collate`, so the order is filename
  order and nothing else. Hit while adding `R/forward-compat.R`, which needs the union of two
  vectors that live in `R/utils-sha.R`: `f` sorts before `u`, so a constant joining them would be
  evaluated before either existed and the package would fail to **install** -- not at call time,
  where it would be obvious. The fix is to make it a **function**, which looks them up when called;
  it also cannot then fall out of step with either half. `R/manifest-upgrade.R`'s header records the
  same hazard from the other side, where a lookup table holds function objects and so every entry
  must be defined above it in that same file. Two rules, one cause: **anything evaluated while the
  namespace is being built can only see what has already been sourced.**
- **A `cli::cli_alert_warning()` is a MESSAGE, not a condition of class `warning`.** Test it with
  `expect_message()`; `expect_warning()` fails and reads as "the code did not warn at all", sending
  you after a nonexistent bug. Applies to every `cli_alert_*` -- only `cli::cli_warn()` signals a
  real warning.
- **cli pluralization**: `{?s}` requires a quantity reference immediately before it (e.g., `{length(x)} variable{?s}`). Without the quantity, cli throws a confusing error.
- **git2r::default_signature()**: Fails on freshly `git2r::init()`'d repos that lack local config. Always call `git2r::config(repo, user.name = ..., user.email = ...)` after init.
- **git2r::merge()**: Expects a string (branch name), not a branch object. Use `upstream_ref$name`.
- **cli dot-literals**: In cli >= 3.4.0, `{.something}` inside any `cli_*()` call is interpreted as a cli style, not an expression. Wrap **any** function call or variable starting with `.` in parentheses: `{(.datom_build_storage_key(...))}`, `{(.sandbox_storage_label(store$data))}`. This applies to `cli_li`, `cli_alert_*`, `cli_abort`, etc. — not just `cli_abort`.
- **glue + cli markup incompatibility**: `glue::glue()` parses `{...}` itself, so passing a cli-markup string like `"Mismatch for {.val {name}}"` through `glue()` will fail or mangle output. Keep cli markup out of strings passed to `glue()`. For values stored in variables (e.g. a `message` field built in a helper) use `paste0()` to assemble the string; call `cli::cli_alert_*()` separately for display, passing the cli markup directly to the cli function rather than through a variable.
- **`datom_history()` returns full SHAs by default**: `short_hash = FALSE` is the default. The `version` column is a functional identifier meant to be passed back to `datom_parent(conn, table, version)` and `datom_get_lineage(version=)` -- those open `{table}/.metadata/{version}.json`, so an 8-char abbreviation silently fails with "file not found". Use `short_hash = TRUE` only for display purposes.
- **`source_lineage` self-entry bootstrap**: `datom_sync()` auto-populates `source_lineage = [{project, table, version_sha}]` for imported tables. The `version_sha` in that self-entry uses `data_sha` (the parquet content SHA), NOT `metadata_sha`. This avoids a circular dependency: `metadata_sha` is computed from the metadata which includes `source_lineage` which would need to embed `metadata_sha`. `data_sha` is content-addressed and computed before metadata is assembled. Any future change to the auto-self logic must preserve this ordering.
- **Walker invariant for lineage traversal**: Code that walks lineage must follow `parents`, NEVER `source_lineage`. `source_lineage` entries are terminal leaves -- they describe raw sources, not traversable edges. For imported tables, the self-entry in `source_lineage` creates a fixed point that would produce an infinite loop if followed. `datom_get_lineage()` is intentionally read-only with no recursion, and the composable lineage-consistency recipe (below) is likewise a set of reads, not a walk.
- **Lineage consistency is a composable recipe, not a dedicated function**: `datom_validate_lineage()` was removed. `datom_write()` derives a derived table's `source_lineage` from its parents' union at write time and lineage is version-pinned, so a recompute equals the recorded value in normal operation. To check consistency, compose existing reads: `datom_get_parents(conn, name)` -> for each parent read `datom_get_lineage(parent_conn, parent$table, version = parent$version, depth = "source")` through a conn scoped to that parent's project -> `datom_lineage_union(...)` -> compare to `datom_get_lineage(conn, name, depth = "source")`. This honors the one-connection-per-project model (each parent is read through its own conn) and keeps semantic checks in the caller's workflow, orthogonal to `datom_validate()`'s git/S3 storage-consistency pass.
- **`.datom_git_commit()` is idempotent**: Returns HEAD SHA (instead of erroring) when staged files are unchanged. This is by design — enables safe re-runs after partial failures in the local → git → S3 pipeline.
- **metadata SHA uses JSON canonical form**: `.datom_compute_metadata_sha()` hashes `jsonlite::toJSON()` output with `serialize = FALSE`, not the R object. This is critical — R's `serialize()` is type-sensitive (`10L` ≠ `10`), so metadata round-tripped through JSON would produce a different SHA. Always test SHA stability with a JSON round-trip.
- **metadata SHA selects fields by ALLOWLIST, and the obligation runs the other way from what you
  would guess.** `.datom_compute_metadata_sha()` hashes exactly the fields named in
  `.datom_metadata_identity_fields` and ignores every other key. So **adding a field to a metadata
  builder without classifying it silently removes it from identity** -- the opposite of the old
  exclusion-list behaviour, where an unclassified field silently *entered* identity. (Superseded
  wording, retained because it inverts: "adding new metadata fields that should NOT affect
  versioning must be added to the `volatile` vector".) Every new field goes in one of two places:
  `.datom_metadata_identity_fields` if it is content, `.datom_metadata_excluded_fields` if it is
  not. The test `every field a metadata builder emits is classified` derives its inventory from the
  builder rather than hardcoding names, so it **fails** until you choose -- and it is the only test
  that catches this direction, because an ignored field leaves every pinned hash untouched
  (verified by adding a junk builder field: the goldens stayed green, that test went red).
- **The exclusion list is not the same idea as "volatile".** `parquet_sha`, `size_bytes`,
  `column_hashes`, `created_at` and `datom_version` are volatile in the drift sense;
  `schema_version` and `document_sha` are on the list for their own reasons (container format, and
  stored-bytes integrity). Read the comment block above each constant rather than assuming the
  rationale.
- **version_history dedup guard**: `.datom_write_metadata_local()` skips appending when the latest entry has the same version SHA. This prevents duplicates but means the guard relies on metadata_sha correctness.
- **`datom_pull()` is git-only**: No S3 manifest refresh — git is the source of truth for all metadata. The manifest is committed to git and pulled with everything else.
- **`governance.json` mirror -- git canonical, storage derived**: The git copy at `.datom/governance.json` is written and committed first; the storage mirror at `{prefix}/datom/.metadata/governance.json` is pushed in the same step. Never write only one. If the mirror is missing, `.datom_sync_governance_json(conn)` regenerates it from the git copy. The file is write-once -- do not update it after creation.
- **S3 namespace check swallows connectivity errors**: `.datom_check_namespace_free()` in `datom_init_repo()` warns but doesn't fail on network errors — offline init still works, S3 push will fail later anyway.
- **`git2r::clone()` target path**: Must not exist or must be an empty directory. `datom_clone()` validates this upfront.
- **`paws.storage` has no STS**: `sts` is in `paws.security.identity`, not `paws.storage`. Validation uses `HeadBucket` only (validates both credentials and bucket access).
- **Storage abstraction**: Business logic must call `.datom_storage_*()`, never `.datom_s3_*()` or `.datom_local_*()` directly. The dispatch layer in `R/utils-storage.R` routes based on `conn$backend`.
- **Two key shapes, and mixing them double-prefixes silently**: `.datom_build_storage_key(prefix, ...)` returns a **FULL** key (`{prefix}/datom/{...}`) and is **backend-internal** -- called only from `.datom_s3_*()` / `.datom_local_*()`, which prepend the prefix themselves. The `.datom_storage_*()` dispatch layer takes **RELATIVE** keys (everything after `{prefix}/datom/`). So business logic must never pass `.datom_build_storage_key()` output to `.datom_storage_*()`: the result is `{prefix}/datom/{prefix}/datom/...`, and because the write succeeds at a wrong location nothing errors. Build relative keys with the helpers in `R/utils-path.R`: `.datom_artifact_payload_key(name, sha, kind)`, `.datom_artifact_meta_key(name, which)`, `.datom_artifact_snapshot_key(name, metadata_sha)`. They also apply the `.datom_validate_name()` / `.datom_validate_sha()` guards -- several former call sites omitted them, and an unvalidated value spliced into a key escapes the namespace on the local backend via `fs::path()`.
- **Payload key vs snapshot key are different directories**: `{name}/{data_sha}.{parquet|json}` is the payload, addressed by **content**; `{name}/.metadata/{metadata_sha}.json` is the versioned metadata snapshot, addressed by **version**. For a set both end in `.json`, which is precisely why they are easy to confuse -- use the two distinct helpers rather than assembling either by hand.
- **`datom_conn` has two clients**: `client` (data store) and `gov_client` (governance store). Use `.datom_conn_for(conn, "gov")` to create a sub-connection for governance operations (this replaced the former `.datom_gov_conn()` helper).
- **`conn$root` is backend-neutral**: S3: root = bucket name. Local: root = directory path.
- **`conn$client` is NULL for local backend**: `.datom_local_*()` functions use `conn$root` + `conn$prefix` directly via `fs::`. Never check `is.null(conn$client)` to determine backend — use `conn$backend` instead.
- **`datom_store_local$path` vs `datom_store_s3$bucket`**: Store components have backend-specific field names. Use `.datom_store_root()` accessor for backend-neutral access.
- **`.datom_storage_delete_prefix()` local backend returns `1L`, not object count**: The local backend removes the directory and returns `1L` (removed) or `0L` (not found). The S3 backend returns the count of deleted objects. Tests and callers that expect a file count will fail -- use structural checks (`dir_exists`) to verify deletion on local.
- **`ref.json` lives at governance store**: Created by `datom_init_repo()`, resolved by `.datom_resolve_ref()`. Contains `current` data location (bucket/prefix/region).
- **Ref resolution asymmetry**: Conn-time ref failure is **warn-only** (governance informs, does not gate). Write-time ref failure is a **hard abort for any reason** (`.datom_check_ref_current()`) — writing without a verified location risks orphaning data, there is no safe fallback. Reads don't re-check — stale conn fails cleanly and the user rebuilds.
- **Migration detection is role-aware**: `.datom_resolve_data_location()` compares `store$data` location vs ref location. Developer mismatch → auto-pull git and re-read `project.yaml` (errors if still disagrees). Reader mismatch → warn + proceed with ref-resolved location using the reader's existing credentials.
- **Backend labels should be lookup-based, not binary**: Prefer `c(s3 = "S3", local = "local")[conn$backend] %||% conn$backend` over `if (conn$backend == "s3") ... else ...`. New backends (GCS, etc.) become one-line additions. Applies to UI strings; dispatch still uses `switch()` in `utils-storage.R`.
- **`datom_init_repo()` validates before side effects**: All store/repo validation happens before any filesystem or git operations. On failure, nothing is left behind.
- **`project.yaml` two-component structure**: `storage.governance` + `storage.data` — each has its own `type`, `bucket`, `prefix`, `region`. Secrets are never persisted.
- **Two repos, never one commit touching both**: governance and data live in separate git repos with separate histories. **Post-lift-out, datom only writes the data repo** (`datom_write`, `datom_sync`, `datom_init_repo`, `datom_repo_attach_governance`, `datom_repo_delete`). All gov-repo writes (register, dispatch/ref, decommission pruning, gov init) now live in `datomanager`. Any operation that spans both repos (e.g. `datomanager::gov_attach()`) produces two distinct commits in two histories — datomanager commits the gov repo itself and routes the data-repo commit through datom's exported `datom_repo_*` helpers.
- **Gov files live at `projects/{project_name}/`**: `dispatch.json`, `ref.json`, `migration_history.json` are project-scoped under `projects/` in both the gov repo and gov storage. They are NOT in the data repo's `.datom/` anymore. Anything reading those paths must use the gov clone (`conn$gov_local_path`) or `gov_client` (storage), never the data clone.
- **`# GOV_SEAM:` markers are gone — the seam is now the package boundary**: before the lift-out, gov-write helpers in `R/utils-gov.R` were tagged `# GOV_SEAM:`. Those nine write helpers are removed; `R/utils-gov.R` now holds only gov-**read** helpers (none seam-marked). Do not reintroduce gov-write code in datom — it belongs in `datomanager`. The port contract (helper inventory + commit-message strings + storage layout) is preserved in `dev/datom_specification.md` → "Governance Repository Contract".
- **`datom_init_repo()` is data-only (post-lift-out)**: it initializes the data repo and leaves the project a Solo_Project — no gov clone bootstrap, no `projects/{name}/*.json`, no `.datom/governance.json`, no gov namespace check. A `store$governance` component is silently ignored for registration. Governance attaches later via `datomanager::gov_attach()`, which calls `datom_repo_attach_governance()` for the data-side pointer.
- **`datom_repo_attach_governance()` writes the data->gov pointer (C4)**: it is the only exported, C4-compliant way to write `.datom/governance.json` (git canonical) + its data-storage mirror. `datomanager::gov_attach()` MUST route the data-repo write through it (datomanager never mutates the data repo directly). Mirror failure warns but does not abort — the git copy is canonical. Guards abort before any write: non-developer conn, NULL `conn$path`, empty `gov_repo_url`, invalid `gov_store`, missing `.datom/project.yaml`.
- **`.datom_sync_data_metadata()` is the data-only half of the old `datom_sync_dispatch()`**: `datom_sync_dispatch()` (removed) did gov-write AND data-side metadata sync. The data-side half (mirror manifest + per-table metadata to the data store; no gov) was kept as this internal helper. Callers: `datom_validate(fix = TRUE)` and `datom_write(data = NULL, name = NULL)`. The gov-write half is `datomanager::gov_sync_dispatch()`.
- **Role-aware ref reads**: `.datom_resolve_data_location()` branches on presence of `conn$gov_local_path`. Developer (clone present) reads `projects/{name}/ref.json` from local gov clone (offline-friendly, reflects last gov pull — now `datomanager::gov_pull()`). Reader reads via `gov_client` from storage. Write-time guard `.datom_check_ref_current()` ALWAYS reads from storage (no clone fallback) to catch stale clones.
- **`datom_repo_delete()` requires literal confirm**: `confirm = "{project_name}"` must match exactly (case-sensitive, no trimming). No interactive prompts (must be scriptable). It deletes the data GitHub repo + local clone only — NOT the data store namespace (use `datom_storage_delete_prefix()` for that) and NOT the caller-owned store root. Refuses governed projects (`gov_root` non-NULL) unless `force_gov_attached = TRUE` — solo teardown is the normal path; governed teardown goes through `datomanager::gov_decommission()`, which passes the force flag.
- **`datom_repo_delete()` ownership boundary**: it owns the GitHub repo + local clone, nothing in storage. For solo local-backend sandboxes the data store directory must be mopped up separately (see `.sandbox_wipe_local_component()` in `dev/dev-sandbox.R`). `datom_storage_delete_prefix()` removes the `datom/` namespace inside the store root but never the root itself (caller-owned).
- **NA-safe optional-string guards**: `nzchar(NA)` returns `NA`, which propagates into `if(...)` as "missing value where TRUE/FALSE needed". For optional fields that may round-trip through yaml/json (e.g. `conn$prefix`), guard with `!is.null(x) && !is.na(x) && nzchar(x)` and wrap the `if` predicate in `isTRUE(...)`. Pattern is in `.datom_local_delete_prefix` / `.datom_s3_delete_prefix`.
- **gov teardown / `.datom_gov_destroy()` moved to datomanager**: the whole-gov-repo teardown helper (refuses if registered projects exist unless forced) was one of the nine removed write helpers. `dev/dev-sandbox.R` still references `datom:::.datom_gov_destroy()` and `datom_decommission()` in its **gov** teardown path — that path is now broken until datomanager provides the equivalents. The **solo** sandbox path (`attach_gov = FALSE` + `datom_repo_delete()`) works standalone; use `dev/e2e-solo-local.R` for datom-only E2E. The legacy `dev/e2e-test-local.R` (gov-attached) references removed functions and will not run until datomanager lands.
- **`gov_local_path` defaults to `tools::R_user_dir("datom","data")/<repo_name>`**: `datom_init_gov(gov_local_path = NULL)` resolves to the user data directory, never CWD. This avoids polluting a package source tree or any other working directory the user happens to be in. One gov clone serves many data projects. `.datom_gov_clone_init()` validates remote URL on existing dirs and errors on mismatch.
- **`datom_init_gov()` idempotence is remote-aware**: The early-return guard checks both local `projects/.gitkeep` AND that `git2r::remote_ls()` returns at least one ref. If the remote was wiped/recreated and is now empty, the function re-pushes the local skeleton (with `pull_first = FALSE`) instead of silently no-oping. A completely unreachable remote (fetch errors) propagates as an error -- it does not silently succeed.
- **`.datom_git_push()` accepts `pull_first = TRUE` (default)**: Callers that already know the remote is empty (first push to a new repo, issue #20 re-push after remote wipe) pass `pull_first = FALSE` to skip the pre-push fetch/merge. This avoids libgit2 errors when the remote has no refs yet. Never pass `pull_first = FALSE` for routine pushes to an established remote.
- **`ref.json` carries `current$type`**: Records the data backend (`"s3"` or `"local"`). Set by `.datom_create_ref()` from `.datom_store_backend(data_store)`. Readers depend on this to identify the backend without already holding a store -- e.g. `datom_projects()` populates `data_backend` from this field.
- **Storage list dispatch returns full keys**: `.datom_storage_list_objects(conn, prefix)` and the S3/local backends both return keys in their full storage-key form (`"{prefix}/datom/..."`), NOT relative to the prefix arg. Callers extract project names / paths via regex; do not assume relative-to-prefix output.
- **`.datom_gov_list_projects()` is a pure read**: lives in `R/utils-gov.R`, which after the lift-out holds **only** gov-read helpers. Read helpers stay with datom; only gov **writes** moved to datomanager. Same rule applies to any future `.datom_gov_read_*()` helper — keep reads in datom.

- **PAT plumbing: `.datom_git_pull()`/`.datom_git_push()` accept `pat` but callers must pass it**: the credential helper `.datom_git_credentials(url, pat)` returns NULL for a NULL/empty PAT (so public repos work unauthenticated), which means a caller that forgets `pat = conn$github_pat` silently falls back to unauthenticated and fails only on private repos. All callers pass it now; guard against regressions with `grep -rn "\.datom_git_pull(\|\.datom_git_push(" R/ | grep -v "pat ="` (should return only non-caller lines). `.datom_gov_clone_init()` takes a `pat` param threaded to the clone.
- **`.datom_git_push()` sets upstream tracking after a successful push**: `git2r::push()` does NOT set upstream. Without it, `.datom_git_pull()` and `.datom_check_git_current()` no-op (their `branch_get_upstream()` is NULL), so on the *initializing* developer's machine `datom_pull()` silently does nothing and the stale-state guard always passes. After a successful push, if upstream is NULL, `.datom_git_push()` fetches (so the remote-tracking ref exists) then `branch_set_upstream()`; the whole upstream step is wrapped in tryCatch -> `cli_warn` so it never fails an already-successful push. Clones are unaffected (git sets upstream on clone), and the `is.null(upstream)` guard makes it a no-op on established branches.
- **`datom_clone()` must set a local git identity**: like `datom_init_repo()`, it calls `.datom_git_ensure_local_identity()` on the fresh clone. Without it the first `datom_write()` after a clone fails inside `git2r::commit()` ("user.name not found") on a host with no global git config (CI, fresh box).
- **Validate SHA-like inputs before splicing into a storage key**: `.datom_validate_sha(x, arg)` (in `R/utils-validate.R`) enforces 6-64 lowercase hex. Call it wherever a user-supplied `version`/`data_sha` becomes part of a key — `datom_get_lineage()` (version, non-NULL), `datom_parent()` (version), `.datom_read_parquet()` (data_sha). On the local backend an unvalidated `"../../x"` escapes the namespace via `fs::path()`. NB: `datom_read()`'s `.datom_resolve_version()` intentionally accepts short prefixes; the 6-char minimum covers that, so do NOT add the validator there. `datom_get_parents()` inherits the check by delegating to `datom_get_lineage()`. (Test fixtures for these functions must use hex versions/SHAs, not placeholders like `"v_dm_9f3"`.)
- **Namespace-check S3 client in `datom_init_repo()` needs `session_token`**: the temporary check client is built directly via `.datom_s3_client()`; pass `session_token = store$data$session_token` or STS temporary creds make the HeadObject fail, the tryCatch downgrades it to a warning, and the "namespace already occupied" guard is silently skipped. No `endpoint` is available at that call site (neither `datom_init_repo()` nor the store carries one).
- **Developer conn cross-check compares BOTH root and prefix**: `.datom_get_conn_developer()` checks `project.yaml` root AND prefix against the store, normalizing both prefixes with `.datom_normalize_prefix()` (so NULL/"" compare equal). Two projects can share a bucket under different prefixes, so a matching root is not sufficient — a wrong-prefix store would otherwise silently operate on the other project's namespace.
- **`.datom_storage_rel_key()` strips the prefix literally, not as a regex**: use `startsWith()` + `substring()`, never `sub(paste0("^", ns_root), ...)`. Prefixes may contain regex metacharacters (`.`, `+`, `(`), which corrupt a regex-based strip in `datom_storage_copy()`/`datom_storage_verify()`.
- **Manifest `size_bytes` uses `as.numeric()`, not `as.integer()`**: `.datom_update_manifest_entry()` reads `size_bytes` as numeric; `as.integer()` returns NA above 2^31 (2 GB) and poisons `summary$total_size_bytes`. `version_count` stays integer.
- **`.datom_mask_secret(secret, reveal_prefix = TRUE)`**: default reveals the first 4 chars (fine for GitHub PATs — `ghp_`/`github_pat_` is a public type tag, and AWS access-key `AKIA` prefix is an identifier, not entropy). The `datom_store_s3`/`datom_store_s3_creds` print methods pass `reveal_prefix = FALSE` for `secret_key` and `session_token` so those are masked fully. `datom_store` objects hold plaintext credentials in memory — SECURITY.md warns against `saveRDS()`/`.RData` of stores.

- **A compatibility check must sit OUTSIDE any handler that softens read errors.** Three of the
  manifest readers wrap their read in `tryCatch`, and `.datom_check_schema_version()` placed inside
  one produces a different outcome at each site: `datom_list()` / `datom_summary()` reword the
  abort as "Could not read manifest ... Underlying error: <the real message>", demoting the only
  actionable line to a footnote, and `datom_status()` is worse -- its handler turns errors into
  `available = FALSE` and **continues**, so that command alone would stay silent while the others
  stopped. The shape that works: read the document inside the handler, run the check on the
  returned object outside it. `datom_status()` needed restructuring to hold both properties at once
  (an unreachable bucket is still reported, not fatal; a too-new repo is fatal), so if you touch
  that block keep both its tests. Same rule for any future document-level contract check.
- **`{.datom_supported_schema}` is cli markup, not a value** -- a concrete instance of the
  dot-literal gotcha above, and easy to miss because the message still renders (the ceiling just
  vanishes, so "supports up to v" reads as truncated). Splice it as
  `{(.datom_supported_schema)}`. A test asserts the rendered message contains `supports up to v2`
  precisely so this cannot regress into a silently incomplete abort.
- **`_pkgdown.yml` index must be kept in sync**: Adding a new exported symbol requires a matching entry in `_pkgdown.yml`. `pkgdown::build_site()` errors with "N topics missing from index" otherwise. Check after every phase that adds exports.
- **Non-ASCII characters in R source and vignettes**: R CMD check warns on any non-ASCII character in `R/*.R` files (even in comments), and pkgdown/knitr can silently mangle them in `.Rmd` vignettes too. Use only ASCII everywhere -- `--` instead of em-dash, `->` instead of `->`, `...` instead of ellipsis (`\u2026`), straight quotes. Bulk-check with `LC_ALL=C grep -lr '[^[:print:][:space:]]' vignettes/*.Rmd R/*.R`. **Scope note:** the ASCII rule covers `R/*.R` and `vignettes/*.Rmd` *source* only. The generated `README.md` legitimately contains non-ASCII smart-typography (en-dashes, curly quotes) because `output: github_document` applies pandoc smart punctuation to the ASCII `README.Rmd` source. This is normal, pre-existing, present on `main`, and does **not** trip R CMD check -- do NOT "fix" it. Exclude `README.md` from ASCII sweeps.
- **pkgdown renders every `vignettes/*.Rmd`, regardless of the `_pkgdown.yml` index**: to *exclude* an article from the built site you must physically relocate the `.Rmd` out of `vignettes/` (e.g. into build-ignored `dev/`), not just drop it from the `articles:` index. Conversely, every `.Rmd` left in `vignettes/` MUST appear in exactly one `articles:` group or `pkgdown::build_site()` is noisy/incomplete. Verify the index matches disk: parse `_pkgdown.yml`, `setdiff()` the indexed basenames against `basename(Sys.glob("vignettes/*.Rmd"))` both ways -- both must be empty. (The earlier index gotcha below is the `reference:`/exports analogue of this.)
- **Deferred vignette suite lives in `dev/vignettes-deferred/`**: after the GOV_SEAM lift-out, the 9 gov-interface articles (S3 promotion, handoff, second-engineer, credentials, buckets/prefixes, and the `ref.json`/`governance.json`/`dispatch`/`two-repos` design notes) plus their `resume_article_4-8.R` scripts were parked there verbatim (build-ignored via `^dev$`), blocked on datomanager's gov API. Two pure-gov articles (`governing-a-portfolio`, `auditing-reproducibility`) were handed off entirely and live at `datomanager/dev/vignettes-from-datom/`. `dev/vignettes-deferred/README.md` holds the reassembly map (original `_pkgdown.yml` grouping, journey order, removed-export list). When datomanager's gov surface ships, rework those articles against it rather than rewriting from memory.
- **(historical) `datom_attach_gov()` backend-correct snapshot + gov-remote precondition**: `datom_attach_gov()` was removed in the lift-out (attachment is now `datomanager::gov_attach()`). Two lessons it taught remain relevant for datomanager's reimplementation: (1) when building the data-store snapshot for `ref.json`, map `conn$root` to `bucket` (s3) or `path` (local) before calling `.datom_create_ref()` — `.datom_store_root()` reads `$bucket`/`$path`, so passing `root = conn$root` yields an empty root; (2) attaching requires an initialised gov remote (the seeded `projects/.gitkeep` skeleton), not a bare empty GitHub repo.
- **`conn$gov_backend` is the 12th interface field (C6)**: set to the governance store's backend (`"s3"`/`"local"`) independent of `conn$backend`; NULL on solo projects. `.datom_conn_for(conn, "gov")` resolves gov-scoped storage dispatch from `gov_backend`, NOT `conn$backend` — so a mixed-backend project (data on S3, gov on local) routes each scope correctly. If `gov_backend` is NULL and a caller forces a gov-scoped op, the sub-conn has `backend = NULL` and storage dispatch fails on first IO — correct, since gov-only commands gate on `.datom_require_gov()` first.
- **`datom_repo_set_data_store()` must use read-modify-write on `project.yaml`**: Read the full yaml first (`yaml::read_yaml()`), then `modifyList` only the `storage.data` subtree, then write back. Never reconstruct the full yaml from conn fields -- that silently drops `storage.governance` on governed projects. The `storage.governance` block is write-once and permanent once populated; overwriting it with NULL or an empty list is a silent data loss.
- **`datom_conn` carries `gov_root = NULL` for no-gov projects**: `is.null(conn$gov_root)` is the canonical "no governance attached" test. Do not use `is.null(conn$gov_client)` -- local-backend gov conns also have `gov_client = NULL` by convention. `.datom_require_gov(conn, what)` encapsulates the uniform error; call it at user-facing function entry for gov-only commands.
- **`sandbox_store_local()` / `sandbox_store()` accept `attach_gov = TRUE` (default)**: when `attach_gov = FALSE`, the gov component is `NULL` and no gov dir is created. `sandbox_up()` branches on `!is.null(store$governance)`. `sandbox_promote_gov(env, gov_store)` mirrors Article 4's flow for testing the no-gov -> gov transition end-to-end.

- **Gov-guard messages intentionally name datomanager — this is NOT a C1 violation**: `.datom_require_gov()` and the `datom_get_conn()` "governance store ignored" warning deliberately point users to `gov_attach()` / `gov_decommission()` "(from the datomanager package)" (design Component 8 / Task 5.2). C1 / R6 mean datom has no **hard runtime dependency** on datomanager — it must load and run without it installed and must not fail mysteriously. A helpful guidance string naming the companion package is the sanctioned UX. Do NOT "fix" these messages to strip datomanager — a solo E2E that asserted the gov error must *not* name datomanager was the bug, not the message. The correct solo assertion: the error mentions `governance` and points to `gov_attach`.

- **A test file cannot see `setup.R`'s namespace swaps by calling them directly (under `R CMD check`)**:
  `testthat:::test_env(package)` is literally `env_clone(asNamespace(package))`, and that clone is
  taken **before** setup files are sourced. So `setup.R`'s
  `assignInNamespace(".datom_s3_client", <blocker>, ns = "datom")` replaces the live namespace
  binding, but a bare `.datom_s3_client()` written at test-file scope resolves through the *clone*
  and reaches the **original** function. Under `devtools::load_all()` + `test_dir()` the lookup
  falls through to the live namespace, so the same line passes locally and fails only in
  `R CMD check` -- discovered exactly that way in Task 12.5 (check ERROR: `argument "access_key"
  is missing`, while `getFromNamespace()` in the same run showed the blocker installed). Two
  consequences: (1) the fail-closed network guard is still **effective** where it matters, because
  package internals are closures over the live namespace and do resolve the blocker -- the guard
  protects leaking *package code*, which is its whole purpose; (2) any test that wants to assert on
  a `setup.R`-installed binding must read it with `utils::getFromNamespace(name, ns)` and call
  that, never name it bare. Live example: the Requirement 16.6 test at the end of
  `test-identity-contract.R`. This also explains why nothing else in the suite ever noticed --
  every other test mocks its own bindings and never calls a chokepoint directly.
- **Run new test files under BOTH run modes before declaring them green**: `devtools::load_all()` +
  `testthat::test_dir()` (the fast local loop) and the installed-package path
  (`R CMD check`, i.e. `test_check()` against `<pkg>.Rcheck/<pkg>`) do not resolve bindings
  identically -- see the namespace-clone gotcha above. The cheap way to check the second mode
  without a full re-check is to run, from `<pkg>.Rcheck/tests`:
  `Rscript -e '.libPaths(c(normalizePath("../../<pkg>.Rcheck"), .libPaths())); library(testthat); library(<pkg>); test_check("<pkg>", filter = "<file>")'`
  (write it to a temp `.R` file -- the shell mangles multi-line `Rscript -e`). Two other
  check-only differences to expect: `dev/` is Rbuildignored, so the `dev/datom_cv1_reference.R`
  parity test (Property 11) legitimately reports SKIP 1 there while the local run reports 0; and
  a plain `R CMD check --as-cran` ERRORs with "Package suggested but not available: covr" on a
  box without covr installed -- run it with `_R_CHECK_FORCE_SUGGESTS_=false` (environmental, not
  a package defect).

- **The ASCII-only rule for `R/` is currently aspirational, not enforced -- 22 pre-existing
  non-ASCII characters live in 7 files**: `R/read_write.R` (4), `R/store.R` (4),
  `R/utils-path.R` (9), `R/validate.R` (2), and one each in `R/utils-git.R`,
  `R/utils-storage.R`, `R/utils-validate.R` -- all em dashes (`e2 80 94`) in comments and
  roxygen, all predating the datom-cv1 spec. `R CMD check --as-cran` does **not** flag them
  here (`DESCRIPTION` declares `Encoding: UTF-8`), which is why they survived. Found with
  `LC_ALL=C grep -c '[^[:print:][:space:]]' R/*.R vignettes/*.Rmd | grep -v ":0"`. Keep
  writing new code ASCII-only -- the convention is still right, and a stray non-ASCII char in
  a cli string is a real portability risk -- but do not treat a non-empty result from that
  grep as a regression introduced by your change: check whether your files are in the list
  first. Sweeping the 22 is a one-commit pre-CRAN cleanup, deliberately not folded into spec
  work (`vignettes/*.Rmd` is already clean).

### datom-cv1 identity (issue #72, landed pre-0.1.0)

Harvested from the spec's work-handoff at completion. The *design* lives in
`dev/datom_specification.md` ("The Three SHAs", "Table Identity = data_sha") and
`vignette("design-version-shas")`; these are the implementation traps.

- **`dev/datom_cv1_reference.R` is the byte-layout single source of truth**, not
  `.datom_canonical_hash()`. It is standalone base R + `digest`, Rbuildignored, pure ASCII, and
  running it prints the goldens (numeric `050d620a...`, mixed `47c94f30...`) and passes 30/30
  self-tests. The package implementation must stay byte-identical to it; the Property 11 parity
  test in `test-utils-sha.R` enforces that and skips when `dev/` is absent -- which means it
  skips under `R CMD check`, i.e. in **every** matrix job. That gap is now covered by
  `.github/workflows/cv1-reference-parity.yaml`, which runs the same file from the source tree
  (where `dev/` exists) on x86_64 AND arm64 and fails if anything skips. If parity ever reddens,
  fix the package, not the reference.
- **Base R's decimal->double conversion is not correctly rounded, and the variable is
  `long double` WIDTH, not architecture.** `R_strtod5()` (`src/main/util.c`) accumulates digits
  into an `LDOUBLE` accumulator and scales by a power of ten; `LDOUBLE` is `long double` unless
  the build lacks it. So: x86_64 (80-bit x87) and aarch64-**Linux**/s390x/riscv64 (128-bit quad)
  agree with correct rounding on everything tested, while **Apple-silicon macOS**, 32-bit ARM, and
  any `--disable-long-double` build (**CRAN's noLD check flavour**) deviate. Linux and macOS on
  the same arm64 chip therefore land on *opposite* sides -- do not reason about this as
  "ARM vs Intel". Detect the local build with `.Machine$sizeof.longdouble` (`8` = no extra
  precision; this workspace reports 8). Accepted R behaviour, not a bug: CRAN maintains noLD
  precisely because results differ, and `?NumericConstants` promises only grammar, never correct
  rounding.
  - **The rule for when it deviates**: whenever `mantissa * 10^expn` cannot be produced by a
    single correctly-rounded operation at the platform's `LDOUBLE` precision -- the accumulated
    mantissa exceeds the significand, or `10^|expn|` is not exactly representable. `10^22` is the
    largest exactly-representable power of ten in a double, `10^23` the first that is not (both
    verified locally), which is exactly why a bare `1e-23` is the first one-digit value to drift
    here.
  - **There is NO fast/exact path keyed on digit count.** `strtod_EXACT_CLAUSE` in the R sources
    is a `> 2^53-1` accuracy-loss guard active only when the caller passes `exact`
    (`type.convert(numerals=)`), not a rounding shortcut. `0.1` and `1e15` come out exact
    *emergently* -- one rounding instead of two. An earlier revision of this note implied a fast
    path; that was a misreading.
  - **x86_64 is a de facto reference, not a provable one.** Clinger (PLDI 1990) proves no
    fixed-precision parser can be correctly rounded for all decimals; correctness needs guard bits
    plus a bignum fallback, which `R_strtod` lacks. Ground truth is a bignum parser -- CPython's
    `float()` (David Gay) or `fast_float`.
  - **Measured here** (arm64 macOS, `sizeof.longdouble == 8`): swept 3792 decimal strings (six
    mantissas x exponents -330..308) against exact rational arithmetic -- 3057 disagreed and R was
    the farther-from-true side in **every one**, never the reverse, never a tie. First drift by
    mantissa: `1` at `e=-23`, `1.5` at `e=-22`, `2.718281828459045` at `e=-11`,
    `3.14159265358979` and `9.87654321098765` at `e=-9`. Reproduce with throwaway scripts: R dumps
    `writeBin()` bits per string, then compare against `struct.pack("<d", float(s))` and
    adjudicate with `fractions.Fraction`. **That is a measuring instrument, not a second
    implementation of the hash** -- Task 1.9's rule (the standalone R reference is the single
    golden source; never bootstrap goldens from another language) is untouched, because nothing
    in the measurement computes a golden.
  - **Reader guidance**: `read.csv`/`scan` share `R_strtod` (same exposure).
    `data.table::fread` has its own parser that is *also* not correctly rounded and whose errors
    **differ** from base R's (`data.table` issue #4461) -- it is not a fix. `arrow`'s CSV reader
    uses `fast_float` (correctly rounded, platform-independent) and parquet stores the doubles
    themselves, so arrow/parquet is the portable path. `readr`/`vroom` is unverified.
  - **Exact literals without a dependency**: C99 hex floats, documented in `?NumericConstants`.
    Verified locally: `0x1.999999999999ap-4` is bit-identical to `0.1`, `0x1.fcp+996` is a large
    value with no base-10 rounding. Usable in fixtures where a decimal literal would not be safe.
- **Never put a many-digit or extreme-exponent decimal literal in a golden fixture -- it makes the
  golden architecture-dependent.** `1e300` in the numeric golden fixture passed on arm64 macOS
  and failed on x86_64 Linux + Windows with the same wrong hash, because R's `R_strtod`
  accumulates extreme-exponent decimals in a `long double`: 80-bit extended on x86_64 (correctly
  rounded) but 64-bit on Apple arm64, which lands `1e300` **4 ULP** off. The encoder was
  innocent -- the divergence happens in the parser, before any datom code runs. Build extreme
  magnitudes parse-exactly instead: powers of two (`2^999`, verified zero-mantissa) or
  `.Machine$double.xmax` / `double.xmin` (IEEE-754 fixed constants). Small-exponent decimals
  like `0.1` take the exact fast path and are portable, so they can stay. Related trap: on arm64
  `2^999` does **not** survive `as.numeric(sprintf("%.17g", 2^999))` -- the round-trip goes back
  through the same broken path -- so never regenerate a fixture value via text.
- **Debugging a cross-platform hash mismatch: pin the payload bytes, not just the hash.** A
  golden-hash failure says "something differs"; it took an exhaustive single-byte search
  (96 x 255), a +/-3 ULP search, and a set of structural hypotheses to *fail* to find the cause
  locally, because the real difference was 4 ULP across two slots at once. What settled it was
  running a standalone probe on the other architecture that printed the parser's bit patterns
  per value, then the payload, then each intermediate digest -- the first diverging line names
  the stage. The "golden numeric fixture is parse-exact" test now pins those payload bytes
  permanently, so the next occurrence reports which value moved instead of only that the hash
  did.
- **`R/hashable.R` detection order is load-bearing.** `.datom_column_kind()` dispatches in a
  fixed order and reordering it silently changes hashes. In `.datom_hash_recourse()`, the
  `POSIXlt`, `sfc`, and nested-data-frame checks are deliberately hoisted **above** the generic
  list rules -- all three are lists underneath, so below the generic rule their specific (more
  useful) recourse would be unreachable. Do not "tidy" them back down.
- **cli dot-literal, concrete instance**: splice the allowlist as
  `{.val {(.datom_import_formats)}}`. Without the inner parens cli reads the leading dot as a
  style name and the message breaks. The design doc's message block omits the parens; they are
  required.
- **`.datom_import_format_recourse()` returns rendered plain text** (via `cli::format_inline()`),
  which is what lets the identical string land in a cli abort bullet AND in the `error` cell of
  the manifest data frame with no markup drift. Keep it markup-free.
- **`data_sha` recompute formula** -- lifted verbatim from `.datom_canonical_hash()`; copy it,
  do not paraphrase, or an assertion drifts from the implementation. Lives in the Property 12
  test in `test-utils-sha.R`:

  ```r
  shas   <- vapply(meta$column_hashes, function(e) e$sha, character(1))
  header <- c(charToRaw("datom-cv1"),
              writeBin(as.double(c(nrow, ncol)), raw(), size = 8L, endian = "little"))
  recompute <- digest::digest(c(header, charToRaw(paste(shas, collapse = ""))),
                              algo = "sha256", serialize = FALSE)
  ```

  `writeBin()` over a length-2 vector is one call, i.e. `f64le(nrow) || f64le(ncol)`. If this
  assertion ever reddens, the byte layout changed -- fix the code, not the test.
- **Token-precise scanning for a `*_sha` rename sweep.** `grep -v "original_file_sha"` filters
  whole *lines*, so it hides a bare token sharing a line with a legitimate one (e.g.
  `customers = list(original_file_sha = file_sha)`). macOS BSD `grep` has no `-P`, so use perl:
  `perl -ne 'print if /(?<!original_)(?<!parquet_)\bfile_sha\b/'`. And `\bfile_sha\b` alone is
  still not enough: `_` is a word character, so it does **not** match inside
  `.datom_compute_file_sha` or `tbl_file_sha`. Rename functions first, then sweep bare tokens,
  then scan the function-name forms separately.
- **`devtools::document()` handles renamed internal helpers by itself.** roxygen2 tracks the
  pages it generated and deletes the stale `.Rd` on rename -- no `git rm` needed. (An earlier
  note claimed otherwise; verified false by running it.)
- **Test fakes avoid new Suggests**: `hms` / `ITime` / `integer64` columns are faked with
  `structure(..., class = ...)`, and the same trick renders the vignette's `sf`/`units`/`zoo`
  recourse rows -- dispatch is on the class tag, so a bare structure is enough.
- **The `metadata_sha` goldens are now builder-derived, and the old hand-written one carried a field
  datom never writes.** `59f1f1d9...` pinned a fixture containing a `name` key -- which no builder
  emits, since `metadata.json` is written as exactly the object `.datom_build_metadata()` produced
  (the `name` in `datom_write()` is its return value) -- and lacking `colnames`, which every builder
  emits. Under allowlist selection that hash changed while **no stored identity moved**, so the
  fixture was reused for the property that changed it: an unknown extra field is ignored, pinned at
  the no-`name` value `cce751b3...`. The load-bearing goldens are now
  `builder-derived metadata_sha goldens are stable`, built through the real builder with and without
  its conditional fields. Lesson worth carrying: **a pinned identity fixture must be a document the
  package can actually write**, or it pins the behaviour of a shape that does not exist. (Superseded
  instruction: "keep that fixture as-is or the golden needs re-deriving".)
- **An acceptance gate can have a legitimate false positive; scope the gate, do not edit the
  source.** `grep -rn "as.data.frame" R/utils-sha.R` will never be empty: the one hit is the
  roxygen line documenting the invariant ("no `as.data.frame()` or coercion, and never invokes
  arrow"). The gate's intent is that no *executable* coercion exists, which the comment asserts.
  Pipe through `grep -vE ":[0-9]+:[[:space:]]*#"` and record the documented match. Deleting the
  comment to satisfy a literal grep would delete the statement of the invariant.

### datom-sv1 set identity (issue #89, spec `.kiro/specs/datom-sets/`)

The set-content hash. Design lives in the spec (`requirements.md` R2, `design.md` 7); these are the
implementation traps.

- **`dev/datom_sv1_reference.R` is the normative byte layout**, exactly as
  `dev/datom_cv1_reference.R` is for tables: standalone (base R + `digest`), Rbuildignored, ASCII,
  self-testing, and it prints the goldens. `R/hashable-set.R` must stay byte-identical to it. The
  parity test in `test-hashable-set.R` skips when `dev/` is absent -- i.e. under **every**
  `R CMD check` job -- so `.github/workflows/cv1-reference-parity.yaml` (which covers cv1 **and**
  sv1 despite its name) is what actually enforces parity, from the source tree, on x86_64 and arm64.
  **The goldens are published, so the encoding is frozen**: a failing golden means the code drifted,
  and a deliberate change is a `datom-sv2` bump with a new `hash_algo`, not an edit.
- **sv1 shares NO primitive with cv1 -- do not reach for `.datom_encode_numeric()`.** There are no
  numbers in a set payload and no length prefixes anywhere (every intermediate is a fixed 32 bytes,
  so `h("a")||h("b")` at 64 bytes cannot collide with `h("ab")` at 32). The only common ground is
  `digest::digest(..., algo = "sha256", serialize = FALSE)`.
- **A NAMED list in a value position must be refused, and this is the trap worth remembering.**
  Element-wise, `list(b = "c")` and `list("c")` are indistinguishable -- both are a one-element list
  holding one string -- so an encoder that checks only elements hashes `{"a": {"b": "c"}}`
  *identically* to `{"a": ["c"]}`. The inner key then sits outside identity, and two different
  payloads share one `data_sha` and therefore one storage address. The guard is
  `is.list(v) && !is.null(names(v))` in `.datom_sv1_as_strings()`. Same reasoning drives the other
  two refusals: an unexpected field at the payload root or in a member record aborts rather than
  being ignored, because an ignored field is content that never enters identity.
- **Intermediates are raw 32-byte vectors, not hex.** Hex appears in exactly two places, both named
  by the spec: the member-digest collation key and the final `data_sha`. Byte order and lowercase-hex
  C-locale order agree, so `order(hex, method = "radix")` and sorting the raw bytes give the same
  result -- but keep the hex spelling, since that is what the specification pins.
- **`is.na()` on a closure warns instead of answering**, so the `NA` refusal sits *after* the
  type gate, with one exception hoisted above it: an all-`NA` **logical** (a bare `NA`) is caught
  first so it gets the "omit the field instead" advice rather than a type error. A
  `tags = list(t = mean)` fixture is what surfaced this, against a suite held at WARN 0.
- **Both empty spellings must agree**: `strset(list())` == `strset(character(0))` == `h(0x02)`, and
  `map(list())` == `map(NULL)` == `h(0x03)`. `[]` and `{}` are the parsed-JSON forms, and write/read
  agreement depends on the R and parsed spellings hashing equal. The encoder must not lean on
  "an empty tag value is dropped upstream" -- that is exactly how an encoder breaks silently the day
  the upstream rule moves. (That upstream rule was itself stated two ways for a while: the spec said
  both "refused by validation" and "the key is dropped". The tidy wins; corrected 2026-09-10.)
- **Where the encoder stops.** It refuses only what it cannot encode without losing content. Grammar
  enforcement with user-facing recourse -- which key is wrong, what types are allowed, whether two
  members share an `id` with conflicting tags -- belongs to `.datom_validate_members()` and
  `datom_write_set()`, the only places that see a whole payload and the caller's intent.
- **Sorting is `method = "radix"` everywhere**, i.e. C-locale byte order, for the same
  locale-independence reason `.datom_compute_metadata_sha()` uses it. No Unicode normalization is
  applied anywhere in the identity path: NFC and NFD are different tags, deliberately, because
  normalization tables are versioned Unicode data. Note the sort runs *before* `enc2utf8()` (which
  happens inside `str()`), which looks like an encoding hazard and is not: checked on a
  latin1-marked string against its UTF-8 twin, radix sort produces the same order and the digests
  agree, because R translates for the comparison. In practice the hash domain is a parsed JSON
  payload, so it is UTF-8 anyway.

### Testing storage side effects without mocking storage

Techniques from the S1-S6 integration suite (`tests/testthat/test-identity-contract.R`). They
matter whenever a test needs to prove something did *not* happen.

- **A real project needs no mocks at all.** Real git repo + real **local bare remote** (so
  `.datom_git_push()` works -- it does `git2r::remotes(repo)[[1L]]`, which subscript-errors
  without a remote, the reason older tests mocked the push) + a real `backend = "local"` store.
  `.datom_check_git_current()` needs no mock either (early-returns with no remote, works
  normally with one), and a conn with `gov_root = NULL` makes `.datom_check_ref_current()` take
  its legacy-conn skip. See `local_identity_project()`, and `dev/e2e-cv1-identity.R` for the
  same fixture as a runnable walkthrough.
- **Prove "no upload" with a backdated mtime**: `fs::file_touch(obj, modification_time = <old>)`
  before the write, then assert the mtime survived. A re-upload goes through
  `.datom_local_upload()` -> `fs::file_copy(overwrite = TRUE)` and would reset it. Byte
  comparison cannot distinguish "not re-uploaded" from "re-uploaded identical bytes".
- **Prove "verified before parsed" with a valid imposter**: swapping in a *different but
  readable* parquet is the only corruption arrow would happily accept, so the abort can only
  come from the `parquet_sha` check. A single flipped byte fails either way and proves less.
- **Locate stored objects through `.datom_local_path()`**, not a hand-written
  `{prefix}/datom/...` path, so a storage-layout change breaks the code rather than silently
  passing a test that looks in the wrong place.

### `conditionMessage()` on a cli error carries terminal escape codes

`cli::cli_abort()` formats its message for the terminal, so the string carries ANSI colour codes
and OSC-8 hyperlinks: `\033[31m` to start red, `\033]8;;file://...` to make a path clickable.
`conditionMessage()` returns that formatted string, escapes included.

- **Printing it is fine.** The terminal consumes the codes, which is the whole point of them, so
  every `cli_abort(..., "i" = "Underlying error: {conditionMessage(e)}")` site reads correctly and
  needs no change.
- **Storing it is not.** Any field datom *returns* holding that text will show the codes as
  literal `\033[31m` noise the moment a caller prints the string itself, writes it to a log, or
  puts it in a report. Wrap those in **`cli::ansi_strip()`**. Three fields needed it (fixed
  2026-08-29): `datom_status()`'s `$tables$error`, `datom_sync()`'s `error` column, and the
  per-table `error` in the metadata sync result. `datom_sync()`'s was the worst, being a data
  frame cell.
- **The distinction to apply to a new field**: is this text going into a message, or into a value
  the caller keeps? Only the second needs stripping. A local copy used for pattern matching --
  `grepl("403|Forbidden", conditionMessage(e))` -- is fine, though be aware the codes surround
  the segments, so a pattern spanning styled and unstyled text will not match.
- **A TEST FOR THIS IS VACUOUS UNLESS IT FORCES COLOUR ON.** `Rscript`, `devtools::test()` and CI
  all run without a colour-capable terminal, so cli emits no escapes at all and the assertion
  passes whatever the code does -- which is exactly why the defect survived to 0.1.1. Use
  `withr::local_options(cli.num_colors = 256, cli.hyperlink = TRUE)`, then assert with
  `expect_false(grepl("\033", x, fixed = TRUE))`. Confirm the test reddens when the fix is
  removed; without forced colour it will not.
- **Reproducing what a user reports**: an interactive console has colour on, so a string that
  looks clean in your test run can look mangled in their paste. To see what they see, force the
  same two options.

### The manifest's artifact list, and the two ways a fixture goes quietly wrong

Landed 2026-09-08 with the `manifest$tables` -> `manifest$artifacts` rename. Three things to know
before touching a manifest or a manifest fixture.

- **Never write a fallback for the old key.** `.datom_read_manifest()` returns the document in
  **current shape** -- a document written in an older shape is converted on the way through, in
  memory, and the file is left alone. So `manifest$artifacts %||% manifest$tables` at a call site is
  not defensive, it is a second implementation of the conversion: the next format change then has to
  edit every copy, and the one it misses fails silently. The conversion has exactly one home,
  `R/manifest-upgrade.R`, reached from exactly two places (the shared reader, and the entry updater
  before it edits the file).

- **A fixture in the current shape needs BOTH the version and the kind.** A hand-built manifest that
  declares `schema_version = 2` but leaves `kind` off its entries reads as a manifest with **zero
  tables**, because the counters filter on `kind == "table"` and there is deliberately no
  missing-`kind` fallback. Nothing errors. A fixture that declares **no** version is a valid v1
  document and gets converted, `kind` included, so it works -- which is the trap: the two failing
  spellings look more alike than the two working ones. If a count comes back zero for no visible
  reason, check the fixture's entries for `kind` first.

- ~~**A test that needs a set has to hand-build one.**~~ **SUPERSEDED 2026-09-13: `datom_write_set()`
  exists, so a real set is writable in a test.** What it costs is one extra fixture step -- the two
  gates read `.datom/project.yaml` for `mode: product` and a `set:` name, and nothing in datom writes
  either field yet, so the fixture writes that file itself via `write_product_config()` in
  `helper-mock.R` (shared, unlike the per-file project fixtures, because it is one fact about one
  file's format and three test files need it). Prefer a real write over a hand-built entry: a
  hand-built row can disagree with what the writer actually produces, which is the disagreement the
  row-vocabulary and rebuild-parity tests exist to catch. The original entry, retained because the
  reasoning still applies to any counter added before something writes the shape it counts: nothing
  wrote a `kind = "set"` entry, so every counter filter passed against a tables-only manifest whether
  or not the filter was there. Any change to a counter needs a fixture holding a set entry beside
  table entries, and the assertion worth making is that the **counted** numbers
  (`datom_summary()`) and the **stored** `summary` block agree -- a filter applied to one and not the
  other is invisible until they are compared.

- **`tables` still exists as a return-value field in three places** and must not be swept:
  `datom_status()$tables`, `datom_validate()$tables`, and the per-table results in `datom_sync()`'s
  result. A `grep tables` across `R/` hits all three. Renaming them is a separate breaking change to
  three public shapes.

### Two ways a condition's class silently disappears on its way to a handler

Both were found while building the reader-side manifest rebuild (2026-09-10), where the whole
decision is made *by* the class of the condition that came back: a compatibility refusal has to keep
travelling, while a storage failure has to be turned into a return value. Both defects go green in a
suite that only checks that *something* failed.

- **`stop(cnd)` inside one `tryCatch()` handler is caught by that same `tryCatch()`'s `error`
  handler.** The spelling below reads as "re-raise this class, catch everything else", and it does
  the opposite -- the re-raised condition lands in the sibling handler and comes back as a returned
  value:

  ```r
  # WRONG. `stop(cnd)` is caught by the error handler two lines down.
  tryCatch(
    risky(),
    my_class = function(cnd) stop(cnd),
    error    = function(e) list(ok = FALSE, error = e)
  )
  ```

  Catch once, decide afterwards, re-signal from outside every handler:

  ```r
  out <- tryCatch(list(ok = TRUE, value = risky()),
                  error = function(e) list(ok = FALSE, error = e))
  if (!isTRUE(out$ok) && inherits(out$error, "my_class")) stop(out$error)
  ```

- **`purrr::map()` and friends re-signal whatever the mapped function threw as their own error.**
  The result carries `purrr_error_indexed` / `rlang_error` and the original condition is demoted to
  its `parent`, so `inherits(e, "my_class")` is `FALSE` and a class-specific `tryCatch` handler never
  fires. Where a mapped function is expected to raise a condition the caller dispatches on, use
  `lapply()` / `vapply()` and say why in a comment -- otherwise the next tidy-up puts `purrr::map()`
  back.
### Adding a field to a metadata document is not the same size of change on each list

Landed 2026-09-10 with `kind` (which kind of artifact the document describes) entering per-artifact
metadata. Two lists exist -- `.datom_metadata_identity_fields` (hashed into the version) and
`.datom_metadata_excluded_fields` (known and deliberately not hashed), both in `R/utils-sha.R` -- and
which one a new field lands on decides whether the release is free or costs every artifact a version.

- **A field added to the IDENTITY list re-mints one version for every existing artifact.** Change
  detection recomputes the document's identity from the stored document and compares it with the
  recorded version (`.datom_has_changes()`), so a document that has gained an identity field
  disagrees with its own recorded version. The next write of each artifact therefore reports
  `metadata_only` and records a version, on content that never moved -- once per artifact, at its
  next write, in every repo. **This is a design decision, not a defect to fix at implementation
  time.** Take it deliberately, and say it in NEWS: the cost is bounded and in the safe direction,
  because `data_sha` does not move, so the storage address does not move, the payload is reused and
  nothing is re-uploaded.

- **A field added to the excluded list costs nothing**, which is why `schema_version`,
  `original_format` and `document_sha` are all there. The question to ask is never "is this field
  cheap" but "can two artifacts that differ only in this field be allowed to share a version".

- **Adding either kind still forces every writer in the fleet to upgrade**, through the vocabulary
  check rather than through identity, so "additive is free" is only ever free *for readers*. See the
  forward-compatibility section of `.github/copilot-instructions.md`.

- **Both lists are guarded by tests that fail when a builder gains a field, in both directions**
  (`test-utils-sha.R`): every field a builder emits must be classified, and nothing may be classified
  before a builder emits it. The second arm carries an exception vector that is currently empty. They
  are not tests to update -- they are where the decision gets made.

### A declared-but-unpopulated field has to be spelled `list(x = NULL)`, not a conditional assign

`list(a = 1, b = NULL)` keeps `b` as a name; `meta$b <- NULL` **removes** it. So the two ways of
writing "this field exists but its value is not known yet" are not interchangeable, and datom uses
both deliberately:

- **Declared, because the value arrives later in the same pipeline.** `parquet_sha` in
  `.datom_build_metadata()` and `document_sha` in `.datom_build_set_metadata()` are both declared as
  `NULL` because the byte hash is not knowable until the payload has been serialized. Both fields are
  outside the version identity, which is what makes the deferred assignment safe.
- **Conditionally assigned, because absence is a real state.** `original_file_sha`, `parents`,
  `custom` and friends are added only when non-NULL, so an absent field is spelled by omitting the
  key rather than by a null value.

**`jsonlite` does NOT omit a NULL element -- it writes `{}`.** Verified:
`write_json(list(kind = "set", document_sha = NULL), auto_unbox = TRUE)` produces
`{"kind":"set","document_sha":{}}`, and reading that back gives an empty named list rather than an
absent key. (An earlier version of this note, and design.md section 4 of the datom-sets spec, both
claimed the key is dropped. It is not. The claim was believed because the case never arises today,
for the reason in the next paragraph.)

**So a declared field must be populated -- or explicitly removed -- before the document is written.**
`parquet_sha` gets away with it by accident of two paths: `datom_write()` either assigns a real hash
or assigns `NULL`, and `meta$parquet_sha <- NULL` **removes** the element rather than setting it, so
no `{}` has ever reached a file. Any new declared field inherits that obligation without inheriting
the accident.

**The same fact bites when EMPTYING a field on an object a caller already holds**, which is a third
case the two above do not cover. `datom_update_members()` has to stop an edited set from claiming the
version it was read as, and `x$version <- NULL` would delete the name -- changing `names(x)` on a
documented return shape, and silently, since `x$version` answers `NULL` either way. The spelling that
empties without removing is `x["version"] <- list(NULL)`. A test on `names()` before and after is what
holds it, because every assertion on the field's *value* passes under both spellings.

The consequence for a field-set contract: a `setequal(names(meta), ...)` assertion about the
in-memory object is satisfied by a key whose value is `{}`, so it cannot tell a populated document
from an unpopulated one. That is a reason to assert on the written bytes wherever the count is
load-bearing, not a reason to switch to a conditional assign -- the conditional form drops the key
from the in-memory object too, which breaks the contract outright.

**The same fact decides the OPPOSITE way one level down, in a set member.** A member with no tags
must **omit** the key: a payload is a list of member records, none of which has a fixed field set to
honour, and R2.10 says a writer never emits `"tags": {}`. So `datom_member()` builds the record with
`list(id = ...)` and adds `tags` only when there are any -- the spelling `list(id = ..., tags = tags)`
would keep the name and put an empty object into every untagged member of the stored file.

**Nothing about identity can catch either case, which is what makes them worth a note.** An absent
tag map and an empty one both encode as `h(0x03)` under `datom-sv1`, so no hash moves and no golden
changes; a test that compares hashes passes whichever spelling is used. The guard has to be an
assertion on the emitted JSON. The rule to carry: **decide per field whether absence is a real state,
then assert on the bytes, because the in-memory object and the identity hash are both blind to the
difference.**

### `fs::dir_ls()` hides datom's storage metadata, because every bit of it is under a dot

`fs::dir_ls(recurse = TRUE)` defaults to `all = FALSE`, so it omits dotfiles and everything under a
dot-directory. datom's storage layout puts the manifest at `{prefix}/datom/.metadata/manifest.json`
and every versioned snapshot under `{name}/.metadata/`, so a listing of a local-backend store shows
the parquet files and **nothing else** -- which reads as "the mirror never ran" and sends you into
the write path looking for a bug that is not there. Pass `all = TRUE`, or test the specific path with
`fs::file_exists()`. Cost an hour on 2026-09-19 while building a fixture that had to corrupt the
manifest.

### A probe fixture can be small enough to pass by coin flip

Found 2026-09-13 while probing the set write. The rule datom relies on is that breaking the code on
purpose reddens something -- so a probe that reddens **nothing** is either evidence the guard is
missing or evidence the fixture is too small to distinguish the two behaviours. Distinguish them
before concluding either.

The concrete case: the set payload's members are sorted by name in the file and by digest in the hash,
deliberately, and swapping the file to digest order reddened **zero** assertions. The guard existed;
the fixture had **two** members, and two items sorted by digest agree with name order half the time.
With five members it is one chance in 120, and the fixture is now five names pinned at one version
where digest order is the exact **reverse** of name order -- asserted inside the test, so the pinning
is visible rather than incidental.

The generalisation: **a fixture for an ordering, dedup, or selection rule needs enough elements that
the wrong rule cannot coincide with the right one.** Two is almost always too few. Where a fixture can
be chosen so the two rules disagree outright, assert that disagreement in the test body -- otherwise
the next reader cannot tell a pinned fixture from an arbitrary one.

### `l[["missing"]]` on a list is a subscript ERROR, not NULL

`list(a = 1)$b` is `NULL`; `list(a = 1)[["b"]]` aborts with "subscript out of bounds". So the
`x[[field]] %||% default` shape -- which reads as the obvious way to take an optional field whose
**name is in a variable** -- fails on exactly the documents it exists for.

Hit while generalising the version-history scan to look up either `parquet_sha` or `document_sha` by
name (`.datom_lookup_history_object_sha()`, `R/read_write.R`): every history entry written before a
field existed lacks it, which is the normal case rather than the edge case. Test presence first:

```r
if (!is.list(entry) || !(field %in% names(entry))) return("")
value <- entry[[field]]
```

`purrr::pluck(entry, field)` also returns NULL and is fine; `$` is not available when the name is a
variable, which is what makes this shape tempting in the first place.

### A probe harness must restore from its own copy, never from `git checkout`

Learned expensively on 2026-09-14, probing the set read. The probe loop is: apply a deliberate
defect, run the affected tests, count what reddens, put the code back. A harness that put the code
back with

```sh
git checkout -- R/set.R R/read_write.R   # NEVER do this in a probe loop
```

deleted the entire task's implementation, because HEAD predates it. **The code under probe is by
definition uncommitted** -- that is what the probe is checking -- so git is the one restore source
that cannot work. Copy the files to a temp directory before the first probe and restore from those
copies:

```python
shutil.copy2(src, backup)   # once, before any probe
...
shutil.copy2(backup, src)   # after each probe
```

Two things made the recovery cheap and are worth arranging in advance: `devtools::document()` had
already been run, so every roxygen block survived in `man/*.Rd`, and the test file was a separate
new file the harness did not touch. Recovery was verified by re-running `document()` (the `man/`
diff came back empty) and by line count against the earlier `git diff --stat`.

If a probe run must touch tracked files, `git stash` is not a fix either -- it is the same class of
tool. Commit the work first, or copy it aside.

**And the copy must be taken once, from a tree known to be good.** Learned the next day, 2026-09-15,
following the rule above and still corrupting the tree. A probe crashed partway through -- the
deliberate defect made the package fail to load, which the harness did not survive -- so the tree was
left mutated. The harness was then re-run, and its first act was to take a **fresh** backup: it copied
the mutated files and recorded them as pristine. The next probe layered its own defect on top, and the
result was a source file carrying two deliberate defects with no clean copy anywhere. Repair was by
hand, from knowledge of what had been written.

Three cheap habits remove it:

* **A fixed backup path, reused.** `file.path(tempdir(), "probe-pristine")` rather than
  `tempfile()`. If the directory already exists, restore from it and do not overwrite it.
* **Refuse to take a backup from a tree that does not parse.** Two lines, and it is the check that
  would have caught this one.
* **Restore inside the error handler, not only on the happy path.** A probe whose defect stops the
  package from loading is a *successful* probe; the harness has to treat that as a result and clean
  up, not propagate it and stop.

### A closure leaks a connection only once the connection has been FORCED

Also 2026-09-14, while pinning that `$fetch` on a set member carries no credentials. The hazard is
real: a factory defined *inside* a function that holds `conn` puts that frame on the closure's parent
chain, and `saveRDS()` then writes the PAT into the file. But the first probe of the broken shape
found **no** token in the bytes, which looked like the guard being unnecessary.

The reason is R's lazy arguments. In the probe, the outer function never used `conn`, so it was still
an unevaluated promise whose environment is the **caller's** -- and for `saveRDS()` the global
environment serializes as a reference rather than by value, so nothing came along. Adding one line
that touched `conn` reproduced the leak exactly.

Two consequences. **For the code**: a namespace-level factory is not enough on its own; every
argument gets `force()`d, so nothing is left as a promise pointing back at a frame that holds a
connection. **For the test**: search the serialized bytes for a token **value** the fixture invents,
not for a field name -- a dev-loaded package keeps source references, so the serialized closure
carries the text of its own source file, which mentions `github_pat` in an example. And use
`grepRaw()`: `rawToChar()` refuses the embedded NULs in serialized R objects.

### What git2r stages, and what a commit-shaped test actually proves

Landed 2026-09-18 with `datom_repo_commit()` / `datom_repo_push()` (datom-sets Task 12). Every
claim here was settled by **running git2r**, because each of them reads plausibly either way.

**Staging.** `.datom_git_commit()` has one staging call with two spellings, and they are not
interchangeable:

| Call | `.gitignore` | deletions | Use for |
|---|---|---|---|
| `git2r::add(repo, files)` -- default | **respected** | **staged** | everything, including `files = "."` |
| `git2r::add(repo, files, force = TRUE)` -- what `staged_deletions = TRUE` sets | **ignored -- gitignored files ARE staged** | staged | staging a path git would refuse |

- **`files = "."` is a legal add-all through the ordinary helper.** `fs::file_exists(".")` is
  `TRUE`, so it passes the existence pre-check, and default flags give exactly "what `git add .`
  would stage". No separate staging code is needed for an add-all wrapper.
- **`staged_deletions = TRUE` is the trap.** It exists to skip the existence check, which is what
  an author reaches for to make deletions work -- and it silently starts staging gitignored files.
  It is also unnecessary, since default flags already stage deletions.
- **An explicitly named gitignored path is dropped in SILENCE.** `git2r::add(repo, "ignored.txt")`
  raises no error and stages nothing. `.datom_git_commit()` cannot notice, because it only objects
  when **nothing at all** is staged and datom's own files always are -- so the commit succeeds
  carrying everything except the file the caller asked for. Any feature that takes a caller-supplied
  file list has to check for this itself; `datom_write_set(include_paths =)` does, in
  `.datom_check_include_paths()` (`R/set.R`).
- **There is no check-ignore verb in git2r.** The only route is
  `git2r::status(repo, staged = FALSE, unstaged = FALSE, untracked = FALSE, ignored = TRUE)`, and
  two properties of its answer decide how to use it. It reports an ignored **directory** with a
  trailing slash (`cache/`) and does **not** recurse into it, even with
  `all_untracked = TRUE` -- so match a caller's path as a **prefix** against a slash-stripped list,
  or every file inside an ignored directory passes the check. And a **tracked** file is never
  reported as ignored, which is correct rather than a gap: git stages it regardless of the rules, so
  it really does reach the commit. `.datom_git_ignored()` (`R/set.R`) wraps both facts.
- **`.datom_git_commit()` returning HEAD's SHA on an empty staging is a SUCCESS value, not a
  sentinel.** A wrapper that must report "nothing to do" cannot get that from the return value; the
  cheap way is to capture HEAD before and compare after, which is what `datom_repo_commit()` does.

**`git2r::status()` reports an untracked DIRECTORY, not its contents.** A new `dp/notes.txt` in an
otherwise-untracked `dp/` shows up as `dp/`. Assert the directory, or add the file to a directory
git already tracks. This also reaches `datom_status()`, which passes git's answer through.

**Asserting on a commit's real tree.** A test that mocks `.datom_git_commit()` and inspects the
`files` argument it captured proves the wrapper passed a list, **not** that the commit contains that
list -- so it stays green through an add-all refactor, which is exactly the regression the
machine-commit isolation guarantee exists to catch. Read the real tree instead:

```r
entries <- git2r::ls_tree(repo = repo, tree = git2r::tree(commit))
paths   <- paste0(entries$path, entries$name)   # `path` carries a trailing slash
blob    <- git2r::lookup(repo, entries$sha[paths == "R/foo.R"])
git2r::content(blob)                            # the bytes the commit holds
```

- **Assert content, not presence, for a tracked file.** The path is in the tree either way if the
  file was committed earlier; the claim worth making is that the tree still holds the *old* bytes.
- **Assert the working tree separately.** A write that "helpfully" committed or reset the edit are
  two different defects, and only the second leaves the tree clean.

**`fs::path_rel()` with a relative first argument resolves it against the working directory**, so
`fs::path_rel("dp/build.R", "/tmp/repo")` returns `"../../private/tmp/dp/build.R"`. Anything handed
to `.datom_commit_and_mirror()` must be an **absolute** path, since that function relativises what
it is given against `conn$path`. The failure is loud (`.datom_git_commit()` aborts "files do not
exist"), so this costs minutes rather than correctness -- but repo-relative input has to be
absolutised first.

### Reading a file as one commit left it, and why tree indexing lies

Landed 2026-09-19 with `commit_sha` on the stored version history (datom-sets Task 15). Both facts
below were settled by running git2r 0.36.2, because the wrong one looks right.

- **`git2r::revparse_single(repo, "<sha>:<path>")` is the whole mechanism.** It resolves git's own
  `commit:path` syntax straight to the blob, and raises `Requested object could not be found` when
  the path is absent at that commit. `git2r::content(blob)` then gives the text, split by lines.
- **`tree(commit)["dir/file"]` returns an empty `list()` for a path that is not there** -- no error,
  no NULL, and `length()` 0. So the obvious "index the tree, `tryCatch` the failure" shape cannot
  tell absence from success. It also does not accept a slash-separated path at all: for a nested
  file the index has to be applied one level at a time (`tree(cmt)["dm"]["metadata.json"]`).
- **`git2r::commits(repo, path = )` filters to the commits that touched that path**, newest-first,
  and `reverse = TRUE` gives oldest-first. That is enough to answer "which commit first produced
  this version" with no extra bookkeeping: hash the document as each commit left it, and the first
  match wins. A commit that did not touch the document is not in the list, which is what makes a
  code-only commit correctly nobody's producer.
- **`ls_tree()` + `lookup()` also works and costs more** -- it walks the whole tree per commit. It
  is the right tool when you want the tree's contents (see the commit-shaped-test note above), and
  the wrong one when you know the path.

### A field only storage may carry has to be merged, not appended

Same task. `version_history.json` exists in two copies -- the clone's, which is committed, and
storage's -- and `commit_sha` can only ever live on the second, because the clone's copy is *inside*
the commit that would name it. The shape of the defect that follows is general:

- **The upload sends the whole file, so it overwrites rather than adds.** Three functions upload
  that file (`.datom_push_metadata_s3()`, `.datom_sync_one_artifact()`, `.datom_sync_metadata()`),
  each reading the clone's copy. Without a merge the field survives on the newest entry only, and
  the loss happens on the **second ordinary write** of an artifact -- not in the repair verb, which
  is where the design notes had put the hazard. Derive the list of upload sites (`grep -n
  version_history R/*.R`) rather than trusting a count written down anywhere.
- **Preserving is not enough on its own.** "An older build may strip this, and that is fine because
  the value can be recomputed" is only true if something recomputes. An implementation that merely
  carries the stored value forward passes every test about the field and quietly removes the
  property that made stripping acceptable. Both halves, in one shared helper: keep what storage has,
  work out only what is missing.
- **Version-history entries have no field vocabulary**, unlike `metadata.json` and the manifest, so
  adding a field there trips no writer refusal and needs no format bump. Convenient, and it also
  means nothing stops an old build from stripping it -- state that at the code site rather than
  treating the asymmetry as an oversight.

### A guard that only fires on a rare route needs that route's test, not the obvious one

Same task, and it is the concrete case for the guard-test rule. The write path hands the uploader the
commit it just made, and the guard says: do not use it if storage already records one for that
version. Nine tests covered the field and **none** of them reddened when that guard was deleted,
because every ordinary write mints a *new* version, so the guard never runs.

The route that reaches it is **reverting an artifact to earlier content**: the version already exists
so no history entry is appended, but a new commit is made and handed over, and without the guard the
entry is repointed at it. Ask what state makes a guard fire, then build that state -- a guard whose
tests all run through the common path is untested by however many of them there are.

### "Not there" and "could not look" are different answers, and a `tryCatch` erases the difference

Found in review 2026-09-19, on the `commit_sha` merge. The shape is general and this is the third
time the spec has closed it: a silent handler sitting inside the function whose output decides
whether a guarantee holds.

```r
# The defect. An unreachable store and an empty one produce the same answer.
stored <- tryCatch(.datom_storage_read_json(conn, key), error = function(e) NULL)
if (!is.list(stored) || length(stored) == 0L) return(nothing_known)
```

Downstream, "nothing known" meant "work it all out from git, then upload the file whole" -- so a
value only storage had was destroyed, in the one case where it could not be reconstructed.

- **The existence probe is what separates them**, and **its own failure counts as could-not-look**,
  never as absence: an unreachable store cannot report that a file is missing. Without the probe a
  first-ever write reports loss where storage never held anything -- a false loss report is worse
  than noise, because it points at recovering a value that never existed.
- **You cannot tell an unreachable store from a corrupt file.** Both `.datom_s3_read_json()` and
  `.datom_local_read_json()` raise their own `cli_abort()` for a network failure and for unparseable
  bytes alike. So any policy that treats the two differently needs a different mechanism, not a
  different handler.
- **Refuse only if something else can still repair the file.** Refusing here would have deadlocked:
  the repair verb goes through the same helper, so a stored document that will not parse could never
  be replaced. A derived projection is *meant* to be rebuilt -- the rule it must satisfy is "not in
  silence", not "never".
- **Report on the loss, not on the failed read.** If the value could be reconstructed anyway, nothing
  was degraded and a warning is noise. Gate the message on a version actually ending up without a
  value.
- **Audit silent handlers by kind, not in bulk.** In the same file, five give-ups signal *absence*
  (they leave a gap that had no stored value either, so nothing is lost) and one signals *loss*. Say
  which is which at the site, or the next reader tidies them into one handler.

**`cli::cli_warn()` / `cli_abort()` resolve a plural against the most recent quantity in the SAME
message**, so a `{?s}` in a bullet that names no count aborts with "Cannot pluralize without a
quantity" -- from inside the warning, which turns a diagnostic into an error. Bind `n <-
length(x)` and use `{n}` in each bullet that pluralizes, and make sure a test actually triggers the
message: the failure is invisible until it fires.

### A test can observe a layer that cannot distinguish the two behaviours

The family behind four separate findings, and the reason the guard-test rule in
`.github/copilot-instructions.md` is not ceremony. **Two shipped and were found by
probing; one was spotted before the bad test was written.** The honest count matters --
"four instances of a defect" and "instances, one of them prevented" are different claims.

| Where | Shape | Caught |
|---|---|---|
| datom-sets Task 13 | a shipped test that could not fail | by probe, after shipping |
| datom-sets Task 14 | a shipped test passing through the wrong guard | by probe, after shipping |
| datom-sets Task 12 / AC16 | the same hazard, spotted before the test was written | at audit; never a defect |
| datom-sets Task 16 / AC2 | a shipped test that could not fail, four ways over | by probe, after shipping |

**AC2 is the canonical case, because the property being tested destroys its own obvious
observable.** The claim: re-writing a set with an identical payload does nothing. Delete
the early return that makes it a no-op and every assertion in its own test stays green.
Four reasons, each sufficient alone:

* the reported action is assigned from the change type, so a write that skipped the
  return and did the entire job still reports `"none"`;
* both hashes are recomputed from the same payload either way;
* appending a version already in the history dedups, so the length is unchanged;
* **an identical payload leaves git nothing to commit, so HEAD does not move either.**

That last one is what makes this the example to remember. The obvious fix is to read the
commit id before and after -- which is what the neighbouring test for the same property
under dirty caller files legitimately does -- and here it cannot fail, because a no-op
and a completed write leave git in the same state. **No amount of careful reading finds
this.** What survives is what the caller is *told*: a skipped write says so and a
completed one announces itself.

The rule, stated so it transfers: **a test that asks a write what it reported cannot tell
a no-op from a completed write.** Generalised: when a property's "nothing happened" state
is indistinguishable from its "everything happened" state at the layer you are observing,
move the observation, and the only way to know you have moved it far enough is to break
the code and watch.

### A criterion that names a mechanism needs an assertion for the mechanism

Discovered 2026-09-19, sweeping the datom-sets acceptance criteria, and it is a distinct
failure from the one above. **The shape: a criterion states a mechanism as well as an
outcome, and only the outcome is asserted.** In a healthy repo the mechanism and its
plausible alternative produce the same result, which is exactly why no test separates
them -- and exactly why the criterion bothered to name the mechanism.

Two live instances, both found by reading the criteria for a "how" clause and then
probing it, and both now fixed:

* **The kind check reads the per-artifact metadata document from storage, never the
  manifest row**, because the manifest can lag behind a write that got partway through.
  Sourcing it from the manifest instead left every test in the file green. The fixture
  that separates them makes the two **disagree** in the direction a half-finished write
  produces: storage knows the artifact, the manifest does not mention it. **Strip the row
  from both manifest copies** -- the clone's and storage's -- or you have ruled out one
  wrong source and not the other. The first draft of that test stripped the clone alone
  and a manifest-reading implementation sailed through it.
* **A set's stored payload is refused before it is parsed.** Moving the hash check to
  after the parse left every assertion green: the abort still happens, same class, same
  message. Only the absence of the parse *call* separates them, and the order is the
  point of the check rather than a detail of it -- those bytes are unverified and may be
  hostile, so a parser is what they must not reach.

**How to find these**: read each criterion for a phrase of the form *reads X rather than
Y*, *from storage not the manifest*, *before parsing*, *through the shared helper*,
*recorded not recomputed*. Most criteria state only an outcome, so the scan is bounded --
ten candidates out of 37 in that sweep, of which eight already had their own assertion.

**The fix pattern is two assertions, not one bigger one.** `commit_sha` is the template:
carry-forward and re-derive are two halves of one claim, and they got a test each, so
neither can be mistaken for the other.

### Probing a guard: the procedure, and the two ways a probe lies

The coverage rule is that a criterion or guard counts as covered only when a named test
**goes red on a deliberate break of the behaviour it claims**. Reading a test and judging
it relevant is not coverage. The procedure below is what makes the resulting red counts
mean something; it came out of 81 probes in datom-sets Task 16.

**Run a control, once per session.** A comment-only edit that changes no behaviour must
redden nothing. Without that result every red count in the sweep could be noise from
reloading the package, and there is no way to tell afterwards.

**A probe that reddens nothing is AMBIGUOUS, not a pass.** It means one of three things,
and they need different responses: the guard is missing; the fixture is too small to tell
the two behaviours apart; or **the probe did not change any behaviour**. That third one is
the common one and it looks exactly like the first two. Real examples, all from one sweep:

* an edit that selected hash fields by the full allowlist instead of the intersection --
  no-op, because the JSON serializer drops null entries;
* an edit that passed old labels into a rebuild while the line two below still restored
  them verbatim -- neutralised by its own neighbour;
* a test fixture edited to strip a manifest row from the clone, while the code under
  probe read storage's copy.

So before recording "nothing reddened, therefore a hole": confirm the edit changes an
observable. Compute both values side by side if that is quicker than reasoning about it.

**A crude probe reads like evidence and is not.** An edit that makes the package fail to
load, or reddens 80 tests because the write path no longer works, answers nothing about
the criterion you were asking about. Narrow it until exactly the intended behaviour
differs. The same applies from the other side: a break that reddens its own test *and*
seventy others is not diagnostic -- record it as such rather than as a clean pin, because
a regression there will not point at the criterion.

**And restore from your own copy, never from git** -- see the probe-harness entry above,
which exists because that cost a whole task's work once.
