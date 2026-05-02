# inst/vignette-setup/resume_article_8.R
#
# End-of-Article-7 state: STUDY_001 lives on S3, the governance repo also
# carries STUDY_002 (registered narratively in Article 7; no real data).
# Article 8 is a read-only audit walkthrough -- no new persistent state is
# created. Resume delegates to Article 7's resume since the on-disk state
# is identical.
#
# Returns invisible(list(
#   conn, study_dir, gov_clone_path,
#   data_s3, gov_component,
#   data_repo_url, gov_repo_url
# )).

source(
  system.file("vignette-setup", "resume_article_7.R", package = "datom")
)$value
