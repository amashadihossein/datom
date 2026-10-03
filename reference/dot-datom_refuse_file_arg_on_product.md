# Refuse a File-Import Argument on a Product Repo

Silently ignoring it would let a caller believe the argument did
something.

## Usage

``` r
.datom_refuse_file_arg_on_product(arg)
```

## Arguments

- arg:

  The argument that was supplied.

## Value

Does not return; aborts with class `datom_sync_file_arg_on_product`.
