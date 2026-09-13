# Set membership: the member constructor and the validator a set write runs.
#
# A member is a pure-data POINTER at one exact version of one artifact, plus
# optional per-member tags:
#
#   { id: { project, name, kind, version }, tags: { ... } }
#
# The `id`/`tags` split is structural rather than cosmetic. `id` is a reference
# record with four fixed single-string keys; `tags` is an open map of text
# labels. Tags are what replace folder structure -- a folder puts an item in
# exactly one place, whereas a multi-valued tag puts it in several at once, so
# `domain = c("safety", "efficacy")` is the point and not an extension.
#
# THREE THINGS HERE ARE EASY TO GET WRONG BY ANALOGY WITH datom_parent().
#
#   1. A member carries NO `data_sha`. The version already pins content, so a
#      second copy of that fact is a second thing to keep consistent. (The
#      encoder in R/hashable-set.R aborts on any field outside `id`/`tags`, so
#      adding one is loud rather than silent.)
#   2. Tags are TIDIED, THEN VALIDATED -- in that order. Tidying first clears
#      the spellings nobody can reasonably care about, so validation only ever
#      reports genuine ambiguity; validating first would make the tidy rules
#      unreachable.
#   3. A member with no tags OMITS the key. It must never carry `tags = NULL`.
#      The hash is identical either way, so nothing here would fail -- but
#      `jsonlite` writes a NULL element as `{}` rather than dropping it, so
#      every untagged member would land in the stored payload carrying an empty
#      object, which is the one spelling a writer must never emit.
#
# There is deliberately NO cycle detection, no visited-set guard, and no depth
# limit. A member pins an immutable version and declaring one requires that
# version to already exist, so a set cannot reference anything that contains it
# -- the same property that makes git history acyclic. datom also resolves one
# level and never traverses. Both reasons are independently sufficient; do not
# reintroduce any of the three as defensive code.


#' Is a Value a Single Non-Empty, Non-Missing String?
#'
#' The field test used by the member validator. Deliberately **stricter than
#' `.datom_validate_parents()`'s equivalent**, which accepts `NA_character_`:
#' that value is character, has length 1, and `nzchar(NA_character_)` is `TRUE`,
#' so the obvious three-part test lets it through. A missing value in a member's
#' `id` would be spliced into a storage key or written into a citable payload,
#' so it is refused here.
#'
#' @param x Value to test.
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_is_text_scalar <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}


#' Drop Tag Keys That Carry No Labels
#'
#' The one tidy rule this file owns: a key whose value is empty is removed,
#' because "no labels" is spelled by omitting the key. Nothing is lost -- an
#' empty value states no fact -- and leaving it in would be worse than cosmetic:
#' a present key with an empty value hashes differently from an absent key, so
#' the same fact would mint two different `data_sha` values.
#'
#' Covers both empty spellings R produces. `character(0)` is the documented one;
#' `NULL` is what an absent value looks like when a tag map is composed
#' programmatically (`list(domain = f())` where `f()` returned nothing), and it
#' means exactly the same thing. Note the encoder still refuses a `NULL` value,
#' and must: there it arrives from a parsed file rather than from a caller, so
#' there is no caller intent to tidy toward.
#'
#' Full canonicalization -- sorting keys, sorting and deduplicating values,
#' unboxing single values, ordering members -- is **not** done here. It belongs
#' to the set write, so that canonical form has exactly one implementation.
#'
#' @param tags A named list, or `NULL`.
#' @return `tags` with empty-valued keys removed; `NULL` unchanged. A
#'   non-list is returned untouched, so the validator reports the type rather
#'   than this function failing on it.
#' @keywords internal
.datom_drop_empty_tags <- function(tags) {
  if (is.null(tags) || !is.list(tags) || length(tags) == 0L) return(tags)

  empty <- vapply(tags, function(v) length(v) == 0L, logical(1L))
  if (!any(empty)) return(tags)

  tags[!empty]
}


