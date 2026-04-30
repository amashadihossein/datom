#' Load Example EDC Data
#'
#' Loads bundled clinical trial example data for use in examples and
#' vignettes. The data simulates a Phase II study (STUDY-001) with 48
#' subjects enrolled over 6 months across four SDTM-flavored domains.
#'
#' @param domain One of `"dm"` (demographics, 48 rows), `"ex"` (exposure,
#'   48 rows), `"lb"` (labs, ~720 rows: 3 visits x 5 tests per subject),
#'   or `"ae"` (adverse events, ~80 rows).
#' @param cutoff_date Optional date string (`"YYYY-MM-DD"`) to filter
#'   rows whose primary date column is on or before this date, simulating
#'   a point-in-time EDC extract. The date column used per domain:
#'   `RFSTDTC` (dm), `EXSTDTC` (ex), `LBDTC` (lb), `AESTDTC` (ae).
#'
#' @return A data frame.
#'
#' @examples
#' # Full demographics
#' dm <- datom_example_data("dm")
#'
#' # Month-3 snapshot (subjects enrolled by 2026-03-28)
#' dm_m3 <- datom_example_data("dm", cutoff_date = "2026-03-28")
#'
#' # Labs collected through Month 3
#' lb_m3 <- datom_example_data("lb", cutoff_date = "2026-03-28")
#'
#' @export
datom_example_data <- function(domain = c("dm", "ex", "lb", "ae"),
                               cutoff_date = NULL) {
  domain <- match.arg(domain)

  file <- system.file("extdata", paste0(domain, ".csv"), package = "datom")
  if (!nzchar(file)) {
    cli::cli_abort("Example data file {.file {domain}.csv} not found in package.")
  }

  data <- utils::read.csv(file, stringsAsFactors = FALSE)

  if (!is.null(cutoff_date)) {
    cutoff <- as.Date(cutoff_date)
    date_col <- switch(
      domain,
      dm = "RFSTDTC",
      ex = "EXSTDTC",
      lb = "LBDTC",
      ae = "AESTDTC"
    )
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
#' datom_example_cutoffs()
#' # month_1    month_2    month_3    month_4    month_5    month_6
#' # "2026-01-28" "2026-02-28" ...
#'
#' @export
datom_example_cutoffs <- function() {
  c(
    month_1 = "2026-01-28",
    month_2 = "2026-02-28",
    month_3 = "2026-03-28",
    month_4 = "2026-04-28",
    month_5 = "2026-05-28",
    month_6 = "2026-06-28"
  )
}
