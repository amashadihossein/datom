# Polish: Issues #14, #15, #19, #20

**Branch**: `fix/issues-14-15-19-20-polish`
**Status**: 🔄 in-progress

## Goal

Four small polish fixes in `R/conn.R`. No new exports, no schema changes,
no new tests infrastructure needed — targeted guards and a default-path fix.

## Issues

| # | Title | File / Line |
|---|-------|-------------|
| 14 | `print.datom_conn` shows `Data region` for local backend | `R/conn.R` ~202 |
| 15 | `print.datom_conn` warns on `normalizePath` after decommission | `R/conn.R` ~223 |
| 19 | `datom_init_gov` default `gov_local_path` is CWD-relative | `R/conn.R` ~713 |
| 20 | `datom_init_gov` idempotence check local-only; stale clone no-ops against empty remote | `R/conn.R` ~728 |

## Fixes

### #14 — Region guard
In `print.datom_conn`, the `Data region` line is already guarded by
`!is.null(x$region)`, but local conns carry a non-NULL region (defaulting to
`"us-east-1"` from store construction or similar). Add a second guard:
`x$backend != "local"`.

### #15 — normalizePath warning
`{.path {x$path}}` in cli internally calls `normalizePath()` which warns when
the directory no longer exists. Fix: pass `normalizePath(x$path, mustWork = FALSE)`
so the warning is suppressed while still showing the path string.

### #19 — CWD-relative default
Replace the `fs::path_abs(base_name)` default (which resolves against CWD)
with `fs::path(tools::R_user_dir("datom", "data"), base_name)`. This is
deterministic, not CWD-relative, and consistent with R's user-data conventions.
Update the roxygen `@param` doc to reflect the new default.

### #20 — Remote-aware idempotence
After the local `.gitkeep` check passes, call `git2r::ls_remotes()` (or
`system2("git", c("ls-remote", "--heads", url))`) to verify the remote has at
least one commit. If the remote is empty, skip the early return and fall
through to re-seed and push.  
Cheapest approach: use `git2r::ls_remotes()` on a temporary clone-check via
`git2r::remote_url()` on the existing local repo, then check if the remote
HEAD exists with `git ls-remote`.

## Acceptance Criteria

- [ ] `print(conn)` for a local-backend conn shows no `Data region` line
- [ ] `print(conn)` after `datom_decommission()` emits no `normalizePath` warning
- [ ] `datom_init_gov(gov_local_path = NULL, ...)` defaults to `R_user_dir("datom","data")/repo_name`, never CWD
- [ ] `datom_init_gov()` with stale local skeleton + empty remote re-seeds and pushes instead of silently no-oping
- [ ] `devtools::test()` green, count non-decreasing

## Progress Log

<!-- append after each commit -->
