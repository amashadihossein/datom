# Sets: the second artifact kind, written and read.
#
# A set is a reference layer, not a data layer. Its payload is a JSON document of
# pointers at existing artifact versions plus text labels, and everything else --
# version history, content addressing, change detection, the git-gates-storage
# ordering -- is the same machinery a table write uses.
#
# THE WRITE CANONICALIZES; THE READ NEVER DOES. Every "same fact, two spellings"
# decision is made once, on the way in. The read parses, normalizes
# REPRESENTATION only (the three R shapes a JSON string array comes back as), and
# reshapes nothing -- see `.datom_read_set_payload()` for what that costs if it is
# undone.
#
# FIVE THINGS ON THE WRITE SIDE ARE LOAD-BEARING AND EASY TO UNDO BY TIDYING.
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
#      written while the field is still unpopulated has every expected key and one
#      of them is an empty object. A names-only field-set check cannot see that,
#      which is why the tests assert on the written bytes.
#
# There is deliberately NO cycle detection, no visited-set guard, and no depth
# limit. A member pins an immutable version and declaring one requires that
# version to already exist, so a set cannot reference anything that contains it.
# The self-reference refusal below is a nonsense check, not cycle detection.


# --- the two gates -------------------------------------------------------------

#' Refuse a Set Write the Repo Has Not Declared
#'
#' Checks that read the clone's `.datom/project.yaml` directly, all of them before
#' anything is hashed or written:
#'
#' 1. The config's declared format must be one this build can read
#'    ([.datom_check_project_schema()]). It runs first because the two checks
#'    below read fields *out of* this file: a future format that renamed or moved
#'    `set:` would make check 3 report "this repo declares `mode: product` but
#'    names no set" and send the user to hand-edit a file that is already correct.
#'    An actionable-looking message that is wrong is worse than no answer. The
#'    connection-time gate does not make this one redundant -- the file can be
#'    hand-edited or pulled between opening a connection and writing through it,
#'    which is the same reason the forward-compatibility door is re-run after a
#'    route's own pull.
#' 2. The repo must declare `mode: product`. A set written into a repo that does
#'    not is a set with no declared owner, which defeats the one below it too.
#' 3. The set's name must be the one the repo declares under `set:`. This is what
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
#' **`datom_init_repo(mode = "product", set = <name>)` is what declares both
#' fields**, so the supported route into this check is a repo created that way. It
#' shipped inert one release earlier, on purpose: a build that can *notice* the
#' declaration has to exist before anything writes it, or the declaration reaches
#' installs that walk straight past it. Hand-editing the file still works and some
#' fixtures do it, which is also what a repo created before that argument existed
#' needs.
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

  # Before either field is read out of the file, not after: the checks below
  # report on `mode` and `set`, so a format this build cannot read would turn
  # them into confident advice about the wrong thing.
  .datom_check_project_schema(cfg, source = yaml_path, operation = "write")

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


