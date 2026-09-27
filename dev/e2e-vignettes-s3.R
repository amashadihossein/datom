# dev/e2e-vignettes-s3.R
# -----------------------------------------------------------------------------
# Runs the code of vignettes/start-on-s3.Rmd and then vignettes/citable-sets.Rmd,
# in one R session, exactly as a reader would, and saves what every chunk prints.
# The saved transcript is where the vignettes' `#>` output blocks come from.
#
# WHY IT RUNS THE VIGNETTES' OWN CODE rather than a copy: the vignettes are
# `eval = FALSE` (they need credentials CRAN does not have), so nothing else in
# the repo checks that their printed output matches their code. A script holding
# its own copy of the code would drift from the vignettes and still pass. This
# one pulls the chunks out of the .Rmd files with knitr::purl() and runs those.
#
# Chunks handled by name, not run as written:
#   keyring-setup, secrets   skipped. macOS authorises keychain access per
#                            binary, so keyring cannot prompt under Rscript
#                            (dev/engineering-notes.md). This reads the
#                            environment instead.
#   settings                 run, then `bucket` and `region` are overridden from
#                            DATOM_E2E_BUCKET / DATOM_E2E_REGION. The bucket in
#                            the vignette is illustrative.
#   derive-script            written to workdir_liver_safety/R/derive_liver_flags.R
#                            (the vignette tells the reader to save it there);
#                            the next chunk source()s it.
#   teardown-imported        skipped: the walk continues into citable-sets.
#   teardown                 (citable-sets, both projects) run last, and only when
#                            the walk succeeded and DATOM_E2E_KEEP is unset.
#
# TWO BACKENDS:
#
#   DATOM_E2E_BACKEND=local  offline. A local folder stands in for S3 and bare git
#                            repos for GitHub, by masking datom_store_s3(),
#                            datom_store() and datom_init_repo() in the chunks'
#                            environment. Checks the runner and the chunk logic;
#                            it CANNOT check S3 or the GitHub API, which is the
#                            point of the real run.
#   DATOM_E2E_BACKEND=s3     (default) real GitHub repos, real bucket.
#
# NEEDS (s3), as environment variables:
#   GITHUB_PAT             repo + delete_repo scope. The GitHub account is the
#                          token's own (asked of the API), not gh's.
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   DATOM_E2E_BUCKET       an existing bucket. USE A SCRATCH BUCKET: the pre-clean
#                          and the teardown delete `imported/datom/` and
#                          `liver-safety/datom/` in it. Nothing else is touched.
#   DATOM_E2E_REGION       optional, default us-east-1.
#
# NAMES ARE THE VIGNETTES' OWN (read from their settings chunks), so the repos
# are `<you>/study001-imported` and `<you>/study001-liver-safety`. A run DELETES
# any existing repos with those names before it starts -- fixed names plus
# delete-if-exists means a failed run leaves at most one set of leftovers and the
# next run clears it.
#
# RUN, sourced from an R session (the way to go if your secrets are in a
# keychain -- the prompt happens once, in your session):
#
#   Sys.setenv(
#     AWS_ACCESS_KEY_ID     = keyring::key_get(...),
#     AWS_SECRET_ACCESS_KEY = keyring::key_get(...),
#     GITHUB_PAT            = keyring::key_get(...),
#     DATOM_E2E_BUCKET      = "my-scratch-bucket"
#   )
#   source("~/projects/dev/datom/dev/e2e-vignettes-s3.R")
#
# Sourced, it leaves `run_env` behind (every object the vignettes created) and,
# on failure, stops with an error rather than ending the session. It restores the
# output options it changes.
#
# Or from a terminal, with the variables already exported:
#   DATOM_E2E_BACKEND=local Rscript dev/e2e-vignettes-s3.R < /dev/null
#
# `< /dev/null` is not decoration: run with a terminal or pipe on stdin, the
# Rscript process was seen to finish the walk, print its result, and then not
# exit. Cause not pinned down; closing stdin makes it exit every time.
#
# ON FAILURE nothing is torn down, so the state can be inspected; the next run's
# pre-clean removes it. The transcript up to the failing chunk is still written.
#
# OUTPUT: <DATOM_E2E_OUT>/transcript-<backend>.md, one section per chunk, in the
# vignettes' own `#>` format. Default DATOM_E2E_OUT is ../datom-test/vignettes-e2e
# beside the package. Exit status is non-zero on any failure.
# -----------------------------------------------------------------------------

