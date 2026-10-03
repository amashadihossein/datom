# Check a Document's Declared Schema Version

Reader-side compatibility check for one metadata or manifest document.
Called wherever such a document enters datom from storage or from the
local clone, so that a repo written by a *newer* datom fails with an
actionable message instead of degrading silently – an older reader would
otherwise find none of the fields it expects and report an empty repo.

## Usage

``` r
.datom_check_schema_version(
  meta,
  source,
  operation = c("read", "write"),
  supported = .datom_supported_schema
)
```

## Arguments

- meta:

  Parsed document (a named list). A non-list or `NULL` is treated as
  carrying no `schema_version`, i.e. v1.

- source:

  Path or key of the document, used in the message so the user knows
  which file is too new.

- operation:

  What the caller was about to do – `"read"` (default) or `"write"`. It
  only selects a word in the refusal message. An argument with a default
  rather than a required one, so that every existing call site and the
  message text they assert on are unchanged: without it a refused write
  said the format was one "this build cannot read", which is the wrong
  verb for a write that was stopped at the door.

- supported:

  Highest version this caller can interpret, defaulting to the repo-wide
  `.datom_supported_schema`. It feeds the comparison **and** the
  message, so a refusal never says "supports up to v2" while refusing a
  v2 file.

  The rule that predicts an override, so a future caller can derive it
  rather than remember it: a document **datom writes** takes the
  repo-wide ceiling; a document that outlives the build that created it
  and is then **edited by hand** gets its own. The shared number holds
  while every document on it is machine-written by one build in one
  operation. `.datom/project.yaml` is not – it is stamped once at init
  and hand-edited afterwards – so it carries `.datom_project_schema` and
  is checked through
  [`.datom_check_project_schema()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_project_schema.md),
  which is where that pairing lives.

## Value

Invisible resolved schema version as an integer. Aborts otherwise.

## Details

The check is deliberately asymmetric:

- **Newer than this build** – abort, pointing at the upgrade. Continuing
  would mean interpreting a format this build does not know.

- **Absent** – treated as v1 and tolerated, so every repo written before
  `schema_version` existed keeps working unchanged.

- **Equal or older** – proceed.

A present-but-unusable value (a string, a fraction, `NA`, a vector)
aborts as a corrupt document rather than being coerced. Coercion here
would compare garbage against the supported version and could silently
read as "supported"; and in R a comparison against `NA` propagates into
`if()` as an opaque "missing value where TRUE/FALSE needed" error rather
than anything a user can act on.

Both aborts carry a condition class so every call site is provably the
same failure: `datom_schema_unsupported` for a too-new document,
`datom_schema_invalid` for an unusable value.
