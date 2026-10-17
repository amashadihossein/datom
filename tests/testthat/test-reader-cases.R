# Shared reader cases: small datom stores written by R datom, each saved with
# the result any reader must produce (fixtures/reader-cases/README.md). The
# Python reader runs the same cases, so R and Python are held to one record.
#
# Every future R datom must still read every committed case: a case is never
# regenerated, so a failure here means R's read behaviour changed, not that the
# case is stale.

rc_cases_dir <- test_path("fixtures", "reader-cases")
rc_case_dirs <- sort(list.dirs(rc_cases_dir, recursive = FALSE))

test_that("the reader cases are present", {
  # Guards against a build that silently drops the fixtures, which would turn
  # every case below into no test at all.
  expect_gte(length(rc_case_dirs), 28L)
  purrr::walk(rc_case_dirs, function(d) {
    expect_true(file.exists(file.path(d, "case.json")), label = basename(d))
    expect_true(file.exists(file.path(d, "storage.zip")), label = basename(d))
  })
})

purrr::walk(rc_case_dirs, function(case_dir) {
  test_that(paste("reader case:", basename(case_dir)), {
    case <- jsonlite::read_json(file.path(case_dir, "case.json"),
                                simplifyVector = FALSE)
    storage <- rc_unpack_storage(case_dir, withr::local_tempdir())
    got <- rc_observe(storage, case$call)
    want <- case$expect

    if (isTRUE(want$ok)) {
      expect_identical(rc_as_json(got), rc_as_json(want))
      return(invisible())
    }

    # A refusal must be the refusal the case names, carried by its own class.
    expect_false(isTRUE(got$ok), label = "R datom refused")
    expect_identical(got$r_class, rc_error_class(want$error, case$call$op))
  })
})
