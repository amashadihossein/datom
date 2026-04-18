# Tests for datom store — Phase 10 Chunks 1-2

# Helper: create a minimal S3 component for composite tests
make_component <- function(bucket = "test-bucket", prefix = "proj/") {
  datom_store_s3(
    bucket = bucket, prefix = prefix,
    access_key = "AKIAEXAMPLE1", secret_key = "secretkey1",
    validate = FALSE
  )
}

# --- datom_store_s3: Structural validation ------------------------------------

test_that("datom_store_s3() creates valid store with validate = FALSE", {
  store <- datom_store_s3(
    bucket = "my-bucket",
    prefix = "proj/",
    region = "us-east-1",
    access_key = "AKIAIOSFODNN7EXAMPLE",
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    validate = FALSE
  )

  expect_s3_class(store, "datom_store_s3")
  expect_equal(store$bucket, "my-bucket")
  expect_equal(store$prefix, "proj/")
  expect_equal(store$region, "us-east-1")
  expect_equal(store$access_key, "AKIAIOSFODNN7EXAMPLE")
  expect_false(store$validated)
  expect_null(store$identity)
})

test_that("datom_store_s3() accepts NULL prefix", {

  store <- datom_store_s3(
    bucket = "my-bucket",
    region = "us-east-1",
    access_key = "AKIAIOSFODNN7EXAMPLE",
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    validate = FALSE
  )

  expect_null(store$prefix)
})

test_that("datom_store_s3() accepts session_token", {
  store <- datom_store_s3(
    bucket = "my-bucket",
    access_key = "AKIAIOSFODNN7EXAMPLE",
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    session_token = "FwoGZXIvYXdzEBYaDH",
    validate = FALSE
  )

  expect_equal(store$session_token, "FwoGZXIvYXdzEBYaDH")
})

test_that("datom_store_s3() errors on empty bucket", {
  expect_error(
    datom_store_s3(bucket = "", access_key = "x", secret_key = "y", validate = FALSE),
    "bucket"
  )
})

test_that("datom_store_s3() errors on NULL bucket", {
  expect_error(
    datom_store_s3(bucket = NULL, access_key = "x", secret_key = "y", validate = FALSE),
    "bucket"
  )
})

test_that("datom_store_s3() errors on NA bucket", {
  expect_error(
    datom_store_s3(bucket = NA_character_, access_key = "x", secret_key = "y", validate = FALSE),
    "bucket"
  )
})

test_that("datom_store_s3() errors on empty access_key", {
  expect_error(
    datom_store_s3(bucket = "b", access_key = "", secret_key = "y", validate = FALSE),
    "access_key"
  )
})

test_that("datom_store_s3() errors on empty secret_key", {
  expect_error(
    datom_store_s3(bucket = "b", access_key = "x", secret_key = "", validate = FALSE),
    "secret_key"
  )
})

test_that("datom_store_s3() errors on empty region", {
  expect_error(
    datom_store_s3(bucket = "b", region = "", access_key = "x", secret_key = "y", validate = FALSE),
    "region"
  )
})

test_that("datom_store_s3() errors on invalid prefix type", {
  expect_error(
    datom_store_s3(bucket = "b", prefix = 123, access_key = "x", secret_key = "y", validate = FALSE),
    "prefix"
  )
})

test_that("datom_store_s3() errors on empty session_token", {
  expect_error(
    datom_store_s3(
      bucket = "b", access_key = "x", secret_key = "y",
      session_token = "", validate = FALSE
    ),
    "session_token"
  )
})

test_that("datom_store_s3() errors on vector bucket", {
  expect_error(
    datom_store_s3(bucket = c("a", "b"), access_key = "x", secret_key = "y", validate = FALSE),
    "bucket"
  )
})


# --- is_datom_store_s3 --------------------------------------------------------

test_that("is_datom_store_s3() returns TRUE for store objects", {
  store <- datom_store_s3(
    bucket = "b", access_key = "x", secret_key = "y", validate = FALSE
  )
  expect_true(is_datom_store_s3(store))
})

test_that("is_datom_store_s3() returns FALSE for other objects", {
  expect_false(is_datom_store_s3(list()))
  expect_false(is_datom_store_s3("string"))
  expect_false(is_datom_store_s3(NULL))
})


# --- print.datom_store_s3 ----------------------------------------------------

