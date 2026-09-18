# Assembling a set in steps: a draft, a verb that adds one member to it, and the
# widening that lets a pipe end at the write.
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
#   1. THE DRAFT HOLDS THE CONNECTION, AND THAT IS STRUCTURAL RATHER THAN
#      CONVENIENT. Validating a member as it is added means reading that
#      artifact's own metadata snapshot out of storage, so a draft that held no
#      connection could not validate at all -- which is the entire reason the
#      verb exists. Two consequences follow, and neither is optional:
#      `datom_add_member()` must never take a `conn` argument (that would put two
#      connections on one draft and make the property false), and a draft is
#      transient -- it must not be saved, because a connection may carry a
#      credential and connections live in memory only.
#
#   2. A RECORD IN ARGUMENT 2 IS A CAPABILITY, NOT SUGAR. A draft holds ONE
#      connection, and a name is resolved through it, so a member of a DIFFERENT
#      project cannot be declared by name in a pipe at all. Passing a record built
#      on the other project's connection -- `datom_member(conn_b, "ae", v)` -- is
#      the only route to a cross-project member here. Deleting the record shape
#      as "a convenience" would remove a capability.
#
#   3. `version` STAYS REQUIRED WHEN A MEMBER IS ADDED BY NAME. Inferring
#      "current" would leave a build script producing a DIFFERENT set on each run
#      from byte-identical source. Pinning makes the artifact immutable; requiring
#      the pin makes the code reproducible, and those are two separate
#      guarantees.
#
#   4. THE PRINT METHOD NAMES EVERY FIELD IT SHOWS AND NEVER HANDS THE
#      CONNECTION TO ANYTHING. Same shape as `print.datom_conn`, and for the same
#      reason: that method is an ALLOWLIST of named fields, so a credential field
#      added to a connection later cannot leak through it. Redaction would have
#      to be taught each new secret; an allowlist is safe by default. There is no
#      masking helper to reach for, and inventing one is how a token reaches
#      output.
#
#   5. A DRAFT DELIBERATELY HOLDS A LIVE CONNECTION, WHICH INVERTS THE PURITY
#      RULE MEMBERS AND LINKS FOLLOW. A member record is pure data and there is a
#      test asserting a serialized one contains no token; a draft is the opposite
#      by design. So there is no purity test for a draft -- the print method warns
#      instead.
#
#   6. THE MEMBER COUNT A DRAFT REPORTS IS THE COUNT THE WRITE WILL PRODUCE, and
#      skipping an exact repeat rather than appending it is what keeps those two
#      numbers equal. The write drops an exact repeat silently, so a draft that
#      appended it would print one count and write another -- and the printed
#      count is the one number a caller inspects mid-pipe. The same version with
#      DIFFERENT labels is an error at the write, so it is an error here too, on
#      the line that introduced it. Both comparisons go through the write's own
#      mechanisms -- the payload check's id key and the dedup's member digest --
#      because `identical()` on two records reads two spellings of one label set
#      as a disagreement and would refuse what the write accepts.


#' Is This Member Already in the Draft, and Is It the Same Member?
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
#' compared -- and stored in the draft -- exactly as the caller supplied it.
#'
#' @param members The draft's members so far.
#' @param record The record about to be added.
#' @return A list with `status` -- `"new"`, `"duplicate"` or `"conflict"` -- and,
#'   for the last two, `at`: the position of the member already in the draft.
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


