## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission. The only NOTE expected from CRAN's
  incoming checks is the standard "New submission" / maintainer note.

## Test environments

* macOS (aarch64), R 4.6.1
* windows-latest (GitHub Actions), R 4.6.1
* ubuntu-latest (GitHub Actions), R 4.6.1
* ubuntu-latest (GitHub Actions), R 4.5.3 (oldrel-1)

## R CMD check --as-cran

All four environments report Status: OK with 0 errors, 0 warnings,
0 notes locally. The "1 note" above refers to CRAN's incoming
pipeline NOTE for new submissions, which does not appear in local or
CI checks.

## Examples note

Examples that require external services (S3 / GitHub / a live git remote) are
wrapped in `\dontrun{}` since they cannot run without credentials and network
access. Functions that work offline (store constructors, predicates,
`datom_example_*`) have runnable examples.

## Downstream dependencies

None (new package).
