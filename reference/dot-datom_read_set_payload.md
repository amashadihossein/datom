# Download, Verify and Parse a Set's Stored Payload

Download, hash, **then** parse. The order is the point: a set read must
not parse an unverified payload, which is the same gate position
[`.datom_read_parquet()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_parquet.md)
uses for `parquet_sha`.

## Usage

``` r
.datom_read_set_payload(conn, name, data_sha, document_sha)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Set name.

- data_sha:

  The resolved content hash – the payload's storage address.

- document_sha:

  The recorded SHA-256 of the stored payload bytes.

## Value

The parsed payload, with `members` kept as a list of records.

## Details

**[`.datom_storage_read_json()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_read_json.md)
cannot be used here, and it would work.** It parses, so after calling it
there is nothing left to hash but bytes re-serialized locally – a hash
of bytes nobody stored, which is exactly the defect the write path
guards against, inverted. It returns a structure identical to parsing
the downloaded file, so nothing fails if you reach for it; the integrity
check simply stops meaning anything.

**A missing `document_sha` is an error, not a skip.** `parquet_sha`'s
skip-on-absent branch exists purely as a grace for metadata written
before that field did. Sets have recorded `document_sha` since their
first write, so there is no legacy population to be lenient about, and
reproducing the grace would build a silent-degradation path on purpose.

`data_sha` is deliberately **not** recomputed from the parsed payload.
It is the address the payload was fetched from, so it catches nothing
`document_sha` did not, and it would refuse a payload a newer datom
wrote – the sv1 encoder aborts on a top-level payload key it does not
know. Same reason the parsed payload is not re-validated. Reads limp.