#' Start assembling a set
#'
#' Opens a **draft** set, to be filled in with [datom_add_member()] and written
#' with [datom_write_set()]:
#'
#' ```r
#' datom_assemble_set(conn, tags = list(description = "ADaM datasets")) |>
#'   datom_add_member("adsl", v_adsl, tags = list(type = "output")) |>
#'   datom_add_member("dm", v_dm, tags = list(type = "input")) |>
#'   datom_write_set()
#' ```
#'
#' The equivalent single call -- a `list()` of [datom_member()] results passed to
#' [datom_write_set()] -- remains fully supported and is the better fit for a
#' build script. What this path adds is **where an error surfaces**: a malformed
#' member aborts on the line that declared it and names that member, instead of
#' aborting once the whole list has been assembled and indexed.
#'
#' @section A draft holds a connection:
#' Validating each member as it is added means reading that artifact's metadata
#' from storage, so the draft carries the connection it was opened with. Two
#' things follow:
#'
#' * **A draft belongs in memory only.** A connection may carry a credential, so a
#'   draft must not be saved to disk or committed. Write the set, and cite the set.
#' * **One draft, one project.** A member of another project cannot be named
#'   through this connection -- pass a record built on that project's connection
#'   instead, which [datom_add_member()] accepts in place of a name.
#'
#' @section Set-level tags:
#' Supplied here rather than by a third verb, because they are facts about the
#' collection rather than about any member. Editing them later is plain R --
#' `draft$tags$description <- "..."` -- and the same grammar applies as to a
#' member's tags: text only, one label or several.
#'
#' @param conn A `datom_conn` from [datom_get_conn()], scoped to the product repo.
#' @param name The set's name. `NULL` (the default) takes the name the repo
#'   declares under `set:` in `.datom/project.yaml`, which is the usual case --
#'   one repo holds one set.
#' @param tags Optional named list of set-level text labels, e.g. a description.
#'
#' @return A `datom_set_draft`: the connection, the name, the tags, and an empty
#'   member list.
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
#'   draft <- datom_assemble_set(
#'     conn,
#'     tags = list(description = "Example product for STUDY-001")
#'   ) |>
#'     datom_add_member("dm", v_dm, tags = list(type = "input")) |>
#'     datom_add_member("lb", v_lb, tags = list(type = "output"))
#'
#'   print(draft)
#'   datom_write_set(draft)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_assemble_set <- function(conn, name = NULL, tags = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      c(
        "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}.",
        "i" = "A draft validates each member as it is added, which needs the \\
               connection the members are read through."
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

  structure(
    list(conn = conn, name = name, tags = tags, members = list()),
    class = "datom_set_draft"
  )
}


