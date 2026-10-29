# For each step of datom_write(): break the write there, then re-run the SAME
# write, and report what a reader sees and what datom_validate() says.
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited:
# each break is a mocked binding that raises at one step.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/write_steps_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  ns <- asNamespace("datom")
  a <- datom_example_data("dm")
  b <- a
  b[[1]][1] <- paste0(b[[1]][1], "-changed")

  setup <- function(label) {
    home <- file.path(tempdir(), paste0("steps-", label))
    unlink(home, recursive = TRUE)
    dir.create(home)
    store <- datom_store(
      data = datom_store_local(path = file.path(home, "storage")),
      data_repo_url = file.path(home, "remote.git")
    )
    ws <- file.path(home, "ws")
    suppressMessages(datom_init_repo(ws, project_name = "P", store = store,
                                     create_repo = TRUE))
    conn <- datom_get_conn(path = ws, store = store)
    reader <- datom_get_conn(store = datom_store(
      data = datom_store_local(path = file.path(home, "storage"))),
      project_name = "P")
    list(conn = conn, reader = reader, ws = ws)
  }

  reads_as <- function(reader) {
    r <- try(suppressMessages(datom_read(reader, "dm")), silent = TRUE)
    if (inherits(r, "try-error")) return("READ FAILS")
    v <- as.character(r[[1]][1])
    if (identical(v, as.character(a[[1]][1]))) "v1" else
      if (identical(v, as.character(b[[1]][1]))) "v2" else "other"
  }

  boom <- function(...) stop("simulated break")
  real_write_json <- ns$.datom_storage_write_json
  breaks <- list(
    commit = list(.datom_git_commit = boom),
    push = list(.datom_git_push = boom),
    upload = list(.datom_storage_upload = boom),
    metadata = list(.datom_push_metadata_s3 = boom),
    manifest = list(.datom_storage_write_json = function(conn, key, data) {
      if (identical(key, ".metadata/manifest.json")) stop("simulated break")
      real_write_json(conn, key, data)
    })
  )

  for (step in names(breaks)) {
    p <- setup(step)
    suppressMessages(datom_write(p$conn, data = a, name = "dm", message = "v1"))
    args <- c(
      breaks[[step]],
      list(
        code = quote(try(suppressMessages(
          datom_write(p$conn, data = b, name = "dm", message = "v2")
        ), silent = TRUE)),
        .package = "datom"
      )
    )
    e <- do.call(testthat::with_mocked_bindings, args)
    after_break <- reads_as(p$reader)
    r <- try(suppressMessages(
      datom_write(p$conn, data = b, name = "dm", message = "v2")
    ), silent = TRUE)
    rerun <- if (inherits(r, "try-error")) "ERROR" else r$action
    after_rerun <- reads_as(p$reader)
    v <- suppressMessages(suppressWarnings(datom_validate(p$conn)))
    cat(sprintf(
      "break at %-8s | raised %-5s | reader after break %-10s | re-run action %-6s | reader after re-run %-10s | validate valid %s\n",
      step, inherits(e, "try-error"), after_break, rerun, after_rerun, v$valid
    ))
  }
  invisible(NULL)
}
main()
