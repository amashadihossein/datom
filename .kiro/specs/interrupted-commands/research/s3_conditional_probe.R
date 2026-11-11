# Real-S3 probe for the data-file upload of the interrupted-commands spec (task 1).
#
# Checks against real AWS S3 what the unit tests can only mock:
#   - an "only if absent" upload (IfNoneMatch = "*") of a key that exists is refused
#     with HTTP 412, and datom's upload reports that as "exists";
#   - an object put with ChecksumSHA256 comes back from head_object (ChecksumMode =
#     "ENABLED") with ChecksumType FULL_OBJECT and the file's SHA-256, so datom can
#     read a stored file's hash without downloading it;
#   - S3 checks the ChecksumSHA256 datom sends (a wrong one is refused), so the
#     header really reaches S3.
# Runs on three paws version pairs, each in its own R process: the ones installed
# here, the declared minimum (paws.storage 0.8.0 with paws.common 0.8.0), and CRAN's
# current ones. The last two come from throwaway libraries under /tmp, installed on
# first run; your own R library is not touched.
#
# Credentials come from the environment and are passed to datom explicitly; none is
# in this script. Set them first, for example from your keyring:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (and AWS_SESSION_TOKEN if you use one)
# Optional: DATOM_PROBE_BUCKET (default "datom-test"), DATOM_PROBE_REGION
# (default "us-east-1").
#
# Everything is written under one fixed prefix, datom-probe/s3-conditional/datom/,
# which is deleted at the start (leftovers from a failed run) and at the end.
#
# Run it either way, from any working directory; datom is loaded from the repo this
# script sits in, not from the working directory:
#   Rscript ~/projects/dev/datom/.kiro/specs/interrupted-commands/research/s3_conditional_probe.R
#   source("~/projects/dev/datom/.kiro/specs/interrupted-commands/research/s3_conditional_probe.R")
#
# A pair counts as passed only when its child process prints a result line saying
# every check passed. A child that never got that far is reported as DID NOT RUN.
#
# DATOM_PROBE_FAKE_S3=1 swaps real S3 for an in-memory stand-in that answers as AWS
# does for the calls made here. That checks this script's own walk offline (no
# credentials needed); it says nothing about S3.
#
# The work is inside main(): on.exit() at the top level of an Rscript never runs.

PAIRS <- list(
  installed = NA_character_,
  minimum   = "/tmp/datom-paws-floor",
  current   = "/tmp/datom-paws-current"
)
PREFIX <- "datom-probe/s3-conditional"

ensure_throwaway_libs <- function() {
  arch <- "https://cran.r-project.org/src/contrib/Archive"
  if (!dir.exists(file.path(PAIRS$minimum, "paws.storage"))) {
    dir.create(PAIRS$minimum, showWarnings = FALSE)
    install.packages(
      c(file.path(arch, "paws.common/paws.common_0.8.0.tar.gz"),
        file.path(arch, "paws.storage/paws.storage_0.8.0.tar.gz")),
      lib = PAIRS$minimum, repos = NULL, type = "source", quiet = TRUE
    )
  }
  if (!dir.exists(file.path(PAIRS$current, "paws.storage"))) {
    dir.create(PAIRS$current, showWarnings = FALSE)
    install.packages(
      c("paws.common", "paws.storage"), lib = PAIRS$current,
      repos = "https://cloud.r-project.org", quiet = TRUE, dependencies = FALSE
    )
  }
}

# --- one run, in a child process ---------------------------------------------

