# Tests for the datom-sv1 set-content hash (R/hashable-set.R)
#
# The golden hex constants below FREEZE THE ENCODING. If one of them changes,
# the fix is never to update the constant: either the code drifted (fix the
# code) or the encoding was deliberately changed, which is a conscious
# `datom-sv2` bump with a new `hash_algo` identifier, not an edit.
#
# The three primitive pins were additionally cross-checked against an
# independent SHA-256 implementation (`printf '\x02' | shasum -a 256` and
# friends), so they assert the marker bytes really are what the specification
# says -- not merely that this implementation agrees with itself.


# --- fixtures -----------------------------------------------------------------

# A member `id` is a map of exactly four single strings.
mid <- function(name, version, project = "STUDY_001", kind = "table") {
  list(project = project, name = name, kind = kind, version = version)
}

mem <- function(name, version, tags = NULL, ...) {
  out <- list(id = mid(name, version, ...))
  if (!is.null(tags)) out$tags <- tags
  out
}

sv1 <- function(payload) .datom_canonical_set_hash(payload)

# Exercises every construct at once: set-level tags, two members, a
# multi-valued tag, a single-valued tag.
golden_payload <- list(
  tags = list(description = "ADaM datasets for STUDY-001"),
  members = list(
    list(id = mid("dm", "d0922fc7"), tags = list(type = "input")),
    list(
      id = mid("adsl", "7e21b0aa"),
      tags = list(type = "output", domain = c("safety", "efficacy"))
    )
  )
)

# The degenerate end of the range: one member, no tags anywhere, so every
# optional slot takes its empty encoding.
minimal_payload <- list(members = list(list(id = mid("dm", "d0922fc7"))))

# A real local-backend store, so the round-trip fixtures below go through the
# production write/read path (`jsonlite::toJSON(auto_unbox = TRUE)` out,
# `fromJSON(simplifyVector = FALSE)` back) rather than a hand-rolled
# approximation of it.
set_store_conn <- function(root) {
  structure(
    list(backend = "local", root = as.character(root), prefix = "proj",
         client = NULL),
    class = "datom_conn"
  )
}

# Hash a payload, store it, read it back, hash again. Returns both hashes so a
# failure shows which side moved.
store_roundtrip <- function(payload, conn, key = "s/x.json") {
  before <- sv1(payload)
  .datom_storage_write_json(conn, key, payload)
  parsed <- .datom_storage_read_json(conn, key)
  list(before = before, after = sv1(parsed), parsed = parsed)
}


# --- Golden constants ---------------------------------------------------------

test_that("primitive constants are pinned (AC13-E g, R2.17)", {
  # An encoder whose correctness rests on an upstream validation refusal breaks
  # silently the day that refusal is relaxed, so the empty cases are pinned even
  # though no writer emits them.
  expect_identical(
    .datom_sv1_hex(.datom_sv1_strset(character(0))),
    "dbc1b4c900ffe48d575b5da5c638040125f65db0fe3e24494b76ea986457d986"
  )
  # The parsed-JSON spelling of the same thing (`[]`) must agree with it.
  expect_identical(
    .datom_sv1_strset(list()),
    .datom_sv1_strset(character(0))
  )
  # h(0x02) with nothing after the marker -- i.e. the empty concatenation.
  expect_identical(
    .datom_sv1_strset(character(0)),
    digest::digest(as.raw(0x02L), algo = "sha256", serialize = FALSE,
                   raw = TRUE)
  )

  expect_identical(
    .datom_sv1_hex(.datom_sv1_map(NULL)),
    "084fed08b978af4d7d196a7446a86b58009e636b611db16211b65a9aadff29c5"
  )
  expect_identical(.datom_sv1_map(list()), .datom_sv1_map(NULL))

  expect_identical(
    .datom_sv1_hex(.datom_sv1_str("a")),
    "e3254ea61c09ead5a01d3bf07e946a561c6c2cd1c46b8ca1bfa8729d26a7d09f"
  )
})

