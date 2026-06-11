# Verify a Single Storage Object

Checks that the object at `rel_key` in `to_conn` matches the one in
`from_conn`. Returns a named list with `key`, `ok` (logical), and
`issue` (character or `NA_character_`).

## Usage

``` r
.datom_verify_one(from_conn, to_conn, rel_key, mode)
```

## Arguments

- from_conn:

  Source `datom_conn`.

- to_conn:

  Destination `datom_conn`.

- rel_key:

  Relative key (after `{prefix}/datom/`).

- mode:

  `"structural"` or `"content"`.

## Value

Named list: `key`, `ok`, `issue`.
