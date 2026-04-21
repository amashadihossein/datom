# Create an S3 Client from Credentials

Constructs a
[`paws.storage::s3()`](https://paws-r.r-universe.dev/paws.storage/reference/s3.html)
client from credential values. Never stores raw credentials beyond the
paws client object.

## Usage

``` r
.datom_s3_client(
  access_key,
  secret_key,
  region = "us-east-1",
  endpoint = NULL,
  session_token = NULL
)
```

## Arguments

- access_key:

  AWS access key ID string.

- secret_key:

  AWS secret access key string.

- region:

  AWS region string (e.g. `"us-east-1"`).

- endpoint:

  Optional S3 endpoint URL. NULL for default AWS endpoint.

- session_token:

  Optional AWS session token for temporary credentials.

## Value

A `paws.storage` S3 client.
