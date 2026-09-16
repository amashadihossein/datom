# Finding and shaping a set's members: three verbs over the object
# `datom_get_set()` returns.
#
# NONE OF THESE READS A DOCUMENT THE SET READ DID NOT ALREADY READ.
# `datom_fetch_member()` performs exactly the reads `datom_read()` /
# `datom_get_set()` perform, because it resolves the pointer through the same
# link core `$fetch` is built from. The other two do no IO at all -- they are
# pure functions of the set object plus a caller-supplied axis, which is what
# keeps them from being a stored view configuration.
#
# FOUR THINGS HERE ARE LOAD-BEARING AND EASY TO UNDO BY TIDYING.
#
#   1. THERE IS ONE EXPANDER, IT READS A TAG MAP BY POSITION, AND BOTH SHAPING
#      VERBS GO THROUGH IT.
#      `datom_list_members()` turns one member into one row per tag value;
#      `datom_structure_members()` turns one member into one leaf per axis
#      value. That is the same operation, and writing it twice is what invites
#      the silent spelling -- taking the FIRST value of a multi-valued tag
#      (`m$tags[[by]][1]`), which puts a member under one branch when it belongs
#      under several. With one expander there is no second place to write it.
#
#      THE BY-POSITION HALF IS NOT A DETAIL, and it was added after the first
#      version of this file shipped with the defect. A tag map can carry the same
#      key twice -- nothing on the read side refuses one, and `jsonlite` parses
#      duplicate JSON keys into two same-named elements -- and `tags[[k]]`
#      returns the first match every time. So a by-name read is the identical
#      silent-first-match failure one level up, on the KEY axis instead of the
#      value axis, written inside the very function that exists to have one
#      place for it. Every read of a member's tag values goes through
#      `.datom_tag_pairs()` for that reason, `.datom_member_has_tags()`
#      included.
#
#   2. A MULTI-VALUED AXIS PUTS ONE MEMBER UNDER SEVERAL BRANCHES. That is the
#      whole reason labels exist here rather than folders: a folder holds an item
#      once, a tag can hold it twice. So the leaf count legitimately exceeds the
#      member count, and any change that makes those two numbers agree has
#      broken the feature rather than tidied it.
#
#   3. A MEMBER IS NEVER SILENTLY DROPPED AND A LEAF NAME IS NEVER SILENTLY
#      REUSED. A member missing the axis key goes under a named bucket; two
#      members asking for one leaf name abort. Both refusals exist because the
#      alternative -- a member the consumer cannot find and cannot see is absent
#      -- is the failure a projection is most likely to hide.
#
#   4. THE PROJECT CHECK IS A HINT ON FAILURE, NEVER A GATE, and it does not
#      live in this file. It sits in the link core in `R/set.R`, because after
#      `datom_structure_members()` a leaf is a link: a hint implemented in
#      `datom_fetch_member()` alone would miss the route people actually use.


# --- the set object ------------------------------------------------------------

#' The Member List of a Set, or an Abort Naming What Was Passed
#'
#' Every verb in this file starts here, so "this is not a set" is reported once
#' and identically rather than surfacing as a `$` on a data frame returning NULL.
#'
#' A set with no members is **not** an error. The writer refuses an empty member
#' list, but the reader does not -- a hand-built payload, or one from a newer
#' datom, reads back with none -- so every verb below has to have an answer for
#' zero members.
#'
#' @param x The value the caller passed.
#' @param arg Argument name for the message.
#' @return The member list, possibly empty.
#' @keywords internal
.datom_set_members <- function(x, arg = "x") {
  if (!inherits(x, "datom_set")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a {.cls datom_set} from {.fn datom_get_set}.",
        "i" = "Read the set first: \\
               {.code x <- datom_get_set(conn, \"my-product\")}."
      ),
      class = "datom_not_a_set"
    )
  }

  members <- x$members
  if (!is.list(members)) return(list())

  members
}


#' One `id` Field as Text, or `NA`
#'
#' A member read by [datom_get_set()] always has four single-string `id` fields
#' -- the read refuses a payload where one is not. This exists for the other
#' input: a `datom_set` assembled by hand, which is supported and untrusted. `NA`
#' rather than an abort so a listing still shows the member; the abort belongs to
#' whoever tries to *resolve* it.
#'
#' @param id A member's `id` map.
#' @param field One of `project`, `name`, `kind`, `version`.
#' @return A single string, or `NA_character_`.
#' @keywords internal
.datom_id_text <- function(id, field) {
  v <- if (is.list(id)) id[[field]]
  if (.datom_is_text_scalar(v)) v else NA_character_
}


