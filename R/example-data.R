#' Load Example EDC Data
#'
#' Loads bundled clinical trial example data (DM and EX domains) for
#' use in examples and vignettes. The data simulates a Phase II study
#' (STUDY-001) with 48 subjects enrolled over 6 months.
#'
#' @param domain One of `"dm"` (demographics) or `"ex"` (exposure).
#' @param cutoff_date Optional date string (`"YYYY-MM-DD"`) to filter
#'   subjects enrolled on or before this date, simulating a point-in-time
#'   EDC extract.
#'
#' @return A data frame.
#'
#' @examples
#' # Full demographics
#' dm <- tbit_example_data("dm")
#'
#' # Month-3 snapshot (subjects enrolled by 2026-03-28)
#' dm_m3 <- tbit_example_data("dm", cutoff_date = "2026-03-28")
#'
#' @export
tbit_example_data <- function(domain = c("dm", "ex"), cutoff_date = NULL) {
  domain <- match.arg(domain)

  file <- system.file("extdata", paste0(domain, ".csv"), package = "tbit")
  if (!nzchar(file)) {
    cli::cli_abort("Example data file {.file {domain}.csv} not found in package.")
  }

  data <- utils::read.csv(file, stringsAsFactors = FALSE)

  if (!is.null(cutoff_date)) {
    cutoff <- as.Date(cutoff_date)
    date_col <- if (domain == "dm") "RFSTDTC" else "EXSTDTC"
    data <- data[as.Date(data[[date_col]]) <= cutoff, , drop = FALSE]
    rownames(data) <- NULL
  }

  data
}


#' Monthly Cutoff Dates for Example Study
#'
#' Returns a named vector of monthly cutoff dates for STUDY-001,
#' useful for simulating EDC data evolution in examples.
#'
#' @return Named character vector with entries `month_1` through `month_6`.
#'
#' @examples
#' tbit_example_cutoffs()
#' # month_1    month_2    month_3    month_4    month_5    month_6
#' # "2026-01-28" "2026-02-28" ...
#'
#' @export
tbit_example_cutoffs <- function() {
  c(
    month_1 = "2026-01-28",
    month_2 = "2026-02-28",
    month_3 = "2026-03-28",
    month_4 = "2026-04-28",
    month_5 = "2026-05-28",
    month_6 = "2026-06-28"
  )
}
