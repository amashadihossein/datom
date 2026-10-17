#!/usr/bin/env Rscript
# Shared reader cases: small datom stores written by R datom, each saved with the
# result any reader must produce. See tests/testthat/fixtures/reader-cases/README.md.
#
#   Rscript dev/reader-cases/generate.R [out_dir]
#
# Run from the package root, with the datom under development installed
# (`devtools::install()`): the cases record what THAT build writes and reads.
# out_dir defaults to tests/testthat/fixtures/reader-cases.
#
# It ONLY ADDS cases whose folder is missing. A committed case is never
# regenerated or edited: new behaviour gets a new case. Checking the committed
# cases is test-reader-cases.R's job, not this script's.
#
# Fully offline: a local-folder store and a local bare git repo as the remote,
# with a placeholder GitHub token and validation off, as datom's own examples
# do. Needs git2r, bit64 and haven (for the column-kinds case).
#
# Every expected result is what R datom itself returns on that case's storage,
# read through a reader (storage-only) connection. Refusal cases are made by
# editing the written files afterwards; case.json records the edit. A case's
# storage is packed as storage.zip, because R CMD check flags the hidden
# `.metadata/` folders every datom store has.

suppressPackageStartupMessages(library(datom))
options(cli.num_colors = 1, warn = 1)

# The code that runs a call and describes the result, shared with the test.
source("tests/testthat/helper-reader-cases.R")

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1L) args[[1L]] else "tests/testthat/fixtures/reader-cases"
stopifnot(dir.exists(dirname(out_dir)))

quiet <- function(expr) suppressMessages(expr)
PROJECT <- rc_project



# --- 1. The source project, written by R datom --------------------------------

root <- tempfile("reader-cases-")
dir.create(root)
remote <- file.path(root, "remote.git")
dir.create(remote)
invisible(git2r::init(remote, bare = TRUE))
storage <- file.path(root, "storage")
dev_store <- datom_store(
  data = datom_store_local(storage),
  github_pat = "example-token", # role selector; a local remote needs none
  data_repo_url = remote,
  validate = FALSE
)
repo <- file.path(root, "repo")
quiet(datom_init_repo(repo, PROJECT, dev_store, mode = "product",
                      set = "trial_product"))
git2r::config(git2r::repository(repo), user.name = "Reader Cases",
              user.email = "reader-cases@example.com")
conn <- quiet(datom_get_conn(repo, dev_store))

# dm: a data change, then a metadata-only change (v3 shares v2's data).
dm1 <- data.frame(
  USUBJID = sprintf("S-%02d", 1:5),
  AGE = c(34L, 51L, 47L, 29L, 62L),
  SEX = factor(c("F", "M", "F", "M", "F")),
  RFSTDTC = as.Date("2026-01-05") + c(0L, 2L, 3L, 7L, 9L)
)
dm2 <- rbind(dm1, data.frame(
  USUBJID = "S-06", AGE = 40L, SEX = factor("M", levels = c("F", "M")),
  RFSTDTC = as.Date("2026-01-20")
))
quiet(datom_write(conn, data = dm1, name = "dm", message = "First data cut"))
quiet(datom_write(conn, data = dm2, name = "dm", message = "Second data cut"))
quiet(datom_write(conn, data = dm2, name = "dm",
                  metadata = list(description = "Demographics"),
                  message = "Describe the table"))
v_dm <- datom_history(conn, "dm", n = 100)$version # newest first: v3, v2, v1

lb <- data.frame(
  USUBJID = rep(sprintf("S-%02d", 1:3), each = 2L),
  LBTESTCD = rep(c("ALT", "AST"), 3L),
  LBSTRESN = c(21.5, 18, 33.25, 29, 15.75, 17.5)
)
quiet(datom_write(conn, data = lb, name = "lb", message = "Labs"))
v_lb <- datom_history(conn, "lb")$version[[1L]]

# kinds: every column kind datom supports, with a missing value in each.
kinds <- data.frame(
  lgl = c(TRUE, FALSE, NA),
  int = c(1L, NA, 3L),
  dbl = c(1.5, NA, -2.25),
  chr = c("a", NA, "c"),
  fct = factor(c("lo", "hi", NA), levels = c("lo", "hi")),
  date = as.Date(c("2026-01-01", NA, "2026-03-01")),
  stringsAsFactors = FALSE
)
kinds$dttm <- as.POSIXct(c("2026-01-01 08:30:00", NA, "2026-03-01 17:45:00"),
                         tz = "America/New_York")
