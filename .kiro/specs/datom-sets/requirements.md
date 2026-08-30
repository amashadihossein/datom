# Requirements -- datom sets (second artifact kind)

**Source issue**: [#89 -- Add a second artifact kind: versioned, citable sets of datoms](https://github.com/amashadihossein/datom/issues/89)
**Branch**: `spec/datom-sets` (cut from `dev`; PRs into `dev` per the CRAN submission freeze -- see `dev/README.md` "Branching During CRAN Submission")
**Prerequisite**: #95 / PR #96 -- corrected the stale pre-release paragraph in
`.github/copilot-instructions.md`. Landed on `dev` before this branch was cut, deliberately
outside this spec's history. Without it the instructions file contradicts this spec's
compatibility reasoning.

---

## 1. Goal

Give datom a **second artifact kind** alongside tables: a **set** -- a versioned, citable,
content-addressed collection of pointers to existing datoms. Same repo, same version history,
same content addressing, same governance and ref resolution as a table. Different payload: a
JSON document of pointers instead of a parquet file.

datom today versions individual tables and has no way to version a *curated collection* of
tables as a single citable thing.

## 2. Motivation

A curated collection is what a data product is. The downstream build package (new; replaces the
`pins`-based `dpbuild`) needs to publish one: a document of pointers to existing datoms, plus
tags and navigation metadata, versioned and immutable so a consumer can pin it, and addressable
so another collection can include it.

Three things block that today:

1. **A collection is a tree, not a flat table**, so it cannot be a datom table. `datom-cv1`
   refuses list and exotic columns by design (`R/hashable.R`, `.datom_canonical_hash()`).
2. **No byte/JSON put-get on the public storage surface.** The Storage Extension API exports
   `datom_storage_list()` / `datom_storage_copy()` / `datom_storage_verify()` /
   `datom_storage_delete_prefix()` (`R/storage.R`) but no JSON read/write. The internals already
   exist (`.datom_storage_read_json()` / `.datom_storage_write_json()`,
   `R/utils-storage.R:66,83`) -- they are simply unexported.
   **Note, 2026-08-18: the write half of this motivation is retired.** As #89 stated it, the gap
   was "a downstream package cannot write its own document into datom's namespace" -- and the
   document in question was a set, which `datom_write_set()` now writes as a first-class artifact.
   A general-purpose JSON write is therefore no longer needed by anything, and exporting one would
   contradict the Authority Principle in `dev/datomanager_scope.md` (data-side writes route
   through purpose-built datom verbs). Only the **read** export survives this motivation; see
   R12.4 and the retirement of R12.4a.
3. **Building it outside datom duplicates** version history, content addressing, dedup, ref
   resolution, and governance in a second package.

### The load-bearing justification is composability, not code reuse

Duplicated machinery could be answered with "copy 200 lines into the build package." What
cannot be answered that way: **a product built outside datom is a dead end.** It can never be a
member of another product, because membership requires living in the addressing scheme.

### Who benefits

| Beneficiary | Need |
|---|---|
| The build package | Publish versioned, immutable, citable products |
| Storage-only consumers | Resolve a pinned product without git access |
| Any team composing one product from another | Reference a product as a member of another product |

## 3. Compatibility posture

datom is `lifecycle: experimental`, 0.1.0 is under CRAN review, and there are no reverse
dependencies. The distinction that governs a change is **failure mode, not compatibility**:

| Change | Verdict at experimental |
|---|---|
| Breaks loudly -- user upgrades, gets an error, fixes code | Fine |
| Silently disables an integrity check | **Not acceptable at any stage** |

This is the operative rule in `.github/copilot-instructions.md` (as corrected by #95). It is
what makes the `tables` -> `artifacts` rename acceptable while `parquet_sha` -> some
kind-neutral name is not. See design.md section "Compatibility analysis" for the full
derivation.

---

## 4. Functional requirements

Additive unless marked **[BREAKING]**.

### R1 -- Set artifact kind

- **R1.1** Metadata carries `kind: "table" | "set"`. `kind` is **semantic** -- it participates
  in `metadata_sha`.
- **R1.2** `kind` is a new field, **not** a new `table_type` value. `table_type`
  (`imported` / `derived`) is a *provenance* axis, not a *kind* axis, and is validated to
  exactly those two values (`.datom_build_metadata()`, `R/read_write.R`).
- **R1.3** A set's `metadata.json` collapses to **exactly these seven fields**: `kind`,
  `schema_version`, `data_sha`, `hash_algo`, `document_sha`, `created_at`, `datom_version`. No
  `parents`, no `source_lineage`, no `table_type`, no `nrow` / `ncol` / `colnames` --
  **omitted, not nulled** (mirroring how `.datom_build_metadata()` already conditionally assigns
  `original_file_sha`).
- **R1.4** Also **absent from a set's metadata**, and the reason for each:
  - `size_bytes` -- nothing consumes it. `summary$total_size_bytes` is tables-only by R8.3, and
    the manifest set entry carries `member_count` instead. A field no counter reads is a field
    that will silently rot.
  - `custom` -- redundant by design. Tags live **in the payload**
    (R6.2), so a second user-metadata channel on a set would create two places to put the same
    thing and two places to look for it. `datom_write_set()` therefore has no `metadata =`
    parameter.

**Acceptance**: a written set's metadata has exactly the seven keys of R1.3 -- asserted with
`setequal(names(meta), <the seven>)`, not merely by checking absences, so an added field fails
the test.

### R2 -- Canonical set-content hash (`datom-sv1`)

- **R2.1** `data_sha` for a set is a canonical hash over the set's **semantic content**, not
  over emitted bytes. Carries the #72 lesson forward: a JSON/YAML emitter drifts across
  versions (key order, quoting, wrapping) the way `arrow` drifted for parquet.
- **R2.2** The basis is **not** `datom-cv1`. cv1 is table-shaped and binary-framed
  (`sha256("datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digests))`); `nrow` / `ncol`
  / per-column digests do not generalize to a tree. sv1 borrows cv1's *approach* -- per-element digests
  hashed together, with fixed byte encodings and no serializer in the identity path -- applied to a
  tree instead of a table. It is **not** a walk that dispatches on runtime type; see R2.10.
- **R2.3** Declared under its own `hash_algo` identifier: `datom-sv1`. `hash_algo` already
  exists and is correctly in the semantic set (`R/utils-sha.R`: "a new hash algorithm
  legitimately defines a new version").
- **R2.4** Ships with a standalone reference implementation, golden vectors, and a
  cross-architecture parity workflow mirroring `dev/datom_cv1_reference.R` and
  `.github/workflows/cv1-reference-parity.yaml`.
- **R2.5 -- write/read agreement (hard constraint; unchanged in force, restated in mechanism).**
  The hash is **defined on the parsed-JSON data model**, and the write path -- which necessarily
  starts from an in-memory R object -- MUST agree with it. Concretely: `data_sha` computed at write
  time from the in-memory payload MUST equal `data_sha` recomputed at read time from the same
  payload after it has been stored and parsed back. (This does *not* mean the write path serializes
  first; see the mechanism below.) R cannot distinguish a scalar
  from a length-1 vector, and a JSON round trip mutates types (demonstrated in design.md
  section 7: `NA_real_` becomes the **string** `"NA"`; doubles return as integers;
  `NA_character_` becomes `null`).
  **Mechanism, per Q5 (R2.10):** an earlier draft satisfied this by normalizing through a
  serialize -> parse cycle. That is superseded -- there is now **no serializer in the identity
  path at all**, and every mutation is eliminated at the source rather than handled, so agreement
  holds by construction (design.md section 7.3):
  - **numbers and booleans**: not in the payload at all (R2.11), so integer-vs-double and boolean
    encoding cannot arise
  - **`NA` / `null`**: `NA` is an error and absence is omission (R2.7), so neither mutation arises
  - **scalar versus length-1 array**: now **immaterial** -- a single string and a one-element set
    hash identically (R2.13), so this stopped being a rule and became a non-question
  - **residual condition, scoped to structure not leaves**: the read path must parse with
    **`simplifyVector = FALSE`** so `members[]` stays a list of records rather than collapsing to a
    data frame. Both storage backends already do this deliberately (`R/utils-local.R:110`,
    `R/utils-s3.R:209`). Leaf-level simplification no longer matters, because leaves are
    order-and-shape insensitive.
- **R2.6 -- Q1: the hash covers the WHOLE payload.** `data_sha` is computed over the entire
  semantic payload -- members **and** their tags (including descriptions carried as tags) -- not the member list
  alone. A set exists to be **citable**, and "same citation, different tags" would be a lie to the
  consumer. **A tag or description edit therefore mints a new version. That is intended behavior,
  not an accident to engineer away.**
- **R2.7 -- Q2: absence is omission; `NA` is an error.** A set payload has no data cells, so `NA`
  could only enter through optional fields. datom's existing **"omitted, not nulled"** convention
  (`.datom_build_metadata()`, `R/read_write.R:302-305`) is therefore adopted as the canonical
  form: an absent field **does not exist** in the payload, and `null` / `NA` / `""` are never
  representations of absence. Consequence for the encoder: a literal `NA` reaching sv1 **aborts**
  with "not encodable -- omit the field instead". Golden vectors include the **refusal** case, not
  an `NA` encoding. This is where sv1 legitimately diverges from cv1, which needs an NA mask byte
  precisely because table cells can be missing.
- **R2.8 -- Q3: an empty set is refused.** `datom_write_set()` with zero members aborts, mirroring
  cv1's refusal of zero-row / zero-column tables (`R/utils-sha.R:310-312`). Utility is marginal --
  the build package simply does not write the set until its first output exists -- and an empty
  citable product is semantically murky. Cheap to relax later, awkward to retract.
- **R2.9 -- Q4: `schema_version` does not enter the payload or the hash.** It describes the
  **container format**, not the content. If it entered identity, a format bump would re-mint every
  set with unchanged members -- the same failure the `volatile` list exists to prevent
  (`R/utils-sha.R:444-447`). It stays a metadata field (R1.3) outside the hash domain.
- **R2.10 -- Q5: emitter-free structural hash, as a hash-of-hashes.** No serializer is in the
  identity path. sv1 is **three primitive encoders plus two shape rules**, not a runtime
  type-dispatch walk. This mirrors cv1's existing construction (per-column digests, then hash their
  concatenation), so both references share one house pattern.

  ```
  h(x) = sha256(x)

  str(s)     = h( 0x01 || utf8(s) )
  strset(v)  = h( 0x02 || concat( str(e) for e in sort(unique(v), method = "radix") ) )
  map(m)     = h( 0x03 || concat( str(k) || strset(m[k])
                                  for k in sort(keys(m), method = "radix") ) )

  member(x)  = h( 0x04 || map(x.id) || map(x.tags) )
  set(p)     = h( 0x05 || map(p.tags) || concat( sort(unique( member(m) for m in p.members ),
                                                 method = "radix") ) )

  data_sha   = h( 0x06 || utf8("datom-sv1") || set(payload) )
  ```

  Member digests sort as **lowercase hex**, `method = "radix"`, and are emitted as raw bytes.
  Stating the collation is not pedantry -- it is the same locale-independence requirement `strset`
  and `map` carry, and `.datom_compute_metadata_sha()` (`R/utils-sha.R:502`) sets the house
  precedent.

  - **No runtime type dispatch, therefore no possible gap.** Every position's shape is known from
    *where it sits*, so the encoder never asks "what type is this?" and cannot have an unhandled
    answer. This is what closes F-A (R2.11).
  - **Every collection is sorted and deduped -- no exceptions, no carve-out.** Tag keys, tag values
    and `members` are all sorted; tag values and members are also **deduped**. So "is this position
    ordered?" has one answer everywhere and is never a judgment call. This is what closes F-B
    (R2.12). An earlier draft made `members` the single unsorted position; **retired by D2** -- see
    R2.12 for the three arguments.
  - **`id` is encoded with `map`, not positionally.** Adding a fifth id field later is then just
    another key -- no positional convention to maintain and no absent-versus-empty question -- and
    one encoder serves both `id` and `tags`. Id values are single strings, encoded as one-element
    strsets; the encoder stays out of validation's job, which separately enforces "id has exactly
    these four keys, each single-valued".
  - **Framing is free, so there are no length prefixes.** Every intermediate is a fixed 32 bytes,
    so concatenation is unambiguous: `["a","b"]` is `h("a")||h("b")` (64 bytes) and cannot collide
    with `["ab"]` (32 bytes). Consequence: **`f64le` disappears from sv1 entirely** -- sv1 shares no
    numeric primitive with cv1.
  - **Pinned edge cases**: absent `tags` and `tags: {}` encode identically (`h(0x03)` over an empty
    concat) -- writers never emit `{}` per R2.7, but the encoder must not depend on that; duplicate
    tag values are not identity (`["a","a"]` is `["a"]`); `radix` sort throughout for locale
    independence, matching `.datom_compute_metadata_sha()`'s existing rationale; a **zero-member set
    is still refused** (R2.8).
  - **An empty tag value is refused by validation**, not encoded. `domain: character(0)` means "no
    labels", which per R2.7 is spelled by **omitting the key**. (The encoder would produce
    `h(0x02)` for it, so this is a validation rule keeping one spelling per fact, not a
    correctness fix.)

  `jsonlite`, or anything else, remains free to format the **stored file** however it likes,
  because stored-byte integrity is `document_sha`'s job -- a separate hash over actual bytes.
  **Identity and storage integrity never share a dependency.** Golden vectors and
  `dev/datom_sv1_reference.R` are written against **this specification**, not against any emitter's
  output.
- **R2.11 -- the payload is closed by its FIXED SHAPE, not by a value grammar.** An earlier draft
  stated the closure as a grammar (`value ::= string | [string, ...] | object`), which **could not
  produce `members[]`** -- an array of objects had no production, while R2.12 required one. Two
  requirements that could not both be true, and the ambiguity would have been frozen into the
  golden vectors. The closure is therefore stated as the shape itself (R2.12), with these rules on
  leaves:
  - every leaf is a **UTF-8 string**, or an unordered set of them; **no `NA`** (R2.7)
  - **no numbers, no booleans, no `null`**, and no nesting beyond R2.12's shape
  - a non-conforming value -- a number, logical, factor, function, nested list, or `NA` -- **aborts**
    naming the offending key and the allowed types (AC27)

  Rationale unchanged: tags replace folder-style organisation and folder labels are text. Admitting
  numbers or booleans would buy nothing datom uses while costing encoder rules and a wider golden
  matrix. A numeric tag is written `"500"` and parsed downstream, exactly as a folder name would be.
- **R2.12 -- the payload shape, with `id` split from `tags`.** The payload holds exactly two kinds
  of content: a **well-specified reference record** (fixed keys, all single strings) and an **open
  tag map**. That split is structural rather than four fixed fields sitting loose beside a nested
  map:

  ```json
  {
    "tags": { "description": "ADaM datasets for STUDY-001" },
    "members": [
      { "id":   { "project": "STUDY_001", "name": "dm",   "kind": "table", "version": "d0922fc7" },
        "tags": { "type": "input" } },
      { "id":   { "project": "STUDY_001", "name": "adsl", "kind": "table", "version": "7e21b0aa" },
        "tags": { "type": "output", "domain": ["safety", "efficacy"] } }
    ]
  }
  ```

  Tags stay **per-member** (R4.6): `dp$output$adsl` downstream comes from `type: "output"` on
  `adsl`'s entry.

  **Ordering and duplication: nothing in the payload is ordered.** One rule, no exceptions, no
  per-position judgment call:

  | Position | Order significant? | Duplicates significant? |
  |---|---|---|
  | `members` | **no** -- sorted by `member()` digest | **no** -- deduped (and refused by validation, R2.14) |
  | tag **keys** | no -- radix-normalised | n/a (keys are unique) |
  | tag **values** | **no** -- radix-sorted | **no** -- deduped |

  Tag values are unordered because a multi-valued tag models *simultaneous folder membership*
  (R4.6), which has no order. `domain: ["safety","efficacy"]` and `domain: ["efficacy","safety"]`
  are the same fact, and must not mint a new citable version. This does not weaken Q1: a tag
  *edit* minting a version is intended; a *reorder* is not an edit.

  **`members` is unordered for the same reason, and that reverses an earlier draft** which made
  member order identity on the grounds that it is "curatorial -- the user sees and controls it".
  Three arguments retired it, any one sufficient:

  1. **It contradicted R4.7.** Arrangement is presentation, not content -- that is precisely why no
     hierarchy is stored. Member order is arrangement. A consumer wanting a display order uses a
     tag (`order: "3"`), like any other projection.
  2. **It contradicted this requirement's own reasoning.** The argument that killed tag-value
     ordering -- a semantically null rearrangement must not mint a citable version -- applies
     verbatim to members. Applying it to one collection and not the other was inconsistent.
  3. **The decisive practical one: the expected producer is a script.** A build package emits
     `members[]` by iterating a list assembled in code. An insertion-order refactor would then mint
     a new product version with byte-identical content -- a tool's incidental ordering becoming
     identity, which is the #72 failure class this spec exists downstream of.

  What order-as-identity was thought to buy does not survive inspection: sorting costs one `sort()`
  over fixed-width 32-byte digests (deterministic and locale-free), and duplicate members are
  refused by validation either way (R2.14). The encoding also gets *simpler* -- design.md 7.2 no
  longer needs its "`members` is the only unsorted `concat`" carve-out.
- **R2.14 -- TIDY FIRST, THEN VALIDATE WHAT REMAINS. Tidy anything that loses no information;
  refuse only what cannot be handled without guessing intent.** This reverses an earlier draft that
  refused six spellings, several of which were pure formatting nobody could reasonably care about.
  The ordering is load-bearing in both directions: tidying first clears the benign cases so
  validation sees only genuine ambiguity, and validating first would make the tidy rules dead code.

  **Tidied silently** (R2.15 performs these; none is an error, and none is an encoder gap -- the
  encoder handles all of them unambiguously):

  | Spelling | Tidied to | Nothing is lost because |
  |---|---|---|
  | tag values out of order | sorted | a multi-valued tag is a set (R2.12) |
  | `["safety","safety"]` | `["safety"]` | duplication is not identity |
  | `["output"]` / `"output"` | `"output"` | both mean one label (R2.13) |
  | members out of order | sorted | order is not identity (R2.12) |
  | **exact duplicate member** -- same `id` *and* same `tags` | one entry | it states one fact twice |
  | `domain = character(0)` | **key dropped** | "no labels" *is* omitting the key (R2.7) |

  **Refused** (each would require datom to guess what the caller meant):

  | Spelling | Why it cannot be tidied |
  |---|---|
  | a number, logical, factor, function, nested list (R2.11) | coercing `500` to text guesses the format -- `"500"`, `"500.0"`, `"5e2"` |
  | `NA` (R2.7) | has no text meaning at all |
  | `domain = ""` | a label with no name. Almost always a real bug (`paste0()` over an empty variable), so refusing is how the caller finds it; dropping it would guess. R2.7 already says `""` never represents *absence* -- this settles the separate question of whether it is a legal *label*. |
  | **same `id` listed twice with DIFFERENT `tags`** | see below -- the case that falls between the other rules |
  | zero members (R2.8) | already decided, Q3 |

  **The duplicate-member case has two halves, and only one is redundant.** `set()` dedupes by
  `member()` digest, and the digest covers tags, so:

  - **Same `id`, same `tags`** -> identical digests -> tidied to one entry. Harmless.
  - **Same `id`, different `tags`** -> *different* digests, so **dedup does not catch it** and both
    entries survive. The payload then holds one member twice with conflicting labels, and a consumer
    projecting tags into a folder view finds `adsl` in both `input` and `output`. That is one fact
    with two spellings -- the intended form is a single entry with a multi-valued tag,
    `type: ["input","output"]`, which the model already supports (R4.6). **Refused**, because both
    ways to tidy it guess: merging the tags is right if the caller meant both categories and
    nonsense if two code paths disagreed, and picking one entry is arbitrary. The refusal message
    names the member and points at the multi-valued form.

- **R2.14a -- the same NAME at DIFFERENT VERSIONS is legal, and is not a duplicate.** `id` is
  `{project, name, kind, version}`, so `adsl@a1b2` and `adsl@f9e8` are **different members** with
  different content. A product carrying a current table alongside a locked baseline for comparison is
  atypical but entirely sensible, and nothing about it is redundant. **The duplicate check therefore
  keys on the FULL `id`, never on `project`+`name`.** Recorded as a requirement with a dedicated test
  (AC27) precisely because `project`+`name` looks like the natural key until case B is remembered --
  the first reader to "tighten" the check would break a legitimate use silently.

  Two consequences:

  - **The R2.15 file sort key must include `version`** -- otherwise two versions of one name have no
    defined relative order and the canonical byte form is not well defined.
  - **Consumers must disambiguate them by tag.** `dp$output$adsl` is ambiguous when both versions are
    tagged `output`; the caller distinguishes them with something like
    `release: "current"` / `release: "baseline"`. That is consumer-side under the projection model
    (R4.7), so datom takes no position and adds no warning -- a warning that fires on legitimate use
    becomes noise.
  - **Note for a future reader-side diff** (not in this spec; diffing is settled as
    no-schema-change): keying members on `project/name` alone is insufficient, and keying on
    `project/name/version` makes an ordinary version bump read as a delete plus an insert rather than
    a change. A diff should key on `project/name` where it is unique in both payloads and fall back
    to including `version` where it is not.
- **R2.13 -- a single string is identical to a one-element set.** `type: "output"` and
  `type: ["output"]` hash **equal**, because every map value passes through `strset`. Both spellings
  mean *one label named output*, so making them differ would mint a new citable version over a
  purely syntactic authoring choice -- the same objection that rules out tag-value ordering.
  This **reverses** an earlier AC13 fixture that required them to differ.
- **R2.15 -- the payload is canonicalized BEFORE the local write, so one content has exactly one
  byte spelling.** Hash-level insensitivity (R2.12, R2.13) means several payload spellings share one
  `data_sha`. Since `data_sha` is also the storage address and `document_sha` hashes the stored
  *bytes*, two spellings at one address would make `document_sha` unverifiable (R7.5). Canonicalizing
  at the source removes the ambiguity rather than managing it. `datom_write_set()` MUST normalize
  before it writes `{name}/set.json`, in this order:

  | Step | Rule |
  |---|---|
  | 1 | **map keys** radix-sorted (set-level `tags`, each member's `id` and `tags`) |
  | 2 | **tag values** radix-sorted, then deduped; a key whose value is `character(0)` is **dropped** (R2.14) |
  | 3 | **single values unboxed** -- a one-element value is written as a bare string, arrays only for 2+ |
  | 4 | **members** deduped by `member()` digest, then sorted by **`project` \|\| `name` \|\| `version`**, radix |

  Step 3's direction is chosen, not arbitrary: `jsonlite::write_json(auto_unbox = TRUE)` is already
  the house default across datom's metadata writers, so unboxing is the free option while
  always-array would need explicit boxing; and the unboxed form reads better in the `git diff`
  R6.1a exists to preserve.

  **Step 4 uses a different sort key from the hash, deliberately.** The hash sorts member digests
  (R2.10); the *file* sorts by `project` || `name` || `version`. Both are fully deterministic, so
  "one content, one byte spelling" holds either way -- but they serve different goals:

  | | Sort key | Why |
  |---|---|---|
  | **hash** | `member()` digest | self-contained: the encoder never has to know what an `id` looks like, which is what keeps "a fifth id field is just another key" true (R2.10) |
  | **file** | `project` \|\| `name` \|\| `version` | stable under edits, which is what `git diff` needs |

  Digest order in the file would undo R6.1a's whole purpose: editing one member's tag changes its
  digest, so the entry **relocates**, and `git diff` reports a delete plus an insert in a different
  place -- with every entry between them shifting -- instead of one changed field. Name order leaves
  the entry where it is, so the diff shows the edit. `version` is in the key because two versions of
  one name are legal (R2.14a) and would otherwise have no defined relative order.

  **No tiebreaker is required, and none may be added.** Two members can share
  `project` || `name` || `version` in exactly one situation: the **same `id` with different `tags`**,
  which survives step 4's dedup because the `member()` digest covers tags. Since tidy (step 0a of
  design.md 21.4) runs *before* validation (0b), the sort can meet that tie -- and R's radix sort is
  stable, so it resolves to caller input order. That is harmless because **R2.14 refuses that payload
  one step later, so no tie can reach a written payload.** An implementer reaching step 4 will ask
  what to do about ties; the answer is nothing, and a defensive tiebreaker would be dead code.

  **Do not resolve this by hoisting the refusal before the tidy step.** The tidy-then-validate phase
  separation is worth more than removing an unreachable edge, and inverting it would make the tidy
  rules unreachable instead (R2.14).

  Note the key omits **`kind`**, which is safe rather than an oversight: a set and a table cannot
  share a name, because storage keys are `{name}/...` regardless of kind and AC4 refuses the
  collision. So `kind` could never break a tie that `project` || `name` || `version` did not already
  decide.

  This split is cheap now and **expensive later**: once payloads ship, changing the canonical file
  order is a change to canonical form, which I27 forbids.

  **The canonical form is what gets hashed, committed, and mirrored** -- there is no path where a
  non-canonical payload reaches disk. A caller that supplies a reordered payload sees it come back
  normalized, which is the honest outcome: the edit was not a content change, and silently
  discarding it (the alternative, if canonicalization happened only at hash time) would leave the
  author wondering where it went.

  **sv1 stays order- and shape-insensitive even so.** R2.12/R2.13 are not made redundant by this:
  the hash domain is a *parsed file*, which may have been written by an older build or hand-edited,
  and insensitivity means those still hash correctly. Canonicalization is belt; insensitivity is
  braces. Both are cheap.
- **R2.16 -- no Unicode normalization; tag bytes are hashed exactly as given.** Tag keys and values
  are hashed as their literal UTF-8 bytes, and radix sorting is byte order. NFC and NFD spellings of
  visually identical text are therefore **different** tags with different `data_sha`. This is stated
  normatively because it would otherwise be decided by accident, and a non-R implementation might
  normalize by default.

  Rejected: normalizing to NFC first. It would make visually identical tags equal, which is the
  appealing part, but **Unicode normalization tables are versioned data that changes across Unicode
  releases** -- putting them in the identity path means a Unicode version bump can re-mint hashes.
  That is structurally the same failure as the parquet-serialization drift of #72, with the Unicode
  Consortium in `arrow`'s role, and sv1 exists precisely to have nothing versioned in its identity
  path. It would also add a string-processing dependency (`stringi`) to a deliberately lean
  `Imports`. Consistent with cv1, which already treats NFC-vs-NFD as identity-relevant for table
  values (labelled as an expected verdict in `dev/e2e-cv1-identity.R`). Recourse is caller-side:
  normalize your tags before writing.
- **R2.17 -- the empty string set is pinned.** `strset(character(0))` is `h(0x02)` over an empty
  concat, exactly as an absent or empty `tags` map is `h(0x03)`. Validation refuses an empty tag
  value (R2.14) and R2.15 step 2 cannot produce one, but **the encoder must not depend on that**,
  for the same reason design.md 7.2 already gives for empty maps: an encoder whose correctness rests
  on an upstream refusal breaks silently the day the refusal is relaxed. Carried as a golden.

**Acceptance**: AC13 below, plus the standalone reference and the in-package implementation
produce identical `data_sha` for every golden fixture, on both x86_64 and arm64.

### R3 -- Members are references, not parents

- **R3.1** A set carries **no** `parents` and **no** `source_lineage`. The member list lives
  only in the payload.
- **R3.2** This is not a special case -- it falls out. `datom_write()` already derives
  `source_lineage` as the union of parents' lineages (`R/read_write.R`, the
  `datom_lineage_union()` call), so null-parents automatically means no inheritance.
