# Render README.md from Template

Reads the template from `inst/templates/README.md` and fills in
project-specific values using `{{{ }}}` delimiters.

## Usage

``` r
.datom_render_readme(
  project_name,
  backend = "s3",
  root,
  prefix,
  region = NULL,
  remote_url,
  gov = NULL
)
```

## Arguments

- project_name:

  Project name string.

- backend:

  Storage backend (`"s3"` or `"local"`).

- root:

  Storage root (S3 bucket name or local directory path).

- prefix:

  Storage prefix (can be NULL).

- region:

  AWS region string (NULL for local backend).

- remote_url:

  Git remote URL.

- gov:

  Governance store component (e.g. from
  [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)),
  or `NULL` for a solo project with no governance attached. Determines
  whether the rendered store snippets use `governance = NULL` or a
  gov-store constructor.

## Value

Character string — the rendered README content.