kinds$dur <- as.difftime(c(1.5, NA, 3), units = "hours")
kinds$i64 <- bit64::as.integer64(c("9007199254740993", NA, "-5"))
kinds$lbl <- haven::labelled(c(1, 2, NA), labels = c(Placebo = 1, Active = 2),
                             label = "Arm")
quiet(datom_write(conn, data = kinds, name = "kinds",
                  message = "Every column kind"))

# trial_product: v1 cites dm and lb; v2 cites dm at two versions, beside an
# untagged lb.
x1 <- quiet(datom_assemble_set(conn, name = "trial_product",
                               tags = list(description = "Interim cut")))
x1 <- quiet(datom_add_member(x1, "dm", v_dm[[3L]], conn = conn,
                             tags = list(type = "input",
                                         domain = c("demographics", "safety"))))
x1 <- quiet(datom_add_member(x1, "lb", v_lb, conn = conn,
                             tags = list(type = "input")))
quiet(datom_write_set(conn, x1, message = "Interim product"))

x2 <- quiet(datom_assemble_set(conn, name = "trial_product",
                               tags = list(description = "Final cut",
                                           area = c("oncology", "phase 2"))))
x2 <- quiet(datom_add_member(x2, "dm", v_dm[[3L]], conn = conn,
                             tags = list(role = "baseline", type = "input")))
x2 <- quiet(datom_add_member(x2, "dm", v_dm[[1L]], conn = conn,
                             tags = list(role = "current", type = "input")))
x2 <- quiet(datom_add_member(x2, "lb", v_lb, conn = conn))
quiet(datom_write_set(conn, x2, message = "Final product"))
v_set <- datom_history(conn, "trial_product")$version # newest first

# vt: written until two versions share a first character (at most 17 writes).
for (i in seq_len(17L)) {
  quiet(datom_write(conn, data = data.frame(i = i), name = "vt",
                    message = sprintf("Version %d", i)))
  firsts <- substr(datom_history(conn, "vt", n = 100)$version, 1L, 1L)
  if (anyDuplicated(firsts)) break
}
vt_shared <- firsts[duplicated(firsts)][[1L]]

meta_dir <- function(s, name) file.path(s, "datom", name, ".metadata")
current_meta <- function(name) {
  jsonlite::read_json(file.path(meta_dir(storage, name), "metadata.json"))
}
dm_current_sha <- current_meta("dm")$data_sha
v_set_first_member_version <- jsonlite::read_json(file.path(
  storage, "datom", "trial_product",
  paste0(current_meta("trial_product")$data_sha, ".json")
))$members[[1L]]$id$version


# --- 2. Building one case -----------------------------------------------------

# A case's storage holds only the artifacts its call touches, plus the
# manifest, so the cases stay small.
copy_store <- function(dest, artifacts) {
  dir.create(file.path(dest, "datom", ".metadata"), recursive = TRUE)
  file.copy(file.path(storage, "datom", ".metadata", "manifest.json"),
            file.path(dest, "datom", ".metadata", "manifest.json"))
  for (a in artifacts) {
    file.copy(file.path(storage, "datom", a), file.path(dest, "datom"),
              recursive = TRUE)
  }
}

# A text edit that must match exactly `n` times, so a format change in R datom
# fails the generator instead of silently producing a case that edits nothing.
edit_text <- function(path, pattern, replacement, n = 1L, fixed = TRUE) {
  txt <- readLines(path, warn = FALSE)
  hits <- if (fixed) grepl(pattern, txt, fixed = TRUE) else grepl(pattern, txt)
  if (sum(hits) != n) {
    stop(sprintf("edit of %s: expected %d match(es) of %s, found %d",
                 path, n, pattern, sum(hits)))
  }
  txt <- if (is.null(replacement)) {
    txt[!hits]
  } else if (fixed) {
    gsub(pattern, replacement, txt, fixed = TRUE)
  } else {
    gsub(pattern, replacement, txt)
  }
  writeLines(txt, path)
}

