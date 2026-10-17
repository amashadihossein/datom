# Running one shared reader case through R datom.
#
# A reader case (tests/testthat/fixtures/reader-cases/, see its README) is a
# small datom store written by R datom plus the result any reader must produce
# on it. This file is the one place that runs a case's call and describes what
# came back, in the language-neutral shape `case.json` records. Two callers:
# test-reader-cases.R, which compares the result against `case.json`, and
# dev/reader-cases/generate.R, which records it when a case is first made. One
# copy, so the recorder and the checker cannot drift apart.
#
# Internal functions are reached through `datom:::` so the generator, which
# attaches the installed package rather than loading the source, can use them.

rc_project <- "STUDY_001"

# The R condition class R datom raises for each language-neutral case error.
# Matched against the error's FIRST class, so an error re-wrapped on its way
# out (as purrr does) does not pass. Kept in step with the table in the cases
# README.
rc_error_class <- function(error, op) {
  if (identical(error, "integrity_mismatch")) {
    return(if (identical(op, "read_set")) {
      "datom_set_integrity_failure"
    } else {
      "datom_parquet_integrity_failure"
    })
  }
  classes <- c(
    schema_unsupported   = "datom_schema_unsupported",
    schema_invalid       = "datom_schema_invalid",
    kind_mismatch        = "datom_artifact_kind_conflict",
    document_sha_missing = "datom_set_document_sha_missing",
    set_member_malformed = "datom_set_member_malformed",
    member_ambiguous     = "datom_member_ambiguous",
    member_not_found     = "datom_member_not_found",
    version_not_found    = "datom_version_not_found",
    version_ambiguous    = "datom_version_ambiguous",
    invalid_address      = "datom_invalid_sha"
  )
  if (!error %in% names(classes)) return(NA_character_)
  classes[[error]]
}

# Always a JSON array, even of length 1.
rc_arr <- function(x) I(as.character(x))

# Unpack a case's storage.zip into a fresh folder and return that folder.
rc_unpack_storage <- function(case_dir, dest = tempfile("reader-case-")) {
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(file.path(case_dir, "storage.zip"), exdir = dest)
  dest
}

rc_reader_conn <- function(storage) {
  datom_get_conn(
    store = datom_store(data = datom_store_local(storage)),
    project_name = rc_project
  )
}

# The language-neutral name for a warning R datom raised, or NULL.
rc_warning_code <- function(w) {
  if (grepl("has governance attached", conditionMessage(w), fixed = TRUE)) {
    return("governance_attached")
  }
  NULL
}

# Arrow type names of the stored parquet object, as R arrow prints them.
#
# An R-only extension type (R arrow stores labelled and other vctrs columns
# this way) is reported as its storage type. Its own name is not stable -- it
# changes with which R packages are loaded -- and a reader outside R sees only
# the storage type anyway.
rc_arrow_types <- function(storage, name, data_sha) {
  file <- file.path(storage, "datom", name, paste0(data_sha, ".parquet"))
  tb <- arrow::read_parquet(file, as_data_frame = FALSE)
  vapply(tb$schema$fields, function(f) {
    type <- f$type
    if (inherits(type, "ExtensionType")) type <- type$storage_type()
    type$ToString()
  }, character(1L))
}

rc_table_result <- function(storage, conn, name, version, df) {
  ml <- datom:::.datom_read_metadata(conn, name)
  res <- datom:::.datom_resolve_version(ml, version, name, "parquet_sha")
  list(
    ok = TRUE,
    version = res$version,
    data_sha = res$data_sha,
    nrow = nrow(df),
    ncol = ncol(df),
    colnames = rc_arr(names(df)),
    arrow_types = rc_arr(rc_arrow_types(storage, name, res$data_sha))
  )
}

rc_tag_map <- function(tags) {
  if (is.null(tags)) return(NULL)
  lapply(tags, function(v) rc_arr(unlist(v, use.names = FALSE)))
}

rc_set_result <- function(s) {
  members <- lapply(s$members, function(m) {
    out <- list(id = m$id[c("project", "name", "kind", "version")])
    if (!is.null(m$tags)) out$tags <- rc_tag_map(m$tags)
    out
  })
  out <- list(
    ok = TRUE,
    name = s$name,
    project = s$project,
    version = s$version,
    data_sha = s$data_sha,
    members = members
  )
  if (!is.null(s$tags)) out$tags <- rc_tag_map(s$tags)
  out
}

rc_frame_rows <- function(df) {
  lapply(seq_len(nrow(df)), function(i) {
    row <- as.list(df[i, , drop = FALSE])
    lapply(row, function(v) if (length(v) == 1L && is.na(v)) NULL else v)
  })
}

rc_run_call <- function(storage, call) {
  conn <- rc_reader_conn(storage)
  op <- call$op
  if (op == "read_table") {
    df <- datom_read(conn, call$name, version = call$version)
    return(rc_table_result(storage, conn, call$name, call$version, df))
  }
  if (op == "read_set") {
    return(rc_set_result(datom_get_set(conn, call$name, version = call$version)))
  }
  if (op == "fetch_member") {
    s <- datom_get_set(conn, call$set, version = call$set_version)
    df <- datom_fetch_member(conn, s, call$member, tags = call$tags,
                             version = call$version)
    record <- datom:::.datom_member_record(s$members, call$member, call$tags,
                                           call$version)
    return(rc_table_result(storage, conn, record$id$name, record$id$version, df))
  }
  if (op == "history") {
    n <- if (is.null(call$n)) 10 else call$n
    return(list(ok = TRUE, rows = rc_frame_rows(datom_history(conn, call$name, n = n))))
  }
  if (op == "list") {
    l <- datom_list(conn, include_versions = TRUE, short_hash = FALSE)
    return(list(ok = TRUE, rows = rc_frame_rows(l)))
  }
  stop("unknown op: ", op)
}

# Run a call and describe what R datom did: the result, or the refusal's first
# class and message, plus any warnings that carry a language-neutral name.
rc_observe <- function(storage, call) {
  warnings <- character()
  out <- withCallingHandlers(
    tryCatch(
      suppressMessages(rc_run_call(storage, call)),
      error = function(e) list(ok = FALSE, r_class = class(e)[[1L]],
                               r_message = conditionMessage(e))
    ),
    warning = function(w) {
      code <- rc_warning_code(w)
      if (!is.null(code)) warnings <<- c(warnings, code)
      invokeRestart("muffleWarning")
    }
  )
  if (length(warnings)) out$warnings <- rc_arr(unique(warnings))
  out
}

# A value as it reads back from JSON, so a result built in R compares equal to
# the one recorded in case.json.
rc_as_json <- function(x) {
  jsonlite::fromJSON(
    jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA),
    simplifyVector = FALSE
  )
}
