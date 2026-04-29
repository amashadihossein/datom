# Create a datom Connection Object

Internal constructor for the `datom_conn` S3 class. Two modes:

- **Developer**: has `path` to local repo + git access

- **Reader**: S3-only access, no local repo

## Usage

``` r
new_datom_conn(
  project_name,
  root,
  prefix = NULL,
  region = "us-east-1",
  client,
  path = NULL,
  role = c("reader", "developer"),
  endpoint = NULL,
  gov_root = NULL,
  gov_prefix = NULL,
  gov_region = NULL,
  gov_client = NULL,
  gov_local_path = NULL,
  backend = "s3"
)
```

## Arguments

- project_name:

  Project name string.

- root:

  Storage root (S3 bucket name or local directory path).

- prefix:

  Storage prefix (can be NULL).

- region:

  AWS region string (data store). Ignored for local backend.

- client:

  A storage client (paws S3 client or NULL for local).

- path:

  Local repo path (NULL for readers).

- role:

  One of `"developer"` or `"reader"`.

- endpoint:

  Optional S3 endpoint URL (e.g., for S3 access points). NULL for
  default.

- gov_root:

  Governance storage root (can be NULL for legacy conns).

- gov_prefix:

  Governance prefix (can be NULL).

- gov_region:

  Governance region (can be NULL).

- gov_client:

  Governance storage client (can be NULL).

- gov_local_path:

  Absolute path to the local gov clone (NULL for readers).

## Value

A `datom_conn` object.

## Details

The primary fields (`root`, `prefix`, `region`, `client`) refer to the
**data store**. Governance store fields are prefixed with `gov_`.
