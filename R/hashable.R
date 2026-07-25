# The datom table contract: column-type classification and recourse.
#
# This file is the single source of truth for two related questions:
#   - .datom_column_kind(x)   -- "can this column be hashed, and if so, how?"
#   - .datom_hash_recourse(x) -- "if not, what should the user do about it?"
#
# The canonical hash engine (.datom_canonical_hash) and the exported pre-flight
# checker (datom_check_hashable) both bind to these functions, so the hash
# gate, the encoder dispatch, and the user-facing advice can never drift.


#' Classify a Column for Canonical Hashing
#'
#' The single supported-type classifier underneath the `datom-cv1` hash. It
#' returns the dispatch *kind* for a hashable column or `NULL` for an
#' unsupported one. Both the all-offenders gate (`.datom_hash_recourse()`)
#' and the per-column encoder in `.datom_canonical_hash()` consume this one
#' function, so a column the gate accepts can never be one the encoder cannot
#' encode.
#'
#' Dispatch is evaluated in a fixed order (reordering can silently change
#' hashes): `bit64::integer64`, factor, `Date` (incl. `data.table::IDate`),
#' `POSIXct`, `difftime`/`hms`, `data.table::ITime`, then
#' `haven_labelled`/`labelled`/`labelled_spss` (stripped to their underlying
#' type and re-classified), then any other explicitly-classed column is
#' refused, then unclassed atomics (logical/integer/double as `"num"`,
#' character as `"chr"`), and finally any other type is refused.
#'
#' Detection uses `inherits()` / `typeof()` / `is.object()` class-string
#' matching only -- it adds no new package dependency (`bit64`, `data.table`,
#' `haven` are recognised by their class strings, not by being loaded).
#'
#' @param x A single column (vector) from a data frame.
#' @return One of the kind tags `"i64"`, `"chr"`, `"date"`, `"time"`,
#'   `"drtn"`, `"num"` for a supported column, or `NULL` when unsupported.
#' @keywords internal
.datom_column_kind <- function(x) {
  # bit64::integer64 -- caught first; its 8-byte patterns are hashed verbatim.
  if (inherits(x, "integer64")) return("i64")

  # factor -- hashed by as.character values; levels/orderedness are not identity.
  if (inherits(x, "factor")) return("chr")

  # Date, incl. integer-storage Dates and data.table::IDate.
  if (inherits(x, "Date")) return("date")

  # POSIXct -- epoch seconds; tzone excluded from identity.
  if (inherits(x, "POSIXct")) return("time")

  # difftime / hms -- numeric payload plus its units string.
  if (inherits(x, "difftime")) return("drtn")

  # data.table::ITime -- encoded like difftime with units "secs".
  if (inherits(x, "ITime")) return("drtn")

  # Labelled columns strip class and attributes and fall through to the
  # underlying type; value labels are not identity.
  if (inherits(x, c("haven_labelled", "labelled", "labelled_spss"))) {
    stripped <- x
    attributes(stripped) <- NULL
    return(.datom_column_kind(stripped))
  }

  # Any other explicitly-classed column is unsupported.
  if (is.object(x)) return(NULL)

  # Unclassed atomics: logical/integer/double unify under "num"; character.
  if (is.logical(x) || is.integer(x) || is.double(x)) return("num")
  if (is.character(x)) return("chr")

  # Any other type (list, complex, raw, ...) is unsupported.
  NULL
}


