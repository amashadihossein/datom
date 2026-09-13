# Writing a set: the second artifact kind's write path.
#
# A set is a reference layer, not a data layer. Its payload is a JSON document of
# pointers at existing artifact versions plus text labels, and everything else --
# version history, content addressing, change detection, the git-gates-storage
# ordering -- is the same machinery a table write uses.
#
# FIVE THINGS HERE ARE LOAD-BEARING AND EASY TO UNDO BY TIDYING.
#
#   1. TIDY, THEN VALIDATE. Tidying clears the spellings nobody can reasonably
#      care about (tag values out of order, a duplicated label, a one-element
#      array, a key pointing at nothing), so validation only ever reports genuine
#      ambiguity. Validating first would make every tidy rule unreachable. And
#      writing without tidying would let one fact mint two different `data_sha`
#      values, since a present key with an empty value hashes differently from an
#      absent one.
#
#   2. THE FILE'S MEMBER ORDER IS NOT THE HASH'S MEMBER ORDER, and the difference
#      is deliberate. The hash sorts member digests, which keeps the encoder
#      ignorant of what an `id` looks like. The file sorts by
#      `project` || `name` || `version`, which is stable under an edit -- with
#      digest order, editing one member's tag would RELOCATE its entry and
#      `git diff` would report a delete plus an insert instead of one changed
#      field, undoing the whole reason the git copy sits at a stable path.
#
#   3. TWO PATHS, ONE PAYLOAD, DIFFERENT ADDRESSES. Git holds `{name}/set.json`
#      at a stable path and is modified in place, so git owns the history and
#      diffs are member-level. Storage holds the same bytes content-addressed at
#      `{name}/{data_sha}.json`, so a reader with no clone can fetch an exact
#      version. Do NOT content-address the git side: every version would be a new
#      file and history would have to be read by listing filenames, which is
#      hand-maintaining what git already maintains.
#
#   4. NEVER RE-EMIT A PAYLOAD FOR A `data_sha` ALREADY IN HISTORY. Reuse the
#      stored object and carry its recorded `document_sha` forward. Recomputing
#      the hash from freshly emitted bytes while reusing the stored object records
#      a hash of bytes nobody stored, and every per-chunk test passes -- it
#      surfaces later as a refused read of a valid version. See
#      `.datom_resolve_document_sha()`.
#
#   5. `document_sha` IS POPULATED BEFORE THE METADATA DOCUMENT IS WRITTEN.
#      `jsonlite` does not omit a NULL element, it writes `{}`, so a document
#      written while the field is still unpopulated has its seven keys and one of
#      them is an empty object. A names-only field-set check cannot see that,
#      which is why the tests assert on the written bytes.
#
# There is deliberately NO cycle detection, no visited-set guard, and no depth
# limit. A member pins an immutable version and declaring one requires that
# version to already exist, so a set cannot reference anything that contains it.
# The self-reference refusal below is a nonsense check, not cycle detection.


# --- the two gates -------------------------------------------------------------

