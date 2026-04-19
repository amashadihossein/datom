# Tests for S3 path construction and parsing utilities
# Phase 1, Chunk 2

# --- .datom_build_storage_key() -----------------------------------------------------

test_that("build key with prefix and table data file", {
  key <- .datom_build_storage_key("proj", "customers", "abc123.parquet")
  expect_equal(key, "proj/datom/customers/abc123.parquet")
})

test_that("build key with prefix and table metadata", {
  key <- .datom_build_storage_key("proj", "customers", ".metadata", "metadata.json")
  expect_equal(key, "proj/datom/customers/.metadata/metadata.json")
})

test_that("build key with prefix and versioned metadata", {
  key <- .datom_build_storage_key("proj", "customers", ".metadata", "xyz789.json")
  expect_equal(key, "proj/datom/customers/.metadata/xyz789.json")
})

test_that("build key with prefix and repo-level metadata", {
  key <- .datom_build_storage_key("proj", ".metadata", "dispatch.json")
  expect_equal(key, "proj/datom/.metadata/dispatch.json")
})

test_that("build key without prefix", {
  key <- .datom_build_storage_key(NULL, "customers", "abc123.parquet")
  expect_equal(key, "datom/customers/abc123.parquet")
})

test_that("build key with multi-level prefix", {
  key <- .datom_build_storage_key("org/project-alpha", "orders", "def456.parquet")
  expect_equal(key, "org/project-alpha/datom/orders/def456.parquet")
})

test_that("build key strips leading/trailing slashes from segments", {
  key <- .datom_build_storage_key("/proj/", "/customers/", "/abc123.parquet/")
  expect_equal(key, "proj/datom/customers/abc123.parquet")
})

test_that("build key errors with no segments", {
  expect_error(.datom_build_storage_key("proj"), "At least one path segment")
  expect_error(.datom_build_storage_key(NULL), "At least one path segment")
})


# --- .datom_parse_s3_uri() -----------------------------------------------------

test_that("parse URI with bucket and prefix", {
  result <- .datom_parse_s3_uri("s3://my-bucket/data/proj")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data/proj")
})

test_that("parse URI with bucket only", {
  result <- .datom_parse_s3_uri("s3://my-bucket")
  expect_equal(result$bucket, "my-bucket")
  expect_null(result$prefix)
})

test_that("parse URI with single-level prefix", {
  result <- .datom_parse_s3_uri("s3://my-bucket/data")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data")
})

test_that("parse URI strips trailing slashes", {
  result <- .datom_parse_s3_uri("s3://my-bucket/data/proj/")
  expect_equal(result$bucket, "my-bucket")
  expect_equal(result$prefix, "data/proj")
})

test_that("parse URI with trailing slash and no prefix", {
  result <- .datom_parse_s3_uri("s3://my-bucket/")
  expect_equal(result$bucket, "my-bucket")
  expect_null(result$prefix)
})

test_that("parse URI errors on non-s3 scheme", {
  expect_error(.datom_parse_s3_uri("https://my-bucket/data"), "s3://")
})

test_that("parse URI errors on empty string", {
  expect_error(.datom_parse_s3_uri("s3://"), "bucket name")
})

test_that("parse URI errors on non-character input", {
  expect_error(.datom_parse_s3_uri(123), "single character string")
  expect_error(.datom_parse_s3_uri(c("s3://a", "s3://b")), "single character string")
})


# --- .datom_build_s3_uri() -----------------------------------------------------

test_that("build URI from bucket and key", {
  uri <- .datom_build_s3_uri("my-bucket", "proj/datom/customers/abc.parquet")
  expect_equal(uri, "s3://my-bucket/proj/datom/customers/abc.parquet")
})

test_that("build URI errors on empty bucket", {
  expect_error(.datom_build_s3_uri("", "key"), "non-empty")
})

test_that("build URI errors on empty key", {
  expect_error(.datom_build_s3_uri("bucket", ""), "non-empty")
})


# --- Round-trip ----------------------------------------------------------------

test_that("parse then build produces correct key", {
  parsed <- .datom_parse_s3_uri("s3://my-bucket/proj")
  key <- .datom_build_storage_key(parsed$prefix, "customers", ".metadata", "metadata.json")
  uri <- .datom_build_s3_uri(parsed$bucket, key)
  expect_equal(uri, "s3://my-bucket/proj/datom/customers/.metadata/metadata.json")
})

test_that("round-trip with no prefix", {
  parsed <- .datom_parse_s3_uri("s3://my-bucket")
  key <- .datom_build_storage_key(parsed$prefix, "orders", "abc.parquet")
  uri <- .datom_build_s3_uri(parsed$bucket, key)
  expect_equal(uri, "s3://my-bucket/datom/orders/abc.parquet")
})


# --- .datom_render_readme() ----------------------------------------------------

test_that("render_readme returns a character string", {
  readme <- .datom_render_readme(
    project_name = "STUDY_001",
    bucket = "my-bucket",
    prefix = "data/",
    region = "us-east-1",
    remote_url = "https://github.com/org/repo.git"
  )

  expect_type(readme, "character")
  expect_length(readme, 1L)
})

test_that("render_readme includes project name as heading", {
  readme <- .datom_render_readme(
    project_name = "STUDY_001",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "https://github.com/org/repo.git"
  )

  expect_match(readme, "# STUDY_001", fixed = TRUE)
})

test_that("render_readme includes bucket and region", {
  readme <- .datom_render_readme(
    project_name = "STUDY_001",
    bucket = "clinical-data-bucket",
    prefix = NULL,
    region = "eu-west-1",
    remote_url = "https://github.com/org/repo.git"
  )

  expect_match(readme, "clinical-data-bucket", fixed = TRUE)
  expect_match(readme, "eu-west-1", fixed = TRUE)
})

test_that("render_readme shows prefix when provided", {
  readme <- .datom_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = "study-001/",
    region = "us-east-1",
    remote_url = "url"
  )

  expect_match(readme, "study-001/", fixed = TRUE)
  expect_match(readme, '"study-001/"', fixed = TRUE)
})

test_that("render_readme shows *(none)* when prefix is NULL", {
  readme <- .datom_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url"
  )

  expect_match(readme, "*(none)*", fixed = TRUE)
})

test_that("render_readme includes store-based connection examples", {
  readme <- .datom_render_readme(
    project_name = "STUDY_001",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url"
  )

  expect_match(readme, "datom_get_conn", fixed = TRUE)
  expect_match(readme, "datom_store_s3", fixed = TRUE)
})

test_that("render_readme includes remote URL in clone command", {
  readme <- .datom_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "https://github.com/org/study-data.git"
  )

  expect_match(readme, "git clone https://github.com/org/study-data.git",
               fixed = TRUE)
})

test_that("render_readme includes datom version and date", {
  readme <- .datom_render_readme(
    project_name = "P",
    bucket = "b",
    prefix = NULL,
    region = "us-east-1",
    remote_url = "url"
  )

  expect_match(readme, format(Sys.Date(), "%Y-%m-%d"), fixed = TRUE)
  expect_match(readme, as.character(utils::packageVersion("datom")),
               fixed = TRUE)
})
