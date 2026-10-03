# Assembling a set in steps: an empty set, and a verb that adds one member to it.
#
# WHY THIS EXISTS WHEN THE LIST FORM ALREADY WORKS. Not brevity -- the pipe is
# about the same length as the nested `list()`. Two reasons, both about where an
# error surfaces. A malformed member aborts on the line that declared it, naming
# that member, rather than after the whole list is built and indexed. And the
# direct form repeats `conn` on every member inside a nested `list()`, which is
# bracket-heavy enough that a human miscounts. The build-script path keeps the
# direct form; this is the human path.
#
# SIX THINGS HERE ARE LOAD-BEARING AND EASY TO UNDO BY TIDYING.
#
#   1. A SET IN MEMORY HOLDS NO CONNECTION, HOWEVER IT WAS MADE. An assembled
#      set is the same `datom_set` a read returns, only with no version yet. A
#      connection is a runtime capability that may carry a credential, so it
#      belongs on the call that uses it -- `datom_add_member(conn = )` for a
#      name, `datom_write_set(conn, x)` for the write -- and never in a value
#      that can be printed, saved or passed on. An earlier draft class held the
#      product repo's connection, which is why the write once took a draft in
#      its first slot and a read set in its second, and why a hint telling the
#      caller to write `x` with `datom_write_set(conn, x)` failed for a draft.
#      Putting a connection back on the object brings both problems back.
#
#   2. A RECORD IN ARGUMENT 2 IS A CAPABILITY, NOT SUGAR. A link or a
#      read-back record is what a consumer holds when they cite what they used,
#      often with no connection to the member's project at all. Those carry
#      their own resolved pointer, so they need no connection and can cross
#      projects freely. Deleting the record shape as "a convenience" would
#      remove a capability, even though a name plus `conn =` reaches another
#      project too.
#
#   3. `version` STAYS REQUIRED WHEN A MEMBER IS ADDED BY NAME. Inferring
#      "current" would leave a build script producing a DIFFERENT set on each run
#      from byte-identical source. Pinning makes the artifact immutable; requiring
#      the pin makes the code reproducible, and those are two separate
#      guarantees.
#
#   4. THE MEMBER COUNT A SET REPORTS IS THE COUNT THE WRITE WILL PRODUCE, and
#      skipping an exact repeat rather than appending it is what keeps those two
#      numbers equal. The write drops an exact repeat silently, so a set that
#      appended it would print one count and write another -- and the printed
#      count is the one number a caller inspects mid-pipe. The same version with
#      DIFFERENT labels is an error at the write, so it is an error here too, on
#      the line that introduced it. Both comparisons go through the write's own
#      mechanisms -- the payload check's id key and the dedup's member digest --
#      because `identical()` on two records reads two spellings of one label set
#      as a disagreement and would refuse what the write accepts.
#
#   5. EVERY ADD IS AN EDIT, LOGGED AND REPORTED LIKE THE OTHER EDIT VERBS. It
#      empties the set's version (a no-op on a set never written), appends an
#      `add` row to the edit log `datom_update_members()` and
#      `datom_remove_members()` share, and says nothing has been written. So a
#      freshly assembled set's first write commits `Update {name}: add N
#      members` with one line per member, which says what the first version
#      holds. Skipping the log for a set never written would bring back the
#      special case one kind of set removed.
#
#   6. EVERY MEMBER CARRIES A `$fetch` LINK, however the set was made. A member
#      added here gets one through the shared factory, so an assembled set looks
#      like a read one; the clash check strips links before digesting (the
#      member digest refuses any field beyond `id` and `tags`), and the write
#      strips them before hashing.