#' A Tag Value as a Plain Character Vector
#'
#' **This is only possible because the tag grammar is text-only.**
#' [.datom_validate_tag_map()] refuses numbers, booleans, `null` and nesting, so
#' a tag value is a character vector and the `value` column of a member listing
#' is a plain character column with no list-column anywhere. If the grammar ever
#' widened, this function and the long format above it are what would have to
#' change.
#'
#' The two shapes handled are the two a value legitimately arrives in: a
#' character vector, and the list-of-length-1-characters a JSON array parses as.
#' A missing value is dropped rather than carried, because it states no label and
#' no datom write can produce one -- carried through, it would become a branch
#' named `NA`.
#'
#' @param v A tag value.
#' @return A character vector, possibly empty.
#' @keywords internal
.datom_tag_values <- function(v) {
  if (is.null(v) || length(v) == 0L) return(character())

  chr <- if (is.character(v)) v else as.character(unlist(v, use.names = FALSE))
  chr[!is.na(chr)]
}


# --- the one expander ----------------------------------------------------------

#' One Member's Tags as Key/Value Pairs
#'
#' A member with no tags yields one pair of `NA` / `NA`, which is what keeps an
#' untagged member visible in a listing rather than absent from it.
#'
#' A key whose value is empty also yields `NA` rather than no row. The writer
#' drops such a key, so this reaches only a hand-built payload -- and there the
#' key IS in the document, so reporting the key with no value states what is
#' there while dropping the row would not.
#'
#' **THE MAP IS READ BY POSITION, NEVER BY NAME, AND THAT IS THE WHOLE POINT OF
#' THE FUNCTION.** A tag map can carry the same key twice -- `jsonlite` parses
#' `{"type": "output", "type": "baseline"}` into two same-named elements, and a
#' caller can write `list(type = "a", type = "b")` -- and nothing on the read side
#' refuses it, because a reader does not validate a tag map. `tags[["type"]]`
#' returns the **first** match every time, so a by-name read reports one label
#' twice and loses the other: the member lists a value it does not have, vanishes
#' from a branch it belongs under, and cannot be found by the label the document
#' says it carries. Verified in all three verbs before this was positional.
#'
#' That is the file header's one-expander rule reappearing on the **key** axis.
#' Having one expander closed the silent-first-value spelling on the *value* axis;
#' reading that expander's own input by name reopened the identical failure one
#' level up.
#'
#' Duplicate keys are therefore treated exactly as one multi-valued key would be,
#' which is also what they mean. Identical pairs are **not** collapsed across
#' duplicate keys: the read reports what the document holds, and deduplicating
#' here would be a reader canonicalizing.
#'
#' @param tags A tag map, or `NULL`.
#' @return A data frame of `key` and `value`, at least one row.
#' @keywords internal
.datom_tag_pairs <- function(tags) {
  none <- data.frame(
    key = NA_character_, value = NA_character_, stringsAsFactors = FALSE
  )
  if (!is.list(tags) || length(tags) == 0L || is.null(names(tags))) return(none)

  keys <- names(tags)
  parts <- lapply(seq_along(tags), function(i) {
    values <- unique(.datom_tag_values(tags[[i]]))
    if (length(values) == 0L) values <- NA_character_
    data.frame(key = keys[[i]], value = values, stringsAsFactors = FALSE)
  })

  do.call(rbind, parts)
}


#' Expand a Member List to One Row Per Member Per Tag Value
#'
#' The shared expansion both shaping verbs are built on -- see point 1 of this
#' file's header for why there is exactly one of these.
#'
#' Carries a `.member` column holding the member's position, which is what lets
#' [datom_structure_members()] get back from a row to the record it came from.
#' [datom_list_members()] drops it, because a position is not a fact about a
#' member.
#'
#' @param members A non-empty member list.
#' @return A data frame of `.member`, `name`, `project`, `version`, `kind`,
#'   `key`, `value`.
#' @keywords internal
.datom_expand_member_tags <- function(members) {
  rows <- lapply(seq_along(members), function(i) {
    m <- members[[i]]
    pairs <- .datom_tag_pairs(m$tags)

    data.frame(
      .member = rep(i, nrow(pairs)),
      name    = .datom_id_text(m$id, "name"),
      project = .datom_id_text(m$id, "project"),
      version = .datom_id_text(m$id, "version"),
      kind    = .datom_id_text(m$id, "kind"),
      key     = pairs$key,
      value   = pairs$value,
      stringsAsFactors = FALSE
    )
  })

  frame <- do.call(rbind, rows)
  row.names(frame) <- NULL

  frame
}