- **R3.3** **Access is per-member, enforced where it already is.** A set contains no data, so
  conjunctive (AND) access across members would be wrong -- it would make a 50-table product
  unreadable to anyone lacking one table. If you can read `AE` but not `CM`, you pull the set
  and work with `AE`. `datom_read()` on the member is the only gate and needs no change.
- **R3.4** **Lineage flows through tables only.** If product B derives a table from product A's
  `adsl`, B's table names A's `adsl` as parent. The set is how you *found* the table, not how
  data *reached* it.
- **R3.5** "Which raw sources fed product X at version V" is a **read-time union** over the
  members' `source_lineage` -- one metadata read per member, composed from the existing
  `datom_get_lineage(depth = "source")` + `datom_lineage_union()`. Not a stored field, so it
  cannot go stale. For a 50-member product that is 50 reads, acceptable because it is a **cold
  path**: access is enforced per-member at `datom_read()`, so the union is needed only for
  audit and reporting, never per-access.

**Acceptance**: AC8 below.

### R4 -- Member schema and constructor

- **R4.1** Each member entry carries an **`id`** record of exactly `{ project, name, kind, version }` -- all single strings -- plus an optional `tags` map (R2.12). The `id`/`tags` split is structural: `id` is a well-specified reference record with fixed keys, `tags` is an open map.
  - `project` -- otherwise cross-project membership cannot resolve, and cross-project is the
    point.
  - `kind` -- because a set may contain a set; without it a resolver cannot know whether to
    call `datom_read()` or `datom_read_set()`.