#' Is This Member Already in the Set, and Is It the Same Member?
#'
#' Answers the question the write answers twice, one step earlier, so a repeat
#' lands on the line that introduced it.
#'
#' **Both of the write's rules are here, and they are deliberately different
#' rules.** `.datom_order_set_members()` drops an **exact** repeat -- same `id`
#' *and* same tags -- silently, because the digest it dedupes on covers tags. The
#' same `id` with **different** tags survives that and is then refused by
#' `.datom_check_set_payload()`, because merging the labels and picking one entry
#' both guess. So an exact repeat is a duplicate to skip, and a same-version
#' disagreement is an error.
#'
#' **The comparison uses the write's own two mechanisms rather than restating
#' them**: the `project` / `name` / `version` key the payload check keys on, and
#' the `datom-sv1` member digest the dedup keys on. `identical()` on the two
#' records is the spelling to avoid, and it fails in the direction that refuses
#' working input: the encoder sorts a tag map's keys and encodes each value as a
#' sorted, deduplicated **set**, so `domain = c("a", "b")` and `c("b", "a")` are
#' one member to the write and to the digest, while `identical()` reads them as a
#' disagreement and aborts.
#'
#' That is also why nothing needs tidying first. Every spelling the write's tidy
#' step collapses is a spelling the digest is already blind to, so a record can be
#' compared -- and stored in the set -- exactly as the caller supplied it.
#'
#' @param members The set's members so far, with their links stripped.
#' @param record The record about to be added.
#' @return A list with `status` -- `"new"`, `"duplicate"` or `"conflict"` -- and,
#'   for the last two, `at`: the position of the member already in the set.
#' @keywords internal
.datom_draft_member_clash <- function(members, record) {
  if (!is.list(members) || length(members) == 0L) {
    return(list(status = "new"))
  }

  # "\r" as the separator, for the reason the payload check uses it: an artifact
  # name may hold a printable separator, so a printable one could make two
  # different ids collide into one key.
  id_key <- function(m) {
    paste(m$id$project, m$id$name, m$id$version, sep = "\r")
  }

  at <- match(id_key(record), vapply(members, id_key, character(1L)))
  if (is.na(at)) return(list(status = "new"))

  digest <- function(m) .datom_sv1_hex(.datom_sv1_member(m, "member"))

  status <- if (identical(digest(members[[at]]), digest(record))) {
    "duplicate"
  } else {
    "conflict"
  }

  list(status = status, at = at)
}


