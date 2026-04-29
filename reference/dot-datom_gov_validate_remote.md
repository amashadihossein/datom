# Validate Gov Clone Remote URL

Reads the first configured remote from the gov clone and compares it
against `expected_url`. Aborts if they differ. This prevents silently
reusing a clone that points at a different governance repo.

## Usage

``` r
.datom_gov_validate_remote(gov_local_path, expected_url)
```

## Arguments

- gov_local_path:

  Absolute path to the governance clone directory.

- expected_url:

  Expected remote URL (from `store$gov_repo_url`).

## Value

Invisible TRUE.

## Details

URL comparison is normalised: trailing `.git` is stripped from both
sides before comparison so `https://github.com/org/acme-gov` and
`https://github.com/org/acme-gov.git` are treated as equivalent.
