# Validate a datom Table Name

Checks that a table name is filesystem-safe and S3-safe. Returns the
name invisibly on success, errors with a clear message on failure.

## Usage

``` r
.datom_validate_name(name)
```

## Arguments

- name:

  Character string to validate as a table name.

## Value

Invisible `name` on success.