#' The Zero-Row Shape of a Member Listing
#'
#' In one place, and carrying every column a populated result carries, so
#' `rbind()` of an empty listing and a populated one works. `datom_list()` had
#' exactly this defect twice: a zero-row frame built from zero rows loses its
#' columns, and the failure only shows up when somebody binds two results.
#'
#' @return A zero-row data frame.
#' @keywords internal
.datom_empty_member_frame <- function() {
  data.frame(
    name = character(),
    project = character(),
    version = character(),
    kind = character(),
    key = character(),
    value = character(),
    stringsAsFactors = FALSE
  )
}


# --- reaching one member -------------------------------------------------------

#' A Member's `id`, or an Abort Saying the Pointer Cannot Be Resolved
#'
#' Checks only what resolution needs, and deliberately does **not** call
#' [.datom_validate_members()]: that is the write-side contract, and it refuses
#' an `id` field a newer datom added -- which the read deliberately carries. Using
#' it here would make an unknown field readable but unfetchable, which is a
#' reads-limp violation arriving by a side door.
#'
#' @param record A member record.
#' @param what Noun for the message.
#' @return The `id` map.
#' @keywords internal
.datom_member_id <- function(record, what = "member") {
  id <- if (is.list(record)) record$id

  if (!is.list(id) || length(id) == 0L || is.null(names(id))) {
    cli::cli_abort(
      c(
        "This {what} has no {.field id} map, so there is nothing to resolve.",
        "i" = "A member is an {.field id} of project, name, kind and version, \\
               plus optional tags.",
        "i" = "Build one with {.fn datom_member}, or read the set with \\
               {.fn datom_get_set}."
      ),
      class = "datom_member_unusable"
    )
  }

  fields <- c("project", "name", "kind", "version")
  bad <- fields[
    !vapply(fields, function(f) .datom_is_text_scalar(id[[f]]), logical(1L))
  ]
  if (length(bad) > 0L) {
    cli::cli_abort(
      c(
        "This {what}'s {.field id} does not name {.val {bad}}.",
        "i" = "Resolving a pointer needs all four of project, name, kind and \\
               version, each a single non-empty string.",
        "i" = "Build one with {.fn datom_member}, or read the set with \\
               {.fn datom_get_set}."
      ),
      class = "datom_member_unusable"
    )
  }

  id
}


#' Build the Resolvable Link for One Member Record
#'
#' The single route from a record to a callable link, used by
#' [datom_fetch_member()] and by every leaf [datom_structure_members()] produces
#' -- and it is the same factory [datom_get_set()] uses for `$fetch`. So kind
#' dispatch, and the project hint that lives beside it, have one implementation
#' reached by every route.
#'
#' Any `fetch` already on the record is dropped first, so a record that came from
#' a read produces a link over pure data rather than a link carrying a link.
#'
#' @param record A member record, with or without a `fetch` element.
#' @param what Noun for messages about an unusable record.
#' @return A `datom_link`.
#' @keywords internal
.datom_member_as_link <- function(record, what = "member") {
  record <- .datom_strip_member_links(list(record))[[1L]]
  id <- .datom_member_id(record, what)

  .datom_member_link(
    name    = id$name,
    kind    = id$kind,
    version = id$version,
    record  = record
  )
}


#' One Line Describing a Member, for a Message That Has to Name Several
#'
#' Name, kind, the first 8 characters of its version, and its tags. The version
#' costs nothing -- a read member's `id$version` is the full recorded string --
#' and it is what the reader needs to narrow an ambiguous name.
#'
#' @param members A member list.
#' @return A character vector, one entry per member.
#' @keywords internal
.datom_member_lines <- function(members) {
  vapply(
    members,
    function(m) {
      paste0(
        .datom_id_text(m$id, "name"),
        " (", .datom_id_text(m$id, "kind"), ") ",
        substr(.datom_id_text(m$id, "version"), 1L, 8L),
        "  ", .datom_format_tag_line(m$tags)
      )
    },
    character(1L)
  )
}


