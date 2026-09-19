# ==============================================================================
# datom-sv1 -- reference implementation + self-test (standalone)
# ==============================================================================
# Canonical content hash for a SET payload ("data_sha"), per datom issue #89.
# Sibling of datom_cv1_reference.R, which does the same job for tabular data.
#
# This file is the NORMATIVE home of the sv1 byte rules and the marker table.
# It is written against the encoding specification, not against any emitter's
# output and not against the package -- the package must match it, never the
# other way round.
#
# Design properties this script embodies:
#   * NO SERIALIZER IN THE IDENTITY PATH. The hash is a function of the
#     parsed-JSON data model. Whatever formats the stored file is irrelevant,
#     because stored-byte integrity is `document_sha`'s separate job. Identity
#     and storage integrity never share a dependency.
#   * NO RUNTIME TYPE DISPATCH. Every position's shape is fixed by where it
#     sits, so the encoder never asks "what type is this?" and cannot have an
#     unhandled answer.
#   * EVERY COLLECTION IS SORTED AND DEDUPED -- tag keys, tag values, members.
#     No carve-out. Sorting is method = "radix", i.e. C-locale byte order, so
#     it is locale-independent.
#   * NO UNICODE NORMALIZATION. NFC and NFD are different tags. Normalization
#     tables are versioned Unicode data, and nothing versioned belongs in an
#     identity path -- that is the failure this whole regime exists to avoid.
#   * NO LENGTH PREFIXES, and no numeric primitive of any kind. Every
#     intermediate is a fixed 32 bytes, so concatenation is already
#     unambiguous. sv1 shares no numeric encoder with cv1.
#   * Only dependency: the `digest` package, used solely as
#     digest(raw_bytes, algo = "sha256", serialize = FALSE).
#
# THE ENCODING
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
# MARKER TABLE (domain separation -- one byte per constructor, so a collision
# across two positions reduces to a SHA-256 collision):
#
#   0x01  string          UTF-8 bytes, no NA
#   0x02  string set      radix-sorted, deduped
#   0x03  map             radix-sorted keys; serves both `id` and `tags`
#   0x04  member          map(id) || map(tags)
#   0x05  set             map(tags) || concat(member digests, sorted + deduped)
#   0x06  payload root    prefixed with utf8("datom-sv1")
#
#   No marker exists for a number, a boolean, or null: none of the three is in
#   the payload grammar. Absence is spelled by omitting the field.
#
# Run:  Rscript dev/datom_sv1_reference.R
# The self-test prints PASS/FAIL per property and a final summary, and prints
# golden hash constants for fixed fixtures. Record these and re-run on other
# machines / R versions / OSes: they must never change. Any change means the
# spec was violated and requires a conscious bump to datom-sv2.
# ==============================================================================

# --- core ---------------------------------------------------------------------

# Raw output, not hex: every intermediate is concatenated into the next hash
# input, so hex would double the width and put a text encoding in the identity
# path.
.sv1_h <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE, raw = TRUE)
}

.sv1_hex <- function(x) paste(as.character(x), collapse = "")

