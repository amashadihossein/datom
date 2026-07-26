# Encode a Numeric Payload for Canonical Hashing

The single shared numeric encoder used by the `num`, `date`, `time`, and
`drtn` column kinds of `datom-cv1`. Produces a fixed,
platform-independent byte sequence: IEEE-754 doubles written
little-endian regardless of host endianness, with three
canonicalizations so that logically-equal values encode identically:

## Usage

``` r
.datom_encode_numeric(x)
```

## Arguments

- x:

  A vector coercible to double (logical, integer, double, or the numeric
  payload of a Date/POSIXct/difftime column).

## Value

A raw vector of `8 * length(x)` bytes.

## Details

- Every `NaN` payload (e.g. `0/0`, a signalling NaN, a negative NaN) is
  folded to the pinned canonical quiet `NaN` bit pattern
  `0x7ff8000000000000` (see `.datom_nan_canonical`).

- `-0.0` is converted to `+0.0`.

- `NA_real_` is preserved as its own distinct bit pattern – it is a
  specific `NaN` payload in R (high word `0x7ff00000`, low word `1954`),
  fixed by R itself and therefore portable, and is deliberately *not*
  folded into the canonical `NaN`, so `NA_real_` and `NaN` encode
  differently.

No rounding is applied: doubles are encoded bit-exact.

**Why the canonical `NaN` is written as bytes, not assigned as a
value.** Assigning R's `NaN` (`d[nan_idx] <- NaN`) folds NaN *payloads*
but inherits the host's NaN *sign bit*: R's `NaN` is `0x7ff8...` on
macOS/arm64 and `0xfff8...` on Linux/x86_64, because it comes from a
C-level `0.0/0.0`. That made `data_sha` platform-dependent for any table
containing a `NaN` – caught by the CI golden matrix (the macOS job
passed, the Linux job did not). Splicing the pinned bytes in directly
removes the host from the equation, which is the whole premise of a
canonical hash.
