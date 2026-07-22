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

  # sf geometry.
  if (inherits(x, "sfc")) {
    return(paste0(
      "sf geometry (sfc) columns are not hashable. Convert to WKT text with ",
      "sf::st_as_text() before writing."
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