probe_one <- function(lib, repo_root) {
  if (!is.na(lib)) .libPaths(c(lib, .libPaths()))
  suppressMessages(devtools::load_all(repo_root, quiet = TRUE))
  ns <- asNamespace("datom")
  versions <- sprintf("paws.storage %s / paws.common %s",
                      utils::packageVersion("paws.storage"),
                      utils::packageVersion("paws.common"))

  bucket <- Sys.getenv("DATOM_PROBE_BUCKET", "datom-test")
  region <- Sys.getenv("DATOM_PROBE_REGION", "us-east-1")

  if (fake_s3_requested()) {
    client <- fake_s3_client()
    versions <- paste(versions, "(FAKE S3, offline)")
  } else {
    token <- Sys.getenv("AWS_SESSION_TOKEN")
    client <- ns$.datom_s3_client(
      access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
      secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
      region = region,
      session_token = if (nzchar(token)) token else NULL
    )
  }

  run_checks(ns, client, bucket, region, versions)
}

fake_s3_requested <- function() identical(Sys.getenv("DATOM_PROBE_FAKE_S3"), "1")

# An in-memory stand-in for the S3 calls this script makes, answering as AWS does:
# 404 for a missing key, 412 for IfNoneMatch on a stored key, 400 for a wrong
# ChecksumSHA256, and the checksum back with ChecksumType FULL_OBJECT.
fake_s3_client <- function() {
  store <- new.env()
  err <- function(status, code) {
    family <- (status %/% 100) * 100
    structure(
      list(message = sprintf("%s (HTTP %d). Fake S3.", code, status), call = NULL,
           status_code = status),
      class = c("paws_error", paste0("http_", unique(c(status, family, "error"))),
                "error", "condition")
    )
  }
  b64sha <- function(raw) {
    jsonlite::base64_enc(digest::digest(raw, algo = "sha256", serialize = FALSE, raw = TRUE))
  }
  list(
    head_object = function(Bucket, Key, ChecksumMode = NULL) {
      obj <- store[[Key]]
      if (is.null(obj)) stop(err(404, "NotFound"))
      enabled <- identical(ChecksumMode, "ENABLED") && length(obj$sha) > 0L
      list(ContentLength = length(obj$body),
           ChecksumSHA256 = if (enabled) obj$sha else character(0),
           ChecksumType = if (enabled) "FULL_OBJECT" else character(0))
    },
    put_object = function(Bucket, Key, Body, IfNoneMatch = NULL, ChecksumSHA256 = NULL, ...) {
      if (identical(IfNoneMatch, "*") && !is.null(store[[Key]])) {
        stop(err(412, "PreconditionFailed"))
      }
      if (!is.null(ChecksumSHA256) && !identical(ChecksumSHA256, b64sha(Body))) {
        stop(err(400, "BadDigest"))
      }
      store[[Key]] <- list(body = Body, sha = ChecksumSHA256 %||% character(0))
      list()
    },
    get_object = function(Bucket, Key) {
      obj <- store[[Key]]
      if (is.null(obj)) stop(err(404, "NoSuchKey"))
      list(Body = obj$body)
    },
    list_objects_v2 = function(Bucket, Prefix, MaxKeys, ContinuationToken = NULL) {
      keys <- Filter(function(k) startsWith(k, Prefix), ls(store, all.names = TRUE))
      list(Contents = lapply(keys, function(k) list(Key = k)), IsTruncated = FALSE)
    },
    delete_objects = function(Bucket, Delete) {
      for (obj in Delete$Objects) rm(list = obj$Key, envir = store)
      list()
    }
  )
}

