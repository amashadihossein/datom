# Parse S3 URI into Components

Extracts bucket and prefix from an `s3://` URI.

## Usage

``` r
.datom_parse_s3_uri(uri)
```

## Arguments

- uri:

  Character string S3 URI (e.g., "s3://my-bucket/prefix/path").

## Value

Named list with `bucket` (character) and `prefix` (character or NULL).

## Examples

``` r
if (FALSE) { # \dontrun{
.datom_parse_s3_uri("s3://my-bucket/data/proj")
# → list(bucket = "my-bucket", prefix = "data/proj")

.datom_parse_s3_uri("s3://my-bucket")
# → list(bucket = "my-bucket", prefix = NULL)
} # }
```
