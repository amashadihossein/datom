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

## Gotchas

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
- **metadata SHA excludes volatile fields**: `created_at` and `datom_version` are stripped before hashing. Adding new metadata fields that should NOT affect versioning must be added to the `volatile` vector in `.datom_compute_metadata_sha()`.
- **version_history dedup guard**: `.datom_write_metadata_local()` skips appending when the latest entry has the same version SHA. This prevents duplicates but means the guard relies on metadata_sha correctness.
- **`datom_pull()` is git-only**: No S3 manifest refresh — git is the source of truth for all metadata. The manifest is committed to git and pulled with everything else.
- **`governance.json` mirror -- git canonical, storage derived**: The git copy at `.datom/governance.json` is written and committed first; the storage mirror at `{prefix}/datom/.metadata/governance.json` is pushed in the same step. Never write only one. If the mirror is missing, `.datom_sync_governance_json(conn)` regenerates it from the git copy. The file is write-once -- do not update it after creation.
- **S3 namespace check swallows connectivity errors**: `.datom_check_namespace_free()` in `datom_init_repo()` warns but doesn't fail on network errors — offline init still works, S3 push will fail later anyway.
- **`git2r::clone()` target path**: Must not exist or must be an empty directory. `datom_clone()` validates this upfront.
- **`paws.storage` has no STS**: `sts` is in `paws.security.identity`, not `paws.storage`. Validation uses `HeadBucket` only (validates both credentials and bucket access).
- **Storage abstraction**: Business logic must call `.datom_storage_*()`, never `.datom_s3_*()` or `.datom_local_*()` directly. The dispatch layer in `R/utils-storage.R` routes based on `conn$backend`.
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
  running it prints the goldens (numeric `48b4c0cb...`, mixed `47c94f30...`) and passes 27/27
  self-tests. The package implementation must stay byte-identical to it; the Property 11 parity
  test in `test-utils-sha.R` enforces that and skips when `dev/` is absent (so it legitimately
  reports SKIP 1 under `R CMD check`). If parity ever reddens, fix the package, not the
  reference.
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
- **The `metadata_sha` golden `59f1f1d9...`** in `test-utils-sha.R` survives the radix-sort and
  volatile-set changes because its fixture has no `parquet_sha`/`column_hashes` and only simple
  lowercase names. Keep that fixture as-is or the golden needs re-deriving.
- **An acceptance gate can have a legitimate false positive; scope the gate, do not edit the
  source.** `grep -rn "as.data.frame" R/utils-sha.R` will never be empty: the one hit is the
  roxygen line documenting the invariant ("no `as.data.frame()` or coercion, and never invokes
  arrow"). The gate's intent is that no *executable* coercion exists, which the comment asserts.
  Pipe through `grep -vE ":[0-9]+:[[:space:]]*#"` and record the documented match. Deleting the
  comment to satisfy a literal grep would delete the statement of the invariant.

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
