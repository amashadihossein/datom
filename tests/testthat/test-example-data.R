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
  # VS: 48 subjects x 3 visits x 3 tests = 432
  expect_equal(nrow(datom_example_data("vs")), 432L)
})

test_that("the values of the four original example tables never change", {
  # Every recorded vignette output is computed from these tables, so a change
  # to any value (e.g. a new domain's draws inserted before an old one in the
  # simulator's single random stream) would silently invalidate them. The
  # fingerprint is over the parsed values, not the file bytes, so it does not
  # depend on line endings or on how the CSV was checked out.
  fingerprint <- function(d) {
    cols <- vapply(d, function(col) paste(as.character(col), collapse = "\x1f"),
                   character(1))
    digest::digest(paste(cols, collapse = "\x1e"), algo = "sha256", serialize = FALSE)
  }
  expected <- c(
    dm = "d3f134315eb8268a8ab324713ed9b7e8c27d0fe3c48b797aee1051e357b98bc7",
    ex = "e30be934b221b4b38070c188d09d2a8608a1e25d9d0cba30d54dfdd4b397859e",
    lb = "6b296998b6a3d357aca7d1673a4d196c3362f04f905dc55fb3226c99dfaae041",
    ae = "a7b862814790ceebd7da5770ad65ce4fb03516d6dadc427a7a25fa6a804c60eb"
  )
  purrr::iwalk(expected, function(sha, domain) {
    expect_identical(fingerprint(datom_example_data(domain)), sha, label = domain)
  })
  expect_equal(nrow(datom_example_data("ae")), 84L)
})

test_that("datom_example_data vs is taken at the lab visits, on the lab dates", {
  vs <- datom_example_data("vs")
  lb <- datom_example_data("lb")
  expect_setequal(unique(vs$VSTESTCD), c("SYSBP", "DIABP", "PULSE"))
  expect_setequal(unique(vs$USUBJID), unique(datom_example_data("dm")$USUBJID))
  visit_key <- function(d, date_col) unique(paste(d$USUBJID, d$VISITNUM, d[[date_col]]))
  expect_setequal(visit_key(vs, "VSDTC"), visit_key(lb, "LBDTC"))
})

test_that("datom_example_data exposes expected SDTM columns", {
  expect_true(all(c("USUBJID", "AGE", "SEX", "RFSTDTC") %in% names(datom_example_data("dm"))))
  expect_true(all(c("USUBJID", "EXTRT", "EXSTDTC") %in% names(datom_example_data("ex"))))
  expect_true(all(c("USUBJID", "LBTESTCD", "LBORRES", "LBDTC") %in% names(datom_example_data("lb"))))
  expect_true(all(c("USUBJID", "AETERM", "AESEV", "AESTDTC") %in% names(datom_example_data("ae"))))
  expect_true(all(c("USUBJID", "VISITNUM", "VSTESTCD", "VSORRES", "VSORRESU", "VSDTC") %in%
                    names(datom_example_data("vs"))))
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

  vs_full <- datom_example_data("vs")
  vs_cut  <- datom_example_data("vs", cutoff_date = cut)
  expect_gt(nrow(vs_cut), 0L)
  expect_lt(nrow(vs_cut), nrow(vs_full))
  expect_true(all(as.Date(vs_cut$VSDTC) <= as.Date(cut)))
})

test_that("datom_example_data rejects unknown domains", {
  expect_error(datom_example_data("xx"), "should be one of")
})

test_that("datom_example_cutoffs returns six monthly cutoff dates", {
  cuts <- datom_example_cutoffs()
  expect_length(cuts, 6L)
  expect_named(cuts, paste0("month_", 1:6))
})
