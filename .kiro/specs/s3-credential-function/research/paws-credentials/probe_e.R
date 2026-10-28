main <- function(port) {
  Sys.setenv(AWS_EC2_METADATA_DISABLED = "true")
  on.exit(Sys.unsetenv("AWS_EC2_METADATA_DISABLED"), add = TRUE)
  cfg <- function(fn) list(credentials = list(provider = list(fn)),
                           region = "us-east-1", s3_force_path_style = TRUE,
                           endpoint = sprintf("http://127.0.0.1:%s", port))
  # E: incomplete result
  r <- try(paws.storage::s3(config = cfg(function()
    list(access_key_id = "AKIDHALF", secret_access_key = "", session_token = "")))$head_bucket(Bucket = "b"),
    silent = TRUE)
  cat("E:", as.character(r), "\n")
  # J: already-expired result from the function
  r <- try(paws.storage::s3(config = cfg(function()
    list(access_key_id = "AKIDEXPIRED", secret_access_key = "s", session_token = "",
         expiration = Sys.time() - 3600)))$head_bucket(Bucket = "b"), silent = TRUE)
  cat("J:", if (inherits(r, "try-error")) as.character(r) else "request sent", "\n")
  # K: numeric expiration in seconds (paws expects milliseconds)
  n <- 0L
  s3 <- paws.storage::s3(config = cfg(function() {
    n <<- n + 1L
    list(access_key_id = "AKIDSECS", secret_access_key = "s", session_token = "",
         expiration = as.numeric(Sys.time()) + 3600)
  }))
  for (i in 1:3) try(s3$head_bucket(Bucket = "b"), silent = TRUE)
  cat("K: calls for 3 requests with seconds-numeric expiration:", n, "\n")
}
main(commandArgs(TRUE)[[1]])
