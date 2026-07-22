# Tests for the datom table contract: column classification + recourse map.
# Feature: datom-cv1

# --- .datom_column_kind() -----------------------------------------------------

test_that("unclassed atomics classify to their kind", {
  expect_identical(.datom_column_kind(1:3), "num")
  expect_identical(.datom_column_kind(c(1.5, 2.5)), "num")
  expect_identical(.datom_column_kind(c(TRUE, FALSE, NA)), "num")
  expect_identical(.datom_column_kind(c("a", "b")), "chr")
})

test_that("supported classed columns classify to their kind", {
  expect_identical(.datom_column_kind(factor(c("a", "b"))), "chr")
  expect_identical(.datom_column_kind(factor(c("a", "b"), ordered = TRUE)), "chr")
  expect_identical(.datom_column_kind(as.Date("2026-01-01")), "date")
  # integer-storage Date (e.g. data.table::IDate shape)
  expect_identical(.datom_column_kind(structure(0L, class = "Date")), "date")
  expect_identical(.datom_column_kind(as.POSIXct("2026-01-01", tz = "UTC")), "time")
  expect_identical(.datom_column_kind(as.difftime(1, units = "secs")), "drtn")
  # hms and data.table::ITime, faked by class string (same shape as the real pkgs)
  expect_identical(
    .datom_column_kind(structure(1, class = c("hms", "difftime"), units = "secs")),
    "drtn"
  )
  expect_identical(.datom_column_kind(structure(1L, class = "ITime")), "drtn")
  # bit64::integer64, faked by class string
  expect_identical(.datom_column_kind(structure(c(1, 2), class = "integer64")), "i64")
})

test_that("labelled columns are supported (strip to underlying kind)", {
  lab_dbl <- structure(c(1, 2), class = "haven_labelled", labels = c(a = 1))
  expect_identical(.datom_column_kind(lab_dbl), "num")
  lab_chr <- structure(c("a", "b"), class = c("labelled_spss", "labelled"),
                       labels = c(x = "a"))
  expect_identical(.datom_column_kind(lab_chr), "chr")
})

test_that("unsupported columns classify to NULL", {
  expect_null(.datom_column_kind(list(1, 2)))
  expect_null(.datom_column_kind(complex(real = 1, imaginary = 1)))
  expect_null(.datom_column_kind(as.raw(1:2)))
  expect_null(.datom_column_kind(as.POSIXlt("2026-01-01", tz = "UTC")))
  expect_null(.datom_column_kind(structure(1:2, class = "units")))
  expect_null(.datom_column_kind(structure(1:2, class = "myclass")))
})

# --- .datom_hash_recourse() ---------------------------------------------------

test_that("supported columns have no recourse", {
  expect_null(.datom_hash_recourse(1:3))
  expect_null(.datom_hash_recourse(c("a", "b")))
  expect_null(.datom_hash_recourse(factor("a")))
  expect_null(.datom_hash_recourse(as.Date("2026-01-01")))
  expect_null(.datom_hash_recourse(as.POSIXct("2026-01-01", tz = "UTC")))
  expect_null(.datom_hash_recourse(as.difftime(1, units = "secs")))
  # labelled is supported -> no recourse
  expect_null(.datom_hash_recourse(
    structure(c(1, 2), class = "haven_labelled", labels = c(a = 1))
  ))
})

test_that("POSIXlt returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(as.POSIXlt("2026-01-01", tz = "UTC")),
    "POSIXlt columns are not hashable. Convert to POSIXct with as.POSIXct() before writing."
  )
})

test_that("nested data-frame list column returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(list(data.frame(a = 1), data.frame(a = 2))),
    paste0(
      "Nested data-frame (list) columns are not hashable. Model the inner ",
      "table as its own datom table joined by a key with datom_parent() ",
      "lineage, or flatten it with tidyr::unnest(), before writing."
    )
  )
})

test_that("generic list / blob column returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(list(1, "a")),
    paste0(
      "List and blob columns are not hashable. Flatten to one value per row ",
      "with tidyr::unnest(), or serialize each element to character (for ",
      "example with jsonlite::toJSON() per element), before writing."
    )
  )
})

test_that("units column returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(structure(c(1, 2), class = "units")),
    paste0(
      "units columns are not hashable. Drop the unit with units::drop_units() ",
      "and record the unit in the column name or a companion column ",
      "(audit-friendly), before writing."
    )
  )
})

test_that("sfc geometry returns its recourse even though it is a list", {
  # A real sfc object is a list of geometries -- it must not be shadowed by the
  # generic list/blob rule.
  list_based_sfc <- structure(list(c(0, 0), c(1, 1)), class = c("sfc_POINT", "sfc"))
  expect_true(is.list(list_based_sfc))
  expect_identical(
    .datom_hash_recourse(list_based_sfc),
    "sf geometry (sfc) columns are not hashable. Convert to WKT text with sf::st_as_text() before writing."
  )
})

test_that("zoo::yearmon / yearqtr / chron return their canonical recourse", {
  expected <- paste0(
    "zoo::yearmon / yearqtr and chron columns are not hashable. Convert to ",
    "Date/POSIXct or ISO-8601 text before writing."
  )
  expect_identical(.datom_hash_recourse(structure(2020.5, class = "yearmon")), expected)
  expect_identical(.datom_hash_recourse(structure(2020.25, class = "yearqtr")), expected)
  expect_identical(.datom_hash_recourse(structure(1, class = "chron")), expected)
})

test_that("complex column returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(complex(real = 1, imaginary = 1)),
    paste0(
      "Complex columns are not hashable. Split into separate real and ",
      "imaginary numeric columns, or convert to character, before writing."
    )
  )
})

test_that("raw column returns its canonical recourse", {
  expect_identical(
    .datom_hash_recourse(as.raw(1:2)),
    "Raw columns are not hashable. Encode the bytes as character (for example base64) before writing."
  )
})

test_that("any other classed column returns the fallback recourse", {
  expect_identical(
    .datom_hash_recourse(structure(1:3, class = "myclass")),
    paste0(
      "Columns of this class are not hashable. Convert to a supported type ",
      "(logical, integer, double, character, factor, Date, POSIXct, ",
      "difftime/hms, or bit64::integer64) before writing."
    )
  )
})

test_that("empty list falls to the generic list rule, not nested-data-frame", {
  expect_match(.datom_hash_recourse(list()), "^List and blob")
})

# --- .datom_class_label() -----------------------------------------------------

test_that("class label is collapsed class for classed columns, typeof otherwise", {
  expect_identical(.datom_class_label(1:3), "integer")
  expect_identical(.datom_class_label(c(1.5)), "double")
  expect_identical(.datom_class_label(list(1)), "list")
  expect_identical(.datom_class_label(complex(real = 1, imaginary = 1)), "complex")
  expect_identical(.datom_class_label(factor("a")), "factor")
  expect_identical(.datom_class_label(factor("a", ordered = TRUE)), "ordered/factor")
  expect_identical(
    .datom_class_label(as.POSIXlt("2026-01-01", tz = "UTC")),
    "POSIXlt/POSIXt"
  )
})