# Sourced, or run with Rscript. The two differ in how the script finds itself
# and in how a failure ends: under Rscript it exits with status 1; sourced, it
# stops with an error and leaves your session running.
.sourced <- sys.nframe() > 0L
.script_path <- local({
  of <- NULL
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) break
  }
  if (is.null(of)) {
    of <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  }
  if (length(of) == 1L) of else NA_character_
})
pkg_dir <- if (!is.na(.script_path)) {
  normalizePath(file.path(dirname(.script_path), ".."))
} else {
  path.expand("~/projects/dev/datom")
}

devtools::load_all(pkg_dir, quiet = TRUE)
source(file.path(pkg_dir, "dev", "dev-sandbox.R"))

# ASCII output, no colour, so transcripts paste into ASCII-only vignettes.
# Restored at the end, so sourcing this does not change your session's output.
# Hyperlinks off too: in RStudio cli wraps every path and URL in terminal
# hyperlink escapes, which the first real run's transcript carried verbatim.
.old_options <- options(cli.unicode = FALSE, cli.num_colors = 1,
                        cli.hyperlink = FALSE, cli.hyperlink_file = FALSE,
                        crayon.enabled = FALSE, width = 80)

# Every early stop goes through here, so a sourced run that stops still gives
# the session its options back.
fail <- function(...) {
  options(.old_options)
  stop(..., call. = FALSE)
}

backend <- Sys.getenv("DATOM_E2E_BACKEND", "s3")
if (!backend %in% c("s3", "local")) {
  fail("DATOM_E2E_BACKEND must be \"s3\" or \"local\".")
}

# GitHub through its API with GITHUB_PAT -- the same token the vignettes use --
# rather than the gh CLI, which answers for whichever account gh is logged in as.
# If those differed, the pre-clean would look for leftovers in the wrong account.
gh_api <- function(method, path) {
  httr2::request("https://api.github.com") |>
    httr2::req_url_path_append(path) |>
    httr2::req_method(method) |>
    httr2::req_auth_bearer_token(Sys.getenv("GITHUB_PAT")) |>
    httr2::req_headers(Accept = "application/vnd.github+json") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()
}
gh_repo_exists <- function(full) {
  httr2::resp_status(gh_api("GET", paste0("repos/", full))) == 200L
}
keep <- nzchar(Sys.getenv("DATOM_E2E_KEEP"))
out_dir <- Sys.getenv(
  "DATOM_E2E_OUT",
  file.path(dirname(pkg_dir), "datom-test", "vignettes-e2e")
)
fs::dir_create(out_dir)
transcript <- fs::path(out_dir, paste0("transcript-", backend, ".md"))

hr <- function(x) cat("\n==========", x, "==========\n")

# --- the chunks ---------------------------------------------------------------
# purl emits `## ----label----...` before each chunk; everything up to the next
# header is that chunk's code. `#>` lines are the vignette's placeholder or
# recorded output, not code, so they are dropped.
read_chunks <- function(rmd) {
  f <- knitr::purl(rmd, output = tempfile(fileext = ".R"), quiet = TRUE,
                   documentation = 1L)
  lines <- readLines(f)
  hdr <- grep("^## ----", lines)
  # A labelled header is `## ----label----` or `## ----label, opts----`. The
  # unlabelled setup chunk comes out as `## ----include = FALSE----` and must not
  # be read as a chunk named "include": it sets `eval = FALSE`.
  labelled <- "^## ----([A-Za-z0-9_-]*[A-Za-z0-9_])(,.*)?-*$"
  labels <- ifelse(grepl(labelled, lines[hdr]),
                   sub(labelled, "\\1", lines[hdr]), NA_character_)
  ends <- c(hdr[-1] - 1L, length(lines))
  chunks <- Map(function(s, e) {
    code <- if (e > s) lines[(s + 1L):e] else character()
    code <- code[!grepl("^#>", code)]
    while (length(code) && !nzchar(trimws(code[length(code)]))) {
      code <- code[-length(code)]
    }
    code
  }, hdr, ends)
  names(chunks) <- labels
  chunks[!is.na(names(chunks))]
}

