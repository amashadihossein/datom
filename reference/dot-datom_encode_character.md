# Encode a Character Payload for Canonical Hashing

The character encoder for the `chr` column kind (character and factor
columns). Emits a one-byte-per-row NA mask (`0x01` where
[`is.na()`](https://rdrr.io/r/base/NA.html), `0x00` otherwise) followed
by each value re-encoded to UTF-8 via
[`enc2utf8()`](https://rdrr.io/r/base/Encoding.html) and NUL-terminated.
The leading mask makes `NA` and the empty string `""` distinguishable
(both have an empty value section, but `NA` sets its mask byte). No
Unicode normalization is applied, so NFC and NFD forms of the same text
encode differently (a documented, benign limitation).

## Usage

``` r
.datom_encode_character(x)
```

## Arguments

- x:

  A vector coercible to character (character or factor).

## Value

A raw vector: `length(x)` mask bytes followed by the NUL-terminated
UTF-8 value bytes.