test_that("golden set payload hashes are stable", {
  # Intermediates are pinned as well as the final value. A payload golden that
  # disagrees across platforms says only "something differs"; these say WHICH
  # stage differs, which is the difference between a quick fix and a bisect.
  expect_identical(
    .datom_sv1_hex(.datom_sv1_member(golden_payload$members[[1]])),
    "cf165469c22e3ab293119e1c93735a88371fb97b1a91e43f692ec3051c561134"
  )
  expect_identical(
    .datom_sv1_hex(.datom_sv1_member(golden_payload$members[[2]])),
    "3483ea9642dd7093fd03549576703050858a7b2b69a95eaea33e080d456efedf"
  )
  expect_identical(
    .datom_sv1_hex(.datom_sv1_set(golden_payload)),
    "33a30b1820154f38fa78ec7cbfcc82a6260d6bf59c022576bfeba7dcebd5a19d"
  )
  expect_identical(
    sv1(golden_payload),
    "e87c6e7be35a0198356e19a77d1acdd57e8f17f3f425320f3297206583d36c7a"
  )
  expect_identical(
    sv1(minimal_payload),
    "f434fcd31c1393721087859182cbdd9fad0372b65dc1dfd6b36d2cfe14c3e782"
  )
})


# --- AC13-P: write/read agreement, and what is / is not identity -------------

test_that("AC13-P: data_sha survives a real store round trip (R2.5, P15)", {
  root <- withr::local_tempdir()
  conn <- set_store_conn(root)

  fixtures <- list(
    golden_payload,
    minimal_payload,
    list(members = list(mem("adsl", "7e21b0aa",
                           tags = list(domain = c("safety", "efficacy"))))),
    # The one-element-array spelling survives the file as `["output"]`, so this
    # fixture proves the parsed and in-memory forms agree rather than merely
    # that they look alike.
    list(members = list(mem("adsl", "7e21b0aa",
                           tags = list(type = list("output"))))),
    list(tags = list(description = "x"),
         members = list(mem("dm", "d0922fc7"), mem("lb", "0f1e2d3c")))
  )

  for (i in seq_along(fixtures)) {
    rt <- store_roundtrip(fixtures[[i]], conn, sprintf("s/f%d.json", i))
    expect_identical(rt$after, rt$before)
  }
})

test_that("AC13-P: members[] parses as records, not a data frame (R2.5)", {
  # The one residual condition of write/read agreement. If a backend ever
  # simplified, `members` would come back as a data frame and every multi-member
  # hash would move, so this is asserted on the parsed object directly rather
  # than inferred from the hash matching.
  root <- withr::local_tempdir()
  conn <- set_store_conn(root)
  rt <- store_roundtrip(golden_payload, conn)

  expect_type(rt$parsed$members, "list")
  expect_false(is.data.frame(rt$parsed$members))
  expect_null(names(rt$parsed$members))
  expect_type(rt$parsed$members[[1]]$id, "list")
})

test_that("AC13-P (a, b): tag-value order and duplication are not identity", {
  root <- withr::local_tempdir()
  conn <- set_store_conn(root)

  a <- list(members = list(mem("adsl", "7e21b0aa",
                              tags = list(domain = c("safety", "efficacy")))))
  b <- list(members = list(mem("adsl", "7e21b0aa",
                              tags = list(domain = c("efficacy", "safety")))))
  expect_identical(sv1(a), sv1(b))

  dup <- list(members = list(mem("adsl", "7e21b0aa",
                                tags = list(domain = c("safety", "safety")))))
  one <- list(members = list(mem("adsl", "7e21b0aa",
                                tags = list(domain = "safety"))))
  expect_identical(sv1(dup), sv1(one))

  # Same relations after the payloads have been through storage.
  expect_identical(
    store_roundtrip(a, conn, "s/a.json")$after,
    store_roundtrip(b, conn, "s/b.json")$after
  )
})

test_that("AC13-P (c): member order is not identity (P3, P30)", {
  a <- list(members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa")))
  b <- list(members = list(mem("adsl", "7e21b0aa"), mem("dm", "d0922fc7")))
  expect_identical(sv1(a), sv1(b))

  # Three members, cycled: sorting, not "reverse also works by accident".
  c3 <- list(members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa"),
                            mem("lb", "0f1e2d3c")))
  c3_rot <- list(members = c3$members[c(2L, 3L, 1L)])
  expect_identical(sv1(c3), sv1(c3_rot))
})

test_that("AC13-P (d): a single string equals a one-element array (R2.13, P28)", {
  scalar <- list(members = list(mem("adsl", "7e21b0aa",
                                   tags = list(type = "output"))))
  array1 <- list(members = list(mem("adsl", "7e21b0aa",
                                   tags = list(type = list("output")))))
  vector1 <- list(members = list(mem("adsl", "7e21b0aa",
                                    tags = list(type = c("output")))))
  expect_identical(sv1(scalar), sv1(array1))
  expect_identical(sv1(scalar), sv1(vector1))
})

