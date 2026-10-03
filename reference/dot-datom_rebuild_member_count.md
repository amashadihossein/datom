# How Many Members a Set's Current Payload Holds

The third storage read a set's row costs. Only a set needs it, and only
a rebuild pays it: the healthy writer knows the count from the payload
it just canonicalized.

## Usage

``` r
.datom_rebuild_member_count(conn, name, data_sha)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Set name.

- data_sha:

  The current version's content hash – the payload's address.

## Value

An integer count, or `NULL`.

## Details

Returns `NULL` for anything that is not a readable payload – an unusable
`data_sha`, a missing object, a document that will not parse. That is
the same trade the rest of this file makes: an absent count is a gap
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
owns, while a stand-in count would be a statement about the set's
contents that nothing supports.
