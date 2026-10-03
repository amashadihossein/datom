# Render a Digest as Lowercase Hex

Used for the two places the specification names hex: the collation key
for member digests, and the final `data_sha` string. Byte order and
lowercase-hex C-locale order agree (`00`-`09` before `0a`-`0f`, digits
before letters in ASCII), so sorting either representation gives the
same result – hex is named in the spec because it is what a reader can
compare by eye.

## Usage

``` r
.datom_sv1_hex(x)
```

## Arguments

- x:

  A raw vector.

## Value

A character string of `2 * length(x)` lowercase hex digits.
