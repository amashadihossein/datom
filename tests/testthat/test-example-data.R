test_that("datom_example_data returns expected row counts for each domain", {
  expect_equal(nrow(datom_example_data("dm")), 48L)
  expect_equal(nrow(datom_example_data("ex")), 48L)
  # LB: 48 subjects x 3 visits x 5 tests = 720
  expect_equal(nrow(datom_example_data("lb")), 720L)
  # AE varies with the seeded Poisson draw; lock the current value but allow
  # a tolerance band to keep the test useful if the simulator is ever re-seeded.
  ae <- datom_example_data("ae")
  expect_gte(nrow(ae), 60L)
  expect_lte(nrow(ae), 110L)
})

test_that("datom_example_data exposes expected SDTM columns", {
  expect_true(all(c("USUBJID", "AGE", "SEX", "RFSTDTC") %in% names(datom_example_data("dm"))))
  expect_true(all(c("USUBJID", "EXTRT", "EXSTDTC") %in% names(datom_example_data("ex"))))
  expect_true(all(c("USUBJID", "LBTESTCD", "LBORRES", "LBDTC") %in% names(datom_example_data("lb"))))
  expect_true(all(c("USUBJID", "AETERM", "AESEV", "AESTDTC") %in% names(datom_example_data("ae"))))
})

test_that("datom_example_data filters by cutoff_date for each domain", {
  cut <- "2026-03-28"
  dm_full <- datom_example_data("dm")
  dm_cut  <- datom_example_data("dm", cutoff_date = cut)
  expect_lt(nrow(dm_cut), nrow(dm_full))
  expect_true(all(as.Date(dm_cut$RFSTDTC) <= as.Date(cut)))

  ex_cut <- datom_example_data("ex", cutoff_date = cut)
  expect_true(all(as.Date(ex_cut$EXSTDTC) <= as.Date(cut)))

  lb_cut <- datom_example_data("lb", cutoff_date = cut)
  expect_true(all(as.Date(lb_cut$LBDTC) <= as.Date(cut)))

  ae_cut <- datom_example_data("ae", cutoff_date = cut)
  if (nrow(ae_cut) > 0L) {
    expect_true(all(as.Date(ae_cut$AESTDTC) <= as.Date(cut)))
  }
})

test_that("datom_example_data rejects unknown domains", {
  expect_error(datom_example_data("xx"), "should be one of")
})

test_that("datom_example_cutoffs returns six monthly cutoff dates", {
  cuts <- datom_example_cutoffs()
  expect_length(cuts, 6L)
  expect_named(cuts, paste0("month_", 1:6))
})
