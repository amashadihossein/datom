# Session 1: put fake secrets in a package's internal memory, keep only an id
# in the "connection", save the session, and look for the secrets in the bytes.
main <- function(lib, out) {
  mk <- paste0("SECRET", "MARK", "ER")
  library(credprobe, lib.loc = lib)
  client <- paws.storage::s3(config = list(
    credentials = list(creds = list(access_key_id = "AKIDMARKER",
                                    secret_access_key = mk)),
    region = "us-east-1"))
  put("a91f", list(secret = mk, client = client))

  g <- globalenv()
  # Design under test: the connection holds only the id.
  assign("conn_id_only", list(id = "a91f"), envir = g)
  # Controls, each expected to leak:
  assign("conn_holds_env", list(reg = credprobe:::.reg), envir = g)   # the registry itself
  assign("conn_holds_client", list(client = client), envir = g)       # today's shape

  has_marker <- function(x) {
    b <- serialize(x, NULL)
    length(grepRaw(mk, b, fixed = TRUE)) > 0
  }
  cat("conn_id_only leaks:     ", has_marker(g$conn_id_only), "\n")
  cat("conn_holds_env leaks:   ", has_marker(g$conn_holds_env), "\n")
  cat("conn_holds_client leaks:", has_marker(g$conn_holds_client), "\n")
  cat("the namespace itself leaks:", has_marker(asNamespace("credprobe")), "\n")

  # A whole saved session holding only the id-only connection.
  rm("conn_holds_env", "conn_holds_client", envir = g)
  save.image(file = out, compress = FALSE)
  bytes <- readBin(out, "raw", file.info(out)$size)
  cat("saved session (.RData) leaks:", length(grepRaw(mk, bytes, fixed = TRUE)) > 0, "\n")
}
a <- commandArgs(TRUE)
main(a[[1]], a[[2]])
