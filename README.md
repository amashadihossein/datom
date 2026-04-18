
<!-- README.md is generated from README.Rmd. Please edit that file -->

# datom <img src="man/figures/logo.svg" align="right" height="139" alt="" />

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/datom)](https://CRAN.R-project.org/package=datom)
<!-- badges: end -->

datom provides version-controlled data management for reproducible
workflows. It abstracts tables as code in git while storing actual data
in cloud storage (S3), enabling:

- Cloud-based data repositories with automatic versioning
- Complete data lineage tracking
- Access to any historical version for reproducibility
- Separation of data developer and data reader workflows

datom is the foundational layer for the
[daapr](https://github.com/amashadihossein/daapr) ecosystem.

## Installation

``` r
# install.packages("pak")
pak::pak("amashadihossein/datom")
```

## Overview

### For Data Developers (git + S3 access)

``` r
library(datom)

# Initialize a datom repository
datom_init_repo(
  path = "my_project",
  project_name = "MYPROJ",
  remote_url = "https://github.com/org/my_project.git",
  bucket = "my-bucket",
  prefix = "data/"
)

# Get connection
conn <- datom_get_conn(path = "my_project")

# Sync input files to versioned storage
manifest <- datom_sync_manifest(conn)
datom_sync(conn, manifest)

# Write individual tables
datom_write(conn, data = my_data, name = "customers", message = "Initial load")
```

### For Data Readers (S3 only)

``` r
library(datom)

# Connect directly to S3
conn <- datom_get_conn(
  bucket = "my-bucket",
  prefix = "data/",
  project_name = "MYPROJ"
)

# List available tables
datom_list(conn)

# Read current version
customers <- datom_read(conn, "customers")

# Read specific version for reproducibility
customers_v1 <- datom_read(conn, "customers", version = "abc123...")
```

## Design Principles

- **Git as source of truth**: All metadata versioned in git
- **Content addressing**: SHA-based storage for efficient deduplication
- **Separated workflows**: Developers need git + S3; readers need only
  S3
- **Language agnostic**: Parquet storage enables cross-language access

## Related Packages

| Package      | Purpose                                         |
|--------------|-------------------------------------------------|
| **datom**    | Version-controlled table storage (this package) |
| **dpbuild**  | Data product construction                       |
| **dpdeploy** | Deployment orchestration                        |
| **dpi**      | Data product access                             |

See `dev/datom_specification.md` for full technical specification.
