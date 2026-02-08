#' Initialize a tbit Repository
#'
#' One-time setup for data developers. Creates folder structure, initializes
#' git with remote, sets up renv, and creates configuration files.
#'
#' @param path Path to the project folder. Defaults to current directory.
#' @param project_name Project name, used to auto-generate credential env var
#'   names (`TBIT_{PROJECT_NAME}_*`).
#' @param remote_url GitHub remote URL.
#' @param bucket S3 bucket name.
#' @param prefix Optional prefix for bucket organization.
#' @param region AWS region. If NULL, uses AWS_DEFAULT_REGION.
#' @param max_file_size_gb Maximum file size limit in GB. Default 1000 (1TB).
#' @param git_ignore Character vector of patterns to add to .gitignore.
#'
#' @return Invisible TRUE on success.
#' @export
tbit_init_repo <- function(path = ".",
                           project_name,
                           remote_url,
                           bucket,
                           prefix = NULL,
                           region = NULL,
                           max_file_size_gb = 1000,
                           git_ignore = c(
                             ".Rprofile", ".Renviron", ".Rhistory",
                             ".Rapp.history", ".Rproj.user/",
                             ".DS_Store", "*.csv", "*.tsv",
                             "*.rds", "*.txt", "*.parquet",
                             "*.sas7bdat", ".RData", ".RDataTmp",
                             "*.html", "*.png", "*.pdf",
                             ".vscode/", "rsconnect/"
                           )) {
 
 # TODO: Implement
 stop("Not yet implemented")
}


#' Get a tbit Connection
#'
#' Flexible connection for both developers and readers. Developers provide a
#' path to read from `.tbit/project.yaml`. Readers provide bucket, prefix, and
#' project_name directly.
#'
#' @param path Path to tbit repository. If provided, reads config from
#'   `.tbit/project.yaml`.
#' @param bucket S3 bucket name. Required for readers without local repo.
#' @param prefix Optional S3 prefix.
#' @param project_name Project name for credential lookup. Required for readers.
#'
#' @return A `tbit_conn` object.
#' @export
tbit_get_conn <- function(path = NULL,
                          bucket = NULL,
                          prefix = NULL,
                          project_name = NULL) {

  # TODO: Implement
  stop("Not yet implemented")
}
