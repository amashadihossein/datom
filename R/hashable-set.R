# The datom-sv1 set contract: canonical identity for a set payload.
#
# Sibling of R/hashable.R, which holds the datom-cv1 table contract. The two
# regimes share NO primitive -- not even `.datom_encode_numeric()` -- and that
# is deliberate:
#
#   * A set payload is text-only (no numbers, no booleans, no `null`), so there
#     is nothing numeric to encode.
#   * Every intermediate here is a fixed-width 32-byte digest, so concatenation
#     is unambiguous without length prefixes: h("a") || h("b") is 64 bytes and
#     cannot collide with h("ab") at 32.
#
# What the two regimes do share is the house construction -- hash the
# per-element digests, then hash their concatenation -- and
# `digest::digest(..., algo = "sha256", serialize = FALSE)`.
#
# THE ENCODING (normative form; byte rules also in dev/datom_sv1_reference.R)
#
#   h(x)       = sha256(x)
#
#   str(s)     = h( 0x01 || utf8(s) )
#   strset(v)  = h( 0x02 || concat( str(e) for e in sort(unique(v), radix) ) )
#   map(m)     = h( 0x03 || concat( str(k) || strset(m[k])
#                                   for k in sort(keys(m), radix) ) )
#
#   member(x)  = h( 0x04 || map(x.id) || map(x.tags) )
#   set(p)     = h( 0x05 || map(p.tags) || concat( sort(unique(
#                            member(m) for m in p.members ), radix) ) )
#
#   data_sha   = h( 0x06 || utf8("datom-sv1") || set(payload) )
#
# Three things about it are load-bearing and must not be "tidied":
#
#   1. NO SERIALIZER IS IN THE IDENTITY PATH. `data_sha` is a function of the
#      parsed-JSON data model, never of emitted bytes. Stored-byte integrity is
#      `document_sha`'s separate job, so `jsonlite` may format the stored file
#      however it likes. Identity and storage integrity never share a
#      dependency -- that is the whole point of the regime.
#   2. NO RUNTIME TYPE DISPATCH. Every position's shape is fixed by where it
#      sits, so the encoder never asks "what type is this?" and therefore
#      cannot have an unhandled answer.
#   3. EVERY COLLECTION IS SORTED AND DEDUPED -- tag keys, tag values, and
#      members alike, with no carve-out. Sorting is `method = "radix"`, i.e.
#      C-locale byte order, so it is locale-independent (the same reason
#      `.datom_compute_metadata_sha()` sorts that way). No Unicode
#      normalization is applied: NFC and NFD are different tags, because
#      normalization tables are versioned Unicode data and nothing versioned
#      belongs in an identity path.
#
# The published golden vectors freeze all of the above. Changing any byte rule
# is a conscious `datom-sv2` bump, not an edit.
#
# WHAT THIS FILE DOES NOT DO: validate. Grammar enforcement with user-facing
# recourse (which key is wrong, what the allowed types are, whether two members
# share an `id` with conflicting tags) belongs to `.datom_validate_members()`
# and `datom_write_set()`, which are the only places that see a whole payload
# and a caller's intent. The refusals below are narrower: they exist because
# the value cannot be encoded at all (`NA`, a number, `null`) or because
# encoding it would silently drop content from identity (an unexpected field).


#' Hash Bytes for datom-sv1
#'
#' The single SHA-256 call of the `datom-sv1` regime. Returns **raw** bytes
#' rather than hex because every intermediate digest is concatenated into the
#' next hash input; hex would double the width and put a text encoding in the
#' identity path.
#'
#' @param bytes A raw vector.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_h <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE, raw = TRUE)
}


#' Render a Digest as Lowercase Hex
#'
#' Used for the two places the specification names hex: the collation key for
#' member digests, and the final `data_sha` string. Byte order and lowercase-hex
#' C-locale order agree (`00`-`09` before `0a`-`0f`, digits before letters in
#' ASCII), so sorting either representation gives the same result -- hex is
#' named in the spec because it is what a reader can compare by eye.
#'
#' @param x A raw vector.
#' @return A character string of `2 * length(x)` lowercase hex digits.
#' @keywords internal
.datom_sv1_hex <- function(x) {
  paste(as.character(x), collapse = "")
}


