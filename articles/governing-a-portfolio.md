# Governing a Study Portfolio

> **Where we left off:** Two engineers share STUDY-001 on S3. Writes
> serialize through a pull-before-push discipline.

A new study, STUDY-002, is starting. You — or your manager — now have to
think one level up: not “how do I version this study?” but “how do my
studies relate to each other?”

This article is the first time we look at datom from the **manager
view**. The capabilities are the same ones you’ve been using; the new
lens is the **governance repo** as a portfolio register.

``` r

state <- source(
  system.file("vignette-setup", "resume_article_7.R", package = "datom")
)$value

study_001_conn <- state$conn
gov_clone_path <- state$gov_clone_path
```

## What governance is, mechanically

Every datom project you’ve initialized so far has registered itself in a
shared git repository — the **governance repo** — under a folder named
after the project. List it:

``` r

fs::dir_ls(fs::path(gov_clone_path, "projects"), type = "directory")
#> /tmp/.../gov_clone/projects/STUDY_001
```

One folder per project. Inside each:

``` r

fs::dir_ls(fs::path(gov_clone_path, "projects", "STUDY_001"))
#> /tmp/.../projects/STUDY_001/dispatch.json
#> /tmp/.../projects/STUDY_001/migration_history.json
#> /tmp/.../projects/STUDY_001/ref.json
```

Three files, all small JSON, all committed to git:

- **`dispatch.json`** points readers (and tools like dpi) at the data
  store. It’s how a teammate with a `GITHUB_PAT` and a project name
  finds the bytes without you handing them a bucket URL.
- **`ref.json`** records the **current** data location and any prior
  locations the project has lived in. This is what makes bucket
  migration possible without rewriting history. See the
  [`ref.json`](https://amashadihossein.github.io/datom/articles/design-ref-json.md)
  design note.
- **`migration_history.json`** is the append-only log of those moves.

You don’t normally read these by hand — datom does. But the
manager-level property of the gov repo is that **every datom project in
your organization is one folder away from being discoverable**. A
`git clone` of the gov repo is a list of all your active studies.

## STUDY-002 starts

STUDY-002 is a small Phase 1 trial. Its data engineer is someone you
don’t directly manage; they’ll do the day-to-day work. As the manager,
your job is to make sure STUDY-002 lands in the same gov repo as
STUDY-001 so the portfolio stays coherent.

You don’t need to do anything special. The STUDY-002 engineer points at
the existing gov repo and runs the standard initialization — the same
sequence from [First
Extract](https://amashadihossein.github.io/datom/articles/first-extract.md),
now against a shared gov repo:

``` r

# (Run by the STUDY-002 engineer on their machine.)
study_002_dir <- fs::path(tempdir(), "study_002_data")

study_002_store <- datom_store(
  governance     = state$gov_component,    # SAME gov as STUDY-001
  data           = state$data_s3,          # could be a different bucket
  github_pat     = keyring::key_get("GITHUB_PAT"),
  gov_repo_url   = state$gov_repo_url,     # SAME gov repo URL
  gov_local_path = fs::path(tempdir(), "study_002_gov_clone")
)

datom_init_repo(
  path         = study_002_dir,
  project_name = "STUDY_002",
  store        = study_002_store,
  create_repo  = TRUE,
  repo_name    = "study-002-data"
)
```

The portfolio now has two projects. From your gov clone, after a
refresh:

``` r

datom_pull_gov(study_001_conn)
fs::dir_ls(fs::path(gov_clone_path, "projects"), type = "directory")
#> /tmp/.../gov_clone/projects/STUDY_001
#> /tmp/.../gov_clone/projects/STUDY_002
```

## `datom_pull_gov()` vs `datom_pull()`

You’ve been using
[`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md),
which refreshes both the data clone and the gov clone for the project
you’re connected to. From a manager’s seat you often want only the gov
side: “what projects are registered now?” not “what’s the latest version
of `lb`?”

[`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)
does exactly that. It’s a fetch + merge against the gov remote, scoped
to your gov clone. No data-store traffic. Cheap to run on a schedule.

This is the operation behind dashboards like “all studies registered in
the last 30 days” — and the foundation that a future
[`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
listing helper will sit on top of.

## Decommissioning

Studies end. STUDY-002 enrolls eight subjects, then sponsors pull the
trial. Six months later, regulatory says “you can purge the data.”

[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
does the full teardown in the right order:

``` r

study_002_conn <- datom_get_conn(path = study_002_dir, store = study_002_store)

datom_decommission(study_002_conn, confirm = "STUDY_002")
#> i Removing data store contents under datom/STUDY_002/
#> v Deleted GitHub repo `study-002-data`
#> v Removed local data clone /tmp/.../study_002_data
#> v Unregistered STUDY_002 from governance
#> v Removed gov storage entry projects/STUDY_002/
```

Five steps, run as a single command:

1.  Delete the parquet bytes under `datom/STUDY_002/` in the data store.
2.  Delete the data GitHub repo via the REST API. (Requires
    `delete_repo` on your `GITHUB_PAT`. Skipped with a warning if not
    present.)
3.  Remove the local data clone.
4.  Remove `projects/STUDY_002/` from the gov clone and push the
    deletion.
5.  Delete `projects/STUDY_002/` from gov storage.

The first four happen on this engineer’s machine. Step 4 is what makes
the decommissioning **organization-visible**: any other developer who
runs
[`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)
will see STUDY-002 disappear from their gov clone too. The portfolio is
back to STUDY-001 alone.

What
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
does **not** delete:

- The governance repo itself. STUDY-001 is still registered, still
  discoverable.
- Any external references — copies of STUDY-002 data your team
  downloaded for analyses, reports the statistician wrote against pinned
  versions, audit logs you exported. datom owns the source of truth, not
  the downstream artefacts.

The `confirm = "STUDY_002"` argument is mandatory and must match the
project name exactly. There is no interactive prompt. This is a
deliberate scriptability decision: cleanup operations should be
reproducible from a runbook, not gated on a human typing “yes” at a
console. Pair it with a code review on the calling script and you get
the same safety with better audit.

## Where you are

- The governance repo is a **portfolio register**: one folder per
  project, all in shared git.
- Adding a project is a normal
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  against the shared gov repo. No special manager-only command.
- [`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)
  refreshes the registry without touching any project’s data clone.
- [`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
  is the single command that cleanly removes a project from every place
  it lives — data store, GitHub, governance.

The user-journey track continues with **Auditing & Reproducibility**,
where the manager view sharpens further: regulator requests, version
pinning across time, validating the chain end-to-end. The companion
design notes that explain *why* governance and data live in separate
repos, and *why* `ref.json`/`dispatch.json` are split, are worth a read
when you have time:

- [`ref.json` and Always-Migration-Ready
  Storage](https://amashadihossein.github.io/datom/articles/design-ref-json.md)
- [`dispatch.json` and Self-Serve
  Access](https://amashadihossein.github.io/datom/articles/design-dispatch.md)
- [Two Repositories: Governance
  vs. Data](https://amashadihossein.github.io/datom/articles/design-two-repos.md)
- [Serverless and Distributed by
  Design](https://amashadihossein.github.io/datom/articles/design-serverless.md)
