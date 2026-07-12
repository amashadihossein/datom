# Tests for datom_lineage_union() -- pure helper, no network/storage needed.

sl_entry <- function(project, table, version_sha) {
  list(project = project, table = table, version_sha = version_sha)
}

test_that("dedups across multiple lists by composite key", {
  sl1 <- list(sl_entry("p", "t", "a"))
  sl2 <- list(sl_entry("p", "t", "a"), sl_entry("q", "u", "b"))

  out <- datom_lineage_union(list(sl1, sl2))

  keys <- vapply(out, function(e) {
    paste(e$project, e$table, e$version_sha, sep = "\t")
  }, character(1))

  expect_length(out, 2L)
  expect_setequal(keys, c("p\tt\ta", "q\tu\tb"))
})

test_that("same project+table but different version_sha are distinct", {
  sl1 <- list(sl_entry("p", "t", "a"))
  sl2 <- list(sl_entry("p", "t", "b"))

  out <- datom_lineage_union(list(sl1, sl2))

  expect_length(out, 2L)
})

test_that("empty input returns an empty list", {
  expect_identical(datom_lineage_union(list()), list())
})

test_that("only-empty lineage lists return an empty list", {
  expect_identical(datom_lineage_union(list(list(), list())), list())
})

test_that("NULL members are tolerated", {
  sl1 <- list(sl_entry("p", "t", "a"))

  out <- datom_lineage_union(list(NULL, sl1, NULL))

  expect_length(out, 1L)
  expect_identical(out[[1]], sl_entry("p", "t", "a"))
})

test_that("only-NULL members return an empty list", {
  expect_identical(datom_lineage_union(list(NULL, NULL)), list())
})

test_that("retained entry fields are preserved unchanged", {
  entry <- sl_entry("study001", "dm", "d_dm_aaa")

  out <- datom_lineage_union(list(list(entry)))

  expect_length(out, 1L)
  expect_identical(out[[1]], entry)
  expect_identical(names(out[[1]]), c("project", "table", "version_sha"))
})

test_that("a single already-unique list returns an equivalent union", {
  sl <- list(sl_entry("p", "t", "a"), sl_entry("q", "u", "b"))

  out <- datom_lineage_union(list(sl))

  expect_length(out, 2L)
  expect_identical(out, sl)
})