#' Coerce a Parsed-JSON String Set to a Character Vector
#'
#' A tag value arrives in one of three spellings, all meaning the same thing:
#' a length-1 character vector (`"output"`), a longer character vector
#' (`c("safety", "efficacy")`), or -- after a JSON round trip with
#' `simplifyVector = FALSE` -- a list of length-1 strings. All three normalise
#' to a character vector here, which is what makes a single string and a
#' one-element array hash identically.
#'
#' `character(0)` and `list()` (the parsed form of `[]`) both normalise to the
#' empty set. Validation refuses an empty tag value upstream and
#' canonicalization cannot produce one, but the encoder must not depend on that:
#' an encoder whose correctness rests on an upstream refusal breaks silently the
#' day the refusal is relaxed.
#'
#' @param v The value to normalise.
#' @param what Key path used in error messages (e.g. `"tags$domain"`).
#' @return A character vector, possibly of length zero.
#' @keywords internal
.datom_sv1_as_strings <- function(v, what) {
  if (is.null(v)) {
    cli::cli_abort(c(
      "{.field {what}} is {.code null}, which is not encodable.",
      "i" = "Absence is spelled by omitting the field, never by a null value."
    ))
  }

  abort_na <- function() {
    cli::cli_abort(c(
      "{.field {what}} contains {.code NA}, which is not encodable.",
      "i" = "Omit the field instead -- absence is omission, not a missing value."
    ))
  }

  if (is.list(v)) {
    # A NAMED list is an object, and an object has no meaning in a value
    # position. Refusing it is not fussiness: element-wise, `list(b = "c")` and
    # `list("c")` are indistinguishable, so accepting the first would encode
    # `{"a": {"b": "c"}}` as if it were `{"a": ["c"]}` -- two payloads sharing
    # one data_sha, with the key name silently outside identity.
    if (!is.null(names(v))) {
      cli::cli_abort(c(
        "{.field {what}} must be text or an array of text, not an object.",
        "i" = "A set payload has no nesting beyond members and their tag maps."
      ))
    }
    if (length(v) == 0L) return(character())
    ok <- vapply(
      v,
      function(e) is.character(e) && length(e) == 1L,
      logical(1L)
    )
    if (!all(ok)) {
      cli::cli_abort(c(
        "{.field {what}} must be text or an array of text.",
        "x" = "Element {which(!ok)[[1]]} is not a single string.",
        "i" = "A set payload holds only UTF-8 strings and arrays of them."
      ))
    }
    v <- unlist(v, use.names = FALSE)
  }

  # A bare `NA` is a logical, so it would otherwise be reported as a type error
  # and send the caller looking for a coercion instead of a deletion. Caught
  # ahead of the type gate for that reason -- and only when every element is NA,
  # so `c(TRUE, NA)` is still reported as what it is: a boolean.
  if (is.logical(v) && length(v) > 0L && all(is.na(v))) abort_na()

  # The type gate precedes the element-wise NA check because `is.na()` on a
  # closure or other non-vector warns rather than answering.
  if (!is.character(v)) {
    cli::cli_abort(c(
      "{.field {what}} must be text or an array of text, not {.cls {class(v)}}.",
      "i" = paste0(
        "A set payload is text-only: no numbers, booleans, or nesting. ",
        "Write a numeric tag as a string, e.g. {.val 500}."
      )
    ))
  }

  if (anyNA(v)) abort_na()

  v
}


#' Encode a String for datom-sv1
#'
#' `str(s) = h(0x01 || utf8(s))`. No length prefix and no terminator: the
#' string is the entire hash input, so nothing follows it to be confused with.
#'
#' @param s A length-1 character vector.
#' @param what Key path used in error messages.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_str <- function(s, what = "value") {
  s <- .datom_sv1_as_strings(s, what)
  if (length(s) != 1L) {
    cli::cli_abort(
      "{.field {what}} must be a single string, not {length(s)} values."
    )
  }
  .datom_sv1_h(c(as.raw(0x01L), charToRaw(enc2utf8(s))))
}