#' Canonical Recourse String for an Unhashable Column
#'
#' The single source of truth for the remediation advice attached to an
#' unsupported column. Returns `NULL` when `.datom_column_kind(x)` classifies
#' the column as hashable, otherwise the canonical recourse string for the
#' first matching offender category. Both `datom_check_hashable()` and the
#' `.datom_canonical_hash()` all-offenders abort call this one function, so
#' the checker's advice and the abort's advice can never diverge.
#'
#' The column name and class are added by the caller (a checker row or an
#' abort bullet); the strings here are type-scoped only. Detection order
#' matters: `POSIXlt` (a list under the hood) is matched before the generic
#' list rows; the nested-data-frame list row before the generic list row; and
#' the class-specific rows (`units`, `sfc`, `yearmon`/`yearqtr`/`chron`)
#' before the "other classed" fallback.
#'
#' @param x A single column (vector) from a data frame.
#' @return `NULL` when `x` is hashable, otherwise a canonical recourse string.
#' @keywords internal
.datom_hash_recourse <- function(x) {
  if (!is.null(.datom_column_kind(x))) return(NULL)

  # POSIXlt is a list under the hood -- match it before the generic list rows.
  if (inherits(x, "POSIXlt")) {
    return(paste0(
      "POSIXlt columns are not hashable. Convert to POSIXct with ",
      "as.POSIXct() before writing."
    ))
  }

  # sf geometry. An sfc object is a list of geometries under the hood, so --
  # like POSIXlt -- it must be matched before the generic list rows or it
  # would be shadowed by the list/blob rule and never reach this specific
  # (more useful) recourse.
  if (inherits(x, "sfc")) {
    return(paste0(
      "sf geometry (sfc) columns are not hashable. Convert to WKT text with ",
      "sf::st_as_text() before writing."
    ))
  }

  # Nested tibble / data-frame list column -- matched before the generic list
  # row. Require at least one element so an empty list falls to the generic
  # list rule rather than being mislabelled a nested-data-frame column.
  if (is.list(x) && !is.data.frame(x) && length(x) > 0L &&
      all(vapply(x, is.data.frame, logical(1)))) {
    return(paste0(
      "Nested data-frame (list) columns are not hashable. Model the inner ",
      "table as its own datom table joined by a key with datom_parent() ",
      "lineage, or flatten it with tidyr::unnest(), before writing."
    ))
  }

  # Any other list / blob column.
  if (is.list(x) && !is.data.frame(x)) {
    return(paste0(
      "List and blob columns are not hashable. Flatten to one value per row ",
      "with tidyr::unnest(), or serialize each element to character (for ",
      "example with jsonlite::toJSON() per element), before writing."
    ))
  }

  # units package.
  if (inherits(x, "units")) {
    return(paste0(
      "units columns are not hashable. Drop the unit with ",
      "units::drop_units() and record the unit in the column name or a ",
      "companion column (audit-friendly), before writing."
    ))
  }

  # zoo::yearmon / yearqtr and chron.
  if (inherits(x, c("yearmon", "yearqtr", "chron"))) {
    return(paste0(
      "zoo::yearmon / yearqtr and chron columns are not hashable. Convert to ",
      "Date/POSIXct or ISO-8601 text before writing."
    ))
  }

  # complex.
  if (typeof(x) == "complex") {
    return(paste0(
      "Complex columns are not hashable. Split into separate real and ",
      "imaginary numeric columns, or convert to character, before writing."
    ))
  }

  # raw.
  if (typeof(x) == "raw") {
    return(paste0(
      "Raw columns are not hashable. Encode the bytes as character (for ",
      "example base64) before writing."
    ))
  }

  # Any other classed column not in the supported set.
  paste0(
    "Columns of this class are not hashable. Convert to a supported type ",
    "(logical, integer, double, character, factor, Date, POSIXct, ",
    "difftime/hms, or bit64::integer64) before writing."
  )
}


#' Human-Readable Class Label for a Column
#'
#' Renders the label shown for a column in the all-offenders abort bullets
#' and in the `datom_check_hashable()` report: the collapsed `class(x)`
#' string for an explicitly-classed column, or `typeof(x)` for an unclassed
#' one (so a list column reads `list`, a complex column `complex`, and a
#' `units` column `units`).
#'
#' @param x A single column (vector) from a data frame.
#' @return A single character string.
#' @keywords internal
.datom_class_label <- function(x) {
  if (is.object(x)) {
    paste(class(x), collapse = "/")
  } else {
    typeof(x)
  }
}