- **R4.2** Members are built with **`datom_member(conn, name, version)`**, mirroring
  `datom_parent()` (`R/lineage.R`). Callers must not hand-assemble member lists:
  `datom_parent()` is the established pattern for constructing a validated reference record,
  and symmetry keeps validation at construction time rather than deep inside
  `datom_write_set()`.
- **R4.3 -- resolution is one level; datom never traverses.** A set's payload lists its **direct**
  members only. Reading a set returns those member records; if a member is itself a set, the
  consumer gets a **pointer** to it and reads that set separately if they want its contents. This
  mirrors `datom_get_parents()`, which returns one step back and leaves further steps to the
  caller. **No datom operation walks the member graph** -- not `datom_read_set()`, not
  `datom_validate()`. A consumer wanting a flattened tree composes repeated reads in their own
  code.
- **R4.4 -- the member graph is acyclic by construction, so no cycle detection is specified.**
  A member pins an **immutable version**, and declaring it requires that version to already exist
  (`datom_member()` reads its snapshot). So a set cannot reference anything that contains it --
  that thing did not exist when its members were chosen. This is the same property that makes git
  history acyclic. Concretely, the sequence that looks like a cross-project cycle is not one:

  ```
  1. A writes set A1 containing B1@v1        (B1@v1 must already exist)
  2. B writes set B1@v2 containing A1@v1     (does NOT mutate B1@v1)

  Result: B1@v2 -> A1@v1 -> B1@v1            terminates; v1 and v2 are distinct nodes
  ```

  Because of this, **no depth limit and no visited-set guard are required**. Nothing can loop,
  and with R4.3 nothing traverses in the first place.
- **R4.5 -- self-reference is refused as nonsense, not as a cycle.** A set listing itself (an
  earlier version of itself) as a member is acyclic and would terminate, but it is never
  meaningful. Cheap check at write time, clear error.
- **R4.6 -- tags are per-member, and are what replace folder structure.**
  `datom_member(conn, name, version, tags = NULL)` -- `tags` is an optional named list of text
  values (R2.11). Set-level tags are also allowed (R2.12) for facts about the collection itself,
  such as a description.

  **Why per-member.** The structure being replaced is dpbuild's nested product list
  (`dp$input$raw_ae()`, `dp$output$derived1`, `dp$metadata$data_def`) -- and those top-level names
  classify *items*, not the collection. So `role: "output"`, `domain: "safety"` are member
  properties. #89's own rejected alternative confirms it: it proposed flattening to
  `(name, project, version, tag_key, tag_value)`, one row per member per tag.

  **Why a value may be an array of strings.** The motivating limitation of folders is that an item
  cannot be in two at once. Multi-valued tags are therefore the point, not an extension --
  `domain: ["safety", "efficacy"]` must work. This is the *only* reason arrays exist in the
  grammar.
- **R4.7 -- "folder structure" is a projection over tags, computed by the consumer, never stored.**
  A given ordering of tag keys yields a folder-like hierarchy; prioritising a different key set
  yields a different one. That prioritisation is a **governance / consumer-side presentation
  choice**, not payload content. Consequences:
  - datom stores tag **facts** and takes no position on hierarchy.
  - **The payload contains no view or navigation config at all**, which is what makes the
    text-only grammar (R2.11) sufficient. #89 listed "view config" as payload content and cited
    "nested view config does not survive flattening" as an argument -- that concern is **retired**:
    the navigation *is* the tags.
  - Arbitrarily many folder structures cost nothing, because none of them is stored.

**Acceptance**: AC9 (self-reference refused) and AC15 (nesting resolves one level, no traversal)
below; plus a hand-assembled member list is refused with a message pointing at `datom_member()`
(mirroring the `remedy` pattern in `.datom_validate_parents()`).

### R5 -- Storage layout

Relative to the artifact prefix:

```
{name}/{data_sha}.json                  <- set payload            (NEW)
{name}/.metadata/metadata.json          <- current state          (same as tables)
{name}/.metadata/version_history.json   <- history                (same as tables)
{name}/.metadata/{metadata_sha}.json    <- versioned snapshot     (same as tables)
```

- **R5.1** Two distinct `.json` addresses exist and must not be confused: the **payload** at
  `{name}/{data_sha}.json` and the **versioned metadata snapshot** at
  `{name}/.metadata/{metadata_sha}.json`. Different directories, no key collision.
- **R5.2** Keys are built through a helper, not hand-rolled `paste0` at call sites. See
  design.md "Deviation D1" for the precise form -- the issue's instruction to use
  `.datom_build_storage_key()` needs a correction, because that function returns a *full* key
  (prefix + `datom/` + segments) while `.datom_storage_*()` dispatch takes *relative* keys.
- **R5.3** Tables keep `{name}/{data_sha}.parquet`. This is *why* an unupgraded reader meeting
  a set fails loudly -- it fetches a `.parquet` object that does not exist.

### R6 -- Payload is git-canonical with a storage mirror

- **R6.1** The payload follows the **`governance.json` dual-pointer pattern**
  (`R/governance_json.R`), not the parquet pattern: git is canonical, the storage mirror is
  written in the same step and always derived from git.
- **R6.1a -- git side: one stable path. Storage side: content-addressed.**

  | Side | Path | Why |
  |---|---|---|
  | **git** | `{name}/set.json` -- a single stable path, modified in place | git carries the history, and `git diff` shows **member-level** changes |
  | **storage** | `{name}/{data_sha}.json` -- content-addressed, immutable | a reader must fetch an exact version by address, with no git |

  The git side mirrors how `{name}/metadata.json` already works: stable path, mutated, history
  owned by git.
- **R6.1b -- why the git side is NOT content-addressed** (this reverses an earlier draft). With a
  content-addressed filename, every version is a **new file**, so `git diff` between two product
  versions reports "file added" and never "these members changed". History would be read by
  listing filenames -- i.e. hand-maintaining what git already maintains (R20). One stable path
  gives real diffs, keeps one file in the working tree instead of N, and makes the earlier
  "retain all historical payloads" rule unnecessary: **git retention is definitional.** Any
  version is still fully reconstructible from the clone alone via
  `git show <commit>:{name}/set.json`, so the P17 guarantee is preserved and strengthened.
- **R6.2** Tags live **in the payload** (descriptions are tags), not in a parallel
  metadata schema.
- **R6.3** **No member index.** `column_hashes` exists so you can diff a table without
  downloading parquet; the payload is small and cheap to read, so a member index would be
  metadata-for-metadata.
- **R6.4** "git-canonical" must **not** be read as "requires a clone". See AC1.

### R7 -- `document_sha` for stored-document integrity

- **R7.1** Sets carry `document_sha`: the SHA-256 of the stored payload bytes, verified on read
  at the **same gate position** as `parquet_sha` -- *before* parsing.
- **R7.2** `document_sha` is persisted in `version_history.json` entries **from day one**, using
  the existing conditional-add pattern in `.datom_write_metadata_local()`
  (`R/read_write.R`, the `if (!is.null(metadata$parquet_sha))` block).
- **R7.3** `parquet_sha` is **not** renamed to a kind-neutral name. It is the correct name for a
  parquet object's byte hash. Rationale: design.md "Compatibility analysis".
- **R7.4** `document_sha` goes in the `volatile` exclusion list of
  `.datom_compute_metadata_sha()` (`R/utils-sha.R:444-447`), for the same reason `parquet_sha` is
  there -- it is a stored-object byte fact, not content identity.
- **R7.5 -- one `data_sha`, one byte spelling, in git and in storage.** `document_sha` is only
  meaningful if the bytes at `{name}/{data_sha}.json` never change once written. Two rules enforce
  that, and **both** are required:

  1. **Never re-emit a payload for a `data_sha` already in history.** Reuse the stored object and
     **carry the recorded `document_sha` forward**. This is the exact `parquet_sha` pattern:
     `.datom_lookup_history_parquet_sha()` scans history newest-first for a matching `data_sha` and
     returns `upload = FALSE` (`R/read_write.R:404-409`, `422-439`). A set needs the direct
     analogue. Recomputing `document_sha` from freshly emitted bytes while reusing the stored object
     records a hash of bytes nobody stored, and the failure surfaces only later, as a **refused read
     of a valid version**.
  2. **The repair path must not break it either.** `datom_validate(fix = TRUE)` re-uploads metadata
     and payloads *from the clone*, so if git ever held a different spelling than storage for one
     `data_sha`, repair would not merely fail to help -- it would **actively** overwrite the stored
     object with bytes that do not match the recorded `document_sha`. R2.15 is what makes this safe
     (git holds the canonical form, so there is only one spelling to hold), and repair must
     additionally **neither re-upload the payload bytes nor recompute `document_sha`** for a version
     whose payload is already stored. Both halves are stated because forbidding only the recompute
     still permits the worst outcome -- overwriting the object while keeping the old hash.

  **Why sets need this more than tables do.** For a table, two byte streams for one `data_sha`
  require an `arrow` upgrade -- rare and externally triggered. For a set, R2.12/R2.13 make it
  reachable by an **ordinary authoring edit** (reorder a tag value), so the rule moves from
  occasional safety net to routine correctness. Sets also have a git copy of the payload, which
  parquet never does, which is what brings rule 2 into scope at all.

  **Ownership note**: this is a write-path and repair-path requirement, not an encoder one. It
  belongs to `datom_write_set()` (Task 9) and `datom_validate()` (Task 14), **not** Task 2. It is
  recorded here because it is a *consequence* of the Task 2 encoding decisions, and a Task 9
  implementer who assumes "new bytes mean a new `document_sha`" ships a defect that every
  per-chunk test passes.

### R8 -- One typed namespace in `manifest.json` **[BREAKING]**

- **R8.1** `manifest$tables` becomes **`manifest$artifacts`**, keyed by name, each entry typed
  by `kind`. **The example below is illustrative, not the full entry schema** -- real table
  entries also carry `current_data_sha`, `last_updated`, and conditionally `original_file_sha` /
  `original_format` (see `.datom_update_manifest_entry()`, `R/sync.R:744-756`). Existing entry
  fields are preserved verbatim; `kind` is added, and set entries substitute `member_count` for
  `size_bytes`:

```json
{
  "schema_version": 2,
  "artifacts": {
    "dm":            {"kind": "table", "current_version": "...", "size_bytes": 4096, "version_count": 3},
    "adsl":          {"kind": "table", "current_version": "...", "size_bytes": 8192, "version_count": 1},
    "study001-adam": {"kind": "set",   "current_version": "...", "member_count": 2,  "version_count": 1}
  }
}
```

- **R8.2** **Not** a sibling `manifest$sets` node. Names must be unique **across kinds**,
  because storage keys are `{name}/...` regardless of kind. A set named `dm` alongside a table
  named `dm` would both write `dm/.metadata/metadata.json` and clobber each other. Two sibling
  nodes make that illegal state *representable* and require an explicit cross-node uniqueness
  guard that someone will eventually forget. One namespace makes it a key collision in a single
  list -- structurally impossible, no guard needed.
- **R8.3** The `summary` block keeps every existing field's current meaning and gains one:

```yaml
summary:
  total_tables:     <count where kind == "table">   # meaning unchanged
  total_size_bytes: <sum over tables>               # meaning unchanged
  total_versions:   <sum over tables>               # meaning unchanged
  total_sets:       <count where kind == "set">     # new, additive
```

  So the breaking surface is exactly **one key rename**, and no counter changes semantics.
- **R8.3a** **Set versions are deliberately not counted in `summary`.** `total_versions` stays
  tables-only (R8.3), and no `total_set_versions` is added. Reason: every existing counter keeps
  its current meaning, which is what holds the breaking surface to one key rename; adding a
  counter whose only consumer would be a future feature is speculative. Per-set version counts
  remain available on the entry (`version_count`) and via `datom_history()`. Recorded here so a
  later reader does not read the omission as an oversight.