vignettes <- list(
  `start-on-s3`  = read_chunks(file.path(pkg_dir, "vignettes", "start-on-s3.Rmd")),
  `citable-sets` = read_chunks(file.path(pkg_dir, "vignettes", "citable-sets.Rmd"))
)

required <- list(
  `start-on-s3`  = c("keyring-setup", "secrets", "settings", "teardown-imported"),
  `citable-sets` = c("settings-liver-safety", "derive-script", "teardown")
)
for (v in names(required)) {
  missing <- setdiff(required[[v]], names(vignettes[[v]]))
  if (length(missing)) {
    fail("vignettes/", v, ".Rmd has no chunk named: ",
         paste(missing, collapse = ", "))
  }
}

# The names the run creates, read from the vignettes rather than restated here.
settings_env <- new.env(parent = globalenv())
eval(parse(text = vignettes$`start-on-s3`$settings), envir = settings_env)
eval(parse(text = vignettes$`citable-sets`$`settings-liver-safety`),
     envir = settings_env)
repos    <- c(settings_env$repo_imported, settings_env$repo_liver_safety)
prefixes <- c(settings_env$prefix_imported, settings_env$prefix_liver_safety)
workdirs <- c(settings_env$workdir_imported, settings_env$workdir_liver_safety)

# --- preflight ----------------------------------------------------------------
hr(paste("preflight, backend:", backend))
local_root <- NULL
if (backend == "s3") {
  need <- c("GITHUB_PAT", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
            "DATOM_E2E_BUCKET")
  unset <- need[!nzchar(Sys.getenv(need))]
  if (length(unset)) {
    fail("Not set: ", paste(unset, collapse = ", "),
         ". See the header of this script.")
  }
  bucket <- Sys.getenv("DATOM_E2E_BUCKET")
  region <- Sys.getenv("DATOM_E2E_REGION", "us-east-1")

  me <- gh_api("GET", "user")
  if (httr2::resp_status(me) != 200L) {
    fail("GITHUB_PAT was refused by the GitHub API (HTTP ",
         httr2::resp_status(me), ").")
  }
  gh_owner <- httr2::resp_body_json(me)$login
  full_repos <- paste0(gh_owner, "/", repos)
  # A classic token lists its scopes in this header. Teardown deletes the two
  # repos, so say now if it will not be allowed to, rather than after the walk.
  scopes <- httr2::resp_header(me, "x-oauth-scopes")
  if (!is.null(scopes) && !grepl("delete_repo", scopes)) {
    fail("GITHUB_PAT has no delete_repo scope (it has: ", scopes, "). ",
         "The pre-clean and the teardown delete the two repos.")
  }

  cat("github :", gh_owner, "\n")
  cat("bucket :", bucket, "(", region, ")\n")
  cat("repos  :", paste(full_repos, collapse = ", "), "\n")
  cat("prefix :", paste(paste0(prefixes, "datom/"), collapse = ", "), "\n")
} else {
  local_root <- fs::path(tempdir(), "e2e-vignettes-local")
  if (fs::dir_exists(local_root)) fs::dir_delete(local_root)
  fs::dir_create(local_root)
  cat("local root:", local_root, "\n")
}
cat("teardown  :", if (keep) "SKIPPED (DATOM_E2E_KEEP)" else "at the end, on success",
    "\n")