#' Refuse a Set Write the Repo Has Not Declared
#'
#' Two checks, both reading the clone's `.datom/project.yaml` directly, both
#' before anything is hashed or written:
#'
#' 1. The repo must declare `mode: product`. A set written into a repo that does
#'    not is a set with no declared owner, which defeats the second check too.
#' 2. The set's name must be the one the repo declares under `set:`. This is what
#'    makes "one repo = one set = one product" true rather than aspirational, and
#'    it is the precondition the self-reference refusal depends on -- that refusal
#'    needs the set's own identity, and this is where it is established.
#'
#' **Read from `project.yaml`, not from the connection.** Only
#' `min_writer_version` rides on a `datom_conn`; `mode` and `set` are read here,
#' at the one place that needs them, so nothing has to be threaded through
#' connection construction for two fields with one consumer. If a later caller
#' wants them on the conn it is a move with one call site to update, rather than a
#' decision to reopen.
#'
#' **Nothing writes either field yet**, so no repo built by this version of datom
#' can pass gate 1 -- `datom_init_repo()` writes nine keys and neither of these is
#' among them. That is the same deliberate inertness the reader-side format check
#' shipped with: the gate lands tested but unreachable through the public path,
#' and the release that starts writing `mode: product` is a later, separate step
#' which depends on a build already existing that can notice the declaration.
#' Fixtures hand-write the file.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name The set name the caller supplied, or `NULL` to take the repo's
#'   declared one.
#' @return The resolved set name.
#' @keywords internal
.datom_check_set_write_gates <- function(conn, name = NULL) {
  yaml_path <- fs::path(conn$path, ".datom", "project.yaml")

  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort(
      c(
        "No {.file .datom/project.yaml} found at {.path {conn$path}}.",
        "i" = "A set is written into a datom repo that declares itself a \\
               product repo; this path holds no datom project."
      ),
      class = "datom_set_config_missing"
    )
  }

  cfg <- yaml::read_yaml(yaml_path)

  declared_mode <- cfg$mode
  if (!identical(as.character(declared_mode %||% ""), "product")) {
    cli::cli_abort(
      c(
        "Writing a set needs a product repo, and this one does not declare \\
         itself as one.",
        "x" = if (is.null(declared_mode)) {
          "{.file .datom/project.yaml} declares no {.field mode}."
        } else {
          "{.file .datom/project.yaml} declares {.field mode} {.val {declared_mode}}."
        },
        "i" = "Add {.code mode: product} and {.code set: <name>} to \\
               {.file .datom/project.yaml}.",
        "i" = "One repo holds one set, and the declaration is what says which."
      ),
      class = "datom_set_mode_required"
    )
  }

  declared_set <- cfg$set
  if (!.datom_is_text_scalar(declared_set)) {
    cli::cli_abort(
      c(
        "This repo declares {.code mode: product} but names no set.",
        "i" = "Add {.code set: <name>} to {.file .datom/project.yaml}.",
        "i" = "Without it there is no way to say which set this repo owns."
      ),
      class = "datom_set_undeclared"
    )
  }

  if (is.null(name)) name <- declared_set

  if (!identical(name, declared_set)) {
    cli::cli_abort(
      c(
        "This repo's set is {.val {declared_set}}, not {.val {name}}.",
        "i" = "One repo holds one set. Write {.val {declared_set}} here, or \\
               write {.val {name}} from its own repo.",
        "i" = "The name comes from {.field set} in {.file .datom/project.yaml}."
      ),
      class = "datom_set_name_mismatch"
    )
  }

  .datom_validate_name(name)

  name
}


# --- canonical form ------------------------------------------------------------

#' Tidy One Tag Value
#'
#' Sorts and dedupes a tag value, and normalises the three spellings of a string
#' set into one character vector so that `auto_unbox = TRUE` writes a single label
#' as a bare string and only a genuine multi-label value as an array.
#'
#' **Anything this build does not recognise as text is returned untouched.** That
#' is what keeps tidying from aborting: `sort()` on a list or a function fails
#' with a base-R message that names nothing, whereas leaving the value alone hands
#' it to the validator, whose message names the key and the allowed types. Tidy
#' what you can, refuse the rest -- in that order, and never the reverse.
#'
#' A missing value is left alone for the same reason: `NA` has no text meaning, so
#' it is a refusal rather than a tidy case.
#'
#' @param v A tag value.
#' @return A sorted, deduplicated character vector, or `v` unchanged.
#' @keywords internal
.datom_tidy_tag_value <- function(v) {
  if (is.character(v)) {
    if (anyNA(v)) return(v)
    return(sort(unique(v), method = "radix"))
  }

  # The parsed-JSON spelling of an array of strings, which is what a payload read
  # back from storage looks like.
  if (is.list(v) && is.null(names(v)) && length(v) > 0L) {
    strings <- vapply(
      v,
      function(e) is.character(e) && length(e) == 1L && !is.na(e),
      logical(1L)
    )
    if (all(strings)) {
      return(sort(unique(unlist(v, use.names = FALSE)), method = "radix"))
    }
  }

  v
}


