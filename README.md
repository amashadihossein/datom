<!-- README.md is generated from README.Rmd. Please edit that file -->



# tbit

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN status](https://www.r-pkg.org/badges/version/tbit)](https://CRAN.R-project.org/package=tbit)
<!-- badges: end -->

tbit provides version-controlled data management for reproducible workflows. It abstracts tables as code in git while storing actual data in cloud storage (S3), enabling:
 
- Cloud-based data repositories with automatic versioning
- Complete data lineage tracking
- Access to any historical version for reproducibility
- Separation of data developer and data reader workflows

tbit is the foundational layer for the [daapr](https://github.com/amashadihossein/daapr) ecosystem.

## Installation

```r
# install.packages("pak")
pak::pak("amashadihossein/tbit")
```

## Overview

### For Data Developers (git + S3 access)

```r
library(tbit)

# Initialize a tbit repository
tbit_init_repo(
  path = "my_project",
  project_name = "MYPROJ",
  remote_url = "https://github.com/org/my_project.git",
  bucket = "my-bucket",
  prefix = "data/"
)

# Get connection
conn <- tbit_get_conn(path = "my_project")

# Sync input files to versioned storage
manifest <- tbit_sync_manifest(conn)
tbit_sync(conn, manifest)

# Write individual tables
tbit_write(conn, data = my_data, name = "customers", message = "Initial load")
```

### For Data Readers (S3 only)

```r
library(tbit)

# Connect directly to S3
conn <- tbit_get_conn(
  bucket = "my-bucket",
  prefix = "data/",
  project_name = "MYPROJ"
)

# List available tables
tbit_list(conn)

# Read current version
customers <- tbit_read(conn, "customers")

# Read specific version for reproducibility
customers_v1 <- tbit_read(conn, "customers", version = "abc123...")
```

## Design Principles

- **Git as source of truth**: All metadata versioned in git
- **Content addressing**: SHA-based storage for efficient deduplication
- **Separated workflows**: Developers need git + S3; readers need only S3
- **Language agnostic**: Parquet storage enables cross-language access

## Related Packages

| Package | Purpose |
|---------|---------|
| **tbit** | Version-controlled table storage (this package) |
| **dpbuild** | Data product construction |
| **dpdeploy** | Deployment orchestration |
| **dpi** | Data product access |

See `dev/tbit_specification.md` for full technical specification.
