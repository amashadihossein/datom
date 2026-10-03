# Hash an Already-Selected Set of Metadata Fields

The canonical-form half of `metadata_sha`, split from field selection so
that each half is testable on its own: this function decides how a
chosen set of fields becomes bytes and knows nothing about which fields
are identity.

## Usage

``` r
.datom_metadata_sha_from_fields(fields)
```

## Arguments

- fields:

  Named list of fields to hash, already filtered to the identity set by
  [`.datom_compute_metadata_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_compute_metadata_sha.md).

## Value

Character SHA-256 hash.

## Details

Sorts field names by C-locale byte order (`method = "radix"`) before
hashing so the result is deterministic regardless of field insertion
order **and** regardless of the host's `LC_COLLATE` (default collation
sorts differ between `C` and e.g. `en_US.UTF-8`, which would otherwise
make the same metadata hash differently on different machines). Sorting
here rather than relying on the declared order of
`.datom_metadata_identity_fields` is deliberate: it means hash stability
does not depend on how that constant happens to be written, so
re-ordering it for readability cannot silently change every recorded
version.