#' Tidy a Tag Map
#'
#' Radix-sorts the keys, drops a key whose value is empty, and tidies each value.
#' Never aborts: a malformed map is passed through for the validator to report.
#'
#' Radix sort throughout, i.e. C-locale byte order, so the canonical form does not
#' depend on the machine's collation -- the same reason the identity hash sorts
#' that way.
#'
#' @param tags A named list, or `NULL`.
#' @return The tidied map, or `NULL` when nothing is left.
#' @keywords internal
.datom_tidy_tag_map <- function(tags) {
  tags <- .datom_drop_empty_tags(tags)
  if (is.null(tags) || !is.list(tags) || length(tags) == 0L) return(tags)
  if (is.null(names(tags))) return(tags)

  tags <- tags[order(names(tags), method = "radix")]
  tags[] <- lapply(tags, .datom_tidy_tag_value)

  tags
}


#' Tidy a Set Payload
#'
#' The silent half of canonicalization: every spelling that states the same fact
#' is reduced to one, and nothing here is an error. Covers the set-level tag map,
#' each member's `id` key order, and each member's tag map.
#'
#' Member order and member deduplication are **not** here, because they need the
#' identity encoder and so can only run once validation has established that every
#' value is encodable -- see [.datom_order_set_members()].
#'
#' An empty tag map has its key **removed** rather than set to `NULL`, at both
#' levels. `jsonlite` writes a NULL element as `{}`, and `"tags": {}` is the one
#' spelling a writer must never emit: the hash cannot tell it from an absent map,
#' so nothing would fail, and the stored file would carry an empty object in every
#' untagged member forever.
#'
#' @param payload A list with `members` and optional set-level `tags`.
#' @return The tidied payload.
#' @keywords internal
.datom_tidy_set_payload <- function(payload) {
  payload$tags <- .datom_tidy_tag_map(payload$tags)
  if (length(payload$tags) == 0L) payload$tags <- NULL

  if (!is.list(payload$members) || !is.null(names(payload$members))) {
    return(payload)
  }

  payload$members <- lapply(payload$members, function(m) {
    if (!is.list(m)) return(m)

    if (is.list(m$id) && !is.null(names(m$id))) {
      m$id <- m$id[order(names(m$id), method = "radix")]
    }

    if ("tags" %in% names(m)) {
      m$tags <- .datom_tidy_tag_map(m$tags)
      if (length(m$tags) == 0L) m$tags <- NULL
    }

    m
  })

  payload
}


#' Deduplicate and Order a Member List for the File
#'
#' Drops exact duplicates -- same `id` **and** same `tags` -- by `datom-sv1`
#' member digest, then sorts by `project`, `name`, `version`.
#'
#' **Two sort keys exist and each has its own reason.** The identity hash orders
#' member digests, which is what keeps the encoder from having to know what an
#' `id` looks like. The file orders by name, which is what keeps an entry in place
#' when its tags change so that `git diff` shows one changed field. `version` is
#' in the key because two versions of one name are legal members, and would
#' otherwise have no defined relative order.
#'
#' **No tiebreaker is required, and none may be added.** The only way two members
#' can share `project` || `name` || `version` is the same `id` with *different*
#' `tags`, which survives dedup because the digest covers tags -- and that payload
#' is refused one step later. R's radix sort is stable, so the tie resolves to
#' caller order in the meantime. A defensive tiebreaker would be dead code.
#'
#' Runs **after** validation, unlike the rest of canonicalization, because the
#' digest is computed by the identity encoder and the encoder refuses a value it
#' cannot encode. Reaching it first would report a bad tag value in the encoder's
#' words rather than the validator's.
#'
#' @param members An unnamed list of validated member records.
#' @return The members, deduplicated and ordered.
#' @keywords internal
.datom_order_set_members <- function(members) {
  if (!is.list(members) || length(members) == 0L) return(members)

  digests <- vapply(
    seq_along(members),
    function(i) {
      .datom_sv1_hex(
        .datom_sv1_member(members[[i]], sprintf("members[[%d]]", i))
      )
    },
    character(1L)
  )
  members <- members[!duplicated(digests)]

  field <- function(which) {
    vapply(members, function(m) as.character(m$id[[which]]), character(1L))
  }

  members[order(
    field("project"), field("name"), field("version"),
    method = "radix"
  )]
}