# Normalise the three spellings of a string set: a character vector of any
# length, or -- after a JSON round trip with simplifyVector = FALSE -- a list of
# length-1 strings. `character(0)` and `list()` (parsed from `[]`) are the empty
# set. This normalisation is what makes "output" and ["output"] hash equal.
.sv1_strings <- function(v, what) {
  if (is.null(v)) {
    stop(sprintf("datom-sv1: '%s' is null; absence is omission, not null.",
                 what), call. = FALSE)
  }
  na_msg <- function() {
    stop(sprintf("datom-sv1: '%s' contains NA, which is not encodable -- omit the field instead.",
                 what), call. = FALSE)
  }
  if (is.list(v)) {
    # A NAMED list is an object, which has no meaning in a value position.
    # Element-wise, list(b = "c") and list("c") are indistinguishable, so
    # accepting the first would encode {"a": {"b": "c"}} as {"a": ["c"]} -- two
    # payloads sharing one data_sha, with the key name outside identity.
    if (!is.null(names(v))) {
      stop(sprintf("datom-sv1: '%s' must be text or an array of text, not an object.",
                   what), call. = FALSE)
    }
    if (length(v) == 0L) return(character())
    ok <- vapply(v, function(e) is.character(e) && length(e) == 1L, logical(1L))
    if (!all(ok)) {
      stop(sprintf("datom-sv1: '%s' must be text or an array of text.", what),
           call. = FALSE)
    }
    v <- unlist(v, use.names = FALSE)
  }
  # A bare NA is logical, so it would otherwise be reported as a type error and
  # send the caller looking for a coercion instead of a deletion. Only when every
  # element is NA, so c(TRUE, NA) is still reported as the boolean it is.
  if (is.logical(v) && length(v) > 0L && all(is.na(v))) na_msg()
  # The type gate precedes the element-wise NA check because is.na() on a
  # closure warns rather than answering.
  if (!is.character(v)) {
    stop(sprintf("datom-sv1: '%s' must be text or an array of text, not %s (the payload is text-only).",
                 what, paste(class(v), collapse = "/")), call. = FALSE)
  }
  if (anyNA(v)) na_msg()
  v
}

.sv1_str <- function(s, what = "value") {
  s <- .sv1_strings(s, what)
  if (length(s) != 1L) {
    stop(sprintf("datom-sv1: '%s' must be a single string.", what), call. = FALSE)
  }
  .sv1_h(c(as.raw(0x01L), charToRaw(enc2utf8(s))))
}

.sv1_strset <- function(v, what = "value") {
  vals <- .sv1_strings(v, what)
  body <- raw()
  if (length(vals) > 0L) {
    body <- unlist(lapply(sort(unique(vals), method = "radix"),
                          function(e) .sv1_str(e, what)),
                   use.names = FALSE)
  }
  .sv1_h(c(as.raw(0x02L), body))
}

# Absent and empty maps both encode as h(0x03). Writers never emit an empty map,
# but the encoder must not depend on that.
.sv1_map <- function(m, what = "map") {
  if (is.null(m)) return(.sv1_h(as.raw(0x03L)))
  if (!is.list(m)) {
    stop(sprintf("datom-sv1: '%s' must be a named list.", what), call. = FALSE)
  }
  if (length(m) == 0L) return(.sv1_h(as.raw(0x03L)))
  keys <- names(m)
  if (is.null(keys) || any(is.na(keys)) || !all(nzchar(keys))) {
    stop(sprintf("datom-sv1: every key in '%s' must be a non-empty name.", what),
         call. = FALSE)
  }
  if (anyDuplicated(keys) > 0L) {
    stop(sprintf("datom-sv1: '%s' has a duplicate key; a repeated key has no single encoding.",
                 what), call. = FALSE)
  }
  body <- unlist(lapply(sort(keys, method = "radix"), function(k) {
    c(.sv1_str(k, paste0(what, " key")),
      .sv1_strset(m[[k]], paste0(what, "$", k)))
  }), use.names = FALSE)
  .sv1_h(c(as.raw(0x03L), body))
}

# An unexpected field aborts rather than being ignored: an ignored field would
# be content outside identity, so two different payloads would share one
# data_sha and one storage address.
.sv1_member <- function(x, what = "member") {
  if (!is.list(x) || is.null(names(x)) || !all(nzchar(names(x)))) {
    stop(sprintf("datom-sv1: '%s' must be a named list with an id.", what),
         call. = FALSE)
  }
  unknown <- setdiff(names(x), c("id", "tags"))
  if (length(unknown) > 0L) {
    stop(sprintf("datom-sv1: '%s' has unexpected field(s): %s. A member is an id plus optional tags.",
                 what, paste(unknown, collapse = ", ")), call. = FALSE)
  }
  if (is.null(x$id) || length(x$id) == 0L) {
    stop(sprintf("datom-sv1: '%s' has no id.", what), call. = FALSE)
  }
  .sv1_h(c(as.raw(0x04L),
           .sv1_map(x$id, paste0(what, "$id")),
           .sv1_map(x$tags, paste0(what, "$tags"))))
}