# The checks themselves, given a loaded datom namespace and an S3 client.
run_checks <- function(ns, client, bucket, region, versions) {
  # Count downloads, so a hash read from S3's checksum can be told from one
  # computed after a download.
  n_get <- 0L
  counted <- client
  counted$get_object <- function(...) {
    n_get <<- n_get + 1L
    client$get_object(...)
  }
  conn <- structure(
    list(project_name = "probe", backend = "s3", root = bucket, prefix = PREFIX,
         region = region, client = counted, path = NULL, role = "reader"),
    class = "datom_conn"
  )
  full <- function(key) ns$.datom_build_storage_key(PREFIX, key)

  ns$.datom_s3_delete_prefix(conn, NULL)
  on.exit(try(ns$.datom_s3_delete_prefix(conn, NULL), silent = TRUE), add = TRUE)

  dir <- tempfile("s3-probe-")
  dir.create(dir)
  file_a <- file.path(dir, "a.bin")
  file_b <- file.path(dir, "b.bin")
  writeBin(as.raw(sample(0:255, 4096, replace = TRUE)), file_a)
  writeBin(as.raw(sample(0:255, 4096, replace = TRUE)), file_b)
  sha_a <- digest::digest(file = file_a, algo = "sha256")
  sha_b <- digest::digest(file = file_b, algo = "sha256")
  key <- "probe/a.parquet"

  rows <- list()
  record <- function(check, expected, observed) {
    rows[[length(rows) + 1L]] <<- data.frame(
      check = check, expected = expected, observed = observed,
      ok = identical(expected, observed), stringsAsFactors = FALSE
    )
  }
  attempt <- function(expr) tryCatch(expr, error = function(e) e)
  classes <- function(x) if (inherits(x, "error")) paste(class(x), collapse = " ") else "no error"

  # 1. First upload of an absent key.
  record("first upload_absent()", "uploaded",
         as.character(attempt(ns$.datom_s3_upload_absent(conn, file_a, key))))

  # 2. What S3 keeps with the object.
  head <- attempt(client$head_object(Bucket = bucket, Key = full(key),
                                     ChecksumMode = "ENABLED"))
  type <- if (inherits(head, "error")) conditionMessage(head) else paste(head$ChecksumType, collapse = "")
  stored <- if (inherits(head, "error")) NA_character_ else
    ns$.datom_s3_whole_file_sha256(head$ChecksumSHA256, head$ChecksumType)
  record("head_object ChecksumType", "FULL_OBJECT", type)
  record("head_object ChecksumSHA256 is the file's SHA-256", sha_a, stored %||% "not trusted")

  # 3. datom's stored-hash read uses it without downloading.
  n_get <- 0L
  record(".datom_s3_object_sha256()", sha_a,
         as.character(attempt(ns$.datom_s3_object_sha256(conn, key))))
  record("downloads made by it", "0", as.character(n_get))

  # 4. A second upload with different bytes: caught by the existence check.
  record("second upload_absent(), other bytes", "exists",
         as.character(attempt(ns$.datom_s3_upload_absent(conn, file_b, key))))

  # 5. The conditional put itself, past the check: S3 refuses it with 412.
  body_b <- readBin(file_b, "raw", file.size(file_b))
  put <- attempt(client$put_object(Bucket = bucket, Key = full(key), Body = body_b,
                                   IfNoneMatch = "*"))
  record("raw put_object(IfNoneMatch = \"*\") on a stored key: has class http_412",
         "TRUE", as.character(inherits(put, "http_412")))
  cat("  [5] condition classes:", classes(put), "\n")

  # 6. datom's 412 path, with its existence check made to miss the stored file.
  missed <- attempt(testthat::with_mocked_bindings(
    ns$.datom_s3_upload_absent(conn, file_b, key),
    .datom_s3_exists = function(...) FALSE,
    .package = "datom"
  ))
  record("upload_absent() past a missed check (412 path)", "exists", as.character(missed))
  n_get <- 0L
  body <- attempt(client$get_object(Bucket = bucket, Key = full(key))$Body)
  record("stored bytes after both refused uploads", sha_a,
         if (inherits(body, "error")) conditionMessage(body) else
           digest::digest(body, algo = "sha256", serialize = FALSE))

  # 7. S3 checks the checksum datom sends: a wrong one is refused.
  wrong <- jsonlite::base64_enc(digest::digest(body_b, algo = "sha256",
                                               serialize = FALSE, raw = TRUE))
  body_a <- readBin(file_a, "raw", file.size(file_a))
  bad <- attempt(client$put_object(Bucket = bucket, Key = full("probe/wrong.bin"),
                                   Body = body_a, ChecksumSHA256 = wrong))
  record("put_object with a wrong ChecksumSHA256 is refused (http_400)", "TRUE",
         as.character(inherits(bad, "http_400")))
  cat("  [7] condition:", if (inherits(bad, "error")) conditionMessage(bad) else "no error", "\n")

  # 8. Clean up, and check nothing is left.
  ns$.datom_s3_delete_prefix(conn, NULL)
  left <- attempt(ns$.datom_s3_list_objects(conn, ""))
  record("objects left under the prefix", "0",
         if (inherits(left, "error")) conditionMessage(left) else as.character(length(left)))

  out <- do.call(rbind, rows)
  cat("\n", versions, "\n", sep = "")
  for (i in seq_len(nrow(out))) {
    cat(sprintf("  %s  %s\n", if (out$ok[[i]]) "PASS" else "FAIL", out$check[[i]]))
    if (!out$ok[[i]]) {
      cat(sprintf("        expected: %s\n        observed: %s\n",
                  out$expected[[i]], out$observed[[i]]))
    }
  }
  cat(sprintf("RESULT %s: %s (%d of %d checks passed)\n", versions,
              if (all(out$ok)) "ALL PASS" else "FAILURES", sum(out$ok), nrow(out)))
  invisible(all(out$ok))
}

