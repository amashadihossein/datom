## Submission

This is a feature release, 0.1.2 -> 0.2.0.

It adds a second kind of artifact, a "set": a named, versioned, citable list of
exact versions of other tables, which stores no data of its own. To make room
for it, one key in the package's own manifest file is renamed (`tables` ->
`artifacts`); existing repositories are converted automatically, with no manual
migration. Every manifest and metadata document now also records a format
number, so a version of the package that meets a repository it cannot fully
account for refuses to write rather than writing a file it does not understand.

This submission follows 0.1.2 (published 2026-09-08) by less than a month,
sooner than the usual interval between updates. The reason: this release
changes the format of the package's manifest file, and the package is being
presented publicly for the first time on 2026-10-20. Having 0.2.0 on CRAN
before then means the first wave of new users does not start on a version they
would then need to migrate away from. 0.1.2 was a patch release that only fixed
check failures.

## R CMD check results

win-builder, R-devel: `Status: OK` -- 0 errors, 0 warnings, 0 notes.

Local `--as-cran`: 0 errors, 0 warnings, 0 notes.

Test suite: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 4687 ]`. Both skips are
golden-vector parity checks whose reference script lives in `dev/`, which is
`.Rbuildignore`d and therefore absent from the tarball; the checks skip cleanly
when it is not present.

## Test environments

* win-builder, R-devel (2026-09-30 r90605 ucrt), x86_64-w64-mingw32 -- Status: OK
* local macOS Tahoe 26.6.2, aarch64-apple-darwin24.4.0, R 4.5.2 (2025-10-31)
* GitHub Actions, all passing on the submitted source:
  * macos-latest, R release
  * windows-latest, R release
  * ubuntu-latest, R release
  * ubuntu-latest, R oldrel-1
  * ubuntu-latest, R devel

The `ubuntu-latest` release job sets `init.defaultBranch` to `main` before
running the suite, so the class of failure fixed in 0.1.2 stays exercised on
Linux in CI.

## Spelling

The incoming check has previously flagged "filesystem" in the Description as
possibly misspelled. It is spelled as intended -- the closed compound is
standard usage in this domain and is used consistently throughout the package.

## References

There are no published references describing this package's methods, so the
Description field cites none.

## Downstream dependencies

None.
