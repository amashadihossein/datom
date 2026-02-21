# Tests for S3 path construction and parsing utilities
# Phase 1, Chunk 2

# --- .tbit_build_s3_key() -----------------------------------------------------

test_that("build key with prefix and table data file", {
  key <- .tbit_build_s3_key("proj", "customers", "abc123.parquet")
  expect_equal(key, "proj/tbit/customers/abc123.parquet")
})

test_that("build key with prefix and table metadata", {
  key <- .tbit_build_s3_key("proj", "customers", ".metadata", "metadata.json")
  expect_equal(key, "proj/tbit/customers/.metadata/metadata.json")
})

test_that("build key with prefix and versioned metadata", {
  key <- .tbit_build_s3_key("proj", "customers", ".metadata", "xyz789.json")
  expect_equal(key, "proj/tbit/customers/.metadata/xyz789.json")
})

test_that("build key with prefix and repo-level metadata", {
  key <- .tbit_build_s3_key("proj", ".metadata", "routing.json")
  expect_equal(key, "proj/tbit/.metadata/routing.json")
})

test_that("build key with prefix and redirect file", {
  key <- .tbit_build_s3_key("proj", ".redirect.json")
  expect_equal(key, "proj/tbit/.redirect.json")
})

test_that("build key without prefix", {
  key <- .tbit_build_s3_key(NULL, "customers", "abc123.parquet")
  expect_equal(key, "tbit/customers/abc123.parquet")
})

test_that("build key with multi-level prefix", {
  key <- .tbit_build_s3_key("org/project-alpha", "orders", "def456.parquet")
  expect_equal(key, "org/project-alpha/tbit/orders/def456.parquet")
})

test_that("build key strips leading/trailing slashes from segments", {
  key <- .tbit_build_s3_key("/proj/", "/customers/", "/abc123.parquet/")
  expect_equal(key, "proj/tbit/customers/abc123.parquet")
})

test_that("build key errors with no segments", {
  expect_error(.tbit_build_s3_key("proj"), "At least one path segment")
  expect_error(.tbit_build_s3_key(NULL), "At least one path segment")
})


# --- .tbit_parse_s3_uri() -----------------------------------------------------

test_that("parse URI with bucket and prefix", {
  result <- .tbit_parse_s3_uri("s3://my-bucket/data/proj")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data/proj")
})

test_that("parse URI with bucket only", {
  result <- .tbit_parse_s3_uri("s3://my-bucket")
  expect_equal(result$bucket, "my-bucket")
  expect_null(result$prefix)
})

test_that("parse URI with single-level prefix", {
  result <- .tbit_parse_s3_uri("s3://my-bucket/data")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data")
})

test_that("parse URI strips trailing slashes", {
  result <- .tbit_parse_s3_uri("s3://my-bucket/data/proj/")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data/proj")
})

test_that("parse URI with trailing slash and no prefix", {
  result <- .tbit_parse_s3_uri("s3://my-bucket/")
  expect_equal(result$bucket, "my-bucket")
  expect_null(result$prefix)
})

test_that("parse URI errors on non-s3 scheme", {
  expect_error(.tbit_parse_s3_uri("https://my-bucket/data"), "s3://")
})

test_that("parse URI errors on empty string", {
  expect_error(.tbit_parse_s3_uri("s3://"), "bucket name")
})

test_that("parse URI errors on non-character input", {
  expect_error(.tbit_parse_s3_uri(123), "single character string")
  expect_error(.tbit_parse_s3_uri(c("s3://a", "s3://b")), "single character string")
})


# --- .tbit_build_s3_uri() -----------------------------------------------------

test_that("build URI from bucket and key", {
  uri <- .tbit_build_s3_uri("my-bucket", "proj/tbit/customers/abc.parquet")
  expect_equal(uri, "s3://my-bucket/proj/tbit/customers/abc.parquet")
})

test_that("build URI errors on empty bucket", {
  expect_error(.tbit_build_s3_uri("", "key"), "non-empty")
})

test_that("build URI errors on empty key", {
  expect_error(.tbit_build_s3_uri("bucket", ""), "non-empty")
})


# --- Round-trip ----------------------------------------------------------------

