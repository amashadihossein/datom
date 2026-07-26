# dev/e2e-cv1-identity.R
# -----------------------------------------------------------------------------
# datom-cv1 identity walkthrough / smoke test -- FULLY OFFLINE.
#
# Unlike the other dev/e2e-solo-*.R scripts, this one needs NO GitHub PAT, no
# AWS, and no network: it builds a real git repo with a real LOCAL BARE REMOTE
# plus a real `backend = "local"` store inside tempdir(). Everything from
# datom_sync() inward is the production code path -- real change
# classification, real parquet upload, real metadata.json /
# version_history.json, real read-back with integrity verification.
#
# Shows, in three sections:
#   1. the table contract -- datom_check_hashable() on a clean and an
#      offending table (the recourse strings datom_write() aborts with)
#   2. what is and is not identity -- container class, storage type, factor
#      levels, tzone, NaN/-0, NA_real_, row/column order, NFC vs NFD, last-bit
#      doubles; each line labelled with the expected verdict
#   3. a real project -- first sync (full) -> re-export with identical content
#      (metadata_only, parquet_sha carried forward, no second object) ->
#      untouched re-scan (skipped before parse) -> new content (full, second
#      object) -> re-sync of the older export (no duplicate version, no
#      re-upload) -> a flipped byte in the stored parquet (read refuses)
#
# It is also a smoke test: every claim is asserted, and the script stops
# non-zero if any of them fails.
#
#   Rscript ~/projects/dev/datom/dev/e2e-cv1-identity.R
#   # or interactively:
#   source("~/projects/dev/datom/dev/e2e-cv1-identity.R")
#
# CAVEAT -- what this does NOT exercise. The connection is assembled directly
# as a `datom_conn` (the same shortcut tests/testthat/test-identity-contract.R
# uses) rather than built by datom_init_repo() + datom_get_conn(). That is what
# removes the PAT requirement, and it means project.yaml handling, GitHub repo
# creation, and ref resolution are skipped. For those, use
# dev/e2e-solo-local.R, which goes through the public entry points and does
# need a PAT.
#
# Artefacts live in tempdir() and vanish with the R session; the path is
# printed at the end if you want to poke at it first.
# -----------------------------------------------------------------------------

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("datom_check_hashable")) {
  devtools::load_all(.datom_pkg_dir, quiet = TRUE)
}

options(crayon.enabled = FALSE)

.failures <- 0L
hr <- function(x) cat("\n\n==========", x, "==========\n")

# Assert-and-report: prints the claim with its verdict so the transcript is
# readable, and records a failure instead of aborting so one bad line does not
# hide the rest of the walkthrough.
claim <- function(label, actual, expected) {
  # unname(): fs:: predicates return named logicals, which identical() would
  # otherwise reject against a bare TRUE/FALSE.
  actual <- unname(actual)
  ok <- identical(actual, expected)
  if (!ok) .failures <<- .failures + 1L
  cat(sprintf("%-46s %-9s %s\n", label,
              if (is.logical(actual)) actual else as.character(actual),
              if (ok) "" else paste0("<< FAIL, expected ", expected)))
  invisible(ok)
}


# --- 1. The table contract ---------------------------------------------------
hr("1. The table contract: datom_check_hashable()")

clean <- data.frame(
  id    = 1:3,
  score = c(1.5, 2.5, 3.5),
  grp   = factor(c("x", "y", "x")),
  day   = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03"))
)
clean_report <- datom_check_hashable(clean)

messy <- data.frame(id = 1:2)
messy$notes <- list(c("a", "b"), "c")                 # list column
messy$when  <- as.POSIXlt("2026-01-01", tz = "UTC")   # POSIXlt, not POSIXct
messy$z     <- c(1 + 2i, 3 + 4i)                      # complex
messy_report <- datom_check_hashable(messy)

cat("\n")
claim("clean table: all columns ok",
      all(clean_report$status == "ok"), TRUE)
claim("messy table: 3 offenders flagged",
      sum(messy_report$status == "unsupported"), 3L)

# datom_write() refuses the same table with the same strings and leaves no
# partial state behind -- asserted in step 3g, once a real project exists.


# --- 2. What is and is not identity -----------------------------------------
hr("2. What is and is not identity")

sha <- function(d) .datom_canonical_hash(d)$data_sha
same <- function(label, a, b, expected) {
  verdict <- if (identical(sha(a), sha(b))) "SAME" else "DIFFERENT"
  ok <- identical(verdict, expected)
  if (!ok) .failures <<- .failures + 1L
  cat(sprintf("%-46s %-10s %s\n", label, verdict,
              if (ok) paste0("(expected ", expected, ")")
              else paste0("<< FAIL, expected ", expected)))
}

