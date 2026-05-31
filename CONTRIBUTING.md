# Contributing to datom

Thank you for your interest in contributing. datom is a pre-release package with
an experimental API — things change frequently.

## Status

This package is under active development. APIs may change without notice. If you
are considering a large contribution, open an issue first to discuss whether it
fits the current roadmap.

## How to contribute

1. **Bug reports**: Open an issue using the bug report template. Include a
   minimal reproducible example.
2. **Feature requests**: Open an issue using the feature request template.
3. **Pull requests**:
   - Fork the repository and create a branch from `main`.
   - Install development dependencies: `devtools::install_dev_deps()`.
   - Make your changes with tests: `devtools::test()` must pass.
   - Run `devtools::check()` — aim for 0 errors and 0 warnings.
   - Open a PR against `main` with a clear description of what changed and why.

## Development setup

```r
# Install dependencies
devtools::install_dev_deps()

# Load the package for interactive development
devtools::load_all()

# Run tests
devtools::test()

# Full check
devtools::check()
```

## Code style

- Flat over nested: use early returns and guard clauses.
- Tidyverse idioms: pipes, `purrr`, `dplyr`.
- Exported functions: `datom_verb()`. Internal functions: `.datom_verb()`.
- Use `cli::` for user-facing messages, `fs::` for filesystem, `glue::glue()`
  for string interpolation.

## Issue resolution workflow

Every code change starts as a GitHub issue. Once an issue is assigned or
self-assigned, follow these steps:

1. **Understand the issue.** Read the full issue body and any linked comments.
   Assess validity of the problem statement and the proposed solution (if any)
   critically -- check whether it is coherent with the current codebase and
   design before accepting the framing.

2. **Scope the work and comment if needed.** If the proposed solution is
   unclear, incomplete, or requires clarification, post a scoping comment on the
   issue before writing any code.

3. **Create a branch.** Branch off `main` with a descriptive name:
   ```
   git checkout -b issue-{number}-{short-slug}
   ```

4. **Plan (for non-trivial changes).** If the fix touches more than two files
   or requires more than one logical commit, write a short plan before coding:
   - What needs to change and why.
   - Which tests and documentation need updating.
   - Any invariants or must-never rules to keep in mind.

   For large cross-cutting work, follow the full phase-doc process described in
   `dev/README.md`.

5. **Develop.** Make the change. Run `devtools::test()` (unfiltered) before
   every commit and include the test count in the commit message. If the count
   drops, something was lost. Keep commits small and logically focused.

6. **Clean up.** Before opening a PR:
   - Remove dead code, debug prints, and stray comments.
   - Update any affected documentation (`man/`, vignettes, `_pkgdown.yml`).
   - Run `devtools::check()` -- aim for 0 errors and 0 warnings.

7. **Open a PR against `main`.** Include:
   - A `Closes #N` reference in the description.
   - A concise summary of what changed and why.
   - The test count delta (e.g. `tests: 1713 (+13)`).

   Before a second attempt at any remote-mutating action (`git push`,
   `gh pr create`, etc.), verify remote state first (`gh pr list`,
   `git log --remotes`) to avoid duplicates.

## Questions

Open an issue or email the maintainer at <amashadihossein@gmail.com>.
