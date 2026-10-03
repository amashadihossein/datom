# Encode a String for datom-sv1

`str(s) = h(0x01 || utf8(s))`. No length prefix and no terminator: the
string is the entire hash input, so nothing follows it to be confused
with.

## Usage

``` r
.datom_sv1_str(s, what = "value")
```

## Arguments

- s:

  A length-1 character vector.

- what:

  Key path used in error messages.

## Value

A raw vector of 32 bytes.