flip_byte <- function(path, at) {
  raw <- readBin(path, "raw", file.info(path)$size)
  raw[[at]] <- as.raw(bitwXor(as.integer(raw[[at]]), 0xFFL))
  writeBin(raw, path)
}

sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

new_cases <- 0L
make_case <- function(id, description, artifacts, call, error = NULL,
                      edit = NULL, edited = NULL) {
  dest <- file.path(out_dir, id)
  if (dir.exists(dest)) {
    cat(sprintf("%-40s exists, left alone\n", id))
    return(invisible(NULL))
  }
  tmp <- file.path(root, "cases", id)
  copy_store(file.path(tmp, "storage"), artifacts)
  if (!is.null(edit)) edit(file.path(tmp, "storage"))

  got <- rc_observe(file.path(tmp, "storage"), call)
  if (is.null(error)) {
    if (!isTRUE(got$ok)) {
      stop(sprintf("case %s: R datom refused: %s", id, got$r_message))
    }
    expect <- got
  } else {
    if (!identical(got$ok, FALSE)) {
      stop(sprintf("case %s: expected a refusal, R datom read it", id))
    }
    # The refusal must carry the class the error-name table maps it to;
    # otherwise the test would fail on the case the moment it is committed.
    want_class <- rc_error_class(error, call$op)
    if (!identical(got$r_class, want_class)) {
      stop(sprintf("case %s: expected class %s, R datom raised %s",
                   id, want_class, got$r_class))
    }
    expect <- list(ok = FALSE, error = error)
  }

  case <- list(
    description = description,
    generated_with = paste("datom", as.character(utils::packageVersion("datom"))),
    call = call,
    expect = expect
  )
  if (!is.null(edited)) case$edited <- edited

  dir.create(dest, recursive = TRUE)
  # Paths inside the zip are relative to the storage root (`datom/...`). -X
  # leaves out file attributes that vary by machine.
  zipfile <- normalizePath(file.path(dest, "storage.zip"), mustWork = FALSE)
  owd <- setwd(file.path(tmp, "storage"))
  utils::zip(zipfile, list.files(".", recursive = TRUE, all.files = TRUE),
             flags = "-q -X")
  setwd(owd)
  jsonlite::write_json(case, file.path(dest, "case.json"), auto_unbox = TRUE,
                       pretty = TRUE, null = "null", digits = NA)
  new_cases <<- new_cases + 1L
  cat(sprintf("%-40s added\n", id))
}

prefix_of <- function(v, others, n = 8L) {
  while (sum(startsWith(others, substr(v, 1L, n))) > 1L) n <- n + 1L
  substr(v, 1L, n)
}


# --- 3. The cases -------------------------------------------------------------

# Reads that succeed.
make_case("table-current", "Read a table at its current version",
          "dm", list(op = "read_table", name = "dm", version = NULL))

make_case("table-version-full", "Read a table at an older version by its full version id",
          "dm", list(op = "read_table", name = "dm", version = v_dm[[3L]]))

make_case("table-version-prefix", "Read a table at an older version by a unique prefix of its id",
          "dm", list(op = "read_table", name = "dm",
                     version = prefix_of(v_dm[[2L]], v_dm)))

make_case("table-shared-data", paste(
  "Read the version before a metadata-only change. It resolves to the same",
  "data file as the current version (see table-current)."
), "dm", list(op = "read_table", name = "dm", version = v_dm[[2L]]))

make_case("table-column-kinds", paste(
  "A table using every column kind datom supports: logical, integer, double,",
  "character, factor, Date, date-time with a time zone, difftime, integer64,",
  "labelled. Each column has a missing value."
), "kinds", list(op = "read_table", name = "kinds", version = NULL))

make_case("table-no-parquet-sha", paste(
  "A table from before integrity hashes existed: no parquet_sha anywhere. The",
  "read succeeds and the hash check is skipped."
), "dm", list(op = "read_table", name = "dm", version = NULL),
edited = "Removed every parquet_sha line from metadata.json and version_history.json.",
edit = function(s) {
  edit_text(file.path(meta_dir(s, "dm"), "metadata.json"), "\"parquet_sha\":", NULL)
  edit_text(file.path(meta_dir(s, "dm"), "version_history.json"), "\"parquet_sha\":",
            NULL, n = length(v_dm))
})