test_that("print.datom_store_s3() masks secrets and returns invisibly", {
  store <- datom_store_s3(
    bucket = "my-bucket",
    prefix = "proj/",
    access_key = "AKIAIOSFODNN7EXAMPLE",
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    validate = FALSE
  )

  output <- capture.output(result <- print(store), type = "message")
  output_text <- paste(output, collapse = "\n")

  # Secrets should be masked
  expect_false(grepl("AKIAIOSFODNN7EXAMPLE", output_text))
  expect_true(grepl("AKIA", output_text))

  # Config should be visible
  expect_true(grepl("my-bucket", output_text))
  expect_true(grepl("proj/", output_text))

  # Returns invisibly
  expect_s3_class(result, "datom_store_s3")
})

test_that("print.datom_store_s3() omits prefix when NULL", {
  store <- datom_store_s3(
    bucket = "b", access_key = "AKIAEXAMPLE1", secret_key = "y",
    validate = FALSE
  )

  output <- capture.output(print(store), type = "message")
  output_text <- paste(output, collapse = "\n")
  expect_false(grepl("Prefix", output_text))
})


# --- .datom_mask_secret -------------------------------------------------------

test_that(".datom_mask_secret() shows first 4 chars then ****", {
  expect_equal(.datom_mask_secret("AKIAIOSFODNN7"), "AKIA****")
})

test_that(".datom_mask_secret() masks short secrets entirely", {
  expect_equal(.datom_mask_secret("abc"), "****")
  expect_equal(.datom_mask_secret("abcd"), "****")
})

test_that(".datom_mask_secret() handles NULL and empty", {
  expect_equal(.datom_mask_secret(NULL), "(not set)")
  expect_equal(.datom_mask_secret(""), "(not set)")
})

test_that(".datom_mask_secret() shows 5-char secret partially", {
  expect_equal(.datom_mask_secret("abcde"), "abcd****")
})


# --- Connectivity validation (mocked) ----------------------------------------

test_that(".datom_validate_s3_store() succeeds with valid mocks", {
  mockery::stub(
    .datom_validate_s3_store, "paws.storage::sts",
    function(...) {
      list(
        get_caller_identity = function() {
          list(Account = "123456789012", Arn = "arn:aws:iam::123456789012:user/test")
        }
      )
    }
  )

  mockery::stub(
    .datom_validate_s3_store, "paws.storage::s3",
    function(...) {
      list(
        head_bucket = function(Bucket) list()
      )
    }
  )

  result <- .datom_validate_s3_store(
    access_key = "AKIAEXAMPLE1",
    secret_key = "secret",
    session_token = NULL,
    region = "us-east-1",
    bucket = "my-bucket"
  )

  expect_equal(result$aws_account_id, "123456789012")
  expect_true(grepl("arn:aws", result$aws_arn))
})

test_that(".datom_validate_s3_store() errors on STS failure", {
  mockery::stub(
    .datom_validate_s3_store, "paws.storage::sts",
    function(...) {
      list(
        get_caller_identity = function() stop("InvalidClientTokenId")
      )
    }
  )

  expect_error(
    .datom_validate_s3_store(
      access_key = "bad", secret_key = "bad",
      session_token = NULL, region = "us-east-1", bucket = "b"
    ),
    "credential validation failed"
  )
})

test_that(".datom_validate_s3_store() errors on 403 HeadBucket", {
  mockery::stub(
    .datom_validate_s3_store, "paws.storage::sts",
    function(...) {
      list(
        get_caller_identity = function() {
          list(Account = "123456789012", Arn = "arn:aws:iam::123456789012:user/test")
        }
      )
    }
  )

  mockery::stub(
    .datom_validate_s3_store, "paws.storage::s3",
    function(...) {
      list(
        head_bucket = function(Bucket) stop("403 Forbidden AccessDenied")
      )
    }
  )

  expect_error(
    .datom_validate_s3_store(
      access_key = "AKIA", secret_key = "secret",
      session_token = NULL, region = "us-east-1", bucket = "locked-bucket"
    ),
    "lack access"
  )
})

