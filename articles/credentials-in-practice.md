# Credentials in Practice

This article is the **reference** for credentials, store construction,
roles, and a handful of utilities that the user-journey articles refer
to without explaining in depth. Read it linearly the first time; come
back to it as a lookup later.

## The two-credential model

datom keeps two things separate:

| Resource       | Backed by   | Credentials                         |
|----------------|-------------|-------------------------------------|
| Metadata (git) | GitHub      | `GITHUB_PAT`                        |
| Data (parquet) | S3 or local | AWS keys (S3) or filesystem (local) |

Every datom project requires git, always – there is no “no-remote” mode.
The data side has two backends today (S3 and local filesystem); local is
for development and small-team workflows, S3 is for shared team or
production use.

For a developer, both halves matter. For a reader, the same is true –
read access to git is how the reader resolves the project; read access
to the data store is how parquet bytes arrive.

## Storing credentials with keyring

`keyring` puts secrets in your operating system’s credential store
(macOS Keychain, Windows Credential Locker, Linux Secret Service). datom
never reads files for credentials and does not honor environment
variables for production use – you pass values explicitly.

### One-time per machine

``` r

keyring::key_set("GITHUB_PAT")
keyring::key_set("AWS_ACCESS_KEY_ID")
keyring::key_set("AWS_SECRET_ACCESS_KEY")
```

Each call prompts for the value once and stores it. Retrieve with:

``` r

keyring::key_get("GITHUB_PAT")
```

The vignettes use `keyring::key_get(...)` inline at every store
construction site; copy that pattern in your own code.

### What the GITHUB_PAT needs

| Operation | Scope required |
|----|----|
| Read a project (clone + pull) | `repo` (read) |
| Write to a project | `repo` (write) |
| `datom_init_repo(create_repo = TRUE)` | `repo` (create) |
| [`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md) repo deletion | `delete_repo` |

For a fine-grained PAT: `Contents: Read and write` (or `Read` for
readers), `Administration: Read and write` if you need to create or
delete repos.

### What the AWS credentials need

The validation step runs `HeadBucket` on both governance and data
buckets at conn time. That implies:

- `s3:ListBucket` on each bucket (or, more narrowly, on the prefix you
  use).
- `s3:GetObject` for reads.
- `s3:PutObject`, `s3:DeleteObject` for writes (developers).

Readers need only `s3:ListBucket` + `s3:GetObject`.

## The store object

Every datom call needs a **store** – the bundle of governance and data
backends plus credentials. There are three constructors:

### `datom_store_local(path)`

Filesystem backend. Used for both halves in articles 1-3, and as the
governance side once you graduate to S3.

``` r

gov_local <- datom_store_local(path = "~/datom-gov")
```

A `datom_store_local` is plain: a directory path. It carries no
credentials.

### `datom_store_s3(bucket, prefix, region, access_key, secret_key)`

S3 backend. The `prefix` is appended under `datom/` inside the bucket to
form the actual storage root.

``` r

data_s3 <- datom_store_s3(
  bucket     = "your-org-datom-data",
  prefix     = "study-001/",
  region     = "us-east-1",
  access_key = keyring::key_get("AWS_ACCESS_KEY_ID"),
  secret_key = keyring::key_get("AWS_SECRET_ACCESS_KEY")
)
```

`print(data_s3)` masks the secret key. Don’t
[`dput()`](https://rdrr.io/r/base/dput.html) a store object into a
script – always reconstruct from `keyring`.

### `datom_store(governance, data, github_pat, ...)`

The composite store – a data component (required), an optional
governance component, and the GitHub PAT:

``` r

# Solo project: no governance attached yet.
store <- datom_store(
  governance = NULL,
  data       = data_s3,
  github_pat = keyring::key_get("GITHUB_PAT")
)

# When sharing or registering in a portfolio, attach gov via
# datom_attach_gov() -- see the Promoting to S3 article.
```

The governance component is optional; the data component is not. A
`datom_store(governance = NULL, ...)` is valid and useful for the solo
phase of a project. Governance is added on demand with
[`datom_attach_gov()`](https://amashadihossein.github.io/datom/reference/datom_attach_gov.md),
and once attached cannot be detached.

### Predicates

Each constructor has a matching predicate:

``` r

is_datom_store(store)             # TRUE for the composite
is_datom_store_local(gov_local)   # TRUE
is_datom_store_s3(data_s3)        # TRUE
```

Useful when writing helper functions that branch on backend without
unpacking the object.

## Roles: developer vs reader

datom auto-detects the role at conn time:

| Has `GITHUB_PAT`? | Has `path`? | Role        |
|-------------------|-------------|-------------|
| Yes               | Yes         | `developer` |
| No or read-only   | No          | `reader`    |

Developer = “I have a local data clone and can write.” Reader = “I have
credentials and a project name; I want to read.” Both use
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md);
the difference is which arguments are present.

``` r

# Developer
dev_conn <- datom_get_conn(path = "~/study-001-data", store = store)

# Reader
reader_conn <- datom_get_conn(project_name = "STUDY_001", store = reader_store)
```

`reader_store` is a
[`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)
constructed with read-only AWS credentials and a read-only `GITHUB_PAT`.
Same shape; lower-permission keys.

