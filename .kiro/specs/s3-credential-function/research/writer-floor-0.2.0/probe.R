# What does datom 0.2.0 do after a teammate raises min_writer_version?
#
# Review 10 (2026-11-12) claimed 0.2.0 checks a copy of the floor taken when the
# connection was built, so a session keeps writing for as long as it reuses its
# connection. This runs 0.2.0's own code (its release commit 1581240) on a
# throwaway project: a folder git remote, a local store, nothing on the network.
#
# Run from the R datom repo root:
#   git worktree add -q --detach /tmp/datom-1581240 1581240
#   Rscript .kiro/specs/s3-credential-function/research/writer-floor-0.2.0/probe.R /tmp/datom-1581240
#   git worktree remove --force /tmp/datom-1581240
#
# The floor is set to "99.0.0" so the result does not depend on which version
# load_all() reports.

main <- function(args) {
  pkg <- args[[1]]
  suppressMessages(devtools::load_all(pkg, quiet = TRUE))
  cat("datom loaded from", pkg, "version", as.character(utils::packageVersion("datom")), "\n")

  tmp <- tempfile("floor-probe-")
  dir.create(tmp)
  remote <- file.path(tmp, "remote.git")
  dir.create(remote)
  git2r::init(remote, bare = TRUE)
  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token",
    data_repo_url = remote,
    validate = FALSE
  )
  clone_a <- file.path(tmp, "alice")
  suppressMessages(datom_init_repo(clone_a, "probe", store))

  try_write <- function(label, conn, n) {
    res <- tryCatch({
      suppressMessages(datom_write(conn, data.frame(x = seq_len(n)), "dm"))
      "WROTE"
    }, error = function(e) {
      paste0("REFUSED [", paste(class(e)[1:2], collapse = ", "), "] ",
             conditionMessage(e)[1])
    })
    floor <- yaml::read_yaml(file.path(clone_a, ".datom", "project.yaml"))$min_writer_version
    cat(sprintf("%-58s %s\n", label, substr(res, 1, 70)))
    cat(sprintf("%-58s clone's project.yaml floor: %s; conn's copy: %s\n", "",
                if (is.null(floor)) "absent" else floor,
                if (is.null(conn$min_writer_version)) "absent" else conn$min_writer_version))
  }

  conn1 <- suppressMessages(datom_get_conn(clone_a, store))
  try_write("1. first write, no floor anywhere", conn1, 1)

  # A teammate (Bob) raises the floor and pushes, with plain git.
  clone_b <- file.path(tmp, "bob")
  repo_b <- git2r::clone(remote, clone_b, progress = FALSE)
  git2r::config(repo_b, user.name = "Bob", user.email = "bob@example.com")
  yml <- file.path(clone_b, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(yml)
  cfg$min_writer_version <- "99.0.0"
  yaml::write_yaml(cfg, yml)
  git2r::add(repo_b, ".datom/project.yaml")
  git2r::commit(repo_b, "Raise the writer floor")
  git2r::push(repo_b, "origin", paste0("refs/heads/", git2r::repository_head(repo_b)$name))
  cat("-- Bob pushed min_writer_version: 99.0.0\n")

  # Alice reconnects before pulling: 0.2.0's connect pulls only on a data move.
  conn2 <- tryCatch(suppressMessages(datom_get_conn(clone_a, store)),
                    error = function(e) { cat("connect refused:", conditionMessage(e), "\n"); NULL })
  cat("2. datom_get_conn() before Alice's clone has pulled:", if (is.null(conn2)) "refused" else "connected", "\n")

  try_write("3. same old connection, write (push pulls the raise)", conn1, 2)
  try_write("4. same old connection, write again", conn1, 3)
  try_write("5. same old connection, write a third time", conn1, 4)
  try_write("6. connection made before the pull (step 2), write", conn2, 5)

  conn3 <- tryCatch(suppressMessages(datom_get_conn(clone_a, store)),
                    error = function(e) { cat("connect refused:", conditionMessage(e), "\n"); NULL })
  cat("7. datom_get_conn() after the clone has pulled:", if (is.null(conn3)) "refused" else "connected", "\n")
  if (!is.null(conn3)) try_write("8. new connection, write", conn3, 6)

  unlink(tmp, recursive = TRUE)
  invisible(NULL)
}

main(commandArgs(TRUE))