#' Start Assembling a Set
#'
#' Returns an empty set, to be filled in with [datom_add_member()] and written
#' with [datom_write_set()]:
#'
#' ```r
#' datom_assemble_set(conn, tags = list(description = "ADaM datasets")) |>
#'   datom_add_member("adsl", v_adsl, tags = list(type = "output"),
#'                    conn = conn) |>
#'   datom_add_member("dm", v_dm, tags = list(type = "input"),
#'                    conn = conn_src) |>
#'   datom_write_set(conn = conn)
#' ```
#'
#' The equivalent single call -- a `list()` of [datom_member()] results passed to
#' [datom_write_set()] -- remains fully supported and is the better fit for a
#' build script. What this path adds is **where an error surfaces**: a malformed
#' member aborts on the line that declared it and names that member, instead of
#' aborting once the whole list has been assembled and indexed.
#'
#' @section One kind of set:
#' What comes back is a `datom_set`, the same kind of object [datom_get_set()]
#' returns, only with no version yet. So every verb that takes a set takes this
#' one: [datom_list_members()], [datom_update_members()], [datom_write_set()]
#' and the rest.
#'
#' **It holds no connection.** A connection may carry a credential, so it is
#' passed on each call that needs one rather than kept in a value that can be
#' printed or saved: `conn =` on [datom_add_member()] for a member given by name,
#' and `conn` on [datom_write_set()]. The connection given here is used only to
#' record which project the set belongs to; the write checks that it is the
#' project it is written into.
#'
#' @section Set-level tags:
#' Supplied here rather than by a third verb, because they are facts about the
#' collection rather than about any member. Editing them later is plain R --
#' `x$tags$description <- "..."` -- and the same grammar applies as to a
#' member's tags: text only, one label or several.
#'
#' @param conn A `datom_conn` from [datom_get_conn()] for the product repo. Its
#'   project name is recorded as the set's project; nothing else is kept.
#' @param name The set's name. `NULL` (the default) leaves it to the write, which
#'   takes the name the repo declares under `set:` in `.datom/project.yaml` --
#'   the usual case, since one repo holds one set.
#' @param tags Optional named list of set-level text labels, e.g. a description.
#'
#' @return A `datom_set` with no version and no members.
#' @seealso [datom_add_member()] to add one member, [datom_write_set()] to write
#'   the result, [datom_member()] for the single-call form.
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
#'   datom_write(conn, data = datom_example_data("lb"), name = "lb")
#'
#'   v_dm <- datom_history(conn, "dm")$version[1]
#'   v_lb <- datom_history(conn, "lb")$version[1]
#'
#'   x <- datom_assemble_set(
#'     conn,
#'     tags = list(description = "Example product for STUDY-001")
#'   ) |>
#'     datom_add_member("dm", v_dm, tags = list(type = "input"), conn = conn) |>
#'     datom_add_member("lb", v_lb, tags = list(type = "output"), conn = conn)
#'
#'   print(datom_list_members(x))
#'   x |> datom_write_set(conn = conn)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_assemble_set <- function(conn, name = NULL, tags = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      c(
        "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}.",
        "i" = "The set records the project it belongs to, taken from this \\
               connection, and the write checks it against the repo it is \\
               written into."
      ),
      class = "datom_not_a_conn"
    )
  }

  if (!is.null(name)) .datom_validate_name(name)

  # Tidy, then validate what remains -- the same order the write uses, and for the
  # same reason: a key pointing at nothing is a tidy case, so validating first
  # would make that rule unreachable. Validated HERE as well as at the write, so a
  # malformed description aborts on the line that wrote it.
  tags <- .datom_drop_empty_tags(tags)
  .datom_validate_tag_map(
    tags, "tags",
    remedy = "Set-level tags describe the collection itself, e.g. \\
              {.code list(description = \"ADaM datasets for STUDY-001\")}."
  )

  # `x["tags"] <- list(NULL)` keeps the field when there are none; `x$tags <-
  # NULL` would remove it and change `names(x)` from what a read returns.
  x <- .datom_empty_set(name, conn$project_name)
  x["tags"] <- list(tags)

  x
}


#' A Set With No Version Yet
#'
#' What a set is before its first write: a name (or `NULL`, left for the write
#' to resolve), the project it belongs to, and no members. Spelled
#' `list(version = NULL, ...)` so the empty fields keep their names, which is
#' the shape [datom_get_set()] returns for a read set. [datom_assemble_set()]
#' returns one, and the sync preview starts from one when the repo's set has
#' never been written.
#'
#' @param name The set's name, or `NULL`.
#' @param project The repo's project name.
#' @return A `datom_set`.
#' @keywords internal
.datom_empty_set <- function(name, project) {
  structure(
    list(
      name = name,
      project = project,
      version = NULL,
      data_sha = NULL,
      tags = NULL,
      members = list()
    ),
    class = "datom_set"
  )
}


#' Append One Member Record to a Set, as an Edit
#'
#' The three steps every addition takes -- a `$fetch` link, the set's version
#' forgotten, an `add` row in the edit log -- in one place, so
#' [datom_add_member()] and the set route of [datom_sync()] cannot drift apart
#' in what they record. See points 5 and 6 of this file's header. **It prints
#' nothing**: each caller says "nothing has been written" once, which for sync
#' means once per call rather than once per added member.
#'
#' The link goes through the shared factory, never inline, so no frame holding
#' a connection lands on its parent chain.
#'
#' @param x A `datom_set`.
#' @param record A member record, already validated and checked for clashes.
#' @return `x`, one member longer.
#' @keywords internal
.datom_set_add_record <- function(x, record) {
  id <- .datom_member_id(record)
  record$fetch <- .datom_member_as_link(record)

  x$members <- c(x$members, list(record))
  x <- .datom_forget_set_identity(x)

  .datom_append_edits(x, data.frame(
    action = "add",
    project = id$project,
    name = id$name,
    kind = id$kind,
    from = NA_character_,
    to = id$version,
    stringsAsFactors = FALSE
  ))
}


#' Add One Member to a Set
#'
#' Declares one member and appends it to a set -- an empty one from
#' [datom_assemble_set()] or one read back with [datom_get_set()] -- validating
#' it immediately: the artifact must exist at the version given, and its labels
#' must be well formed. The member record is built through the same path
#' [datom_member()] uses, so a set assembled this way is byte-identical to the
#' same set passed as a list.
#'
#' @section Naming a member:
#' `member` accepts the three shapes a caller holds, and the second and third are
#' not merely convenient:
#'
#' | What you pass | What it means |
#' |---|---|
#' | a name | look this artifact up through `conn` |
#' | a member record | use it as given -- from [datom_member()], or from a set read back |
#' | a link | use the member it points at -- `x$members[[i]]$fetch`, or a leaf of [datom_structure_members()] |
#'
#' **A name is looked up in one project's storage**: the project `conn` is
#' for. A set holds no connection, so a name always needs `conn`, whichever
#' project it is in. A record or a link carries its own resolved pointer and
#' needs no connection at all:
#'
#' ```r
#' datom_assemble_set(conn_a) |>
#'   datom_add_member("dm", v1, conn = conn_a) |>      # this project, by name
#'   datom_add_member("ae", v2, conn = conn_b) |>      # another project, by name
#'   datom_add_member(datom_member(conn_b, "vs", v3))  # another project, as a record
#' ```
#'
#' **A link is how a consumer cites what they used.** Someone holding only a
#' projection of a set -- a leaf of [datom_structure_members()] -- can add exactly
#' the version they read to a new set, without reconstructing the pointer.
#'
#' `version` and `tags` describe a member given by **name**. Beside a record or a
#' link they are refused rather than ignored, because a record already carries its
#' own version and labels and a second set of them could only disagree.
#'
#' @section Why the version is required:
#' A member pins one exact version, and there is no way to ask for "whatever is
#' current". Inferring current would make a build script produce a **different
#' set** on each run from byte-identical source. Pinning is what makes the
#' artifact immutable; requiring the pin is what makes the code reproducible.
#' List versions with [datom_history()].
#'
#' @section Every add is an edit:
#' Adding a member behaves like [datom_update_members()] and
#' [datom_remove_members()], whether the set was just assembled or read back:
#'
#' * **Nothing is written.** The set is stored only when you pass the result to
#'   [datom_write_set()], and the call says so.
#' * **`version` and `data_sha` are emptied**, because they described the
#'   payload the set was read as. A set never written has neither.
#' * **The addition is recorded**, so the write's default commit message says
#'   `add 1 member` beside any repoints or removals made on the same object. A
#'   freshly assembled set's first write therefore names every member it adds.
#' * **The new member gets a `$fetch` link**, like every member of a set read
#'   back.
#'
#' @param x A `datom_set`, from [datom_assemble_set()] or [datom_get_set()].
#' @param member The member to add: an artifact name, a member record, or a link.
#' @param version The version to pin, when `member` is a name. Required there;
#'   refused beside a record or a link.
#' @param conn A `datom_conn` from [datom_get_conn()] for the project a
#'   **name** is looked up in. Required for a name; not used for a record or a
#'   link.
#' @section Adding the same member twice:
#' The two cases differ, and they differ the same way they differ at the write:
#'
#' * **The same version with the same labels** is skipped, with a note. The write
#'   drops an exact repeat anyway, so refusing here would make this verb stricter
#'   than the equivalent list -- `Reduce(datom_add_member, records, init = x)`
#'   over a generated list that happens to repeat would fail where it works today.
#' * **The same version with different labels** aborts. One version of one
#'   artifact is one member holding one set of labels, and merging or choosing
#'   between two sets would guess. The write refuses this too; here it names the
#'   line that introduced it.
#'
#' So the member count a set reports is the count the write will produce. Two
#' different **versions** of one artifact are two members, and both are kept.
#'
#' @param tags Optional named list of text labels for this member, when `member`
#'   is a name. Refused beside a record or a link, which carry their own.
#'
#' @return The set, one member longer, with its `version` and `data_sha`
#'   emptied and the addition appended to its `datom_edits` attribute -- or
#'   unchanged, when the member was already in it with the same labels.
#' @seealso [datom_assemble_set()] to start a set, [datom_get_set()] to read one
#'   back, [datom_member()] to build a record on another connection,
#'   [datom_update_members()] and [datom_remove_members()] for the other edits.
#' @export
#'
#' @examples
#' # Adding by name needs a live connection, so the runnable example lives on
#' # datom_assemble_set(), which shows the whole pipe.
#' print(names(formals(datom_add_member)))
datom_add_member <- function(x, member, version = NULL, tags = NULL,
                             conn = NULL) {

  if (!inherits(x, "datom_set")) {
    cli::cli_abort(
      c(
        "{.arg x} must be a {.cls datom_set}, from {.fn datom_assemble_set} or \\
         {.fn datom_get_set}.",
        "i" = "You passed {.cls {class(x)}}.",
        "i" = "Start one: {.code datom_assemble_set(conn) |> \\
               datom_add_member(\"dm\", v, conn = conn)}.",
        "i" = "Or read the set: \\
               {.code x <- datom_get_set(conn, \"my-product\")}.",
        "i" = "To build a member on its own, use {.fn datom_member}."
      ),
      class = "datom_not_a_set"
    )
  }

  if (!is.null(conn) && !inherits(conn, "datom_conn")) {
    cli::cli_abort(
      c(
        "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}.",
        "i" = "You passed {.cls {class(conn)}}.",
        "i" = "It is the connection a member given by name is looked up \\
               through."
      ),
      class = "datom_not_a_conn"
    )
  }

  got <- .datom_member_shape(member)
  shape <- got$shape

  if (is.null(got$record)) {
    # A NAME, resolved through `conn`. `datom_member()` reads the version's own
    # snapshot, so a member that does not exist aborts here -- on the line that
    # declared it -- rather than at the write.
    if (is.null(version)) {
      # Built as a string first: an artifact name reaching cli as message text
      # would be read as markup.
      hint <- sprintf("datom_history(conn, \"%s\")", member)
      cli::cli_abort(
        c(
          "Adding {.val {member}} needs the {.arg version} to pin.",
          "i" = "A member points at one exact version, and there is no \\
                 {.emph current}: inferring it would make this script produce \\
                 a different set on each run from the same source.",
          "i" = "List the versions with {.code {hint}}."
        ),
        class = "datom_member_version_required"
      )
    }

    # Only the `conn` argument, never a `conn` field on `x`: a set holds no
    # connection (point 1 of this file's header), so one found there was put
    # there by hand and must not be used silently.
    if (is.null(conn)) {
      hint <- sprintf(
        "datom_add_member(x, \"%s\", version, conn = conn)", member
      )
      cli::cli_abort(
        c(
          "Adding {.val {member}} by name needs {.arg conn}.",
          "i" = "A set holds no connection, and a name is looked up in one \\
                 project's storage.",
          "i" = "Pass the connection for the project that holds it: \\
                 {.code {hint}}."
        ),
        class = "datom_member_conn_required"
      )
    }

    record <- datom_member(conn, member, version, tags = tags)
  } else {
    if (!is.null(version) || !is.null(tags)) {
      cli::cli_abort(
        c(
          "{.arg version} and {.arg tags} describe a member given by \\
           {.emph name}, and you passed {shape}.",
          "i" = "{shape} already carries its own version and labels, so a \\
                 second set of them could only disagree with it.",
          "i" = "Drop them, or add the member by name -- or edit the record \\
                 before passing it."
        ),
        class = "datom_member_declared_twice"
      )
    }

    # A record read back from a set carries a callable `fetch`, which no payload
    # may hold. Dropped here so the validator below never needs a carve-out for
    # it -- and only when it is a function, so a hand-built `fetch = "junk"` still
    # reaches the validator and aborts.
    record <- .datom_strip_member_links(list(got$record))[[1L]]

    # The write-side contract, run per entry. That is the whole point of this
    # path: a malformed record aborts on the line that added it.
    .datom_validate_members(list(record))
  }

  # The record is appended AS GIVEN -- not tidied here. Tidying is the write's
  # job, and doing it here would change what a caller reads back out of the set
  # for no gain: the duplicate check below compares member digests, and the
  # encoder already treats a tag map as sorted keys over sorted, deduplicated
  # value sets, so every spelling tidying would collapse digests the same anyway.
  #
  # The existing members are compared WITHOUT their links: every member of a set
  # read back carries a callable `$fetch`, and the member digest refuses any
  # field beyond `id` and `tags`.
  clash <- .datom_draft_member_clash(
    .datom_strip_member_links(x$members), record
  )
  nm <- record$id$name

  if (identical(clash$status, "conflict")) {
    have <- .datom_format_tag_line(x$members[[clash$at]]$tags)
    want <- .datom_format_tag_line(record$tags)
    cli::cli_abort(
      c(
        "{.val {nm}} is already in this set, at the same version, with \\
         different labels.",
        "*" = "already added: {.val {have}}",
        "*" = "adding now:    {.val {want}}",
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

  if (identical(clash$status, "duplicate")) {
    # SKIPPED, NOT REFUSED, and said out loud. The write drops an exact repeat
    # silently, so refusing here would make this verb stricter than the list
    # form -- `Reduce(datom_add_member, records, init = x)` over a generated list
    # that happens to repeat would start failing where it works today. Skipping
    # in silence would move the surprise rather than remove it: the caller typed
    # a line and the count would not move.
    cli::cli_alert_info(
      "{.val {nm}} is already in this set with the same labels -- not \\
       added twice."
    )
    return(x)
  }

  x <- .datom_set_add_record(x, record)

  cli::cli_alert_info(
    "Nothing has been written. Write the set with \\
     {.code datom_write_set(conn, x)}."
  )

  x
}