#' Turn a Vector of Description Lines into cli Bullets
#'
#' Each line is interpolated as a **value** rather than embedded as message text,
#' because a tag value may legitimately contain a brace and cli reads
#' `{anything}` in message text as markup. Embedding the lines directly turns an
#' artifact called `dm{1}` into a cli parse error instead of a message.
#'
#' @param lines A character vector. Must be bound to the name `lines` in the
#'   frame that calls [cli::cli_abort()], which is what the interpolation refers
#'   to.
#' @return A character vector of bullets, each named `*`.
#' @keywords internal
.datom_line_bullets <- function(lines) {
  stats::setNames(
    vapply(
      seq_along(lines),
      function(k) sprintf("{lines[[%dL]]}", k),
      character(1L)
    ),
    rep("*", length(lines))
  )
}


#' Does a Member Carry All the Labels Asked For?
#'
#' Every key must be present and every value listed under it must be one the
#' member carries. So `tags = list(domain = "safety")` matches a member tagged
#' `domain = c("safety", "efficacy")` -- narrowing by one label of a multi-valued
#' tag is the ordinary case, since multi-valued tags are the point.
#'
#' **The member's labels are read through [.datom_tag_pairs()], not off the map**,
#' so there is genuinely one access path to a member's tag values and the
#' duplicate-key hazard documented there cannot be reintroduced here. A
#' `member$tags[[k]]` read is the same silent-first-match defect, and it fails in
#' the direction that looks like missing data: the member is reported not found
#' under a label the document says it carries.
#'
#' The filter side is read by position for the same reason, even though
#' [datom_fetch_member()] refuses a filter with duplicate keys before this runs.
#'
#' @param member A member record.
#' @param tags The filter map.
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_member_has_tags <- function(member, tags) {
  pairs <- .datom_tag_pairs(member$tags)
  keys <- names(tags)

  all(vapply(
    seq_along(tags),
    function(i) {
      want <- .datom_tag_values(tags[[i]])
      have <- pairs$value[!is.na(pairs$key) & pairs$key == keys[[i]]]
      have <- have[!is.na(have)]
      length(have) > 0L && all(want %in% have)
    },
    logical(1L)
  ))
}


#' Find the One Member a Name Refers To
#'
#' **An ambiguous name aborts and teaches.** Two members can legitimately share a
#' name -- the same artifact at two versions, for instance a current table beside
#' a locked baseline -- so a name is not a key, and answering with the first match
#' would be plausible and wrong. The abort lists the candidates with their
#' versions and tags and names the two ways to narrow: `tags`, which is the
#' navigation axis people reach for, and `version`, for exact pinning.
#'
#' @param members The set's member list.
#' @param name The name to look up.
#' @param tags Optional label filter.
#' @param version Optional version, or a prefix of one.
#' @return One member record.
#' @keywords internal
.datom_find_member <- function(members, name, tags = NULL, version = NULL) {
  named <- Filter(
    function(m) identical(.datom_id_text(m$id, "name"), name),
    members
  )

  if (length(named) == 0L) {
    available <- unique(vapply(
      members, function(m) .datom_id_text(m$id, "name"), character(1L)
    ))
    cli::cli_abort(
      c(
        "This set has no member named {.val {name}}.",
        "i" = if (length(available) == 0L) {
          "The set has no members at all."
        } else {
          "It has {.val {available}}."
        },
        "i" = "See every member with its labels using {.fn datom_list_members}."
      ),
      class = "datom_member_not_found"
    )
  }

  narrowed <- named
  if (!is.null(tags)) {
    narrowed <- Filter(function(m) .datom_member_has_tags(m, tags), narrowed)
  }
  if (!is.null(version)) {
    narrowed <- Filter(
      function(m) isTRUE(startsWith(.datom_id_text(m$id, "version"), version)),
      narrowed
    )
  }

  lines <- .datom_member_lines(named)

  if (length(narrowed) == 0L) {
    cli::cli_abort(
      c(
        "No member named {.val {name}} matches what you narrowed by.",
        "i" = "{length(named)} member{?s} named {.val {name}}:",
        .datom_line_bullets(lines),
        "i" = "A label filter needs the key and the exact value; a version may \\
               be given as a prefix."
      ),
      class = "datom_member_not_found"
    )
  }

  if (length(narrowed) > 1L) {
    lines <- .datom_member_lines(narrowed)
    cli::cli_abort(
      c(
        "{.val {name}} names {length(narrowed)} members of this set.",
        "i" = "That is legal: the same artifact at two versions is two \\
               members, such as a current table beside a locked baseline.",
        .datom_line_bullets(lines),
        "i" = "Narrow by label -- {.code tags = list(release = \"baseline\")} \\
               -- or pin one exactly with {.code version = }.",
        "i" = "Labels are the navigation axis; see them all with \\
               {.fn datom_list_members}."
      ),
      class = "datom_member_ambiguous"
    )
  }

  narrowed[[1L]]
}


