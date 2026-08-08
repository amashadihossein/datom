## Resubmission

This is a resubmission. Thank you for the review.

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

## Downstream dependencies

None (new package).
