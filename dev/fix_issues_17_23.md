# Fix: Issues #17 and #23

**Branch**: `fix/issues-17-23`
**Status**: Chunk 1 -- in progress

## Goal

Two closely related bugs: both stem from the same root -- `datom_conn` does not carry
enough credential/identity state, so downstream helpers have to re-discover it from the
environment or the filesystem.

| Issue | Title | Root cause |
|-------|-------|------------|
| #17 | conn should carry `data_repo_url`; audit all remote lookups | `datom_decommission()` calls `git2r::remote_url()` on the local clone -- fails if clone is gone |
| #23 | git push/pull ignores PAT passed via `datom_store()`; only reads env var | `.datom_git_credentials()` ignores `store$github_pat`; always reads `GITHUB_PAT`/`GITHUB_TOKEN` env vars |

**Why together**: both are fixed by threading two new fields onto `datom_conn`:
- `conn$data_repo_url` (issue #17) -- the GitHub HTTPS remote
- `conn$github_pat` (issue #23) -- the PAT used at store-construction time

Once both fields are on `conn`, every downstream helper that today re-reads the git
remote or the env var can instead read from `conn`, consistent with the secret-handling
principle documented in the updated Copilot instructions.

---

## Acceptance Criteria

1. `new_datom_conn()` accepts `data_repo_url` and `github_pat` as optional fields.
2. `datom_get_conn()` (developer path) populates `conn$data_repo_url` from the local
   git remote and `conn$github_pat` from `store$github_pat`.
3. `datom_init_repo()` populates both fields on the returned conn (used by callers
   that chain into write/push after init).
4. `datom_clone()` populates both fields on the returned conn.
5. `datom_attach_gov()` carries both fields through to the fresh conn it returns.
6. `.datom_git_credentials()` accepts a required `pat` argument (no default);
   **no env-var fallback** — if `pat` is NULL or empty, returns NULL (unauthenticated).
   Callers are responsible for supplying the PAT via `conn$github_pat`.
7. `.datom_git_push()` and `.datom_git_pull()` accept a `pat` argument and
   pass it to `.datom_git_credentials()`.
8. All callers of `.datom_git_push()` / `.datom_git_pull()` pass `conn$github_pat`
   (or `NULL` for gov helpers where no conn is in scope -- unauthenticated/SSH is
   acceptable there; gov PAT threading is out of scope).
9. `datom_decommission()` uses `conn$data_repo_url` as the sole source for the
   GitHub remote URL; **no `git2r::remote_url()` fallback** -- if `conn$data_repo_url`
   is NULL, abort with a clear error directing the user to rebuild conn via
   `datom_get_conn()`.
10. `datom_decommission()` uses `conn$github_pat` as the sole PAT source;
    **no env-var fallback** -- if `conn$github_pat` is NULL, the GitHub repo deletion
    step skips authentication (unauthenticated delete will fail naturally).
11. `print.datom_conn()` does NOT print the PAT (mask or omit).
12. All existing tests pass; new tests cover the AC items above.

---

## Chunks

| # | Name | Files | Status |
|---|------|-------|--------|
| 1 | Extend `datom_conn` + credential threading | `R/conn.R`, `R/utils-git.R` | ⏳ next |
| 2 | `datom_decommission()` conn-first remote + PAT | `R/decommission.R` | ☐ todo |
| 3 | Tests | `tests/testthat/test-utils-git.R`, `test-conn.R`, `test-decommission.R` | ☐ todo |

---

## Chunk 1 -- Extend `datom_conn` + credential threading

### What changes

**`R/utils-git.R`** -- `.datom_git_credentials(remote_url, pat = NULL)`

```r
# Before
.datom_git_credentials <- function(remote_url) {
  if (!grepl("^https://", remote_url, ignore.case = TRUE)) return(NULL)
  pat <- Sys.getenv("GITHUB_PAT", unset = "")
  if (!nzchar(pat)) pat <- Sys.getenv("GITHUB_TOKEN", unset = "")
  if (!nzchar(pat)) return(NULL)
  git2r::cred_user_pass(username = "git", password = pat)
}

# After -- no env-var fallback; PAT must be supplied explicitly
.datom_git_credentials <- function(remote_url, pat = NULL) {
  if (!grepl("^https://", remote_url, ignore.case = TRUE)) return(NULL)
  if (is.null(pat) || !nzchar(pat)) return(NULL)
  git2r::cred_user_pass(username = "git", password = pat)
}
```

**`.datom_git_push(path, pat = NULL)`** and **`.datom_git_pull(path, pat = NULL)`** --
add `pat` arg, pass to `.datom_git_credentials()`.

**`.datom_check_git_current(path, pat = NULL)`** -- same pattern.

**`new_datom_conn()`** -- add `data_repo_url = NULL` and `github_pat = NULL`.
  - `github_pat` is stored in memory only; `print.datom_conn()` must not emit it.

**`datom_get_conn()` developer path (`.datom_get_conn_developer()`)** -- after building
`conn`, set:
```r
conn$data_repo_url <- tryCatch(
  { repo <- git2r::repository(path); git2r::remote_url(repo, git2r::remotes(repo)[[1L]]) },
  error = function(e) NULL
)
conn$github_pat <- store$github_pat
```

**`datom_init_repo()`** -- after `.datom_git_push(path)` succeeds, set both fields on
`data_conn` before returning:
```r
data_conn$data_repo_url <- remote_url
data_conn$github_pat    <- store$github_pat
```
Then pass `pat = store$github_pat` to all `.datom_git_push()` / `.datom_git_pull()`
calls in `datom_init_repo()`.

**`datom_attach_gov()`** -- pass `conn$github_pat` to its `.datom_git_push(conn$path)`
call, and carry both fields through to `fresh_conn`.

**`datom_clone()`** -- set both fields on the returned conn.

**Gov helpers that call `.datom_git_push()` / `.datom_git_pull()` with only a path
(no conn)** -- `datom_init_gov()`, `.datom_gov_commit()`, `.datom_gov_push()`,
`.datom_gov_pull()` -- leave `pat = NULL` (acceptable: gov helpers take their own
explicit `github_pat` param; the env-var fallback is the documented secondary path
for gov ops).

**`R/read_write.R` `datom_write()`** and **`R/sync.R` `datom_sync()`** -- both have
`conn` in scope; pass `pat = conn$github_pat`.

**`R/utils-sha.R`** -- `repo_path` helpers do not have `conn`; leave `pat = NULL`.

**`R/ref.R`** -- similar; leave `pat = NULL`.

### Invariants
- Never persist `github_pat` to disk (project.yaml, JSON, git).
- `print.datom_conn()` must not print the raw PAT (either omit or mask).
- **No env-var fallback inside datom git helpers** -- PAT flows `store → conn → helper`.
- Gov-path callers pass `pat = NULL` (unauthenticated/SSH acceptable for gov ops).

---

## Chunk 2 -- `datom_decommission()` conn-first remote + PAT

### What changes

**`R/decommission.R`** step 2 (GitHub repo deletion):

```r
# Before: reads remote URL from git clone (fails if clone gone)
repo_url <- tryCatch(
  { repo <- git2r::repository(conn$path); git2r::remote_url(repo, "origin") },
  error = function(e) NULL
)
pat <- Sys.getenv("GITHUB_PAT")

# After: conn is the sole source; abort if data_repo_url is missing
if (is.null(conn$data_repo_url)) {
  cli::cli_abort(c(
    "Cannot delete GitHub repository: {.field data_repo_url} is not set on this conn.",
    "i" = "Rebuild the conn with {.fn datom_get_conn} and retry."
  ))
}
repo_url <- conn$data_repo_url
pat      <- conn$github_pat  # NULL if not set; delete step will fail naturally without auth
```

---

## Chunk 3 -- Tests

### `test-utils-git.R`

- `.datom_git_credentials()` with explicit `pat` arg uses the supplied PAT, not env var.
- `.datom_git_credentials()` with `pat = NULL` falls back to `GITHUB_PAT` env var.
- `.datom_git_credentials()` with `pat = NULL` and no env var returns NULL.
- `.datom_git_push()` with `pat = "tok"` calls `.datom_git_credentials(url, pat = "tok")`.
- `.datom_git_pull()` with `pat = "tok"` passes through.

### `test-conn.R`

- `new_datom_conn()` stores `data_repo_url` and `github_pat` fields.
- Developer conn via `.datom_get_conn_developer()` with a store carrying `github_pat`
  populates `conn$github_pat` and `conn$data_repo_url`.
- `print.datom_conn()` does NOT emit the raw PAT string.

### `test-decommission.R`

- `datom_decommission()` uses `conn$data_repo_url` when the local clone is absent.
- `datom_decommission()` uses `conn$github_pat` for repo deletion when set,
  ignoring the env var.
- Existing decommission tests continue to pass (backward-compatible fallback).

---

## Progress Log

| Date | What shipped |
|------|-------------|
