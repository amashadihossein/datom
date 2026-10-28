# Research probe for #134 part 3b: how paws.common resolves credentials.
# Fake keys only; requests go to a local capture server, never to AWS.
# Everything runs inside main() (top-level on.exit() never fires under Rscript).

main <- function(port, log) {
  dir <- tempfile("paws-probe-")
  dir.create(dir)
  cred_file <- file.path(dir, "credentials")
  conf_file <- file.path(dir, "config")
  writeLines(c("[planted]", "aws_access_key_id = AKIDFROMFILE",
               "aws_secret_access_key = filesecret"), cred_file)
  writeLines(c("[profile planted]", "region = eu-west-3"), conf_file)

  old <- Sys.getenv(c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
                      "AWS_PROFILE", "AWS_SHARED_CREDENTIALS_FILE",
                      "AWS_CONFIG_FILE", "AWS_EC2_METADATA_DISABLED"),
                    unset = NA)
  on.exit({
    for (n in names(old)) {
      if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(old[n]))
    }
    unlink(dir, recursive = TRUE)
  }, add = TRUE)

  Sys.setenv(
    AWS_ACCESS_KEY_ID = "AKIDFROMENV",
    AWS_SECRET_ACCESS_KEY = "envsecret",
    AWS_PROFILE = "planted",
    AWS_SHARED_CREDENTIALS_FILE = cred_file,
    AWS_CONFIG_FILE = conf_file,
    AWS_EC2_METADATA_DISABLED = "true"
  )

  endpoint <- sprintf("http://127.0.0.1:%s", port)
  mark <- function(label) cat("MARK", label, "\n", file = log, append = TRUE)
  head2 <- function(s3) {
    for (i in 1:2) try(s3$head_bucket(Bucket = "b"), silent = TRUE)
  }
  base_cfg <- function(credentials) {
    list(credentials = credentials, region = "us-east-1",
         endpoint = endpoint, s3_force_path_style = TRUE)
  }

  # A. Today's shape: static creds, no expiration.
  mark("A static-no-expiration")
  head2(paws.storage::s3(config = base_cfg(list(
    creds = list(access_key_id = "AKIDSTATIC", secret_access_key = "s")))))

  # B. Static creds that carry an expiration in the past.
  mark("B static-expired")
  head2(paws.storage::s3(config = base_cfg(list(
    creds = list(access_key_id = "AKIDSTATIC", secret_access_key = "s",
                 session_token = "tok", expiration = Sys.time() - 60)))))

  # C. Provider list replaced by one function; long-lived result.
  calls <- 0L
  fn_long <- function() {
    calls <<- calls + 1L
    list(access_key_id = paste0("AKIDFN", calls), secret_access_key = "s",
         session_token = "tok", expiration = Sys.time() + 3600)
  }
  mark("C provider-only-long")
  head2(paws.storage::s3(config = base_cfg(list(provider = list(fn_long)))))
  mark(paste("C calls", calls))

  # D. Provider function whose result expires inside paws's 5-minute window.
  calls <- 0L
  fn_short <- function() {
    calls <<- calls + 1L
    list(access_key_id = paste0("AKIDFN", calls), secret_access_key = "s",
         session_token = "tok", expiration = Sys.time() + 60)
  }
  mark("D provider-only-short")
  head2(paws.storage::s3(config = base_cfg(list(provider = list(fn_short)))))
  mark(paste("D calls", calls))

  # E. Provider function returns an incomplete result (no secret).
  mark("E provider-incomplete")
  head2(paws.storage::s3(config = base_cfg(list(provider = list(
    function() list(access_key_id = "AKIDHALF", secret_access_key = ""))))))

  # F. Provider function returns NULL.
  mark("F provider-null")
  head2(paws.storage::s3(config = base_cfg(list(provider = list(
    function() NULL)))))

  # G. Provider function errors.
  mark("G provider-error")
  r <- try(paws.storage::s3(config = base_cfg(list(provider = list(
    function() stop("boom from fn")))))$head_bucket(Bucket = "b"), silent = TRUE)
  mark(paste("G error:", gsub("\n", " ", as.character(r))))

  # H. Region and endpoint from ambient settings when datom gives none.
  # (Checked through paws's own resolver, so nothing is sent anywhere.)
  Sys.setenv(AWS_ENDPOINT_URL_S3 = "https://planted.example")
  ep <- paws.common:::get_service_endpoint("", "S3")
  Sys.unsetenv("AWS_ENDPOINT_URL_S3")
  writeLines(c("[profile planted]", "endpoint_url = https://fromconfig.example"),
             conf_file)
  ep_file <- paws.common:::get_service_endpoint("", "S3")
  mark(paste("H endpoint-from-env:", ep, "| from-config:", ep_file))

  # I. Does the stored client hold the resolved secret after a request?
  s3i <- paws.storage::s3(config = base_cfg(list(provider = list(function() {
    list(access_key_id = "AKIDSER", secret_access_key = "SECRETMARKER123",
         session_token = "TOKENMARKER456", expiration = Sys.time() + 3600)
  }))))
  try(s3i$head_bucket(Bucket = "b"), silent = TRUE)
  bytes <- serialize(s3i, NULL)
  found <- grepRaw("SECRETMARKER123", bytes, fixed = TRUE)
  mark(paste("I secret-in-serialized-client:", length(found) > 0))
  invisible(NULL)
}

args <- commandArgs(TRUE)
main(args[[1]], args[[2]])
