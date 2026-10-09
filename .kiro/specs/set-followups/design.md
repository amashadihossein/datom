# Design -- set follow-ups

## 1. Facts checked against the code (2026-10-08, `dev` at `8b8e37b`)

- `.datom_find_member(members, name, tags = NULL, version = NULL)` is defined in
  `R/set-members.R` (~line 424). Callers: `.datom_member_record()` in the same file (the resolver
  behind `datom_fetch_member()`), the shared selector in `R/set-edit.R` (~line 199, used by
  `datom_remove_members()` / `datom_update_members()`), and `datom_parent(x = )`'s resolver in
  `R/lineage.R` (~line 239). Roxygen links to it also sit in those files.
- No exported `datom_find_*` exists. `datom_get_*` exports all read storage, which is why the new
  verb is not called `get`. `datom_member()` (build a pointer) and `datom_fetch_member()` (download
  what a member points at) are taken.
- `.datom_supported_schema <- 2L` (`R/utils-validate.R`). It is absent from tags `v0.1.1` and
  `v0.1.2`, and present in `v0.2.0`, so 0.2.0 is the first release that writes and checks formats.
- The five upgrade messages: `R/utils-validate.R` (`datom_schema_unsupported`),
  `R/manifest-rebuild.R` (rebuild warning), `R/forward-compat.R` (writer floor
  `datom_writer_floor`, unknown field, restructured file).
- `dev/check-spec.R` defaults to `.kiro/specs/datom-sets` and cannot distinguish one spec's `AC<n>`
  from another's (README Backlog), which is why R3's numbers go into the datom-sets spec.

## 2. `datom_find_member()` (R1)

One function. The top of the body resolves `x`:

```r
if (inherits(x, "datom_set")) x <- x$members
if (!is.list(x)) cli::cli_abort(..., class = "datom_not_a_set")  # reuse the existing class if it fits
```

then the existing body runs unchanged. The argument formerly named `name` becomes `member`, matching
`datom_fetch_member()`; internal callers pass it positionally or are updated. Accepting only a
**name** (not a record or link) is deliberate: a caller holding a record already has the answer.
Check what an empty list or a member list element of the wrong shape does today and keep it.

## 3. `?datom_schema` (R2)

A roxygen-only topic (`@name datom_schema`, `NULL` object, or attached to a docs file), so it is
reachable as `?datom_schema` from an installed package. The table:

| Format (`schema_version`) | Written by | Read by |
|---|---|---|
| 1 | every release before 0.2.0 (no field; absence means 1) | all releases |
| 2 | 0.2.0 and later | 0.2.0 and later |

Plus: the number moves only on a change that would break a reader (rename, removal, meaning or type
change, restructure), never for an added field, so a new row is rare. `datom_version` in a file is
which release wrote it, not which one is needed.

Message lines (cli), for the four format-related refusals:

```
i Upgrade with install.packages("datom"), or remotes::install_github("amashadihossein/datom") for a development build.
i See ?datom_schema for which datom version reads this repo.
```

Tests that match on the old `install_github` text are updated to the new text; condition classes do
not change.

## 4. AC42 / AC43 (R3)

Edits to a completed spec are additive and labelled. The appended datom-sets task says, in one line,
that it was added on 2026-10-08 by `set-followups` to give two pre-existing tests their gate, ships no
behaviour, and owns AC42/AC43. The issue cites the tests at `test-write-set.R:878` (metadata field
set) and `:498` (hand-assembled list refused); line numbers may have moved.

## 5. Invariants

- No behaviour change to member lookup, fetch, edit, or `datom_parent()` -- only a name.
- No condition class changes in the upgrade messages.
- No `R/` source cites `dev/` or `.kiro/`; `?datom_schema` and NEWS are self-contained.

## 6. Model escalation

None flagged as required. Optional: a test-coverage review before close-out.