#' Resolve the Third Argument of [datom_fetch_member()] to a Member Record
#'
#' One accessor for the three shapes a caller holds, so a console call and a loop
#' use the same verb: a **name**, a **member record**, or a **link**.
#'
#' A record with no `fetch` on it is accepted, and that matters: it is the payload
#' shape -- what a caller who built a member with [datom_member()] holds, and what
#' stripping a read set's links produces. The accessor keys on `id` and nothing
#' else, which is what keeps this verb and [datom_write_set()] agreeing about what
#' a member is.
#'
#' `tags` and `version` narrow a **name**. Supplied beside a record or a link they
#' are refused rather than ignored, because ignoring them would resolve a
#' different version than the one asked for and report success.
#'
#' @param members The set's member list.
#' @param member A name, a member record, or a `datom_link`.
#' @param tags Optional label filter.
#' @param version Optional version, or a prefix of one.
#' @return One member record.
#' @keywords internal
.datom_member_record <- function(members, member, tags = NULL,
                                 version = NULL) {
  from_object <- function(record, shape) {
    if (!is.null(tags) || !is.null(version)) {
      cli::cli_abort(
        c(
          "{.arg tags} and {.arg version} narrow a member {.emph name}, and \\
           you passed {shape}.",
          "i" = "{shape} already names one exact member, so a filter beside it \\
                 could only disagree with it.",
          "i" = "Drop the filter, or pass the member's name instead."
        ),
        class = "datom_member_filter_ignored"
      )
    }
    record
  }

  if (inherits(member, "datom_link")) {
    record <- attr(member, "datom_member")
    if (!is.list(record)) {
      cli::cli_abort(
        c(
          "This link carries no member record, so what it points at is \\
           unknown.",
          "i" = "Links come from {.fn datom_get_set} -- read the set again \\
                 rather than reconstructing one."
        ),
        class = "datom_member_unusable"
      )
    }
    return(from_object(record, "a link"))
  }

  if (is.list(member)) return(from_object(member, "a member record"))

  if (!.datom_is_text_scalar(member)) {
    cli::cli_abort(
      c(
        "{.arg member} must be a member's name, a member record, or a link.",
        "i" = "You passed {.cls {class(member)}}.",
        "i" = "A link is a member's {.field fetch} element; a record is what \\
               {.fn datom_member} returns."
      ),
      class = "datom_member_unusable"
    )
  }

  .datom_find_member(members, member, tags, version)
}


# --- the three verbs -----------------------------------------------------------

