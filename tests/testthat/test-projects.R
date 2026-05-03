# Tests for datom_projects() + .datom_gov_list_projects()

# --- helpers ----------------------------------------------------------------

# Build a minimal gov conn that uses fs:: for read_json via mocked binding.
mock_gov_conn <- function(root = "gov-bucket", prefix = "gov", backend = "s3") {
  structure(
    list(
      project_name = "gov",
      backend = backend,
      root = root,
      prefix = prefix,
      region = "us-east-1",
      client = NULL,
      path = NULL,
      role = "reader",
      endpoint = NULL
    ),
    class = "datom_conn"
  )
}

# Build a real gov clone on disk with N projects, each with a ref.json.
make_gov_clone <- function(projects = list()) {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  fs::dir_create(fs::path(tmp, ".git"))  # so .datom_gov_clone_exists() is TRUE
  fs::dir_create(fs::path(tmp, "projects"))
  for (nm in names(projects)) {
    pdir <- fs::path(tmp, "projects", nm)
    fs::dir_create(pdir)
    jsonlite::write_json(projects[[nm]], fs::path(pdir, "ref.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }
  tmp
}

ref_payload <- function(type = "s3", root = "data-bucket",
                        prefix = "p/", region = "us-east-1") {
  list(
    current  = list(type = type, root = root, prefix = prefix, region = region),
    previous = list()
  )
}

# --- input validation -------------------------------------------------------

test_that("datom_projects() rejects non-conn / non-store input", {
  expect_error(datom_projects("nope"), "datom_conn.*datom_store|datom_store.*datom_conn")
})

test_that("datom_projects() errors on conn without governance", {
  conn <- mock_datom_conn(list())  # no gov_root
  expect_error(datom_projects(conn), "no governance attached")
  # Hint references datom_attach_gov() per Chunk 7 uniform error.
  err <- tryCatch(datom_projects(conn), error = function(e) e)
  expect_match(conditionMessage(err), "datom_attach_gov")
})

# --- developer / clone path ------------------------------------------------

test_that("returns one row per project from local gov clone, sorted by name", {
  gov_path <- make_gov_clone(list(
    STUDY_002 = ref_payload(root = "study2-bucket"),
    STUDY_001 = ref_payload(root = "study1-bucket")
  ))

  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")
  conn$gov_local_path <- gov_path

  df <- datom_projects(conn)

  expect_s3_class(df, "data.frame")
  expect_equal(df$name, c("STUDY_001", "STUDY_002"))
  expect_equal(df$data_root, c("study1-bucket", "study2-bucket"))
  expect_equal(df$data_backend, c("s3", "s3"))
  expect_equal(df$data_prefix, c("p/", "p/"))
  expect_false(any(is.na(df$registered_at)))
})

test_that("returns empty data frame when projects/ is empty", {
  gov_path <- make_gov_clone(list())  # no projects
  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")
  conn$gov_local_path <- gov_path

  df <- datom_projects(conn)
  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), 0)
  expect_setequal(
    names(df),
    c("name", "data_backend", "data_root", "data_prefix", "registered_at")
  )
})

test_that("skips project directories that lack ref.json (warn + drop)", {
  gov_path <- make_gov_clone(list(GOOD = ref_payload()))
  fs::dir_create(fs::path(gov_path, "projects", "BROKEN"))  # no ref.json

  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")
  conn$gov_local_path <- gov_path

  df <- datom_projects(conn)
  expect_equal(df$name, "GOOD")
})

test_that("NA prefix is preserved when ref.json has no prefix", {
  gov_path <- make_gov_clone(list(
    NOPREFIX = ref_payload(prefix = NULL)
  ))
  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")
  conn$gov_local_path <- gov_path

  df <- datom_projects(conn)
  expect_true(is.na(df$data_prefix))
})

# --- reader / storage path -------------------------------------------------

test_that("reader path: uses storage list + storage read, registered_at is NA", {
  # Simulate two projects discoverable via storage list_objects.
  keys <- c(
    "gov/datom/projects/ALPHA/ref.json",
    "gov/datom/projects/ALPHA/dispatch.json",
    "gov/datom/projects/BETA/ref.json",
    "gov/datom/projects/BETA/migration_history.json"
  )
  refs <- list(
    ALPHA = ref_payload(type = "local", root = "/data/alpha"),
    BETA  = ref_payload(type = "s3",    root = "beta-bucket", prefix = NULL)
  )

  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) keys,
    .datom_storage_read_json = function(conn, key) {
      nm <- sub("^projects/([^/]+)/ref\\.json$", "\\1", key)
      refs[[nm]]
    }
  )

  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")
  # No gov_local_path -> storage path

  df <- datom_projects(conn)

  expect_equal(df$name, c("ALPHA", "BETA"))
  expect_equal(df$data_backend, c("local", "s3"))
  expect_equal(df$data_root, c("/data/alpha", "beta-bucket"))
  expect_true(all(is.na(df$registered_at)))
})

test_that("reader path: per-project read failure warns and skips", {
  keys <- c(
    "gov/datom/projects/OK/ref.json",
    "gov/datom/projects/BAD/ref.json"
  )
  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) keys,
    .datom_storage_read_json = function(conn, key) {
      if (grepl("/BAD/", key)) stop("network blip")
      ref_payload()
    }
  )

  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")

  df <- suppressWarnings(datom_projects(conn))
  expect_equal(df$name, "OK")
  expect_warning(datom_projects(conn), "BAD")
})

test_that("reader path: empty storage list yields empty data frame", {
  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) character(0)
  )
  conn <- mock_datom_conn(list(), gov_root = "gov-bucket", gov_prefix = "gov")

  df <- datom_projects(conn)
  expect_equal(nrow(df), 0)
})

# --- datom_store input -----------------------------------------------------

test_that("accepts a datom_store and routes through the storage path", {
  data_store <- datom_store_local(
    path = withr::local_tempdir(), prefix = "data/", validate = FALSE
  )
  gov_store <- datom_store_local(
    path = withr::local_tempdir(), prefix = "gov/", validate = FALSE
  )
  store <- structure(
    list(data = data_store, governance = gov_store),
    class = "datom_store"
  )

  keys <- c("gov/datom/projects/ZED/ref.json")
  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) keys,
    .datom_storage_read_json = function(conn, key) ref_payload(type = "local")
  )

  df <- datom_projects(store)
  expect_equal(df$name, "ZED")
  expect_equal(df$data_backend, "local")
  expect_true(is.na(df$registered_at))
})
