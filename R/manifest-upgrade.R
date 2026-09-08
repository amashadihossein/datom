# Manifest schema upgrade steps.
#
# EVERY FUNCTION IN THIS FILE IS FROZEN ONCE RELEASED. A step is written against
# documents that already exist unchanged in the world, so re-tuning one to a
# later shape converts them wrongly -- and the wrong conversion is silent,
# because the output is well-formed for the version it is no longer describing.
# Add a new step for a new adjacent pair; never edit a shipped one, not even to
# tidy it.
#
# The shape of the chain: one function per adjacent version pair, applied in
# order by the dispatcher. A v1 document reaching a v3 build runs v1-to-v2 and
# then v2-to-v3. No direct v1-to-v3 function is ever written -- that needs one
# function per *pair* of versions rather than per step, grows with the square of
# the version count, and gives the two routes to the same shape somewhere to
# disagree.
#
# Reads apply the chain in memory and leave the file alone. Writes apply it,
# edit the result, and write it back with the reached version stamped. Neither
# ever stamps a version onto a document it did not convert first.


#' Upgrade a v1 Manifest to v2
#'
#' v1 is every manifest written before the artifact namespace existed: the
#' artifact list sits under `tables` and no entry declares what kind of artifact
#' it is. v2 renames that key to `artifacts` and types every entry with
#' `kind = "table"`, which is what all of them are -- sets did not exist.
#'
#' The rename is done **in place** (`names()` assignment rather than
#' add-then-remove), so the key keeps its position in the document and any
#' sibling key this build does not recognise survives untouched.
#'
#' A v1 document with no `tables` key at all is left with no artifact key. That
#' is deliberate: an absent key and an empty one are different states -- a
#' truncated document versus a repo with nothing in it -- and flattening them
#' here would destroy the distinction a later self-healing read depends on.
#'
#' **Frozen.** See the file header.
#'
#' @param manifest Parsed manifest document (a named list) declaring v1.
#' @return The same document in v2 shape. The version is stamped by
#'   [.datom_manifest_upgrade()], not here, so a step is never mistaken for the
#'   thing that records the result.
#' @keywords internal
.datom_manifest_upgrade_v1_to_v2 <- function(manifest) {
  if (!is.list(manifest)) return(manifest)

  names(manifest)[names(manifest) == "tables"] <- "artifacts"

  if (!is.null(manifest$artifacts)) {
    manifest$artifacts <- purrr::map(manifest$artifacts, function(entry) {
      if (!is.list(entry)) return(entry)
      if (!is.null(entry$kind)) return(entry)
      c(list(kind = "table"), entry)
    })
  }

  manifest
}


# The chain, keyed by the version each step upgrades FROM. Append only.
.datom_manifest_upgrade_steps <- list(
  "1" = .datom_manifest_upgrade_v1_to_v2
)


#' Apply Every Upgrade Step from a Declared Version to Current
#'
#' The dispatcher. Runs each step from `declared` up to
#' `.datom_supported_schema` in order, then records the version it reached.
#'
#' `declared` is a parameter rather than something read off the document,
#' because the only correct source for it is
#' [.datom_check_schema_version()], which returns it after refusing a document
#' this build cannot convert. Taking it as an argument is what makes
#' "check first, then upgrade" structural: there is no way to call this without
#' having obtained the number from the check.
#'
#' Identity on a document already at the current version -- zero steps run. A
#' document declaring a version *above* current is returned untouched too, since
#' no step exists for it; that state is unreachable through the check, which
#' aborts first.
#'
#' @param manifest Parsed manifest document (a named list).
#' @param declared Declared schema version, as returned by
#'   [.datom_check_schema_version()].
#' @return The document in current shape, declaring the version it reached.
#' @keywords internal
.datom_manifest_upgrade <- function(manifest, declared) {
  # A document that did not parse to a named list has no shape to convert, and
  # stamping one would turn `null` on disk into an object in memory -- inventing
  # a document where the file had none.
  if (!is.list(manifest)) return(manifest)

  declared <- as.integer(declared)

  # Guarded rather than relying on seq(): seq(2, 1) counts DOWN, so an
  # unguarded seq() would run the steps backwards on a current-version
  # document.
  if (declared >= .datom_supported_schema) return(manifest)

  from_versions <- seq(declared, .datom_supported_schema - 1L)

  manifest <- purrr::reduce(from_versions, function(m, from) {
    step <- .datom_manifest_upgrade_steps[[as.character(from)]]
    if (is.null(step)) {
      cli::cli_abort(
        "No manifest upgrade step from schema v{from} to v{from + 1L}.",
        class = "datom_schema_no_upgrade_step"
      )
    }
    step(m)
  }, .init = manifest)

  # Stamped only now, and only because the steps above ran: the number on disk
  # has to describe the shape the document actually has.
  manifest$schema_version <- .datom_supported_schema

  manifest
}
