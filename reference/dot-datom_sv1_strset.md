# Encode a String Set for datom-sv1

`strset(v) = h(0x02 || concat(str(e) for e in sort(unique(v), radix)))`.
Order and multiplicity are not identity: a multi-valued tag models
simultaneous membership in several categories, which has no order and no
notion of a repeated element.

## Usage

``` r
.datom_sv1_strset(v, what = "value")
```

## Arguments

- v:

  A character vector, or a list of length-1 strings.

- what:

  Key path used in error messages.

## Value

A raw vector of 32 bytes.

## Details

The empty set is `h(0x02)` over an empty concatenation – a pinned
golden.