#' Encode a String Set for datom-sv1
#'
#' `strset(v) = h(0x02 || concat(str(e) for e in sort(unique(v), radix)))`.
#' Order and multiplicity are not identity: a multi-valued tag models
#' simultaneous membership in several categories, which has no order and no
#' notion of a repeated element.
#'
#' The empty set is `h(0x02)` over an empty concatenation -- a pinned golden.
#'
#' @param v A character vector, or a list of length-1 strings.
#' @param what Key path used in error messages.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_strset <- function(v, what = "value") {
  vals <- .datom_sv1_as_strings(v, what)
  body <- raw()
  if (length(vals) > 0L) {
    ordered <- sort(unique(vals), method = "radix")
    body <- unlist(
      lapply(ordered, function(e) .datom_sv1_str(e, what)),
      use.names = FALSE
    )
  }
  .datom_sv1_h(c(as.raw(0x02L), body))
}


#' Encode a Map for datom-sv1
#'
#' `map(m) = h(0x03 || concat(str(k) || strset(m[k]) for k in sort(keys(m), radix)))`.
#'
#' One encoder serves both slots of a member record -- the `id` and the `tags`
#' -- so a fifth `id` field added later is just another key: no positional
#' convention to maintain, and no absent-versus-empty question. `id` values are
#' single strings, encoded as one-element string sets; enforcing "exactly these
#' four keys, each single-valued" is validation's job, not the encoder's.
#'
#' An absent map (`NULL`) and an empty map both encode as `h(0x03)`. Writers
#' never emit an empty map, but the encoder must not depend on that.
#'
#' @param m A named list, or `NULL`.
#' @param what Key path used in error messages.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_map <- function(m, what = "map") {
  if (is.null(m)) return(.datom_sv1_h(as.raw(0x03L)))

  if (!is.list(m)) {
    cli::cli_abort(
      "{.field {what}} must be a named list, not {.cls {class(m)}}."
    )
  }
  if (length(m) == 0L) return(.datom_sv1_h(as.raw(0x03L)))

  keys <- names(m)
  if (is.null(keys) || any(is.na(keys)) || !all(nzchar(keys))) {
    cli::cli_abort(c(
      "Every key in {.field {what}} must be a non-empty name.",
      "i" = "An unnamed or blank key has no meaning as a tag."
    ))
  }
  if (anyDuplicated(keys) > 0L) {
    dup <- unique(keys[duplicated(keys)])
    cli::cli_abort(c(
      "{.field {what}} has {length(dup)} duplicate key{?s}: {.val {dup}}.",
      "i" = "A map with a repeated key has no single encoding."
    ))
  }

  body <- unlist(
    lapply(sort(keys, method = "radix"), function(k) {
      c(
        .datom_sv1_str(k, paste0(what, " key")),
        .datom_sv1_strset(m[[k]], paste0(what, "$", k))
      )
    }),
    use.names = FALSE
  )
  .datom_sv1_h(c(as.raw(0x03L), body))
}


#' Encode a Member Record for datom-sv1
#'
#' `member(x) = h(0x04 || map(x.id) || map(x.tags))`. Both slots are maps, so
#' swapping content between them cannot collide, and a member with no tags
#' encodes its `tags` slot as the empty map.
#'
#' An unexpected field aborts. That is not grammar validation creeping in: a
#' field the encoder ignored would be content that does not enter identity, so
#' two payloads differing in it would share one `data_sha` and one storage
#' address.
#'
#' @param x A member record: a list with `id` and optionally `tags`.
#' @param what Position label used in error messages.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_member <- function(x, what = "member") {
  if (!is.list(x) || is.null(names(x)) || !all(nzchar(names(x)))) {
    cli::cli_abort(
      "{.field {what}} must be a named list with an {.field id}."
    )
  }
  unknown <- setdiff(names(x), c("id", "tags"))
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "{.field {what}} carries {length(unknown)} unexpected field{?s}: {.val {unknown}}.",
      "i" = paste0(
        "A member is exactly an {.field id} plus optional {.field tags}. ",
        "Encoding around an extra field would leave it out of identity."
      )
    ))
  }
  if (is.null(x$id) || length(x$id) == 0L) {
    cli::cli_abort(c(
      "{.field {what}} has no {.field id}.",
      "i" = "Build members with {.fn datom_member}."
    ))
  }

  .datom_sv1_h(c(
    as.raw(0x04L),
    .datom_sv1_map(x$id, paste0(what, "$id")),
    .datom_sv1_map(x$tags, paste0(what, "$tags"))
  ))
}


