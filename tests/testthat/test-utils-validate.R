# Tests for name validation utilities
# Phase 1, Chunk 3

# --- .tbit_validate_name() ----------------------------------------------------

# Valid names
test_that("accepts simple lowercase name", {
  expect_invisible(.tbit_validate_name("customers"))
  expect_equal(.tbit_validate_name("customers"), "customers")
})

test_that("accepts uppercase name", {
  expect_equal(.tbit_validate_name("ADSL"), "ADSL")
})

test_that("accepts name with underscores", {
  expect_equal(.tbit_validate_name("lab_results"), "lab_results")
})

test_that("accepts name with hyphens", {
  expect_equal(.tbit_validate_name("my-table"), "my-table")
})

test_that("accepts name with numbers", {
  expect_equal(.tbit_validate_name("table2"), "table2")
})

test_that("accepts mixed case with numbers and underscores", {
  expect_equal(.tbit_validate_name("ADLB_v2_final"), "ADLB_v2_final")
})

test_that("accepts single letter name", {
  expect_equal(.tbit_validate_name("x"), "x")
})

test_that("accepts name with spaces", {
  expect_equal(.tbit_validate_name("my table"), "my table")
})

test_that("accepts name with parentheses", {
  expect_equal(.tbit_validate_name("ADSL (v2)"), "ADSL (v2)")
})

test_that("accepts name with spaces underscores and hyphens combined", {
  expect_equal(.tbit_validate_name("Lab Results (final-v2)"), "Lab Results (final-v2)")
})

# Invalid: type/empty
test_that("rejects non-character input", {
  expect_error(.tbit_validate_name(123), "single non-NA character")
  expect_error(.tbit_validate_name(NULL), "single non-NA character")
  expect_error(.tbit_validate_name(TRUE), "single non-NA character")
})

test_that("rejects vector of names", {
  expect_error(.tbit_validate_name(c("a", "b")), "single non-NA character")
})

test_that("rejects NA", {
  expect_error(.tbit_validate_name(NA_character_), "single non-NA character")
})

test_that("rejects empty string", {
  expect_error(.tbit_validate_name(""), "must not be empty")
})

# Invalid: pattern
test_that("rejects name starting with number", {
  expect_error(.tbit_validate_name("123abc"), "start with a letter")
})

test_that("rejects name starting with underscore", {
  expect_error(.tbit_validate_name("_hidden"), "start with a letter")
})

test_that("rejects name with slashes", {
  expect_error(.tbit_validate_name("customers/orders"), "letters, numbers, underscores")
})

test_that("rejects name with dots", {
  expect_error(.tbit_validate_name("my.table"), "letters, numbers, underscores")
})

test_that("rejects name with special characters", {
  expect_error(.tbit_validate_name("table@1"), "letters, numbers, underscores")
  expect_error(.tbit_validate_name("table!"), "letters, numbers, underscores")
  expect_error(.tbit_validate_name("table#1"), "letters, numbers, underscores")
})

# Invalid: reserved names
test_that("rejects .metadata", {
  expect_error(.tbit_validate_name(".metadata"), "start with a letter")
})

test_that("rejects input_files", {
  expect_error(.tbit_validate_name("input_files"), "reserved name")
})

test_that("rejects tbit", {
  expect_error(.tbit_validate_name("tbit"), "reserved name")
})

test_that("rejects reserved names case-insensitively", {
  expect_error(.tbit_validate_name("INPUT_FILES"), "reserved name")
  expect_error(.tbit_validate_name("Tbit"), "reserved name")
})

# Invalid: length
test_that("rejects name over 128 characters", {
  long_name <- paste0("a", paste(rep("b", 128), collapse = ""))
  expect_error(.tbit_validate_name(long_name), "128 characters")
})

test_that("accepts name at exactly 128 characters", {
  name_128 <- paste0("a", paste(rep("b", 127), collapse = ""))
  expect_equal(nchar(name_128), 128)
  expect_equal(.tbit_validate_name(name_128), name_128)
})


# =============================================================================
# .tbit_derive_cred_names()
# =============================================================================

test_that("derives standard cred names from simple project_name", {
  result <- .tbit_derive_cred_names("clinical_data")
  expect_equal(result$access_key_env, "TBIT_CLINICAL_DATA_ACCESS_KEY_ID")
  expect_equal(result$secret_key_env, "TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY")
})

test_that("converts hyphens to underscores", {
  result <- .tbit_derive_cred_names("my-project")
  expect_equal(result$access_key_env, "TBIT_MY_PROJECT_ACCESS_KEY_ID")
  expect_equal(result$secret_key_env, "TBIT_MY_PROJECT_SECRET_ACCESS_KEY")
})

