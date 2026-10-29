# The git2r calls the design leans on, checked on a throwaway repo:
#  1. read a file as it is in HEAD (revparse "HEAD:path" -> blob -> content)
#  2. list the files changed between two commits (diff of two trees)
#  3. reset chosen files to HEAD, leaving other changes alone (checkout path=)
#  4. see an untracked file in status
# No network, no datom code.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/git2r_primitives_probe.R
main <- function() {
  cat("git2r", as.character(packageVersion("git2r")), "\n")
  dir <- tempfile("g2r-")
  dir.create(dir)
  repo <- git2r::init(dir)
  git2r::config(repo, user.name = "p", user.email = "p@p")
  dir.create(file.path(dir, ".datom"))
  writeLines('{"a": 1}', file.path(dir, ".datom", "manifest.json"))
  writeLines("user v1", file.path(dir, "notes.md"))
  git2r::add(repo, c(".datom/manifest.json", "notes.md"))
  c1 <- git2r::commit(repo, "one")
  dir.create(file.path(dir, "dm"))
  writeLines('{"m": 1}', file.path(dir, "dm", "metadata.json"))
  git2r::add(repo, "dm/metadata.json")
  c2 <- git2r::commit(repo, "two")

  # 1
  blob <- git2r::revparse_single(repo, "HEAD:.datom/manifest.json")
  cat("1. HEAD blob class:", class(blob)[1], "| content:", git2r::content(blob), "\n")

  # 2
  d <- git2r::diff(git2r::tree(c1), git2r::tree(c2))
  changed <- vapply(d$files, function(f) f$new_file, character(1))
  cat("2. changed between commits:", paste(changed, collapse = " "), "\n")

  # 3
  writeLines('{"a": 2}', file.path(dir, ".datom", "manifest.json"))
  writeLines('{"m": 2}', file.path(dir, "dm", "metadata.json"))
  writeLines("user v2", file.path(dir, "notes.md"))
  r <- try(git2r::checkout(repo, path = c(".datom/manifest.json", "dm/metadata.json"),
                           force = TRUE), silent = TRUE)
  cat("3. checkout path= raised:", inherits(r, "try-error"),
      if (inherits(r, "try-error")) conditionMessage(attr(r, "condition")) else "", "\n")
  cat("   manifest now:", readLines(file.path(dir, ".datom", "manifest.json")),
      "| dm meta now:", readLines(file.path(dir, "dm", "metadata.json")),
      "| notes.md now:", readLines(file.path(dir, "notes.md")), "\n")

  # 4
  dir.create(file.path(dir, "lb"))
  writeLines("{}", file.path(dir, "lb", "metadata.json"))
  st <- git2r::status(repo, untracked = TRUE)
  cat("4. untracked:", paste(unlist(st$untracked), collapse = " "), "\n")
  invisible(NULL)
}
main()
