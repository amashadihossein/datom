#' Load Example Clinical Trial Data
#'
#' Returns one of five small, made-up tables from a simulated clinical trial
#' of 48 subjects: demographics, exposure (dosing), lab results, adverse events
#' or vital signs. Set `cutoff_date` to get the data as it stood on that date,
#' which mimics a new data delivery each month; [datom_example_cutoffs()] lists
#' the dates the examples use.
#'
#' The data simulates STUDY-001, a Phase II study enrolling over six months;
#' table and column names loosely follow SDTM.
#'
#' @param domain One of `"dm"` (demographics, 48 rows), `"ex"` (exposure,
#'   48 rows), `"lb"` (labs, 720 rows: 3 visits x 5 tests per subject),
#'   `"ae"` (adverse events, ~80 rows), or `"vs"` (vital signs, 432 rows:
#'   3 visits x 3 tests per subject, taken on the same dates as the labs).
#' @param cutoff_date Optional date string (`"YYYY-MM-DD"`) to filter
#'   rows whose primary date column is on or before this date, simulating
#'   a point-in-time EDC extract. The date column used per domain:
#'   `RFSTDTC` (dm), `EXSTDTC` (ex), `LBDTC` (lb), `AESTDTC` (ae),
#'   `VSDTC` (vs).
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
datom_example_data <- function(domain = c("dm", "ex", "lb", "ae", "vs"),
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
      ae = "AESTDTC",
      vs = "VSDTC"
    )
    data <- data[as.Date(data[[date_col]]) <= cutoff, , drop = FALSE]
    rownames(data) <- NULL
  }

  data
}


#' Write an Example Table to a CSV File
#'
#' Writes [datom_example_data()] to `<dir>/<domain>.csv`, ready for
#' [datom_sync()] to pick up from a repo's `input_files/` folder. Lines end
#' with a line feed on every operating system, so the file has the same
#' bytes -- and datom records the same version for it -- on Windows, macOS
#' and Linux. (`write.csv()` on its own ends lines with a carriage return
#' and line feed on Windows.)
#'
#' An existing file of the same name is overwritten, which is how the
#' examples simulate a new monthly delivery.
#'
#' @inheritParams datom_example_data
#' @param dir Existing folder to write into, typically a repo's
#'   `input_files/`.
#'
#' @return The path of the written file, invisibly.
#'
#' @examples
#' dir <- tempfile("inputs-")
#' dir.create(dir)
#' datom_example_file("dm", cutoff_date = "2026-01-28", dir = dir)
#' list.files(dir)
#' unlink(dir, recursive = TRUE)
#'
#' @export
datom_example_file <- function(domain = c("dm", "ex", "lb", "ae", "vs"),
                               cutoff_date = NULL,
                               dir) {
  domain <- match.arg(domain)
  if (!fs::dir_exists(dir)) {
    cli::cli_abort("Folder {.path {dir}} does not exist.")
  }

  path <- fs::path(dir, paste0(domain, ".csv"))

  # Binary mode: on Windows a text-mode connection turns every line feed
  # into carriage return + line feed, which changes the file's bytes and
  # so its datom version.
  con <- file(path, "wb")
  on.exit(close(con))
  utils::write.csv(datom_example_data(domain, cutoff_date), con, row.names = FALSE)

  invisible(as.character(path))
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