#' Check Whether a Table Can Be Hashed by datom
#'
#' Pre-flight check for the datom table contract. Reports, per column, whether
#' `datom_write()` can hash it and -- when it cannot -- exactly what to do
#' about it. Run this before a write to fix a table in one pass instead of
#' discovering offenders one error at a time.
#'
#' datom identifies a table version by a canonical hash of its contents
#' (`data_sha`), which requires every column to be a supported type: logical,
#' integer, double, character, factor, `Date`, `POSIXct`, `difftime`/`hms`,
#' `data.table::ITime`/`IDate`, `bit64::integer64`, or a labelled vector over
#' one of those. List columns (including nested data frames, blobs, and
#' `POSIXlt`), `complex`, `raw`, `sf` geometry, `units`, and `zoo`/`chron`
#' columns are refused with specific advice.
#'
#' The advice printed here is the same single-source recourse text
#' `datom_write()` would abort with, so the two can never disagree.
#'
#' @param data A data frame to check.
#'
#' @return Invisibly, a data frame with one row per column of `data` and
#'   columns:
#'   \describe{
#'     \item{`column`}{Column name.}
#'     \item{`class`}{Collapsed class string, or `typeof()` when unclassed.}
#'     \item{`status`}{`"ok"` or `"unsupported"`.}
#'     \item{`recourse`}{`NA` when ok, otherwise how to make the column
#'       hashable.}
#'   }
#'
#' @seealso [datom_write()]
#'
#' @examples
#' # A clean table: every column is a supported type
#' clean <- data.frame(
#'   id = 1:3,
#'   score = c(1.5, 2.5, 3.5),
#'   label = c("a", "b", "c"),
#'   grp = factor(c("x", "y", "x")),
#'   day = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03"))
#' )
#' datom_check_hashable(clean)
#'
#' # An offending table: a list column and a complex column
#' messy <- data.frame(id = 1:2)
#' messy$notes <- list(c("a", "b"), "c")
#' messy$z <- c(1 + 2i, 3 + 4i)
#' report <- datom_check_hashable(messy)
#' report[report$status == "unsupported", c("column", "recourse")]
#'
#' @export
datom_check_hashable <- function(data) {

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  if (ncol(data) == 0L) {
    cli::cli_abort("{.arg data} must have at least one column.")
  }

  nms <- names(data)

  report <- data.frame(
    column = nms,
    class = vapply(data, .datom_class_label, character(1L), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
  recourse <- lapply(data, .datom_hash_recourse)
  report$recourse <- vapply(
    recourse,
    function(r) if (is.null(r)) NA_character_ else r,
    character(1L), USE.NAMES = FALSE
  )
  ok <- is.na(report$recourse)
  report$status <- ifelse(ok, "ok", "unsupported")
  report <- report[, c("column", "class", "status", "recourse")]

  n_bad <- sum(!ok)

  if (n_bad == 0L) {
    cli::cli_alert_success(
      "All {ncol(data)} column{?s} {?is/are} hashable. This table is ready for {.fn datom_write}."
    )
    return(invisible(report))
  }

  bullets <- vapply(which(!ok), function(i) {
    paste0(
      "Column {.field ", nms[[i]], "} ",
      "({.cls ", report$class[[i]], "}): ",
      report$recourse[[i]]
    )
  }, character(1L), USE.NAMES = FALSE)
  names(bullets) <- rep("x", n_bad)

  cli::cli_alert_danger(
    "{n_bad} of {ncol(data)} column{?s} {?is/are} not hashable."
  )
  cli::cli_bullets(bullets)
  cli::cli_alert_info(
    "Fix these before {.fn datom_write}, which refuses the whole table until they are resolved."
  )

  invisible(report)
}
