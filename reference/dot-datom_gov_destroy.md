# Destroy the Gov Repo (Guard + Local Clone Removal)

Refuses to proceed if any projects are still registered in the gov
clone, unless `force = TRUE`. When clear (or forced), removes the local
gov clone directory. GitHub repo and storage deletion are handled by the
caller (e.g., sandbox teardown via `gh` CLI and storage backend tools).

## Usage

``` r
.datom_gov_destroy(gov_local_path, force = FALSE)
```

## Arguments

- gov_local_path:

  Absolute path to the local gov clone.

- force:

  Logical. If `TRUE`, destroy even when projects are registered.

## Value

Named character vector of registered project names (invisible), so the
caller can clean up projects first if needed.

## Details

**`GOV_SEAM:`** The companion package will eventually own the full gov
lifecycle (init -\> register -\> destroy) and expose a user-facing
`gov_decommission()`. In Phase 15, only the dev sandbox calls this.
