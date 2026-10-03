# Encode a Member Record for datom-sv1

`member(x) = h(0x04 || map(x.id) || map(x.tags))`. Both slots are maps,
so swapping content between them cannot collide, and a member with no
tags encodes its `tags` slot as the empty map.

## Usage

``` r
.datom_sv1_member(x, what = "member")
```

## Arguments

- x:

  A member record: a list with `id` and optionally `tags`.

- what:

  Position label used in error messages.

## Value

A raw vector of 32 bytes.

## Details

An unexpected field aborts. That is not grammar validation creeping in:
a field the encoder ignored would be content that does not enter
identity, so two payloads differing in it would share one `data_sha` and
one storage address.
