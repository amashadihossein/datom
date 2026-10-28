# Session 2: a fresh R loads the saved session and asks for the id.
main <- function(lib, file) {
  load(file, envir = globalenv())
  library(credprobe, lib.loc = lib)
  cat("connection restored:", !is.null(globalenv()$conn_id_only), "\n")
  cat("secret found by id: ", !is.null(lookup(globalenv()$conn_id_only$id)), "\n")
}
a <- commandArgs(TRUE)
main(a[[1]], a[[2]])
