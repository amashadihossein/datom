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


# --- datom_check_hashable() ---------------------------------------------------

test_that("datom_check_hashable rejects non-data-frame and zero-column input", {
  expect_error(datom_check_hashable("not a frame"), "data frame")
  expect_error(datom_check_hashable(list(a = 1)), "data frame")
  expect_error(datom_check_hashable(data.frame()), "at least one column")
})

test_that("datom_check_hashable reports every column ok for a clean table", {
  clean <- data.frame(
    id = 1:3,
    score = c(1.5, 2.5, 3.5),
    flag = c(TRUE, FALSE, TRUE),
    label = c("a", "b", "c"),
    grp = factor(c("x", "y", "x")),
    day = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03")),
    stringsAsFactors = FALSE
  )

  report <- datom_check_hashable(clean)

  expect_s3_class(report, "data.frame")
  expect_identical(names(report), c("column", "class", "status", "recourse"))
  expect_identical(report$column, names(clean))
  expect_true(all(report$status == "ok"))
  expect_true(all(is.na(report$recourse)))
})

test_that("datom_check_hashable returns its report invisibly", {
  expect_invisible(datom_check_hashable(data.frame(id = 1L)))
})

test_that("datom_check_hashable reports the class label per column", {
  df <- data.frame(id = 1:2, stringsAsFactors = FALSE)
  df$day <- as.Date(c("2026-01-01", "2026-01-02"))
  df$notes <- list(1, 2)

  report <- datom_check_hashable(df)

  expect_identical(report$class[report$column == "id"], "integer")
  expect_identical(report$class[report$column == "day"], "Date")
  expect_identical(report$class[report$column == "notes"], "list")
})

test_that("datom_check_hashable prints a success summary when clean and offenders otherwise", {
  withr::local_options(cli.width = 1000)

  expect_message(datom_check_hashable(data.frame(id = 1L)), "hashable")

  messy <- data.frame(id = 1L)
  messy$z <- complex(real = 1, imaginary = 1)
  expect_message(datom_check_hashable(messy), "not hashable")
})


# --- Property 15 --------------------------------------------------------------
# Feature: datom-cv1, Property 15: Table-contract recourse is single-sourced and
# complete. For every row of the recourse map, datom_check_hashable() flags the
# column AND .datom_canonical_hash() aborts with the identical canonical string;
# a multi-offender table aborts exactly once naming every offender; and applying
# the stated recourse makes the fixture hashable.

# One fixture per recourse-map row, paired with the column the stated recourse
# produces. `offender` must be flagged; `fixed` must be hashable.
recourse_fixtures <- list(
  posixlt = list(
    offender = as.POSIXlt(c("2026-01-01", "2026-06-15"), tz = "UTC"),
    # recourse: as.POSIXct()
    fixed = as.POSIXct(c("2026-01-01", "2026-06-15"), tz = "UTC")
  ),
  nested_df = list(
    offender = list(data.frame(a = 1), data.frame(a = 2)),
    # recourse: model the inner table separately / unnest -> a flat column
    fixed = c(1, 2)
  ),
  list_blob = list(
    offender = list(c("a", "b"), "c"),
    # recourse: serialize each element to character
    fixed = c("a,b", "c")
  ),
  units = list(
    offender = structure(c(1, 2), class = "units", units = "m"),
    # recourse: units::drop_units() -> bare numeric
    fixed = c(1, 2)
  ),
  sfc = list(
    offender = structure(list("g1", "g2"), class = c("sfc_POINT", "sfc")),
    # recourse: sf::st_as_text() -> WKT character
    fixed = c("POINT (0 0)", "POINT (1 1)")
  ),
  yearmon = list(
    offender = structure(c(2026.0, 2026.083), class = "yearmon"),
    # recourse: convert to Date
    fixed = as.Date(c("2026-01-01", "2026-02-01"))
  ),
  complex = list(
    offender = c(1 + 2i, 3 + 4i),
    # recourse: split into real/imaginary numerics
    fixed = c(1, 3)
  ),
  raw = list(
    offender = as.raw(c(1, 2)),
    # recourse: encode the bytes as character
    fixed = c("01", "02")
  ),
  other_classed = list(
    offender = structure(c(1, 2), class = "someExoticClass"),
    # recourse: convert to a supported type
    fixed = c(1, 2)
  )
)