test_that("AC13-P (f): NFC and NFD are different tags (R2.16, P33)", {
  # `\u` escapes, not literal bytes: these fixtures ship in tests/ and
  # `R CMD check --as-cran` must stay at zero warnings.
  nfc <- "na\u00efve"           # precomposed i-diaeresis
  nfd <- "nai\u0308ve"          # i + combining diaeresis
  expect_false(identical(nfc, nfd))

  value_nfc <- list(members = list(mem("dm", "d0922fc7", tags = list(t = nfc))))
  value_nfd <- list(members = list(mem("dm", "d0922fc7", tags = list(t = nfd))))
  expect_false(identical(sv1(value_nfc), sv1(value_nfd)))

  key_nfc <- list(members = list(mem("dm", "d0922fc7",
                                    tags = stats::setNames(list("v"), nfc))))
  key_nfd <- list(members = list(mem("dm", "d0922fc7",
                                    tags = stats::setNames(list("v"), nfd))))
  expect_false(identical(sv1(key_nfc), sv1(key_nfd)))
})

test_that("AC13-E (e): a duplicated member hashes equal to one entry (R2.14)", {
  # Called against the encoder, not through the write path: the write path tidies
  # this away before the encoder sees it, so the property is only observable
  # here.
  twice <- list(members = list(mem("dm", "d0922fc7"), mem("dm", "d0922fc7")))
  once <- list(members = list(mem("dm", "d0922fc7")))
  expect_identical(sv1(twice), sv1(once))

  # Duplication of a member that carries tags, too.
  tagged <- mem("adsl", "7e21b0aa", tags = list(type = "output"))
  expect_identical(
    sv1(list(members = list(tagged, tagged))),
    sv1(list(members = list(tagged)))
  )
})


# --- AC3: what IS identity ---------------------------------------------------