#' Add one member to a draft set
#'
#' Declares one member and appends it to a draft from [datom_assemble_set()],
#' validating it immediately: the artifact must exist at the version given, and
#' its labels must be well formed. The member record is built through the same
#' path [datom_member()] uses, so a set assembled this way is byte-identical to
#' the same set passed as a list.
#'
#' @section Naming a member:
#' `member` accepts the three shapes a caller holds, and the second and third are
#' not merely convenient:
#'
#' | What you pass | What it means |
#' |---|---|
#' | a name | look this artifact up through the draft's connection |
#' | a member record | use it as given -- from [datom_member()], or from a set read back |
#' | a link | use the member it points at -- `x$members[[i]]$fetch`, or a leaf of [datom_structure_members()] |
#'
#' **A record is the only way to add a member of another project.** A draft holds
#' one connection, so a name can only be resolved in that project; a record built
#' on the other project's connection carries its own resolved pointer:
#'
#' ```r
#' datom_assemble_set(conn_a) |>
#'   datom_add_member("dm", v1) |>                     # this project, by name
#'   datom_add_member(datom_member(conn_b, "ae", v2))   # another project
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
#' @param x A `datom_set_draft` from [datom_assemble_set()].
#' @param member The member to add: an artifact name, a member record, or a link.
#' @param version The version to pin, when `member` is a name. Required there;
#'   refused beside a record or a link.
#' @section Adding the same member twice:
#' The two cases differ, and they differ the same way they differ at the write:
#'
#' * **The same version with the same labels** is skipped, with a note. The write
#'   drops an exact repeat anyway, so refusing here would make a draft stricter
#'   than the equivalent list -- `Reduce(datom_add_member, records, init = draft)`
#'   over a generated list that happens to repeat would fail where it works today.
#' * **The same version with different labels** aborts. One version of one
#'   artifact is one member holding one set of labels, and merging or choosing
#'   between two sets would guess. The write refuses this too; here it names the
#'   line that introduced it.
#'
#' So the member count a draft reports is the count the write will produce. Two
#' different **versions** of one artifact are two members, and both are kept.
#'
#' @param tags Optional named list of text labels for this member, when `member`
#'   is a name. Refused beside a record or a link, which carry their own.
#'
#' @return The draft, one member longer -- or unchanged, when the member was
#'   already in it with the same labels.
#' @seealso [datom_assemble_set()] to open a draft, [datom_member()] to build a
#'   record on another connection.
#' @export
#'
#' @examples
#' # A draft needs a live connection, so the runnable example lives on
#' # datom_assemble_set(), which shows the whole pipe.
#' print(names(formals(datom_add_member)))
datom_add_member <- function(x, member, version = NULL, tags = NULL) {

  if (!inherits(x, "datom_set_draft")) {
    cli::cli_abort(
      c(
        "{.arg x} must be a {.cls datom_set_draft} from \\
         {.fn datom_assemble_set}.",
        "i" = "Open one first: \\
               {.code datom_assemble_set(conn) |> datom_add_member(\"dm\", v)}.",
        "i" = "To build a member on its own, use {.fn datom_member}."
      ),
      class = "datom_not_a_draft"
    )
  }

  got <- .datom_member_shape(member)
  shape <- got$shape

  if (is.null(got$record)) {
    # A NAME, resolved through the draft's one connection. `datom_member()` reads
    # the version's own snapshot, so a member that does not exist aborts here --
    # on the line that declared it -- rather than at the write.
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

    record <- datom_member(x$conn, member, version, tags = tags)
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
  # job, and doing it here would change what a caller reads back out of the draft
  # for no gain: the duplicate check below compares member digests, and the
  # encoder already treats a tag map as sorted keys over sorted, deduplicated
  # value sets, so every spelling tidying would collapse digests the same anyway.
  clash <- .datom_draft_member_clash(x$members, record)
  nm <- record$id$name

  if (identical(clash$status, "conflict")) {
    have <- .datom_format_tag_line(x$members[[clash$at]]$tags)
    want <- .datom_format_tag_line(record$tags)
    cli::cli_abort(
      c(
        "{.val {nm}} is already in this draft, at the same version, with \\
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
    # silently, so refusing here would make the draft stricter than the list form
    # -- `Reduce(datom_add_member, records, init = draft)` over a generated list
    # that happens to repeat would start failing where it works today. Skipping
    # in silence would move the surprise rather than remove it: the caller typed
    # a line and the count would not move.
    cli::cli_alert_info(
      "{.val {nm}} is already in this draft with the same labels -- not added \\
       twice."
    )
    return(x)
  }

  x$members <- c(x$members, list(record))

  x
}


#' Print a draft set
#'
#' What is assembled so far, and that it is not written yet. One line per member
#' -- name, kind, and its labels as compact `key=value` pairs -- which is what
#' makes a pipe inspectable mid-build.
#'
#' **It names every field it shows and never prints the connection.** A
#' connection may carry a credential, and a `datom_conn` prints an allowlist of
#' named fields for exactly that reason: a secret added to a connection later
#' cannot leak through a method that never iterates it.
#'
#' @param x A `datom_set_draft` from [datom_assemble_set()].
#' @param ... Ignored.
#' @param n Maximum number of members to list.
#' @return Invisible `x`.
#' @export
#'
#' @examples
#' # See datom_assemble_set() for a runnable example that prints a draft.
#' print(names(formals(datom_assemble_set)))
print.datom_set_draft <- function(x, ..., n = 20L) {

  # A name is optional, and the usual case is not supplying one -- so the header
  # says where the name will come from rather than quoting a sentence as if it
  # were the set's name.
  if (is.null(x$name)) {
    cli::cli_h3("datom set draft: {.emph the set this repo declares}")
  } else {
    cli::cli_h3("datom set draft: {.val {x$name}}")
  }

  cli::cli_ul()
  # Named fields only, and never `x$conn` itself -- see this method's docs.
  cli::cli_li("Project: {.val {x$conn$project_name}}")
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

  cli::cli_alert_info("Not written yet -- finish with {.code datom_write_set()}.")
  cli::cli_alert_warning(
    "A draft holds a live connection, so it belongs in memory only -- do not \\
     save one to disk or commit it."
  )

  invisible(x)
}