make_case("set-current", paste(
  "Read a set at its current version. It cites dm at two versions (a baseline",
  "beside the current cut) and an untagged lb. Members come back as pointers;",
  "nothing is fetched."
), "trial_product", list(op = "read_set", name = "trial_product", version = NULL))

make_case("set-older", "Read a set at an older version by a prefix of its id",
          "trial_product", list(op = "read_set", name = "trial_product",
                                version = prefix_of(v_set[[2L]], v_set)))

make_case("set-fetch-member", paste(
  "Fetch one member's data from a set. The name dm matches two members, so",
  "the call narrows by a label."
), c("trial_product", "dm"), list(op = "fetch_member", set = "trial_product",
                                  set_version = NULL, member = "dm",
                                  tags = list(role = "current"), version = NULL))

make_case("set-fetch-member-by-version", paste(
  "Fetch one member's data from a set, narrowing a repeated name by a",
  "version prefix instead of a label."
), c("trial_product", "dm"), list(op = "fetch_member", set = "trial_product",
                                  set_version = NULL, member = "dm", tags = NULL,
                                  version = substr(v_dm[[3L]], 1L, 8L)))

make_case("history-table", paste(
  "A table's history, newest first: version, data_sha, timestamp, author,",
  "commit_message, commit_sha."
), "dm", list(op = "history", name = "dm", n = 100))

make_case("history-set", "A set's history", "trial_product",
          list(op = "history", name = "trial_product", n = 100))

make_case("list", "List a repo: names, kinds, current versions",
          c("dm", "lb", "kinds", "trial_product", "vt"), list(op = "list"))

make_case("list-manifest-v1", paste(
  "List a repo whose manifest is in the older format: tables under `tables`,",
  "no `kind`, no `schema_version`. It is converted in memory."
), c("dm", "lb"), list(op = "list"),
edited = paste(
  "Rewrote .metadata/manifest.json in the v1 shape: `artifacts` renamed to",
  "`tables`, every `kind` and the `schema_version` removed, only dm and lb kept."
),
edit = function(s) {
  path <- file.path(s, "datom", ".metadata", "manifest.json")
  m <- jsonlite::read_json(path)
  tables <- lapply(m$artifacts[c("dm", "lb")], function(e) { e$kind <- NULL; e })
  v1 <- list(project_name = m$project_name, tables = tables,
             summary = list(total_tables = 2L), updated_at = m$updated_at)
  jsonlite::write_json(v1, path, auto_unbox = TRUE, pretty = TRUE, digits = NA)
})

make_case("governance-marker", paste(
  "A project whose storage holds a governance marker. The read succeeds with a",
  "warning that the supplied location may go stale after a data move."
), "dm", list(op = "read_table", name = "dm", version = NULL),
edited = "Wrote a valid .metadata/governance.json by hand.",
edit = function(s) {
  jsonlite::write_json(
    list(gov_repo_url = "https://github.com/example/acme-gov",
         gov_storage = list(type = "s3", root = "acme-gov-bucket",
                            prefix = "gov", region = "us-east-1"),
         attached_at = "2026-01-01T00:00:00Z"),
    file.path(s, "datom", ".metadata", "governance.json"),
    auto_unbox = TRUE, pretty = TRUE
  )
})

# Refusals.
make_case("refuse-schema-unsupported", "Metadata declares a newer format than supported",
          "dm", list(op = "read_table", name = "dm", version = NULL),
          error = "schema_unsupported",
          edited = "schema_version set to 3 in dm's metadata.json.",
          edit = function(s) edit_text(file.path(meta_dir(s, "dm"), "metadata.json"),
                                       "\"schema_version\": 2", "\"schema_version\": 3"))

make_case("refuse-schema-invalid", "Metadata declares a malformed format number",
          "dm", list(op = "read_table", name = "dm", version = NULL),
          error = "schema_invalid",
          edited = "schema_version set to 2.5 in dm's metadata.json.",
          edit = function(s) edit_text(file.path(meta_dir(s, "dm"), "metadata.json"),
                                       "\"schema_version\": 2", "\"schema_version\": 2.5"))

make_case("refuse-set-read-as-table", "A set read as a table", "trial_product",
          list(op = "read_table", name = "trial_product", version = NULL),
          error = "kind_mismatch")