# --- driver ------------------------------------------------------------------

# This script's own path, whether it was run with Rscript or source(). source()
# keeps the path in its frame as `ofile`; Rscript passes it as --file=.
this_script <- function() {
  for (i in rev(seq_len(sys.nframe()))) {
    ofile <- sys.frame(i)$ofile
    if (is.character(ofile) && length(ofile) == 1L) return(normalizePath(ofile))
  }
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) == 1L) return(normalizePath(sub("^--file=", "", file_arg)))
  stop("Cannot tell where this script is. Run it with Rscript or source().", call. = FALSE)
}

# The datom repo this script sits in: four folders up from research/.
repo_root_of <- function(script) {
  root <- normalizePath(file.path(dirname(script), "..", "..", "..", ".."))
  desc <- file.path(root, "DESCRIPTION")
  if (!file.exists(desc) || !identical(unname(read.dcf(desc)[1, "Package"]), "datom")) {
    stop("Expected the datom repo at ", root, call. = FALSE)
  }
  root
}

run_pair <- function(name, lib, script, repo_root) {
  cat("\n==== paws pair:", name, "====\n")
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript,
    c(shQuote(script), "--one", shQuote(if (is.na(lib)) "installed" else lib),
      shQuote(repo_root)),
    stdout = TRUE, stderr = TRUE
  ))
  cat(out, sep = "\n")
  result <- grep("^RESULT ", out, value = TRUE)
  if (length(result) != 1L) return("DID NOT RUN (no result line; see output above)")
  sub("^RESULT ", "", result)
}

main <- function(args) {
  if (length(args) >= 1L && identical(args[[1]], "--one")) {
    lib <- if (args[[2]] == "installed") NA_character_ else args[[2]]
    ok <- probe_one(lib, args[[3]])
    quit(save = "no", status = if (isTRUE(ok)) 0L else 1L)
  }

  no_creds <- !nzchar(Sys.getenv("AWS_ACCESS_KEY_ID")) ||
    !nzchar(Sys.getenv("AWS_SECRET_ACCESS_KEY"))
  if (no_creds && !fake_s3_requested()) {
    stop("Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in the environment first.",
         call. = FALSE)
  }
  script <- this_script()
  repo_root <- repo_root_of(script)
  ensure_throwaway_libs()

  results <- vapply(names(PAIRS), function(nm) {
    run_pair(nm, PAIRS[[nm]], script, repo_root)
  }, character(1))

  cat("\n==== summary ====\n")
  cat(sprintf("  %-9s %s\n", names(results), results), sep = "")
  invisible(results)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

main(commandArgs(TRUE))