test_that("converts spaces to underscores", {
  result <- .tbit_derive_cred_names("my project")
  expect_equal(result$access_key_env, "TBIT_MY_PROJECT_ACCESS_KEY_ID")
})

test_that("uppercases lowercase input", {
  result <- .tbit_derive_cred_names("alpha")
  expect_equal(result$access_key_env, "TBIT_ALPHA_ACCESS_KEY_ID")
})

test_that("handles already-uppercase input", {
  result <- .tbit_derive_cred_names("ALPHA")
  expect_equal(result$access_key_env, "TBIT_ALPHA_ACCESS_KEY_ID")
})

test_that("collapses consecutive hyphens/spaces", {
  result <- .tbit_derive_cred_names("my--project  name")
  expect_equal(result$access_key_env, "TBIT_MY_PROJECT_NAME_ACCESS_KEY_ID")
})

test_that("returns a list with correct names", {
  result <- .tbit_derive_cred_names("x")
  expect_type(result, "list")
  expect_named(result, c("access_key_env", "secret_key_env"))
})

test_that("aborts on non-string input", {
  expect_error(.tbit_derive_cred_names(123), "single non-empty string")
  expect_error(.tbit_derive_cred_names(NULL), "single non-empty string")
  expect_error(.tbit_derive_cred_names(c("a", "b")), "single non-empty string")
})

test_that("aborts on empty string", {
  expect_error(.tbit_derive_cred_names(""), "single non-empty string")
})

test_that("aborts on NA", {
  expect_error(.tbit_derive_cred_names(NA_character_), "single non-empty string")
})


# =============================================================================
# .tbit_check_credentials()
# =============================================================================

test_that("succeeds when all reader credentials are set", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  result <- .tbit_check_credentials("myproj", role = "reader")
  expect_type(result, "list")
  expect_equal(result$access_key_env, "TBIT_MYPROJ_ACCESS_KEY_ID")
  expect_equal(result$secret_key_env, "TBIT_MYPROJ_SECRET_ACCESS_KEY")
})

test_that("returns invisibly on success", {
  withr::local_envvar(
    TBIT_X_ACCESS_KEY_ID = "k",
    TBIT_X_SECRET_ACCESS_KEY = "s"
  )

  expect_invisible(.tbit_check_credentials("x", role = "reader"))
})

test_that("succeeds when all developer credentials are set", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  result <- .tbit_check_credentials("myproj", role = "developer")
  expect_equal(result$access_key_env, "TBIT_MYPROJ_ACCESS_KEY_ID")
})

test_that("aborts when access key is missing (reader)", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  expect_error(.tbit_check_credentials("myproj", role = "reader"), "ACCESS_KEY_ID")
})

test_that("aborts when secret key is missing (reader)", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA
  )

  expect_error(.tbit_check_credentials("myproj", role = "reader"), "SECRET_ACCESS_KEY")
})

test_that("aborts when both S3 credentials are missing", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA
  )

  expect_error(.tbit_check_credentials("myproj", role = "reader"), "ACCESS_KEY_ID")
})

test_that("reader does not check GITHUB_PAT", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = NA
  )

  # Should succeed — reader doesn't need GITHUB_PAT
  expect_no_error(.tbit_check_credentials("myproj", role = "reader"))
})

test_that("developer aborts when GITHUB_PAT is missing", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = NA
  )

  expect_error(.tbit_check_credentials("myproj", role = "developer"), "GITHUB_PAT")
})

test_that("developer aborts listing all missing vars", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA,
    GITHUB_PAT = NA
  )

  expect_error(.tbit_check_credentials("myproj", role = "developer"), "ACCESS_KEY_ID")
  expect_error(.tbit_check_credentials("myproj", role = "developer"), "GITHUB_PAT")
})

test_that("credential check uses derived names from project_name", {
  withr::local_envvar(
    TBIT_CLINICAL_DATA_ACCESS_KEY_ID = "k",
    TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY = "s"
  )

  result <- .tbit_check_credentials("clinical_data", role = "reader")
  expect_equal(result$access_key_env, "TBIT_CLINICAL_DATA_ACCESS_KEY_ID")
})

test_that("defaults to reader role", {
  withr::local_envvar(
    TBIT_X_ACCESS_KEY_ID = "k",
    TBIT_X_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = NA
  )

  # Should succeed because default is reader (no GITHUB_PAT needed)
  expect_no_error(.tbit_check_credentials("x"))
})