#' Fetch one member of a set
#'
#' Resolves one member of a set to what it points at: a table member to its data,
#' a set member to another set. It is the named route to the same resolution a
#' member's own `$fetch` link performs, and it goes through the same code -- so
#' the two cannot drift.
#'
#' This is kind dispatch at the **member** level, which is the only level it
#' belongs at. Iterating members, a caller cannot know each one's kind in advance;
#' at the top level they named one artifact they chose, which is why
#' [datom_read()] and [datom_get_set()] stay separate verbs.
#'
#' @section Naming a member:
#' `member` accepts the three shapes a caller actually holds, so a console call
#' and a loop use one verb:
#'
#' | What you pass | Where it comes from |
#' |---|---|
#' | a name | you read the set and know what you want |
#' | a member record | `datom_member()`, or `x$members[[i]]` |
#' | a link | `x$members[[i]]$fetch`, or a leaf of `datom_structure_members()` |
#'
#' **A name is not a key.** The same artifact at two versions is a legal pair of
#' members -- a current table beside a locked baseline, say -- so an ambiguous
#' name aborts and lists the candidates rather than answering with the first.
#' Narrow with `tags`, which is the navigation axis, or pin one exactly with
#' `version`. Both narrow a name only; supplied beside a record or a link they are
#' refused rather than quietly ignored.
#'
#' @section Which connection to pass:
#' The one for the **member's** project. Access in datom is per project and not
#' conjunctive: reading a set needs the set's project only, and resolving a member
#' is a separate, deliberate step. Same-project members resolve through the
#' connection you already have.
#'
#' A member's project is **not** checked against the connection's before the
#' fetch, and that is deliberate: a connection's project name is a label the
#' caller supplied and nothing compares it against the repo, so a mismatch is
#' ordinary rather than wrong. When a fetch fails and the two names differ, the
#' error says which project the member's own writer recorded, so the ordinary
#' cause is named instead of presenting as a missing object.
#'
#' @param conn A `datom_conn` from [datom_get_conn()], scoped to the **member's**
#'   project.
#' @param x A `datom_set` from [datom_get_set()].
#' @param member The member to fetch: its name, a member record, or a link.
#' @param tags Optional named list of labels narrowing an ambiguous name, e.g.
#'   `list(release = "baseline")`. A member matches when it carries every label
#'   listed.
#' @param version Optional version, or a prefix of one, narrowing an ambiguous
#'   name.
#'
#' @return Whatever the member points at: a data frame for a `table` member, a
#'   `datom_set` for a `set` member.
#' @seealso [datom_list_members()] to see every member and its labels,
#'   [datom_structure_members()] for a navigable view.
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
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'   datom_write(conn, data = datom_example_data("lb"), name = "lb")
#'
#'   members <- list(
#'     datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
#'                  tags = list(type = "input")),
#'     datom_member(conn, "lb", datom_history(conn, "lb")$version[1],
#'                  tags = list(type = "output", domain = c("safety", "labs")))
#'   )
#'   datom_write_set(conn, members)
#'
#'   x <- datom_get_set(conn, "example_product")
#'
#'   # By name, and the same fetch by the link the read already put on it.
#'   print(head(datom_fetch_member(conn, x, "dm")))
#'   print(head(datom_fetch_member(conn, x, x$members[[1]]$fetch)))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_fetch_member <- function(conn, x, member, tags = NULL, version = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  members <- .datom_set_members(x)

  if (!is.null(tags)) {
    .datom_validate_tag_map(
      tags, "tags",
      remedy = "Narrow by labels a member carries, e.g. \\
                {.code list(type = \"output\")}."
    )
  }
  if (!is.null(version) && !.datom_is_text_scalar(version)) {
    cli::cli_abort(
      c(
        "{.arg version} must be a single non-empty string.",
        "i" = "A version, or a prefix of one, as {.fn datom_history} reports \\
               them."
      )
    )
  }

  record <- .datom_member_record(members, member, tags, version)

  # Through the same factory `$fetch` is built from, so kind dispatch and the
  # project hint have one implementation rather than two that agree today.
  .datom_member_as_link(record)(conn)
}


#' List a set's members and their labels
#'
#' A data frame with one row per member **per label value** -- long format, not
#' wide. Tags are open-keyed and multi-valued, so a wide frame would need a
#' list-column and a column set that changes from one set to the next; long is a
#' plain frame with fixed columns whatever the set holds.
#'
#' Filtering is therefore ordinary R -- `subset()`, `dplyr::filter()` -- and datom
#' grows no query vocabulary of its own.
#'
#' @section The columns:
#' `name`, `project`, `version` and `kind` identify the member; `key` and `value`
#' are one label. **An untagged member still gets a row**, with `NA` for both, so
#' `unique(m$name)` is the complete member list rather than the tagged part of it.
#'
#' `value` is a plain character column, never a list-column, because the tag
#' grammar is text only.
#'
#' @param x A `datom_set` from [datom_get_set()].
#'
#' @return A data frame of `name`, `project`, `version`, `kind`, `key`, `value`.
#'   Zero rows, with those columns, for a set with no members.
#' @seealso [datom_structure_members()] for a navigable view of the same labels,
#'   [datom_fetch_member()] to resolve one member.
#' @export
#'
#' @examples
#' # These two facts about a set -- its members and their labels -- are all this
#' # verb reads, so a set built by hand shows the shape. In practice `x` comes
#' # from datom_get_set().
#' x <- structure(
#'   list(
#'     name = "study001-adam", project = "study001", version = NULL,
#'     data_sha = NULL, tags = list(description = "ADaM datasets"),
#'     members = list(
#'       list(
#'         id = list(project = "study001", name = "adsl", kind = "table",
#'                   version = strrep("a", 64)),
#'         tags = list(type = "output", domain = c("safety", "efficacy"))
#'       ),
#'       list(
#'         id = list(project = "study001", name = "dm", kind = "table",
#'                   version = strrep("b", 64))
#'       )
#'     )
#'   ),
#'   class = "datom_set"
#' )
#'
#' # adsl appears three times, once per label; the untagged dm appears once.
#' datom_list_members(x)
#'
#' # Filtering is plain R.
#' subset(datom_list_members(x), key == "domain" & value == "safety")
datom_list_members <- function(x) {
  members <- .datom_set_members(x)
  if (length(members) == 0L) return(.datom_empty_member_frame())

  frame <- .datom_expand_member_tags(members)
  frame <- frame[
    , c("name", "project", "version", "kind", "key", "value"), drop = FALSE
  ]
  row.names(frame) <- NULL

  frame
}


#' Assign One Leaf Into a Nested List, Creating Branches on the Way
#'
#' Recursive rather than iterative because the depth is the length of the axis
#' vector, and `tree[[c("a", "b")]] <- v` fails when the intermediate list does
#' not exist yet.
#'
#' @param tree The list to assign into.
#' @param path A character vector of branch names, innermost last.
#' @param value The leaf value.
#' @return `tree`, with the leaf assigned.
#' @keywords internal
.datom_assign_leaf <- function(tree, path, value) {
  key <- path[[1L]]

  if (length(path) == 1L) {
    tree[[key]] <- value
    return(tree)
  }

  child <- tree[[key]]
  if (!is.list(child)) child <- list()
  tree[[key]] <- .datom_assign_leaf(child, path[-1L], value)

  tree
}


#' Group a set's members into a navigable view
#'
#' Groups members by the values of the label key(s) named in `by` and returns a
#' nested list whose leaves are the members' **links**, so
#' `dp$output$adsl(conn)` works and tab-completes.
#'
#' A pure function of `x` and the axis you ask for: nothing is stored, and datom
#' takes no position on which hierarchy is the right one. Ask for
#' `by = c("domain", "type")` and you get a different tree from the same set,
#' which is that design working rather than being worked around.
#'
#' @section One member, several branches:
#' A member tagged `domain = c("safety", "efficacy")` appears under **both**
#' `safety` and `efficacy`, so the total number of leaves can exceed the number of
#' members. That is the point of labels over folders rather than a quirk of this
#' verb: a folder holds an item in exactly one place, and a label does not.
#'
#' @section What is refused, and why nothing is dropped:
#' Two requests abort, because the alternative in both cases is a member the
#' consumer cannot find and cannot see is absent:
#'
#' * **Two members asking for one leaf name.** Two members may legitimately share
#'   a name at different versions, and if both carry the same label they ask for
#'   the same leaf. The abort names both and points at adding an axis --
#'   `by = c("type", "release")`. The set itself is entirely legal; only this
#'   projection of it is refused.
#' * **A `missing` bucket name that is also a real label value.** The bucket is a
#'   leaf name, so a set where some member genuinely carries
#'   `type = "untagged"` would merge the real branch into the bucket. Refused
#'   whatever the members happen to look like, so that whether the projection
#'   works does not depend on whether a member is currently missing the key.
#'
#' A member that simply lacks the axis key is **not** refused and **not** dropped:
#' it goes under `missing`, named, because a named bucket is visible and an
#' omission is not.
#'
#' @param x A `datom_set` from [datom_get_set()].
#' @param by Character vector of one or more label keys to group by, outermost
#'   first.
#' @param missing Branch name for members carrying no value for an axis key.
#'
#' @return A nested list `length(by) + 1` levels deep: one level per axis, then
#'   the member's own name holding its `datom_link`. An empty list for a set with
#'   no members.
#' @seealso [datom_list_members()] for the flat view,
#'   [datom_fetch_member()] to resolve one member by name.
#' @export
#'
#' @examples
#' # Built by hand to show the shape; in practice `x` comes from
#' # datom_get_set(). adsl carries two domains, so it appears under both.
#' x <- structure(
#'   list(
#'     name = "study001-adam", project = "study001", version = NULL,
#'     data_sha = NULL, tags = NULL,
#'     members = list(
#'       list(
#'         id = list(project = "study001", name = "adsl", kind = "table",
#'                   version = strrep("a", 64)),
#'         tags = list(domain = c("safety", "efficacy"))
#'       ),
#'       list(
#'         id = list(project = "study001", name = "dm", kind = "table",
#'                   version = strrep("b", 64))
#'       )
#'     )
#'   ),
#'   class = "datom_set"
#' )
#'
#' dp <- datom_structure_members(x, by = "domain")
#' print(names(dp))
#' print(names(dp$safety))
#'
#' # A leaf is a link: call it with a connection to resolve it.
#' print(dp$safety$adsl)
datom_structure_members <- function(x, by, missing = "untagged") {
  members <- .datom_set_members(x)

  if (!is.character(by) || length(by) == 0L || anyNA(by) || !all(nzchar(by))) {
    cli::cli_abort(
      c(
        "{.arg by} must name one or more label keys.",
        "i" = "For example {.code by = \"type\"}, or \\
               {.code by = c(\"type\", \"domain\")} for a two-level view.",
        "i" = "See which keys this set uses with {.fn datom_list_members}."
      ),
      class = "datom_structure_by_invalid"
    )
  }
  if (anyDuplicated(by) > 0L) {
    cli::cli_abort(
      c(
        "{.arg by} names {.val {unique(by[duplicated(by)])}} more than once.",
        "i" = "Each level of the view groups by a different label key."
      ),
      class = "datom_structure_by_invalid"
    )
  }
  if (!.datom_is_text_scalar(missing)) {
    cli::cli_abort(
      c(
        "{.arg missing} must be a single non-empty string.",
        "i" = "It becomes the branch name for members carrying no value for \\
               an axis key."
      ),
      class = "datom_structure_by_invalid"
    )
  }

  if (length(members) == 0L) return(list())

  # Built first so a member whose pointer is unusable is reported as that, rather
  # than as a branch called `NA` appearing in the view.
  links <- lapply(members, .datom_member_as_link)

  long <- .datom_expand_member_tags(members)
  on_axis <- !is.na(long$key) & long$key %in% by

  # Refused whatever the members look like: a bucket name that is also a real
  # value merges two different facts into one branch, and making the refusal
  # conditional on a member currently missing the key would mean the projection
  # starts failing the day one is added -- silently at authoring time, which is
  # the failure mode this whole verb is built to avoid.
  clash <- on_axis & !is.na(long$value) & long$value == missing
  if (any(clash)) {
    axes <- unique(long$key[clash])
    cli::cli_abort(
      c(
        "{.arg missing} is {.val {missing}}, which is already a value of \\
         {.val {axes}}.",
        "i" = "The bucket for members with no value would share a branch with \\
               members that really carry that label.",
        "i" = "Pass a different {.arg missing}, e.g. \\
               {.code missing = \"(none)\"}."
      ),
      class = "datom_structure_missing_collision"
    )
  }

  # One member's values on each axis -- deduplicated, and the named bucket when
  # it has none. This is where a member with two domains becomes two leaves.
  axis_values <- lapply(seq_along(members), function(i) {
    lapply(by, function(k) {
      values <- unique(long$value[on_axis & long$.member == i & long$key == k])
      values <- values[!is.na(values)]
      if (length(values) == 0L) missing else values
    })
  })

  # A path is the axis values, outermost first, and then the member's own name --
  # so `by = "type"` gives `dp$output$adsl`. The name is the leaf rather than a
  # level of the grouping, which is what makes two same-named members the case
  # that has to be refused.
  paths <- unlist(
    lapply(seq_along(members), function(i) {
      grid <- expand.grid(
        axis_values[[i]],
        stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
      )
      leaf <- .datom_id_text(members[[i]]$id, "name")
      lapply(
        seq_len(nrow(grid)),
        function(r) c(as.character(unlist(grid[r, ], use.names = FALSE)), leaf)
      )
    }),
    recursive = FALSE
  )
  owners <- rep(
    seq_along(members),
    times = vapply(axis_values, function(v) prod(lengths(v)), numeric(1L))
  )

  # "\r" as the separator: a label value may hold a slash or a hyphen, so a
  # printable separator could make two different paths compare equal.
  flat <- vapply(paths, paste, character(1L), collapse = "\r")
  clashed <- duplicated(flat)
  if (any(clashed)) {
    at <- which(clashed)[[1L]]
    first <- owners[[match(flat[[at]], flat)]]
    branch <- paste(paths[[at]], collapse = " / ")
    lines <- .datom_member_lines(members[c(first, owners[[at]])])
    cli::cli_abort(
      c(
        "Two members would both be {.val {branch}} in this view.",
        .datom_line_bullets(lines),
        "i" = "A leaf holds one member, and these two are different members \\
               that {.arg by} cannot tell apart.",
        "i" = "Add an axis that separates them, e.g. \\
               {.code by = c({.val {by}}, \"release\")}.",
        "i" = "The set itself is fine -- only this grouping of it is \\
               ambiguous."
      ),
      class = "datom_structure_leaf_collision"
    )
  }

  Reduce(
    function(tree, j) .datom_assign_leaf(tree, paths[[j]], links[[owners[[j]]]]),
    seq_along(paths),
    init = list()
  )
}
