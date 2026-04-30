# inst/vignette-setup/resume_article_7.R
#
# End-of-Article-6 state: STUDY_001 lives on S3, two engineers share the
# gov repo, gov registry has one project. Article 7 takes the manager view,
# pulls the gov clone fresh, and narrates STUDY_002 joining the portfolio.
#
# Continuity contract: requires Article 4 has run (S3 promotion). Article 6
# does not change persistent state beyond Article 4 (the second engineer's
# clone is in a separate dir; the original engineer's state is unchanged),
# so this script reuses the Article 6 rebuild path.
#
# Returns invisible(list(
#   conn, study_dir, gov_clone_path,
#   data_s3, gov_component,
#   data_repo_url, gov_repo_url
# )).

source(
  system.file("vignette-setup", "resume_article_6.R", package = "datom")
)$value
