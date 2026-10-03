# AC15 test coverage review -- spec/set-sync-ergonomics @ 6dc1f23

Reviewer: Claude Code, independent of the per-task probe records.

## Method

- Guards enumerated from the diff `7d55a8b..6dc1f23 -- R/`: every added
  abort (23), every new call site of an existing refusal, and each check
  inside a multi-check abort (the seven value checks in
  `.datom_sync_apply_frame()`, the three stale branches). Checks shared by
  preview and apply were probed at each call site separately.
- 57 probes, each disabling exactly one guard in a scratch copy (never in the
  repo), then running the six spec test files (`test-parent.R`,
  `test-set-draft.R`, `test-set-edit.R`, `test-sync-set.R`,
  `test-write-set.R`, `test-sync.R`; baseline 369 tests, 0 failures).
  Restored after each probe; `diff -rq R/` clean at the end.
- Control probe (comment-only edit): 0 red.
- R 4.4.3, testthat 3.3.2, purrr 1.2.2, arrow 25.0.0 (conda-forge).

## Result: 54 of 57 red, 3 gaps

| Probe | Guard removed | Tests red |
|---|---|---|
| L3 | `R/lineage.R`, `.datom_parents_from_set()`: `.datom_validate_tag_map()` on `tags` | 0 |
| L6 | `R/lineage.R`, `.datom_parents_from_set()`: `.datom_validate_name(name)` per table | 0 |
| S1a | `R/sync-set.R`, `.datom_sync_set_apply()`: the `.datom_sync_set_name()` call (apply's undeclared-set refusal) | 0 |

### Tests to add (one each; watch each go red with its guard removed)

1. **L3.** `datom_parent(conn, "lb", x = x, tags = list(type = 1))` (and/or an
   unnamed `tags`) stops with the tag validator's message, the same one
   `datom_fetch_member()` gives for the same `tags`. Without the check, a bad
   `tags` reaches the resolver and fails as "not found" (or matches wrongly),
   so R5.3's "resolved exactly as `datom_fetch_member()`" isn't pinned for
   labels. The validator raises no class, so match on the message.
2. **L6.** `datom_parent(conn, c("dm", "Not A Name!"), x = x)` stops with
   `.datom_validate_name()`'s message. Without it the call degrades to
   `datom_member_not_found`, naming the wrong problem.
3. **S1a.** `datom_sync(conn, manifest, sources = src)` on a product repo whose
   `project.yaml` names no `set` stops with `datom_set_undeclared` before any
   read. Today only the preview route has this test (probe S1p reddens
   "a product repo naming no set refuses..." in `test-sync-set.R`).

## Also noted (not an AC15 gap)

- **Unprobeable guard.** `.datom_refuse_import_on_product()` opens with
  `if (!isTRUE(context$product)) return(invisible(NULL))`, but both callers
  (`R/sync.R`, `datom_sync_manifest()` and `datom_sync()`) call it only inside
  `if (isTRUE(context$product))`. The early return can never fire, so no test
  can go red for it. Same situation as task 4's dropped kind filter; suggest
  removing it for consistency with that decision.
- **Changed-row project check in apply** goes through the shared
  `.datom_repoint_member()`, whose refusal is pinned in `test-set-edit.R`
  (`datom_update_project_mismatch`). No sync-path test, but same code, so
  covered. Optional.

## Every probe that went red (for the record)

`datom_parent`: L1, L1a (neither), L1b (both), L2, L4 (classless table-shape
check), L5. `datom_add_member`: D1, D2. `datom_write_set`: W1, W1b, W2, W3, W3b,
W4, W5, W6 (R6.3 exemption). Context branch: C1-C8 (every argument/context
refusal, preview and apply). Sync set: S1, S1p, S2p, S2a, S3, S4p, S4a, S5, S6,
S6h (file-shaped hint), S7-S13 (each value check), S14, S15, S16, S17, S18,
S18c, S19 (x= remedy), S20, S21, S22, S23, S24, S25.
