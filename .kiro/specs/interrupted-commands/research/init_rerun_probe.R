# What datom_init_repo() leaves after a break at each of its steps, and what a
# re-run (or the way out its message names) does today. Written 2026-11-07 for
# task 9's cold start, on the code at task 8's review fix (6921561).
#   Rscript .kiro/specs/interrupted-commands/research/init_rerun_probe.R
main <- function() {
  suppressMessages(devtools::load_all(quiet = TRUE))
  break_init <- function(step) {
    root <- tempfile("init-probe-"); dir.create(root)
    store <- datom_store(data = datom_store_local(file.path(root, "storage")),
                         data_repo_url = file.path(root, "remote.git"))
    repo <- file.path(root, "repo")
    real_json <- get(".datom_storage_write_json", envir = asNamespace("datom"))
    boom <- function(...) stop("simulated break at ", step)
    bindings <- switch(step,
      commit = list(.datom_git_commit = boom),
      push = list(.datom_git_push = boom),
      manifest = list(.datom_storage_write_json = function(conn, key, data) {
        if (identical(key, ".metadata/manifest.json")) boom()
        real_json(conn, key, data)
      })
    )
    err <- tryCatch(
      do.call(testthat::with_mocked_bindings, c(bindings, list(
        code = quote(suppressMessages(datom_init_repo(repo, "P", store, create_repo = TRUE))),
        .package = "datom"))),
      error = function(e) conditionMessage(e))
    cat("\n== break at", step, "==\n")
    cat("break fired:", grepl("simulated break", paste(err, collapse = " ")), "\n")
    cat("project.yaml left:", file.exists(file.path(repo, ".datom", "project.yaml")),
        " bare remote left:", dir.exists(file.path(root, "remote.git")),
        " stored manifest:", file.exists(file.path(root, "storage", "P", "datom", ".metadata", "manifest.json")), "\n")
    rerun <- tryCatch({
      suppressMessages(datom_init_repo(repo, "P", store, create_repo = TRUE)); "succeeded"
    }, error = function(e) paste("refused:", gsub("\\s+", " ", cli::ansi_strip(conditionMessage(e)))))
    cat("re-run of the same call:", substr(rerun, 1, 160), "\n")
    if (step == "manifest") {
      fixed <- tryCatch({
        conn <- suppressMessages(datom_get_conn(repo, store))
        suppressWarnings(suppressMessages(datom_validate(conn, fix = TRUE)))
        "ran"
      }, error = function(e) paste("failed:", gsub("\\s+", " ", cli::ansi_strip(conditionMessage(e)))))
      stored <- list.files(file.path(root, "storage"), recursive = TRUE, all.files = TRUE)
      cat("datom_validate(fix = TRUE):", substr(fixed, 1, 160), "\n")
      cat("stored files after it:", paste(stored, collapse = ", "), "\n")
    }
    unlink(root, recursive = TRUE)
  }
  for (s in c("commit", "push", "manifest")) break_init(s)
}
main()
