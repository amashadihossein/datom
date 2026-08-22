## Resubmission

This is a resubmission, version bumped 0.1.0 -> 0.1.1. Thank you to
Konstanze Lauseker for the review. The three points raised are addressed
below.

* Removed the `\examples` sections from the two unexported functions that had
  them, `.datom_build_storage_key()` and `.datom_parse_s3_uri()`.

* Replaced the commented-out example in `datom_projects.Rd` with an
  executable one.

* Removed all `\dontrun{}` wrappers. The package now has no `\dontrun{}` and
  no `\donttest{}` sections; every example runs. Examples that need a data
  repository build a self-contained project in `tempdir()`, using a bare
  local git repository as the remote and a local directory as the object
  store, so no credentials or network access are required. Those examples
  are conditional on `git2r` (and `rio` for `datom_sync()`), which are in
  Suggests.

One further change, not requested in the review: DESCRIPTION now declares
`Depends: R (>= 4.1.0)` explicitly. `R CMD build` had been adding that
dependency itself, since the package uses the native pipe, and declaring it in
the sources makes the requirement explicit rather than build-time.

## R CMD check results

0 errors | 0 warnings | 1 note

The single NOTE is the incoming-checks note and covers two items: the standard
"New submission" / maintainer flag, and one possibly-misspelled word in the
Description (see Spelling below).

## Test environments

* win-builder, R Under development (unstable) (2026-08-08 r90381 ucrt),
  x86_64-w64-mingw32 -- Status: 1 NOTE (as above)
* local macOS (aarch64), R 4.5.2
* GitHub Actions:
  * macos-latest, R 4.6.1
  * windows-latest, R 4.6.1
  * ubuntu-latest, R 4.6.1 (release)
  * ubuntu-latest, R 4.5.3 (oldrel-1)
  * ubuntu-latest, R Under development (unstable) (2026-06-21 r90185)

All environments report 0 errors and 0 warnings.

## Spelling

The incoming check flags "filesystem" in the Description as possibly
misspelled. It is spelled as intended -- the closed compound is standard
usage in this domain and is used consistently throughout the package.

## References

There are no published references describing this package's methods, so
the Description field cites none.

## Downstream dependencies

None (new package).
