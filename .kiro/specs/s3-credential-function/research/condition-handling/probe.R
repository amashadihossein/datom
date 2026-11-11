# Checks behind the 2026-11-10 review of the s3-credential-function design (design.md, section 14):
# how R's condition handling, purrr, testthat and rlang treat a credential failure on its way to a
# caller. Needs only purrr, rlang, testthat and cli; nothing from datom is loaded.
# Run: Rscript .kiro/specs/s3-credential-function/research/condition-handling/probe.R
main <- function() {
  cat("purrr", as.character(packageVersion("purrr")),
      " rlang", as.character(packageVersion("rlang")),
      " testthat", as.character(packageVersion("testthat")),
      " cli", as.character(packageVersion("cli")), "\n\n")

  cred <- function() {
    stop(structure(class = c("datom_credentials_error", "error", "condition"),
                   list(message = "cred", call = NULL)))
  }

  cat("== Finding 1: a class clause listed before error = \n")
  r1 <- tryCatch(cred(),
                 datom_credentials_error = function(e) stop(e),
                 error = function(e) "reworded")
  cat("result:", r1, "\n")
  cat("reviewer's option (a), first line of the catch-all: ")
  r1c <- tryCatch(
    tryCatch(cred(), error = function(e) {
      if (inherits(e, "datom_credentials_error")) stop(e)
      "reworded"
    }),
    error = function(e) paste("caller sees class:", class(e)[1]))
  cat(r1c, "\n\n")

  cat("== Finding 2: purrr::map re-wraps\n")
  e2 <- tryCatch(purrr::map(1, function(i) cred()), error = identity)
  cat("class:", class(e2), "\n")
  cat("inherits credentials error:", inherits(e2, "datom_credentials_error"), "\n")
  cat("parent class:", class(e2$parent)[1], "\n")
  cat("caller's class handler sees the original:",
      isTRUE(tryCatch(purrr::map(1, function(i) cred()),
                      datom_credentials_error = function(e) TRUE,
                      error = function(e) FALSE)), "\n")
  e2l <- tryCatch(lapply(1, function(i) cred()), error = identity)
  cat("lapply class:", class(e2l)[1], "\n")
  for (f in c("map_lgl", "walk", "imap", "map_chr", "keep", "detect", "compact")) {
    e <- tryCatch(
      switch(f,
        map_lgl = purrr::map_lgl(1, function(i) cred()),
        walk = purrr::walk(1, function(i) cred()),
        imap = purrr::imap(list(a = 1), function(x, i) cred()),
        map_chr = purrr::map_chr(1, function(i) cred()),
        keep = purrr::keep(list(1), function(x) cred()),
        detect = purrr::detect(list(1), function(x) cred()),
        compact = purrr::compact(list(1))
      ),
      error = identity)
    cat(sprintf("  purrr::%s -> %s\n", f,
                if (inherits(e, "condition")) class(e)[1] else "no error"))
  }
  cat("\n")

  cat("== Finding 3: expect_error(class =) across the parent chain\n")
  e0 <- rlang::catch_cnd(cred())
  t_inherit <- tryCatch({
    testthat::expect_error(cli::cli_abort("Failed to upload", parent = e0),
                           class = "datom_credentials_error")
    "passes"
  }, expectation_failure = function(e) "fails", error = function(e) paste("errors:", conditionMessage(e)))
  # When the class does not match, testthat lets the unmatched error through rather than reporting
  # an expectation failure, so either outcome means "does not pass".
  t_noinherit <- tryCatch({
    testthat::expect_error(cli::cli_abort("Failed to upload", parent = e0),
                           class = "datom_credentials_error", inherit = FALSE)
    "passes"
  }, expectation_failure = function(e) "does not pass",
     error = function(e) "does not pass (the reworded error goes through)")
  cat("inherit = TRUE (default):", t_inherit, "\n")
  cat("inherit = FALSE:", t_noinherit, "\n")
  t_regexp <- tryCatch({
    testthat::expect_error(cli::cli_abort("Failed to upload", parent = e0),
                           regexp = "^cred$|cred")
    "passes"
  }, expectation_failure = function(e) "fails")
  cat("regexp matching the cause's text:", t_regexp, "\n\n")

  cat("== Finding 5 / R2.5: conditionMessage of an rlang error with a parent\n")
  m <- conditionMessage(rlang::error_cnd(message = "outer", parent = simpleError("inner")))
  cat(m, "\n")
  cat("contains 'inner':", grepl("inner", m), "\n")
  m2 <- tryCatch(cli::cli_abort("datom outer", parent = simpleError("FUNCTION-OUTPUT")),
                 error = conditionMessage)
  cat("cli_abort(parent =) message contains the parent's text:",
      grepl("FUNCTION-OUTPUT", m2), "\n\n")

  cat("== Finding 6 / FM12: a function using a global, sent to a fresh R\n")
  assign("probe_global_profile", "dev-profile", envir = globalenv())
  fn <- eval(quote(function() probe_global_profile), globalenv())
  f <- tempfile(fileext = ".rds")
  saveRDS(list(credentials = fn), f)
  out <- system2(file.path(R.home("bin"), "Rscript"),
                 c("-e", shQuote(sprintf(
                   "x <- readRDS('%s'); r <- tryCatch(x$credentials(), error = function(e) paste('error:', conditionMessage(e))); cat(r)", f))),
                 stdout = TRUE, stderr = TRUE)
  cat("fresh R calling the loaded function:", out, "\n")
  invisible(NULL)
}
main()
