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

0 errors | 0 warnings | 1 note

Test suite: 2451 passing, 1 skipped, 0 failures. The skip is a golden-vector
parity check whose reference script lives in `dev/`, which is `.Rbuildignore`d
and therefore absent from the tarball; the check skips cleanly when it is not
present.

The single NOTE is the incoming-checks maintainer note.

## Test environments

* local macOS (aarch64), R 4.5.2 -- with `init.defaultBranch` set to `main`,
  i.e. the configuration under which 0.1.1 failed, and again with the default
  setting
* GitHub Actions:
  * macos-latest, R release
  * windows-latest, R release
  * ubuntu-latest, R release
  * ubuntu-latest, R oldrel-1
  * ubuntu-latest, R devel

## Spelling

The incoming check has previously flagged "filesystem" in the Description as
possibly misspelled. It is spelled as intended -- the closed compound is
standard usage in this domain and is used consistently throughout the package.

## References

There are no published references describing this package's methods, so the
Description field cites none.

## Downstream dependencies

None.