.sv1_set <- function(payload, what = "payload") {
  if (!is.list(payload)) {
    stop("datom-sv1: `payload` must be a list.", call. = FALSE)
  }
  keys <- names(payload)
  if (length(payload) > 0L && (is.null(keys) || !all(nzchar(keys)))) {
    stop("datom-sv1: `payload` must be a named list.", call. = FALSE)
  }
  unknown <- setdiff(keys, c("tags", "members"))
  if (length(unknown) > 0L) {
    stop(sprintf("datom-sv1: `payload` has unexpected field(s): %s. A payload is members plus optional set-level tags.",
                 paste(unknown, collapse = ", ")), call. = FALSE)
  }
  members <- payload$members
  if (is.null(members) || length(members) == 0L) {
    stop("datom-sv1: a set must have at least one member.", call. = FALSE)
  }
  if (!is.list(members) || !is.null(names(members))) {
    stop("datom-sv1: `members` must be an unnamed list of member records.",
         call. = FALSE)
  }
  digests <- lapply(seq_along(members), function(i) {
    .sv1_member(members[[i]], sprintf("members[[%d]]", i))
  })
  hex <- vapply(digests, .sv1_hex, character(1L))
  keep <- !duplicated(hex)
  digests <- digests[keep]
  hex <- hex[keep]
  digests <- digests[order(hex, method = "radix")]
  .sv1_h(c(as.raw(0x05L),
           .sv1_map(payload$tags, "tags"),
           unlist(digests, use.names = FALSE)))
}

datom_canonical_set_hash <- function(payload) {
  .sv1_hex(.sv1_h(c(as.raw(0x06L), charToRaw("datom-sv1"), .sv1_set(payload))))
}

# ==============================================================================
# Self-test suite
# ==============================================================================

.results <- new.env(parent = emptyenv())
.results$pass <- 0L; .results$fail <- 0L

check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (ok) .results$pass <- .results$pass + 1L else .results$fail <- .results$fail + 1L
  cat(sprintf("[%s] %s\n", if (ok) "PASS" else "FAIL", label))
  invisible(ok)
}

expect_error_msg <- function(expr, pattern) {
  err <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  !is.null(err) && grepl(pattern, err, fixed = FALSE)
}

h <- datom_canonical_set_hash

# Member helpers for the fixtures. `id` is a map of four single strings; tags
# are optional and per-member.
mid <- function(name, version, project = "STUDY_001", kind = "table") {
  list(project = project, name = name, kind = kind, version = version)
}
mem <- function(name, version, tags = NULL, ...) {
  out <- list(id = mid(name, version, ...))
  if (!is.null(tags)) out$tags <- tags
  out
}

cat("== datom-sv1 self-test ==\n\n")

