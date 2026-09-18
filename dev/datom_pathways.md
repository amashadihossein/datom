# datom Pathway Map

This document is a quick lookup for canonical routes through datom's architecture. It is not the source of truth for schemas or APIs; it points to the route the design expects developers and companion packages to use.

Use this before adding a new lookup path, helper, index, or metadata field. If a route already exists here, prefer using or hardening that route over opening a parallel path.

## Maintenance Rule

Any change to metadata schema, storage layout, governance refs, lineage, access control, role resolution, migration, or decommissioning must do one of two things:

1. Update the relevant route card in this document.
2. Explicitly note "no pathway impact" in the phase progress log or PR description.

Each route card should stay short. Put detailed schema and algorithm changes in `dev/datom_specification.md`; this document should name the intended path and point to the canonical functions or files.

## Route Cards

### Given table + version, read data

**Question:** I have a table name and a datom version. Which parquet object should be read?

**Canonical route:**

1. Treat `version` as metadata_sha.
2. Open `{table}/.metadata/{version}.json` when the exact version is supplied, or use `{table}/.metadata/version_history.json` when resolving display/history state.
2a. **Schema version gate** (added by the `datom-sets` spec, issue #89): on reading any metadata or manifest document, check its declared `schema_version` before using it. Newer than `.datom_supported_schema` aborts with the upgrade message (`datom_schema_unsupported`); absent means v1 and is tolerated. Like the integrity gate below, this is a **gate on a document already fetched, not a new lookup** -- the route shape is unchanged.
3. Read `data_sha` **and `parquet_sha`** from the metadata/history entry.
4. Fetch `{table}/{data_sha}.parquet` from the data store.
5. **Integrity gate** (added by `datom-cv1`, issue #72): before parsing, hash the downloaded object and compare to the recorded `parquet_sha`; abort on mismatch. An absent/empty `parquet_sha` (pre-`datom-cv1` entries) skips the check. This is a gate on step 4's result, **not a new lookup** -- the route shape is unchanged.

**Primary functions/files:** `datom_read()`, `.datom_read_metadata()`, `.datom_check_schema_version()`, `.datom_check_artifact_kind()` (with `operation = "read"`, so a set read as a table names the verb that reads sets), `.datom_resolve_version()` (returns `list(data_sha, object_sha, version)`; `field =` selects which recorded stored-object hash `object_sha` holds), `.datom_read_parquet()`, `metadata.json`, `{metadata_sha}.json`, `version_history.json`.

**Do not:** Try to infer metadata_sha from data_sha unless the route explicitly starts from `version_history.json`. Do not read the parquet before the integrity check -- the point of the gate is that a tampered object is never parsed. Do not add a second schema check inside the machinery of a route: the check belongs at the point a document enters datom, so a refusal happens before any work is done rather than partway through it.

### Given a repo, decide whether this build can read it

**Question:** A datom-owned document just arrived -- a metadata or manifest document from storage or the local clone, or the clone's `.datom/project.yaml` being parsed while a developer connection is built. Can this build of datom interpret it?

**Canonical route:**

1. Read `schema_version` from the parsed document. Absent means **v1** -- every repo written before the field existed.
2. Compare against the ceiling **for that document**. Machine-written documents (manifest, per-artifact metadata) take the repo-wide `.datom_supported_schema` (`R/utils-validate.R`). `project.yaml` takes its own `.datom_project_schema`, supplied by `.datom_check_project_schema()` -- it is written once at init and hand-edited for years, so its shape moves on its own clock, and sharing the repo-wide ceiling would refuse a whole developer path over a manifest bump that never touched this file.
3. Greater than supported -> abort (`datom_schema_unsupported`), naming the document and the upgrade command. Equal or less -> proceed. Present but not a whole number >= 1 -> abort as corrupt (`datom_schema_invalid`). **One exception, and only one: a MANIFEST being READ.** That document is reconstructible, so instead of aborting it goes to the reconstruction card below. Per-artifact metadata aborts at any role, and the manifest still aborts on the write path. `project.yaml` has no hatch either -- there is nothing to rebuild it from, so it aborts like per-artifact metadata.
4. **Manifest only: convert whatever survived step 3 to the current shape**, using the version step 3 resolved (`.datom_manifest_upgrade()`, `R/manifest-upgrade.R`). The order is fixed and only one order works: there is no step for a version this build does not know, so a too-new document must never reach the converter. A **read** converts in memory and leaves the file alone; a **write** converts the file and then stamps the version reached. This is a transform on a document already fetched, **not a new lookup** -- the route shape is unchanged.
5. **Manifest only: is there an artifact list after the conversion?** Absent on a read -> the reconstruction card below. Absent on a write -> refuse. Present but empty is **not** this condition: that is what a brand-new repo looks like.

**Where it is called (reader side):** `.datom_read_metadata()` (the `datom_read()` data path, which never touches the manifest), `datom_list()`, `datom_summary()`, `datom_status()` (both the stored manifest and the clone's copy), `datom_sync_manifest()`. Plus, for `project.yaml`, **every site that parses it** -- derive the list from `yaml::read_yaml()`'s call sites rather than trusting a count, which the project-mode work will move: `.datom_get_conn_developer()` where a developer connection parses the config, `.datom_resolve_data_location()` on its post-migration-pull re-read (the pull may have replaced the copy the connection started from), `.datom_check_set_write_gates()`, which reads `mode` and `set` out of that file on every set write, and `datom_repo_set_data_store()`, the only verb besides `datom_init_repo()` that writes the file -- it merges a storage block in on this build's assumptions and then commits and pushes, so an unreadable shape would be edited wrongly and then distributed. A **reader**-role connection has no clone and never parses `project.yaml` at all -- the right scope, since the harm is a write into a repo whose policy this build cannot read, but not a gate that covers every role.

**The connection-time gate does not cover the other three.** It ran on the file as it stood when the connection opened, and a hand edit or a pull replaces it -- the same reason the write entry is re-run after a route's own pull. Do not remove any of the three on the grounds that a developer connection was already built.

**Primary functions/files:** `.datom_check_schema_version()`, `.datom_supported_schema`, `.datom_check_project_schema()`, `.datom_project_schema`, `.datom_manifest_upgrade()` and `.datom_manifest_upgrade_v1_to_v2()` (`R/manifest-upgrade.R`), `.metadata/manifest.json`, `{artifact}/.metadata/metadata.json`, `.datom/project.yaml`.

**Why this matters:** it makes the artifact-namespace change the **last** transition that can degrade silently. Before it, an older reader against a newer repo found none of the fields it expected and reported an empty repo.

**Do not:** Put the check inside a `tryCatch` that softens read failures -- the upgrade message gets reworded as "could not read manifest", or worse, downgraded to a warning. Read the document inside the handler, check it outside. Do not gate on `datom_version`: that records the writing package version (provenance), so gating on it would fire on harmless upgrades. Do not point the **vocabulary** check at `project.yaml`: that check's power comes from a document being machine-written, and this one is hand-edited, so an unrecognised key there is as likely a typo or a private note -- refusing on one would block every write in the repo until somebody found it. Do not stamp `project.yaml` with the repo-wide number, and do not "simplify" the two constants into one.

**Write side:** the schema comparison above is one step of the write entry, described in its own card below.

### Given a manifest whose artifact list this build cannot reach, still list the repo

**Question:** The manifest read above got as far as a parsed document and then found no artifact list this build can use -- either the key is not there after the conversion, or the document declares a format this build has never heard of. What does a reader do?

**Why there is a route at all:** without one, the answer is "report an empty repo, and do not error". Every discovery command agrees, confidently, and nothing looks wrong. The manifest is the one datom-owned document with a way out, because it is a **projection**: every fact in it is also recorded in the per-artifact documents it summarises.

**Canonical route** -- `.datom_rebuild_manifest(conn, prior)` (`R/manifest-rebuild.R`), reached from inside `.datom_read_manifest()` and only when `operation = "read"`:

1. **One recursive storage listing**, `.datom_storage_list_objects(conn, "")`. Artifact names are the first segment of every key shaped `{name}/.metadata/metadata.json`. The listing returns **full** keys (`{prefix}/datom/...`), so the namespace root is stripped before matching -- this is the two-key-shapes trap, and mixing them fails silently rather than erroring.
2. **Two reads per artifact**: `metadata.json` and `version_history.json`. The metadata document gets the schema check from the card above, and its refusal **escapes the rebuild** rather than becoming a missing row: metadata is stamped and not reconstructible, so if the release that moved the manifest ahead also moved metadata there is nothing to salvage.
3. **Copy the row's fields from those two documents.** `kind` is read from the metadata document, falling back to `"table"` for documents written before metadata declared it -- a set's row is therefore recovered as a set, though not yet completely, since a set row also carries `member_count` and that number lives in the payload rather than in either document read here. `current_version` is the `version` **recorded** in the history, never a recomputed hash -- recomputing reaches for the identity code in exactly the situation a rebuild is for and can publish a version matching nothing in the history. Which entry describes the current state is not always the newest: a write that reverts to content already in the history appends nothing, so selection narrows by `data_sha` first and by the copied `created_at` second (`.datom_recorded_current_version()`).
4. **Recompute the summary counters** from the rebuilt rows, declare the current schema version, and carry `project_name` and `updated_at` from the document being replaced.
5. **Warn once** (`datom_manifest_rebuilt`), naming the copy, the reason and the upgrade.

**In memory, for this session, always.** Neither copy of the manifest is written. A reader holds storage credentials and no clone, so persisting is not available to the population this route exists for; the recorded copy is repaired by the next ordinary write.

**When the rebuild itself cannot be done**, the fork matters and is not symmetric. A **too-new** document falls back to the original schema refusal -- reporting it as an unreadable manifest is the one thing forbidden at every reader, because "could not read manifest" sends the user to check credentials when the instruction is to upgrade. An **unreachable-shape** document was perfectly readable, so the failure is the storage one and comes back as data for each caller's own policy.

**Primary functions/files:** `.datom_rebuild_manifest()`, `.datom_rebuild_manifest_entry()`, `.datom_storage_artifact_names()`, `.datom_recorded_current_version()`, `.datom_warn_manifest_rebuilt()` (all `R/manifest-rebuild.R`); `.datom_read_manifest()` (`R/sync.R`).

**Do not:** Trigger on an **empty** artifact list. Empty is what a new repo looks like and what a truncated file looks like, so it would put one storage listing on every read of every healthy repo and hide corruption behind a plausible answer. Do not give the writer the same response -- a writer meeting either condition refuses, and that asymmetry is the reads-limp / writes-stop rule rather than an inconsistency. Do not let a rebuilt row go untyped: `kind` is read from the document, and `"table"` is kept as the fallback for documents written before metadata declared it, because an untyped row is silently uncounted by `.datom_artifacts_of_kind()` -- a rebuilt repo would then list its artifacts while reporting zero of them.

### Given a write request, decide whether this build may write here

**Question:** `datom_write()` was just called. Is this build entitled to rewrite this repo's documents at all?

**Why a separate card:** the read side asks "can I interpret this document?" and answers by degrading gracefully where it can. The write side asks a stricter question, because a reader that guesses wrong gives one wrong answer to one person while a writer that guesses wrong leaves the repo wrong for everybody. **Reads limp, writes stop.**

**Canonical route** -- `.datom_check_write_entry(conn, artifact)` (`R/forward-compat.R`), called immediately after `datom_write()`'s `datom_conn` class check, at the top of `.datom_sync_data_metadata()` (which `datom_validate(fix = TRUE)` calls directly without passing through `datom_write()`), and from `datom_write_set()`, which inherits nothing from any of them:

1. **The floor.** If `project.yaml` declares a `min_writer_version` above the running build, refuse (`datom_writer_floor`). Absent means no floor. Read off the connection, which parsed that file already.
2. **The manifest**, through `.datom_read_manifest(conn, "clone", operation = "write")` -- the schema check and then the conversion chain, exactly as the read card describes, with the refusal worded for a write.
3. **The shape the chain reached.** No artifact list after the chain has run -> refuse (`datom_shape_unreachable`). Worded as *still* absent, not absent: a current build meeting a pre-rename repo finds no `artifacts` key either, and refusing on that would deadlock every upgrade.
4. **The vocabulary**, on the manifest's top level, on each artifact entry, and on each per-artifact `metadata.json` this write will touch. A top-level key this build cannot classify -> refuse (`datom_vocabulary_unknown`), naming the field. Per-artifact documents also get the step-2 schema comparison here, since this is the only place a write sees them.

**Scope of the documents inspected:** all three are the **clone's** copies -- local file reads, no network. `artifact` is the single artifact name a table write or metadata-only sync touches; `NULL` means every artifact in the clone, which is the mirror-everything route, enumerated by `.datom_clone_artifact_names()` (the same helper that route uses, so the door cannot inspect a different set than the one that gets written).

**Placement:** above the two routing returns, because one route mirrors the whole manifest to storage without touching a single artifact. Above any hashing, local write or commit, so a refusal leaves no partial state. **On the shared function, not on each caller** -- a repair verb that reaches storage without going through the write verb is the gap that has now been missed three times running. **Re-run after a route's own pull** -- `.datom_sync_metadata()` pulls as its first act, which replaces the documents the entry just read. Re-running is free and safe: every step is a local file read and none of them mutates anything.

**Known residual, so it is not rediscovered as a defect:** on both write routes the pull happens inside the push, in `.datom_commit_and_mirror()`, **after** the metadata document has been written and the manifest edited -- so the entry's answer can be stale there and re-checking cannot help, because the write is already built. The backstop is the push itself: it aborts on rejection or on a merge conflict, and the storage steps come after it, so a write cannot reach storage from a base this build has not seen.

**Cases that pass through untouched:** no clone (a reader-role connection fails later with a clearer message about role), no manifest file yet (nothing written, nothing to disagree with), and a manifest that will not parse (not a compatibility failure; the write fails on it moments later with the parser's own error).

**Primary functions/files:** `.datom_check_write_entry()`, `.datom_check_writer_floor()`, `.datom_check_document_vocabulary()`, `.datom_manifest_known_fields`, `.datom_manifest_entry_known_fields`, `.datom_metadata_known_fields()` (all `R/forward-compat.R`); `.datom_clone_artifact_names()` (`R/sync.R`).

**Why this matters:** a build that rewrites a document it cannot fully account for recomputes that document's version identity from the fields it knows, reaching a different answer from the build that wrote it -- on content that never moved. All of it binds **0.1.1 forward only**: 0.1.0 has none of these checks and none can be added to a released build.

**Do not:** Add directional logic. A newer build's vocabulary is a superset of every older one's, so the vocabulary check cannot fire on the upgrade path, and a guard for it would be dead code. Do not prune a name from a vocabulary list: a build that forgets a name meets an **older** document, fails to place a key it should know, and refuses it -- blocking the one direction that must always work. Do not put the per-artifact half of the check on storage's copy: git is written first and gates the mirror, so the newer document arrives in the clone.

### Given a member list, write a set

**Question:** `datom_write_set()` was called with member records from `datom_member()`. What happens, in what order, and where do the bytes end up?

**Why a separate card:** a set is the second artifact kind, and its write differs from a table's in three places that are easy to get wrong by analogy -- there are two extra gates before anything happens, the payload is written to **two different paths** rather than one, and the stored-object hash is over a JSON document that git also holds.

**Canonical route** -- `datom_write_set()` (`R/set.R`):

1. **Connection, role, clone.** Same three checks as a table write.
2. **The two gates**, `.datom_check_set_write_gates()`: `.datom/project.yaml` must declare `mode: product`, and `name` must equal its `set:` field. These read that file directly -- neither field is on the connection. They run **before** the write entry, because they are what establish which artifact this write touches, and the entry check's `artifact = NULL` means "every artifact in the clone".
3. **The write entry**, exactly the card above.
4. **Tidy, then validate, then order.** Tidy normalises tag maps at both levels and the `id` key order, and is deliberately **tolerant** -- a value it does not recognise as text passes through for validation to report. Validation is `.datom_validate_tag_map()` on the set's own tags and `.datom_validate_members()` per member. Then `.datom_order_set_members()` dedupes by `datom-sv1` member digest and sorts by `project` || `name` || `version`.
5. **The payload-level refusals**, `.datom_check_set_payload()`: zero members, the same `id` twice with different tags, and self-reference. All three need the whole payload, which is why none is in the member validator.
6. **Identity, then the version.** `.datom_build_set_metadata()` computes `data_sha` with `.datom_canonical_set_hash()` (`datom-sv1`, `R/hashable-set.R`), then `.datom_compute_metadata_sha()` gives the version.
7. **Change detection and the kind check.** `.datom_has_changes()` reads the artifact's current metadata from storage; `.datom_check_artifact_kind()` refuses on that same document if the name already belongs to a table. No change -> return, nothing written.
8. **The git payload**, at `{name}/set.json`. Written before the metadata document, because `document_sha` hashes these bytes.
9. **`document_sha`**, via `.datom_resolve_document_sha()` -- reuse the recorded hash and skip the upload when this `data_sha` is already in history, otherwise hash the bytes just written. Populated on the metadata object **before** it is written.
10. **Metadata, history, manifest row**, then `.datom_commit_and_mirror()`: commit, push, upload the payload to `{name}/{data_sha}.json`, mirror the metadata, mirror the manifest.

**Storage layout, and the two `.json` addresses that are easy to confuse:** the payload is `{name}/{data_sha}.json` (content), the versioned metadata snapshot is `{name}/.metadata/{metadata_sha}.json` (version). Build both with the `R/utils-path.R` helpers, never by hand.

**Primary functions/files:** `datom_write_set()`, `.datom_check_set_write_gates()`, `.datom_tidy_set_payload()`, `.datom_order_set_members()`, `.datom_check_set_payload()` (all `R/set.R`); `datom_member()`, `.datom_validate_members()`, `.datom_validate_tag_map()` (`R/member.R`); `.datom_canonical_set_hash()` (`R/hashable-set.R`); `.datom_build_set_metadata()`, `.datom_resolve_document_sha()`, `.datom_commit_and_mirror()`, `.datom_check_artifact_kind()` (`R/read_write.R`); `.datom_update_manifest_entry()` (`R/sync.R`).

**Do not:** Content-address the git path. Every version would be a new file, `git diff` would report "file added" instead of which members changed, and history would have to be read by listing filenames. Do not sort the file's members by digest -- editing one member's tags changes its digest, so the entry relocates and the diff becomes a delete plus an insert; the hash sorts by digest and the file sorts by name, and the two keys have separate reasons. Do not recompute `document_sha` for content already stored: that records a hash of bytes nobody stored, and it surfaces later as a refused read of a valid version. Do not re-serialize the payload for storage -- upload the same file git holds, so one `data_sha` cannot end up with two byte spellings. Do not add cycle detection: a member pins a version that already exists, so a set cannot contain itself, and the self-reference refusal is a nonsense check rather than the first step of a walk.

### Given a set + version, resolve its members

**Question:** `datom_get_set()` was called. What is read, what is verified, and what does the caller get back?

**Why a separate card:** the shape mirrors the table read card, and the three differences are all places a naive implementation goes wrong -- the integrity gate forbids the convenient JSON read, the read is not allowed to canonicalize anything, and members come back as **pointers**, one level deep, never resolved to data.

**Canonical route** -- `datom_get_set()` (`R/set.R`):

1. **Metadata + history**, `.datom_read_metadata()`, which also runs the schema gate. No git clone is touched: a storage-only reader with `path = NULL` is the primary consumer.
2. **The kind check**, `.datom_check_artifact_kind(..., operation = "read")`, on the document just read. Both directions of one invariant: a table read as a set points at `datom_get_set()`, a set read as a table points at `datom_read()`.
3. **Resolve the version**, `.datom_resolve_version(..., field = "document_sha")`. Returns the storage address (`data_sha`), the recorded stored-object hash (`object_sha`) and the **recorded** version string, so a caller who passed an 8-character prefix gets the full version back.
4. **Download, hash, then parse**, `.datom_read_set_payload()`. `.datom_storage_read_json()` must not be used: it parses, leaving nothing to hash but locally re-serialized bytes. A missing `document_sha` is an **error**, not a skipped check -- sets have no legacy population.
5. **Normalize representation only.** A JSON string array comes back in three R shapes, so an all-text array becomes a character vector with the same strings in the same order. An `id` value that is still not a text scalar aborts as a malformed document, because those values are spliced into storage keys and are checked on write only.
6. **Build the links.** Every member gets `$fetch(conn)` from `.datom_member_link()` -- a namespace-level factory, so the connection never lands on the closure's parent chain -- classed `datom_link` and carrying its own member record as an attribute.

**Primary functions/files:** `datom_get_set()`, `.datom_read_set_payload()`, `.datom_read_set_members()`, `.datom_read_set_member()`, `.datom_read_string_array()`, `.datom_member_link()`, `print.datom_set()`, `print.datom_link()` (all `R/set.R`); `.datom_read_metadata()`, `.datom_resolve_version()`, `.datom_check_artifact_kind()` (`R/read_write.R`); `{name}/{data_sha}.json`, `{name}/.metadata/metadata.json`, `{name}/.metadata/version_history.json`.

**Do not:** Tidy on the read. `.datom_tidy_set_payload()` is right there and changes nothing on a healthy payload, so every test passes and the divergence shows up later -- as a repair that re-uploads reshaped bytes over an object whose recorded hash describes different bytes. Do not recompute `data_sha`: it is the address the payload was fetched from, and the sv1 encoder aborts on a payload key a newer datom added. Do not resolve members to data, and do not traverse a member that is itself a set: read cost is a function of this set's direct member count, never of the depth beneath it. Do not build the link factory inside `datom_get_set()` -- that frame holds the connection, and `saveRDS()` of a member would then write the token into the file.

### Given data_sha, find metadata versions

**Question:** I have a content hash. Which datom versions used these bytes?

**Canonical route:**

1. Open `{table}/.metadata/version_history.json`.
2. Filter entries where `data_sha` matches.
3. Use each matching `version` as the metadata_sha.

**Primary functions/files:** `version_history.json`, `datom_history()`.

**Why this matters:** `metadata_sha -> data_sha` is a direct lookup through metadata. `data_sha -> metadata_sha` is many-to-one and only cheap because `version_history.json` records `data_sha` in each entry.

**Do not:** Scan all `{table}/.metadata/{metadata_sha}.json` snapshots unless recovering from a missing/corrupt history file.

### Given derived table, find raw source inputs

**Question:** Which raw source versions contributed to this derived table?

**Canonical route:**

1. Open the table's current or versioned metadata snapshot.
2. Read `source_lineage`.
3. Treat each `{project, table, version_sha}` entry as a terminal raw-source leaf.

**Primary functions/files:** `datom_get_lineage(depth = "source")`, `metadata.json`, `{metadata_sha}.json`.

**Do not:** Traverse recursively through `source_lineage`. Imported tables contain a self-entry by design.

### Given table, walk parent graph

**Question:** What derived tables or parent versions led to this table?

**Canonical route:**

1. Open the table's current or versioned metadata snapshot.
2. Read `parents`.
3. For each parent, use `parents[].version` as metadata_sha and open `{parent_table}/.metadata/{version}.json`.
4. Repeat only through `parents`.

**Primary functions/files:** `datom_get_lineage(depth = "parents")`, `datom_get_parents()`, `datom_lineage_union()` (compose the recompute recipe), `parents`.

**Do not:** Use `source_lineage` as a graph edge. It is a flattened source attribution list, not a traversal graph.

### Given user + table, decide read access

**Question:** Can this reader access a table, especially a derived table?

**Canonical route:**

1. Resolve the project and data location through governance when governance is attached.
2. Open the requested table's metadata snapshot.
3. Read `source_lineage`.
4. Check each `{project, table, version_sha}` against the policy registry, where `version_sha` is data_sha.
5. Call `datom_read()` only after all source entries are authorized.

**Primary functions/files:** Future datomaccess access gate, `.datom_resolve_ref()`, `ref.json`, `source_lineage`.

**Do not:** Authorize derived table access using only the derived table's own data_sha. Permissions must cover the raw source lineage.

### Given store + project, resolve data location

**Question:** Where should reads and writes look for this project's data bytes and metadata mirror?

**Canonical route:**

1. If governance is attached, resolve `projects/{project}/ref.json` from the governance store or local governance clone according to role.
2. Compare the resolved location with the data store supplied by the caller.
3. Developer mismatch: pull data git and re-read `project.yaml`.
4. Reader mismatch: warn and proceed with the ref-resolved location using the reader's credentials.
5. Write-time guard always reads `ref.json` from storage before writing.

**Primary functions/files:** `.datom_resolve_data_location()`, `.datom_check_ref_current()`, `ref.json`, `project.yaml`.

**Do not:** Treat a caller-supplied bucket/prefix as authoritative after governance is attached.

### Given store credentials, determine reader vs developer role

**Question:** Should the connection use developer or reader behavior?

**Canonical route:**

1. Developer role requires explicit git/GitHub capability plus a local data path.
2. Reader role uses storage credentials only and resolves data location from governance when available.
3. Presence of `github_pat` changes role expectations; do not pass it to reader-only store objects.

**Primary functions/files:** `datom_store()`, `datom_store_s3()`, `datom_store_s3_creds()`, `datom_get_conn()`.

**Do not:** Infer backend or role from `conn$client` being NULL. Use explicit backend/role fields and constructors.

### Given migration need, switch data location

**Question:** How should a project move to a new data store or prefix?

**The branch is the location authority** (a *solo project* has `project.yaml` as authority;
a *governed project* has `ref.json` -- see `dev/datomanager_scope.md`):

- **Solo project (`project.yaml` is authority)** -- self-serve relocate, fully within
  datom:
  1. Copy bytes + metadata mirror to the new location (`datom_storage_copy()`).
  2. Rewrite `storage.data` in `project.yaml`; commit + push the data repo
     (`datom_repo_set_data_store()`). This completes the move; rebuild the conn to pick up
     the new location.
- **Governed project (`ref.json` is authority)** -- governed migration via
  datomanager:
  1. Copy bytes + metadata mirror to the new location.
  2. Update governance `ref.json` to point to the new location.
  3. Record migration history in governance.
  4. Let readers resolve the new location from governance.

**Primary functions/files:** Future `gov_migrate_data()` (datomanager, governed),
`datom_storage_copy()` / `datom_repo_set_data_store()` (datom data-side helpers; also the
solo-project self-serve path), `ref.json`, `migration_history.json`.

**Do not:** For a governed project, change only `project.yaml` or only storage contents.
Governance `ref.json` is the routing authority after governance is attached. datomanager
never writes the data repo directly -- it calls the datom `datom_repo_*` helpers.

### Given decommission request, remove project safely

**Question:** What is the safe deletion order for a datom project?

**The branch is the location authority** (same rule as migration -- solo vs governed
project):

- **Solo project** -- self-serve teardown, fully within datom:
  1. Require literal confirmation matching the project name.
  2. Delete the project's `datom/` namespace inside the data store root
     (`datom_storage_delete_prefix()`).
  3. Delete the data GitHub repo + local clone (`datom_repo_delete()`).
- **Governed project** -- governed teardown via `gov_decommission()` (datomanager),
  which orchestrates the datom helpers then cleans up gov:
  1-3. As above, but via `datom_storage_delete_prefix()` + `datom_repo_delete()` called
     from datomanager.
  4. Unregister the project from governance.
  5. Delete governance storage under `projects/{project}/`.

**Primary functions/files:** Future `gov_decommission()` (datomanager, governed),
`datom_repo_delete()` / `datom_storage_delete_prefix()` (datom data-side helpers; also the
solo-project self-serve path), gov unregister (datomanager-owned post gov-seam-liftout).

**Do not:** Delete the storage root itself. Buckets/directories are caller-owned; datom
owns only its namespace. datomanager never deletes the data repo directly -- it calls
`datom_repo_delete()`. A gov user must not call `datom_repo_delete()` directly (it guards
with `force_gov_attached = FALSE`); use `gov_decommission()`.