test_that(".datom_validate_s3_store() errors on 404 HeadBucket", {
  mockery::stub(
    .datom_validate_s3_store, "paws.storage::sts",
    function(...) {
      list(
        get_caller_identity = function() {
          list(Account = "123456789012", Arn = "arn:aws:iam::123456789012:user/test")
        }
      )
    }
  )

  mockery::stub(
    .datom_validate_s3_store, "paws.storage::s3",
    function(...) {
      list(
        head_bucket = function(Bucket) stop("404 NoSuchBucket")
      )
    }
  )

  expect_error(
    .datom_validate_s3_store(
      access_key = "AKIA", secret_key = "secret",
      session_token = NULL, region = "us-east-1", bucket = "nonexistent"
    ),
    "does not exist"
  )
})

test_that("datom_store_s3() with validate = TRUE calls validation", {
  # Mock the validation function to track it was called
  mockery::stub(
    datom_store_s3, ".datom_validate_s3_store",
    function(...) list(aws_account_id = "111111111111", aws_arn = "arn:aws:iam::111111111111:user/test")
  )

  store <- datom_store_s3(
    bucket = "my-bucket",
    access_key = "AKIAEXAMPLE1",
    secret_key = "secret",
    validate = TRUE
  )

  expect_true(store$validated)
  expect_equal(store$identity$aws_account_id, "111111111111")
})

test_that("datom_store_s3() with validate = FALSE skips validation", {
  # No mocking needed — if validation runs it would fail without real AWS
  store <- datom_store_s3(
    bucket = "my-bucket",
    access_key = "AKIAEXAMPLE1",
    secret_key = "secret",
    validate = FALSE
  )

  expect_false(store$validated)
  expect_null(store$identity)
})


# ==============================================================================
# datom_store: composite constructor (Chunk 2)
# ==============================================================================

# --- datom_store: structural validation ---------------------------------------

test_that("datom_store() rejects non-store governance", {
  comp <- make_component()
  expect_error(
    datom_store(governance = "not-a-store", data = comp, validate = FALSE),
    "governance.*must be a datom store component"
  )
})

test_that("datom_store() rejects non-store data", {
  comp <- make_component()
  expect_error(
    datom_store(governance = comp, data = list(bucket = "x"), validate = FALSE),
    "data.*must be a datom store component"
  )
})

test_that("datom_store() rejects invalid github_pat types", {
  comp <- make_component()
  for (bad in list(123, c("a", "b"), NA_character_, "")) {
    expect_error(
      datom_store(governance = comp, data = comp, github_pat = bad, validate = FALSE),
      "github_pat.*single non-empty string"
    )
  }
})

test_that("datom_store() rejects invalid remote_url types", {
  comp <- make_component()
  for (bad in list(123, c("a", "b"), NA_character_, "")) {
    expect_error(
      datom_store(governance = comp, data = comp, remote_url = bad, validate = FALSE),
      "remote_url.*single non-empty string"
    )
  }
})

test_that("datom_store() rejects invalid github_org types", {
  comp <- make_component()
  for (bad in list(123, c("a", "b"), NA_character_, "")) {
    expect_error(
      datom_store(governance = comp, data = comp, github_org = bad, validate = FALSE),
      "github_org.*single non-empty string"
    )
  }
})

# --- datom_store: role derivation ---------------------------------------------

test_that("datom_store() derives developer role when github_pat provided", {
  comp <- make_component()
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_test123", validate = FALSE
  )
  expect_equal(store$role, "developer")
})

test_that("datom_store() derives reader role when github_pat is NULL", {
  comp <- make_component()
  store <- datom_store(governance = comp, data = comp, validate = FALSE)
  expect_equal(store$role, "reader")
})

# --- datom_store: construction ------------------------------------------------

test_that("datom_store() creates valid developer store", {
  gov <- make_component(bucket = "gov-bucket", prefix = "gov/")
  dat <- make_component(bucket = "data-bucket", prefix = "data/")
  store <- datom_store(
    governance = gov, data = dat,
    github_pat = "ghp_abc123",
    remote_url = "https://github.com/org/repo.git",
    github_org = "my-org",
    validate = FALSE
  )

  expect_true(is_datom_store(store))
  expect_s3_class(store, "datom_store")
  expect_equal(store$governance$bucket, "gov-bucket")
  expect_equal(store$data$bucket, "data-bucket")
  expect_equal(store$role, "developer")
  expect_equal(store$github_pat, "ghp_abc123")
  expect_equal(store$remote_url, "https://github.com/org/repo.git")
  expect_equal(store$github_org, "my-org")
  expect_false(store$validated)
  expect_null(store$identity$github)
})

