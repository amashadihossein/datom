# For each step of datom_write_set(): break the write there, then re-run the SAME
# set write, and report what a reader sees. Then run datom_validate(fix = TRUE)
# and report again (sets have a restore route tables lack).
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/set_steps_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  ns <- asNamespace("datom")

  setup <- function(label) {
    home <- file.path(tempdir(), paste0("setsteps-", label))
    unlink(home, recursive = TRUE)
    dir.create(home)
    store <- datom_store(
      data = datom_store_local(path = file.path(home, "storage")),
      data_repo_url = file.path(home, "remote.git")
    )
    ws <- file.path(home, "ws")
    suppressMessages(datom_init_repo(ws, project_name = "P", store = store,
                                     create_repo = TRUE, mode = "product",
                                     set = "adam"))
    conn <- datom_get_conn(path = ws, store = store)
    reader <- datom_get_conn(store = datom_store(
      data = datom_store_local(path = file.path(home, "storage"))),
      project_name = "P")
    suppressMessages(datom_write(conn, data = datom_example_data("dm"), name = "dm"))
    v <- datom_history(conn, "dm", short_hash = FALSE)$version[[1L]]
    members <- list(datom_member(conn, "dm", v, tags = list(type = "input")))
    list(conn = conn, reader = reader, members = members)
  }

  reads_as <- function(reader) {
    s <- try(suppressMessages(datom_get_set(reader, "adam")), silent = TRUE)
    if (inherits(s, "try-error")) return("READ FAILS")
    s$tags$description %||% "?"
  }

  boom <- function(...) stop("simulated break")
  real_write_json <- ns$.datom_storage_write_json
  breaks <- list(
    commit = list(.datom_git_commit = boom),
    push = list(.datom_git_push = boom),
    upload = list(.datom_storage_upload = boom),
    metadata = list(.datom_push_metadata_s3 = boom)
  )

  for (step in names(breaks)) {
    p <- setup(step)
    suppressMessages(datom_write_set(p$conn, p$members,
                                     tags = list(description = "v1")))
    args <- c(breaks[[step]], list(
      code = quote(try(suppressMessages(datom_write_set(
        p$conn, p$members, tags = list(description = "v2")
      )), silent = TRUE)),
      .package = "datom"
    ))
    e <- do.call(testthat::with_mocked_bindings, args)
    after_break <- reads_as(p$reader)
    r <- try(suppressMessages(datom_write_set(
      p$conn, p$members, tags = list(description = "v2")
    )), silent = TRUE)
    rerun <- if (inherits(r, "try-error")) "ERROR" else r$action
    after_rerun <- reads_as(p$reader)
    suppressMessages(suppressWarnings(datom_validate(p$conn, fix = TRUE)))
    after_fix <- reads_as(p$reader)
    cat(sprintf(
      "break at %-8s | raised %-5s | reader after break %-10s | re-run %-5s | reader after re-run %-10s | after validate(fix) %s\n",
      step, inherits(e, "try-error"), after_break, rerun, after_rerun, after_fix
    ))
  }
  invisible(NULL)
}
`%||%` <- function(x, y) if (is.null(x)) y else x
main()
