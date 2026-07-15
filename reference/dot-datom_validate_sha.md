# Validate a SHA-Like Input (Version / data_sha)

Ensures a user-supplied SHA-like string is 6-64 lowercase hex
characters. Used to guard values that get spliced into a storage key
(`{table}/{sha}`) – on the local backend an unvalidated value like
`"../../x"` would escape the namespace via
[`fs::path()`](https://fs.r-lib.org/reference/path.html). The 6-char
minimum still covers the short prefixes
[`.datom_resolve_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_resolve_version.md)
intentionally accepts.

## Usage

``` r
.datom_validate_sha(x, arg = "version")
```

## Arguments

- x:

  Value to validate.

- arg:

  Name of the calling argument, used in the error message.

## Value

Invisible `x` on success. Aborts otherwise.