#' Encode a Set Payload for datom-sv1
#'
#' `set(p) = h(0x05 || map(p.tags) || concat(sort(unique(member(m)), radix)))`.
#'
#' Member digests are deduped and sorted, exactly like tag values: arrangement
#' is presentation, not content. The producer of a member list is normally a
#' script, so an insertion-order refactor must not mint a new version of a
#' citable artifact.
#'
#' A zero-member payload aborts, mirroring `.datom_canonical_hash()`'s refusal
#' of a zero-row or zero-column table.
#'
#' @param payload A list with `members` and optional set-level `tags`.
#' @param what Position label used in error messages.
#' @return A raw vector of 32 bytes.
#' @keywords internal
.datom_sv1_set <- function(payload, what = "payload") {
  if (!is.list(payload)) {
    cli::cli_abort(
      "{.arg {what}} must be a list, not {.cls {class(payload)}}."
    )
  }
  keys <- names(payload)
  if (length(payload) > 0L && (is.null(keys) || !all(nzchar(keys)))) {
    cli::cli_abort("{.arg {what}} must be a named list.")
  }
  unknown <- setdiff(keys, c("tags", "members"))
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "{.arg {what}} carries {length(unknown)} unexpected field{?s}: {.val {unknown}}.",
      "i" = paste0(
        "A set payload is exactly {.field members} plus optional set-level ",
        "{.field tags}. Container facts such as {.field schema_version} ",
        "describe the format, not the content, and stay out of identity."
      )
    ))
  }

  members <- payload$members
  if (is.null(members) || length(members) == 0L) {
    cli::cli_abort(c(
      "A set must have at least one member.",
      "i" = "An empty set has no content to identify."
    ))
  }
  if (!is.list(members) || !is.null(names(members))) {
    cli::cli_abort(
      "{.field members} must be an unnamed list of member records."
    )
  }

  digests <- lapply(seq_along(members), function(i) {
    .datom_sv1_member(members[[i]], sprintf("members[[%d]]", i))
  })
  hex <- vapply(digests, .datom_sv1_hex, character(1L))
  keep <- !duplicated(hex)
  digests <- digests[keep]
  hex <- hex[keep]
  digests <- digests[order(hex, method = "radix")]

  .datom_sv1_h(c(
    as.raw(0x05L),
    .datom_sv1_map(payload$tags, "tags"),
    unlist(digests, use.names = FALSE)
  ))
}


#' Compute the datom-sv1 Canonical Set-Content Hash
#'
#' The identity engine for a set artifact: `data_sha` for the payload's
#' semantic content. `data_sha = h(0x06 || utf8("datom-sv1") || set(payload))`.
#'
#' The hash domain is the **parsed-JSON data model**, not the in-memory R
#' object, and the write path -- which necessarily starts from an in-memory
#' object -- agrees with it *by construction* rather than through a
#' serialize-and-reparse pass. Each way a JSON round trip could mutate a value
#' is unrepresentable instead of handled: there are no numbers (so
#' integer-versus-double cannot arise), `NA` aborts and absence is omission (so
#' neither the string `"NA"` nor `null` can appear), and a single string hashes
#' equal to a one-element array (so scalar-versus-length-1 is not a question).
#' One structural condition remains: the payload must be parsed with
#' `simplifyVector = FALSE`, so `members[]` stays a list of records instead of
#' collapsing into a data frame. Both storage backends already do that.
#'
#' No I/O, no serializer, and no dependency that carries versioned data --
#' which is what makes the hash stable across R versions, `jsonlite` versions,
#' platforms, and architectures.
#'
#' @param payload The set payload: a list with `members` (an unnamed list of
#'   member records, each an `id` map plus optional `tags` map) and optional
#'   set-level `tags`.
#' @return A 64-character SHA-256 hex string.
#' @keywords internal
.datom_canonical_set_hash <- function(payload) {
  .datom_sv1_hex(.datom_sv1_h(c(
    as.raw(0x06L),
    charToRaw("datom-sv1"),
    .datom_sv1_set(payload)
  )))
}