#' Check the Caller's Extra Paths Before a Set Write Does Anything
#'
#' `include_paths` is the **only** way a commit datom makes on its own initiative
#' may carry a path datom does not own, and it is allowed only because the caller
#' enumerated it (R14.3). What it buys is that checking out a set version's commit
#' yields the data pointers **and** the code and environment that produced them.
#' So every refusal here is a refusal to produce a commit that would claim more
#' than it holds.
#'
#' Four refusals, in this order, each with its own condition class:
#'
#' 1. **Not a path inside the clone.** An absolute path, or one climbing out
#'    through `..`, refused lexically before the filesystem is touched.
#'    `fs::path()` joins an absolute second argument *onto* the clone path rather
#'    than replacing it, so `/etc/passwd` would otherwise be reported as a missing
#'    path inside the repo -- a correct refusal whose message names the wrong
#'    thing.
#' 2. **A datom-owned path.** `.datom/`, the set being written, and any artifact
#'    directory already in the clone. The write stages those itself, so listing one
#'    is either a misunderstanding or an attempt to hand-place a datom document
#'    into a commit through a caller's argument.
#' 3. **A path that does not exist.** An error, never a skip: a joint commit is
#'    deterministic or it is refused.
#' 4. **A path git is ignoring.** `git2r::add()` on a gitignored path raises
#'    nothing and stages nothing, and [.datom_git_commit()] cannot notice, because
#'    it objects only when the staging area ends up empty and datom's own files are
#'    always in it. The commit would therefore succeed while omitting exactly the
#'    file the caller named, and the set version would claim a joint commit it does
#'    not have. Refused rather than dropped in silence (decided 2026-09-18).
#'
#' **This runs before the first hash and the first local write**, the same
#' placement as the two gates above, so a refused joint commit leaves nothing
#' behind. One consequence, stated so nobody later softens it: change detection
#' needs the hashes, so a bad path is an error **even when the set is unchanged**.
#' The refusal wins over the no-op.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name The set being written, as resolved by
#'   [.datom_check_set_write_gates()]. Named rather than discovered because a
#'   first write has no directory to discover.
#' @param include_paths The caller's character vector, or `NULL`.
#' @return Absolute paths in the clone, or `NULL`. **Absolute**, because
#'   [.datom_commit_and_mirror()] relativises what it is given against `conn$path`,
#'   and `fs::path_rel()` on an already-relative path resolves it against the
#'   working directory instead -- which aborts with "files do not exist" pointing
#'   somewhere the caller never named.
#' @keywords internal
.datom_check_include_paths <- function(conn, name, include_paths) {
  if (is.null(include_paths)) return(NULL)

  if (!is.character(include_paths) || length(include_paths) == 0L ||
      anyNA(include_paths) || !all(nzchar(include_paths))) {
    cli::cli_abort(
      c(
        "{.arg include_paths} must be a non-empty character vector of \\
         repo-relative paths, or {.code NULL}.",
        "i" = "For example {.code include_paths = c(\"R\", \"renv.lock\")}.",
        "i" = "You passed {.cls {class(include_paths)}}."
      ),
      class = "datom_include_paths_invalid"
    )
  }

  paths <- as.character(include_paths)

  # Lexically normalised once, and every check below reads the normalised form.
  # `./dp/x` and `dp/x` are one path, and an owned-path check that split the raw
  # string would let `./.datom/manifest.json` past a check that `.datom/...` fails.
  # Nothing here touches the filesystem, so a path that does not exist still
  # reaches its own refusal below with the spelling the caller used.
  normalised <- as.character(fs::path_norm(paths))
  segments <- fs::path_split(normalised)
  first <- purrr::map_chr(segments, function(s) s[[1L]])

  # Escape is judged AFTER normalising, so `a/../b` is `b` and allowed while
  # `../a` and `/etc/passwd` are not. Refusing every `..` would refuse a path that
  # never leaves the clone.
  outside <- fs::is_absolute_path(normalised) | first == ".."
  if (any(outside)) {
    cli::cli_abort(
      c(
        "{.arg include_paths} takes paths relative to the repo root, and these \\
         lead outside it:",
        purrr::set_names(paths[outside], rep("x", sum(outside))),
        "i" = "The set's commit is made in {.path {conn$path}}; a path outside \\
               the clone cannot be part of it."
      ),
      class = "datom_include_path_outside_repo"
    )
  }

  # The set being written is named rather than discovered: on a first write its
  # directory does not exist yet, so the artifact listing cannot see it.
  owned <- c(".datom", name, .datom_clone_artifact_names(conn))
  is_owned <- first %in% owned
  if (any(is_owned)) {
    cli::cli_abort(
      c(
        "{.arg include_paths} names paths datom owns:",
        purrr::set_names(paths[is_owned], rep("x", sum(is_owned))),
        "i" = "The set's payload, its metadata and {.file .datom/manifest.json} \\
               are staged by the write itself.",
        "i" = "{.arg include_paths} is for content datom does not own -- code, \\
               {.file renv.lock}, build state."
      ),
      class = "datom_include_path_datom_owned"
    )
  }

  absolute <- fs::path(conn$path, normalised)
  # `fs::file_exists()` is an access test, so a directory answers TRUE -- which is
  # wanted: a build package lists `R/` and `tests/`, not every file under them.
  gone <- !fs::file_exists(absolute)
  if (any(gone)) {
    cli::cli_abort(
      c(
        "{.arg include_paths} names paths that do not exist in \\
         {.path {conn$path}}:",
        purrr::set_names(paths[gone], rep("x", sum(gone))),
        "i" = "A joint commit is deterministic or it is refused, so a missing \\
               path is an error rather than a skipped entry."
      ),
      class = "datom_include_path_missing"
    )
  }

  ignored <- .datom_git_ignored(conn$path)
  # Directory-aware, because git reports an ignored DIRECTORY (`cache/`) and
  # never the files inside it, while the caller may name either.
  is_ignored <- purrr::map_lgl(normalised, function(p) {
    any(purrr::map_lgl(ignored, function(g) {
      identical(p, g) || startsWith(p, paste0(g, "/"))
    }))
  })
  if (any(is_ignored)) {
    cli::cli_abort(
      c(
        "{.arg include_paths} names paths {.file .gitignore} excludes:",
        purrr::set_names(paths[is_ignored], rep("x", sum(is_ignored))),
        "i" = "git stages an ignored path silently and reports nothing, so the \\
               set version would claim a commit that omits it.",
        "i" = "Un-ignore the path, or drop it from {.arg include_paths}."
      ),
      class = "datom_include_path_ignored"
    )
  }

  as.character(absolute)
}


