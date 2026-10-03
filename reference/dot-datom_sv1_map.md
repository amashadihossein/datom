# Encode a Map for datom-sv1

`map(m) = h(0x03 || concat(str(k) || strset(m[k]) for k in sort(keys(m), radix)))`.

## Usage

``` r
.datom_sv1_map(m, what = "map")
```

## Arguments

- m:

  A named list, or `NULL`.

- what:

  Key path used in error messages.

## Value

A raw vector of 32 bytes.

## Details

One encoder serves both slots of a member record – the `id` and the
`tags` – so a fifth `id` field added later is just another key: no
positional convention to maintain, and no absent-versus-empty question.
`id` values are single strings, encoded as one-element string sets;
enforcing "exactly these four keys, each single-valued" is validation's
job, not the encoder's.

An absent map (`NULL`) and an empty map both encode as `h(0x03)`.
Writers never emit an empty map, but the encoder must not depend on
that.
