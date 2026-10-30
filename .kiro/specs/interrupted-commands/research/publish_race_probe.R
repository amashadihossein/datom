# The race the second design review raised: a publish lands after a colleague
# published something newer. Today's code, no heal yet.
#   1. A writes dm v2; its commit and push succeed.
#   2. Before A publishes, B pulls, writes dm v3, pushes and publishes it.
#   3. A's publish of v2 then lands.
# The pause in step 2 is a mocked binding around A's metadata publish that runs
# B's whole write first. Folder git remote + local storage; no AWS, no GitHub.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/publish_race_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  ns <- asNamespace("datom")
  home <- file.path(tempdir(), "publish-race")
  unlink(home, recursive = TRUE)
  dir.create(home)
  remote <- file.path(home, "remote.git")
  store <- datom_store(
    data = datom_store_local(path = file.path(home, "storage")),
    data_repo_url = remote
  )
  ws_a <- file.path(home, "a")
  ws_b <- file.path(home, "b")
  suppressMessages(datom_init_repo(ws_a, project_name = "P", store = store,
                                   create_repo = TRUE))
  a <- datom_get_conn(path = ws_a, store = store)
  v1 <- datom_example_data("dm")
  suppressMessages(datom_write(a, data = v1, name = "dm", message = "v1"))
  b <- suppressMessages(datom_clone(ws_b, store = store))

  v2 <- v1; v2[[1]][1] <- "v2"
  v3 <- v1; v3[[1]][1] <- "v3"

  real <- ns$.datom_push_metadata_s3
  fired <- FALSE
  testthat::with_mocked_bindings(
    .datom_push_metadata_s3 = function(conn, name, metadata, metadata_sha, commit_sha = NULL) {
      if (!fired) {
        fired <<- TRUE
        # B, in between: pull, write v3, push, publish -- all with the real code.
        testthat::with_mocked_bindings(
          .datom_push_metadata_s3 = real,
          {
            suppressMessages(datom_pull(b))
            suppressMessages(datom_write(b, data = v3, name = "dm", message = "v3"))
          },
          .package = "datom"
        )
      }
      real(conn, name, metadata, metadata_sha, commit_sha)
    },
    suppressMessages(datom_write(a, data = v2, name = "dm", message = "v2")),
    .package = "datom"
  )

  github_meta <- jsonlite::fromJSON(paste(system2("git", c(paste0("--git-dir=", remote),
    "show", "HEAD:dm/metadata.json"), stdout = TRUE), collapse = "\n"), simplifyVector = FALSE)
  stored_meta <- ns$.datom_storage_read_json(a, "dm/.metadata/metadata.json")
  reader <- datom_get_conn(store = datom_store(
    data = datom_store_local(path = file.path(home, "storage"))), project_name = "P")
  got <- suppressMessages(datom_read(reader, "dm"))[[1]][1]
  cat("GitHub's latest dm:", substr(ns$.datom_compute_metadata_sha(github_meta), 1, 8),
      "| storage's current dm:", substr(ns$.datom_compute_metadata_sha(stored_meta), 1, 8),
      "| a reader gets first value:", got, "\n")
  invisible(NULL)
}
main()