#' Validate a Tag Map
#'
#' The tag grammar, in one place, shared by [datom_member()] (its `tags`
#' argument), the member validator (each member's `tags`), and the set write
#' (set-level `tags`). A tag map is a named list whose values are UTF-8 strings
#' or arrays of them -- no numbers, booleans, `null`, or nesting.
#'
#' Per-value type checking delegates to `.datom_sv1_as_strings()`, the same
#' coercion the hash encoder uses, rather than restating its rules. That is
#' deliberate: two copies of "what counts as text here" would eventually
#' disagree, and the encoder's messages already name the offending key and the
#' allowed types. What this function adds on top is the **empty-label** refusal,
#' which the encoder does not make -- there, `""` hashes as an ordinary label.
#'
#' An empty value is **not** refused, because it is a tidy case rather than an
#' error: call [.datom_drop_empty_tags()] first, which every caller does.
#'
#' @param tags A named list, or `NULL` (no tags).
#' @param what Label used in error messages, e.g. `"tags"` or
#'   `"members[[2]]$tags"`.
#' @param remedy Optional `cli` bullet appended to every abort.
#' @return Invisibly `TRUE`.
#' @keywords internal
.datom_validate_tag_map <- function(tags, what = "tags", remedy = NULL) {
  if (is.null(tags)) return(invisible(TRUE))

  bullets <- function(...) {
    msg <- c(...)
    if (!is.null(remedy)) msg <- c(msg, "i" = remedy)
    msg
  }

  if (!is.list(tags) || (length(tags) > 0L && is.null(names(tags)))) {
    cli::cli_abort(bullets(
      paste0("{.field {what}} must be a named list, not ",
             "{.cls {class(tags)}}."),
      "i" = "For example: {.code list(type = \"output\")}."
    ))
  }
  if (length(tags) == 0L) return(invisible(TRUE))

  keys <- names(tags)
  if (any(is.na(keys)) || !all(nzchar(keys))) {
    cli::cli_abort(bullets(
      "Every key in {.field {what}} must be a non-empty name.",
      "i" = "An unnamed or blank key has no meaning as a tag."
    ))
  }
  if (anyDuplicated(keys) > 0L) {
    dup <- unique(keys[duplicated(keys)])
    cli::cli_abort(bullets(
      "{.field {what}} has {length(dup)} duplicate key{?s}: {.val {dup}}.",
      "i" = paste0("Give one key several labels instead, e.g. ",
                   "{.code list(domain = c(\"safety\", \"efficacy\"))}.")
    ))
  }

  for (k in keys) {
    label <- paste0(what, "$", k)
    vals <- .datom_sv1_as_strings(tags[[k]], label)
    if (length(vals) > 0L && !all(nzchar(vals))) {
      cli::cli_abort(bullets(
        "{.field {label}} contains an empty label.",
        "i" = paste0("A zero-length string is a label with no name -- almost ",
                     "always an accident. Omit the key to mean no labels.")
      ))
    }
  }

  invisible(TRUE)
}


#' Validate a Member List
#'
#' Checks that `members` is a list of member records, each an `id` of exactly
#' `project`, `name`, `kind`, `version` -- all single non-empty strings, with
#' `kind` one of `"table"` or `"set"` -- plus an optional `tags` map. Aborts
#' naming the first offending member, with a remedy pointing at
#' [datom_member()].
#'
#' **This validator sees one member at a time**, so two payload-level cases are
#' deliberately not here and belong to the set write, which is the only place
#' that sees a whole payload:
#'
#' * **zero members** -- an empty member list passes here;
#' * **the same `id` listed twice with different `tags`** -- invisible from a
#'   per-member view, and not caught by deduplication either, since a member's
#'   digest covers its tags, so both entries survive.
#'
#' Set-level tags never pass through here at all; the write validates those
#' with [.datom_validate_tag_map()] directly.
#'
#' @param x Value to validate: a list of member records, or `NULL`.
#' @return Invisibly `TRUE`.
#' @keywords internal
.datom_validate_members <- function(x) {
  if (is.null(x)) return(invisible(TRUE))

  remedy <- paste0(
    "Declare members with {.fn datom_member} so each carries a validated ",
    "{.field id}."
  )

  if (!is.list(x) || (length(x) > 0L && !is.null(names(x)))) {
    cli::cli_abort(c(
      "{.arg members} must be a list of member records, not a named list.",
      "i" = remedy
    ))
  }

  id_fields <- c("project", "name", "kind", "version")

  for (i in seq_along(x)) {
    entry <- x[[i]]
    at <- sprintf("members[[%d]]", i)

    if (!is.list(entry) || is.null(names(entry)) || !all(nzchar(names(entry)))) {
      cli::cli_abort(c(
        paste0("Member {i} must be a named list with an {.field id}, not ",
               "{.cls {class(entry)}}."),
        "i" = remedy
      ))
    }

    unknown <- setdiff(names(entry), c("id", "tags"))
    if (length(unknown) > 0L) {
      cli::cli_abort(c(
        paste0("Member {i} carries {length(unknown)} unexpected ",
               "field{?s}: {.val {unknown}}."),
        "i" = paste0("A member is exactly an {.field id} plus optional ",
                     "{.field tags}. User metadata belongs in tags."),
        "i" = remedy
      ))
    }

    id <- entry$id
    if (!is.list(id) || length(id) == 0L || is.null(names(id))) {
      cli::cli_abort(c(
        "Member {i} has no {.field id} map.",
        "i" = remedy
      ))
    }

    missing <- setdiff(id_fields, names(id))
    if (length(missing) > 0L) {
      cli::cli_abort(c(
        paste0("Member {i} is missing required {.field id} ",
               "field{?s}: {.val {missing}}."),
        "i" = remedy
      ))
    }
    extra <- setdiff(names(id), id_fields)
    if (length(extra) > 0L) {
      cli::cli_abort(c(
        paste0("Member {i} has {length(extra)} unexpected {.field id} ",
               "field{?s}: {.val {extra}}."),
        "i" = "An {.field id} is exactly {.val {id_fields}}.",
        "i" = remedy
      ))
    }

    for (field in id_fields) {
      if (!.datom_is_text_scalar(id[[field]])) {
        # The label is built first: a leading `.` or a literal `$` inside an
        # inline cli style is read as markup, not as text.
        fld <- paste0("id$", field)
        cli::cli_abort(c(
          paste0("Member {i}: {.field {fld}} must be a single non-empty ",
                 "string."),
          "i" = remedy
        ))
      }
    }

    if (!id$kind %in% .datom_artifact_kinds) {
      cli::cli_abort(c(
        "Member {i} declares {.field kind} {.val {id$kind}}.",
        "i" = "A member points at one of {.val {(.datom_artifact_kinds)}}.",
        "i" = remedy
      ))
    }

    .datom_validate_tag_map(entry$tags, paste0(at, "$tags"), remedy = remedy)
  }

  invisible(TRUE)
}


