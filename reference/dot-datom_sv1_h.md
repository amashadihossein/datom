# Hash Bytes for datom-sv1

The single SHA-256 call of the `datom-sv1` regime. Returns **raw** bytes
rather than hex because every intermediate digest is concatenated into
the next hash input; hex would double the width and put a text encoding
in the identity path.

## Usage

``` r
.datom_sv1_h(bytes)
```

## Arguments

- bytes:

  A raw vector.

## Value

A raw vector of 32 bytes.
