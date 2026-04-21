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
  remote_url
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

## Value

Character string — the rendered README content.
