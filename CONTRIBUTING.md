# Contributing to datom

Thank you for your interest in contributing. datom is a pre-release
package with an experimental API — things change frequently.

## Status

This package is under active development. APIs may change without
notice. If you are considering a large contribution, open an issue first
to discuss whether it fits the current roadmap.

## How to contribute

1.  **Bug reports**: Open an issue using the bug report template.
    Include a minimal reproducible example.
2.  **Feature requests**: Open an issue using the feature request
    template.
3.  **Pull requests**:
    - Fork the repository and create a branch from `main`.
    - Install development dependencies: `devtools::install_dev_deps()`.
    - Make your changes with tests: `devtools::test()` must pass.
    - Run `devtools::check()` — aim for 0 errors and 0 warnings.
    - Open a PR against `main` with a clear description of what changed
      and why.

## Development setup

``` r
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
- Exported functions: `datom_verb()`. Internal functions:
  `.datom_verb()`.
- Use `cli::` for user-facing messages, `fs::` for filesystem,
  [`glue::glue()`](https://glue.tidyverse.org/reference/glue.html) for
  string interpolation.

## Questions

Open an issue or email the maintainer at <amashadihossein@gmail.com>.