test_that("AC3: advancing a member version mints a new data_sha (P4)", {
  before <- list(members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa")))
  after <- list(members = list(mem("dm", "d0922fc7"), mem("adsl", "ffffffff")))
  expect_false(identical(sv1(before), sv1(after)))
})

test_that("every id field participates in identity", {
  base <- list(members = list(mem("dm", "d0922fc7")))
  variants <- list(
    name = list(members = list(mem("lb", "d0922fc7"))),
    version = list(members = list(mem("dm", "aaaaaaaa"))),
    project = list(members = list(mem("dm", "d0922fc7", project = "STUDY_002"))),
    kind = list(members = list(mem("dm", "d0922fc7", kind = "set")))
  )
  for (field in names(variants)) {
    expect_false(identical(sv1(base), sv1(variants[[field]])),
                 info = paste("id field not in identity:", field))
  }
})

test_that("the hash covers the WHOLE payload, tags included (R2.6, AC2 converse)", {
  # A tag or description edit mints a new version. Intended behavior: a set is
  # citable, so "same citation, different tags" would lie to the consumer.
  no_tag <- list(members = list(mem("dm", "d0922fc7")))
  tagged <- list(members = list(mem("dm", "d0922fc7",
                                   tags = list(type = "input"))))
  edited <- list(members = list(mem("dm", "d0922fc7",
                                   tags = list(type = "output"))))
  expect_false(identical(sv1(no_tag), sv1(tagged)))
  expect_false(identical(sv1(tagged), sv1(edited)))

  desc_a <- list(tags = list(description = "a"),
                 members = list(mem("dm", "d0922fc7")))
  desc_b <- list(tags = list(description = "b"),
                 members = list(mem("dm", "d0922fc7")))
  expect_false(identical(sv1(desc_a), sv1(desc_b)))
  expect_false(identical(sv1(desc_a), sv1(no_tag)))

  # An added member is a content change.
  expect_false(identical(
    sv1(no_tag),
    sv1(list(members = list(mem("dm", "d0922fc7"), mem("lb", "0f1e2d3c"))))
  ))
})

test_that("the same name at two versions is two members (R2.14a)", {
  both <- list(members = list(mem("adsl", "a1b2c3d4"), mem("adsl", "f9e8d7c6")))
  expect_false(identical(sv1(both),
                         sv1(list(members = list(mem("adsl", "a1b2c3d4"))))))
  expect_false(identical(sv1(both),
                         sv1(list(members = list(mem("adsl", "f9e8d7c6"))))))
})


# --- AC5: empty set refused, single member legal ------------------------------

test_that("AC5: a zero-member payload is refused (R2.8)", {
  # Mirrors `.datom_canonical_hash()`'s refusal of a zero-row / zero-column
  # table. The refusal is the tested behavior, not a documented maybe.
  expect_error(sv1(list(members = list())), "member")
  expect_error(sv1(list(tags = list(description = "x"))), "member")
  expect_error(sv1(list()), "member")
})

test_that("AC5: a single-member set is legal and hashes normally", {
  expect_match(sv1(minimal_payload), "^[0-9a-f]{64}$")
})


# --- Determinism and key-order independence (P1, P2) --------------------------

test_that("P1/P2: the hash is deterministic and key-insertion-order free", {
  expect_identical(sv1(golden_payload), sv1(golden_payload))

  reordered <- list(
    members = list(
      list(tags = list(type = "input"), id = mid("dm", "d0922fc7")),
      list(
        tags = list(domain = c("efficacy", "safety"), type = "output"),
        id = list(version = "7e21b0aa", kind = "table",
                  name = "adsl", project = "STUDY_001")
      )
    ),
    tags = list(description = "ADaM datasets for STUDY-001")
  )
  expect_identical(sv1(reordered), sv1(golden_payload))
})


# --- Domain separation and framing (P5, P6) ----------------------------------

test_that("P5: each constructor carries its own marker byte", {
  # A collision across two positions must reduce to a SHA-256 collision, so the
  # same text at different positions must not produce the same digest.
  digests <- c(
    .datom_sv1_hex(.datom_sv1_str("a")),
    .datom_sv1_hex(.datom_sv1_strset("a")),
    .datom_sv1_hex(.datom_sv1_map(list(a = "a"))),
    .datom_sv1_hex(.datom_sv1_member(list(id = list(a = "a")))),
    .datom_sv1_hex(.datom_sv1_set(list(members = list(list(id = list(a = "a"))))))
  )
  expect_length(unique(digests), length(digests))

  # The marker bytes are the mechanism, asserted directly.
  expect_identical(
    .datom_sv1_str("a"),
    digest::digest(c(as.raw(0x01L), charToRaw("a")), algo = "sha256",
                   serialize = FALSE, raw = TRUE)
  )
})

test_that("P5: swapping content between the id and tags slots cannot collide", {
  a <- list(id = list(k = "v"), tags = list(x = "y"))
  b <- list(id = list(x = "y"), tags = list(k = "v"))
  expect_false(identical(.datom_sv1_member(a), .datom_sv1_member(b)))
})

test_that("P6: fixed-width framing makes concatenation unambiguous", {
  # `["a","b"]` is h("a")||h("b") -- 64 bytes -- and cannot collide with `["ab"]`
  # at 32. This is why sv1 needs no length prefixes and no numeric primitive.
  expect_false(identical(.datom_sv1_strset(c("a", "b")),
                         .datom_sv1_strset("ab")))
  expect_false(identical(.datom_sv1_map(list(a = "b")),
                         .datom_sv1_map(list(ab = character(0)))))
  expect_length(.datom_sv1_str("a"), 32L)
  expect_length(.datom_sv1_strset(c("a", "b")), 32L)
  expect_length(.datom_sv1_map(golden_payload$members[[1]]$id), 32L)
})


# --- The payload grammar is closed by shape (I24, P28, P31) ------------------

test_that("P28: a non-text tag value is not encodable (R2.11)", {
  offenders <- list(
    number = 500,
    integer = 5L,
    logical = TRUE,
    factor = factor("a"),
    nested = list(list("a")),
    fn = mean
  )
  for (label in names(offenders)) {
    payload <- list(members = list(
      mem("dm", "d0922fc7", tags = list(t = offenders[[label]]))
    ))
    expect_error(sv1(payload), "text", info = label)
  }
})

test_that("P28: NA is not encodable, and the message says to omit (R2.7)", {
  # The refusal is the golden case: goldens carry no `NA` encoding, because
  # there is none to carry.
  expect_error(
    sv1(list(members = list(mem("dm", "d0922fc7", tags = list(t = NA))))),
    "encodable"
  )
  expect_error(
    sv1(list(members = list(mem("dm", "d0922fc7",
                               tags = list(t = NA_character_))))),
    "encodable"
  )
  expect_error(
    sv1(list(members = list(mem("dm", "d0922fc7",
                               tags = list(t = c("a", NA)))))),
    "encodable"
  )
  # An NA in an `id` field is refused by the same primitive.
  expect_error(
    sv1(list(members = list(list(id = mid("dm", NA_character_))))),
    "encodable"
  )
})

test_that("P28: null has no marker -- absence is omission (R2.7)", {
  tags_with_null <- list(t = "x")
  tags_with_null["t"] <- list(NULL)
  expect_error(
    sv1(list(members = list(mem("dm", "d0922fc7", tags = tags_with_null)))),
    "null|omission"
  )
})

test_that("P31: there is no object-valued position, so no type dispatch", {
  # A map value is always a string set. A nested object in that position is not
  # dispatched to some other encoder -- it is refused, which is what makes the
  # "no unhandled runtime type" claim structural rather than aspirational.
  #
  # This is also the sharpest case in the file. Element-wise, `list(b = "c")` and
  # `list("c")` are the same thing, so an encoder that only checked elements
  # would read `{"a": {"b": "c"}}` as `{"a": ["c"]}` -- the inner key would sit
  # outside identity and two different payloads would share one data_sha and one
  # storage address. Caught by this test while writing it.
  expect_error(.datom_sv1_map(list(a = list(b = "c"))), "not an object")
  expect_false(identical(
    tryCatch(.datom_sv1_map(list(a = list(b = "c"))), error = function(e) "refused"),
    .datom_sv1_map(list(a = list("c")))
  ))
  expect_error(
    sv1(list(members = list(mem("dm", "d0922fc7",
                               tags = list(t = list(inner = "a")))))),
    "not an object"
  )
})

test_that("P8: container facts cannot enter set identity (R2.9)", {
  # `schema_version` describes the format, not the content. In identity it would
  # re-mint every set on a format bump, so the payload root refuses it outright
  # rather than silently ignoring it.
  expect_error(
    sv1(c(list(schema_version = "2"), minimal_payload)),
    "unexpected"
  )
  expect_error(
    sv1(c(list(document_sha = "abc"), minimal_payload)),
    "unexpected"
  )
})

test_that("an unexpected member field aborts rather than leaving identity", {
  # A silently ignored field would be payload content outside identity: two
  # different payloads would share one data_sha and one storage address.
  extra <- c(mem("dm", "d0922fc7"), list(note = "hello"))
  expect_error(sv1(list(members = list(extra))), "unexpected")
})

test_that("structural malformations are refused with a usable message", {
  expect_error(sv1(list(members = list(list(tags = list(t = "x"))))), "id")
  expect_error(sv1(list(members = list("dm"))), "named list")
  expect_error(sv1(list(members = list(a = mem("dm", "d0922fc7")))), "unnamed")
  expect_error(sv1("dm"), "list")
  expect_error(
    .datom_sv1_map(stats::setNames(list("v"), "")),
    "non-empty name"
  )
  expect_error(
    .datom_sv1_map(stats::setNames(list("a", "b"), c("t", "t"))),
    "duplicate"
  )
})


# --- Reference parity (P12) --------------------------------------------------

test_that("P12: package hash matches the standalone sv1 reference", {
  candidates <- c(
    file.path("dev", "datom_sv1_reference.R"),
    testthat::test_path("..", "..", "dev", "datom_sv1_reference.R"),
    testthat::test_path("dev", "datom_sv1_reference.R")
  )
  hit <- candidates[file.exists(candidates)]
  skip_if(length(hit) == 0, "reference script absent (e.g. CRAN, dev/ Rbuildignored)")
  ref_env <- new.env()
  invisible(utils::capture.output(
    suppressMessages(sys.source(hit[[1]], envir = ref_env))
  ))
  ref <- ref_env$datom_canonical_set_hash

  fixtures <- list(
    golden_payload,
    minimal_payload,
    list(members = list(mem("dm", "d0922fc7"), mem("adsl", "7e21b0aa"))),
    list(members = list(mem("adsl", "7e21b0aa",
                           tags = list(domain = c("safety", "efficacy"),
                                       type = list("output"))))),
    list(tags = list(description = "\u65e5\u672c\u8a9e"),
         members = list(mem("dm", "d0922fc7",
                           tags = list(t = "na\u00efve")))),
    list(members = list(mem("dm", "d0922fc7", project = "OTHER",
                           kind = "set")))
  )
  for (fx in fixtures) {
    expect_identical(sv1(fx), ref(fx))
  }

  # The primitives must agree too, not only the composed hash -- a divergence
  # inside one of them could still cancel out at the top for some fixture.
  expect_identical(.datom_sv1_strset(character(0)),
                   ref_env$.sv1_strset(character(0)))
  expect_identical(.datom_sv1_map(NULL), ref_env$.sv1_map(NULL))
  expect_identical(.datom_sv1_str("a"), ref_env$.sv1_str("a"))
})