make_case("refuse-table-read-as-set", "A table read as a set", "dm",
          list(op = "read_set", name = "dm", version = NULL),
          error = "kind_mismatch")

make_case("refuse-table-integrity", paste(
  "A table's data file with one byte changed. Refused before parsing."
), "dm", list(op = "read_table", name = "dm", version = NULL),
error = "integrity_mismatch",
edited = "Flipped every bit of byte 64 of dm's current parquet file.",
edit = function(s) {
  flip_byte(file.path(s, "datom", "dm", paste0(dm_current_sha, ".parquet")), 64L)
})

make_case("refuse-set-integrity", paste(
  "A set's payload with changed bytes. The payload is still valid JSON, so",
  "only the hash check catches it."
), "trial_product", list(op = "read_set", name = "trial_product", version = NULL),
error = "integrity_mismatch",
edited = "Changed \"Final cut\" to \"Final cuT\" in the current set payload.",
edit = function(s) {
  sha <- current_meta("trial_product")$data_sha
  edit_text(file.path(s, "datom", "trial_product", paste0(sha, ".json")),
            "Final cut", "Final cuT")
})

make_case("refuse-document-sha-missing", "A set version with no document_sha",
          "trial_product", list(op = "read_set", name = "trial_product", version = NULL),
          error = "document_sha_missing",
          edited = "Removed the document_sha line from the set's metadata.json.",
          edit = function(s) edit_text(file.path(meta_dir(s, "trial_product"),
                                                 "metadata.json"),
                                       "\"document_sha\":", NULL))

make_case("refuse-set-member-malformed", paste(
  "A set payload whose member id has a version that is not a string. The",
  "payload's recorded hash was updated, so the hash check passes and the",
  "member check is what refuses it."
), "trial_product", list(op = "read_set", name = "trial_product", version = NULL),
error = "set_member_malformed",
edited = paste(
  "In the current payload, the first member's version became the number 42;",
  "document_sha in metadata.json updated to the edited payload's hash."
),
edit = function(s) {
  sha <- current_meta("trial_product")$data_sha
  payload <- file.path(s, "datom", "trial_product", paste0(sha, ".json"))
  first <- v_set_first_member_version
  edit_text(payload, sprintf("\"version\": \"%s\"", first), "\"version\": 42")
  meta <- file.path(meta_dir(s, "trial_product"), "metadata.json")
  old <- jsonlite::read_json(meta)$document_sha
  edit_text(meta, old, sha256_file(payload))
})

make_case("refuse-member-ambiguous", paste(
  "Fetch a member by a name that two members share, without narrowing."
), c("trial_product", "dm"), list(op = "fetch_member", set = "trial_product",
                                  set_version = NULL, member = "dm", tags = NULL,
                                  version = NULL),
error = "member_ambiguous")

make_case("refuse-member-not-found", "Fetch a member the set does not have",
          "trial_product", list(op = "fetch_member", set = "trial_product",
                                set_version = NULL, member = "ae", tags = NULL,
                                version = NULL),
          error = "member_not_found")

make_case("refuse-version-not-found", "A version not in the history", "dm",
          list(op = "read_table", name = "dm",
               version = setdiff(c("ffffffff", "eeeeeeee", "dddddddd"),
                                 substr(v_dm, 1L, 8L))[[1L]]),
          error = "version_not_found")

make_case("refuse-version-ambiguous", paste(
  "A version prefix that matches two versions: one character shared by the",
  "first characters of two of vt's versions."
), "vt", list(op = "read_table", name = "vt", version = vt_shared),
error = "version_ambiguous")

make_case("refuse-invalid-address", paste(
  "A data address in metadata that isn't 6 to 64 lowercase hex characters.",
  "Refused before any storage path is built."
), "dm", list(op = "read_table", name = "dm", version = NULL),
error = "invalid_address",
edited = "data_sha set to \"../x\" in dm's metadata.json.",
edit = function(s) edit_text(file.path(meta_dir(s, "dm"), "metadata.json"),
                             sprintf("\"data_sha\": \"%s\"", dm_current_sha),
                             "\"data_sha\": \"../x\""))

cat(sprintf("\n%d new case(s) in %s\n", new_cases, out_dir))
unlink(root, recursive = TRUE)
