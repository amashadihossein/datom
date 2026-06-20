# Tests for the package export surface after the gov-seam lift-out.
# The governance *write* surface moved to datomanager; datom retains only the
# gov-read surface plus the data-side repo helpers.

test_that("removed gov-write exports are absent from the namespace", {
  # Feature: gov-seam-liftout, Property: removed gov-write exports gone
  exports <- getNamespaceExports("datom")
  removed <- c(
    "datom_decommission",
    "datom_init_gov",
    "datom_attach_gov",
    "datom_pull_gov",
    "datom_sync_dispatch"
  )
  for (fn in removed) {
    expect_false(fn %in% exports, info = paste0(fn, " should not be exported"))
  }
})

test_that("retained gov-read and repo exports are present in the namespace", {
  # Feature: gov-seam-liftout, Property: retained read surface present
  exports <- getNamespaceExports("datom")
  retained <- c(
    "datom_projects",
    "datom_pull",
    "datom_repo_delete",
    "datom_repo_attach_governance"
  )
  for (fn in retained) {
    expect_true(fn %in% exports, info = paste0(fn, " should be exported"))
  }
})
