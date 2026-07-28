## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission, so CRAN's incoming checks report the standard
  "New submission" / maintainer NOTE.

## Test environments

* win-builder, R Under development (unstable) (2026-07-26 r90304 ucrt),
  x86_64-w64-mingw32 -- Status: 1 NOTE (New submission only)
* macOS (aarch64), R 4.6.1
* ubuntu-latest (GitHub Actions), R-devel
* ubuntu-latest (GitHub Actions), R 4.6.1 (release)
* ubuntu-latest (GitHub Actions), R 4.5.3 (oldrel-1)
* windows-latest (GitHub Actions), R 4.6.1

All environments report 0 errors and 0 warnings. The only NOTE on
win-builder R-devel is the incoming-checks "New submission" note.

## Spelling

The incoming check flags "filesystem" in the Description as possibly
misspelled. It is spelled as intended -- the closed compound is standard
usage in this domain and is used consistently throughout the package.

## References

There are no published references describing this package's methods, so
the Description field cites none.

## Examples

Examples that require external services (S3, GitHub, or a live git remote)
are wrapped in `\dontrun{}`, since they cannot run without credentials and
network access. Functions that work offline (store constructors,
predicates, `datom_check_hashable()`, `datom_lineage_union()`,
`datom_example_*`) have runnable examples.

## Downstream dependencies

None (new package).
