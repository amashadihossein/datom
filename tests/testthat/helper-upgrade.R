# Assert that a refusal or warning carries the upgrade hint: CRAN first, GitHub
# for a development build, and -- for format-related messages only -- a pointer
# at `?datom_schema`. Strips ANSI first so the check holds with colour on or off
# (cli wraps only at spaces, and none of the matched tokens contains one).
expect_upgrade_hint <- function(msg, schema_pointer) {
  msg <- cli::ansi_strip(paste(msg, collapse = "\n"))
  expect_match(msg, 'install.packages("datom")', fixed = TRUE)
  expect_match(msg, 'remotes::install_github("amashadihossein/datom")', fixed = TRUE)
  if (schema_pointer) {
    expect_match(msg, "?datom_schema", fixed = TRUE)
  } else {
    expect_no_match(msg, "datom_schema", fixed = TRUE)
  }
}