- **R8.4** `datom_list()` and `datom_summary()` read `artifacts` and surface `kind`. They surface it
  differently, because their shapes differ: `datom_list()` gains a `kind` column on every row
  **including its empty-result returns**, while `datom_summary()` has no per-artifact axis and gains
  a `set_count` aggregate beside `table_count` (owner-decided 2026-08-23).
- **R8.5** No existing repo has this shape, and R9's toleration of an absent `schema_version` is not
  enough on its own to keep one working. **R22 is a prerequisite of this rename**, not a companion
  to it.

### R9 -- `schema_version` gate

Add a repo schema version, checked by readers, so that **this is the last transition that can
degrade silently**.

```r
SUPPORTED_SCHEMA <- 2L

if ((meta$schema_version %||% 1L) > SUPPORTED_SCHEMA) {
  cli::cli_abort(c(
    "This repo uses datom schema v{meta$schema_version}.",
    "x" = "Installed datom {utils::packageVersion('datom')} supports up to v{SUPPORTED_SCHEMA}.",
    "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')}."
  ))
}
```

- **R9.1** **Asymmetric**: refuse *newer*, tolerate *older*. An absent field defaults to `1`, so
  v1 repos keep working. **Toleration alone stops being sufficient once R8.1 lands** -- a tolerated
  v1 manifest still holds its list under `tables`, so "keeps working" requires the upgrade in R22.
  Tolerating a version and understanding the shape it implies are two different obligations, and
  before R22 only the first was met.
- **R9.2** **Both reader entry points.** Readers take two independent paths, and a
  manifest-only gate leaves one open:

```
datom_list() / datom_summary()  --> .metadata/manifest.json          <- gate here
datom_read()                    --> {name}/.metadata/metadata.json   <- and here
```

  `datom_read()` never touches the manifest (verified: `R/read_write.R:44-58` -- it calls
  `.datom_read_metadata()` -> `.datom_resolve_version()` -> `.datom_read_parquet()`). So
  `schema_version` must live in **both** the manifest and per-table `metadata.json`.
- **R9.3** `schema_version` goes in the `volatile` exclusion list of
  `.datom_compute_metadata_sha()` (`R/utils-sha.R:444-447`), alongside `datom_version`. Otherwise a
  schema bump silently rewrites every table's version identity.
- **R9.4** **Do not overload `datom_version`.** It records the *writing package version* --
  provenance, not contract. Most releases will not change the schema, so gating on it would
  fire on harmless upgrades. Keep the two fields distinct.
- **R9.5** **Stamped always, incremented only on a break** (owner-decided 2026-08-23). Every
  manifest and every per-artifact metadata document carries `schema_version`, so a reader can
  always tell what shape it is holding. The number **increments only when a change would break a
  reader**; a release that merely adds a field leaves it where it is. The test, written down so it
  is not a judgment made under release pressure:

  Classified by **effect on a reader**, not by the shape of the edit -- an earlier version of this
  table classified by shape, so a content-bearing addition fell through as "added, not breaking":

  | Change | Reader | Schema number | Also required |
  |---|---|---|---|
  | rename a field, or move it to a different parent | breaks | **bump** | |
  | remove a field a reader may rely on | breaks | **bump** | |
  | change what an existing field means, or its type | breaks | **bump** | |
  | restructure a container (keyed object to array of records, etc.) | breaks | **bump** | |
  | add a field that does **not** enter identity | safe | no bump | NEWS entry |
  | **add a field that enters identity** (content-bearing) | **safe** | **no bump** | **NEWS entry + writer floor raise if one is set (R23.3)** |

  The last row is the one that has no shape-based answer. A content-bearing addition is
  **reader-safe and writer-breaking**: readers never recompute identity, writers do
  (`R/read_write.R:343`), so an older writer disagrees with the recorded version and mints a version
  on unchanged content. The format did not change, so the number must not move -- and the writer-side
  stop therefore comes from R23's vocabulary check rather than from the number.

  **Per-file rule** (Design A, owner-decided 2026-08-23). The number moves for **both** documents on
  a breaking change, and it always describes the shape the file actually has. What differs is the
  **reader's response**, because only one of the two files is rebuildable:

  | Document | Too-new number, reader | Too-new number, writer |
  |---|---|---|
  | `.metadata/manifest.json` | **warn and rebuild** from storage (R22.11) | **refuse** |
  | `{name}/.metadata/metadata.json` | **refuse** -- no hatch exists (R22.9) | **refuse** |

  Rejected alternative: freeze the manifest's number and dispatch on shape instead. It would leave a
  file stamped v2 while carrying a v5 shape, leave the upgrade chain with one step forever, and --
  decisively -- make a **truncated** manifest indistinguishable from a **future-shaped** one, since
  both present with the expected key missing. The number is what separates corruption from the
  future.

  The call is made at design time, alongside the escalation flags -- not at implementation time.
  Rationale for the split: stamping costs nothing (R9.3 keeps the field out of identity, and under
  an allowlist-based hash it stays out by construction), while incrementing costs every pinned
  build its access. Incrementing on an additive change therefore fires a refusal for a change the
  reader could have tolerated, which is the failure this rule exists to prevent. The v1 to v2 bump
  in this spec qualifies as breaking on row one: the artifact list is renamed.
- **R9.6** **Publish one schema history table.** The number changes rarely and the package version
  changes often, so "which datom reads schema v2" is not inferable from either field: one schema
  version spans many releases. One table in the package documentation, with a row per change:
  **schema version, minimum writer version, released in, what changed, why it moved (or why it did
  not)**. That is #103's table plus two columns, and it makes "when did this move and why" a single
  lookup. Every refusal message points at it -- a refusal raises exactly one question, *which datom
  do I need*, and nothing in the repo answers it.
- **R9.7** **A release that adds any field to a datom-owned document requires a writer upgrade.**
  Follows from R23.1 and is stated here because it is counter-intuitive next to R9.5's "add a field
  -> no bump": the *number* does not move, and older **writers** are nonetheless refused. Reader
  compatibility and writer compatibility are separate guarantees, and only the reader one survives an
  addition. Consequence accepted deliberately (R23.6): even a cosmetic addition forces a fleet-wide
  writer upgrade. The population is small, writes are infrequent, and the alternative is a writer
  that disagrees about identity.

### R10 -- Project mode: set repos forbid the import path, not the table path

A build-package repo *does* write new tables (derived `adsl`, `adae` parquets) -- it never
imports from files.

- **R10.1** Expressed as a project-level mode in `project.yaml` so `datom_sync_manifest()`
  refuses with a clear message instead of silently no-op'ing, and `datom_status()` reports
  accurately.
- **R10.2** The mode also **names the repo's set**:

```yaml
mode: product
set: study001-adam
```

- **R10.3** One repo = one set = one product. Enforcing it in datom rather than in the build
  package costs almost nothing, removes the ambiguity of "which set is this repo's product," and
  prevents anything else writing to the repo from violating the invariant.
- **R10.3a -- how R10.3 is actually enforced.** The claim above is only true if something checks,
  so two concrete gates:
  1. **`datom_write_set()` requires `mode: product`.** On a repo without it, abort with the
     recourse (set `mode: product` + `set:` in `project.yaml`). A set written into a
     non-product repo would have no declared owner and would defeat both gates below.
  2. **`datom_write_set(name = )` must equal `project.yaml`'s `set:` field.** A mismatch aborts.
     This is what makes "one repo = one set" true rather than aspirational, and it is also the
     precondition the self-reference check (R4.5) relies on -- it needs to know the set's own
     identity before the write.

  These two checks run **before** any hashing or IO, so a refusal leaves no partial state
  (the `.datom_canonical_hash()` precedent).
- **R10.4** `mode: "product"` reads better than `mode: "set"` since these repos also hold
  derived tables.
- **R10.5 -- `mode: product` is also an identity badge.** Beyond gating the import path, the mode
  declares "this datom repo is also a build-package project". The downstream build package
  (`dpdev`) checks it at attach time. So the mode carries two meanings that must both hold:
  *forbid the import path* (R10.1) and *this repo is jointly owned* (R14). datom itself knows
  nothing about the build package's structure -- see R16 non-goals.

### R11 -- `datom_validate()` branches on kind

`R/validate.R:391` hardcodes the data-object check inside `.datom_validate_one_table()`:

```r
data_key <- paste0(name, "/", meta$data_sha, ".parquet")
```

On a set this fails 100% of the time and reports `data_missing_s3`.

- **R11.1** **table** -- existing parquet existence check, unchanged.
- **R11.2** **set** -- payload exists at `{name}/{data_sha}.json`, **and** every member resolves
  as far as the available connections allow. "Resolves" is **scoped, because it has to be**:
  - **Same-project members** are fully checked (their metadata is in this namespace).
  - **Cross-project members** are checked as *well-formed pointers* only, unless the caller
    supplies a connection for that project. datom performs no name-to-location lookup of its own
    (R18), so a validator that claimed to fully check cross-project members would either be
    lying or silently requiring governance.
  Checking is **one level deep** -- each member pointer resolves to an existing artifact. The
  validator does not traverse into nested sets (R4.3); validating an inner set is a separate
  `datom_validate()` call against that set's own project. Unresolvable members reuse the same
  status code (R11.3) rather than inventing a second vocabulary.
- **R11.3** New status code for unresolvable members (e.g. `members_unresolvable`). A citable
  artifact that can silently rot undermines the auditability claim, so this is in scope rather
  than deferred.

### R12 -- Public write/read surface

- **R12.1** `datom_member(conn, name, version, tags = NULL)` -- validated member constructor
  mirroring `datom_parent()`, with optional per-member tags (R4.6).
- **R12.2** `datom_write_set(conn, members, tags = NULL, ...)` -- derives the payload from members
  and optional **set-level tags**; **reuses change detection, git-gates-storage ordering, and dedup
  unchanged** (the step 4-10 sequence in `datom_write()`).
  **`tags` is not optional decoration -- it is required payload structure.** R2.12 puts `tags` at the
  payload root, R2.6 hashes it, and **AC2's converse half cannot be written without it** (a changed
  description must mint a version, and a description *is* a set-level tag per R6.2). Note this is
  the only channel: R1.4 deliberately withholds a `metadata =` parameter, so without `tags` the
  public surface could not express a payload the spec requires.
- **R12.3** `datom_read_set()` -- resolves and returns the set. **Both directions of the
  kind mismatch abort with a pointer to the right function**: `datom_read()` on a set points at
  `datom_read_set()` (AC6), and `datom_read_set()` on a table points at `datom_read()` (AC14).
  The converse matters as much as the original -- without it, `datom_read_set()` on a table
  fetches `{name}/{data_sha}.json`, gets a not-found, and reports a missing payload for an
  artifact that is perfectly healthy.
- **R12.4 -- export JSON GET only** (narrowed 2026-08-18; the put is deferred, see R12.4a).
  `datom_storage_read_json()` on the Storage Extension API, hardening the existing
  `.datom_storage_read_json()` internal (`R/utils-storage.R:66`): conn class check, relative-key
  validation, clear abort on an absent key. No direct `.datom_s3_*()` calls from business logic
  (I7). Reads carry no policy -- there is nothing to bypass, which is why R12.4a's refusal list
  never applied to them.
