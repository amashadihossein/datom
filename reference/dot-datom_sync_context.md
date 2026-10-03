# Which Context a Sync Call Is In: an Ordinary Repo or a Product Repo

The two sync verbs do different jobs depending on the repo: an ordinary
repo imports source files, a product repo maps its one set against
source projects. This reads which, once per call, so every branch below
it acts on one answer.

## Usage

``` r
.datom_sync_context(conn)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

## Value

A list of `product` (`TRUE` for a `mode: product` repo) and `set` (the
declared set name as written, possibly `NULL`). A repo with no config is
reported as ordinary: the file path then fails with its own message
about an uninitialised repo.

## Details

**Read from `.datom/project.yaml`, not from the connection**, for the
reason
[`.datom_refuse_import_on_product()`](https://amashadihossein.github.io/datom/reference/dot-datom_refuse_import_on_product.md)
gives: the answer can authorise a write, and a hand edit or a pull can
change the file after the connection was built. And the parse is gated –
the file's declared format is checked before `mode` or `set` is read out
of it.