# --- 0. pin SHA-256 itself against the published NIST test vector -------------
check("NIST vector: sha256('abc') is correct (pins the digest package)",
      digest::digest(charToRaw("abc"), algo = "sha256", serialize = FALSE) ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

# --- 1. determinism and key-order independence ---------------------------------
p1 <- list(tags = list(description = "ADaM datasets"),
           members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa")))
check("same payload twice -> same hash", h(p1) == h(p1))

p1_reordered_keys <- list(
  members = list(
    list(tags = NULL, id = mid("dm", "d0922fc7"))[c("id")],
    list(id = mid("adsl", "7e21b0aa"))
  ),
  tags = list(description = "ADaM datasets")
)
check("payload key insertion order -> equal (maps are sorted)",
      h(p1) == h(p1_reordered_keys))

id_swapped <- list(members = list(
  list(id = list(name = "dm", project = "STUDY_001",
                 version = "d0922fc7", kind = "table")),
  list(id = mid("adsl", "7e21b0aa"))
))
check("id key insertion order -> equal",
      h(list(members = p1$members)) == h(id_swapped))

# --- 2. nothing in a payload is ordered, and no collection counts duplicates ---
# These four are the payload-level identity boundary. Each pair states the same
# fact two ways, so they must hash EQUAL -- a citable version must not be minted
# by a purely syntactic authoring choice.
tv_a <- list(members = list(mem("adsl", "7e21b0aa",
                               tags = list(domain = c("safety", "efficacy")))))
tv_b <- list(members = list(mem("adsl", "7e21b0aa",
                               tags = list(domain = c("efficacy", "safety")))))
check("tag-value ORDER -> equal", h(tv_a) == h(tv_b))

tv_dup <- list(members = list(mem("adsl", "7e21b0aa",
                                 tags = list(domain = c("safety", "safety")))))
tv_one <- list(members = list(mem("adsl", "7e21b0aa",
                                 tags = list(domain = "safety"))))
check("tag-value DUPLICATION -> equal", h(tv_dup) == h(tv_one))

shape_scalar <- list(members = list(mem("adsl", "7e21b0aa",
                                       tags = list(type = "output"))))
shape_array <- list(members = list(mem("adsl", "7e21b0aa",
                                      tags = list(type = list("output")))))
check("single string vs ONE-ELEMENT ARRAY -> equal",
      h(shape_scalar) == h(shape_array))

mo_a <- list(members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa")))
mo_b <- list(members = list(mem("adsl", "7e21b0aa"), mem("dm", "d0922fc7")))
check("MEMBER ORDER -> equal (arrangement is presentation, not content)",
      h(mo_a) == h(mo_b))

md <- list(members = list(mem("dm", "d0922fc7"), mem("dm", "d0922fc7")))
check("MEMBER DUPLICATION -> equal to one entry",
      h(md) == h(list(members = list(mem("dm", "d0922fc7")))))

# --- 3. what IS identity --------------------------------------------------------
check("member VERSION advanced -> DIFFER",
      h(list(members = list(mem("dm", "d0922fc7")))) !=
        h(list(members = list(mem("dm", "aaaaaaaa")))))
check("member NAME changed -> DIFFER",
      h(list(members = list(mem("dm", "d0922fc7")))) !=
        h(list(members = list(mem("lb", "d0922fc7")))))
check("member PROJECT changed -> DIFFER",
      h(list(members = list(mem("dm", "d0922fc7")))) !=
        h(list(members = list(mem("dm", "d0922fc7", project = "STUDY_002")))))
check("member KIND changed -> DIFFER",
      h(list(members = list(mem("dm", "d0922fc7")))) !=
        h(list(members = list(mem("dm", "d0922fc7", kind = "set")))))
check("a member TAG edit -> DIFFER (whole payload is hashed)",
      h(list(members = list(mem("dm", "d0922fc7", tags = list(type = "input"))))) !=
        h(list(members = list(mem("dm", "d0922fc7", tags = list(type = "output"))))))
check("a SET-LEVEL tag edit -> DIFFER (a description is a tag)",
      h(list(tags = list(description = "a"), members = list(mem("dm", "d0922fc7")))) !=
        h(list(tags = list(description = "b"), members = list(mem("dm", "d0922fc7")))))
check("an added member -> DIFFER",
      h(mo_a) != h(list(members = list(mem("dm", "d0922fc7")))))
check("same name at two DIFFERENT versions -> both present, differs from either alone",
      {
        both <- list(members = list(mem("adsl", "a1b2"), mem("adsl", "f9e8")))
        h(both) != h(list(members = list(mem("adsl", "a1b2")))) &&
          h(both) != h(list(members = list(mem("adsl", "f9e8"))))
      })

# --- 4. absent vs empty, and the pinned primitive constants ---------------------
check("absent tags == empty tags map",
      h(list(members = list(mem("dm", "d0922fc7")))) ==
        h(list(members = list(list(id = mid("dm", "d0922fc7"), tags = list())))))
check("absent set-level tags == empty set-level tags map",
      h(list(members = list(mem("dm", "d0922fc7")))) ==
        h(list(tags = list(), members = list(mem("dm", "d0922fc7")))))
check("strset(character(0)) == h(0x02), and equals strset(list()) [parsed []]",
      identical(.sv1_strset(character(0)), .sv1_h(as.raw(0x02L))) &&
        identical(.sv1_strset(list()), .sv1_h(as.raw(0x02L))))
check("map(NULL) == map(list()) == h(0x03)",
      identical(.sv1_map(NULL), .sv1_h(as.raw(0x03L))) &&
        identical(.sv1_map(list()), .sv1_h(as.raw(0x03L))))

# --- 5. domain separation and framing -------------------------------------------
check("domain separation: str / strset / map of the same text all DIFFER",
      length(unique(c(.sv1_hex(.sv1_str("a")),
                      .sv1_hex(.sv1_strset("a")),
                      .sv1_hex(.sv1_map(list(a = "a")))))) == 3L)
check("framing is free: ['a','b'] != ['ab'] (fixed-width entries)",
      !identical(.sv1_strset(c("a", "b")), .sv1_strset("ab")))
check("id/tags slot swap cannot collide",
      {
        a <- list(id = list(k = "v"), tags = list(x = "y"))
        b <- list(id = list(x = "y"), tags = list(k = "v"))
        !identical(.sv1_member(a), .sv1_member(b))
      })

# --- 6. unicode: bytes as given, no normalization -------------------------------
# Fixtures built via intToUtf8 so this file stays pure ASCII and is immune to
# editor re-normalization.
s_nfc <- paste0("na", intToUtf8(0x00EF), "ve")    # precomposed i-diaeresis
s_nfd <- paste0("nai", intToUtf8(0x0308), "ve")   # i + combining diaeresis
check("NFC vs NFD tag value -> DIFFER (no Unicode normalization)",
      h(list(members = list(mem("dm", "d0922fc7", tags = list(t = s_nfc))))) !=
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = s_nfd))))))
check("NFC vs NFD tag KEY -> DIFFER",
      {
        ka <- list(); ka[[s_nfc]] <- "v"
        kb <- list(); kb[[s_nfd]] <- "v"
        h(list(members = list(mem("dm", "d0922fc7", tags = ka)))) !=
          h(list(members = list(mem("dm", "d0922fc7", tags = kb))))
      })