base <- data.frame(id = 1:3, v = c("a", "b", "c"), stringsAsFactors = FALSE)

same("data.frame vs tibble (same values)",
     base, tibble::as_tibble(base), "SAME")
same("integer 1L vs double 1 storage",
     data.frame(x = 1:3), data.frame(x = c(1, 2, 3)), "SAME")
same("factor vs its character values",
     data.frame(g = factor(c("a", "b"))),
     data.frame(g = c("a", "b"), stringsAsFactors = FALSE), "SAME")
same("factor with an extra unused level",
     data.frame(g = factor(c("a", "b"))),
     data.frame(g = factor(c("a", "b"), levels = c("a", "b", "z"))), "SAME")
same("same instant, different tzone",
     data.frame(t = as.POSIXct("2026-01-01 12:00", tz = "UTC")),
     data.frame(t = as.POSIXct("2026-01-01 07:00", tz = "America/New_York")),
     "SAME")
same("0/0 vs NaN", data.frame(x = 0 / 0), data.frame(x = NaN), "SAME")
same("-0 vs +0", data.frame(x = -0), data.frame(x = 0), "SAME")
same("NA_real_ vs NaN",
     data.frame(x = NA_real_), data.frame(x = NaN), "DIFFERENT")
same("row order", base, base[c(3, 1, 2), ], "DIFFERENT")
same("column order", base, base[, c("v", "id")], "DIFFERENT")
same("NFC vs NFD (same-looking text)",
     data.frame(s = intToUtf8(0x00E9)),               # e-acute, composed
     data.frame(s = intToUtf8(c(0x0065, 0x0301))),    # e + combining acute
     "DIFFERENT")
same("last-bit double difference",
     data.frame(x = 0.1 + 0.2), data.frame(x = 0.3), "DIFFERENT")
same("same values, different column name",
     data.frame(x = 1:3), data.frame(y = 1:3), "DIFFERENT")

cat("\nThe line is drawn at platform non-determinism, not at human\n",
    "equivalence: where identical logical values can get different bytes for\n",
    "reasons outside your control (NaN payload bits, signed zero, storage type\n",
    "after a round-trip) datom canonicalizes; where the difference is a real\n",
    "property of your data (row order, NFC vs NFD) it is preserved.\n", sep = "")


# --- 3. A real project ------------------------------------------------------
hr("3. A real project: sync, re-export, revert, integrity")

root      <- tempfile("datom_cv1_e2e_")
repo_dir  <- fs::path(root, "repo")
store_dir <- fs::path(root, "store")
bare_dir  <- fs::path(root, "remote.git")
fs::dir_create(c(repo_dir, store_dir, bare_dir))

git2r::init(bare_dir, bare = TRUE)
repo <- git2r::init(repo_dir)
git2r::config(repo, user.name = "Tire Kicker", user.email = "you@example.com")
writeLines("init", fs::path(repo_dir, "README.md"))
git2r::add(repo, "README.md")
git2r::commit(repo, "Initial commit")
git2r::remote_add(repo, "origin", as.character(bare_dir))
git2r::push(repo, "origin", refspec = "refs/heads/master", set_upstream = TRUE)

# See the CAVEAT in the header: assembled directly so no PAT is needed.
conn <- structure(
  list(project_name = "CV1_E2E", backend = "local",
       root = as.character(store_dir), prefix = NULL, region = NULL,
       client = NULL, path = as.character(repo_dir), role = "developer",
       endpoint = NULL, gov_root = NULL, gov_prefix = NULL,
       gov_region = NULL, gov_backend = NULL, gov_client = NULL),
  class = "datom_conn"
)

input_dir <- fs::path(repo_dir, "input_files")
fs::dir_create(input_dir)
csv <- fs::path(input_dir, "dm.csv")
dm_m1 <- datom_example_data("dm", cutoff_date = "2026-01-28")
dm_m2 <- datom_example_data("dm", cutoff_date = "2026-02-28")

stored <- function() {
  dir <- fs::path(store_dir, "datom", "dm")
  if (!fs::dir_exists(dir)) return(character())
  fs::path_file(fs::dir_ls(dir, type = "file", glob = "*.parquet"))
}
meta <- function() jsonlite::read_json(fs::path(repo_dir, "dm", "metadata.json"))
hist <- function() jsonlite::read_json(fs::path(repo_dir, "dm", "version_history.json"))
versions <- function() vapply(hist(), function(e) e$version, character(1))
sync <- function() invisible(datom_sync(conn, datom_sync_manifest(conn)))