test_that("parse then build produces correct key", {
  parsed <- .tbit_parse_s3_uri("s3://my-bucket/proj")
  key <- .tbit_build_s3_key(parsed$prefix, "customers", ".metadata", "metadata.json")
  uri <- .tbit_build_s3_uri(parsed$bucket, key)
  expect_equal(uri, "s3://my-bucket/proj/tbit/customers/.metadata/metadata.json")
})

test_that("round-trip with no prefix", {
  parsed <- .tbit_parse_s3_uri("s3://my-bucket")
  key <- .tbit_build_s3_key(parsed$prefix, "orders", "abc.parquet")
  uri <- .tbit_build_s3_uri(parsed$bucket, key)
  expect_equal(uri, "s3://my-bucket/tbit/orders/abc.parquet")
})


# --- .tbit_render_readme() ----------------------------------------------------

test_that("render_readme returns a character string", {
  readme <- .tbit_render_readme(
    project_name = "STUDY_001",
    bucket = "my-bucket",
    prefix = "data/",
    region = "us-east-1",
    remote_url = "https://github.com/org/repo.git",
    cred_names = list(
      access_key_env = "TBIT_STUDY_001_ACCESS_KEY_ID",
      secret_key_env = "TBIT_STUDY_001_SECRET_ACCESS_KEY"
    )
  )

  expect_type(readme, "character")
  expect_length(readme, 1L)
})

test_that("render_readme includes project name as heading", {
  readme <- .tbit_render_readme(
    project_name = "STUDY_001",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "https://github.com/org/repo.git",
    cred_names = list(
      access_key_env = "TBIT_STUDY_001_ACCESS_KEY_ID",
      secret_key_env = "TBIT_STUDY_001_SECRET_ACCESS_KEY"
    )
  )

  expect_match(readme, "# STUDY_001", fixed = TRUE)
})

test_that("render_readme includes bucket and region", {
  readme <- .tbit_render_readme(
    project_name = "STUDY_001",
    bucket = "clinical-data-bucket",
    prefix = NULL,
    region = "eu-west-1",
    remote_url = "https://github.com/org/repo.git",
    cred_names = list(
      access_key_env = "A",
      secret_key_env = "S"
    )
  )

  expect_match(readme, "clinical-data-bucket", fixed = TRUE)
  expect_match(readme, "eu-west-1", fixed = TRUE)
})

test_that("render_readme shows prefix when provided", {
  readme <- .tbit_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = "study-001/",
    region = "us-east-1",
    remote_url = "url",
    cred_names = list(access_key_env = "A", secret_key_env = "S")
  )

  expect_match(readme, "study-001/", fixed = TRUE)
  expect_match(readme, '"study-001/"', fixed = TRUE)
})

test_that("render_readme shows *(none)* when prefix is NULL", {
  readme <- .tbit_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url",
    cred_names = list(access_key_env = "A", secret_key_env = "S")
  )

  expect_match(readme, "*(none)*", fixed = TRUE)
  expect_match(readme, "prefix       = NULL", fixed = TRUE)
})

test_that("render_readme includes credential env var names", {
  readme <- .tbit_render_readme(
    project_name = "STUDY_001",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url",
    cred_names = list(
      access_key_env = "TBIT_STUDY_001_ACCESS_KEY_ID",
      secret_key_env = "TBIT_STUDY_001_SECRET_ACCESS_KEY"
    )
  )

  expect_match(readme, "TBIT_STUDY_001_ACCESS_KEY_ID", fixed = TRUE)
  expect_match(readme, "TBIT_STUDY_001_SECRET_ACCESS_KEY", fixed = TRUE)
})

test_that("render_readme includes remote URL in clone command", {
  readme <- .tbit_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "https://github.com/org/study-data.git",
    cred_names = list(access_key_env = "A", secret_key_env = "S")
  )

  expect_match(readme, "git clone https://github.com/org/study-data.git",
               fixed = TRUE)
})

test_that("render_readme includes tbit version and date", {
  readme <- .tbit_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url",
    cred_names = list(access_key_env = "A", secret_key_env = "S")
  )

  expect_match(readme, format(Sys.Date(), "%Y-%m-%d"), fixed = TRUE)
  expect_match(readme, as.character(utils::packageVersion("tbit")),
               fixed = TRUE)
})