jp <- intToUtf8(c(0x65E5, 0x672C, 0x8A9E))
check("non-ASCII tag hashes deterministically",
      h(list(members = list(mem("dm", "d0922fc7", tags = list(t = jp))))) ==
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = jp))))))

# --- 7. what is not encodable aborts (the refusals are part of the spec) --------
check("NA tag value -> abort telling the caller to omit the field",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = NA))))),
        "NA.*omit the field"))
check("NA_character_ tag value -> abort",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = NA_character_))))),
        "NA"))
check("numeric tag value -> abort (payload is text-only)",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = 500))))),
        "text-only|must be text"))
check("logical tag value -> abort",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = TRUE))))),
        "text-only|must be text"))
check("factor tag value -> abort",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = factor("a")))))),
        "text-only|must be text"))
check("nested list tag value -> abort (no nesting beyond the fixed shape)",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7",
                                  tags = list(t = list(list("a"))))))),
        "must be text"))
# The dangerous nesting case: a NAMED list in a value position. Element-wise it
# is indistinguishable from a one-element array, so accepting it would put the
# inner key outside identity and give two payloads one data_sha.
check("nested OBJECT tag value -> abort (not silently read as [value])",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7",
                                  tags = list(t = list(inner = "a")))))),
        "not an object"))
check("function tag value -> abort without an is.na() warning",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7", tags = list(t = mean))))),
        "text-only"))
check("null tag value -> abort (absence is omission)",
      expect_error_msg(
        {
          tg <- list(t = "x"); tg["t"] <- list(NULL)
          h(list(members = list(mem("dm", "d0922fc7", tags = tg))))
        },
        "null|absence is omission"))
check("empty-name tag key -> abort",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7",
                                  tags = stats::setNames(list("v"), ""))))),
        "non-empty name"))