cat("transcript:", transcript, "\n")

# --- pre-clean -----------------------------------------------------------------
hr("pre-clean anything a previous run left behind")
# Local clones first, on both backends: a sourced run shares tempdir() with any
# earlier run in the same session, and init refuses a folder that exists.
for (w in workdirs) {
  if (fs::dir_exists(w)) {
    cat("removing leftover clone", w, "\n")
    fs::dir_delete(w)
  }
}
if (backend == "s3") {
  for (full in full_repos) {
    if (gh_repo_exists(full)) {
      cat("deleting leftover repo", full, "\n")
      st <- httr2::resp_status(gh_api("DELETE", paste0("repos/", full)))
      if (st != 204L) fail("Could not delete ", full, " (HTTP ", st, ").")
    } else {
      cat("no leftover repo", full, "\n")
    }
  }
  for (p in prefixes) {
    comp <- datom_store_s3(
      bucket = bucket, prefix = p, region = region,
      access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
      secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
      validate = FALSE
    )
    .sandbox_wipe_s3_component(comp, label = p)
  }
}

# --- the environment the chunks run in ------------------------------------------
run_env <- new.env(parent = globalenv())

if (backend == "local") {
  # Stand-ins with the same arguments the vignettes pass. A store with a token
  # gets a bare git remote keyed by its prefix, so the writer store and the
  # project's init agree on one remote; create_repo is dropped because there is
  # no GitHub to create a repo on.
  local({
    remote_for <- function(prefix) {
      p <- fs::path(local_root, "remotes",
                    paste0(gsub("[^A-Za-z0-9]", "", prefix %||% "root"), ".git"))
      if (!fs::dir_exists(p)) {
        fs::dir_create(p)
        git2r::init(p, bare = TRUE)
      }
      as.character(p)
    }
    datom_store_s3 <- function(bucket, prefix = NULL, region = NULL,
                               access_key = NULL, secret_key = NULL, ...) {
      datom::datom_store_local(path = fs::path(local_root, "s3", bucket),
                               prefix = prefix, validate = FALSE)
    }
    datom_store <- function(data, github_pat = NULL, ...) {
      if (is.null(github_pat)) {
        datom::datom_store(data = data, validate = FALSE)
      } else {
        datom::datom_store(data = data, github_pat = "local-dry-run",
                           data_repo_url = remote_for(data$prefix),
                           validate = FALSE)
      }
    }
    datom_init_repo <- function(..., create_repo = FALSE, repo_name = NULL) {
      datom::datom_init_repo(..., create_repo = FALSE)
    }
  }, envir = run_env)
}

# --- one chunk at a time ---------------------------------------------------------
# Knitted one by one, appending as it goes, so a failure still leaves the
# transcript of everything before it.
writeLines(c(
  paste0("# Transcript: start-on-s3 + citable-sets (", backend, ")"),
  "",
  paste0("Run ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
         ", datom ", as.character(utils::packageVersion("datom")),
         ", HEAD ", tryCatch(
           as.character(git2r::revparse_single(git2r::repository(pkg_dir),
                                               "HEAD")$sha),
           error = function(e) "unknown"), ".")
), transcript)

append_md <- function(...) {
  cat(..., file = transcript, sep = "\n", append = TRUE)
}

knit_chunk <- function(vignette, label, code, heading = TRUE) {
  rmd <- c(
    paste0("```{r ", gsub("[^A-Za-z0-9]", "-", paste(vignette, label)),
           ", eval = TRUE, collapse = TRUE, comment = '#>', error = FALSE}"),
    code,
    "```"
  )
  md <- knitr::knit(text = paste(rmd, collapse = "\n"), envir = run_env,
                    quiet = TRUE)
  if (heading) append_md("", paste0("## ", vignette, " / ", label), "")
  append_md(md)
}

special_skip <- c("keyring-setup", "secrets", "teardown-imported", "teardown")