#' Declare a member of a set
#'
#' Resolves one artifact version against a single project connection and returns
#' a pure-data member record to pass to a set write. The record is a pointer:
#' it names the project, artifact, kind, and version, and carries no copy of the
#' data. Reading the artifact's versioned metadata snapshot is what makes the
#' pointer trustworthy -- a member can only point at something that already
#' exists, which is also why a set cannot contain itself at any depth.
#'
#' Same-project and cross-project members are declared identically; the only
#' difference is which connection is passed. `project` is always derived from the
#' connection's `project_name`, and `kind` from the snapshot (defaulting to
#' `"table"` for a snapshot written before datom recorded the field).
#'
#' Unlike [datom_parent()], a member carries **no `data_sha`**: the version
#' already pins the content, and a second copy of that fact would be a second
#' thing to keep consistent.
#'
#' @section Tags:
#' `tags` is an optional named list of text labels describing this member's role
#' in the set -- what folder structure would otherwise express. A value may be a
#' single string or several, because the whole point of labels over folders is
#' that an item can be in more than one category at once:
#' `list(type = "output", domain = c("safety", "efficacy"))`.
#'
#' Values are text only: no numbers, booleans, or nesting. Write a numeric label
#' as a string (`"500"`) and parse it downstream, exactly as you would a folder
#' name. A key with no labels is dropped rather than refused, since that is how
#' "no labels" is spelled; an empty string is refused, because a label with no
#' name is almost always an accident.
#'
#' @param conn A `datom_conn` scoped to the **member's** project store, from
#'   [datom_get_conn()].
#' @param name Artifact name (single validated string).
#' @param version The artifact version (`metadata_sha`) to pin, e.g. from
#'   [datom_history()].
#' @param tags Optional named list of text labels for this member. Omitted from
#'   the record when absent or empty.
#' @return A list with `id` (a list of exactly `project`, `name`, `kind`,
#'   `version`) and, when tags were supplied, `tags`. Pure data: it retains no
#'   connection and is serializable.
#' @seealso [datom_parent()] for the lineage equivalent.
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'
#'   # Pin the version just written and label its role in the set.
#'   version <- datom_history(conn, "dm")$version[1]
#'   print(datom_member(conn, "dm", version, tags = list(type = "input")))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_member <- function(conn, name, version, tags = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  .datom_validate_name(name)

  if (!is.character(version) || length(version) != 1L ||
      is.na(version) || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string.")
  }
  # version is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(version, arg = "version")

  # Tidy, then validate what remains. Both steps run before the storage read,
  # so a malformed tag map costs no round trip.
  tags <- .datom_drop_empty_tags(tags)
  .datom_validate_tag_map(tags, "tags")

  key <- .datom_artifact_snapshot_key(name, version)

  snap <- tryCatch(
    .datom_storage_read_json(conn, key),
    error = function(e) {
      cli::cli_abort(c(
        paste0("Member {.val {name}@{version}} not found in ",
               "project {.val {conn$project_name}}."),
        "i" = paste0("A member must point at a version that already exists. ",
                     "List them with {.fn datom_history}."),
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  # Absent means a snapshot written before datom recorded the field, and every
  # such snapshot describes a table -- sets did not exist yet. The fallback is
  # not padding: an untyped pointer is one a reader cannot classify, so it would
  # not know whether to resolve it with datom_read() or datom_read_set().
  kind <- snap$kind %||% "table"
  if (!.datom_is_text_scalar(kind) || !kind %in% .datom_artifact_kinds) {
    cli::cli_abort(c(
      paste0("The snapshot for {.val {name}@{version}} declares a kind ",
             "this version of datom cannot use."),
      "i" = "Expected one of {.val {(.datom_artifact_kinds)}}.",
      "i" = paste0("The snapshot at {.val {key}} in project ",
                   "{.val {conn$project_name}} may have been written by a ",
                   "newer datom -- upgrade datom and retry.")
    ))
  }

  member <- list(
    id = list(
      project = conn$project_name,
      name    = name,
      kind    = kind,
      version = version
    )
  )
  # Present only when there is something to say. `member$tags <- NULL` would
  # not add the key, but building the record with `tags = tags` inside list()
  # WOULD -- and jsonlite writes such a key as `{}` rather than omitting it.
  if (length(tags) > 0L) member$tags <- tags

  member
}