check("duplicate tag key -> abort",
      expect_error_msg(
        h(list(members = list(mem("dm", "d0922fc7",
                                  tags = stats::setNames(list("a", "b"), c("t", "t")))))),
        "duplicate key"))
check("zero members -> abort",
      expect_error_msg(h(list(members = list())), "at least one member"))
check("missing members -> abort",
      expect_error_msg(h(list(tags = list(description = "x"))),
                       "at least one member"))
check("unexpected payload field (e.g. schema_version) -> abort",
      expect_error_msg(
        h(list(schema_version = "2", members = list(mem("dm", "d0922fc7")))),
        "unexpected field"))
check("unexpected member field -> abort rather than being dropped from identity",
      expect_error_msg(
        h(list(members = list(c(mem("dm", "d0922fc7"), list(note = "x"))))),
        "unexpected field"))
check("member with no id -> abort",
      expect_error_msg(h(list(members = list(list(tags = list(t = "x"))))),
                       "no id"))

# --- 8. write/read agreement across a real JSON round trip (optional dep) -------
# The hash domain is the PARSED payload, and the write path starts from an
# in-memory R object. Those two must agree, which is the one property that
# cannot be checked by inspection.
if (requireNamespace("jsonlite", quietly = TRUE)) {
  roundtrip_ok <- function(p) {
    f <- tempfile(fileext = ".json")
    on.exit(unlink(f), add = TRUE)
    jsonlite::write_json(p, f, auto_unbox = TRUE, pretty = TRUE)
    back <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    identical(h(p), h(back))
  }
  fixtures <- list(p1, tv_a, tv_dup, shape_scalar, shape_array, mo_a,
                   list(members = list(mem("dm", "d0922fc7",
                                           tags = list(t = s_nfd)))),
                   list(tags = list(description = jp),
                        members = list(mem("adsl", "7e21b0aa",
                                           tags = list(type = "output",
                                                       domain = c("safety", "efficacy"))))))
  check("in-memory hash == hash of the same payload written and parsed back",
        all(vapply(fixtures, roundtrip_ok, logical(1L))))
} else {
  cat("[skip] jsonlite not installed -- round-trip agreement check skipped\n")
}

# --- golden constants: record these, re-run everywhere, they must never change --
cat("\n== golden constants (portable across machines / R versions / OSes) ==\n")

# Primitive pins. These are the diagnostic half of the payload goldens below: a
# payload golden that disagrees across platforms says only "something differs",
# while these say WHICH stage differs.
cat("empty strset h(0x02)   :", .sv1_hex(.sv1_strset(character(0))), "\n")
cat("empty map    h(0x03)   :", .sv1_hex(.sv1_map(NULL)), "\n")
cat("str('a')               :", .sv1_hex(.sv1_str("a")), "\n")

# The golden payload exercises every construct at once: set-level tags, two
# members, a multi-valued tag, and a single-valued tag.
golden_payload <- list(
  tags = list(description = "ADaM datasets for STUDY-001"),
  members = list(
    list(id = mid("dm", "d0922fc7"), tags = list(type = "input")),
    list(id = mid("adsl", "7e21b0aa"),
         tags = list(type = "output", domain = c("safety", "efficacy")))
  )
)
cat("golden member (dm)     :", .sv1_hex(.sv1_member(golden_payload$members[[1]])), "\n")
cat("golden member (adsl)   :", .sv1_hex(.sv1_member(golden_payload$members[[2]])), "\n")
cat("golden set()           :", .sv1_hex(.sv1_set(golden_payload)), "\n")
cat("golden data_sha        :", h(golden_payload), "\n")

# A minimal single-member payload with no tags anywhere -- the degenerate end of
# the range, where every optional slot takes its empty encoding.
minimal_payload <- list(members = list(list(id = mid("dm", "d0922fc7"))))
cat("golden minimal data_sha:", h(minimal_payload), "\n")

cat(sprintf("\n== summary: %d passed, %d failed ==\n", .results$pass, .results$fail))
if (.results$fail > 0L) stop("datom-sv1 self-test FAILED", call. = FALSE)
