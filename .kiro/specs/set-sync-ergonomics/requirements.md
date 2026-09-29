# Requirements -- set sync ergonomics

**Issue**: [#121](https://github.com/amashadihossein/datom/issues/121).
**Branch**: `spec/set-sync-ergonomics`, cut from `dev` at `7d55a8b`. **PRs into `dev`, not `main`.**
**Test baseline**: 4282 (measured on `dev` at `7d55a8b`, 2026-09-27).

## Source

An owner prompt written with Claude Code (kept untracked, `dev/archive/`), then reworked point by
point with the owner in chat on 2026-09-27. **This document is self-contained**: every decision below
was agreed in that exchange, and where it differs from the prompt, this document wins.

## Goal

Building and refreshing a set follows the same pattern tables already use: **map** what the sources
have, **review** it as a data frame, **apply** it. `vignettes/citable-sets.Rmd` then has no loops and
no hand-editing of a member list.

Today the vignette builds a set by hand in four places: a loop over `datom_list()` to register every
input; `x$members <- c(x$members, ...)` to add the output; a manual version lookup through
`datom_list_members()` before each `datom_parent()`; and a refresh that can only move members already
in the set, so a table newly onboarded in a source is never picked up.

## Terms

- **source**: a project a set pulls its inputs from, given as a connection.
- **the set's own project**: the product repo that owns the set. Its members are outputs.
- **input** / **output**: a member labelled `type = "input"` / `type = "output"`.

## Requirements

### R1. One pair of sync verbs, two contexts

- R1.1 `datom_sync_manifest()` and `datom_sync()` keep their names. In a `mode: product` repo they
  work on the repo's set; in an ordinary repo they work on files exactly as today.
- R1.2 **The repo decides the context, and the arguments must agree with it.** Product repo without
  `sources =` stops, naming the argument to pass. Ordinary repo with `sources =` stops, saying sets
  live in product repos. A file-shaped manifest handed to a product repo still stops.
- R1.3 Ordinary-repo behaviour, arguments, columns and return value are unchanged.

### R2. The preview (`datom_sync_manifest(conn, sources = , pattern = )`)

- R2.1 One row per table in the sources (name filtered by `pattern`, a glob as today), plus one row
  per set member the call could not check. Columns at least: `project`, `name`, `kind`,
  `version_from` (`NA` when new), `version_to`, `status`.
- R2.2 `status` is one of `new`, `changed`, `unchanged`, `ambiguous`, `not_checked`, `excluded`.
  `excluded` (added 2026-09-28) marks a member whose table is in a passed source but does not match
  `pattern`: the row confirms the filter left it alone, so the preview accounts for every member.
- R2.1a **Sets count as artifacts** (added 2026-09-28, owner). "Table" in R2.1-R2.8 means a table or
  a set: a set in a source gets a row, and a set member of a source project is compared, exactly as a
  table is. A set built from sets is the case sets exist for, so sync must be able to move one.
- R2.3 **Never proposes a removal.** A member whose table no longer exists in its source is reported
  and left alone, as `datom_update_members()` does today.
- R2.4 **No labels column.** Labels for new members are set when applying (R3.3).
- R2.5 **The set's own project is never a source.** A source whose tables belong to the set's own
  project stops, saying outputs are moved with `datom_update_members()` after re-deriving.
- R2.6 **Same table twice.** When the set holds two members for one source table (e.g. live plus a
  frozen baseline), the row is `ambiguous`, neither is moved, and the message names the
  `datom_update_members(member = , tags = )` call that moves one.
- R2.7 **A source project not passed.** Members from a project that is neither a source nor the set's
  own project appear as `not_checked`, keep their versions, and the message says how to fix a mistake:
  build the manifest again with every source.
- R2.8 **First version.** With no set yet, every row is `new`.
- R2.9 Saves nothing.
- R2.10 **A mislabelled source stops** (added 2026-09-28). When a source connection's project name
  differs from the name its own manifest records, the preview stops and names both. A manifest that
  records no name is not checked.

### R3. Applying (`datom_sync(conn, manifest, sources = , tags = , x = )`)

- R3.1 Accepts **any row subset** of a preview (`subset()`, `dplyr::filter()`). Validates columns and
  values, never object identity or row count.
- R3.2 `new` rows join the set; `changed` rows repoint the matching member. `unchanged`, `ambiguous`,
  `not_checked` and `excluded` rows do nothing.
- R3.3 `tags =` labels the **new** members, default `list(type = "input")`. A repointed member keeps
  its labels exactly.
- R3.4 **Saves nothing.** Returns the updated `datom_set` and, when any row was applied, ends with
  `Nothing has been written. Write the set with datom_write_set(conn, x).` When no row applies it
  says so instead (amended 2026-09-28, owner). **The rule for every verb that hands back a set
  without writing: print the not-written line when the object in hand differs from what is
  stored.** That is already how `datom_update_members()`, `datom_remove_members()` and
  `datom_add_member()` on a saved set behave; a draft always differs, so an add to a draft prints
  it too (reverses task 3's "adding to a draft stays silent"). Since R9 there are no drafts: every
  add prints it, and the hint is always `datom_write_set(conn, x)`.
- R3.5 `x =` applies the preview to a set already in hand (the "top up" case); omitted, the stored set
  is read. With no stored set, the result is a set with no version, named from `.datom/project.yaml`.
  Since R9, `x` is a `datom_set` however it was made, including by `datom_assemble_set()`.
- R3.6 A `changed` row whose `version_from` no longer matches the set's member stops: the set moved
  since the preview was built. So does a `new` row whose table the set now already holds (added
  2026-09-28). Like a push refused because the remote moved, the message says to build the preview
  again from the current set.
- R3.7 The edits are recorded, so `datom_write_set()`'s default commit message names what was added
  and repointed.

### R4. `datom_add_member()` on a saved set

- R4.1 Accepts a `datom_set` as well as a draft, and returns the class it was given.
- R4.2 New `conn =` argument resolves a member given by name. On a draft it overrides the draft's
  connection; on a `datom_set` it is required for a name. A record or link still needs no `conn`.
- R4.3 On a `datom_set`, the addition is recorded and the default commit message says `add N members`.
  A draft's commit message is unchanged.

**R4 as shipped by task 3 is superseded by R9 (owner, 2026-09-29):** there is no draft class any
more, so R4.1's "returns the class it was given" and R4.3's draft carve-out go, and R4.2's `conn =`
is required for every name.

### R9. One in-memory set (added 2026-09-29, owner)

Why: a set in memory came in two kinds -- a draft, which held the product repo's connection, and a
set read back, which held none -- and each verb had to know which it was handed. The two kinds
disagreed in ways a user meets: `datom_write_set(conn, draft)` fails ("`members` must be a list of
member records") while `datom_write_set(conn, x)` works for a read set; the list, structure and
fetch verbs refuse a draft outright; and the edit verbs' "nothing has been written" hint names a
call that fails for a draft. The foundational fact is that **writing needs the product repo's
connection and a set value does not**, so the connection belongs on the call, never in the object.

- R9.1 **A set in memory is always a `datom_set`**, with no connection in it. `datom_assemble_set()`
  returns an empty one, the same object sync starts from on a first version. The `datom_set_draft`
  class and its print method are removed.
- R9.2 **Every verb that needs a connection takes it on the call.** `datom_add_member()` needs
  `conn =` for a member given by name, whichever set it is adding to. A record or a link still needs
  none.
- R9.3 **One way to write what you hold:** `datom_write_set(conn, x)`, which pipes as
  `x |> datom_write_set(conn = conn)`. `datom_write_set(draft)` goes. A plain list of
  `datom_member()` records is still accepted in the same place, as the build-script form.
- R9.4 **Every add is recorded**, gives the new member a fetch link, and ends with the not-written
  line, as the other edit verbs do (R3.4). A set's first commit message therefore names its adds.
- R9.5 **The write refuses a set that belongs to another repo.** When the set carries a name, it
  must equal the repo's declared set; when it carries a project, it must equal the repo's project.
  Otherwise the write stops before anything is hashed or written. Today the write ignores both, so a
  set read from one product repo and written with another's connection is silently re-homed.
- R9.6 The list, structure, fetch, edit and sync verbs accept a set however it was made.

### R5. `datom_parent()` from a set

- R5.1 New `x =` (a `datom_set`) and `tags =`. `version` and `x` are mutually exclusive; exactly one
  is required. Calls without `x` are unchanged, positional calls included.
- R5.2 With `x`, `table` may name several tables and the result is **always a list** of parent
  records, ready for `datom_write(parents = )`.
- R5.3 The member is resolved exactly as `datom_fetch_member()` resolves it: an ambiguous name stops
  listing candidates (same condition class), narrowed by `tags`; a set-kind member stops.

### R6. Provenance check at set write

- R6.1 `datom_write_set()` reads the recorded parents of every table member from the set's own
  project. If a parent's table is in the set at a **different** version and not at the parent's
  version, the write stops, naming the member, the parent, and both versions.
- R6.2 Runs before any hashing or local write, so a refusal leaves nothing behind.
- R6.3 A parent whose table is not in the set at all is not checked.

### R7. Example data gains `vs`

- R7.1 `datom_example_data("vs")` returns a vital-signs table (48 subjects, visit-aligned with `lb`,
  date column `VSDTC`), usable with `cutoff_date`.
- R7.2 **The four existing CSVs are byte-for-byte unchanged**, and `R/sysdata.rda` loads to identical
  values. Every recorded vignette output depends on them.

### R8. Vignette

- R8.1 `citable-sets.Rmd` follows the agreed shape: v1 via sync; v2 derive (a function returning a
  data frame) -> `datom_write(parents = datom_parent(..., x = x))` -> `datom_add_member(conn = )` ->
  one set write; refresh via sync -> derive -> write output -> `datom_update_members(tags = output)`
  -> one set write.
- R8.2 The month-4 extract adds `vs`, so the imported project's sync shows it new and the set's sync
  shows it `new`.
- R8.3 `start-on-s3.Rmd` is **not** edited.
- R8.4 Every `#>` block comes from one credentialed run of `dev/e2e-vignettes-s3.R` (owner runs it),
  under the same edit rules as the last spec (paths and account as `...`, bucket as `study001`).

## Acceptance checks

- [ ] AC1 Ordinary-repo sync tests pass unchanged; product-repo refusals still refuse file import.
- [ ] AC2 A preview shows `new` / `changed` / `unchanged` with from/to versions and never a removal.
- [ ] AC3 A table added to a source appears as `new` on the next preview.
- [ ] AC4 `datom_sync()` accepts a row subset, and a hand-built frame with the right columns.
- [ ] AC5 Own project as a source stops; an unpassed source project shows `not_checked` with the fix;
      a member excluded by `pattern` shows `excluded` and does not move; a mislabelled source stops.
- [ ] AC6 A duplicated table shows `ambiguous` and neither member moves.
- [ ] AC7 First version: every row `new`, result is a versionless set with the declared name.
- [ ] AC8 Sync saves nothing and prints the not-written line; the next set write's commit message
      names adds and repoints.
- [ ] AC9 A preview made stale by a set change stops at apply -- a moved `changed` member, and a
      `new` table the set has since gained.
- [ ] AC10 `datom_add_member()` on a `datom_set`, by record and by name with `conn`, records the add.
- [ ] AC11 `datom_parent(x = )` picks what `datom_fetch_member()` picks; ambiguous and set-kind stop;
      several tables return a list; existing calls unchanged.
- [ ] AC12 A set write whose output's parent disagrees with the set's pin stops, before any write.
- [ ] AC13 `vs` exists; the four existing CSVs are byte-identical; `sysdata.rda` values identical.
- [ ] AC14 citable-sets matches R8 and every `#>` block traces to the credentialed run.
- [ ] AC15 Every guard above has a test watched going red with the guard removed (convention 2a).
- [ ] AC16 `NEWS.md` entry; `dev/datom_pathways.md` route card for the set sync route; no `dev/` or
      `.kiro/` cite from NEWS, roxygen or vignettes; `R CMD check --as-cran` 0E/0W.
- [ ] AC17 A set in a source is previewed and applied like a table (R2.1a). And a set built from a
      real stored set (inner set written, pointed at with `datom_member()`, outer set written) reads
      back and validates on a local store -- no test did this end to end before 2026-09-28.
- [ ] AC18 `datom_assemble_set()` returns a `datom_set`; no `datom_set_draft` remains in `R/`,
      `NAMESPACE`, `man/` or `_pkgdown.yml`; a name added without `conn` stops; an assembled set
      pipes through `datom_add_member()` and `datom_list_members()` to
      `datom_write_set(conn = conn)`; a set whose name or project is another repo's stops at write
      with nothing written (R9).

## Out of scope

- Label-based filtering when building a preview (names via `pattern` only).
- Declaring sources in `project.yaml`.
- ~~Sets as sources (preview rows are tables only).~~ **Brought into scope 2026-09-28** (R2.1a).
- A set as a derived table's parent. A parent is a table version; a table member of a set can be a
  parent, the set itself cannot (R5.3, unchanged).
- Any change to table hashing, versioning or storage.
- Changing table sync to save lazily. The asymmetry (tables save on sync, sets save on
  `datom_write_set()`) is deliberate and documented.