cat("\n--- 3a. First sync: new content -> full ---\n")
write.csv(dm_m1, csv, row.names = FALSE)
sync()
m1 <- meta()
cat("data_sha         :", substr(m1$data_sha, 1, 16), "\n")
cat("parquet_sha      :", substr(m1$parquet_sha, 1, 16), "\n")
cat("original_file_sha:", substr(m1$original_file_sha, 1, 16), "\n")
claim("object addressed by data_sha",
      stored(), paste0(m1$data_sha, ".parquet"))
claim("hash_algo recorded", m1$hash_algo, "datom-cv1")

cat("\n--- 3b. Re-export: same content, different file bytes -> metadata_only ---\n")
# quote = FALSE moves the file's bytes without changing what it parses to.
write.csv(dm_m1, csv, row.names = FALSE, quote = FALSE)
sync()
m2 <- meta()
claim("data_sha unchanged", identical(m2$data_sha, m1$data_sha), TRUE)
claim("original_file_sha changed",
      !identical(m2$original_file_sha, m1$original_file_sha), TRUE)
claim("parquet_sha carried forward",
      identical(m2$parquet_sha, m1$parquet_sha), TRUE)
claim("versions recorded", length(hist()), 2L)
claim("still ONE object in store", length(stored()), 1L)

cat("\n--- 3c. Re-scan with nothing touched -> skipped before parse ---\n")
scan3 <- datom_sync_manifest(conn)
claim("manifest status", scan3$status, "unchanged")
claim("sync result", datom_sync(conn, scan3)$result, "skipped")

cat("\n--- 3d. Real content change -> full, second object ---\n")
write.csv(dm_m2, csv, row.names = FALSE)
sync()
claim("versions recorded", length(hist()), 3L)
claim("objects in store", length(stored()), 2L)

cat("\n--- 3e. Re-sync the ORIGINAL month-1 export (revert) ---\n")
v_before <- versions()
write.csv(dm_m1, csv, row.names = FALSE)
sync()
claim("no duplicate version appended", length(versions()), length(v_before))
claim("month-1 version still present once",
      sum(versions() == v_before[length(v_before)]), 1L)
claim("no re-upload (still two objects)", length(stored()), 2L)
claim("month-1 version reads back",
      nrow(datom_read(conn, "dm", version = v_before[length(v_before)])),
      nrow(dm_m1))
claim("current pointer reads back month-1 content",
      nrow(datom_read(conn, "dm")), nrow(dm_m1))

cat("\n--- 3f. Flip one byte in the stored parquet -> the read refuses ---\n")
obj <- fs::path(store_dir, "datom", "dm", paste0(meta()$data_sha, ".parquet"))
bytes <- readBin(obj, "raw", fs::file_size(obj))
mid <- floor(length(bytes) / 2)
bytes[mid] <- as.raw(xor(as.integer(bytes[mid]), 1L))
writeBin(bytes, obj)
tamper <- tryCatch(datom_read(conn, "dm"), error = function(e) conditionMessage(e))
cat(tamper, "\n")
claim("read aborts on integrity failure",
      grepl("integrity check", paste(tamper, collapse = " ")), TRUE)

cat("\n--- 3g. An unhashable table is refused, leaving no state ---\n")
head_before <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
objects_before <- length(fs::dir_ls(fs::path(store_dir, "datom"), recurse = TRUE,
                                    type = "file"))
refusal <- tryCatch(datom_write(conn, data = messy, name = "messy"),
                    error = function(e) conditionMessage(e))
cat(paste(refusal, collapse = "\n"), "\n")
claim("write aborts naming the offenders",
      grepl("not hashable", paste(refusal, collapse = " ")), TRUE)
claim("no table directory created",
      fs::dir_exists(fs::path(repo_dir, "messy")), FALSE)
claim("no git commit made",
      as.character(git2r::revparse_single(repo, "HEAD")$sha), head_before)
claim("nothing written to storage",
      length(fs::dir_ls(fs::path(store_dir, "datom"), recurse = TRUE,
                        type = "file")),
      objects_before)

cat("\n--- store layout (one object per distinct content) ---\n")
fs::dir_tree(store_dir)


# --- summary ----------------------------------------------------------------
hr("summary")
if (.failures == 0L) {
  cat("All claims held.\n")
  cat("Project left at:", root, "\n")
} else {
  cat(.failures, "claim(s) FAILED -- see the << FAIL markers above.\n")
  cat("Project left at:", root, "\n")
  stop("e2e-cv1-identity: ", .failures, " claim(s) failed.", call. = FALSE)
}