- **R12.5 -- `datom_write_set(conn, members, ..., include_paths = NULL)`.** Optional character
  vector of repo-relative paths staged **into the same commit** as the set payload and its
  metadata files. Purpose: the set version's commit tree contains the code and environment that
  produced it, so **the joint version is structural, not recorded** (see R14 rationale). The build
  package passes its own enforced-structure manifest (e.g. `R/`, `dp/`, `renv.lock`, `tests/`);
  it never passes add-all.
  - **Ordering unchanged.** git-gates-storage is preserved: local writes -> **one** git commit
    (payload + metadata + `include_paths`) -> push -> storage mirror.
  - **The storage mirror contains only datom artifacts.** `include_paths` content is **never**
    mirrored to storage. It is git-only, by design (R16).
  - **Validation, both before any hashing or IO** (same gate placement as R10.3a):
    - A nonexistent path in `include_paths` is an **error**, not a skip. Joint commits must be
      deterministic, not best-effort.
    - A path overlapping datom-owned paths (`{artifact}/**`, `.datom/**`) is **refused** -- those
      are staged automatically and listing them invites double-staging confusion.
  - **Dedup interaction -- the sharp edge.** If the set content is unchanged (same `data_sha`, so
    AC2's idempotent no-op applies), the write **remains a no-op even when `include_paths` files
    have changed**: no commit is created. Emit an informational message directing the caller to
    `datom_repo_commit()` (R15). Rationale: AC2 must not acquire a side channel that commits code.
    An idempotent data write that silently commits human WIP would be exactly the
    machine-moment-add-all failure R14 exists to prevent, arriving through a different door.
- **R12.4a -- RETIRED 2026-08-18, together with the write export it governed.** The whole
  requirement existed to make a public JSON **write** safe. That export is **deferred, not
  implemented** (Backlog in `dev/README.md`, trigger: datomanager needs to write JSON into its own
  gov namespace), so there is nothing to constrain and nothing to test -- AC23 is retired with it,
  and so is I14.

  **Why deferred rather than built.** The capability had no remaining consumer once
  `datom_write_set()` existed: #89 asked for it so a downstream package could write *its own
  document* into datom's namespace, and that document was a set. Separately, it cuts against the
  Authority Principle in `dev/datomanager_scope.md` -- "data-repo mutations always route through
  datom ... datomanager never touches the data repo directly" -- whose expression is a **purpose-built
  verb per need** (`datom_repo_set_data_store()`, `datom_repo_delete()`,
  `datom_repo_attach_governance()`), not a generic byte channel. The `governance.json` data-side
  mirror is the precedent: datom gave datomanager a named export instead of a generic write.
  Deferring is also the cheap direction -- adding an export later is additive, removing one after
  release is breaking.

  **The analysis below is preserved as-is**, because if the trigger fires it is the starting point:
  scope the export to the caller's own namespace, and re-derive the refusal list rather than
  assuming this one still fits.

  Original requirement, retained for reference: a public
  `datom_storage_write_json()` that accepts any key lets a downstream package write
  `{name}/.metadata/metadata.json` or `{name}/{data_sha}.json` directly, **silently bypassing
  git-gates-storage (I5/I6) and integrity for artifacts datom manages**. That is a
  silent-degradation path in a new public API, which the compatibility posture forbids on its own
  terms. The write export therefore **refuses managed keys**: anything under a `.metadata/`
  segment, and any payload-shaped key (`{name}/{sha}.{json,parquet}`) under an existing artifact
  directory. Reads are unrestricted -- reading a managed key is useful and harmless.
  **It must also refuse `.access/`.** `{prefix}/datom/.access/` is a **namespace reserved for the
  future access-enforcement package** (`dev/datomanager_overview.md`, "Reserved Namespace"), under
  a standing rule that datom never reads, writes, or deletes there -- with an audit confirming
  datom is currently safe *by construction* (it has no list/delete calls and every key goes
  through the `datom/`-inserting key builder). This export is the first genuinely general-purpose
  write surface datom has ever offered, so it is also the first thing that could break that
  reservation. Adding `.access/` to the refusal list keeps the guarantee structural rather than
  incidental.
  This is a **public contract decision, settled here rather than at implementation time**.

### R13 -- Documentation

- **R13.1** `dev/datom_pathways.md` route card: "Given a set + version, resolve its members".
- **R13.2** `dev/datom_specification.md`: set artifact kind, `schema_version` contract.
- **R13.3** Fix the stale "task 5.1" claims in `R/read_write.R`. They assert version-pinned reads
  lack `parquet_sha` "until `version_history` entries persist `parquet_sha` (task 5.1)". That is
  **stale**: `.datom_write_metadata_local()` already persists it (the conditional-add block) and
  `.datom_resolve_version()` reads it back (`R/read_write.R:187` for a version-pinned read, `129`
  for the current one). Only *legacy* entries lack it.
  **Four sites, verified by `grep -n "task 5\.1" R/read_write.R`** -- note #89 cited `95-97`,
  which is the function title, not the stale text:

  | Line | Site | Problem |
  |---|---|---|
  | 105-108 | `.datom_resolve_version()` docstring | "until ... (task 5.1)" -- stale |
  | 205-206 | `.datom_read_parquet()` `@param parquet_sha` | "before task 5.1 persists it" -- stale |
  | 413 | `.datom_lookup_history_parquet_sha()` docstring | "transitional period before task 5.1" -- stale |
  | 393 | `.datom_resolve_parquet_sha()` comment | **"Since task 5.1..."** -- already correct, and therefore *contradicts* the three above within the same file |

  Sweep all four: drop the internal task references entirely (they are meaningless to public
  readers, per the Don'ts) and state the actual condition -- only pre-#72 legacy entries lack
  `parquet_sha`.
- **R13.4** NEWS entry noting the `artifacts` rename, its discovery-only exposure, and the
  `schema_version` gate.

### R14 -- Foreign-content discipline in `mode: product` repos

**Context (the decision this encodes).** The `mode: product` repo **is the joint repo**: data
pointers, derivation code, and environment (`renv.lock`) live together. There is no separate
code/env repo. All git **mutations** (stage, commit, push, pull) go through datom; downstream
packages never import `git2r`. Writing files on disk is not a git operation and needs no datom
API. Rationale in design.md section 19.

Consequence: a datom repo now routinely contains content datom does not own, and datom commits at
**machine-chosen** moments (inside each write, possibly mid-build) while humans edit code
continuously. So:

- **R14.1 -- machine-moment commits stage only datom-owned paths.** A commit created inside
  `datom_write()` / `datom_write_set()` stages **only** the written artifact's files and
  `.datom/**`. **Never add-all.** This is already true by implementation --
  `.datom_git_commit()` takes an explicit file list (`R/utils-git.R:182`) -- so the requirement
  **elevates it from an accident of implementation to a stated guarantee**, with a test, so a
  future add-all refactor fails CI rather than an audit.
- **R14.2 -- all datom operations tolerate non-datom paths.** `datom_validate()`,
  `datom_status()`, `datom_list()`, and the sync/pull paths must never stage foreign paths and
  never report them as defects. `datom_status()` **may** report foreign dirty files as
  uncommitted git state (that is honest reporting of the repository, and useful), but must not
  classify them as a datom problem; `datom_validate()` must not surface them at all.
- **R14.3 -- `include_paths` is the sole exception.** The only way a machine-moment commit may
  contain a non-datom path is R12.5, and only because the caller enumerated it explicitly.

### R15 -- New exports: the sanctioned git-mutation surface

```r
datom_repo_commit(conn, message, paths = NULL, push = TRUE)
datom_repo_push(conn)
```

The **sanctioned git-mutation surface** for downstream packages committing non-datom content
(framework state, code, environment). Without it, a downstream package's only options are to
import `git2r` (rejected -- R16) or to abuse a datom write.

**Two verbs, not one, and the reason is a hazard rather than a preference.** R15.3 supports
`push = FALSE` explicitly so downstream can decouple commit from push (the `dpbuild`
`dp_commit()` / `dp_push()` pattern). That pattern needs a second verb: without one, "push what I
already committed" is only expressible as *another commit attempt*, and in a `mode: product` repo
`paths = NULL` is add-all. So a caller who merely wants to push would route through a code path
that commits any human WIP it happens to find -- **the R14 machine-moment add-all failure arriving
through a third door.** Intent to push must be spellable without risking a commit.

Supporting symmetry: datom already exports a standalone `datom_pull()` (`R/sync.R:45`) with no
standalone push counterpart, and the `datom_repo_*` family already exists (`datom_repo_delete()`,
`datom_repo_set_data_store()`, `datom_repo_attach_governance()`). `datom_repo_push()` closes an
existing asymmetry rather than inventing a new shape.

- **R15.1** `paths = NULL` (default): stage **all** tracked-and-modified plus untracked changes,
  respecting `.gitignore` -- i.e. what `git add .` would stage. These are **human-invoked**
  moments, where add-all is the correct semantic (this is exactly why R14.1 restricts
  *machine* moments only).
- **R15.2** `paths = <character vector>`: stage exactly those repo-relative paths.
- **R15.3** `push = TRUE` (default): push after commit through the existing path
  (`.datom_git_push()`, inheriting its pull-before-push and upstream-tracking behavior).
  `push = FALSE` is supported so downstream can decouple commit from push -- see
  `datom_repo_push()` (R15.8) for the other half.
- **R15.4** Requires **developer** role; a reader conn gets the standard role error.
- **R15.5** **Nothing to stage is an informational no-op** (`cli::cli_alert_info()`, return
  `invisible(NULL)`), **not** an error -- a human-moment "commit everything" must be idempotent.
  **Qualification: "no-op" means no *commit* is created; it does not suppress the push.** When
  `push = TRUE` and the branch is ahead of the remote, the push still runs. Otherwise a failed
  push on a previous call leaves the remote silently behind forever, since every subsequent call
  finds a clean tree and returns early -- a silent divergence, which the compatibility posture
  forbids on its own terms.
- **R15.6** Returns the commit SHA invisibly on success; `invisible(NULL)` when no commit was
  created (whether or not a push occurred).
- **R15.7** **The on-a-branch (no detached HEAD) guard must be asserted explicitly**, not
  inherited. It currently lives in `.datom_git_branch()` and is reached only via
  `.datom_git_push()`, so with `push = FALSE` nothing would check it. Call it up front so the
  guard holds for both `push` values. (See design.md section 19 "Corrections to the delta".)
- **R15.8 -- `datom_repo_push(conn)`.** Pushes the current branch through the same path
  (`.datom_git_push()`), so it inherits pull-before-push, upstream-tracking, and the on-a-branch
  guard identically. **Convergent, not imperative**: nothing to push is an informational no-op,
  not an error, so calling it twice is safe and "ensure the remote has everything" is a legal
  standalone operation. Requires **developer** role. Returns `invisible(TRUE)`.
- **R15.9** Push convergence is decided by the **already-available** ahead count.
  `.datom_check_git_current()` already calls `git2r::ahead_behind()` and reads element `[[2]]`
  (behind); element `[[1]]` is ahead. So R15.5 and R15.8 need **no new git machinery** -- this is
  not speculative capability.

### R16 -- Non-goals (this spec deliberately does not do these)

- **Branch create/switch helpers.** Belongs with a future refs / branch-publication design.
  datom's existing on-a-branch requirement is unchanged.
- **Storage mirroring of code or environment content.** `include_paths` is git-only by design;
  the storage namespace holds datom artifacts and nothing else.
- **Any datom knowledge of the build package's structure.** datom receives paths as **opaque
  arguments**. The three-tier ownership taxonomy in design.md section 19 is *context for the
  reader*, not a datom contract -- datom must not validate, assume, or special-case `dp/`, `R/`,
  `renv.lock`, or any other build-package path.
- **No `.gitignore` API.** `datom_init_repo()` seeds `.gitignore` (existing behavior) and
  downstream packages append entries by **editing the file directly** -- a file write, not a git
  operation. **No `datom_gitignore_*` function is to be added.** Recorded to prevent API creep.

### R17 -- Artifact topology: one repo, one namespace, one manifest

- **R17.1** A datom project is one git repo paired with one **storage namespace**
  (`{root}/{prefix}/datom/`). Repo, namespace, and manifest are 1:1:1. Nothing is shared between
  two projects -- not artifacts, not the manifest, not a single file.
- **R17.2** A set therefore lands in **the namespace of the product repo that owns it**, never in
  a namespace holding onboarded source data. This is already structurally true by composition:
  a set can only be written to the repo whose config names it (R10.3a), one repo maps to one
  namespace, and `datom_init_repo()` already refuses an occupied namespace via
  `.datom_check_namespace_free()`.
- **R17.3 -- new guard.** Initializing a `mode: product` repo **refuses a namespace that already
  contains a manifest for a different project**, with a message naming the occupying project and
  the recourse (use a distinct prefix). This closes the one remaining hole -- a deliberate
  force-init over an existing source namespace -- and turns a documented convention into a
  structural one.
- **R17.4 -- rationale is blast radius and ownership, not access control.** Teardown and
  prefix-delete operate on a **whole namespace**, so a product sharing a prefix with its source
  study means deleting the product can delete raw data. Secondarily, one namespace means one
  manifest, so sharing would make `datom_list()` unable to distinguish "the product" from
  "everything it was built from", and two git repos would contend for one manifest.
  **Explicitly not justified by access control** -- see R19.1, access is per-artifact.
- **R17.5 -- the rule is namespace separation, not bucket count.** One bucket with a prefix per
  product is the documented house convention (`dev/vignettes-deferred/buckets-and-prefixes.Rmd`,
  Pattern A: bucket-per-study, empty prefix for raw, *"prefix per product"* for multiple products
  per study). A dedicated or shared product bucket is equally fine. datom enforces separation and
  takes no position on bucket topology.
- **R17.6** A `mode: product` repo is **not a leaf**. Its derived tables are first-class datoms in
  a real namespace, so another product can take them as members or as parents. This is the
  composability claim from #89 and it depends on R17.1 holding.

### R18 -- Location resolution: explicit standalone, governance takes priority

- **R18.1 -- datom needs no governance for cross-project membership or lineage.** The mechanism is
  **caller-supplies-connection**: `datom_member(conn_src, ...)` and `datom_parent(conn_src, ...)`
  receive the other project's connection explicitly, record its `project_name` as a **label**, and
  datom performs **no name-to-location lookup anywhere**. A product spanning three studies in
  three buckets works with three configured connections and no governance attached.
- **R18.2 -- the precedence that already exists, which sets inherit rather than re-invent.** A
  project's location is written explicitly in its own config; `ref.json` in the governance repo is
  the authoritative pointer **once governance exists**, and connection-time resolution prefers it
  (this is what makes migration possible without rewriting artifacts). `governance.json` --
  written to both the git repo and the storage mirror -- **is the flag** for whether governance is
  attached. Member resolution follows exactly this precedence: caller-supplied connection when
  there is no governance, governance register once attached.
- **R18.3 -- member records carry a logical project name and never a location.** No backend, root,
  prefix, or region in a member entry. The payload is immutable and content-addressed, so an
  embedded location would go stale the day a bucket moves -- which is precisely the indirection
  `ref.json` exists to provide. Logical name in the artifact; physical location resolved at read
  time.
- **R18.4** Automatic name-to-location resolution is the **future access-enforcement package's**
  concern, not datom's: its registry holds a SOURCES table mapping project name to bucket/prefix,
  used when its lineage walker crosses buckets (`dev/datomanager_overview.md`). datom must not
  grow a competing lookup.

### R19 -- Forward compatibility with access enforcement

Recorded so this spec's decisions stay coherent with the planned access layer
(`dev/datomanager_overview.md`). **Nothing here is built now**; it constrains what we must not
foreclose.

- **R19.1 -- access is per-artifact, not per-namespace.** Roles are defined at table granularity,
  and every artifact has its own folder under the namespace, so a policy can grant
  `.../datom/adsl/*` without granting `.../datom/adae/*`. Per-artifact grants are expressible as
  prefix patterns. **A set is independently grantable for the same reason** -- it is an artifact
  with its own folder.
- **R19.2 -- two derived tables in one product legitimately have different access requirements.**
  Required permissions for a derived table are the union of the roles required by its **leaf**
  ancestors, discovered by walking lineage. Two tables in the same product, same bucket, same
  prefix, with different ancestry get different requirements **automatically** -- nobody configures
  it. This is a reason R17's namespace rule must not be justified by access control: separation is
  about blast radius, and granularity is finer than a namespace anyway.
- **R19.3 -- a set gates on nothing, because it has no lineage.** Members are references, not
  parents (R3), so a lineage walk from a set terminates immediately and finds no leaves. Under the
  access algorithm that means a set requires no roles unless explicitly overridden. This is not a
  special case -- it is the same conclusion the non-conjunctive access decision (R3.3) reached from
  the other direction, now consistent with the access layer's own algorithm.
- **R19.4 -- granting a product does not grant its members.** Auto-inheritance runs through
  `parents`, and sets have none. Counterintuitive enough that it must be documented, not left to
  be discovered.
- **R19.5 -- a sensitive member list uses the explicit-override path.** Knowing which studies are
  pooled can itself be confidential. The access layer already supports adding a specific artifact
  directly to the roles table to *add* requirements beyond what lineage implies (the embargo
  case). Sets need no new mechanism for this.
- **R19.6 -- `.access/` stays reserved, and stays safe by construction.** datom never reads,
  writes, or deletes there. The reservation was going to need an explicit refusal in the JSON-write
  export (R12.4a); with that export deferred, **datom adds no general-purpose write path at all**,
  so the guarantee remains structural rather than enforced -- verified 2026-08-18: `.access` appears
  nowhere in `R/`. Whoever revives the write export owns re-establishing the refusal.

### R20 -- Git is the history mechanism; anything history-shaped datom writes is a projection

- **R20.1 -- the rule.** Git owns history. Anything datom writes that *resembles* history exists
  **only as a projection for consumers who cannot read git**, is always **derived from git**, and
  is **never the source of truth**.
- **R20.2 -- the test.** *Would someone holding the repo use this file to answer a history
  question?* If yes, it is a smell.

  | Artifact | Test | Verdict |
  |---|---|---|
  | `version_history.json` | a developer would run `git log`; only a **reader** needs it, to map `version` -> `data_sha` without a clone | **keep** -- legitimate projection |
  | `manifest.json` | same: a discovery index for git-less readers | **keep** |
  | content-addressed payload filenames **in git** | a developer would have had to read history by listing filenames | **smell -- fixed by R6.1a** |

  The clearest illustration that `version_history.json` is a projection rather than a duplicate:
  it carries `author` and `commit_message`, which are **literally git commit fields**. Nobody with
  a clone would ever read them from there.
- **R20.3** Consequently no new hand-maintained history is introduced by this spec. Set payload
  history is git history (R6.1a/b); set version history is the existing `version_history.json`
  projection; no payload index and no per-payload log is added.

### R21 -- Version semantics, and the version-to-commit link

**Decision (option 1 of three considered):** a version stays **content-derived** for both artifact
kinds. The git commit is recorded **provenance**, not identity.

- **R21.1 -- what a version means, identically for tables and sets.** A version
  (`metadata_sha`) answers *"is this the same content and declared metadata?"* It is
  **code-invariant**: nothing code-derived enters it.
- **R21.2 -- the consequence, which is intended, not a gap.** The relationship is asymmetric:
  a data change necessarily changes the commit, but a commit change does **not** necessarily
  change the data. So **a code-only change that reproduces identical content mints no new
  version** -- a refactor, a comment fix, or an added script leaves `data_sha` and `metadata_sha`
  untouched, and the write is the existing idempotent no-op. This is already true for tables today
  and is deliberately kept true for sets.
- **R21.3 -- therefore one version maps to one-or-more commits**, and `commit_sha` records **the
  commit that first introduced that version**. The ambiguity is benign: the caller asked for a way
  to reproduce the version, and the recorded commit provably produces it.
- **R21.4 -- why not make the commit the version.** Considered and rejected. It is not directly
  possible (the commit contains the metadata that would name it -- the same circularity as a git
  commit not containing its own SHA), and a composite `(metadata_sha, commit_sha)` version would
  break `datom_read(version = )` taking a single string. **Also rejected: putting code/env content
  hashes into the payload** (which *would* avoid the circularity, since file hashes are knowable
  before committing). Reason: a set exists to be **citable**, and under that scheme a comment typo
  or a lint fix mints a new product version, so versions proliferate for semantically null changes
  and "product v47" stops carrying meaning. Reproduction is fully served by R21.3 instead.
- **R21.5 -- `commit_sha` lives in the `version_history.json` entry**, beside `author` and
  `commit_message` -- its siblings, also git facts projected for readers (R20.2). Note this has
  **zero identity impact and needs no volatile-list entry**: `metadata_sha` hashes
  `metadata.json`, not `version_history.json`.
- **R21.6 -- storage copy only, because of the write order.** The git copy of
  `version_history.json` is *inside* the commit it would have to name. So: local files -> commit
  -> push -> **upload the storage copy with `commit_sha` added**. That is the existing
  git-gates-storage ordering, one step tighter than dpbuild's (which needs a separate deploy pass
  because pins gives it no post-commit hook).
- **R21.7 -- derived, never authored.** This is the trap. `datom_validate(fix = TRUE)` re-uploads
  metadata from the clone, which would **silently strip `commit_sha`**. So the repair path must
  **re-derive** it from `git log` on the artifact path rather than dropping it. Both writers derive
  from git -- the write path from the commit it just made, the repair path from history -- so
  storage never holds unrecoverable state and the "mirror is always derived from git" invariant
  survives.
- **R21.8 -- repo holders need nothing stored.** With the stable-path payload (R6.1a),
  `git log -p {name}/set.json` gives version, diff, and commit together. The stored field exists
  purely for the git-less reader.
- **R21.9 -- precedent, recorded because it is confirmation rather than invention.** dpbuild keeps
  no commit hash in the product repo (its `.daap/daap_log.yaml` is inside the commit), and
  dpdeploy publishes it to a storage-side board log (`dpboard-log`) that dpi's `dp_list()` reads
  **with no git**. That log's composite key is `(dp_name, pin_version, git_sha)` -- an explicit
  acknowledgement that the same content version can pair with different commits, which is exactly
  R21.3. datom differs only in granularity: the per-artifact `version_history.json` already exists
  and already carries the sibling git fields, so no board-wide per-version index is added.

### R22 -- The v1 to v2 transition for existing repos

Added 2026-08-23 after the E2 design audit. R9's gate refuses a repo written by a **newer** datom.
This requirement covers the other direction -- a **current build meeting an older repo** -- which
the gate deliberately tolerates and which the R8.1 rename therefore breaks.

- **R22.1 -- the failure being prevented.** Every repo written before this spec keeps its artifact
  list under `tables` and carries no `schema_version` field. R9.1 tolerates an absent field as v1,
  so such a repo passes the check and then meets a reader looking for `artifacts`: `datom_list()`
  returns an empty frame, `datom_summary()` and `datom_status()` report zero, and nothing errors.
  Discovery goes blank while data access keeps working (`datom_read()` never touches the manifest,
  R9.2). Under the compatibility posture the disqualifier is the silence, not the severity.
- **R22.2 -- reads upgrade in memory.** `read file -> upgrade in memory -> use`. The file on disk is
  not modified by a read. This is what keeps **readers** working, and it is the reason a loud
  refusal is not an acceptable alternative: a reader has storage access and no git, so it cannot
  repair a repo it is refused from.
- **R22.3 -- writes upgrade on disk.** `read file -> upgrade in memory -> edit -> stamp
  schema_version -> write`. A write never tolerates an old shape and never stamps a version onto a
  document it did not upgrade first. Reusing the read-side toleration on the write side is how a
  file ends up with a v2-shaped entry under a v1 declaration: half in each format.
- **R22.4 -- one reader, and the two failure kinds are structurally different.** All manifest reads
  go through one internal helper. An **IO failure is returned** to the caller as data, so each
  caller keeps its own policy (abort with its own wording, or tolerate and report unavailable); a
  **schema refusal is thrown**. Task 4 established that a schema check placed inside an
  error-softening handler gets reworded or downgraded; returning one failure and throwing the other
  removes the handler the check could be placed inside, so the property holds by construction
  rather than by comment.
  **Qualified by Design A (2026-08-23).** "Thrown" is the response for **per-artifact metadata at any
  role**, and for **the manifest on the writer path**. On the **manifest reader** path a too-new
  version instead becomes warn-and-rebuild (R22.11) -- because that file is reconstructible and the
  other is not. What is invariant across all four cases, and is the actual point of this
  sub-requirement, is that **a schema outcome is never reported as an unreadable manifest**: it is
  either thrown or handled by its own deliberate path, never absorbed into the caller's IO handler.
  Until Task 22 lands the rebuild, the manifest reader throws like the rest; Task 22 is where this
  qualification starts to bite.
- **R22.5 -- one step per adjacent version pair, and a shipped step is frozen.** The upgrade is an
  ordered chain: `.datom_manifest_upgrade_v1_to_v2()` and, later, one function per subsequent pair,
  applied in sequence by a dispatcher that reads the declared version and runs every step up to
  current. No direct v1-to-v3 step is ever written: that shape needs one function per *pair* and
  grows with the square of the version count. **A step, once released, is never edited** -- it is
  written against files that exist unchanged in the world, so re-tuning it to a later shape
  converts them wrongly. Same discipline as the frozen sv1 goldens.
- **R22.6 -- two deliberate exclusions.** (a) `.datom_check_namespace_free()` keeps its own read and
  its own softening: it reads *another project's* manifest purely to name it in a refusal that has
  already been decided, so degrading to `<unreadable>` is correct there and a throwing check is not.
  (b) The four in-pipeline local reads stay excluded, on Task 4's principle that the check belongs
  where a document enters datom, so a refusal happens before work starts rather than partway
  through a write.
- **R22.7 -- one frozen fixture per historical schema version.** `tests/testthat/fixtures/`
  carries a preserved manifest per past version (`manifest-v1.json` first), plus a test that each
  upgrades cleanly to current. A file, not an inline fixture, so "do not sweep this to the new
  shape" is structural rather than a comment a sweeping author has to notice.
- **R22.10 -- the schema check runs BEFORE the upgrade chain.** Pinned because nothing in this
  requirement, design 10.2, I28 or P34 fixed the order, and only one order is correct: a v3 document
  on a v2 build has no v2-to-v3 step, so the dispatcher must never see it. Check first, then upgrade.
  Two implementation notes that belong with it, both about the dispatcher and neither about the spec:
  the loop must be guarded (`if (declared < supported)`) because R's `seq()` **counts down** when
  `from > to`, so an unguarded `seq(declared, supported - 1L)` runs the steps backwards on a
  current-version document; and a test must assert a current-version document runs **zero** steps,
  which is P34's identity clause made mechanical.
- **R22.11 -- the manifest's too-new response is asymmetric between roles.** A manifest declaring a
  version above what this build supports is **not** a dead end, because the manifest is derived:
  - **Reader**: warn once and **rebuild** from storage (R22.12). Survivable beats loud when the file
    is reconstructible.
  - **Writer**: **refuse.** Writes never limp.
  This self-selects correctly without extra logic: the rebuild reads per-artifact metadata, which is
  stamped and **not** rebuildable, so if the too-new release also changed metadata the rebuild aborts
  there anyway. Survivability is available exactly when the break was manifest-only.
- **R22.12 -- rebuild triggers, and what a rebuild must not do.** Rebuild when either (a) the expected
  artifact key is **absent** -- never when it is merely *empty*, which is what a new repo and a
  truncated file both look like -- or (b) the declared version is above `.datom_supported_schema`
  (R22.11). A storage-only reader rebuilds **in memory for that session** and writes nothing. It
  **warns once**, pointing at the upgrade: a silent repair is a silent degradation, which is the
  failure this whole section exists to remove.
  **The rebuild reads the recorded version id; it never recomputes one.** `version_history.json`
  entries already carry `version` (`R/read_write.R:485`). Recomputing through
  `.datom_compute_metadata_sha()` walks straight into the denylist defect (#100) in precisely the
  scenario the rebuild exists for -- an older build reading a repo a newer one wrote -- and would
  publish a `current_version` matching no version in the history, which is worse than the empty list
  it replaced.
- **R22.9 -- which files may break, and which may never.** The two documents are not equivalent and
  future changes must not treat them as such.
  - **The manifest may break.** It is **derived**: every fact in it also exists in the per-artifact
    metadata and the storage listing, so a build that cannot read it can rebuild one. That is what
    makes an escape hatch possible there.
  - **Per-artifact metadata may never break.** It **is** the source of truth, so there is nothing to
    rebuild it from, and a legacy-shaped second copy backfires: change detection recomputes identity
    from the stored file (`R/read_write.R:343`), so a copy in a different shape hashes differently
    from the recorded version and an older build mints a version on every run. For that file the
    forward-compatibility rules are absolute -- additive only, forever.
  - Recorded because **this spec has the division the right way round by accident**: it breaks the
    file with an escape hatch (the manifest key rename) and only adds to the file without one
    (`kind`). The next change should have that shape on purpose.
- **R22.8 -- the missing-`kind` question, decided.** Counters filter on `kind == "table"` and add
  **no** fallback for an entry with no `kind`, because R22.2 guarantees every entry has one by the
  time any counter runs. The alternative (treat absent as `"table"`) was rejected: it would make a
  read path that forgot the upgrade produce roughly-correct numbers instead of visibly wrong ones,
  which hides exactly the class of mistake this spec is trying to make loud. Owner-decided
  2026-08-23; reversible in one line if a real case for tolerance appears.

### R23 -- Writer-side forward-compatibility controls

Owner-decided 2026-08-23. R22 keeps **readers** working across a format change. This requirement
stops **writers** that would corrupt a repo they do not fully understand. The asymmetry is deliberate
and already in the design: reads limp, writes stop.

- **R23.1 -- an unrecognised field refuses the write.** Before writing, a build inspects the
  top-level keys of each datom-owned document it is about to modify. A key it cannot classify --
  neither in its identity list nor on its documented excluded list -- means a newer build wrote this
  document. **Refuse.** No version comparison, no configuration, no network: the evidence is in the
  file.
  Scope, so it neither over- nor under-fires: **top-level keys only**, on documents datom owns
  (per-artifact `metadata.json`, manifest entries, manifest top level). `custom` is **opaque** -- it
  holds arbitrary user keys by design and is classified as a whole.
- **R23.1a -- EVERY document the write-entry sequence inspects is the CLONE's copy.** This governs the
  whole sequence, not one step of it: **the manifest at step 3** (the schema check and the upgrade
  chain) and **all three documents at step 5** (the vocabulary check). `.datom_read_manifest()` takes a
  scope, so the entry sequence must name one, and it names the clone.
  Named explicitly for two different reasons at the two steps. At **step 5** the sequence does not
  otherwise have the per-artifact document in hand at all: `datom_write()` does not touch stored
  artifact metadata until pipeline step 4, inside `.datom_has_changes()` (`R/read_write.R:334-343`), so
  an unspecified scope means an implementer checks only the manifest -- dropping the check from the
  document that matters most, since per-artifact metadata is never rebuildable and is where identity
  lives. At **step 3** the default pull is the opposite one: the too-new-repo framing reads as
  storage-flavoured and every check Task 4 wired was, so an unstated scope would land on storage --
  adding a network read to every write and checking the wrong copy.
  **The clone is right at both steps for the same four reasons.** It is the document the write
  actually mutates (`.datom_update_manifest_entry()` edits `{conn$path}/.datom/manifest.json`,
  `R/sync.R:818`); it is a local file read rather than a round trip on every write; it is where a newer
  collaborator's work lands after a pull; and storage cannot legitimately be ahead of git (I5).
  All three documents exist as local files in the clone: `{conn$path}/.datom/manifest.json` and
  `{conn$path}/{name}/metadata.json` (`R/read_write.R:463-469`, committed via `git_paths`). So the
  check is a **local file read, no network**, and it works for every write route including the
  mirror-everything one, where the set of artifacts is not a single name.
  **Why the local copy is the right target, not a compromise.** A newer build writes git first and
  storage after (I5), so a document written by a newer build reaches the clone by a pull -- which is
  exactly the handoff this check exists to catch. Storage cannot legitimately hold a newer document
  than git; if it does, that is drift, which is `datom_validate()`'s job and has its own detection.
  Two alternatives rejected: an extra storage GET at entry (a second read of an object
  `.datom_has_changes()` reads anyway, and N reads on the mirror-everything route), and moving the
  per-artifact half of the check down to pipeline step 4 (still before any mutation, but it would make
  design 10.7's "before any hashing" false for one check, and the reader would have to notice).
- **R23.2 -- the vocabulary list is APPEND-ONLY, and this is the discipline everything else rests
  on.** A build must never stop recognising a field name that has ever existed in a datom document,
  **including names it no longer writes**. Retire a name by marking it retired, never by removing it.
  A build that forgets a name meets an older file, fails to classify a key it should know, and
  refuses it -- **blocking the upgrade direction**, which is the one direction that must always work.
  Same freeze rule as a released upgrade step (I30), and it carries the same weight.
- **R23.2a -- why the good direction is structurally safe.** A newer build's vocabulary is a superset
  of every older one's, so it can never meet a name it does not know. The check is therefore
  incapable of firing on the upgrade path, and **no directional logic is required** -- do not write a
  special case for it, and do not add one later "for safety": it would be dead code guarding an
  unreachable state.
- **R23.3 -- a repo may declare a minimum writer version, and every build from 0.1.1 reads it.**
  Optional field in `project.yaml`; **absent means no floor**, so no existing repo changes behaviour.
  A writer below the declared version is refused. Expressed as a **package** version, not a schema
  number: the number does not move for a writer-breaking-but-reader-safe change (R9.5), so it cannot
  carry this, and a package version directly answers the question a refusal raises.
  **The reading half ships now even though it may never be set**, because it cannot be retrofitted --
  a build that does not look for the field can never be bound by it, which is exactly why nothing can
  stop a 0.1.0 writer. Deferred with the rest of the mechanism: a purpose-built verb for raising it
  (a normal commit cannot validate that the raiser satisfies the new value, and the R15 precedent is
  named verbs over generic writes), plus tooling and docs.
- **R23.3a -- one home, no mirror.** `project.yaml` only, git-tracked. **Not** the manifest: the
  manifest is derived, and a rebuild could not recover a policy field that exists in no other file
  (R22.9). Repo level is the right granularity -- per-artifact would leave a repo half-writable, and
  per-namespace is the same thing, since repo, namespace and manifest are 1:1:1 (R17.1). It rides on
  the connection, since `datom_get_conn()` already parses that file, so the check costs no extra read.
  One guard: whoever sets it must already satisfy it.
- **R23.4 -- a writer refuses when the expected key is still absent AFTER the upgrade chain has
  run.** The discriminator is not the key, it is whether the chain can **reach** the shape:

  | Situation | Chain | Writer |
  |---|---|---|
  | v1 repo, current build | runs, key appears | **write** (forward) |
  | future-shaped repo, older build | runs, key still absent | **refuse** (backward) |

  Stated this way because "refuse when the expected key is absent" would deadlock the v1-to-v2
  upgrade itself -- a 0.1.1 writer meeting a v1 repo finds `artifacts` absent and would refuse
  forever, so no repo could ever be upgraded. Without the refusal half, two builds flip the manifest's
  shape back and forth in git history, each seeing a rebuild warning on the other's turn.
  Note the deliberate asymmetry: **the same condition, opposite responses.** Key absent after the
  chain means *rebuild* for a reader (R22.12) and *refuse* for a writer. That is the reads-limp /
  writes-stop split, and it is not an inconsistency.
- **R23.5 -- the two mechanisms cover complementary sets, and neither is sufficient alone.** Say so
  wherever either is documented, so neither is oversold:

  | Change | Caught by |
  |---|---|
  | field added | **vocabulary** (R23.1) -- the number does not move |
  | field renamed | **vocabulary**, and the number too |
  | field removed | **number** (R9.5) -- the old name is still in an append-only vocabulary, so nothing looks unrecognised |
  | type or meaning change | **number** -- no new name appears |
  | container restructured | **number** -- no new name appears |
  | policy block for a non-format reason | **floor** (R23.3) only |

- **R23.6 -- the accepted cost.** Every release that adds any field to a datom-owned document forces
  a fleet-wide **writer** upgrade, including a purely cosmetic addition. Accepted knowingly: writes
  are infrequent, done by few people, and they change content. **A false refusal costs one person an
  install; a miss costs corrupted data**, so refusing too often is the right direction to err.
  Recorded because it inverts the intuition that additive changes are free -- they are free for
  readers only, and R9.7 says so next to the rule that generates the intuition.
- **R23.7 -- enforcement begins at 0.1.1; 0.1.0 writers cannot be stopped.** 0.1.0 has no schema
  check, no vocabulary check, and no floor read (verified: zero occurrences on `main`), and none can
  be added to a released build. Every write-side refusal in this requirement protects against builds
  **from 0.1.1 forward only**. State it plainly wherever the refusals are described -- the spec
  currently writes "an older build writing into a newer repo" without separating the population that
  can be stopped from the one that cannot. For 0.1.0 the remedy is a NEWS entry, not engineering: it
  cannot be made to fail loudly from inside, and the only lever that would -- relocating the manifest
  so 0.1.0's existing "could not read manifest" abort fires -- costs a storage-layout change, a
  `datom_validate()` change (`R/validate.R:236-238`) and two filenames carried forever. 0.1.0 is under
  CRAN review with no reverse dependencies; the exposed population is the team.
- **R23.8 -- unrecognised fields are carried forward, not dropped.** Where a write is permitted at
  all, a build must preserve top-level keys it does not recognise rather than rebuilding the document
  from scratch and silently deleting them. Applies at **three** levels: per-artifact metadata
  documents, manifest **entries**, and manifest **top-level** keys. The reason is **information
  loss**, not churn -- churn settles after one version per handoff either way, because a build that
  deletes the field agrees with itself on its next run. Today most such fields are recomputable; the
  rule exists for the ones that will not be. Test by asserting a field **survives a round trip**
  through a write, not by counting versions.

---

## 5. Acceptance criteria

These are the behaviors most likely to be silently mis-implemented. **Each gets a test.**

| # | Criterion |
|---|---|
| **AC1** | **Reader role, no git -- and "resolve" means two different things, tested separately.** (a) **Resolve the pointers**: a storage-only connection (no `github_pat`, no clone) can `datom_read_set()` and get back the member records. This always works and is the primary use case -- the "git-canonical" framing must not lead to requiring a clone. (b) **Resolve to data**: reading a member's actual content needs a connection scoped to *that member's* project -- same-project members work through the same connection; cross-project members require the caller's connection (or, later, the governance register). Conflating (a) and (b) is how this gets mis-implemented as "reading a set requires access to everything in it". |
| **AC2** | **Idempotent re-write -- on the whole payload, not just members.** Writing an identical **payload** (members *and* their tags) to the same set name is a no-op -- dedup on set `data_sha`, no new version appended. **Converse, tested alongside it**: an identical member list with a *changed tag or description* is **not** a no-op and **does** mint a new version (R2.6/Q1). Both halves are needed -- the original wording said "identical member list", which under whole-payload hashing would have been wrong. |
| **AC3** | **Version sensitivity.** A set whose member *names* are unchanged but whose member *versions* advanced **must** produce a new `data_sha` and a new version. Do not "optimize" this away. |
| **AC4** | **Name uniqueness across kinds.** Writing a set with the name of an existing table (or vice versa) is refused. **Mechanism**: the check reads `{name}/.metadata/metadata.json` from **storage** and compares `kind` -- not the manifest, which can lag behind a partially-completed write. This is the same source `.datom_has_changes()` already consults, so the check costs no extra round-trip. Stated explicitly so it is not decided by accident. |
| **AC5** | **Empty set refused; single-member set legal.** `datom_write_set()` with zero members **aborts** (R2.8/Q3), mirroring `.datom_canonical_hash()`'s refusal of zero-row/zero-column tables. A one-member set is legal and hashes normally. The refusal is the *tested* behavior, not a documented maybe. |
| **AC6** | **`datom_read()` on a set** aborts with a message pointing at `datom_read_set()`, not a cryptic missing-parquet error. |
| **AC7** | **Schema gate fires, both directions.** *Refuse-newer*: a repo declaring `schema_version: 3` aborts with the upgrade message, at **both** entry points (manifest and per-artifact metadata). *Tolerate-older*: a repo with no `schema_version` field behaves exactly as 0.1.0 did. **Mechanism note**: an actually-installed 0.1.0 reader has no gate to fire, so this is not testable by installing an old version -- the test drives `.datom_check_schema_version()` directly with a fixture declaring a version above `SUPPORTED_SCHEMA`. Test the gate, not the archaeology. **Second mechanism note, added 2026-08-23**: the *tolerate-older* half is not satisfied by the gate alone once R8.1 lands, because a tolerated v1 manifest still holds its list under the old key. What makes this clause true is the upgrade in R22, and what tests it is AC30. Before that was noticed, this criterion and P10 were both recorded as met by Task 4 while the rename was queued to falsify them. |
| **AC8** | **Lineage isolation.** A set's metadata contains no `parents` and no `source_lineage` (**omitted, not null**), and writing a set does not alter any member's lineage. |
| **AC9** | **Self-reference refused.** Writing a set that lists itself (any version of itself) as a member is refused at write time with a clear error (R4.5). Note this is a nonsense check, **not** cycle detection -- cycles are structurally impossible (R4.4), so there is deliberately no cycle test and no depth test. |
| **AC13** | **Write/read hash agreement, plus what is and is not identity.** Split into two levels, because the earlier single-umbrella wording was unsatisfiable for some fixtures -- (g) has no payload and no `data_sha` at all, and (e) cannot be built through the public path since R2.14 refuses it. **AC13-P, payload level** (the umbrella applies: `data_sha` from the in-memory payload equals `data_sha` recomputed after the payload has been stored and read back with `simplifyVector = FALSE` -- covers R2.5): **equal** for (a) tag-value **order**, (b) tag-value **duplication**, (c) **member order**, (d) **single string vs one-element array**; **different** for (f) **NFC vs NFD** spellings of visually identical tag text (R2.16). **AC13-E, encoder level** -- called against the encoder directly, *not* through `datom_write_set()`, since the write path tidies or refuses these before the encoder sees them: (e) a member listed twice with identical `id` **and** `tags` hashes **equal** to one entry (R2.14), (g) `strset(character(0)) == h(0x02)` as a pinned constant (R2.17). Note (c) and (d) each **reverse** an earlier fixture that required a difference. (f) **must use `\u` escapes**, not literal non-ASCII bytes -- these fixtures ship in `tests/`, and `R CMD check --as-cran` must stay at zero warnings (AC11). Number and boolean cases are not applicable -- see AC27. |
| **AC29** | **Canonicalization happens before the local write, and one `data_sha` keeps one byte spelling.** (a) A payload supplied with unsorted tag values, a duplicated tag value, an array-wrapped single value, and unsorted members is written to `{name}/set.json` in canonical form -- assert on the **file bytes**, not the return value (R2.15). (b) Re-writing a payload whose `data_sha` is already in history does **not** re-upload and does **not** recompute `document_sha`; the recorded value is carried forward and the stored object is untouched (R7.5 rule 1). (c) `datom_validate(fix = TRUE)` on such a repo leaves the stored payload bytes and the recorded `document_sha` unchanged, and a subsequent version-pinned read still verifies (R7.5 rule 2). (c) is the clause a naive implementation fails while passing (a) and (b). |
| **AC14** | **`datom_read_set()` on a table** aborts pointing at `datom_read()` -- the converse of AC6, not a missing-payload error for a healthy table. |
| **AC15** | **Nesting resolves one level -- no traversal.** Reading a set whose members include another set returns a **pointer** to that inner set (`kind = "set"`, name, project, version), and does **not** fetch the inner set's own members. Asserted by observing that no storage read of the inner set's payload occurs. Covers R4.3, and guards against an implementer "helpfully" flattening the tree. |
| **AC16** | **Machine-commit isolation.** In a `mode: product` repo with an uncommitted edit at `R/foo.R`, a `datom_write()` of a table produces a commit whose tree does **not** contain the `R/foo.R` change, **and** `R/foo.R` is still dirty in the working tree afterward. Both halves matter: the second catches a "helpfully" cleaned working tree (R14.1). |
| **AC17** | **`datom_repo_commit()` semantics.** `paths = NULL` stages a mixed tracked/untracked change set **minus** gitignored files; explicit `paths` stages exactly those; a reader conn is refused; nothing-to-stage creates **no commit** and is not an error; `push = FALSE` leaves the remote untouched. **Plus the R15.5 qualification**: with a clean tree, `push = TRUE`, and the branch ahead of the remote, no commit is created **but the push still happens** -- assert the remote advanced (R15). |
| **AC18** | **`include_paths` produces one joint commit.** A set write with `include_paths` creates **exactly one** commit containing payload + metadata + the listed paths, and the storage mirror afterward contains **only** datom artifacts (R12.5). |
| **AC19** | **Idempotent re-write stays a no-op under dirty `include_paths`.** Re-writing an identical **payload** (members *and* tags -- R2.6) while `include_paths` files have changed creates **no commit and no new version**, and emits the informational message pointing at `datom_repo_commit()` (R12.5). This is AC2 defended against a side channel. Note the payload must be identical for this to apply: a tag edit *does* mint a version, and then the `include_paths` content is committed with it legitimately. |
| **AC20** | **`include_paths` refused early -- two distinct gates, two separate test cases.** (a) A **nonexistent** path is refused; (b) a path **overlapping** a datom-owned path (`{artifact}/**`, `.datom/**`) is refused. Both **before any hashing or IO** (R12.5), consistent with the R10.3a gate placement. Kept as one criterion but **tested as two cases**, so a regression identifies which gate broke rather than only that one of them did. |
| **AC21** | **`datom_repo_push()` is convergent.** With unpushed local commits it advances the remote; called again immediately it is an informational **no-op, not an error**; a reader conn is refused; it inherits the on-a-branch guard (R15.8). |
| **AC22** | **Namespace separation is enforced, not merely documented.** Initializing a `mode: product` repo into a namespace that already holds another project's manifest is **refused**, with a message naming the occupying project and pointing at using a distinct prefix (R17.3). |
| **AC23** | **RETIRED 2026-08-18 -- no test required.** It asserted that the JSON-**write** export refuses a `.access/` key; that export is deferred (R12.4a), so the behaviour has no implementation to test. Reads were never in its scope. Revive it with the export. |
| **AC24** | **The git payload is diffable.** After writing a set twice with one member added, `git diff` on `{name}/set.json` between the two commits shows the **member-level** change (one added entry), not a whole-file add. Guards R6.1a/b -- a content-addressed git filename would make this test impossible to write. |
| **AC25** | **`commit_sha` is present, git-less, and survives repair.** After a set write: the **storage** copy of `version_history.json` carries `commit_sha` for the new version; the **git** copy does not (it cannot -- it is inside that commit); and after `datom_validate(fix = TRUE)` re-uploads metadata, `commit_sha` is **still there**, re-derived from `git log` rather than stripped (R21.6/R21.7). The third clause is the one that fails silently in a naive implementation. |
| **AC26** | **A code-only change mints no new version.** With the set's member list unchanged, modifying tracked code and re-running `datom_write_set()` produces **no new version**, and the existing version's recorded `commit_sha` is **unchanged** (still the first producing commit). Encodes the option-1 decision (R21.2/R21.3) so a later "improvement" that makes versions code-sensitive fails a test. |
| **AC27** | **The payload grammar is enforced, not assumed -- and only where refusal is warranted.** Tested **per case**, never as one lumped assertion, so a regression names which one leaked. **Refusals**: (a) a tag value that is a number, logical, factor, function, or nested list, message naming the offending key and the allowed types (R2.11); (b) `NA` (R2.7); (c) an empty-string tag value `""`; (d) **the same `id` listed twice with different `tags`**, message naming the member and pointing at the multi-valued form; (e) zero members (R2.8). **Tidy assertions, not refusals** -- each of these must be silently normalized and must NOT abort (R2.14, and see AC29a for the byte-level assertion): tag-value order, tag-value duplication, single-vs-array shape, member order, an exact-duplicate member, and `character(0)` dropping its key. **Plus the case that must be ALLOWED** (R2.14a): the same `project`+`name` at two different `version`s writes successfully with both members present. That last one has its own test because `project`+`name` looks like the natural duplicate key, and the first reader to tighten the check to it would break a legitimate use silently. **Ownership**: per-member grammar (a, b, c) belongs to `.datom_validate_members()`; the payload-level cases (d, e), set-level `tags` grammar, and every tidy assertion belong to `datom_write_set()`, which is the only place that sees the whole payload. This is the test that keeps I24 true -- without it, "just allow numbers" is a one-line change nobody notices. |
| **AC30** | **An existing repo still reads after the rename.** A **frozen fixture** at `tests/testthat/fixtures/manifest-v1.json` -- no `schema_version`, artifact list under `tables`, one real table entry -- yields a **non-empty** result from every manifest reader, with the entry reported as `kind = "table"` (R22.2, R22.7). Asserted before the rename and again after it, from the same file. **Mechanism note**: the fixture is a file precisely so that a sweep of `tables` to `artifacts` across the test suite cannot quietly rewrite the evidence. Two existing tests do the same job inline and must **not** be swept (`datom_list` / `datom_summary` "tolerates a manifest with no schema_version"); a third of the same name asserts on an *empty* block, so it passes either way and needs a non-empty counterpart for the clone-copy readers. |
| **AC31** | **A write into an existing repo upgrades the file, and the counters do not collapse.** After one table write into a v1 repo: the manifest carries `artifacts`, carries **no** `tables` key, declares `schema_version: 2`, and `summary$total_tables` counts **every** pre-existing artifact rather than only the one just written (R22.3). The counter clause is the one a naive implementation fails: adding an entry under the new key while the old key sits untouched leaves a twelve-table repo reporting `1`, in a file that is now half in each format. |
| **AC32** | **An unreadable manifest and a too-new manifest are different failures, at every reader.** Through the single reader (R22.4): an IO failure preserves each caller's current behaviour -- `datom_list()` and `datom_summary()` abort with their own wording, `datom_status()` tolerates it and reports the manifest unavailable -- while a manifest declaring an unsupported version is **never** reported as an unreadable manifest at any of them, including `datom_status()`. Both halves in one criterion because the regression is a trade between them: making the schema outcome reach every caller must not make an ordinary storage failure fatal, and vice versa. **Deliberately says nothing about which outcome the schema case produces** -- that is AC37b's job, and it differs by role and by task. This criterion asserts only that the outcome is **its own**, never the IO path's: not reworded as "could not read manifest", not downgraded to a warning about storage. So it holds unchanged before and after Task 22, where the manifest reader's response changes from abort to warn-and-rebuild. **Simplified 2026-08-23** from a version that spelled out both behaviours and therefore changed shape at a task boundary -- the same insight already applied to P35: the invariant was never the abort, it was that the schema outcome is not disguised as an IO failure. |
| **AC28** | **The `document_sha` integrity gate fires, and never silently skips.** (a) A set whose stored payload bytes do not match the recorded `document_sha` is **refused before parsing** -- assert the abort occurs without the payload being parsed. (b) Metadata with a **missing or empty** `document_sha` is an **error, not a skip** (R7.1, I3): sets have no legacy population, so reproducing `parquet_sha`'s pre-cv1 grace would be building a silent-degradation path on purpose. Both halves matter, and (b) is the one a naive implementation gets wrong by copying `.datom_read_parquet()`'s `if (!is.null(...) && nzchar(...))` guard. |

| **AC33** | **Identity hashing is an allowlist, and it is behaviour-preserving.** (a) Every existing `metadata_sha` is unchanged -- asserted against **pinned values**, not merely a green suite. (b) A metadata document carrying an **unknown extra field** hashes identically to one without it. (c) A document **missing** an optional field (`parents`, `source_lineage`, `original_file_sha`, `custom`) hashes to today's value for that document. (d) **The classification test**: every field any metadata builder can emit -- table **and** set -- is classified, in the hash list or on the documented excluded list. An allowlist fails the **opposite** way from a denylist (a denylist silently *includes* an unknown field; an allowlist silently *excludes* a new one, so identity stops responding to real content changes), and (d) is the only clause that catches that direction. |
| **AC34** | **Unrecognised fields survive a write.** A document carrying a top-level key the build does not recognise still carries it after that build writes the artifact -- at all three levels (per-artifact metadata, manifest entry, manifest top level). Asserted as a **round trip**, not as a version count: churn settles either way, and the property at stake is that information is not destroyed (R23.8). |
| **AC35** | **The writer refuses what it cannot classify, and never on the upgrade path.** (a) A document with an unrecognised top-level key refuses the write, naming the field. (b) `custom` contents are **not** treated as unrecognised, however exotic. (c) A **retired** name still classifies, so an older document does not refuse -- the append-only rule (R23.2) made mechanical. (d) The forward path never refuses: a current build writing a v1-shaped repo proceeds, which is R23.4's first row and the case a naive "refuse when the key is absent" rule would have deadlocked. (e) **The check covers per-artifact metadata, not only the manifest** -- an unrecognised key in the clone's `{name}/metadata.json` refuses the write, with no storage read required (R23.1a). This clause exists because an implementation that checks only the manifest passes (a) through (d), and the per-artifact document is the one that is never rebuildable. |
| **AC36** | **The floor is read and enforced, and absent means absent.** (a) A repo whose `project.yaml` declares a minimum writer version above the running build refuses the write, naming the required version. (b) A repo with **no** floor field behaves exactly as before -- no warning, no refusal, no change of any kind. (c) Setting a floor above the setting build's own version is refused. |
| **AC37** | **The rebuild fires on absent and on too-new, never on empty, and never recomputes identity.** (a) A manifest with the expected artifact key **absent** yields a correct non-empty listing plus exactly **one** warning naming the upgrade. (b) A manifest declaring a version **above** what the build supports yields the same for a **reader**, and a **refusal** for a **writer** (R22.11). (c) A **genuinely empty** repo triggers no rebuild and performs **no storage listing** -- asserted on the absence of the listing call, not on the result. (d) A **corrupt** manifest still fails visibly. (e) The rebuilt `current_version` for every artifact equals the `version` **recorded** in `version_history.json`, never a recomputed hash (R22.12). (f) A rebuilt index matches the on-disk one field for field on a healthy repo, `original_format` included. |
| **AC38** | **The upgrade chain runs after the check, and runs zero steps when there is nothing to do.** (a) A document declaring a version above `.datom_supported_schema` never reaches the dispatcher -- asserted by observing the abort's condition class, not by inspecting the document. (b) A **current-version** document runs **zero** upgrade steps, which catches the `seq()` counts-down defect (R22.10). (c) Applying the chain twice equals applying it once. |

Plus the standing project gates:

- **AC10** Full `devtools::test()` suite green, count reported in every commit message, count
  never drops. Baseline at spec start: **2460** (verified by two `devtools::test()` runs on
  `dev` @ `b57cdba`: `FAIL 0 | WARN 0 | SKIP 0 | PASS 2460`).
- **AC11** `R CMD check --as-cran` at 0 errors / 0 warnings (the one pre-existing NOTE is
  acceptable).
- **AC12** E2E workflow run before spec completion (per Operational Discipline item 5): a new
  offline `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`, asserting every claim and
  exiting non-zero on mismatch.

---

## 6. Out of scope

| Item | Disposition |
|---|---|
| Flattening a collection into a long-format table | Rejected -- see design.md "Alternatives considered" |
| Building the collection in the build package instead | Rejected -- composability loss is unworkaroundable |
| Sibling `manifest$sets` node | Rejected -- makes cross-kind name collision representable |
| Renaming `parquet_sha` to a kind-neutral name | Rejected -- would silently disable integrity verification in released readers |
| Dual-writing `tables` alongside `artifacts` for one release | Rejected -- exposure is discovery-only; permanent schema clutter not worth it |
| Bespoke canonical regime for `metadata_sha` itself | **File separately.** The emitter-drift argument already applies to `metadata_sha` today (it hashes `jsonlite::toJSON(auto_unbox = TRUE)` output). This is a pre-existing exposure and expanding this spec to cover it is out of scope -- see design.md "Surfaced latent concern". |
| datom knowing the term "product" | Out of scope by design. `set` is datom's word; "product" belongs to the build package. A domain-neutral primitive that downstream packages give domain meaning to is the correct layering, and it keeps the door open for non-data-product uses. |
