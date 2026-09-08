## Submission

This is a patch release, 0.1.1 -> 0.1.2, fixing the `tests` ERROR reported by
the CRAN check farm against 0.1.1 on four Linux flavors
(`r-devel-linux-x86_64-debian-clang`, `r-devel-linux-x86_64-debian-gcc`,
`r-patched-linux-x86_64`, `r-release-linux-x86_64`).

The failure was in the test fixtures, not in package code, and no user-facing
behaviour changes.

Cause: fixtures that build a throwaway git repository and push it to a local
stand-in remote named the branch `refs/heads/master` as a string literal, but
`git2r::init()` honours git's `init.defaultBranch` setting, so on a machine
whose default branch name is something other than `master` the fixture pushed a
branch that had never been created. All 26 failures were this one error, raised
during setup. Fixtures now read the branch name from the repository they just
created. The package's own push helper already derived the branch from the
repository, which is why fixtures routing through it succeeded on the same
machines.

The failure was reproduced locally, including CRAN's exact counts, and the fix
verified under three different `init.defaultBranch` values.

This submission follows 0.1.1 by less than the usual interval because it exists
only to clear the check failures reported against 0.1.1. It contains no other
changes.

## R CMD check results

win-builder, R-devel: `Status: OK` -- 0 errors, 0 warnings, 0 notes.

Local `--as-cran`: 0 errors, 0 warnings, 1 note. The note is from the
incoming-checks step, verbatim:

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Afshin Mashadi-Hossein <amashadihossein@gmail.com>'

Days since last update: 6
```

The day count is as of the check run above and will be a day or two higher at
submission; the reason for the short interval is given in the Submission section.

Test suite, identical on both: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 2451 ]`. The
skip is a golden-vector parity check whose reference script lives in `dev/`,
which is `.Rbuildignore`d and therefore absent from the tarball; the check skips
cleanly when it is not present.

## Test environments

* win-builder, R-devel, x86_64-w64-mingw32 -- Status: OK
* local macOS, aarch64-apple-darwin24.4.0, R 4.5.2 (2025-10-31) -- with
  `init.defaultBranch` set to `main`, i.e. the configuration under which 0.1.1
  failed, and again with the default setting
* GitHub Actions:
  * macos-latest, R release
  * windows-latest, R release
  * ubuntu-latest, R release
  * ubuntu-latest, R oldrel-1
  * ubuntu-latest, R devel

The `ubuntu-latest` release job sets `init.defaultBranch` to `main` before
running the suite, so this class of failure is now exercised on Linux in CI
rather than discovered downstream.

## Spelling

The incoming check has previously flagged "filesystem" in the Description as
possibly misspelled. It is spelled as intended -- the closed compound is
standard usage in this domain and is used consistently throughout the package.

## References

There are no published references describing this package's methods, so the
Description field cites none.

## Downstream dependencies

None.