test_that("datom_store() creates valid reader store", {
  comp <- make_component()
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  expect_true(is_datom_store(store))
  expect_equal(store$role, "reader")
  expect_null(store$github_pat)
  expect_null(store$remote_url)
  expect_null(store$github_org)
})

test_that("datom_store() stores component identities", {
  gov <- make_component()
  dat <- make_component()
  store <- datom_store(governance = gov, data = dat, validate = FALSE)

  # Components had validate = FALSE so identity is NULL
  expect_null(store$identity$governance)
  expect_null(store$identity$data)
  expect_null(store$identity$github)
})

# --- datom_store: GitHub PAT validation ---------------------------------------

test_that("datom_store() validates PAT when validate = TRUE", {
  comp <- make_component()

  mockery::stub(
    datom_store, ".datom_validate_github_pat",
    list(login = "testuser", id = 12345)
  )

  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_real_token", validate = TRUE
  )

  expect_true(store$validated)
  expect_equal(store$identity$github$login, "testuser")
  expect_equal(store$identity$github$id, 12345)
})

test_that("datom_store() skips PAT validation when validate = FALSE", {
  comp <- make_component()
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_token", validate = FALSE
  )
  expect_false(store$validated)
  expect_null(store$identity$github)
})

test_that("datom_store() skips PAT validation when no github_pat", {
  comp <- make_component()
  store <- datom_store(governance = comp, data = comp, validate = TRUE)
  # validate = TRUE but no PAT, so no GitHub validation occurs
  expect_true(store$validated)
  expect_null(store$identity$github)
})

# --- .datom_validate_github_pat -----------------------------------------------

test_that(".datom_validate_github_pat() returns login and id on success", {
  mockery::stub(
    .datom_validate_github_pat, "httr2::req_perform",
    structure(list(body = ""), class = "httr2_response")
  )
  mockery::stub(
    .datom_validate_github_pat, "httr2::resp_body_json",
    list(login = "octocat", id = 1)
  )

  result <- .datom_validate_github_pat("ghp_valid")
  expect_equal(result$login, "octocat")
  expect_equal(result$id, 1)
})

test_that(".datom_validate_github_pat() errors on API failure", {
  mockery::stub(
    .datom_validate_github_pat, "httr2::req_perform",
    function(...) stop("HTTP 401")
  )

  expect_error(
    .datom_validate_github_pat("ghp_invalid"),
    "GitHub PAT validation failed"
  )
})

# --- .is_datom_store_component ------------------------------------------------

test_that(".is_datom_store_component() recognizes datom_store_s3", {
  comp <- make_component()
  expect_true(.is_datom_store_component(comp))
})

test_that(".is_datom_store_component() rejects non-components", {
  expect_false(.is_datom_store_component(list(a = 1)))
  expect_false(.is_datom_store_component("string"))
  expect_false(.is_datom_store_component(NULL))
})

# --- is_datom_store -----------------------------------------------------------

test_that("is_datom_store() recognizes datom_store objects", {
  comp <- make_component()
  store <- datom_store(governance = comp, data = comp, validate = FALSE)
  expect_true(is_datom_store(store))
})

test_that("is_datom_store() rejects non-store objects", {
  expect_false(is_datom_store(list()))
  expect_false(is_datom_store(make_component()))
  expect_false(is_datom_store(NULL))
})

# --- print.datom_store --------------------------------------------------------

test_that("print.datom_store() prints developer store without error", {
  comp <- make_component()
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_secret_token_12345",
    remote_url = "https://github.com/org/repo.git",
    github_org = "my-org",
    validate = FALSE
  )

  output <- capture.output(print(store), type = "message")
  full <- paste(output, collapse = "\n")

  expect_match(full, "datom store")
  expect_match(full, "developer")
  expect_match(full, "ghp_\\*+")
  expect_match(full, "org/repo")
  expect_match(full, "my-org")
  # PAT should be masked
  expect_no_match(full, "secret_token_12345")
})

test_that("print.datom_store() prints reader store without error", {
  comp <- make_component()
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  output <- capture.output(print(store), type = "message")
  full <- paste(output, collapse = "\n")

  expect_match(full, "datom store")
  expect_match(full, "reader")
  # No PAT or org lines
  expect_no_match(full, "GitHub PAT")
})
