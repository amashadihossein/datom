# Tests for governance.json primitives (R/governance_json.R)
# Phase 21, Chunk 1

# --- helper -------------------------------------------------------------------

make_gov_store_s3 <- function() {
  datom_store_s3(
    bucket     = "gov-bucket",
    prefix     = "gov-prefix",
    region     = "us-east-1",
    access_key = "FAKE",
    secret_key = "FAKE",
    validate   = FALSE
  )
}

make_gov_store_local <- function(path = withr::local_tempdir()) {
  datom_store_local(
    path       = as.character(path),
    prefix     = "gov-prefix"
  )
}

# --- .datom_create_governance_json() ------------------------------------------

test_that("creates expected schema for s3 gov store", {
  result <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3()
  )

  expect_equal(result$gov_repo_url, "https://github.com/acme/datom-gov.git")
  expect_equal(result$gov_storage$type,   "s3")
  expect_equal(result$gov_storage$root,   "gov-bucket")
  expect_equal(result$gov_storage$prefix, "gov-prefix")
  expect_equal(result$gov_storage$region, "us-east-1")
  expect_true(is.character(result$attached_at) && nzchar(result$attached_at))
})

test_that("creates expected schema for local gov store", {
  tmp <- withr::local_tempdir()
  result <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_local(tmp)
  )

  expect_equal(result$gov_storage$type, "local")
  expect_null(result$gov_storage$region)  # local stores omit region
  expect_equal(result$gov_storage$root, as.character(fs::path_norm(tmp)))
})

test_that("respects caller-supplied attached_at", {
  ts <- "2026-01-01T00:00:00Z"
  result <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3(),
    attached_at  = ts
  )
  expect_equal(result$attached_at, ts)
})

test_that("aborts when gov_repo_url is empty", {
  expect_error(
    .datom_create_governance_json(
      gov_repo_url = "",
      gov_store    = make_gov_store_s3()
    ),
    "gov_repo_url"
  )
})

test_that("content contains no secret field names", {
  result <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3()
  )
  all_names <- c(names(result), names(result$gov_storage))
  secret_pattern <- "pat|token|secret|access_key|password|session_token"
  expect_false(any(grepl(secret_pattern, all_names, ignore.case = TRUE)))
})


# --- local round-trip ---------------------------------------------------------

test_that("write_local + read_local round-trips correctly", {
  tmp <- withr::local_tempdir()
  content <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3(),
    attached_at  = "2026-05-23T12:00:00Z"
  )

  .datom_write_governance_json_local(tmp, content)

  result <- .datom_read_governance_json_local(tmp)
  expect_equal(result$gov_repo_url, content$gov_repo_url)
  expect_equal(result$gov_storage$type,   content$gov_storage$type)
  expect_equal(result$gov_storage$root,   content$gov_storage$root)
  expect_equal(result$gov_storage$prefix, content$gov_storage$prefix)
  expect_equal(result$gov_storage$region, content$gov_storage$region)
  expect_equal(result$attached_at,        content$attached_at)
})

test_that("read_local returns NULL when file is absent", {
  tmp <- withr::local_tempdir()
  expect_null(.datom_read_governance_json_local(tmp))
})

test_that("read_local aborts on malformed JSON", {
  tmp <- withr::local_tempdir()
  fs::dir_create(fs::path(tmp, ".datom"))
  writeLines("{not valid json", fs::path(tmp, ".datom", "governance.json"))

  expect_error(.datom_read_governance_json_local(tmp), class = "rlang_error")
})

test_that("read_local aborts when gov_repo_url missing", {
  tmp <- withr::local_tempdir()
  fs::dir_create(fs::path(tmp, ".datom"))
  jsonlite::write_json(
    list(gov_storage = list(type = "s3", root = "b")),
    fs::path(tmp, ".datom", "governance.json"),
    auto_unbox = TRUE
  )

  expect_error(.datom_read_governance_json_local(tmp), "gov_repo_url")
})

test_that("read_local aborts when gov_storage$type is unsupported", {
  tmp <- withr::local_tempdir()
  fs::dir_create(fs::path(tmp, ".datom"))
  jsonlite::write_json(
    list(
      gov_repo_url = "https://github.com/acme/gov.git",
      gov_storage  = list(type = "gcs", root = "b")
    ),
    fs::path(tmp, ".datom", "governance.json"),
    auto_unbox = TRUE
  )

  expect_error(.datom_read_governance_json_local(tmp), "gov_storage")
})

test_that("local backend omits region from file", {
  tmp <- withr::local_tempdir()
  store_tmp <- withr::local_tempdir()
  content <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_local(store_tmp)
  )
  .datom_write_governance_json_local(tmp, content)

  raw <- jsonlite::read_json(fs::path(tmp, ".datom", "governance.json"),
                              simplifyVector = FALSE)
  expect_null(raw$gov_storage$region)
})


# --- storage round-trip (local backend) ---------------------------------------

test_that("storage_write + storage_read round-trips via local backend", {
  store_dir <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = as.character(store_dir),
         prefix = "proj", client = NULL),
    class = "datom_conn"
  )

  content <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3(),
    attached_at  = "2026-05-23T12:00:00Z"
  )

  .datom_storage_write_governance_json(conn, content)
  result <- .datom_storage_read_governance_json(conn)

  expect_equal(result$gov_repo_url, content$gov_repo_url)
  expect_equal(result$gov_storage$type,   content$gov_storage$type)
  expect_equal(result$gov_storage$root,   content$gov_storage$root)
  expect_equal(result$attached_at,        content$attached_at)
})

test_that("storage_read returns NULL when key is absent", {
  store_dir <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = as.character(store_dir),
         prefix = "proj", client = NULL),
    class = "datom_conn"
  )

  expect_null(.datom_storage_read_governance_json(conn))
})

test_that("sync helper restores storage mirror from local git copy", {
  store_dir <- withr::local_tempdir()
  clone_dir <- withr::local_tempdir()

  conn <- structure(
    list(backend = "local", root = as.character(store_dir),
         prefix = "proj", client = NULL,
         path   = as.character(clone_dir)),
    class = "datom_conn"
  )

  content <- .datom_create_governance_json(
    gov_repo_url = "https://github.com/acme/datom-gov.git",
    gov_store    = make_gov_store_s3(),
    attached_at  = "2026-05-23T12:00:00Z"
  )
  .datom_write_governance_json_local(clone_dir, content)

  # Mutate the storage mirror
  mirror_path <- fs::path(store_dir, "proj", "datom", ".metadata", "governance.json")
  fs::dir_create(fs::path_dir(mirror_path))
  jsonlite::write_json(list(gov_repo_url = "STALE"), mirror_path, auto_unbox = TRUE)

  # Sync restores from git
  .datom_sync_governance_json(conn)

  restored <- .datom_storage_read_governance_json(conn)
  expect_equal(restored$gov_repo_url, content$gov_repo_url)
})

test_that("sync helper aborts when no local git copy exists", {
  clone_dir <- withr::local_tempdir()
  store_dir <- withr::local_tempdir()

  conn <- structure(
    list(backend = "local", root = as.character(store_dir),
         prefix = "proj", client = NULL,
         path   = as.character(clone_dir)),
    class = "datom_conn"
  )

  expect_error(.datom_sync_governance_json(conn), "governance.json")
})