test_that("Feature: datom-cv1, Property 15: checker and hash abort share one recourse string", {
  withr::local_options(cli.width = 1000)

  for (nm in names(recourse_fixtures)) {
    offender <- recourse_fixtures[[nm]]$offender

    df <- data.frame(id = 1:2)
    df$bad <- offender

    expected <- .datom_hash_recourse(offender)
    expect_false(is.null(expected), info = nm)

    # (a) the checker flags the column and carries the canonical string verbatim
    report <- datom_check_hashable(df)
    expect_identical(report$status[report$column == "bad"], "unsupported", info = nm)
    expect_identical(report$recourse[report$column == "bad"], expected, info = nm)
    # the clean sibling column is unaffected
    expect_identical(report$status[report$column == "id"], "ok", info = nm)

    # (b) the hash aborts with the identical string
    err <- tryCatch(.datom_canonical_hash(df), error = function(e) e)
    expect_s3_class(err, "error")
    expect_true(
      grepl(expected, conditionMessage(err), fixed = TRUE),
      info = paste0(nm, ": abort message must carry the canonical recourse verbatim")
    )

    # (c) applying the stated recourse makes the fixture hashable
    fixed_df <- data.frame(id = 1:2)
    fixed_df$bad <- recourse_fixtures[[nm]]$fixed
    expect_null(.datom_hash_recourse(recourse_fixtures[[nm]]$fixed), info = nm)
    expect_identical(
      datom_check_hashable(fixed_df)$status,
      c("ok", "ok"),
      info = nm
    )
    expect_match(.datom_canonical_hash(fixed_df)$data_sha, "^[0-9a-f]{64}$")
  }
})

test_that("Feature: datom-cv1, Property 15: a multi-offender table aborts once naming all offenders", {
  withr::local_options(cli.width = 1000)

  df <- data.frame(id = 1:2)
  df$blob <- list(1, 2)
  df$z <- c(1 + 2i, 3 + 4i)
  df$bytes <- as.raw(c(1, 2))

  err <- tryCatch(.datom_canonical_hash(df), error = function(e) e)
  expect_s3_class(err, "error")
  msg <- conditionMessage(err)

  # one abort, naming all three offenders and none of the clean columns
  expect_match(msg, "3 columns are not hashable")
  for (col in c("blob", "z", "bytes")) {
    expect_true(grepl(col, msg, fixed = TRUE), info = col)
    expect_true(
      grepl(.datom_hash_recourse(df[[col]]), msg, fixed = TRUE),
      info = col
    )
  }

  # the checker agrees on which columns are at fault
  report <- datom_check_hashable(df)
  expect_identical(
    report$column[report$status == "unsupported"],
    c("blob", "z", "bytes")
  )
})

test_that("Feature: datom-cv1, Property 15: a refused table leaves no git, storage, or manifest state", {
  withr::with_tempdir({
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Writer", user.email = "w@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "init")
    head_before <- as.character(git2r::revparse_single(repo, "HEAD")$sha)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    uploads <- 0L
    local_mocked_bindings(
      .datom_storage_upload = function(conn, lp, sk) {
        uploads <<- uploads + 1L
        invisible(TRUE)
      },
      .datom_storage_write_json = function(conn, sk, d) invisible(TRUE),
      .datom_git_push = function(path, pat = NULL) invisible(TRUE)
    )

    bad <- data.frame(id = 1:2)
    bad$blob <- list(1, 2)

    expect_error(datom_write(conn, data = bad, name = "t"), "not hashable")

    # no parquet upload, no table directory, no metadata, no manifest, no commit
    expect_equal(uploads, 0L)
    expect_false(fs::dir_exists("t"))
    expect_false(fs::file_exists(fs::path("t", "metadata.json")))
    expect_false(fs::file_exists(fs::path(".datom", "manifest.json")))
    expect_identical(
      as.character(git2r::revparse_single(repo, "HEAD")$sha),
      head_before
    )
  })
})