plan <- list()
for (v in names(vignettes)) {
  for (label in names(vignettes[[v]])) {
    if (label %in% special_skip) next
    plan[[length(plan) + 1L]] <- list(v = v, label = label)
  }
}

failed <- NULL
hr("walk")
for (step in plan) {
  code <- vignettes[[step$v]][[step$label]]
  cat(sprintf("%-14s %s\n", step$v, step$label))
  res <- tryCatch({
    if (step$label == "derive-script") {
      # Saved where the vignette tells the reader to save it, then shown.
      assign(".derive_code", code, envir = run_env)
      eval(quote({
        fs::dir_create(fs::path(workdir_liver_safety, "R"))
        writeLines(.derive_code,
                   fs::path(workdir_liver_safety, "R", "derive_liver_flags.R"))
      }), envir = run_env)
      append_md("", paste0("## ", step$v, " / ", step$label),
                "", "(saved to R/derive_liver_flags.R; no output)")
    } else {
      knit_chunk(step$v, step$label, code)
    }
    if (step$v == "start-on-s3" && step$label == "settings" && backend == "s3") {
      assign("bucket", bucket, envir = run_env)
      assign("region", region, envir = run_env)
      append_md("", paste0("(e2e override: bucket <- \"", bucket,
                           "\", region <- \"", region, "\")"))
    }
    NULL
  }, error = function(e) e)
  if (!is.null(res)) {
    failed <- step
    cat("\nFAILED in", step$v, "/", step$label, ":\n", conditionMessage(res), "\n")
    append_md("", paste0("**FAILED here:** ", conditionMessage(res)))
    break
  }
}

# --- teardown, only after a clean walk -----------------------------------------
if (is.null(failed) && !keep) {
  hr("teardown (citable-sets `teardown` chunk: both projects)")
  td <- tryCatch({
    knit_chunk("citable-sets", "teardown", vignettes$`citable-sets`$teardown)
    NULL
  }, error = function(e) e)
  if (!is.null(td)) {
    failed <- list(v = "citable-sets", label = "teardown")
    cat("\nTEARDOWN FAILED:", conditionMessage(td), "\n")
  } else {
    left <- vapply(c("conn_write_imported", "conn_write_liver_safety"),
                   function(nm) {
                     length(tryCatch(datom_storage_list(get(nm, envir = run_env)),
                                     error = function(e) character()))
                   }, integer(1L))
    clones <- vapply(c("workdir_imported", "workdir_liver_safety"),
                     function(nm) fs::dir_exists(get(nm, envir = run_env)),
                     logical(1L))
    cat("objects left in storage:", paste(names(left), left, collapse = ", "), "\n")
    cat("clones left            :", paste(names(clones), clones, collapse = ", "), "\n")
    if (any(left > 0L) || any(clones)) failed <- list(v = "teardown", label = "check")
    if (backend == "s3") {
      for (full in full_repos) {
        gone <- !gh_repo_exists(full)
        cat("repo gone:", full, gone, "\n")
        if (!gone) failed <- list(v = "teardown", label = "repos")
      }
    }
  }
} else if (is.null(failed)) {
  hr("left standing (DATOM_E2E_KEEP)")
  cat("Run the citable-sets `teardown` chunk by hand, or re-run this script",
      "(its pre-clean removes both projects).\n")
}

hr("result")
options(.old_options)
cat("transcript:", transcript, "\n")
if (is.null(failed)) {
  cat("VIGNETTES_E2E_RESULT: SUCCESS\n")
} else {
  cat("VIGNETTES_E2E_RESULT: FAILED at", failed$v, "/", failed$label, "\n")
  cat("Nothing was torn down; the next run's pre-clean removes what is left.\n")
  # Sourced: stop, and leave the session (and run_env) for inspection.
  if (.sourced) {
    stop("VIGNETTES_E2E_RESULT: FAILED", call. = FALSE)
  } else {
    quit(status = 1L, save = "no")
  }
}
