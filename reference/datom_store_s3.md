# Create an S3 Store Component

Constructs a validated S3 storage component for use as either the
governance or data component of a `datom_store`. Validates credentials
and bucket access at construction time (unless `validate = FALSE`).

## Usage

``` r
datom_store_s3(
  bucket,
  prefix = NULL,
  region = "us-east-1",
  access_key,
  secret_key,
  session_token = NULL,
  validate = TRUE
)
```

## Arguments

- bucket:

  S3 bucket name.

- prefix:

  S3 key prefix (e.g., `"project/"`). NULL for no prefix.

- region:

  AWS region (default `"us-east-1"`).

- access_key:

  AWS access key ID.

- secret_key:

  AWS secret access key.

- session_token:

  Optional AWS session token (for temporary credentials).

- validate:

  If `TRUE` (default), validate credentials and bucket access at
  construction time. Set to `FALSE` for tests or offline use.

## Value

A `datom_store_s3` object.