#' Refuse a Payload Only a Whole-Payload View Can Judge
#'
#' Three refusals that `.datom_validate_members()` deliberately cannot make,
#' because each needs the whole payload rather than one member:
#'
#' * **Zero members.** An empty citable product has no content to identify, and
#'   the recourse is simply to write the set once its first output exists.
#' * **The same `id` listed twice with different `tags`.** Deduplication does not
#'   catch this -- the digest covers tags, so both entries survive -- and the
#'   payload then holds one member twice with conflicting labels, which a consumer
#'   projecting tags into a folder view sees as one artifact in two places.
#'   Refused rather than tidied because both ways to tidy it guess: merging the
#'   tags is right if the caller meant both categories and nonsense if two code
#'   paths disagreed, and picking one entry is arbitrary.
#' * **Self-reference.** A set listing itself, at any version, is refused.
#'
#' **The same `project` and `name` at two different `version`s is legal and must
#' stay legal**: a product carrying a current table beside a locked baseline is
#' atypical and entirely sensible. So the duplicate check keys on the **full**
#' `id`, never on `project` + `name` -- which is the tightening that looks natural
#' and would break that use silently.
#'
#' **Self-reference is a nonsense check, not cycle detection.** Cycles are
#' structurally impossible: a member pins a version that already exists, so a set
#' cannot reference anything containing it. Nothing here may grow into a visited
#' set or a depth limit.
#'
#' @param payload A tidied, validated, ordered payload.
#' @param name The set's own name.
#' @param project The set's own project.
#' @return Invisibly `TRUE`.
#' @keywords internal
.datom_check_set_payload <- function(payload, name, project) {
  members <- payload$members

  if (!is.list(members) || length(members) == 0L) {
    cli::cli_abort(
      c(
        "A set must have at least one member.",
        "i" = "An empty set has no content to identify, so it cannot be cited.",
        "i" = "Declare members with {.fn datom_member} and write the set once \\
               its first output exists."
      ),
      class = "datom_set_empty"
    )
  }

  # "\r" as the separator rather than "/" or "-": an artifact name may hold a
  # space, a hyphen or parentheses, so a printable separator could in principle be
  # part of a field and make two different ids collide into one key.
  id_key <- vapply(
    members,
    function(m) paste(m$id$project, m$id$name, m$id$version, sep = "\r"),
    character(1L)
  )

  duplicated_ids <- unique(id_key[duplicated(id_key)])
  if (length(duplicated_ids) > 0L) {
    offender <- members[[match(duplicated_ids[[1L]], id_key)]]$id
    cli::cli_abort(
      c(
        "Member {.val {offender$name}} is listed twice with different tags.",
        "i" = "One version of one artifact is one member, and it holds one set \\
               of labels.",
        "i" = "To put it in two categories, give one key several values: \\
               {.code list(type = c(\"input\", \"output\"))}.",
        "i" = "Two different {.emph versions} of one artifact are two members, \\
               and that is not this case."
      ),
      class = "datom_set_member_conflict"
    )
  }

  refers_to_self <- vapply(
    members,
    function(m) {
      identical(m$id$project, project) && identical(m$id$name, name)
    },
    logical(1L)
  )

  if (any(refers_to_self)) {
    cli::cli_abort(
      c(
        "A set cannot list itself as a member.",
        "x" = "{.val {name}} in project {.val {project}} appears in its own \\
               member list.",
        "i" = "Remove that member. Referring to an earlier version of itself \\
               would terminate, but it states nothing a consumer can use."
      ),
      class = "datom_set_self_reference"
    )
  }

  invisible(TRUE)
}


# --- the write verb ------------------------------------------------------------

#' Write a datom Set
#'
#' Writes a **set**: a versioned, citable, content-addressed collection of
#' pointers at existing datom artifacts. A set holds no data of its own -- its
#' payload is the member list plus text labels -- so writing one neither copies
#' nor moves anything a member contains.
#'
#' One repo holds one set. The repo declares which, in `.datom/project.yaml`:
#'
#' ```yaml
#' mode: product
#' set: study001-adam
#' ```
#'
#' Both are checked before anything is hashed or written, so a repo that has not
#' declared itself a product repo is refused with nothing left behind.
#'
#' @section What a set carries, and what it does not:
#' User metadata is **tags**, and there is no `metadata =` parameter: a
#' description is a tag, and a second channel for the same thing would be two
#' places to look. There is no view or navigation configuration either -- a
#' folder-like hierarchy is a projection a consumer computes over tags, and any
#' number of them cost nothing precisely because none is stored.
#'
#' A set records **no** `parents` and **no** `source_lineage`. Members are
#' references, not derivation: lineage flows through tables, and the set is how
#' you *found* a table rather than how data reached it.
#'
#' @section Versions, and what moves one:
#' The version covers the **whole payload**, members and tags alike. So editing a
#' tag or a description mints a new version, which is intended: a set exists to be
#' citable, and "same citation, different labels" would be a lie to whoever cited
#' it. What does **not** mint a version is a purely syntactic edit -- reordering
#' tag values or members, repeating a label, or writing a single label as a
#' one-element array. Those are normalised on the way in, so re-writing an
#' identical payload is a no-op.
#'
#' @section Where the payload lives:
#' Two copies, at two deliberately different addresses. Git holds
#' `{name}/set.json` at one stable path, modified in place, so git carries the
#' history and `git diff` between two versions shows which members changed.
#' Storage holds the same bytes content-addressed at `{name}/{data_sha}.json`, so
#' a reader with no clone can fetch an exact version. Any past version is still
#' reconstructible from the clone alone with
#' `git show <commit>:{name}/set.json`.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()], scoped to the
#'   product repo (developer role).
#' @param members A list of member records from [datom_member()], each pinning one
#'   artifact version and optionally carrying its own tags. Hand-assembled lists
#'   are refused.
#' @param tags Optional named list of set-level text labels -- facts about the
#'   collection itself, such as a description. Same grammar as a member's tags: a
#'   value is one string or several, text only.
#' @param name The set's name. Defaults to the `set:` field in
#'   `.datom/project.yaml`; when supplied it must equal it.
#' @param message Optional commit message.
#'
#' @return Invisibly, a list with `name`, `data_sha`, `metadata_sha` (the
#'   version), `member_count` (the count after normalisation), `action`
#'   (`"none"` or `"full"`) and `commit_sha`.
#' @seealso [datom_member()] to declare a member, [datom_write()] for tables.
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
#'
#'   # Declare the repo a product repo and name its set. A later release writes
#'   # these two fields at init time; today they are added by hand.
#'   cfg_path <- file.path(tmp, "repo", ".datom", "project.yaml")
#'   cfg <- yaml::read_yaml(cfg_path)
#'   cfg$mode <- "product"
#'   cfg$set <- "example_product"
#'   yaml::write_yaml(cfg, cfg_path)
#'
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # A set points at versions that already exist.
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'   datom_write(conn, data = datom_example_data("lb"), name = "lb")
#'
#'   members <- list(
#'     datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
#'                  tags = list(type = "input")),
#'     datom_member(conn, "lb", datom_history(conn, "lb")$version[1],
#'                  tags = list(type = "output", domain = c("safety", "labs")))
#'   )
#'
#'   datom_write_set(
#'     conn, members,
#'     tags = list(description = "Example product for STUDY-001")
#'   )
#'
#'   print(datom_list(conn))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_write_set <- function(conn, members, tags = NULL, name = NULL,
                            message = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Write operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Write operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # The two gates run first because they are what establish WHICH artifact this
  # write touches -- the forward-compatibility door below needs that name, and
  # handing it NULL would silently widen the door to every artifact in the clone.
  name <- .datom_check_set_write_gates(conn, name)

  # Forward-compatibility door. A new write verb inherits nothing from the three
  # routes that already call this, so leaving it out would silently skip the
  # writer floor, the format check and the vocabulary check for every set write.
  # Above all hashing and every local write, so a refusal leaves nothing behind.
  .datom_check_write_entry(conn, name)

  # Write-time ref guard: ensure the data location has not moved.
  .datom_check_ref_current(conn)

  # Tidy, then validate what remains, then order. The order is not style: the
  # validator deliberately PASSES a tag key whose value is empty, because that is
  # a tidy case, so validating first would make that rule unreachable.
  payload <- .datom_tidy_set_payload(list(tags = tags, members = members))

  .datom_validate_tag_map(
    payload$tags, "tags",
    remedy = "Set-level tags describe the collection itself, e.g. \\
              {.code list(description = \"ADaM datasets for STUDY-001\")}."
  )
  .datom_validate_members(payload$members)

  payload$members <- .datom_order_set_members(payload$members)
  .datom_check_set_payload(payload, name, conn$project_name)

  # Identity over the canonical payload, then the version over the metadata
  # document. `document_sha` is not knowable yet -- it hashes the stored bytes --
  # and it is outside identity, so the version does not wait for it.
  meta <- .datom_build_set_metadata(payload)
  data_sha <- meta$data_sha
  metadata_sha <- .datom_compute_metadata_sha(meta)

  chg <- .datom_has_changes(conn, name, data_sha, metadata_sha)
  change_type <- chg$change_type

  # One name is one artifact, checked against the document change detection has
  # just read rather than against the manifest, which can lag behind a write that
  # got partway through.
  .datom_check_artifact_kind(chg$current, name, "set")

  if (change_type == "none") {
    cli::cli_alert_info(
      "No changes detected for set {.val {name}}. Skipping write."
    )
    return(invisible(list(
      name = name,
      data_sha = data_sha,
      metadata_sha = metadata_sha,
      member_count = length(payload$members),
      action = "none"
    )))
  }

  # The git copy at its stable path, and the bytes every other hash refers to.
  # Written before the metadata document so `document_sha` can describe real
  # bytes, and it is the same file that gets uploaded, so the git and storage
  # copies cannot hold two spellings of one `data_sha`.
  set_dir <- fs::path(conn$path, name)
  fs::dir_create(set_dir)
  payload_path <- fs::path(set_dir, "set.json")
  jsonlite::write_json(payload, payload_path, auto_unbox = TRUE, pretty = TRUE)

  new_document_sha <- digest::digest(file = payload_path, algo = "sha256")

  document_decision <- .datom_resolve_document_sha(
    conn, name, data_sha, new_document_sha, change_type, chg$current
  )
  meta$document_sha <- document_decision$document_sha

  # A set records `document_sha` from its first write, so there is no legacy
  # population to be lenient about -- and being lenient here would write a
  # document whose declared-but-unpopulated field serialises as `{}`, which a
  # later read cannot verify and cannot distinguish from corruption.
  if (is.null(meta$document_sha)) {
    cli::cli_abort(
      c(
        "The recorded metadata for set {.val {name}} carries no \\
         {.field document_sha}.",
        "i" = "Every version of a set records the hash of its stored payload; \\
               a version without one cannot be verified on read.",
        "i" = "Run {.fn datom_validate} on this project."
      ),
      class = "datom_set_document_sha_missing"
    )
  }

  # Keep any top-level field the existing document holds that this build cannot
  # place -- the document above was rebuilt from scratch, which would delete it.
  meta <- .datom_carry_unknown_fields(
    meta,
    .datom_prior_metadata(conn, name),
    .datom_metadata_known_fields()
  )

  write_result <- .datom_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = message
  )
  .datom_update_manifest_entry(
    conn, name,
    metadata_sha = metadata_sha,
    data_sha = data_sha,
    kind = "set",
    # The count AFTER normalisation, which is the canonical one: tidying can drop
    # an exact duplicate, so it can differ from what the caller passed.
    member_count = length(payload$members)
  )

  # The payload joins the commit explicitly: `.datom_write_metadata_local()`
  # returns the metadata and history paths only, and a set has a third file.
  commit_sha <- .datom_commit_and_mirror(
    conn, name, meta, metadata_sha,
    git_paths = c(write_result$git_paths, payload_path),
    message = message %||% paste0("Update ", name),
    upload = if (isTRUE(document_decision$upload)) {
      list(
        path = payload_path,
        key = .datom_artifact_payload_key(name, data_sha, "set")
      )
    } else {
      NULL
    }
  )

  n_members <- length(payload$members)
  cli::cli_alert_success(
    "Wrote set {.val {name}} ({n_members} member{?s}): \\
     {.val {substr(metadata_sha, 1, 8)}}"
  )

  invisible(list(
    name = name,
    data_sha = data_sha,
    metadata_sha = metadata_sha,
    member_count = n_members,
    action = change_type,
    commit_sha = commit_sha
  ))
}
