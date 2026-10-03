# Compute the datom-sv1 Canonical Set-Content Hash

The identity engine for a set artifact: `data_sha` for the payload's
semantic content.
`data_sha = h(0x06 || utf8("datom-sv1") || set(payload))`.

## Usage

``` r
.datom_canonical_set_hash(payload)
```

## Arguments

- payload:

  The set payload: a list with `members` (an unnamed list of member
  records, each an `id` map plus optional `tags` map) and optional
  set-level `tags`.

## Value

A 64-character SHA-256 hex string.

## Details

The hash domain is the **parsed-JSON data model**, not the in-memory R
object, and the write path – which necessarily starts from an in-memory
object – agrees with it *by construction* rather than through a
serialize-and-reparse pass. Each way a JSON round trip could mutate a
value is unrepresentable instead of handled: there are no numbers (so
integer-versus-double cannot arise), `NA` aborts and absence is omission
(so neither the string `"NA"` nor `null` can appear), and a single
string hashes equal to a one-element array (so scalar-versus-length-1 is
not a question). One structural condition remains: the payload must be
parsed with `simplifyVector = FALSE`, so `members[]` stays a list of
records instead of collapsing into a data frame. Both storage backends
already do that.

No I/O, no serializer, and no dependency that carries versioned data –
which is what makes the hash stable across R versions, `jsonlite`
versions, platforms, and architectures.