## Verifying a repo on disk

[`is_valid_datom_repo()`](https://amashadihossein.github.io/datom/reference/is_valid_datom_repo.md)
is the cheap “is this directory a datom project?” check, no network
calls:

``` r

is_valid_datom_repo("~/study-001-data")
#> [1] TRUE

is_valid_datom_repo("~/random-folder")
#> [1] FALSE

is_valid_datom_repo("~/random-folder", verbose = TRUE)
#> x git_initialized
#> x datom_initialized
#> x datom_manifest
#> x renv_initialized
#> [1] FALSE
```

Pass `verbose = TRUE` to see which subchecks failed. Use this in scripts
that want to gracefully handle “the user pointed at the wrong
directory.”

## Recovery & introspection utilities

A few functions appear in the user-journey articles only briefly.
They’re collected here for reference.

### `datom_sync_dispatch(conn)`

Re-pushes governance metadata (`dispatch.json`, `manifest.json`, etc.)
from the local clone to the storage backend. Use after a manual data
migration or when
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
reports storage drift on metadata.

``` r

datom_sync_dispatch(conn)
#> Sync this project's dispatch + manifest to S3? [y/N]:
```

Interactive by default; pass `.confirm = FALSE` for scripted use.
Developer-only.

### `datom_get_parents(conn, name, version = NULL)`

Reads the `parents` field from a table’s metadata. datom doesn’t
populate `parents` on its own – it’s a slot for upstack tools (dpbuild,
in particular) to record lineage when they construct derived tables.

``` r

datom_get_parents(conn, "lb")
#> NULL    # no recorded parents for raw extracts

datom_get_parents(derived_conn, "lb_summary")
#> [[1]]
#>   source: "datom"
#>   table:  "lb"
#>   version: "9f3a1b2c..."
```

For raw EDC extracts written via
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
directly, `parents` is `NULL`. For now you can think of it as a
forward-looking API surface.

### `datom_example_cutoffs()`

Companion to
[`datom_example_data()`](https://amashadihossein.github.io/datom/reference/datom_example_data.md).
Returns the six monthly cutoff dates the simulator uses for STUDY-001:

``` r

datom_example_cutoffs()
#>    month_1    month_2    month_3    month_4    month_5    month_6
#> "2026-01-28" "2026-02-28" "2026-03-28" "2026-04-28" "2026-05-28" "2026-06-28"
```

Used internally to filter `datom_example_data("dm")` to a particular
month’s snapshot.

## Troubleshooting checklist

If a call fails, walk these in order:

1.  **`keyring::key_list()`** – are the secrets actually stored on this
    machine? A fresh container or VM has none.
2.  **`is_datom_store(store)`** – did the composite constructor succeed?
    Print it; the print methods mask secrets but reveal shape.
3.  **`is_valid_datom_repo(path)`** – is the directory you’re pointing
    at actually a datom project?
4.  **[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
    error message** – it tells you which side failed (gov reachability,
    data reachability, ref resolution).
5.  **`datom_validate(conn)`** – once a conn is built, this is the
    end-to-end sanity check.

The errors are designed to be specific. If you get a message that
doesn’t pinpoint the issue, that’s a bug – file an issue on GitHub.

## Where to go next

You’ve now seen all of datom. The user-journey track told the story from
first extract to portfolio governance. The design notes (sidebar group
“Design”) explain *why* the system is shaped this way and are the right
next stop if you intend to extend datom or build on top of it.