#' Paths git Is Ignoring in a Clone
#'
#' `git2r::status(ignored = TRUE)` is the only route -- git2r exposes no
#' check-ignore verb -- and it reports an ignored **directory** with a trailing
#' slash and does not recurse into it, so a caller's path has to be matched
#' against these as prefixes rather than compared for equality. The trailing slash
#' is stripped here so one comparison covers a file entry and a directory entry.
#'
#' Only ever called from [.datom_check_include_paths()], and only when the caller
#' supplied paths, so no existing write gains a git read.
#'
#' @param path Repository path.
#' @return Character vector of ignored paths, possibly empty, without trailing
#'   slashes.
#' @keywords internal
.datom_git_ignored <- function(path) {
  .datom_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  entries <- git2r::status(
    repo,
    staged = FALSE, unstaged = FALSE, untracked = FALSE, ignored = TRUE
  )$ignored

  sub("/+$", "", unlist(entries, use.names = FALSE))
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
#' Key order is canonicalized at **three** levels, not two: the set's own tag
#' map, each member's `id`, and each member record's own `id` / `tags` pair.
#' Stopping at the second leaves one spelling uncanonical for no reason -- the
#' encoder reaches both member slots by name, so the two orders hash identically
#' and serialise differently.
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

    # The record's OWN two keys, for exactly the reason `id`'s are sorted above:
    # the encoder reaches both slots by name, so `tags` before `id` hashes
    # identically to `id` before `tags` while serialising to different bytes --
    # two byte spellings of one `data_sha`, which is the state `document_sha`
    # cannot survive. It bites on a revert, where the clone's payload is rewritten
    # from the current spelling while the stored object is reused: git would then
    # hold bytes that do not match the recorded hash and storage would hold bytes
    # that do. Reachable only from a hand-built record, since `datom_member()`
    # emits `id` first and a JSON round trip preserves that -- but a member is
    # documented as pure data, so hand-built records are supported input.
    # Alphabetically this is `id`, `tags`, the order already emitted, so no
    # existing payload changes.
    #
    # Guarded rather than unconditional: `order(NULL)` is `integer(0)`, so
    # sorting a record with no names would empty it instead of leaving it for the
    # validator to report.
    if (!is.null(names(m)) && all(nzchar(names(m)))) {
      m <- m[order(names(m), method = "radix")]
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
               its first output exists.",
        # A caller who got here through a draft never called `datom_member()` and
        # would go looking for the wrong verb.
        "i" = "Building the set in steps? Add one with {.fn datom_add_member} \\
               before writing the draft."
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


#' Drop the `$fetch` Link a Read Puts on Every Member
#'
#' The one step that makes read-modify-write possible. A member record is
#' payload-shaped -- exactly `id` plus optional `tags` -- and
#' [datom_get_set()] adds a callable `fetch` to each one, which both
#' `.datom_validate_members()` and the sv1 encoder refuse. Removing it here means
#' neither of them needs a carve-out for a field that must never reach a payload.
#'
#' **Only a function is dropped.** A hand-built `fetch = "junk"` is left in place
#' so the validator reports it; stripping by name would turn a typo into a silent
#' success.
#'
#' @param members A member list.
#' @return The member list with any callable `fetch` element removed.
#' @keywords internal
.datom_strip_member_links <- function(members) {
  if (!is.list(members) || length(members) == 0L) return(members)

  lapply(members, function(m) {
    if (!is.list(m) || !("fetch" %in% names(m))) return(m)
    if (!is.function(m[["fetch"]])) return(m)
    m[names(m) != "fetch"]
  })
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
#' **Your code does not move a version either, even though it travels in the same
#' commit** (see `include_paths` below). Refactor your build script, re-run it,
#' get the same members and tags, and nothing is minted: the write is the usual
#' no-op. [datom_history()] then shows the version it showed before, with a
#' `commit_sha` pointing at the commit that **first** produced that payload -- a
#' commit that does not contain the code you just wrote. That is the recorded
#' value doing its job rather than going stale; see [datom_history()] for why the
#' commit is deliberately not part of the version.
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
#' @section Carrying your code and environment into the same commit:
#' `include_paths` stages paths you name into the **one** commit that carries the
#' payload and its metadata. So checking out a set version's commit yields the
#' data pointers, the logic that produced them **and** the environment they ran in
#' -- one clone, one checkout, the whole product. The joint version is
#' **structural**: nothing records a link between the set and your files, because
#' the commit *is* the link.
#'
#' ```r
#' datom_write_set(conn, members,
#'                 include_paths = c("R", "dp", "renv.lock"))
#' ```
#'
#' Four refusals, all of them before anything is hashed or written, so a refusal
#' leaves nothing behind: a path that does not exist, a path outside the clone, a
#' path datom owns (`.datom/`, the set, any artifact directory), and a path
#' `.gitignore` excludes. The last one matters because git stages an ignored path
#' silently and without complaint, which would leave the set version claiming a
#' commit that omits exactly the file you named. Refusals win over the no-op
#' below, since they are settled before change detection runs.
#'
#' **An unchanged set is still a no-op, however dirty those paths are.** No
#' commit, no version, and a message pointing at [datom_repo_commit()], which is
#' the verb for committing your own content at a moment you chose. A data write
#' that quietly committed work in progress is the thing datom's explicit file
#' lists exist to prevent, and idempotency must not become a side door into it.
#'
#' @section Editing a set that already exists:
#' Read it, change it, write it back. `members` accepts a `datom_set` from
#' [datom_get_set()] directly, so the loop needs no unpacking:
#'
#' ```r
#' x <- datom_get_set(conn, "study001-adam")
#' x$members <- c(x$members, list(datom_member(conn, "lb", v)))
#' datom_write_set(conn, x)
#' ```
#'
#' The set's own `tags` come along with it unless `tags` is supplied, so a
#' read-append-write cannot silently drop the description. Passing
#' `x$members` instead works too, and there `tags` is yours to carry.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()], scoped to the
#'   product repo (developer role) -- or a `datom_set_draft` from
#'   [datom_assemble_set()], which already carries its connection, name, members
#'   and tags, so a pipe ends `|> datom_write_set()` with nothing typed. The
#'   checks below are the same either way.
#' @param members A list of member records from [datom_member()], each pinning one
#'   artifact version and optionally carrying its own tags -- or a `datom_set`
#'   from [datom_get_set()], to write back a set that was read. Hand-assembled
#'   lists are refused.
#' @param tags Optional named list of set-level text labels -- facts about the
#'   collection itself, such as a description. Same grammar as a member's tags: a
#'   value is one string or several, text only.
#' @param name The set's name. Defaults to the `set:` field in
#'   `.datom/project.yaml`; when supplied it must equal it.
#' @param message Optional commit message. Omitted, it is `Update {name}` --
#'   except for a set that came from [datom_update_members()], where the default
#'   names the members that moved and their old and new versions. Pass `x` rather
#'   than `x$members` to get that, since the change list travels with the object.
#' @param include_paths Optional character vector of repo-relative paths -- your
#'   own code, `renv.lock`, build state -- staged into the **same commit** as the
#'   set. Never mirrored to storage: the storage namespace holds datom artifacts
#'   and nothing else. See the section below.
#'
#' @return Invisibly, a list with `name`, `data_sha`, `metadata_sha` (the
#'   version), `member_count` (the count after normalisation), `action`
#'   (`"none"` or `"full"`) and `commit_sha`.
#' @seealso [datom_member()] to declare a member, [datom_assemble_set()] to build
#'   a set a member at a time, [datom_write()] for tables.
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
#'   # A product repo declares itself as one and names the single set it owns.
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store,
#'                   mode = "product", set = "example_product")
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
                            message = NULL, include_paths = NULL) {

  # TWO INDEPENDENT WIDENINGS ON TWO DIFFERENT PARAMETERS. `members` accepts a
  # `datom_set` (a set read back, unpacked further down); `conn` accepts a
  # `datom_set_draft`, so a pipe ends `|> datom_write_set()` with nothing typed.
  # They are separate branches on separate arguments -- extending either one must
  # leave the other alone.
  #
  # THE UNPACK RUNS BEFORE THE THREE GUARDS BELOW. A draft in the `conn` position
  # fails `inherits(conn, "datom_conn")`, so leaving the guards first would abort
  # a correct pipe by naming an argument the user never typed.
  #
  # `missing(members)`, NEVER `is.null(members)`. On the correct call --
  # `datom_write_set(draft)` -- `members` has no value and the formal has no
  # default, so evaluating it errors with R's own "argument is missing" instead of
  # reporting the conflict this refuses. Nothing may touch `members` before the
  # rebind below.
  # An edit verb's log of what it changed rides as an ATTRIBUTE on the object it
  # edited, so it cannot reach the payload -- the unpack below takes `tags` and
  # `members` and nothing else. Read here, before either unpack, because both of
  # them replace the value the attribute is on. It defaults the commit message and
  # nothing else; a caller who passes `x$members` instead of `x` simply gets
  # today's default.
  edits <- NULL

  if (inherits(conn, "datom_set_draft")) {
    if (!missing(members)) {
      cli::cli_abort(
        c(
          "A draft already carries its members, and {.arg members} was \\
           supplied as well.",
          "i" = "Write the draft on its own -- {.code datom_write_set(draft)} \\
                 -- or pass a member list together with a connection.",
          "i" = "Preferring one over the other would write a set you did not \\
                 describe."
        ),
        class = "datom_draft_members_conflict"
      )
    }

    draft <- conn
    edits <- attr(draft, "datom_edits")
    conn <- draft$conn
    # The draft's name and tags are DEFAULTS, exactly as a `datom_set`'s tags are
    # below: an explicitly supplied one wins, so a draft can be written under
    # different labels without rebuilding it.
    if (is.null(tags)) tags <- draft$tags
    if (is.null(name)) name <- draft$name
    members <- draft$members
  }

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(c(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}, or a \\
       {.cls datom_set_draft} from {.fn datom_assemble_set}.",
      "i" = "You passed {.cls {class(conn)}}."
    ))
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

  # A read-modify-write loop hands this verb back what `datom_get_set()`
  # returned, and that value is not payload-shaped: the set's tags sit beside its
  # member list, and every member carries a `fetch` closure. Both are fixed here,
  # in the write verb, and NOT by relaxing `.datom_validate_members()` or the sv1
  # encoder -- both of those keep saying "a member is exactly `id` plus `tags`",
  # and the write is what knows how to get from a read back to a payload.
  #
  # `fetch` is dropped only when it is a FUNCTION, so a hand-built
  # `fetch = "junk"` still reaches the validator and aborts. Stripping by name
  # alone would turn a typo into a silent success.
  if (inherits(members, "datom_set")) {
    if (is.null(tags)) tags <- members$tags
    edits <- attr(members, "datom_edits")
    members <- members$members
  }
  members <- .datom_strip_member_links(members)

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

  # The caller's own paths, checked here rather than at the commit call, so every
  # refusal lands above the first hash and the first local write. After the gates
  # because the owned-path check needs the resolved set name.
  include_paths <- .datom_check_include_paths(conn, name, include_paths)

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
  # `project` is the repo's own declaration -- a set write requires a clone, and a
  # connection built from one reads the name out of `.datom/project.yaml`.
  meta <- .datom_build_set_metadata(payload, project = conn$project_name)
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

    # THIS RETURN SITS ABOVE EVERY LINE THAT STAGES A FILE -- the payload write,
    # the metadata document, the manifest row and the single commit call are all
    # below it -- and that placement is the whole of the no-side-channel
    # guarantee. Nothing checks it, so do not move the return and do not move a
    # staging step above it.
    #
    # The message exists because silence here reads as success: a caller who
    # listed paths asked for a commit and did not get one, so name the verb that
    # makes one at a moment they choose. Committing them anyway would be the
    # add-all failure that datom's explicit file lists exist to prevent, arriving
    # through idempotency's door.
    if (!is.null(include_paths)) {
      cli::cli_alert_info(
        "{.arg include_paths} was not committed -- an unchanged set makes no \\
         commit. Commit those paths with {.fn datom_repo_commit}."
      )
    }

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

  # `Update {name}` says nothing in `git log`, so a write of a set that was edited
  # names what changed instead -- repoints and removals alike, since both verbs
  # append to one log. One line is recorded as this version's commit message,
  # where `datom_history()` can show it; the commit itself carries the full list.
  messages <- .datom_set_commit_messages(name, message, edits)

  write_result <- .datom_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = messages$history
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
  #
  # `include_paths` joins the SAME call, which is what makes the joint version
  # structural: one commit contains the payload, the metadata and the caller's
  # files. A second commit for them would leave two versions of "what produced
  # this set" and no way to say which one the set pins. `NULL` drops out of
  # `c()`, so a write with no extra paths is byte-for-byte the previous one.
  commit_sha <- .datom_commit_and_mirror(
    conn, name, meta, metadata_sha,
    git_paths = c(write_result$git_paths, payload_path, include_paths),
    message = messages$commit,
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


#' Which Project a Set Reports Itself As Belonging To
#'
#' Two steps, not the three [.datom_declared_project()] uses: the set's own
#' metadata document, then the connection's name. See the call site in
#' [datom_get_set()] for why the manifest step is deliberately absent here.
#'
#' @param current The set's `metadata.json`, as already read by the set read.
#' @param conn The connection the set was read through.
#' @return A single string, or whatever the connection carries.
#' @keywords internal
.datom_set_project <- function(current, conn) {
  recorded <- if (is.list(current) && "project" %in% names(current)) {
    current$project
  }
  if (.datom_is_text_scalar(recorded)) return(recorded)

  conn$project_name
}


# --- the read path -------------------------------------------------------------
#
# THE READ NEVER TIDIES, AND THE TIDY FUNCTIONS ARE RIGHT THERE INVITING IT.
# `.datom_tidy_set_payload()` run on a healthy payload changes nothing -- the
# write already canonicalized -- so reaching for it passes every test today and
# diverges later. Three reasons it must not be reached for, in order:
#
#   1. LOAD-BEARING. Repair must neither re-upload payload bytes nor recompute
#      `document_sha` for a version already stored. A repair built on a tidying
#      read does both: it re-emits reshaped bytes over an object whose recorded
#      hash describes different bytes.
#   2. THE READ REPORTS WHAT WAS CITED. A reorder must not mint a version; that
#      does not license a reader to perform one.
#   3. DROPPING AN EMPTY-VALUED KEY removes a key the document actually contains.
#
# The one thing the read does normalize is representation: `jsonlite` unboxes on
# write, so one tag key comes back as a character vector, a length-1 character, or
# a list of length-1 characters, depending on how many labels it had. Those are
# three R spellings of one JSON value, not three values. Never touch the presence
# axis: an absent key stays absent, an absent value stays NULL, and nothing
# becomes `character(0)` or `NA`.


#' Normalize a Parsed JSON String Array to a Character Vector
#'
#' `jsonlite::fromJSON(simplifyVector = FALSE)` returns a JSON array of strings
#' as a list of length-1 characters, and `auto_unbox = TRUE` on the write means a
#' single label was written as a bare string. So one tag key comes back in three
#' shapes -- `character(1)`, a list of 1, or a list of n -- for what is one value
#' in the document.
#'
#' Same strings, same order, same count: this is a representation change, not a
#' content change, which is why order is preserved and duplicates are kept.
#' Sorting or deduplicating here would be the write's canonicalization performed
#' by a reader.
#'
#' Anything that is not an all-text array is returned untouched. A reader has no
#' caller intent to tidy toward and nothing downstream requires tag values to be
#' text, so an odd value is reported by whoever tries to use it rather than
#' refused here.
#'
#' @param v A parsed JSON value.
#' @return A character vector when `v` was an all-text array, otherwise `v`.
#' @keywords internal
.datom_read_string_array <- function(v) {
  if (!is.list(v) || !is.null(names(v)) || length(v) == 0L) return(v)

  strings <- vapply(
    v,
    function(e) is.character(e) && length(e) == 1L && !is.na(e),
    logical(1L)
  )
  if (!all(strings)) return(v)

  unlist(v, use.names = FALSE)
}


#' Normalize a Parsed Tag Map's Values
#'
#' Applies [.datom_read_string_array()] to every value and does nothing else: no
#' key sorting, no value sorting, no deduplication, no dropping of an
#' empty-valued key. A map with no names is returned untouched rather than
#' refused, for the same reason a single odd value is.
#'
#' @param tags A parsed tag map, or `NULL`.
#' @return The map with each value normalized, or `NULL`.
#' @keywords internal
.datom_read_tag_map <- function(tags) {
  if (is.null(tags) || !is.list(tags) || length(tags) == 0L) return(tags)
  if (is.null(names(tags))) return(tags)

  tags[] <- lapply(tags, .datom_read_string_array)
  tags
}


#' Normalize One Member Record Read Back from a Payload
#'
#' Normalizes representation in `id` and `tags`, then makes the one refusal the
#' read owns: an `id` field that is not a single non-empty string after
#' normalization aborts as a malformed document, naming the member.
#'
#' **Why `id` is refused where a tag value is tolerated.** `id` values are
#' spliced into storage keys and compared against project names, and
#' `.datom_validate_members()` enforces that contract on **write only** -- so the
#' read is the only place a payload's `id` is ever checked. Normalizing without
#' refusing would silently accept a document `datom_write_set()` cannot produce,
#' and a caller comparing a list against a string would conclude that a member of
#' this project belongs to another one.
#'
#' Fields outside the four are left alone rather than refused: a newer datom may
#' have added one, and this build never reads it.
#'
#' @param m One parsed member record.
#' @param at Position label used in error messages, e.g. `"members[[2]]"`.
#' @param name The set's name, for error messages.
#' @return The member record, normalized.
#' @keywords internal
.datom_read_set_member <- function(m, at, name) {
  # `.envir` is passed through because cli interpolates in the frame that CALLS
  # cli_abort, which here is this helper -- and the values worth naming (`fld`)
  # live in the frame that called the helper.
  malformed <- function(..., .envir = parent.frame()) {
    cli::cli_abort(
      c(
        "The stored payload for set {.val {name}} is malformed.",
        ...,
        "i" = "Run {.fn datom_validate} on the project that owns this set."
      ),
      class = "datom_set_member_malformed",
      .envir = .envir
    )
  }

  if (!is.list(m) || is.null(names(m)) || !all(nzchar(names(m)))) {
    malformed("x" = "{at} is not a named record.")
  }

  id <- m$id
  if (!is.list(id) || length(id) == 0L || is.null(names(id))) {
    malformed("x" = "{at} has no {.field id} map.")
  }

  id[] <- lapply(id, .datom_read_string_array)

  purrr::walk(c("project", "name", "kind", "version"), function(field) {
    fld <- paste0("id$", field)
    if (!(field %in% names(id)) || !.datom_is_text_scalar(id[[field]])) {
      malformed(
        "x" = "{at}: {.field {fld}} is not a single non-empty string.",
        "i" = "{.fn datom_write_set} cannot produce this, so the payload was \\
               hand-edited or written by something else."
      )
    }
  })

  m$id <- id
  if ("tags" %in% names(m)) m$tags <- .datom_read_tag_map(m$tags)

  m
}


#' Resolve One Member Pointer Without a Connection in the Closure
#'
#' Builds the `$fetch` link every member of a read set carries: call it with a
#' connection to the member's project and it resolves the pointer -- a table
#' member to data via [datom_read()], a set member to references via
#' [datom_get_set()].
#'
#' **`fetch` rather than `read` or `get` because it is genuinely both.** This is
#' the one polymorphic door in the design, and the member level is where the
#' domain forces it: iterating members, the caller cannot know each kind in
#' advance. At the top level they named one artifact they chose, which is why
#' [datom_read()] and [datom_get_set()] stay separate verbs.
#'
#' **This function is namespace-level, and that is load-bearing.** A factory
#' defined inside [datom_get_set()] would put that call's frame -- which holds
#' `conn`, and therefore the PAT -- on the closure's parent chain, and
#' `saveRDS()` of the member would write the token into the file. Measured, same
#' code both ways: nested, 2094 bytes with the token present; namespace-level,
#' 1609 bytes without. Every argument is forced so that nothing is left as a
#' promise pointing back at the caller's frame. The guard is a test on the
#' **serialized bytes**, not on `environment(link)`, because an environment check
#' passes on the broken shape -- there the connection sits one frame further up.
#'
#' The link carries its own pointer as an attribute, so a consumer holding only a
#' projection can still cite what they used. Links built without it cannot be
#' repaired afterwards, which is why it ships with the factory rather than later.
#'
#' **It does not compare the member's project against the connection's, and it
#' must not.** That looks free -- both names are in hand -- and it would refuse
#' working reads. For a **reader** connection, which is the primary consumer of a
#' set, `project_name` is a label the caller passes to [datom_get_conn()]: the
#' namespace comes from the store's bucket and prefix and nothing validates the
#' label against the repo. So a mismatch is the ordinary case rather than the error
#' case, and a gate here would abort a fetch that resolves correctly. **Recording
#' the writer's own project name in metadata does not change this.** It makes the
#' member's side of the comparison trustworthy; the connection's side is still a
#' label nobody checked, so comparing them still refuses working reads. Pinned by a
#' test that fetches through a deliberately mismatched label. A *hint* on an
#' already-failed resolution is a different thing and is left to the task that
#' owns that message.
#'
#' @param name,kind,version The member's pinned identity -- the three facts
#'   resolution needs. `project` is deliberately not a parameter: see above.
#' @param record The member record the link describes -- pure data, attached as
#'   the `datom_member` attribute, and where `project` remains readable.
#' @return A function of one argument (`conn`), classed `datom_link`.
#' @keywords internal
.datom_member_link <- function(name, kind, version, record) {
  force(name)
  force(kind)
  force(version)
  force(record)

  link <- function(conn) {
    tryCatch(
      switch(
        kind,
        table = datom_read(conn, name, version = version),
        set = datom_get_set(conn, name, version = version),
        cli::cli_abort(
          c(
            "Member {.val {name}} is a {.val {kind}}, which this version of \\
             datom cannot resolve.",
            "i" = "A member points at one of {.val {(.datom_artifact_kinds)}}.",
            "i" = "The set may have been written by a newer datom -- upgrade \\
                   datom and retry."
          ),
          class = "datom_member_kind_unknown"
        )
      ),
      error = function(cnd) .datom_link_failure(cnd, name, kind, record, conn)
    )
  }

  attr(link, "datom_member") <- record
  class(link) <- "datom_link"

  link
}


#' Say Which Project a Member Belongs To, When Fetching It Has Already Failed
#'
#' The highest-value message in the set design, and it is a **hint on failure,
#' never a gate**. Access in datom is per project and not conjunctive, so
#' resolving a member of another project through this connection genuinely does
#' not work -- but without this bullet it presents as a missing object, which
#' names the wrong problem and sends the reader looking for corruption.
#'
#' **Why it cannot be a check that runs first.** A connection's `project_name` is
#' not a verified fact. On a reader connection -- the primary consumer of a set --
#' it is a label passed to [datom_get_conn()]: the namespace comes from the
#' store's root and prefix and nothing compares the label against the repo. So a
#' mismatch is the ordinary case, and refusing on it aborts fetches that resolve
#' correctly. Verified end to end by a test that fetches through a deliberately
#' wrong label.
#'
#' Recording the writer's own project name in metadata made the **member's** side
#' of that comparison trustworthy; the connection's side is unchanged. Comparing a
#' verified value against an unverified one still refuses working reads, which is
#' why this stayed a hint. What it did buy is the wording: the message names the
#' project the member's own writer recorded, rather than a project someone typed.
#'
#' **When the two names agree, the original condition is re-signalled untouched**
#' -- same object, same class -- because callers dispatch on those classes and a
#' failure that has nothing to do with projects must not be reworded.
#'
#' @param cnd The condition the resolution raised.
#' @param name,kind The member's name and kind.
#' @param record The member record, which holds its recorded project.
#' @param conn The connection the fetch was attempted through.
#' @return Never returns; always signals.
#' @keywords internal
.datom_link_failure <- function(cnd, name, kind, record, conn) {
  theirs <- record$id$project
  ours <- if (inherits(conn, "datom_conn")) conn$project_name

  same_or_unknown <- !.datom_is_text_scalar(theirs) ||
    !.datom_is_text_scalar(ours) ||
    identical(theirs, ours)

  if (same_or_unknown) stop(cnd)

  cli::cli_abort(
    c(
      "Could not fetch member {.val {name}} through this connection.",
      "i" = "That {kind} is recorded as belonging to project {.val {theirs}}, \\
             and this connection is for {.val {ours}}.",
      "i" = "Access is per project: open a connection to {.val {theirs}} and \\
             fetch the member through that one.",
      "i" = "If the two really are one project, the name on this connection \\
             just differs -- nothing checks it -- and the cause is below."
    ),
    parent = cnd,
    class = "datom_member_project_mismatch"
  )
}


#' Print a Member Link
#'
#' @param x A `datom_link` from a member of a set read with [datom_get_set()].
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
#'
#' @examples
#' # See datom_get_set() for a runnable set example; a link is one of its
#' # members' `$fetch` elements.
#' print(names(formals(datom_get_set)))
print.datom_link <- function(x, ...) {
  id <- attr(x, "datom_member")$id
  tags <- attr(x, "datom_member")$tags

  cli::cli_h3("datom link")
  cli::cli_ul()
  cli::cli_li("Points at: {id$kind} {.val {id$name}} in project {.val {id$project}}")
  cli::cli_li("Version:   {.val {id$version}}")
  if (length(tags) > 0L) {
    # Formatted first, then interpolated: a `{.something}` expression is read by
    # cli as an inline style name, so calling a function inside the braces is a
    # markup error rather than a call.
    tag_line <- .datom_format_tag_line(tags)
    cli::cli_li("Tags:      {tag_line}")
  }
  cli::cli_end()
  cli::cli_alert_info(
    "Resolve it with {.code link(conn)}, using a connection to project \\
     {.val {id$project}}."
  )

  invisible(x)
}


#' Format a Tag Map for One Line of Output
#'
#' `key=value` pairs, several labels joined by `|`, `-` when there are no tags.
#' Tags are open-keyed, so a fixed column layout is impossible -- do not try.
#'
#' @param tags A tag map, or `NULL`.
#' @return A single string.
#' @keywords internal
.datom_format_tag_line <- function(tags) {
  if (!is.list(tags) || length(tags) == 0L || is.null(names(tags))) return("-")

  pairs <- vapply(
    names(tags),
    function(k) {
      values <- tags[[k]]
      values <- if (is.list(values)) {
        vapply(values, function(v) paste(as.character(v), collapse = "|"),
               character(1L))
      } else {
        as.character(values)
      }
      paste0(k, "=", paste(values, collapse = "|"))
    },
    character(1L)
  )

  paste(pairs, collapse = ", ")
}


#' Download, Verify and Parse a Set's Stored Payload
#'
#' Download, hash, **then** parse. The order is the point: a set read must not
#' parse an unverified payload, which is the same gate position
#' [.datom_read_parquet()] uses for `parquet_sha`.
#'
#' **`.datom_storage_read_json()` cannot be used here, and it would work.** It
#' parses, so after calling it there is nothing left to hash but bytes
#' re-serialized locally -- a hash of bytes nobody stored, which is exactly the
#' defect the write path guards against, inverted. It returns a structure
#' identical to parsing the downloaded file, so nothing fails if you reach for
#' it; the integrity check simply stops meaning anything.
#'
#' **A missing `document_sha` is an error, not a skip.** `parquet_sha`'s
#' skip-on-absent branch exists purely as a grace for metadata written before
#' that field did. Sets have recorded `document_sha` since their first write, so
#' there is no legacy population to be lenient about, and reproducing the grace
#' would build a silent-degradation path on purpose.
#'
#' `data_sha` is deliberately **not** recomputed from the parsed payload. It is
#' the address the payload was fetched from, so it catches nothing
#' `document_sha` did not, and it would refuse a payload a newer datom wrote --
#' the sv1 encoder aborts on a top-level payload key it does not know. Same
#' reason the parsed payload is not re-validated. Reads limp.
#'
#' @param conn A `datom_conn` object.
#' @param name Set name.
#' @param data_sha The resolved content hash -- the payload's storage address.
#' @param document_sha The recorded SHA-256 of the stored payload bytes.
#' @return The parsed payload, with `members` kept as a list of records.
#' @keywords internal
.datom_read_set_payload <- function(conn, name, data_sha, document_sha) {
  .datom_validate_name(name)

  if (!.datom_is_text_scalar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }
  # data_sha is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(data_sha, arg = "data_sha")

  if (!.datom_is_text_scalar(document_sha)) {
    cli::cli_abort(
      c(
        "The recorded metadata for set {.val {name}} carries no \\
         {.field document_sha}.",
        "i" = "Every version of a set records the hash of its stored payload, \\
               so a version without one cannot be verified.",
        "i" = "Run {.fn datom_validate} on this project."
      ),
      class = "datom_set_document_sha_missing"
    )
  }

  key <- .datom_artifact_payload_key(name, data_sha, "set")
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)

  .datom_storage_download(conn, key, tmp)

  actual <- digest::digest(file = tmp, algo = "sha256")
  if (!identical(actual, document_sha)) {
    cli::cli_abort(
      c(
        "Stored payload for set {.val {name}} failed its integrity check.",
        "x" = "Key: {.val {key}}",
        "x" = "Expected {.field document_sha}: {.val {document_sha}}",
        "x" = "Actual SHA-256: {.val {actual}}",
        "i" = "The stored object may be corrupted or tampered with. Do not \\
               trust this set."
      ),
      class = "datom_set_integrity_failure"
    )
  }

  # simplifyVector = FALSE is what keeps `members` a list of records; the
  # simplifying parse collapses them into a data frame, at which point a member's
  # tags are gone.
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}


#' Turn a Parsed Member List into Resolvable Member Records
#'
#' @param members The payload's parsed member list.
#' @param name The set's name, for error messages.
#' @return An unnamed list of member records, each carrying `$fetch`.
#' @keywords internal
.datom_read_set_members <- function(members, name) {
  if (!is.list(members) || (length(members) > 0L && !is.null(names(members)))) {
    cli::cli_abort(
      c(
        "The stored payload for set {.val {name}} is malformed.",
        "x" = "{.field members} is not a list of member records.",
        "i" = "Run {.fn datom_validate} on the project that owns this set."
      ),
      class = "datom_set_payload_malformed"
    )
  }

  # lapply() rather than purrr::map(): a mapped function's abort is re-signalled
  # by purrr as its own condition, and callers dispatch on the class.
  lapply(seq_along(members), function(i) {
    record <- .datom_read_set_member(
      members[[i]], sprintf("members[[%d]]", i), name
    )

    id <- record$id
    c(record, list(
      fetch = .datom_member_link(
        name    = id$name,
        kind    = id$kind,
        version = id$version,
        record  = record
      )
    ))
  })
}


#' Read a datom set
#'
#' Reads a **set**: a versioned, citable collection of pointers at datom
#' artifacts. It returns *references and labels, and no data at all* -- which is
#' why the verb is `get` rather than `read`. Every member carries a `$fetch`
#' link, so resolving one to its content is one call and needs no reassembly.
#'
#' Reading a set requires access to the set's own project only. A member is a
#' pointer, and resolving it is a separate, deliberate step -- so a 50-member
#' product is readable by someone entitled to none of its members.
#'
#' @section What comes back:
#' A `datom_set`: `name`, `project`, `version`, `data_sha`, `tags` and
#' `members`. The four identifying facts are there so that a caller who passed
#' `version = NULL` can still say which version they got, because a set exists to
#' be cited. `version` is the version **recorded** in the history, so an
#' 8-character prefix goes in and the full version comes back.
#'
#' `members` is a flat, **unnamed** list in payload order. Not name-keyed, and
#' the reason is not style: the same artifact at two different versions is a
#' legal pair of members, two projects may both hold a `dm`, and R's `$`
#' partial-matches on lists -- so a name-keyed list would answer plausibly and
#' wrongly. The unique key is the full `id`.
#'
#' One of the four identifying facts has a limit worth knowing before you cite it:
#'
#' * **`version` can be `NULL`.** It is the version *recorded* in
#'   `version_history.json` for the state `metadata.json` describes, and a
#'   truncated or partly-synced history records no such entry. A manufactured
#'   version would be a wrong statement rather than a missing one, so the field is
#'   left empty and [datom_validate()] owns the inconsistency. A version-pinned
#'   read always reports one, since the entry is what it resolved through.
#'
#' `project` is the name the set's **own metadata** records -- the declaration of
#' the repo that wrote it, not the name on your connection. It falls back to the
#' connection's name only for a set written by a datom that predates the field,
#' which no released build ever was. Each **member** carries its own recorded
#' `id$project` for the same reason, resolved through a slightly longer route
#' because that value is durable and hashed rather than displayed.
#'
#' @section Resolving a member:
#' Each member is `id` (`project`, `name`, `kind`, `version`), its optional
#' `tags`, and `fetch`:
#'
#' ```r
#' x <- datom_get_set(conn, "study001-adam")
#' dm <- x$members[[1]]$fetch(conn)
#' ```
#'
#' `fetch` resolves whatever the pointer points at: a table member yields data, a
#' set member yields another `datom_set`. **A link pins the version it was read
#' at** -- it is a citation, not a subscription, so it never drifts to the latest.
#' Pass a connection scoped to the member's own project; same-project members
#' resolve through the connection you already have.
#'
#' Two reads of the same set are **not** `identical()`, because closures compare
#' by environment. Compare `m[c("id", "tags")]` instead, or use
#' `identical(a, b, ignore.environment = TRUE)`.
#'
#' @section Integrity, and what is not rechecked:
#' The stored payload is verified against the recorded `document_sha` **before it
#' is parsed**, and a version that records no `document_sha` is an error rather
#' than a skipped check. `data_sha` is not recomputed: it is the address the
#' payload was fetched from, so it would catch nothing the byte hash did not, and
#' it would refuse a payload written by a newer datom. Nothing in the payload is
#' re-canonicalized -- what you are shown is what was cited.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()], scoped to the
#'   set's project. A storage-only connection with no git clone is enough.
#' @param name The set's name.
#' @param version Optional version (`metadata_sha`, or a prefix of one). `NULL`
#'   reads the current version.
#'
#' @return A `datom_set`: a list of `name`, `project`, `version` (possibly
#'   `NULL`), `data_sha`, `tags` and `members`.
#' @seealso [datom_write_set()] to write one, [datom_member()] to declare a
#'   member, [datom_read()] for tables.
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
#'   # A product repo declares itself as one and names the single set it owns.
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store,
#'                   mode = "product", set = "example_product")
#'
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'   member <- datom_member(
#'     conn, "dm", datom_history(conn, "dm")$version[1],
#'     tags = list(type = "input")
#'   )
#'   datom_write_set(conn, list(member),
#'                   tags = list(description = "Example product"))
#'
#'   x <- datom_get_set(conn, "example_product")
#'   print(x)
#'
#'   # Resolve one member to its data. The link pins the version it was read at.
#'   print(head(x$members[[1]]$fetch(conn)))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_get_set <- function(conn, name, version = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  .datom_validate_name(name)

  # Nothing on this path touches `conn$path`: a storage-only reader with no clone
  # is the primary consumer of a set.
  metadata_list <- .datom_read_metadata(conn, name)

  # One name is one artifact. Without this a healthy table read as a set is
  # reported as a missing payload, which names the wrong problem.
  .datom_check_artifact_kind(
    metadata_list$current, name, "set", operation = "read"
  )

  resolved <- .datom_resolve_version(
    metadata_list, version = version, name = name, field = "document_sha"
  )

  payload <- .datom_read_set_payload(
    conn, name, resolved$data_sha, resolved$object_sha
  )

  structure(
    list(
      name = name,
      # The name the set's own metadata records, falling back to the connection's.
      # THE FALLBACK MUST NOT READ THE MANIFEST, which is what the two pointer
      # constructors do: the data path never touches that document -- which is why
      # a stale build can still read data after a manifest-shape change -- and a
      # manifest read here would put a derived, rebuildable, possibly too-new
      # document into a read path that today cannot fail for its sake. The
      # asymmetry is deliberate: a member's project is durable and hashed, this
      # one is an echo for display. Silent, because every set that has ever been
      # written records the field -- sets and the field ship together.
      project = .datom_set_project(metadata_list$current, conn),
      version = resolved$version,
      data_sha = resolved$data_sha,
      tags = .datom_read_tag_map(payload$tags),
      members = .datom_read_set_members(payload$members, name)
    ),
    class = "datom_set"
  )
}


#' Print a datom Set
#'
#' One line per member -- name, kind, and its tags as compact `key=value` pairs,
#' or `-` when it has none -- plus the route to a member's content. Long member
#' lists are truncated.
#'
#' Tags are open-keyed by design, so there is no fixed column layout to print
#' them in.
#'
#' @param x A `datom_set` from [datom_get_set()].
#' @param ... Ignored.
#' @param n Maximum number of members to list.
#' @return Invisible `x`.
#' @export
#'
#' @examples
#' # See datom_get_set() for a runnable example that prints a set.
#' print(names(formals(datom_get_set)))
print.datom_set <- function(x, ..., n = 20L) {
  cli::cli_h3("datom set: {.val {x$name}}")
  cli::cli_ul()
  cli::cli_li("Project: {.val {x$project}}")
  cli::cli_li("Version: {.val {x$version %||% NA_character_}}")
  cli::cli_li("Members: {.val {length(x$members)}}")
  if (length(x$tags) > 0L) {
    tag_line <- .datom_format_tag_line(x$tags)
    cli::cli_li("Tags:    {tag_line}")
  }
  cli::cli_end()

  shown <- utils::head(x$members, n)
  cli::cli_ul()
  purrr::walk(shown, function(m) {
    line <- paste0(
      m$id$name, " (", m$id$kind, ")  ", .datom_format_tag_line(m$tags)
    )
    cli::cli_li("{line}")
  })
  if (length(x$members) > length(shown)) {
    cli::cli_li("... and {length(x$members) - length(shown)} more")
  }
  cli::cli_end()

  if (length(x$members) > 0L) {
    # The named verb rather than the link, now that it exists: it is the route a
    # reader can type from what they see above, and it teaches the one that
    # matters when a name turns out to be ambiguous. Built as a string first --
    # a member name reaching cli as message text would be read as markup.
    first <- .datom_id_text(x$members[[1L]]$id, "name")
    hint <- sprintf(
      "datom_fetch_member(conn, x, %s)",
      if (is.na(first)) "member" else paste0("\"", first, "\"")
    )
    cli::cli_alert_info("Fetch a member with {.code {hint}}.")
  }

  invisible(x)
}
