# Tasks -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89) -- plus **three delta
comments on that issue** that amend it (joint-repo decision; E1 question resolutions; the sv1
payload/encoding restructure). All three are already applied here, so this spec -- not the issue
body alone -- is the current truth.
**Branch**: `spec/datom-sets`, cut from `dev`. **PRs into `dev`, not `main`** -- **0.1.2 is submitted
and awaiting CRAN**, so `main` stays frozen for the same reason it always did: if CRAN asks for
another fix, `main` must keep matching what they received (see `dev/README.md` "Branching During CRAN
Submission" for current heads). `main` is also protected and takes only PRs, enforced for admins.
Draft PR [#97](https://github.com/amashadihossein/datom/pull/97) is open and accumulates the task
commits.
**Test baseline**: 2460 at spec start -> 2482 after Task 1 -> 2572 after Task 2 -> 2612 after
Task 3 -> 2660 after Task 4 -> 2664 after Task 18 -> 2675 after the two operator-facing fixes
that followed it (see the 2026-08-26 rows in the Decisions log) -> 2686 after Task 19 -> 2740
after Task 5 -> 2748 after the escape-code fix that followed it -> 2836 after Task 6 -> 2861 after the
four review findings that followed it -> 2863 after its purity audit -> **2867 after the two loose
ends the second review pass found -> 2898 after Task 20 -> 2902 after the review that followed it
-> 2905 after the classify-late guard -> 2959 after Task 21 -> 2965 after the three review findings
that followed it -> 3050 after Task 22 -> 3053 after the three review findings that followed
it -> 3077 after Task 7 -> 3218 after Task 8 -> 3227 after the review finding that followed it ->
3413 after Task 9 -> 3418 after the review finding that followed it -> 3553 after Task 10 ->
3557 after the review finding that followed it -> 3585 after Task 26 -> 3686 after Task 24 -> 3697
after the review finding that followed it -> 3770 after Task 25 -> 3781 after the review finding
that followed it -> 3836 after Task 23 -> 3841 after the review finding that followed it -> 3854 after Task 11's guard hardening -> 3860 after the fail-closed change -> 3900 after Task 11 proper -> 3909 after the review finding that followed it -> 3926 after Task 12's chunk A -> 3974 after Task 12 proper -> 4012 after Task 13 -> 4065 after Task 14 -> **4067 after the review finding that followed it**.
Report the count in every commit message; it must never drop.

---

## Where things stand

**Done**: Task 0 (spec), **Task 1** (stale docstring sweep + relative-key helpers), **Task 2**
(`datom-sv1`), **Task 3** (`datom_storage_read_json()` + the relative-key validator), **Task 4**
(the reader-side `schema_version` gate), **Task 18** (the `.datom_check_git_current()`
fetch-failure defect, #104), **Task 19** (allowlist identity hashing, #100) **Task 5** (one
manifest reader + one skeleton builder), **Task 6** (the artifact-namespace rename plus the
old-format conversion), **Task 20** (unfamiliar fields survive a write), **Task 21** (the writer
refusals), **Task 22** (the reader-side rebuild), **Task 7** (`kind` in per-artifact metadata
plus the set metadata builder), **Task 8** (`datom_member()` plus the member and tag
validators) **Task 9** (`datom_write_set()`), **Task 10** (`datom_get_set()` plus the member link)
**Task 26** (a stored project name comes from the repo, not from a connection label),
**Task 24** (read-side ergonomics: finding and shaping members),
**Task 25** (write-side ergonomics: assembling a set in steps)
**Task 23** (`project.yaml` declares its format), **Task 11** (project mode gating the
import path), **Task 12** (foreign-content discipline plus the two git-mutation exports),
**Task 13** (the joint commit) and **Task 14** (validation branches on kind), plus
three things
that are not tasks: the prerequisite #89
named ([#95](https://github.com/amashadihossein/datom/issues/95) / PR #96, landed on `dev` *before*
this branch was cut, deliberately outside this history), `dev/check-spec.R`, and
`.kiro/steering/communication.md`.

**TASK 7 IS CLOSED, AND THE SET WORK PROPER HAS STARTED.** Per-artifact metadata now declares what
kind of artifact it describes: `.datom_build_metadata()` stamps `kind = "table"`, the new
`.datom_build_set_metadata()` produces a set's seven-field document, and the version-history entries
gained a `document_sha` slot that stays empty until something computes one. `kind` is **identity**,
which is what stops a table and a set sharing a version string, and which is why **both pinned
identity goldens legitimately moved** and why every existing table mints one extra version at its
next write -- an accepted decision from 2026-08-23, now stated in NEWS with its bound (`data_sha`
does not move, so nothing is re-uploaded). Task 22's handoff is discharged: a rebuilt manifest row
reads `kind` from the document and falls back to `"table"` only for documents written before the
field existed. Two things a later change must not undo, and four probes, are in Task 7's DONE record.

**Reviewed after it landed (2026-09-10). Nothing was wrong with the shipped code; two things were
wrong in what was written about it, and Task 9 closed both** -- a rebuilt set row now carries
`member_count` and no `size_bytes`, the rebuild fixture writes a set, and `document_sha` is populated
before the metadata document is written with the field set asserted on the bytes. The findings are
kept below because the reasoning is what a later change needs, not because anything is open.
(1) **A rebuilt row for a
set is wrong in two directions, not one.** A set's row carries a member count *instead of* a byte
size, and the rebuild produces neither correctly: the member count is missing, because it lives in
the payload rather than in the two documents a rebuild reads, and a byte size of `0` is **present**,
because the default has length 1 and survives the compaction step. The test that compares a rebuilt
row against a written one field for field would catch both, but its fixture writes tables only -- so
this is the same shape as the `kind` hardcode Task 7 just fixed: a real guard exists and reaching it
depends on somebody connecting two files. Task 9's body now says to extend that fixture.
(2) **`jsonlite` does not omit a NULL field -- it writes `{}`.** The Task 7 record claimed the
declared and conditional spellings "produce identical files", which is false. It changes nothing that
shipped (no set is written yet, and `parquet_sha` escapes because assigning NULL *removes* an element),
but it means a set metadata document written before `document_sha` is populated would pass the
seven-key check while carrying an empty object. Corrected in four places, including design.md section
4, which has carried the same wrong claim since the spec was written.

**TASK 22 IS CLOSED. EVERY PHASE E TASK THAT HAD TO RUN EARLY IS DONE; ITS SIXTH (TASK 23, ADDED LATER) RUNS IMMEDIATELY BEFORE TASK 11.** A reader that meets a
manifest whose artifact list it cannot use no longer reports an empty repo. It lists storage instead,
reconstructs the index from the per-artifact documents that hold the same facts, and **warns once**
naming the upgrade. Two conditions bring it there -- the artifact key is absent after the conversion,
or the document declares a format above what this build supports -- and they are the same two that make
a **writer** refuse. Same evidence, opposite responses; that asymmetry is the reads-limp / writes-stop
rule and must not be "unified". It lives in the new `R/manifest-rebuild.R`, is reached only from inside
`.datom_read_manifest()` when `operation = "read"`, and **writes nothing** at any role. **Four things a
later change must not undo.** (1) The trigger is **absent**, never *empty* -- empty is what a new repo
and a truncated file both look like. (2) A rebuilt row is stamped `kind = "table"`, because nothing in
per-artifact metadata says what kind an artifact is until Task 7; an untyped row is uncounted, so a
rebuilt repo would list its artifacts while reporting zero of them. (3) `current_version` is the
version **recorded** in the history, never recomputed -- and not simply the newest entry, since a write
reverting to earlier content appends none. (4) The artifact loop is `lapply()`, not `purrr::map()`,
because purrr re-signals a mapped function's condition as its own and the caller dispatches on the
class. Full reasoning in Task 22's DONE record.

**Also from Task 22: `original_format` is now written into per-artifact metadata**, not only onto the
manifest row, which is what made it recoverable. It is classified **not identity** -- the symmetric
choice with its sibling `original_file_sha` would have re-minted a version for every imported table in
every repo, on content that did not move.

**TASK 21 IS CLOSED.** A write now stops at a door before it does
anything, when this build cannot fully account for the repo it is writing into: the repo declares a
minimum datom version this build is below, the manifest declares a format this build does not know, the
conversion cannot reach an artifact list, or any of the three documents the write touches carries a
top-level field this build cannot classify. All of it is one function,
`.datom_check_write_entry()` in `R/forward-compat.R`, and it reads the clone's copies only -- local
file reads, no network. **Two things about it a later change must not undo.** (1) The vocabulary check
runs on the **converted** manifest, never the raw one: a pre-rename document keeps its list under the
old key, so checking the raw document would refuse every existing repo. (2) The shape refusal is
"still absent **after** the conversion ran", not "absent" -- the other wording deadlocks the upgrade
it exists to protect. **One deviation from the written design, recorded rather than quiet**: design
10.7's step 1 fetch is not implemented, because a fetch does not refresh the working tree and so cannot
make any of the four checks read a fresher document; the freshness problem it was aimed at is solved by
re-running the sequence after the one route that pulls. Full reasoning in Task 21's DONE record.

**Two things Task 21 leaves for whoever adds a field to a datom-owned document next.** (1) There are
now **three** vocabularies, one per document scope, all append-only:
`.datom_metadata_known_fields()`, `.datom_manifest_entry_known_fields` and
`.datom_manifest_known_fields`. Each has a test asserting that every field a real write produces is on
it, so an unclassified field fails there rather than refusing every subsequent write on a real repo.
(2) **Never delete a name from one of them.** `tables` sits on the manifest list marked retired, as the
worked example: a build that pruned an old name would meet an older document, fail to place a key it
should know, and refuse it -- blocking the upgrade direction, which always has to work.

**Task 6's rename shipped
2026-09-08 -- `manifest$tables` is now `manifest$artifacts`, entries carry `kind`, both manifests and
every per-artifact metadata document declare `schema_version: 2`, and a write into a repo whose format
this build does not know is refused before any hashing or file write. The conversion that keeps
existing repos readable lives in the new `R/manifest-upgrade.R`: reads convert in memory and leave the
file alone, writes convert the file and then stamp the version reached. All five of Task 6's open
calls were taken at their stated defaults, each recorded with what shipped in the DONE record at the
end of that task.

**Task 20 shipped the same day**: a top-level field this build cannot place now survives a write
instead of being deleted by the rebuild. It lives in a new `R/forward-compat.R` and is called from two
places, `datom_write()` and the manifest entry updater. **Three things about it that a later change
must not undo.** (1) The manifest's **top level** needed no code -- it survives because that document
is read, edited and written back rather than rebuilt, so a refactor to rebuilding it would end the
guarantee without failing anything except the one test written for exactly that. (2) **Only
unplaceable fields are carried.** A field datom knows still disappears when the write does not set it,
which is what stops a stale "this came from a CSV" claim outliving the version it described. (3)
`.datom_metadata_known_fields()` is a **function** because `R/` is sourced alphabetically and that
file sorts before the one holding the two halves it joins -- as a stored vector the package would not
install. **A fourth surface exists that the requirement does not name**: an entry in
`version_history.json`, safe by the same edit-don't-rebuild property and now pinned by a test, because
Task 7 and Task 15 both add fields to those entries.

**It took four commits, not one, and two things the follow-ups changed will bite whoever edits this
code next.** A review found four defects in the first commit, a purity audit followed, and a second
review pass found two loose ends; all of it is in the Decisions log (2026-09-08) and in Task 6's DONE
record. The two worth knowing before you touch anything:

* **Selecting artifacts by `kind` goes through `.datom_artifacts_of_kind()` and nowhere else.** The
  predicate had been written out at four sites and one copy lost a tolerance, which aborted
  `datom_status()` on a manifest entry the conversion step deliberately preserves. Do not re-inline it.
* **`datom_list()`'s zero-row frame is built by `.datom_empty_artifact_frame()`** and must carry the
  same columns a populated result would, `version_count` included when `include_versions = TRUE`. Two
  commits fixed two halves of that one defect; a third would be embarrassing.

**The purity audit E2 required is DISCHARGED, and its method is the reusable part.** Both of its
questions were answered by breaking the code on purpose and counting what reddened, not by reading:
deleting the artifact key from the shared reader reddens 64 assertions across 36 tests, and making an
untyped entry abort inside the selection helper reddens exactly one. It also caught two tests that
were passing whatever the code did.

**Start here.** Branch `spec/datom-sets`, working tree clean, **4067** tests
(FAIL 0 / WARN 0 / SKIP 0), `dev/check-spec.R` 9/9, and `R CMD check` 0/0/0 with examples run
(tests run separately). Next is **Task 15**
(the version-to-commit link, `commit_sha`), then Tasks 27 and 28, then the sweep.

**TASK 15 IS AUDITED AND STARTABLE COLD (2026-09-19), WITH NOTHING OPEN -- and the audit moves where
the work is.** Eleven findings in its body, both decisions settled by the owner the same day at their
defaults. The one thing to carry in before reading anything else: **the field this task adds is
stripped by the ordinary write path, not only by the repair the body describes.** Three functions
write the storage copy of `version_history.json`, and the busiest of them uploads the clone's copy
wholesale -- so the second ordinary write erases the first version's commit id, before a repair is
anywhere in the picture. All three therefore go through **one** helper that keeps what storage
already has and derives only what is missing; deriving is **required rather than preferred**, because
the argument that makes an older build's stripping tolerable ("it can always be re-derived") is false
if nothing ever derives. The derivation was probed on a real repo rather than reasoned about:
recomputing the version hash from each committed `metadata.json` reproduces the recorded version
exactly, oldest-first gives the first producing commit, and a code-only commit is correctly no
version's producer. `datom_history()` gains a `commit_sha` column, because the stored copy exists for
the reader with no clone and that verb is their only route to it.

**TASK 14 IS CLOSED, AND VALIDATION NOW UNDERSTANDS BOTH KINDS OF ARTIFACT.** It looked for a
parquet object for every artifact, so a set reported its data missing every single time; the payload
address now comes from the kind the artifact's own metadata declares. A set is checked past that:
every member's pinned version must still exist in this project's storage, the set must record the
hash of its payload, and **neither check descends** -- a member that is itself a set is confirmed and
its member list is never opened, so validating a set costs the same whatever sits beneath it. A
member recorded as belonging to another project is checked as a well-formed pointer only, because
this connection sees one namespace and looking there would report every cross-project citation as
rotten. **`fix = TRUE` also gained the one payload upload that is safe to give it**: git holds
`{name}/set.json`, so a payload storage has lost comes back from the clone -- only when the stored
object is absent, only when the clone's bytes hash to the hash already recorded, and never
recomputing that hash. Without it a set whose upload failed after the commit had no repair route at
all, since the write verb correctly does nothing on unchanged members. Five things a later change
must not undo, seven probes, three decisions taken at their defaults and one residual are in
Task 14's DONE record. **The probe worth carrying out of it**: the first spelling of the
never-re-upload test passed through the wrong guard and stayed green with the right one deleted --
same shape as Task 13's finding, a test asserting a value where the behaviour lives elsewhere.

**TASK 13 IS CLOSED, AND A SET CAN NOW CARRY THE CODE AND ENVIRONMENT THAT PRODUCED IT.**
`datom_write_set(include_paths = c("R", "dp", "renv.lock"))` stages the caller's own paths into the
**one** commit that carries the payload and its metadata, so checking out a set version yields the
data pointers plus what produced them -- the joint version is the commit itself, and nothing records
a link. Storage is untouched by it. **The claim the audit said nothing pinned now has a test that
reads git**: an unchanged set makes no commit however dirty those files are, and the probe that
commits them on the no-op path reddens the HEAD assertions while leaving the old
`action == "none"` assertion green, which is exactly why the existing coverage could not fail. Four
refusals, all above the first hash and the first local write, so a bad path is an error even when the
set turns out to be unchanged: outside the clone, datom-owned, nonexistent, and **gitignored** --
that last one because git stages an ignored path in silence and datom's own files keep the commit
from failing, so the version would claim a joint commit that omits exactly the file named. Five
things a later change must not undo, and nine probes, are in Task 13's DONE record.

**TASK 13'S SCOPED PRE-START AUDIT, KEPT BECAUSE THE REASONING IS WHAT A LATER CHANGE NEEDS (the task
itself shipped 2026-09-18 -- see its DONE record).** Six findings in its body and its one scope
question was decided, so the session began without a decision round. The reviewer narrowed the pass to **I19** -- an unchanged set stays a no-op
even when the caller's extra files are dirty -- because the Decisions log already names what that
protects, and a hazard claim nothing pins needs a test that can fail rather than another reading.
**The headline is that I19 holds today and its existing coverage cannot fail**: the no-change branch
returns above everything that stages a file, and the two tests that exercise it assert the *returned
value* said "no change", which stays green through a write that commits the dirty code and then
reports no change. Three things to carry in cold. That test must read git HEAD before and after, and
must assert the file is dirty on **both** sides or it passes in a repo where nothing changed. **A
listed path that happens to be gitignored is refused rather than silently dropped** -- owner-decided,
because git stages nothing and says nothing, and datom's own files being staged means the commit
succeeds while omitting exactly the file the caller named. And a nonexistent or overlapping path is
an error **even on the no-op path**, because validation runs before the hashing that change detection
needs. No escalation flag is owed and no export is added, so there is no NAMESPACE or `_pkgdown.yml`
step -- the first task in six without one.

**TASK 12 IS CLOSED, AND DATOM NOW HAS A SANCTIONED WAY TO COMMIT CONTENT IT DOES NOT OWN.**
`datom_repo_commit(conn, message, paths = NULL, push = TRUE)` and `datom_repo_push(conn)` let a
downstream package put its code, its lockfile and its build state into the data repo without
importing `git2r`. `paths = NULL` means what `git add .` means -- which is the **opposite** of what
datom's own writes do, and that asymmetry is the point: a machine-moment commit fires when datom
chose and must never sweep up work in progress, while a human-moment commit was asked for. Commit is
idempotent, push is convergent, and **the no-op still pushes when the branch is ahead**, because
returning early there would let one failed push leave the remote behind for good. Two verbs rather
than one, because "push what I already committed" must be spellable without risking a commit of
whatever the tree happens to hold. The other half of the task was proving two guarantees that were
already true: datom's own commits exclude a human's dirty files, and datom ignores paths it does not
own. Both now have tests that can fail -- reading the **real** commit tree rather than a mocked file
list, and using a foreign directory (`dp/`) that is not on the hardcoded skip list sitting in front
of the mechanism the requirement rests on. Eight things a later change must not undo, seven probes,
one deviation that changed the code (the push verb inherits the detached-HEAD guard rather than
asserting it -- an explicit assert there reddened nothing, and the reason is written at both sites),
and one residual owned by Task 16, are in Task 12's DONE record.

**TASK 23 IS CLOSED, AND `project.yaml` NOW SAYS WHAT SHAPE IT IS IN.** The config file carries
settings a writer must obey, and until now had no way to say "this repo needs a newer datom"; it
declares a format number, and every place this build reads that file checks it before reading a field
out of it. That number is **its own** (`.datom_project_schema`, `1L`), not the one every other
document is stamped with, so it stays put through every manifest or metadata bump -- the point being
that an upgrade elsewhere can never refuse a config whose shape never moved. Absent means v1, so no
existing repo changes behaviour, and an unrecognised **key** stays tolerated, which is the clause a
later tidy-up would break. **Every site that parses this file is gated** -- derive the list rather
than trusting a count, since Task 11 adds one: connection
construction, the re-read after a migration pull, the set-write gates (which read `mode` and `set`,
the very fields the requirement exists for), and the store-pointer verb, which is the only writer of
this file besides init and was caught by the review that followed. **When Task 11 adds `mode` and
`set`, the answer to the new key-set tripwire is to extend the expected key set and leave the number at
`1L`**, and that answer is written in the test's own comment -- but Task 11's audit found the test fires
only on keys written at **every** init, so if those two are emitted just for a product repo it stays
green and needs a second case (Task 11 finding 1). Five things a later change must not undo,
one recorded residual on the writer floor, and the probes are in Task 23's DONE record.

**TASK 12 IS AUDITED AND STARTABLE COLD (2026-09-18), AND THE HEADLINE IS THAT ITS TWO "ALREADY TRUE BY
CONSTRUCTION" CLAIMS BOTH HOLD AND BOTH NEED A TEST THAT THE OBVIOUS SPELLING DOES NOT GIVE.** Ten
findings in its body, and **its one decision is settled**: the commit verb does **not** run the staleness
gate, and R15.7's explicit branch guard stays -- this audit's claim that the gate makes that guard
redundant was checked and is false, since the gate reaches the branch check only after four early returns
and so misses a detached HEAD that is up to date, which is the ordinary shape of the mistake. The three worth carrying into a cold session. **The machine-commit isolation test must read
the real commit tree**: there is already a test that mocks `.datom_git_commit()` and asserts the manifest
is in its file list, and extending that one with an exclusion assertion defends nothing, because the mock
replaces the very function whose file list *is* the guarantee -- it would stay green through the add-all
refactor the requirement exists to catch. **The foreign-path tolerance is two mechanisms on two
surfaces**, a `metadata.json` filter for artifact discovery and an explicit expected-file list for the
repo-level checks, so one test covers half of it; and the fixture directory must be a name that is
**not** on the hardcoded exclusion list sitting in front of that filter, or the test passes by the
mechanism the requirement does not depend on. **Two git behaviours were settled by running git2r rather
than reasoning**: `paths = NULL` *can* delegate to the existing helper with `files = "."`, which respects
`.gitignore` and stages deletions; and the tempting `staged_deletions = TRUE` spelling sets
`force = TRUE`, which stages gitignored files and silently breaks the acceptance criterion. Also: two new
exports, so NAMESPACE **and** `_pkgdown.yml` need entries, which the task body does not say.

**TASK 11 IS CLOSED (2026-09-18): A REPO CAN NOW DECLARE THAT IT BUILDS ITS DATA RATHER THAN
ONBOARDING IT.** `datom_init_repo(mode = "product", set = <name>)` records both fields; the two import
verbs refuse on such a repo and name the two verbs that do work there; `datom_status()` reports the mode
and stops describing an input-files directory the repo will never use; and a product repo's storage
namespace is checked on **every** backend with no `.force` opt-out, because teardown operates on a whole
namespace and a product sharing a prefix with its source study means deleting the product can delete the
raw data. It took three commits, since the guard work had to precede the mode work and carried a
behaviour change of its own -- an unverifiable namespace now **fails closed** for every repo, after a
trace showed the old tolerance did not defer the check but dropped it. Six things a later change must
not undo, and seven probes including one that reddened nothing and was the useful one, are in Task 11's
DONE record.

**Its two must-decide questions were answered on 2026-09-17 -- one against the audit's own default.** Ten findings in its body; nothing is
open. (1) `mode` and `set` are written **only for a product repo**, and the key-set tripwire gains the
**rule** that it must exercise every path writing `project.yaml` -- not just an extra case, because the
blind spot is any conditional key rather than these two, and a second path to cover exists today.
(2) The import refusal reads `mode` **from the file**; only `datom_status()`'s report reads it from the
connection. The audit had put both on the connection, which inverted its own rule: a check that
authorises a write must see the file as it is now, and the import refusal is exactly such a check --
otherwise a repo hand-edited to `mode: product` after the connection opened goes on accepting imports.
**That correction adds a fifth parse of `project.yaml`, which by Task 23's rule must carry the format
check**, so the shared refusal helper is parse, format check, mode check, in one place. Three
things a cold session should carry into it. **Nothing in a machine-written document changes**, so there
is no vocabulary entry, no format bump and no writer-refusal work here -- unusual for this spec, and
worth knowing before hunting for it. **The namespace guard R17.3 calls "one remaining hole" is two**,
and the unnamed one is that a **local** backend gets no namespace check at all -- the backend every set
fixture uses -- so AC22 is unsatisfiable as written until that widens; widening also falsifies the
refusal's message, which hardcodes `s3://` and the word bucket, and the condition class goes in before
the widening so the new test does not encode the text-matched re-raise it would otherwise pass through. And **four exported examples
hand-edit `project.yaml` to declare the mode**, so they teach the superseded route unless they move to
init's new argument in the same commit.

**THE SPEC GREW BY A PHASE ON 2026-09-16, AFTER TASK 25 LANDED: Phase H, Tasks 27 and 28, editing a
set that already exists.** A set is now pleasant to build and to read, and **unpleasant to edit** --
the only route is list surgery on what the read returned, and two of the obvious hand-rolled
spellings are silently wrong. Filtering members by name drops **every** version of that name, which
quietly removes a deliberately frozen baseline alongside the live table; and repointing by hand loses
each member's labels, which are content. So `datom_update_members()` (repoint at newer versions) and
`datom_remove_members()` (drop members) are scheduled into **this** release rather than deferred --
an owner decision made on value alone, because these verbs touch no stored document and so could have
been deferred at **no** forward-compatibility cost. **They execute after Task 15 and before Task 16**,
which is forced rather than chosen: Task 16 is the acceptance sweep and Task 17 is docs plus spec
completion, so verbs landing later would leave the sweep testing a surface that then grew. Task 27
runs before Task 28 because both share a plural member selector that does not exist yet, and the
harder consumer is what shapes it correctly.

**TASK 23'S PRE-START AUDIT, KEPT BECAUSE THE REASONING IS WHAT A LATER CHANGE NEEDS (the task itself
shipped 2026-09-17 -- see its DONE record).** It was audited cold on 2026-09-16 and startable with
nothing open -- ten findings in its
body, and the one that had to be settled first was **decided by the owner the same day, against this
audit's default**. The call: `project.yaml` carries **its own** format number, `1L` today, rather than
riding the one shared constant every other document is stamped with. The audit had priced a per-file
number as "a second constant kept in step by hand", and that price was wrong -- the point of a
per-file number is that it moves *independently*, so it stays `1L` through every manifest or metadata
bump and moves only when this file's own shape changes. What the shared constant would have cost is a
**false refusal**: the check sits in connection construction, so a build one version behind loses the
whole developer path on a file whose shape never changed, and the reader escape hatch does not help
the developer who is the one stuck. Two things a cold session must carry with that decision. Its one
real hole is a **forgotten bump**, closed by a test that fails when the config's key set changes
without the constant changing -- a tripwire that forces a *decision*, not one that mandates a bump,
since Task 11's addition of `mode` fires it and correctly does not move the number. And the shared
checker needs a `supported =` argument **in the same commit**, or the gate is nominal: the day this
file's shape breaks, a build whose global ceiling already equals the new number would accept it, and
the reading half cannot be retrofitted into builds already installed. That argument stays **optional**
-- all eight existing call sites read machine-written documents, where the global ceiling is the right
answer -- and the file-to-ceiling pairing lives in a three-line wrapper both of the config's callers go
through, so a third caller cannot forget it. **Two findings change what the task's body says.**
The body names two read sites and there are now **four**: Task 9's set-write gates parse this file on
every set write and read `mode` and `set`, which are the very fields the requirement exists for, so
that site gets the check too. And the harm the body illustrates with a silent `datom_sync()` no-op is
now sharper in shipped code: a future format that moved `set:` would make those gates report "declares
`mode: product` but names no set" and send the user to hand-edit a file that is already correct.
**No escalation flag is owed**, and unlike the last four tasks this one adds no export, so there is no
`_pkgdown.yml` or NAMESPACE step.

**TASK 25 IS CLOSED, AND A SET IS NOW PLEASANT TO BUILD AS WELL AS TO READ.**
`datom_assemble_set(conn, name = NULL, tags = NULL)` opens a draft, `datom_add_member(x, member,
version = NULL, tags = NULL)` validates one member and appends it, `print.datom_set_draft()` shows
what is assembled and says it is not written, and `datom_write_set()`'s **first** argument now
accepts the draft -- so a pipe ends `|> datom_write_set()` with nothing typed. The payload is
byte-identical to the direct form's; what is new is that a malformed member aborts on the line that
declared it. **The one call the audit said had to be settled first was taken at its default**: the
two widenings sit on two different parameters, `conn` for a draft and `members` for a set read back,
and the test asserts three *routes* to one write rather than three shapes of one argument. **Five
things a later change must not undo, and eight probes' worth of reasoning, are in Task 25's DONE
record.** The two worth knowing before touching it: **the draft is unpacked before the three guards
at the top of the write and the test for a supplied member list is `missing()`, never `is.null()`**
-- on the correct call `members` has no value and no default, so `is.null()` errors with R's own
"argument is missing" on the call that is right; and **`datom_add_member()` must never gain a `conn`
argument**, because two connections on one draft ends the property the verb is built on, and the
cross-project case is already covered by passing a **record** built on the other project's
connection, which is a capability rather than sugar and now has its own test on the written payload.
**Reviewed after it landed; one finding, accepted and fixed (tests -> 3781)**: a draft printed a
member count the write could silently change, because the write drops an exact repeat -- same
version, same labels -- while the draft appended it. Adding the same version with **different**
labels was worse: already an error at the write, so it aborted after forty lines had run instead of
on the line that introduced it. Both now settle at the add: an exact repeat is skipped and said out
loud, a disagreement aborts naming both label sets. **One thing the fix over-claimed and the probe
corrected**: it briefly tidied the record on the way in, on the theory that two spellings of one
label set would otherwise read as a conflict -- but the identity encoder already sorts a tag map's
keys and encodes each value as a sorted, deduplicated set, so the digest was blind to that
difference all along. The tidy is gone; the load-bearing part is comparing **digests** rather than
records, and swapping in `identical()` reddens exactly the test that pins it.

**TASK 24 IS CLOSED, AND A SET THAT READS CORRECTLY IS NOW PLEASANT TO USE.** Three verbs over the
object `datom_get_set()` returns: `datom_fetch_member()` resolves one member named by name, by
record **or** by link; `datom_list_members()` returns one row per member per tag as a plain data
frame; `datom_structure_members()` groups members by tag values into `dp$output$adsl(conn)`, where
the branches are tag values and the **leaf is the member's own name** holding its link.
**Reviewed after it landed; one finding, accepted and fixed (tests -> 3697)**: a tag map carrying the
same key twice silently lost every label after the first, because the one expander read its own input
by name and `tags[["type"]]` returns the first match. Reachable, because a reader validates no tag map
and `jsonlite` keeps duplicate JSON keys as two same-named elements. It is item 1's hazard on the
**key** axis rather than the value axis, which is why that item now says "by position".
**Six things a later change must not undo, and the reasoning behind each refusal, are in Task 24's
DONE record.** The three worth knowing before touching it: **there is one expander and both shaping
verbs go through it** (`.datom_expand_member_tags()`), because writing the multi-value expansion
twice is what invites the silent first-value spelling, and with one expander there is no second
place to write it; **the project hint lives in `.datom_link_failure()` in `R/set.R`, not in the
fetch verb**, because after `datom_structure_members()` a leaf is a link and never reaches that verb
-- and it re-signals the original condition **untouched** when the two project names agree, since
callers dispatch on those classes; and **a `missing` bucket name that collides with a real tag value
is refused whatever the members currently look like**, not only when some member is actually missing
the key, so the view does not start failing the day one is added.

**TASK 24 WAS AUDITED AND STARTABLE WITH NOTHING OPEN** -- ten findings in its body, and both scope
questions among them were approved at their stated defaults by the owner on 2026-09-15, so a fresh
session can begin implementing without a decision round. Three of the ten change what that task's body
says, so read the audit before the bullets above it. **The one that would otherwise be read as a
regression**: Task 24 justified its no-gate rule partly on "a reader is never told which string the
writer used", which **Task 26 made false** -- a member's project now comes from the artifact's own
metadata. The conclusion stands unchanged, because what makes a gate wrong is the **connection's**
side, which is still an unvalidated label; the sentence is restated in place so nobody concludes the
premise died with the defect and adds the gate. The other two: the third argument of
`datom_fetch_member()` is `member`, not `name`, because it accepts a name, a record **or** a link; and
a `missing =` bucket name that collides with a real tag value is refused rather than silently merged.
**Task 26 was also reviewed after it landed and no code changed** -- see the review record at the end
of Task 26.

**TASK 26 IS CLOSED. A PROJECT NAME IN A STORED DOCUMENT NOW COMES FROM THE REPO.** Both metadata
builders record `project`, taken from the writing repo's own `.datom/project.yaml`, and the field is
classified outside identity -- so **no existing artifact mints a version**, which is the opposite of
what `kind` cost in Task 7 and is now asserted rather than assumed. `datom_member()` and
`datom_parent()` read the name through one shared cascade: the artifact's own snapshot, then the
namespace manifest, then the connection's label **with a warning saying it is unverified**.
`datom_get_set()` stops one step earlier, snapshot then label, and **must not read the manifest** --
the data path never touches that document. Both open questions were taken at their stated defaults:
`datom_parent()` is fixed in the same commit, and the manifest step goes through the gated reader.
**Five things a later change must not undo, and the worst case is now reproduced rather than reasoned
about, in Task 26's DONE record.** The two worth knowing before touching it: the `project` argument is
**last** in both builder signatures and emitted **only when non-NULL**, because `jsonlite` writes a
declared NULL as `{}` and a dozen tests call the table builder positionally; and "a set's metadata has
exactly seven fields" is gone from all six places that said it -- the field set is named now, never
counted, which is what stops the next addition needing six edits.

**TASK 10 IS CLOSED, AND A SET IS NOW READABLE END TO END.** `datom_get_set(conn, name,
version = NULL)` is exported and returns a `datom_set` of `name`, `project`, `version`, `data_sha`,
`tags`, `members` -- references and labels, no data. `version` is the version **recorded** in the
history, so an 8-character prefix goes in and the full one comes back. The stored payload is
**downloaded, hashed, then parsed**, and a version recording no `document_sha` is an error rather
than a skipped check. Reading one kind with the other verb now aborts naming the verb that fits, in
**both** directions, from one function and one condition class. **Every member carries
`$fetch(conn)`** -- a `datom_link` closure that resolves a table member to data and a set member to
another `datom_set`, carries its own member record as an attribute, prints readably and survives a
save/load round trip. `datom_write_set()` accepts a `datom_set` back, so read-modify-write is a
loop. **Six things a later change must not undo, and eleven probes, are in Task 10's DONE record.**
The two worth knowing before touching it: **the read never tidies** -- `.datom_tidy_set_payload()`
changes nothing on a healthy payload, so reaching for it is green today and surfaces later as a
repair that re-uploads reshaped bytes over an object whose recorded hash describes different bytes,
which is why the never-tidy tests hand-write uncanonical payloads; and **the link factory is
namespace-level with every argument forced**, verified by serializing a member and searching the
bytes for the fixture's token, because a nested factory puts the connection on the closure's parent
chain.

**One process failure from Task 10 that cost an hour and must not recur.** A probe harness reverted
its deliberate defects with `git checkout -- R/set.R R/read_write.R`, which restored HEAD and
deleted the task's entire uncommitted implementation. It was rewritten from the session transcript
plus the already-generated `man/` pages and verified identical, so nothing shipped differently --
but the rule is now in `dev/engineering-notes.md`: **a probe harness restores from a copy it made
itself, never from git**, because the code under probe is by definition uncommitted.

**Task 10 was cold-start audited on 2026-09-13, then REPLANNED the same day after a design round on
set ergonomics. It is startable and NOTHING IS OPEN** -- every question the audit raised, and every
question the design round raised, was decided by the owner and is recorded in Task 10's body with
what was approved. The shape, so a fresh session does not re-derive it:

* **`datom_get_set(conn, name, version = NULL)`**, not `datom_read_set()`. It returns references and
  tags and no data, and `get` already meant that here (`datom_get_parents`, `datom_get_lineage`).
  Same reason the two verbs are **not** unified into one kind-dispatching `datom_read()`.
* **Result**: a `datom_set`-classed list of `name`, `project`, `version`, `data_sha`, `tags`,
  `members`, where `version` is the version **recorded** in the history, never recomputed.
* **Every member carries `$fetch(conn)`** -- a callable link that resolves the pointer, carries the
  member record as an attribute, and is classed `datom_link` with a `print` method. The factory is a
  **namespace-level** function with every argument forced, and the guard is a test on the
  **serialized bytes**.
* **The ergonomics on top are Tasks 24 and 25**, appended and executing after this one.

The naming rule the new verbs follow is design.md section 22, derived from the 40 exports that
already existed rather than invented, with the rejected names and the reason for each.

**The submission freeze still holds**: 0.1.2 is in flight, so `main` must keep matching what CRAN
received, and this branch PRs into `dev`. Branch heads live in `dev/README.md` "Branching During CRAN
Submission" rather than here, so there is one copy to keep true. One thing worth knowing before
touching anything git-adjacent: three tools misbehave silently in a git worktree because `.git` is a file
there rather than a directory, and one of them cost us the 0.1.2 submission record -- see
`dev/engineering-notes.md`, "In a git worktree, `.git` is a FILE".

**TASK 8 IS CLOSED.** A member of a set is now constructible as pure data: `datom_member()`
resolves one artifact version through one project connection and returns
`{id: {project, name, kind, version}}` plus optional per-member tags. It reads the version's own
metadata snapshot, which is what makes the pointer trustworthy -- a member can only point at
something that already exists, and that is the whole of the acyclicity guarantee. Alongside it,
`.datom_validate_members()` is the checker every set write will run, and two smaller helpers hold
the tag rules in one place so the write can reuse them for set-level tags. All of it is the new
`R/member.R`; nothing calls the validator yet, which is Task 9's job. **Three things a later change
must not undo, and six probes, are in Task 8's DONE record.** The one worth knowing before touching
it: an untagged member **omits** the tags key rather than carrying it as NULL, and no hash and no
golden can tell the difference, so the guard is a test on the emitted bytes.

**TASK 9 IS CLOSED, AND A SET IS NOW WRITABLE END TO END.** `datom_write_set(conn, members,
tags = NULL, name = NULL, message = NULL)` is exported and lives in the new `R/set.R`: two gates read
`.datom/project.yaml` and refuse a repo that has not declared itself a product repo or that names a
different set, the forward-compatibility door runs next, then tidy, then validate, then the canonical
member order, then the three payload-level refusals including self-reference. The payload is written
twice from one file -- git at the stable `{name}/set.json`, storage content-addressed at
`{name}/{data_sha}.json` -- and content already in history is never re-emitted: the stored object is
left alone and its recorded `document_sha` is carried forward. The manifest row carries
`kind = "set"` and `member_count` **instead of** `size_bytes`, on the healthy path and on the rebuild
alike. **Both of Task 9's approved scope calls shipped as approved**: fixtures hand-write
`project.yaml` (via a shared `write_product_config()` helper) and the gates read that file directly
rather than riding on the conn; and the commit-push-then-mirror sequence was **extracted** out of
`datom_write()` into `.datom_commit_and_mirror()`, so the table write path was touched. **Six things
a later change must not undo, and eight probes, are in Task 9's DONE record.** The one worth knowing
before touching it: the file's member order is **not** the hash's member order, and a probe that
sorted the file by digest reddened only after a fixture was pinned where digest order is the exact
reverse of name order -- with two members the two orders agree half the time, so an arbitrary fixture
made that test a coin flip.

**Reviewed after it landed; one finding, fixed (tests -> 3418).** Key order in the written payload was
canonicalized at two levels and needed three: the set's tag map and each member's `id` were sorted, the
member record's **own** `id` / `tags` pair was not. The encoder reaches both member slots by name, so
the two spellings hash identically and only the file differs -- and the case where that costs something
is the one the reuse machinery exists for, a revert to content already in history, where the clone's
payload is rewritten while the stored object is reused. Git would then hold bytes that do not match the
recorded `document_sha` while storage holds bytes that do. One line, and no existing payload changes,
because the canonical order is the one `datom_member()` already emits.

**Task 9's cold-start audit (2026-09-11) is kept below because both calls it raised are what shaped
the result.** The audit found nine things; the two scope questions among them were approved at their
stated defaults by the owner the same day -- explicitly, so they are decisions and not defaults that
happened to hold. The two decisions: **fixtures hand-write `project.yaml`** (the execution order
stands, and the gates read that file directly rather than riding on the conn), and **the
commit-push-then-upload sequence gets extracted** out of `datom_write()` so both write verbs share one
copy, with the commit message saying the table path was touched.
The two that would have cost real time: **the two gates read `project.yaml` fields nothing writes
until Task 11, which runs after this task**, so `datom_write_set()` landed unreachable through the
public path and its fixtures hand-write that file -- the same deliberate inertness Task 4's gate
had, and pulling Task 11's init half forward is the wrong fix because it drags Task 23 with it; and
**"reuse `datom_write()`'s steps 7-10" is not a call**, because those steps were inline in that
function's body, so this task either extracted the commit-push-then-upload sequence or wrote a second
copy of "git must succeed before storage is touched". Also found: a new write verb inherits nothing
from the three existing write doors and must call the entry check itself (the same route-was-the-gap
finding for the fourth task running); the **healthy** writer had the same set-row defect the task
attributed to the rebuild alone; and one code citation named the wrong function outright. **Six
things the finished tasks left sitting under it, all now discharged, kept because each is the reason
the shipped code has the shape it has.**

1. **The tag rules are already written and must be reused, not restated.**
   `.datom_validate_tag_map()` (`R/member.R`) is the grammar -- text only, no missing values, no
   empty labels, no duplicate or blank keys -- and it is what set-level tags go through, since
   those never pass through the member constructor. `.datom_drop_empty_tags()` is the one tidy rule
   that already exists; the rest of canonicalization (sorting keys, sorting and deduplicating
   values, unboxing single values, ordering members) is deliberately **not** written yet, so that
   canonical form has exactly one implementation and it is Task 9's.
2. **Tidy must run before validate at every call site, and the reason is not style.** The validator
   deliberately **passes** a key whose value is empty, because that is a tidy case rather than an
   error. Validate first and the tidy rule becomes unreachable; write without tidying and the same
   fact mints two different `data_sha` values, since a present key with an empty value hashes
   differently from an absent one.
3. **`.datom_validate_members()` deliberately accepts an empty member list.** The zero-member
   refusal is a whole-payload decision and is Task 9's, as is the same-`id`-different-`tags` case,
   which a per-member view cannot see and deduplication does not catch. Putting either refusal in
   both places would give one failure two messages.
4. **The self-reference refusal is Task 9's** (moved from Task 8 by owner decision, 2026-09-10):
   both the requirement and the criterion say "at write time", and the set's own declared name is
   established by the gate immediately above it. It is a nonsense check, not cycle detection:
   I10a forbids a visited set or a depth limit creeping in beside it.
5. **A member's `kind` is one of exactly two values**, held by `.datom_artifact_kinds`
   (`R/utils-validate.R:17`), append-only for the same reason the write-side field vocabularies are.
   Reuse it rather than spelling the pair again.
6. **Nothing writes a `kind = "set"` entry yet, so a counter filter passes whether or not it is
   there.** Any assertion about set counts needs a hand-built manifest holding a set entry beside
   table entries; `dev/engineering-notes.md` has the two spellings that go quietly wrong. The same
   shape applies to the rebuilt-row test named in Task 9's body: its fixture writes tables only, so
   the guard exists but cannot fire until somebody extends it.

**Two forcing functions still fire the moment a builder gains a field, and that is the design.** The
classification test in `test-utils-sha.R` derives its field inventory from the builders themselves --
both of them now, table and set -- so a new field fails there until it is classified, and its converse
arm fails when a name is classified before a builder emits it. The vocabulary test in
`test-forward-compat.R` does the same for the write-side field lists. Neither is a test to update;
each is where the decision gets made. Task 9 will trip the manifest-row one deliberately when it adds
`member_count`.

**One task was added after Task 22 and is NOT next: Task 23, `project.yaml` declares its format.** It
sits at the end of the list but **executes immediately before Task 11**, because Task 11 is what starts
writing `mode: product` into that file and Task 23 is what lets an older build notice. Recorded now
because the reading half cannot be added to a build that has already shipped -- the same filter Phase E
used. Nothing about it blocks Task 8 through Task 10.

**Two things Task 19 leaves for whoever adds a metadata field next.** (1) `metadata_sha` now selects
fields by **allowlist**: `.datom_metadata_identity_fields` is identity,
`.datom_metadata_excluded_fields` is the documented not-identity list, and a field in **neither** is
silently outside identity. The classification test in `test-utils-sha.R` derives its inventory from
the builders, so it fails until the new field is classified -- that is the forcing function, and
**Task 7 tripped it deliberately** when it added `kind` and the set metadata builder, whose fields it
now covers as well. (2) The union
of those two constants is the vocabulary Task 21's writer check reads; it is append-only from here.

**EXECUTION ORDER IS NOT TASK ORDER.** Phase E was appended rather than inserted so that nothing
renumbered a third time. The order is `18 -> 19 -> 5 -> 6 -> 20 -> 21 -> 22 -> 7 -> 8 -> 9 -> 10 -> 26 -> 24 -> 25 ->
23 -> 11 -> 12 -> 13 -> 14 -> 15 -> 27 -> 28 -> 16 -> 17`, and Phase
E's preamble says why each edge exists. Task 19 before Task 7 is the one that matters most: an
identity allowlist seeded from *table* metadata and landed after the set metadata builder would
silently drop set-specific fields from identity. **Task 23 before Task 11** is the other edge that is
not cosmetic: Task 11 starts writing `mode: product` into `project.yaml`, and Task 23 is what gives an
older build a way to notice -- a reading half cannot be added to a build that has already shipped, so
writing the field first would leave a permanent population treating a product repo as an ordinary data
repo. Task 11's body states the dependency, so the constraint holds from both ends rather than
depending on somebody checking the order at release time.

**Phase E exists because six things cannot be retrofitted.** The filter: does deferring it postpone
the cost, or permanently exclude every install shipped meanwhile? Allowlist hashing,
carry-unknown-fields, the writer refusals, the floor's reading half, the rebuild, and
`project.yaml`'s format check only ever help
builds that already contain them. Everything else from the same review round -- the bump rules, the
schema history table, the policy prose, the floor's tooling -- lands later without stranding anyone.
The aim is that **0.1.1 is the last release needing a transition plan.**
**Five of the six are done; the sixth is Task 23**, added later and the only one that does not run
early -- it runs immediately before the task it protects (Task 11). Phase E's preamble has the edge.

**Phase B is DONE, both halves** -- Task 5 the shared reader, Task 6 the rename itself. It was one task
until 2026-08-23 and became two (owner-decided, after the E2 design audit) because the rename's failure
mode is silent, so landing the reader first is what made the rename's own failure loud. Task 6's
escalation E2 is fully discharged: the design spot-check before it, the purity audit after.

**The gap that caused the split, and what closed it.** Nothing upgraded an existing repo's manifest:
every repo written before Task 6 keeps its artifact list under `tables` and declares no schema version,
the reader-side check tolerates that as v1, so such a repo would have passed the check and then met a
reader looking for `artifacts` -- every discovery command reporting an empty repo without erroring.
Neither thing that might have healed it did: the entry updater stamped no schema version, and a
no-change write returns at `R/read_write.R:1081-1090` before the manifest is touched. Closed by R22 --
**reads upgrade in memory, writes upgrade on disk** -- shipped in Task 6 as `R/manifest-upgrade.R`. The
full reasoning, including why refusing loudly was not an option, is in design.md 10.1 and 10.2, and it
is worth reading before any later format change rather than re-deriving it.

**Task 4's gate now fires, because Task 6 is what writes the number.** Three things about it that a
later change must preserve. `.datom_check_schema_version()` is the **one** implementation and gets
reused rather than reimplemented -- Task 6 gave it an `operation` word and nothing else. Its
**placement relative to error handling is load-bearing**: three reader sites wrap their read in a
handler that softens failures, and a check placed inside one reworded the upgrade instruction as
"could not read manifest" (`datom_status()` went further and downgraded it to a warning while
continuing). Task 4 held that line with a comment at each site; Task 5 replaced the comment with
structure, by having the shared reader **return** IO failures as data and **throw** schema refusals, so
there is no handler left for a caller to put the check inside. And the **check runs before the
conversion chain**, never after: there is no upgrade step for a version this build does not know, so the
dispatcher must never see one (I32).

**Task 3's validator is now the thing to reuse, not to rewrite.**
`.datom_validate_rel_key()` (`R/utils-validate.R`) guards any *caller-supplied* whole key. The
Task 1 key builders in `R/utils-path.R` deliberately do **not** call it -- they compose keys from
parts already validated by `.datom_validate_name()` / `.datom_validate_sha()`, so their output
cannot contain a `..` segment or a `datom` segment and the check would be dead code. Reach for the
validator when a key arrives from outside datom; reach for the builders when datom composes one.

**THE GOLDENS ARE PUBLISHED AS OF TASK 2, SO THE ENCODING IS FROZEN.** Changing any sv1 byte rule
from here is a conscious `datom-sv2` bump with a new `hash_algo` identifier -- not a spec edit, not a
code fix. The three places that hold it: `R/hashable-set.R` (implementation),
`dev/datom_sv1_reference.R` (normative byte rules + marker table), and the hard-coded constants in
`tests/testthat/test-hashable-set.R`. If a golden ever fails, the code drifted; do not update the
constant. E1's discharge record and the four deltas it produced are in the Decisions log
(2026-08-17); nothing about it is open.

**Open with the owner**: **nothing.** Task 6's six defaulted items were all taken at their defaults on
2026-09-08 and each is recorded with what shipped in that task's DONE record; its purity audit is
discharged. **One of the six was later reversed** by review and is logged as a reversal:
`datom_list()`'s empty result now carries the columns a populated one does, where the recorded default
had been to leave that difference alone. Nothing else is open either: the
AC33(a) anchoring item that sat here on 2026-08-26 was decided the same day and **implemented as
decided on 2026-08-28** -- the realistic fixture was pinned in its own commit under the pre-change
code, and the `name`-bearing golden became AC33(b)'s test.

**Also on this branch, outside the task list**: three operator-facing fixes -- two that followed
Task 18 (the merge-conflict message, and `datom_validate(fix = TRUE)` no longer claiming to repair a
missing payload) and one that followed Task 5 (terminal escape codes stripped from the three error
strings datom *returns*, rather than prints) -- plus
[#105](https://github.com/amashadihossein/datom/issues/105) and a `dev/README.md`
Backlog row capturing five deferred ideas for making a push-rejected write rarer and recoverable
without git skill. Nothing there blocks Task 6.

**Superseded note**: this slot previously read "nothing". Task 2 added three encoder refusals the spec did not spell out
(named list in a value position; unexpected field at the payload root or in a member record) -- all
three prevent content sitting outside identity, none changes a golden, and all are logged below
(2026-08-18) rather than left to be rediscovered.

**Before each commit** (the chunk gate):

```
Rscript -e 'devtools::test()'      # report the count; it must not drop
Rscript dev/check-spec.R           # structural gate on this spec -- see dev/README.md
```

`check-spec.R` runs **nine** checks: dangling `R*/I*/P*/AC*` references, orphaned criteria, task
numbering, tasks missing an `Acceptance:` clause, code citations pointing outside the file, retired
wording surviving as a live instruction, **duplicated content agreeing** (check 6), ASCII, and
**every `Task N` reference resolving to a task that exists** (check 8, added with the 2026-08-23
renumber and verified by reintroducing a dangling reference).

**Check 6 guards the encoding pseudocode**, which is written out in all three spec files: it asserts
all six encoder rules are present in every file and byte-identical modulo whitespace. That exists
because a delta once fixed the formula in `design.md` only, leaving `requirements.md` and `tasks.md`
stating the opposite *inside the task that froze the goldens*. Now that the goldens are published the
pseudocode is a **record of what shipped**, so a disagreement between the three copies is a
documentation defect rather than an implementation risk -- and the copy that matters most is the one
the next reader trusts.

**Check 6 also guards the execution order**, added 2026-09-10 for the same reason: the
`18 -> 19 -> ...` sequence is written out three times -- the state block at the top of this file,
Phase E's preamble further down, and the status cell in `dev/README.md` -- and adding Task 23 swept
one and left two saying the order ended at Task 7. Caught by a reader, which is what a gate is for.
The copies are compared **against each other**, never against an expected sequence, because the order
changes legitimately and a check holding today's answer would need editing every time it moved.
`dev/README.md` is read for this one clause even though it is not a spec file, since that is where the
third copy lives and the one a person meets first. Verified by reintroducing the exact defect: both a
stale preamble and a stale README FAIL, and the output names which copy is behind.

It is **structural only**, and do not over-trust it: on the round that added check 6 it passed on all
six sites of the defect it was supposed to catch, because its retired-wording suppression list was
too permissive. Both it and check 6 have since been **verified by deliberately reintroducing the
defect** and confirming a FAIL. Do that for any new check you add -- a green run is not evidence.
Reasoning defects still need a reader.

**Read before editing `R/`**: `dev/engineering-notes.md`. The three most relevant entries for the
remaining tasks are the **two key shapes** (full vs relative -- mixing them double-prefixes
silently and does not error), **payload key vs snapshot key** (different directories, both `.json`
for a set), and the new **`datom-sv1` set identity** section (what the encoder refuses and why, and
the one trap that a test caught during Task 2).

**One repeating defect pattern, worth knowing.** Five review rounds found the same class: an encoding
change swept some places and left others stating the old mechanism -- the invariant/property tables in
design.md, Task 2's own bullets, the pseudocode copies. The last round left **six** such sites and the
gate passed on all six.

What to do if you change the encoding -- which now means shipping `datom-sv2`, so all of this applies
to the *new* regime's documentation, and the sv1 copies become historical rather than edited:

1. **Pseudocode: edit all three copies** (`requirements.md` R2.10, `design.md` 7.2, `tasks.md` Task
   2). Mechanically guarded now -- check 6 will catch you.
2. **Prose: sweep requirements, the design invariant/property tables, and the task bullets**, then add
   the retired phrasing to the `retired` denylist in `dev/check-spec.R`. Not mechanically guarded
   until you add the phrase.
3. **Counts and ranges: never restate one.** A spelled-out criteria count and a literal
   first-to-last AC range both went stale here; check 6 now forbids an explicit AC bound anywhere in
   the spec. Derive the list, don't restate its edges. (Check 6 is strict enough that even *quoting*
   a stale range as an example trips it -- which is why this bullet describes the shape in words.)
4. **Prove any new gate fails before trusting it.** Two consecutive rounds shipped a check that
   passed on the defect it existed to catch.

One task (or a small related group) = one chunk = one commit. Mark the checkbox in the **same
commit** as the code, and update the `dev/README.md` Active Specs status line. Per Operational
Discipline rule 5d, **STOP after each chunk** and wait for explicit go-ahead.

**Escalation flags** (design.md section 12) are marked inline. A flagged task **must** re-surface
its escalation recommendation in that chunk's checkpoint message, whether or not it still seems
necessary.

---

## Task 0 -- Spec creation

- [x] **0. Create the spec and register it**
  - `.kiro/specs/datom-sets/{requirements,design,tasks}.md` translated from #89 at full detail
  - Register in the `dev/README.md` Active Specs table
  - Prerequisite #95 (copilot-instructions compatibility posture) landed on `dev` separately via
    PR #96, deliberately outside this branch's history
  - _No code. Docs only._

---

## Phase A -- Contract-neutral groundwork

- [x] **1. Housekeeping: stale docstrings + relative-key helpers**
  - Fix the stale "task 5.1" `parquet_sha` claims at `R/read_write.R:110-113`, `205-206`, `413`,
    and reword the already-correct-but-now-inconsistent comment at `393` (R13.3 has the site
    table). History **has** persisted `parquet_sha` since #72; only pre-#72 legacy entries lack
    it. Drop the internal task references entirely per the Don'ts. **Note #89's `95-97` citation
    is wrong** -- that is the function title; verified with `grep -n "task 5\.1"`.
  - Add `.datom_artifact_payload_key()` / `.datom_artifact_meta_key()` /
    `.datom_artifact_snapshot_key()` to `R/utils-path.R` -- **relative** keys, per design.md
    Deviation D1. `.datom_build_storage_key()` stays unchanged as the backend-internal full-key
    builder.
  - Fold `.datom_validate_sha()` / `.datom_validate_name()` guards into the helpers (I9).
  - Migrate existing `paste0` key call sites in `R/read_write.R`, `R/query.R`, `R/lineage.R`,
    `R/validate.R` to the helpers. Behavior-identical -- assert with the existing suite.
  - File the separate issue for the `metadata_sha` emitter-drift exposure (design.md section 16).
    Do **not** implement it here.
  - **DONE 2026-08-17.** Filed as [#98](https://github.com/amashadihossein/datom/issues/98).
    Four stale "task 5.1" docstrings reworded (105-108, 205-206, 393, 413) plus **three
    pre-existing phase/chunk comments** the Don'ts forbid, found while sweeping
    (`R/conn.R`, `R/governance_json.R`, `R/utils-gov.R` -- the last was doubly stale, pointing at
    a gov write surface that has since been lifted out). Three relative-key helpers added to
    `R/utils-path.R` and **16 of 17** hand-rolled key sites migrated across 7 files
    (`read_write.R`, `query.R`, `lineage.R`, `validate.R`, `sync.R`, `utils-sha.R`).
    tests: **2482** (+22).
  - **Deliberate exclusion**: `R/sync.R:307` still builds its key with `paste0`. It splices a
    *discovered filename* (already `{sha}.json`) rather than a bare sha, so the helper's sha guard
    does not fit, and adding one would change behavior -- a stray `.json` in `.metadata/` would
    start aborting instead of being uploaded. Commented in place.
  - **SCOPE DEVIATION -- OWNER-APPROVED 2026-08-17, the guard stays.** This chunk was scoped
    behavior-identical,
    and folding `.datom_validate_sha()` into the payload-key helper is **not**: it closed a real gap
    (`.datom_validate_one_table()` spliced `meta$data_sha`, read from a file, into a storage key with
    **no** validation -- #74's guard sweep missed this site, so a corrupt or hostile `metadata.json`
    containing `../../x` could probe outside the namespace on the local backend). One test fixture
    used `data_sha = "d1"`, a value that cannot occur in real data since every sha is 64 hex, and it
    was updated to a realistic digest. Observable behavior for *valid* data is unchanged, and a new
    test pins that a corrupt `data_sha` still surfaces as a `data_missing_s3` finding rather than
    aborting the validation run.
  - _Requirements: R5.2, R13.3. Invariants: I9. **Acceptance: none by design** -- this chunk is
    contract-neutral (docstring wording plus behavior-identical key helpers), so the existing
    suite passing unchanged *is* the assertion. Recorded explicitly so the absence is not read as
    an omission. No pathway impact._

- [x] **2. `datom-sv1` canonical set-content hash** &nbsp; **[ESCALATION E1 -- design review DONE 2026-08-17; implemented 2026-08-18. The goldens below are PUBLISHED: the encoding is frozen.]**
  - **All five open questions are settled** (owner-decided 2026-08-15, design.md 7.5). The
    escalation is now a **design review of the encoding specification**, not a debate: exact byte
    rules, whether the tag table leaves a collision surface, and whether the goldens cover the
    7.3 agreement cases. The goldens still freeze the encoding -- a later change needs a conscious
    `datom-sv2` bump.
  - **Q1 whole payload.** `data_sha` covers members **and** their tags (a description is a tag). A tag
    or description edit **mints a new version** -- intended, not a bug to engineer away (R2.6).
    This makes AC2 two-sided: identical *payload* is a no-op, identical *members with a changed
    tag* is **not**.
  - **Q2 absence is omission; `NA` is an error.** Adopt datom's existing "omitted, not nulled"
    convention (`R/read_write.R:303-314`) as the canonical form. A literal `NA` reaching the
    encoder **aborts** with "not encodable -- omit the field instead". Goldens carry the
    **refusal**, not an `NA` encoding. Note `null` therefore has **no marker** in the encoding (R2.7).
  - **Q3 empty set refused.** `datom_write_set()` with zero members aborts, mirroring
    `.datom_canonical_hash()`'s zero-dim abort (`R/utils-sha.R:310-312`). Update AC5: refusal is
    the tested behavior (R2.8).
  - **Q4 `schema_version` stays out** of the payload and the hash -- container format, not content;
    in identity it would re-mint every set on a format bump (R2.9).
  - **Q5 emitter-free hash.** **No serializer in the identity path.** The construction is the
    hash-of-hashes in the next bullet -- **not** a walk with per-type dispatch, which was the
    superseded formulation (F-A). `jsonlite` may format the **stored** file however it likes,
    because stored-byte integrity is `document_sha`'s separate job. **Identity and storage integrity
    never share a dependency.**
  - **The encoding is a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10, design.md 7.2),
    **not** a runtime type-dispatch walk -- that earlier formulation had a structural gap (F-A) and
    is superseded:

    ```
    str(s)    = h(0x01 || utf8(s))
    strset(v) = h(0x02 || concat(str(e) for e in sort(unique(v), radix)))
    map(m)    = h(0x03 || concat(str(k) || strset(m[k]) for k in sort(keys(m), radix)))
    member(x) = h(0x04 || map(x.id) || map(x.tags))
    set(p)    = h(0x05 || map(p.tags) || concat(sort(unique(member(m) for m in p.members), radix)))
    data_sha  = h(0x06 || utf8("datom-sv1") || set(payload))
    ```

    Member digests sort as **lowercase hex**, `method = "radix"`, emitted as raw bytes.

    Mirrors cv1's per-column-digests-then-hash-the-concatenation pattern, so both references share
    one house construction.
  - **No length prefixes**: every intermediate is a fixed 32 bytes, so concatenation is already
    unambiguous. **`f64le` disappears from sv1 entirely** -- `.datom_encode_numeric()` is not used
    at all, not even for lengths. sv1 shares no numeric primitive with cv1.
  - **Every collection is sorted and deduped -- `members` included, with no carve-out.** An earlier
    draft made member order identity; **retired** (R2.12 carries the three arguments, chiefly that a
    script-generated member list would mint spurious versions on an insertion-order refactor).
    Sorting members means sorting their fixed 32-byte digests. A single string equals a one-element
    set (R2.13).
  - **No Unicode normalization** (R2.16). Radix sort is byte order; NFC and NFD are different tags.
    Golden asserts they differ. Do not add `stringi` -- normalization tables are versioned Unicode
    data, and putting them in the identity path is #72's failure mode with a different vendor.
  - **Pin `strset(character(0)) = h(0x02)`** as a golden (R2.17), for the same reason design.md 7.2 already
    pins the empty map: an encoder whose correctness rests on an upstream validation refusal breaks
    silently the day that refusal is relaxed.
  - **Not this task, but caused by it -- flag it forward.** Order- and shape-insensitivity means
    several spellings share one `data_sha`, which is a write-path correctness problem, not an encoder
    one: R2.15 (canonicalize before the local write) and R7.5 (never re-emit for a known `data_sha`;
    bind `validate(fix = TRUE)` too). Owned by Tasks 9 and 14. Design.md 7.2.3 explains why. Left
    undone, the failure is a **refused read of a valid version**, and every per-chunk test passes.
  - **`id` is encoded with `map`, not positionally**, so a fifth id field later is just another key.
    Validation, not the encoder, enforces "id has exactly these four keys, each single-valued".
  - **The encoder does NOT validate, and this task does not own AC27.** Grammar enforcement lives in
    `.datom_validate_members()` (Task 8, per-member) and `datom_write_set()` (Task 9, payload-level),
    because design.md 7.2 and R2.10 both put the encoder out of validation's job -- and because the
    payload-level cases are invisible from here: the encoder never sees two members at once in a way
    that distinguishes "same `id`, different `tags`" from two ordinary members. An earlier draft had
    Task 2 and Task 9 both claiming AC27; **retired**.
  - Payload shape is **fixed** (R2.12): optional set-level `tags`, then `members[]` each with
    an `id` record `{project, name, kind, version}` and optional per-member `tags`. Depth is bounded by the schema,
    not by what a caller nests.
  - **The R2.5 hard constraint still governs**, with its mechanism restated: write-time and
    read-time hashes must agree, and they now do **by construction** rather than via a
    serialize/parse cycle. Every mutation is **unrepresentable**, not handled (design.md 7.3):
    numbers and booleans are not in the grammar; `NA` aborts; `null` has no marker; and
    scalar-vs-one-element-array is **immaterial because the two hash equal** (R2.13). **Do not write
    an f64 rule and do not write an atomic-vs-list rule** -- both were removed, and an earlier draft
    of this bullet still instructed them. The one supporting condition is structural: read with
    `simplifyVector = FALSE` so `members[]` stays a list of records rather than collapsing to a data
    frame. **Already satisfied** by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`).
  - `.datom_sv1_str()` / `.datom_sv1_strset()` / `.datom_sv1_map()` +
    `.datom_canonical_set_hash()` go in a **new `R/hashable-set.R`**. *(Decided at the E1 review,
    2026-08-17 -- an earlier draft left this as "decide at the review", which would have dangled once
    the review closed.)* Rationale: cv1's equivalents sit in `R/utils-sha.R`, already 565 lines and
    holding three unrelated concerns (`.datom_encode_numeric`, `.datom_canonical_hash`,
    `.datom_compute_metadata_sha`); sv1 shares **no** primitive with any of them, so co-locating buys
    nothing and worsens the biggest file. A sibling file also mirrors the existing
    `R/hashable.R` naming, which is where #72 put the cv1-adjacent surface.
    **`.datom_encode_numeric()` is NOT used** -- sv1 has no numeric primitive at
    all now that length prefixes are gone, so there is nothing to share with cv1 beyond
    `digest::digest(..., algo = "sha256", serialize = FALSE)`. (Superseded instruction: an earlier
    draft said to reuse it verbatim for `f64le` framing.)
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`. It is the **normative home of the byte rules and the tag
    table**, written against the encoding spec and **not** against any emitter's output.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run the
    sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - **Goldens are gated on this delta landing** -- post-goldens, any of the above becomes a breaking
    `datom-sv2` bump rather than a spec edit. Hard-coded in tests, cross-architecture asserted, and
    covering the **seven** identity-boundary fixtures of AC13, which is authoritative -- **Equal**:
    (a) tag-value order, (b) tag-value duplication, (c) **member order**, (d) single string vs
    one-element array, (e) member duplication. **Different**: (f) NFC vs NFD. **Pinned constant**:
    (g) `strset(character(0)) == h(0x02)`. Note (c) and (d) each **reverse** an earlier fixture that
    required a difference. Plus the AC27 grammar refusals.
  - **DONE 2026-08-18.** New `R/hashable-set.R` (the encoder: `.datom_sv1_str/_strset/_map/_member/_set`
    plus `.datom_canonical_set_hash()` and two byte helpers), new `dev/datom_sv1_reference.R`
    (standalone, `digest`-only, **44** self-tests, prints the goldens), new
    `tests/testthat/test-hashable-set.R`, and `.github/workflows/cv1-reference-parity.yaml` extended
    in place to run the sv1 reference and both parity test files on x86_64 and arm64 with the
    existing nothing-may-skip assertion. No new export, so NAMESPACE and `_pkgdown.yml` are
    untouched; nine internal `man/dot-datom_sv1_*.Rd` pages generated. tests: **2572** (+90),
    FAIL 0 / WARN 0 / SKIP 0.
  - **The published goldens** (recorded here so a reader need not run anything to know what is
    frozen):

    | Constant | Value |
    |---|---|
    | `strset(character(0))` = `h(0x02)` | `dbc1b4c900ffe48d575b5da5c638040125f65db0fe3e24494b76ea986457d986` |
    | `map(NULL)` = `h(0x03)` | `084fed08b978af4d7d196a7446a86b58009e636b611db16211b65a9aadff29c5` |
    | `str("a")` | `e3254ea61c09ead5a01d3bf07e946a561c6c2cd1c46b8ca1bfa8729d26a7d09f` |
    | golden payload `data_sha` | `e87c6e7be35a0198356e19a77d1acdd57e8f17f3f425320f3297206583d36c7a` |
    | minimal payload `data_sha` | `f434fcd31c1393721087859182cbdd9fad0372b65dc1dfd6b36d2cfe14c3e782` |

    The three primitive pins were **cross-checked against an independent SHA-256 implementation**
    (`printf '\x02' | shasum -a 256` and friends), so they assert that the marker bytes really are
    what the specification says rather than only that datom agrees with itself. Intermediates are
    pinned as well as the final values, carrying forward the cv1 lesson that a golden mismatch which
    names the *stage* is a quick fix while one that names only the total is a bisect.
  - **THREE ENCODER REFUSALS THE SPEC DID NOT SPELL OUT.** All three exist for one reason -- an
    ignored field is payload content that never enters identity, so two different payloads would
    share one `data_sha` **and one storage address**. That is the failure the whole regime exists to
    prevent, so silence was not an option; and none of them changes a golden.
    1. **A named list in a value position is refused.** This is the sharp one, and a test caught it
       while being written. Element-wise, `list(b = "c")` and `list("c")` are indistinguishable: both
       are a one-element list holding one string. An encoder that checked only elements would
       therefore hash `{"a": {"b": "c"}}` exactly as `{"a": ["c"]}`, silently dropping the inner key
       out of identity. The check is `is.list(v) && !is.null(names(v))` -> abort.
    2. **An unexpected field at the payload root is refused** -- which is also how R2.9 becomes
       structural rather than aspirational: a payload carrying `schema_version` aborts instead of
       being quietly hashed without it.
    3. **An unexpected field in a member record is refused** (anything besides `id` and `tags`).
  - **Two implementation notes for anyone touching the encoder.** Intermediates are **raw 32-byte
    vectors, not hex** -- hex appears in exactly two places, the member collation key and the final
    `data_sha`, which is what the spec names. And the `NA` refusal sits **after** the type gate,
    except for an all-`NA` logical which is caught before it: `is.na()` on a closure warns rather
    than answering, so a `tags = list(t = mean)` fixture emitted a warning against a suite that holds
    at WARN 0. A bare `NA` is a logical, so it still reports "omit the field" rather than a type
    error, which is the advice R2.7 wants.
  - **`strset(list())` equals `strset(character(0))`.** `[]` is the parsed spelling of an empty
    string set, and write/read agreement requires the two to hash equal -- so the R2.17 pin covers
    both spellings, not just the R one.
  - **AC13-P is asserted through the real local-backend store** (`.datom_storage_write_json()` ->
    `.datom_storage_read_json()`), not a hand-rolled `jsonlite` round trip, so it also proves the
    backends preserve `members[]` as a list of records. That structural condition is additionally
    asserted on the parsed object directly rather than inferred from the hashes matching.
  - **Deliberately not done here** (flagged forward, unchanged): R2.15 canonicalization and R7.5
    byte-identity are Tasks 9 and 14; AC27 grammar enforcement with user-facing recourse is Tasks 8
    and 9. The encoder refuses what it cannot encode; it does not name offending keys with remedies.
  - _Requirements: R2.1-R2.14, R2.16, R2.17 (**not** R2.15 -- that is Task 9's, per the flag-forward
    bullet above). Invariants: I13, I24. Properties: P1, P2, P3, P4, P5, P6,
    P8, P12, P15, P28, P30, P31, P33. Acceptance: **AC13 (both levels)**, AC3, AC5. **Not AC27** --
    see the encoder-does-not-validate bullet. No pathway impact._

- [x] **3. Export and harden storage JSON GET** &nbsp; **[SCOPE REDUCED 2026-08-18: the write export is dropped; DONE 2026-08-21]**
  - **Deliverable: `datom_storage_read_json()` only.** Wraps `.datom_storage_read_json()`
    (`R/utils-storage.R:66`). Harden: conn class check, relative-key validation, clear abort on an
    absent key, no direct `.datom_s3_*()` reachability (I7).
  - **`datom_storage_write_json()` is NOT built.** Owner-decided; R12.4a, I14 and AC23 are retired
    with it and P18 is restated. The short form: the export's stated purpose was to let a downstream
    package write *its own document* into datom's namespace, that document was a set, and
    `datom_write_set()` (Task 9) now writes it as a first-class artifact -- so no consumer remains.
    It also cuts against the Authority Principle in `dev/datomanager_scope.md` ("data-repo mutations
    always route through datom ... datomanager never touches the data repo directly"), whose
    expression is a **purpose-built verb per need**, not a generic byte channel; the
    `governance.json` data-side mirror is the precedent, where datom gave datomanager
    `datom_repo_attach_governance()` rather than a generic write. Deferral is the cheap direction:
    adding an export later is additive, removing one after release is breaking. Backlog trigger is
    recorded in `dev/README.md` -- **datomanager needing to write JSON into its own gov namespace**,
    which is a *different* export (gov-scoped, no managed-key rules) and must re-derive its refusal
    list rather than inherit R12.4a's.
  - **Do not add a role check.** Reads are policy-free and no `datom_storage_*` export checks
    `conn$role` (see the landing-zone table).
  - **Landing zone, verified against the tree 2026-08-18** (so a fresh session does not have to
    re-derive any of it):

    | What | Where | Note |
    |---|---|---|
    | file for the export | **`R/storage.R`** | its header states the family contract ("exported wrappers over the internal storage dispatch layer") and the naming split `datom_storage_*` vs `datom_repo_*`. Not a new file. |
    | roxygen example to copy | `datom_storage_list()` (`R/storage.R:51`, example block just above it) | this **is** "the established bare-git-remote + local-store style": `requireNamespace("git2r")` guard, `tempfile()`, `git2r::init(bare = TRUE)`, `datom_store(validate = FALSE)`, `datom_init_repo()`, `datom_get_conn()`, `datom_write()`, `unlink()`. All four existing storage exports use it verbatim. |
    | pkgdown entry | `_pkgdown.yml`, the package-developer storage section (currently lists the four `datom_storage_*` plus two `datom_repo_*`) | add the new export there; the index must match exports exactly or `pkgdown::build_site()` errors. |
    | tests | `tests/testthat/test-storage.R` | reuse its `make_local_storage_conn()` fixture for the local backend and its `mockery` pattern for S3. |
    | role check | **none** -- no existing `datom_storage_*` export checks `conn$role`, including the destructive `datom_storage_delete_prefix()` | the family is deliberately policy-free; role gating lives on the git-mutating verbs (Task 12). Do not add one here without deciding to break that symmetry. |
    | `.access/` today | **appears nowhere in `R/`** (verified by grep) | R19.6's "safe by construction" claim therefore holds as stated -- and with the write export dropped, datom still offers no general-purpose write path, so nothing in this task can break it. |
  - **There is no relative-key validator to reuse** -- `R/utils-validate.R` has only
    `.datom_validate_name()` (`R/utils-validate.R:28`) and `.datom_validate_sha()`
    (`R/utils-validate.R:78`), and nothing validates a key. So "relative-key validation" means
    writing it. Two things it must catch, and they are different in kind:
    1. **Traversal / shape** (`..` segments, leading `/`, empty, non-scalar) -- an I9 concern, and it
       applies to a **read** as much as to a write. "Reads are unrestricted" was always about
       *managed keys*, never about escaping the namespace: on the local backend an unvalidated
       `../../x` walks out via `fs::path()`, which is what #74's guard sweep existed for. This is
       the load-bearing half of the task now that the write export is dropped.
    2. **A full key passed where a relative one belongs** -- the double-prefix hazard in
       `dev/engineering-notes.md`. Worth catching because it does **not** error today: the call
       resolves under `{prefix}/datom/{prefix}/datom/...` and simply finds nothing, which reads as
       "the object is missing" rather than "the key was wrong". A key already containing a `datom/`
       segment is the detectable form.
  - **P18 needs nothing from this task.** Restated with the write export's removal: no public API can
    put storage ahead of git because every public write is a purpose-built verb that commits first --
    a read cannot violate it at all. Do not add a git gate to a byte-level primitive.
  - Roxygen with a runnable offline example in the established bare-git-remote + local-store style
    (exemplar cited above); `_pkgdown.yml` entry.
  - **DONE 2026-08-21.** New `.datom_validate_rel_key()` in `R/utils-validate.R` (the validator that
    did not exist), new export `datom_storage_read_json()` appended to `R/storage.R`, `_pkgdown.yml`
    entry in the existing Storage Extension API section, two `man/` pages, NAMESPACE. Tests split by
    subject: validator units in `tests/testthat/test-utils-validate.R`, export behavior in
    `tests/testthat/test-storage.R` reusing `make_local_storage_conn()` for local and `mockery` for
    S3. tests: **2612** (+40), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all eight checks
    pass. Landing zone was accurate as recorded -- nothing in the verified table had drifted.
  - **The absent-key abort probes `.datom_storage_exists()` up front**, costing one extra round trip
    per read. Bought deliberately: the local backend already aborts clearly, but S3 surfaces the
    provider's error naming the **full** key, which is precisely the wrong thing to show a caller
    whose bug is key-shape confusion. One message, both backends, and it names the relative key that
    was passed.
  - **The full-key refusal keys on a `datom` path segment**, and that is sound rather than heuristic:
    `datom` is in `.datom_reserved_names` (`R/utils-validate.R:4-7`), so no legitimate relative key
    can contain it as a segment. Verified in the same pass that the guard is on a whole `..` segment
    and not on the dot character -- `.metadata/manifest.json`, `my.data/abc.json` and
    `dm/..hidden.json` all still pass, each with a test.
  - **No role check, as specified**, and now pinned by a test rather than left as an absence: a
    `role = "reader"` conn reads successfully. The family symmetry (no `datom_storage_*` export gates
    on role, including the destructive delete) cannot now be broken silently.
  - **Deliberately NOT retrofitted into the Task 1 key helpers.** They compose keys from parts already
    validated -- `.datom_validate_name()` admits only `[a-zA-Z0-9_ ()-]` and must start with a letter,
    `.datom_validate_sha()` only hex -- so their output cannot contain a `..` or `datom` segment and
    the check would be dead code. Recorded because the two guards look like duplicates and the
    obvious "cleanup" is to merge them; the distinction is *composed from validated parts* versus
    *supplied whole by a caller*.
  - _Requirements: R12.4 (narrowed to GET; R12.4a retired with the write export). Invariants: I7
    (I14 retired). Properties: P18 (satisfied without new code -- a read cannot violate it).
    Acceptance: **none of the set-specific ACs** -- AC23 was the only one this task carried and it is
    retired with the export it tested. The assertions are the hardening tests themselves: non-conn
    refused, traversal refused, full key refused, absent key aborts clearly, and a round trip through
    the local backend returns the parsed object. Recorded explicitly so the absence is not read as an
    omission. No pathway impact._

- [x] **4. `schema_version` gate (reader side)** &nbsp; **[DONE 2026-08-21]**
  - `.datom_check_schema_version(meta, source)` -- one implementation, one message.
  - Wire into **both** entry points: `.datom_read_metadata()` (the `datom_read()` path, which
    never touches the manifest -- verified `R/read_write.R:58-65`) and the manifest readers
    (`datom_list()`, `datom_summary()`, `datom_status()`).
  - `SUPPORTED_SCHEMA <- 2L`. Asymmetric: refuse newer, tolerate older; absent defaults to `1`.
  - Add `schema_version` **and** `document_sha` to the `volatile` list (that list is now
    `.datom_metadata_excluded_fields`, `R/utils-sha.R:467-470`, promoted from a local variable by
    Task 19; both names are still on it).
  - Nothing wrote `schema_version: 2` at the time this task shipped -- the gate landed
    tested-but-inert on purpose, so that Task 6's writer bump could not be the first exercise of
    untested gate code. Task 6 has since landed and the gate now fires.
  - _Requirements: R9, R7.4. Invariants: I4. Properties: P10, P11. Acceptance: AC7._
  - _Pathway impact: read route gains a version gate -- update `dev/datom_pathways.md`._
  - **DONE 2026-08-21.** New `.datom_check_schema_version()` + `.datom_supported_schema` in
    `R/utils-validate.R`, wired into **six** call sites (see the next bullet), both names added to
    the `volatile` list with the roxygen rationale paragraph updated alongside it, and two route
    cards in `dev/datom_pathways.md` (the existing read route gains step 2a; a new
    "can this build read this repo" card carries the call-site list and the tryCatch warning).
    tests: **2660** (+48), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all eight checks
    pass. Also not a task: `.kiro/steering/communication.md`, recording the owner's chat-response
    conventions after this task's design round needed three restatements to land.
  - **SIX call sites, not the four the task named** -- owner-approved scope widening. The task
    listed the reader paths that go through storage; the same manifest is also read from the git
    clone by `datom_sync_manifest()` and `.datom_status_input_files()`, and that copy can be ahead
    of the installed build by an ordinary route: a collaborator upgrades datom and writes, this
    developer pulls. Left ungated, those two commands read a manifest shape this build does not
    know. The four in-pipeline local reads (`R/sync.R:202`, `R/read_write.R:848`,
    `.datom_update_manifest_entry()`, `R/validate.R:257`) were **deliberately excluded** at the time:
    the check belongs where a document enters datom, so a refusal happens before work starts rather
    than partway through a write. **Two of those four are no longer excluded, and the record is left
    here rather than rewritten**: Task 6 routed the mirror route's read through the shared reader, so
    it is checked and converted, and Task 21 put the whole write entry on the function that read sits
    in -- because `datom_validate(fix = TRUE)` calls that function directly and so never passed
    `datom_write()`'s door. The entry updater and `datom_validate()`'s project-name read are still
    excluded, for the reason stated.
  - **THE WIRING IS NOT SIX IDENTICAL ONE-LINERS, and that is the whole difficulty of this task.**
    Three of the six wrap their read in error handling that softens failures, so a check placed
    inside it produces a *different* outcome per site. `datom_list()` and `datom_summary()` would
    reword the upgrade instruction as "Could not read manifest", demoting the only actionable line
    to a footnote. `datom_status()` is worse: its handler downgrades errors to
    `available = FALSE` and continues, so that one command would stay silent while the other five
    stopped -- the exact degradation R9 exists to end. All three now read inside the handler and
    check outside it, with a comment at each site saying why. `datom_status()`'s block was
    restructured for it, and a test pins that an *ordinary* storage failure is still tolerated --
    making the schema check fatal must not make an unreachable bucket fatal.
  - **Two condition classes, so "all six behave the same" is provable rather than asserted**:
    `datom_schema_unsupported` (too new) and `datom_schema_invalid` (present but unusable). Every
    site's test asserts the class, not the message text.
  - **A present-but-unusable value aborts rather than being coerced**, which the requirement did
    not specify. Two reasons, either sufficient: `as.integer("two")` is `NA`, and `NA > 2` reaches
    `if()` as "missing value where TRUE/FALSE needed" -- an internal-looking error for what is
    really a corrupt file; and a string comparison against a number can read as *supported* by
    accident. Refused: non-numeric, `NA`, fractional, `< 1`, non-scalar, logical, list.
  - **Constant is `.datom_supported_schema`, not R9's `SUPPORTED_SCHEMA`** -- house style for
    internal constants (`.datom_reserved_names`, `.datom_import_formats`). R9's spelling is
    pseudocode. Note the leading dot makes it a **cli style** inside a message string, so it is
    spliced as `{(.datom_supported_schema)}`; a test asserts the ceiling renders as `v2` rather
    than vanishing into markup.
  - **The write side is NOT covered here, and it is the more damaging direction** -- an older build
    writing into a newer repo produces a manifest that is half one format and half the other.
    Assigned to Task 6 rather than bolted on here: a write is several steps (local files, one
    commit, then the storage mirror), so the check has to sit ahead of all of them, and Task 6 is
    where those steps are in view. Owner-decided 2026-08-21.
  - **Adding the two names to `volatile` is inert for every document already written**, since no
    metadata carries either field yet -- so I4 holds by construction rather than by migration. A
    test asserts presence-versus-absence of both is immaterial to `metadata_sha`, so the inertness
    is pinned rather than inferred from the suite staying green.
  - **The boundary is strictly greater-than**, with its own test. At `>=` the entire read path
    would break the moment Task 6 writes `schema_version: 2`.
  - **Spec code citations were re-derived** after these insertions shifted line numbers in five
    files (`R/query.R`, `R/read_write.R`, `R/summary.R`, `R/sync.R`, `R/utils-sha.R`) -- including
    every site in Task 6's checklist, which would otherwise have sent the next session hunting.
    Verified by content with `SPEC_CHECK_SHOW_CITATIONS=1`, not by arithmetic: two were already off
    by one before the shift. **Bare numbers inside historical log rows were left as-is** -- the
    2026-08-17 row that records one citation being corrected to another still names the old number,
    because it documents what was true on that date; only live `path:line` citations were updated.
    (The literal pair is not repeated here: check 4 now fails on a citation resolving to a blank
    line, and quoting a deliberately-wrong number would trip it -- the same call as the check 6 note
    below about quoting a stale AC range.)

---

## Phase B -- Manifest namespace **[BREAKING]**

**One change, two commits.** Task 5 moves every manifest read and every empty-manifest default onto
one internal helper and changes nothing observable. Task 6 then renames the key, in that one place.
**Split on 2026-08-23** (owner-decided, after the design audit below): as a single task it had grown
to a nine-site rename plus a write-side refusal, five counter filters, two read consolidations, an
old-format transition and a fixture sweep across ten test files -- and its failure mode is silent, so
a green suite is not evidence that any of it worked. Task 5 is the part that can be verified on its
own; landing it first is what makes Task 6's failure loud.

- [x] **5. One manifest reader, one skeleton builder** &nbsp; **[contract-neutral; DONE 2026-08-29]**
  - **The problem this exists to make fixable.** After the rename a reader looks for `artifacts`
    while every repo written so far says `tables` and carries no `schema_version` field at all. The
    reader-side check does not stop it: it tolerates an absent version as v1
    (`R/utils-validate.R:257`), so the repo passes and the reader then finds nothing where the list
    should be. `datom_list()` returns an empty frame (`R/query.R:94`), `datom_summary()` reports
    zero (`R/summary.R:68`), `datom_status()` reports zero (`R/query.R:488`), and **nothing errors**
    -- the failure E2 exists to prevent, arriving through the front door instead of through a
    partial rename. `datom_read()` is unaffected (it never touches the manifest,
    `R/read_write.R:93`), so this is a discovery blackout rather than data loss. Silence is what
    disqualifies it, not severity.
  - **Fixing it needs one place to stand.** There are five manifest reads today, each with its own
    absent-file default and its own failure policy, so an upgrade added now would be added five
    times. This task creates the one place; Task 6 uses it.
  - **New: `.datom_read_manifest(conn, scope)`** in `R/sync.R`, where `scope` selects the storage
    copy (`.metadata/manifest.json`) or the clone copy (`.datom/manifest.json`). It returns a
    **result record**, not a bare document: `list(ok =, absent =, manifest =, error =)`.
  - **The load-bearing detail is which failure is returned and which is thrown.** An IO failure is
    returned as data (`ok = FALSE`); a schema refusal is **thrown**. That is what makes it
    impossible to soften the upgrade message by accident. Task 4 found three readers wrapping their
    read in a handler that softens failures, and a check placed inside one reworded the upgrade
    instruction as "could not read manifest" -- `datom_status()` went further and downgraded it to a
    warning while continuing. Until this task, that placement was preserved by a comment at each of
    those three sites; now it is preserved by the shape of the helper, because there is no handler
    left for a caller to put the check inside. (Those comments are gone, so the line citations they
    carried are not reproduced here.)
  - Route the five read sites through it, each keeping its **current** failure behaviour verbatim
    (call sites as shipped): `datom_list()` (`R/query.R:80`) and `datom_summary()`
    (`R/summary.R:50`) abort with their own wording on an unreadable manifest; `datom_status()`
    (`R/query.R:468`) still tolerates one and reports it unavailable;
    `.datom_status_input_files()` (`R/query.R:579`) and `datom_sync_manifest()` (`R/sync.R:602`)
    still fall back to an empty manifest when the clone has no file.
  - **New: `.datom_manifest_skeleton(project_name = NULL)`** (`R/sync.R:759`) -- the one
    empty-manifest shape. It replaced three hand-built copies, now three calls to it:
    `R/query.R:617`, `R/sync.R:408`, and the one inside the entry updater at `R/sync.R:969`, which
    is the copy that would have written the old key after the rename (see Task 6). Use
    `datom_init_repo()`'s spelling,
    `structure(list(), names = character(0))` (now `R/sync.R:762`, inside the skeleton itself),
    not a bare `list()`: an empty bare
    list serializes as a JSON **array**, an empty named list as an **object**. Inert today (the
    skeleton is never written empty) and correct for the one case where it would be.
  - **`.datom_check_namespace_free()` is excluded by name** (`R/utils-validate.R:194`). It reads
    a *different project's* manifest inside a handler that softens failure to `<unreadable>`, and
    that softening is right there: the message is best-effort context for a refusal that has already
    been decided. Sweeping it onto the shared helper would put a throwing check inside an
    error-softening handler, which is the exact shape this task removes everywhere else.
  - **The four in-pipeline local reads stay excluded**, on Task 4's stated principle: the check
    belongs where a document enters datom, so a refusal happens before work starts rather than
    partway through a write.
  - **New: `tests/testthat/fixtures/manifest-v1.json`** -- one preserved file per historical schema
    version, frozen, never edited. Contents: no `schema_version`, a `tables` block with one real
    table entry, a `summary` block. It is the only mechanical evidence that old repos still read,
    and being a file rather than an inline fixture is what stops a later sweep from quietly
    rewriting it to the new shape.
  - **Two existing tests are v1-compatibility tests and must not be swept in Task 6**:
    `datom_list tolerates a manifest with no schema_version` (`test-query.R:930`) and
    `datom_summary tolerates a manifest with no schema_version` (`test-summary.R:180`). Both build a
    `tables` block with an entry and assert a **non-empty** result. Rewritten to `artifacts` they go
    green while asserting nothing. Add the third: `datom_sync_manifest` has the same-named test
    (`test-sync.R:1308`) but its `tables` block is **empty**, so it passes either way and proves
    nothing -- give the clone-copy readers a non-empty old-format fixture too.
  - **No new export. No on-disk change. No schema bump.** The key is still `tables` when this task
    ends; `git diff` on any repo must be empty after running the suite.
  - _Requirements: R22 (R22.4, R22.6, R22.7). Invariants: I28. Properties: P35. Acceptance: AC30
    (the frozen fixture reads non-empty), AC32 (a schema outcome is never reported as an unreadable
    manifest, at any reader). **One instruction about test SHAPE, not about the criterion**: the
    behaviour this task ships is an abort at all five readers, and Task 22 changes it to
    warn-and-rebuild for the manifest reader. So write that assertion where it is easy to find and
    amend -- **do not bury it in a loop over the five readers**, because one of the five stops
    aborting later. AC32's wording is invariant across that boundary; the test is not. No pathway
    impact -- route shapes unchanged; record explicitly._
  - **DONE 2026-08-29.** `.datom_read_manifest()` and `.datom_manifest_skeleton()` added to
    `R/sync.R` in a new "Shared manifest access" section; five read sites routed through the first;
    three hand-built empty manifests replaced by the second; `tests/testthat/fixtures/manifest-v1.json`
    frozen, with a `fixtures/README.md` saying these files are never edited. tests: 2686 ->
    **2740** (+54), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No
    pathway impact -- the route shapes and gate positions are unchanged; only the number of places
    the manifest is read moved, from five to one.
  - **Both new guards were proven to fail before being trusted**, per this spec's own rule. (1)
    Pointing `datom_list()` at `manifest$artifacts` -- what Task 6 will do -- turns the frozen-fixture
    test red, so it really is evidence that old-format repos still list their contents rather than a
    test that would pass either way. (2) Wrapping the schema check in a handler inside
    `.datom_read_manifest()` turns three tests red, including `datom_sync_manifest`'s existing
    refusal test, so the returned-versus-thrown split is pinned rather than assumed. Both probes were
    reverted; the workspace carries neither.
  - **The `error` field holds the whole condition, not its message text.** Two callers need different
    things from it: `datom_list()` and `datom_summary()` splice `conditionMessage()` into their own
    abort, and the two clone readers re-signal the original failure with `stop()` so a corrupt local
    manifest still fails with the parser's own error and no datom wrapper. Keeping only the text would
    force the second case to manufacture a look-alike error, which loses the condition class -- and
    class is what the suite asserts on elsewhere.
  - **`absent = TRUE` is a positive claim and storage never makes it.** For the clone copy it is a
    free `fs::file_exists()`. For storage, separating a missing object from an unreachable store
    needs an extra request on every `datom_list()`, `datom_summary()` and `datom_status()` call, and
    no caller treats the two differently, so the field is left `FALSE` there, meaning "not known to
    be absent". Pinned by a test, since the tempting later optimisation is to infer absence from the
    error message. If a caller ever needs the distinction, probe `.datom_storage_exists()`; do not
    parse the message.
  - **A corrupt clone manifest is a failure, not an absence, and that distinction is now tested.**
    Both clone readers fall back to an empty manifest when the file does not exist. A present but
    unparseable file must not take that branch: it would report every input file as new, which is a
    wrong answer delivered confidently. The helper separates the two, and each clone reader
    re-signals the parse failure.
  - **`datom_status()` lost its `read_ok` flag.** It had one because a manifest that legitimately
    parses to `NULL` must still count as read, and a `NULL` check could not tell those apart. The
    helper's `ok` field carries that distinction now, so the flag was redundant rather than dropped.
  - **The entry updater keeps its own direct read, deliberately.** `.datom_update_manifest_entry()`
    (`R/sync.R:984`) reads `.datom/manifest.json` mid-write, and a compatibility refusal there would
    stop a write partway through instead of at the door. Only its empty shape moved to the shared
    builder. A comment at the site says so, because the obvious tidy-up is to route the read through
    the shared reader as well.
  - **The two clone readers' fallback is now `.datom_manifest_skeleton()` rather than
    `list(tables = list())`.** Behaviour-identical for lookups -- both answer `NULL` for any name --
    and it removes the last two places that spelled an empty manifest by hand.

- [x] **6. `manifest$tables` -> `manifest$artifacts`, typed by `kind`** &nbsp; **[ESCALATION E2 --
  FULLY DISCHARGED: design spot-check 2026-09-01, implemented 2026-09-08, purity audit run and
  discharged the same day. Nothing owed -- see the DONE record at the end of this task]**
  - Write side (**3** sites -- an earlier draft said 2 and missed the third):
    `.datom_update_manifest_entry()` (`R/sync.R:1004,1014-1024`); the **absent-manifest skeleton**,
    which Task 5 collapsed into `.datom_manifest_skeleton()` (`R/sync.R:759`, called at
    `R/sync.R:969`); and `datom_init_repo()`'s seed (`R/conn.R:522-528`).
    **The skeleton stamps `schema_version: 2` itself** (owner-decided 2026-08-29), so no repo ever
    exists in a state that declares no format at all. Note what that does *not* cover: a manifest
    read from disk in the old shape still needs the upgrade to stamp it, because the skeleton is
    only reached when there is no file. Two paths, one for a document being created and one for a
    document being converted, and both have to stamp.
    **The skeleton was the dangerous one**: left unrenamed it writes a `tables` key after the
    rename, and it only fires on a fresh or repaired repo, so tests against an existing fixture pass
    while the bug ships. Task 5 reduced it to one place, which is the point of the split.
  - Read side: **one** site now -- `.datom_read_manifest()` (`R/sync.R:1036`) -- plus the six field
    accesses that read the artifact key off the returned document (`R/query.R:92,109`,
    `R/query.R:489`, `R/query.R:604`, `R/summary.R:68`, `R/sync.R:411`).
  - Each entry gains `kind` (`"table"` for everything existing). `summary` gains `total_sets`;
    `total_tables` / `total_size_bytes` / `total_versions` keep **current** semantics (tables
    only).
  - **FIVE counters silently widen to include sets, not three.** The three in the summary block
    (`R/sync.R:1032,1033,1036`) plus two computed independently of it: `datom_summary()`'s
    `table_count` counts entries rather than reading the summary block (`R/summary.R:69`), and
    `datom_status()`'s count does the same and prints as "Tables on S3" (`R/query.R:488`). Each
    needs a `kind == "table"` filter. There are no sets until Task 9, so **every test passes either
    way** unless it is driven by a hand-built manifest containing a `kind: "set"` entry -- so write
    that fixture, and assert `datom_summary()`'s counted number and the stored `summary` block
    agree.
  - **"Surface `kind`" means two different things.** `datom_list()` returns per-artifact rows, so it
    gains a `kind` column -- **including in both empty-frame early returns** (`R/query.R:94,103`),
    not only the populated path. Those two already omit `current_data_sha`, which populated rows
    carry, so the column set has drifted here once already. `datom_summary()` has no per-artifact
    axis: it gains `set_count` alongside `table_count`, plus a line in `print.datom_summary()`, and
    `table_count` keeps its tables-only meaning (owner-decided 2026-08-23).
  - Manifest and per-artifact metadata now write `schema_version: 2`. **Both are stamped; the number
    moves to 2 because this change is genuinely breaking** (the artifact list is renamed, which is
    row one of R9.5's test). Stamping and incrementing are separate decisions from here on -- a later
    release that merely adds a field stamps the same number, so no pinned build is refused for a
    change it could have tolerated.
  - **The old-format upgrade, which is what makes the rename safe** (R22): add
    `.datom_manifest_upgrade_v1_to_v2()` (move `tables` to `artifacts`, stamp `kind = "table"` on
    every entry) and the dispatcher `.datom_manifest_upgrade()`, both in a **new
    `R/manifest-upgrade.R`** (owner-decided 2026-08-29). Reason: a shipped step is frozen forever
    and one more arrives with every future format change, so they accumulate -- a file whose entire
    contents are "never edit these" is easier to protect than a section of `R/sync.R`, which is
    already 881 lines and holds sync, import and manifest concerns. Same split reasoning as
    `R/hashable-set.R`. Apply it in the **one** place Task
    5 created. Concretely, inside `.datom_read_manifest()` (`R/sync.R:1036`) the order is: read,
    then `.datom_check_schema_version()` -- which throws on a document too new to touch at all --
    then the upgrade chain on what survives, then return. `manifest` simply comes back upgraded.
    **The record gained a fifth field on 2026-09-08**, `declared` -- the version a document announced
    before conversion -- so a caller that goes on to write the converted document can say the format
    moved without re-deriving the comparison or reading the file twice. An earlier version of this
    line said the four fields (`ok` / `absent` / `manifest` / `error`) do not change shape. Task 22 later adds a rebuild branch at the same point, so keep the step separable
    rather than inlined into the return. Read upgrades in memory and leaves the file alone; write
    upgrades the file, then stamps the version. Never stamp a version onto a document that was not upgraded first, and never
    write a v2-shaped entry into a file still declaring v1 -- that is how a file ends up half in
    each format. Concretely, without this: a repo with twelve tables gets one entry added under the
    new key while the old key sits untouched, and `total_tables` reads **1**.
  - **The write-side refusal, inherited from Task 4** (owner-decided 2026-08-21). Task 4 gated the
    six reader entry points; an **older** build writing into a **newer** repo is the more damaging
    direction and is still open. Reuse `.datom_check_schema_version()`; do not write a second one.
    Placement is the whole question, and it has two parts. (a) It needs the **manifest**, which
    `datom_write()` never reads -- gating only the per-artifact metadata leaves the manifest
    unprotected. (b) It must sit directly after the `datom_conn` class check and **above** the two
    routing returns at `R/read_write.R:1137` and `R/read_write.R:1141`, because
    `.datom_sync_data_metadata()` mirrors the whole local manifest to storage (`R/sync.R:212`)
    without ever reaching the manifest-writing step, so a check placed after the router misses it.
    A write is several steps -- local files, one commit, then the storage mirror -- so the check
    goes ahead of all of them: stopping halfway leaves a half-finished write, which is worse than
    the disagreement it was trying to prevent.
  - **`.datom_check_schema_version()`'s message says "which this build cannot read"**
    (`R/utils-validate.R:279`). On a refused **write** that sentence is wrong. Give it an operation
    word, or accept it knowingly and say so.
  - **Must land atomically**: the rename, the five counters, the upgrade step and the tests, in one
    commit. A partial rename presents as "everything looks fine, the list is just empty."
  - _Requirements: R8 (incl. R8.4, R8.5), R9 (writer side), R22 (R22.2, R22.3, R22.5, R22.8).
    Invariants: I2, I4, I29, I30.
    Properties: P10 (restated -- this task is where it is defended), P34. Acceptance: AC7 (the v2
    writer half of the schema gate), AC30 (the frozen v1 fixture still reads non-empty **after** the
    rename), AC31 (a write into an old-format repo upgrades the file and the counters cover every
    pre-existing artifact). Add a test that `datom_list()` and `datom_summary()` surface `kind` and
    that `total_sets` counts only sets -- the rename's own failure mode is silent, so it needs a
    positive assertion, not just the absence of errors. No new pathway (route shapes unchanged) --
    record explicitly. **Confirmed on landing**: `dev/datom_pathways.md` gained no route. The
    "can this build read it" route gained a step (convert after checking) and its write-side
    paragraph now names the door instead of deferring to this task, but both are transforms and
    gates on a document already fetched -- no new lookup, no new traversal._
  - **Escalation rationale**: touches `datom_list()`, `datom_summary()`, `datom_status()` and the
    sync manifest updater together, plus the writer-side check inherited from Task 4 and the
    old-format upgrade added by the 2026-08-23 audit; failure mode is silent writer/reader
    disagreement. (An earlier draft also named `datom_validate()` -- **corrected 2026-08-21**, see
    the cold-start audit below: it reads the manifest only for `project_name` and never touches the
    artifact key.)
  - **COLD-START AUDIT, 2026-08-21** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked
    against the tree. The nine-site enumeration was **accurate as recorded** (Task 5 has since
    collapsed the read half to one site), and all citations were re-derived after Task 4's
    insertions. Two things needed fixing and one is worth budgeting for:
    1. **`datom_validate()` does NOT read `manifest$tables`** -- verified by grepping every
       reference to the key in `R/`. Its only manifest read is `.datom_validate_project_name()`
       (`R/validate.R:257`), which looks at `project_name` and nothing else, and
       `.datom_validate_tables()` enumerates artifacts without consulting the manifest at all. So
       the rename does not touch it, and the escalation rationale above previously sent a reader
       hunting in a file with nothing in it. **Corrected 2026-09-09**: this line said it enumerates
       "from a storage listing", which is wrong -- it enumerates from the **clone**
       (`fs::dir_ls(repo_path, type = "directory")`, `R/validate.R:386`) and then checks storage per
       name. The conclusion above is unaffected, but the wrong version matters for Task 22, whose
       rebuild has to serve a reader with no clone: it would send that reader looking for a
       storage-side enumerator that does not exist.
    2. **THREE DECOY SITES that look like the rename and must not be renamed.** Each is a
       user-facing **return-value** field named `tables`, not the manifest key:
       `datom_sync()`'s result (`R/sync.R:171`, `R/sync.R:222`), `datom_validate()`'s result
       (`R/validate.R:205`), and `datom_status()`'s result (`R/query.R:536`). A `grep tables`
       sweep hits all three. Renaming them is a **separate** breaking change to three return
       shapes that R8 does not ask for -- R8.1 renames the manifest key only. If it ever looks
       desirable, it needs its own decision and its own NEWS entry.
    3. **Test surface is wide**: ten test files mention `tables`, re-counted 2026-08-29 after
       Tasks 18/19/5 added to them (`test-sync.R` 45 hits, `test-query.R` 39, `test-validate.R` 24,
       `test-read-write.R` 17, `test-summary.R` 9, `test-conn.R` 4, plus four with one each). Many
       are manifest fixtures that must move to `artifacts`; some are decoys per item 2. Budget for
       the fixture sweep being the bulk of the chunk, and remember the rename's own failure mode is
       silent -- a fixture left on `tables` against a reader expecting `artifacts` presents as an
       empty list, not an error.
    4. **SIX TESTS AND ONE FILE MUST STAY ON THE OLD KEY.** They are the only evidence that repos
       written before this rename still read, so sweeping them to `artifacts` leaves them green
       while asserting nothing -- and the regression then ships clean. Verified present
       2026-08-29:
       `tests/testthat/fixtures/manifest-v1.json` (frozen; `fixtures/README.md` says so) and its
       readers `datom_list reads the frozen old-format manifest as non-empty`
       (`tests/testthat/test-query.R:941`), `datom_status input file scan sees entries in an
       old-format manifest` (`tests/testthat/test-query.R:1049`), `datom_summary reads the frozen
       old-format manifest as non-empty` (`tests/testthat/test-summary.R:191`) and
       `datom_sync_manifest sees entries in an old-format manifest in the clone`
       (`tests/testthat/test-sync.R:1327`); plus the two older tolerance tests
       `datom_list tolerates a manifest with no schema_version`
       (`tests/testthat/test-query.R:930`) and `datom_summary tolerates a manifest with no
       schema_version` (`tests/testthat/test-summary.R:180`). Note the same-named
       `datom_sync_manifest` tolerance test (`tests/testthat/test-sync.R:1308`) has an **empty**
       `tables` block, so it proves nothing either way -- Task 5 added the non-empty clone-copy
       test above precisely because of that.
  - **DESIGN AUDIT, 2026-08-23** -- run before implementation per the E2 flag, and the reason this
    phase is now two tasks. It found the old-format transition described above (nothing upgraded a
    v1 manifest, and neither of the two things that might have self-healed it does: the entry
    updater stamps no version, and a no-change write returns at `R/read_write.R:1081-1090` before the
    manifest is touched), the two v1-compatibility tests that must not be swept, the five counters
    rather than three, the two empty-frame early returns, the placement of the write-side refusal
    above the routing returns, and two acceptance criteria this task cannot exercise (AC4 needs
    `datom_write_set()`, Task 9; AC22 is Task 11's and is already largely implemented by
    `.datom_check_namespace_free()`) -- both now removed from the clause above and left with the
    tasks that own them. Verified independently against the tree before acceptance; the one
    overstatement was that a clone can lack a local manifest, which is true but close to
    unreachable because `.datom/manifest.json` is git-tracked. **`dev/check-spec.R` cannot catch any
    of this** and says so itself, in the comment explaining why the manifest key is not on the
    retired-wording list: the risk lives in `R/`, which that script does not read. This phase has
    the least mechanical protection and the most silent failure mode of any work in this spec.
  - **DONE 2026-09-08, in one commit, as planned below.** The design was proposed 2026-09-01 and
    the session stopped for owner go-ahead per rule 5b; CRAN's post-acceptance fix intervened and
    shipped as 0.1.2 (test-only, no `R/` file), so the plan stood untouched and was implemented from
    it verbatim. **The five open calls were taken at their stated defaults**, each of which is
    recorded with its consequence below. Tests 2748 -> **2836** (+88), FAIL 0 / WARN 0 / SKIP 0;
    `Rscript dev/check-spec.R` all nine checks pass. What shipped, beyond the plan: nine internal
    `man/` pages regenerated, no new export, NAMESPACE and `_pkgdown.yml` untouched.
    - **E2 status.** The design spot-check half was discharged by the proposal below, produced after
      reading the audits and re-reading every cited site in `R/`. **The purity-audit half is now
      due** -- 6 `R/` files edited, 1 added, ~40 fixtures swept across 8 test files, and a failure
      mode that shows up as an empty list rather than an error. Per rule 5d it is surfaced in this
      chunk's checkpoint message; per the default taken below it runs in-line, before Task 20 starts.
    - **Plan, by file -- implemented as written.** New **`R/manifest-upgrade.R`**: `.datom_manifest_upgrade_v1_to_v2()` renames
      the artifact key **in place** (`names(m)[names(m) == "tables"] <- "artifacts"`, so position and
      any unrecognised sibling keys survive -- which is also what Task 20 wants) and stamps
      `kind = "table"` first in each entry; `.datom_manifest_upgrade()` derives the declared version,
      applies each step in order via `purrr::reduce`, guarded by `if (declared < supported)` because
      R's `seq()` counts down (R22.10), then records the version it reached.
      `R/sync.R`: the skeleton (`R/sync.R:759`) renames its key and stamps `schema_version: 2`; the
      shared reader (`R/sync.R:1036`) gains one line -- chain **after** `.datom_check_schema_version()`
      and before the return, kept separable for Task 22's rebuild branch; the entry updater
      (`R/sync.R:946`) chains what it read from disk, writes `kind` on the entry, stamps the version,
      and filters its three summary counters (**all four kind selections went through one helper,
      `.datom_artifacts_of_kind()`, on 2026-09-08** -- the predicate was spelled out at each site and
      one of those copies had lost a tolerance); `datom_sync_manifest()`'s lookup moves to the new key.
      `R/query.R`: `kind` column in `datom_list()`'s populated path **and** both empty returns;
      `datom_status()`'s count filtered; the input-file scan's lookup moved. `R/summary.R`:
      `table_count` filtered, new `set_count`, new print line. `R/conn.R`: the seed is built from the
      skeleton plus `updated_at` and a zeroed summary, so the stamp is not spelled a third time.
      `R/read_write.R`: `schema_version` into `.datom_build_metadata()` (already classified excluded
      in `.datom_metadata_excluded_fields`, so identity does not move and the classification test
      stays green), plus the write-entry check above both routing returns. `R/utils-validate.R`: an
      operation word in the refusal message.
    - **Two stamping sites, restated because the plan depends on it.** Created-from-nothing gets the
      number from the skeleton; converted-from-old gets it from the dispatcher, which sets it only
      after the steps ran (I29). The seed is routed through the skeleton rather than stamping itself,
      which is the only reason there are two sites and not three.
    - **Docs that ship in the same commit.** `dev/datom_specification.md`'s `.datom/manifest.json`
      example still shows `tables` and no `schema_version`; a NEWS entry for a breaking rename; the
      `tasks.md` checkbox and the `dev/README.md` status line; and "no pathway impact" recorded
      explicitly.
    - **Test plan.** The load-bearing new fixture is a **hand-built manifest carrying a `kind: "set"`
      entry beside table entries** -- without it every counter change passes whether or not it was
      made, since nothing writes a set until Task 9. It asserts the two counted numbers
      (`datom_summary()`), the two stored numbers (the `summary` block), and that counted and stored
      **agree**. Then: unit tests for the step and the dispatcher (converts; identity on a
      current-version document; **zero** steps run there; twice equals once); a write into an
      old-shape repo leaves the new key, no old key, the number stamped and every pre-existing table
      still counted (AC31); the write-entry refusal on **all three** write routes including the
      mirror-everything one; stamping mints no new version for unchanged content; `kind` present in
      both empty returns.
      **The sweep rule, and how it goes quietly wrong**: a swept fixture must declare
      `schema_version: 2` **and** carry `kind` on its entries. Declaring the number without `kind`
      makes the counters read zero, because R22.8 deliberately has no missing-`kind` fallback -- the
      counter tests above are what catch that. The six tests and the frozen file named in item 4 stay
      on the old key; the two frozen-fixture readers gain AC30's `kind = "table"` assertion, which
      touches the assertions and not the fixture.
    - **FIVE OPEN CALLS, ALL FIVE TAKEN AT THEIR DEFAULT (2026-09-08).** The owner said nothing on
      any of them, which the defaults were written to make safe. Each is stated below as it was
      proposed, with what shipped noted at the end of the item.
      1. **The mirror-to-storage route converts before mirroring and leaves the clone file alone.**
         `datom_write(NULL, NULL)` and `datom_validate(fix = TRUE)` reach
         `.datom_sync_data_metadata()`, which today copies the clone's manifest to storage byte for
         byte -- so a build that knows the new shape would push the old one. Plan: read it through the
         shared reader, mirror the converted form, do **not** rewrite the local file, because this
         route does not commit and rewriting it would leave the repo dirty. Accepted cost: for a
         window the clone is old-shape and storage is new-shape; both are internally consistent and
         both read correctly. Side benefit: `datom_validate(fix = TRUE)` bypasses `datom_write()`'s
         door, and routing its read through the shared reader is what stops it mirroring a manifest it
         cannot understand. *Default: as described.* **Shipped as described**, and pinned by a test
         that mirrors the frozen v1 fixture and asserts both halves: storage receives the converted
         document, and the clone file's digest is unchanged.
      2. **An operation word in `.datom_check_schema_version()`'s message.** It says the format is one
         "this build cannot read", which is wrong on a refused write. Plan: an optional argument, so
         every existing call site and its asserted text are unchanged. *Default: add it.* **Shipped
         as `operation = c("read", "write")`.** A refused write now says the build "cannot write"
         that format. **All three** write-route tests assert the word -- only one did when this was
         first written, and the other two were tightened on 2026-09-08 rather than the claim being
         weakened.
      3. **The clone manifest is read twice on a write** -- once by the entry check, once by the
         updater that edits it. Task 21 asks for this to be decided rather than drifted into. Plan:
         accept two reads of a small local file, and say why in the commit -- the door's copy cannot be
         threaded down, because the sync route pulls from the remote in between, so a document read at
         the door can be stale by the time the file is edited. *Default: accept two reads.* **Two
         reads shipped, but the reason above is WRONG and was corrected 2026-09-08.** Nothing pulls
         between the two reads **on this route**: the door runs first, the updater about a hundred lines
         later, and the pull is inside the push after both of them. `datom_sync()` does not change that
         -- it calls `datom_write()` per file, so the door runs inside each call. (The metadata-only
         route is different and pulls right after the door, which makes the door's check stale there;
         it writes no manifest, so nothing can end up half in each format, and Task 21's entry sequence
         is where that has to be dealt with. Recorded in Task 21's bullets.) The **decision** stands on
         a plainer footing: the door deliberately runs before any hashing so that a refusal leaves
         nothing half-written, and threading its document down to the updater would carry state
         through every intervening step, each of which must stay free to abort. It is a local file
         read, not a round trip.
      4. **The entry check is skipped when there is no clone path.** A reader-role conn has no clone
         to inspect and already fails a few lines later with a clearer message about developer role.
         *Default: skip, and let the existing error stand.* **Shipped**, and tested: a reader-role
         connection passes the door and still fails on the developer-role message.
      5. **`datom_list()`'s two empty returns gain `kind` but not `current_data_sha`.** Those returns
         omit a column the populated rows carry -- pre-existing drift this task's body already notes.
         Fixing it changes a public shape nobody asked to change. *Default: leave the drift,
         recorded.* **REVERSED by review, 2026-09-08 -- the drift is gone.** Both empty returns come
         from `.datom_empty_artifact_frame()`, which now carries every column a populated result
         carries, `version_count` included when `include_versions = TRUE`. The default's reason was
         already spent when it was written: the same commit added a `kind` column to that very shape.
         And the difference was a defect, not a cosmetic one -- `rbind()` of frames with different
         columns errors, so a caller collecting listings across projects broke as soon as one was
         empty. Fixed in two goes, one column each; see the Decisions rows.
    - **Also open, also defaulted -- and now DONE**: the post-landing purity audit ran in-line and is
      discharged (2026-09-08); its method and result are in the bullet below and in the Decisions log.
      **Sequenced after the review fixes, owner-decided 2026-09-08**: an audit of a
      state that is about to change produces findings that go stale, and two of the fixes land
      squarely in what the audit inspects (three fresh copies of one predicate, and a public shape).
      So the audit is the last check, not the first.
    - **THREE THINGS THE PLAN DID NOT SAY, decided while implementing.**
      1. **The upgrade dispatcher takes the declared version as an argument** rather than reading it
         off the document. The number can only come from the check, which refuses a document too new
         to convert, so passing it in is what makes "check first, then convert" structural: there is
         no way to call the converter without having obtained the number from the check (I32).
      2. **The entry updater runs the check on what it read from disk**, purely to obtain that
         number. It cannot fire for a write that came through `datom_write()`, because the door
         already refused a too-new manifest before any hashing; the alternative was guessing the
         version of a document about to be edited, which is how a file ends up half in each format.
         Task 5's decision that the updater keeps its own **read** is unchanged.
      3. **A document that did not parse to a named list is returned untouched** by the converter.
         Stamping one would turn `null` on disk into an object in memory -- inventing a document
         where the file had none.
    - **EVERY GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED**, per this spec's own rule, and each
      probe was reverted. (a) Disabling the conversion in the shared reader reddens **18**
      assertions: all four frozen-fixture readers, both no-`schema_version` tolerance tests, the
      mirror route, and the two reader tests added here. (b) Removing the `kind` filters reddens five
      tests across all three counting sites -- the stored `summary` block, `datom_summary()`'s
      counted numbers, and `datom_status()`'s. (c) Moving the write door below `datom_write()`'s
      routing returns reddens both non-table routes, which is the placement the 2026-08-23 audit
      flagged. (d) Dropping the conversion from the entry updater reddens the ten assertions that say
      a pre-existing table is still counted after a write. Without (b) and (d) the suite passes with
      the bug in it.
    - **FOUR FINDINGS FROM THE POST-LANDING REVIEW, all fixed 2026-09-08 in a follow-up commit.** Each
      was verified against the code before being accepted, and each was proven to redden a test before
      the fix was trusted. (1) **Three counters aborted on an entry that is not a named list** -- the
      v1 step preserves such an entry, having no shape to convert, and the counters dereferenced it.
      `datom_status()` was the damaging one: the count sits outside the handler that lets it describe
      a connection when the manifest cannot be trusted. Fixed by routing all four selections through
      `.datom_artifacts_of_kind()` rather than repeating a guard four times. (2) **A conversion that
      persisted was silent**, so `datom_validate(fix = TRUE)` could degrade a colleague's install;
      writes now say what moved, reads still say nothing. (3) **`stop(read$error)` could be
      `stop(NULL)`** on the mirror route, aborting with an empty message. (4) **`datom_list()`'s empty
      result lacked `current_data_sha`**, so `rbind()` failed when one side was empty -- which
      reversed open call 5. Two claims in this record were also wrong and are corrected in place: only
      one of the three door tests asserted the message word (the other two were tightened), and the
      double read was justified by a pull that does not happen where it was said to.
    - **TWO LOOSE ENDS FROM A SECOND REVIEW PASS, both closed 2026-09-08.** (1) The zero-row frame was
      still one column short in the narrower case: `version_count` is opt-in, a caller **can** ask for
      it and get an empty repo, and a comment claimed they could not. The frame now takes the flag and
      carries the column exactly when a populated result would, so `rbind()` works for that call too --
      the fix, not a reworded comment, because it is the same defect the `current_data_sha` reversal
      was about. (2) The metadata-only write route pulls from the remote immediately after the door,
      so the door's manifest check is stale on that route; harmless in this task's code because the
      route writes no manifest, and now written into Task 21's bullets, where the entry sequence has to
      either own the fetch or re-check after it.
    - **PURITY AUDIT, 2026-09-08 -- discharged, two tests tightened, no code changed.** Run last
      rather than first, so that it audited the state that actually shipped. Method and result, so
      neither is re-derived:
      1. **Is the suite blind to the failure this task exists to prevent?** No. Dropping the artifact
         key from the shared reader's returned document -- the silent blackout itself -- reddens **64
         assertions across 36 tests**, spanning all five readers plus five `datom-cv1` end-to-end
         scenarios. The fixture sweep did not cost the suite its teeth.
      2. **Did any swept fixture end up declaring the version but carrying no `kind`, which reads as
         zero artifacts?** No. Making an untyped entry abort inside the selection helper reddens
         exactly **one** test -- the one that deliberately passes an untyped entry to assert it is not
         counted. Checked this way rather than by grepping the fixtures, because an entry spread over
         several lines defeats the pattern and a false negative here is invisible.
      3. **Two tests were passing whatever the code did.** `print.datom_summary shows the set count`
         asserted that a `Sets:` line exists, which holds against a count that is always zero; it now
         asserts the number. `returns empty data frame when pattern matches nothing` asserted an empty
         result from a non-empty fixture, which holds equally if the manifest was never read; it now
         asserts the unfiltered call returns a row first.
      4. **Duplicated logic**: after the follow-up commit each of the five concerns has exactly one
         home -- the reader, the skeleton, the conversion, the kind selection, and the zero-row frame.
         Stamping is still the two sites I29 requires (the skeleton for a document being created, the
         dispatcher for one being converted) and a third has not appeared.
      5. **No surviving read of the old key in `R/`**, and every remaining `tables` in the tests is one
         of: a v1 document handed to the conversion, one of the six preserved old-key tests, a
         deliberately malformed JSON string, a namespace fixture that only reads `project_name`, or one
         of the three documented return-value decoys.
      6. **`R CMD check`** (docs, Rd, code/doc agreement; tests and examples skipped as they run
         separately): 0 errors, 0 warnings, 0 notes.
      **One gap it did not close, named rather than fixed**: the write door inspects the manifest only.
      `.datom_sync_metadata()` (`R/utils-sha.R:576`) copies a per-artifact metadata document from the
      clone straight to storage, and a document pulled from a collaborator on a newer datom would go
      through unchecked. Pre-existing -- before Task 6 there was no write-side check at all -- so this
      narrows the hole rather than leaving it where it was. Closing it belongs with Task 21, which is
      already writing the entry sequence that reads all three documents at the door.

---

## Phase C -- The set artifact

- [x] **7. `kind` in metadata + set metadata builder + `document_sha`**
  - `kind: "table" | "set"` -- **semantic**, participates in `metadata_sha`. A **new field**, not
    a `table_type` value; `table_type` stays validated to exactly `imported`/`derived` (I12).
  - `.datom_build_metadata()` gains `kind = "table"`; new `.datom_build_set_metadata()` produces
    the collapsed field set using **conditional assign** so fields are omitted, not nulled.
    **The authoritative field list is R1.3** -- seven fields, named there -- with R1.4 giving what is
    absent and why. It is **not** in design.md section 4, which this bullet used to cite: that section
    is about tags replacing structure and contains no field matrix, so the citation sent a fresh reader
    looking for a table that does not exist.
  - **The set builder's two concrete values, because both are easy to get wrong by copying the table
    builder.** `data_sha` comes from `.datom_canonical_set_hash(payload)` (`R/hashable-set.R:421`),
    already shipped by Task 2, and `hash_algo` is the string **`"datom-sv1"`** -- the encoder embeds
    that string inside the digest but nothing stamps the field, so the builder must. Copying
    `"datom-cv1"` across would leave a set claiming the table regime while hashing under the set one.
  - `document_sha` persisted in `version_history.json` entries from day one, mirroring the
    `parquet_sha` conditional-add in `.datom_write_metadata_local()` (R7.2).
  - **`document_sha` ALSO GOES IN A SET'S `metadata.json` -- R1.3 lists it as one of the seven.** This
    bullet previously said to keep it out of the metadata document, which contradicts R1.3 and would
    break the read gate: R7.1 requires the stored payload verified **before parsing**, and the reader
    has nowhere else to get the expected hash from. The Task 20 concern that produced the old wording
    does not survive contact with R1.3 either -- carry-forward only matters for a field **nothing
    writes**, and once the set builder writes it there is no rewrite that can lose it. It stays on the
    excluded (not-identity) list: it is a fact about stored bytes, and hashing it would make a set's
    identity depend on its own serialization.
  - **`document_sha` is inert at this task, so decide whether the plumbing lands here.** Nothing
    computes a `document_sha` until the set **write** path exists (Task 9), so the
    `version_history.json` conditional-add added here writes nothing and the set builder's field is
    only reachable from a test. R7.2 says "from day one", which argues for adding it now; the
    alternative is deferring both to Task 9 and carrying no unreachable code. **Default: add it now**,
    with a comment saying what makes it live, because it is one line, it mirrors `parquet_sha` exactly,
    and a deferred line is a line Task 9 has to remember.
  - **CLASSIFY EVERY FIELD THIS TASK ADDS -- Task 19 landed the allowlist, so an unclassified field
    is silently outside identity.** `kind` is **semantic** and goes in the **hash list**; every field
    `.datom_build_set_metadata()` emits needs the same decision, one by one, against design.md
    section 4's matrix. Left unclassified, `kind` stops affecting `metadata_sha` and a table and a
    set can share a version identity -- which the 2026-08-23 decision closed off deliberately, and
    which no other test in this task would catch. Task 19's classification test is written to
    enumerate what the builders emit rather than hardcode names, so it **fails** until each new field
    is classified; extend it to cover the set builder. `document_sha` is already on the
    excluded list from Task 4, so leave it there -- but note it now becomes a field a builder **emits**,
    which takes it off the classified-before-written exception list (see the audit below).
  - **COLD-START AUDIT, 2026-09-10** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked
    against the tree. **Startable.** Two of this task's own statements were wrong and are corrected
    above (the design.md section 4 citation; "keep `document_sha` out of the metadata document").
    **No escalation flag** -- design.md section 12 carries E1 and E2 only -- so nothing is owed under
    rule 5d. Five things a fresh session would otherwise have to derive or discover the hard way:
    1. **ADDING `kind` RE-MINTS A VERSION FOR EVERY EXISTING TABLE, AND THAT IS AN ACCEPTED OWNER
       DECISION, NOT A DEFECT TO ENGINEER AWAY.** `kind` is identity, so a rebuilt table document
       hashes differently from the recorded one, `.datom_has_changes()` returns `metadata_only`, and
       the next write of every table in every repo mints a version on unchanged content. Verified by
       computing both hashes. The decision is in the Decisions log (2026-08-23) and **only** there,
       which is why a fresh session would reach for the two fixes it explicitly closed off: `kind`
       cannot be left out of the hash (a table and a set could then share a version identity) and
       cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata,
       precisely because the manifest can lag a partial write). Accepted as bounded and in the safe
       direction -- an **extra** version, not a changed one; same content, same storage address,
       parquet reused, nothing re-uploaded. Say it in NEWS.
    2. **P36 AS WRITTEN SAYS THE OPPOSITE OF WHAT THIS TASK DOES, and this task cites it.** Its first
       clause read "adding any field to a metadata document leaves every existing `metadata_sha`
       unchanged" without qualification, which is true only for a field outside the identity list.
       Scoped on this audit, the way P35 and AC32 were scoped when Task 22 changed their subject --
       the property was never "no addition moves a hash", it was "identity ignores what it does not
       name".
    3. **THIS TASK MOVES TWO PINNED GOLDENS, AND IT IS THE FIRST ONE ALLOWED TO.** `builder-derived
       metadata_sha goldens are stable` (`tests/testthat/test-utils-sha.R:1002`) holds two hardcoded
       hashes computed from `.datom_build_metadata()`; adding `kind` moves both. The standing
       instruction "if a golden fails the code drifted -- do not update the constant" is about the
       **sv1** goldens and applying it here would deadlock the task. Record both new values with the
       reason beside them, so the next reader can tell a licensed move from a drift.
    4. **THE FULL SET OF TESTS THIS REDDENS IS SIX SITES, not one.** `builder-derived metadata_sha
       goldens are stable` (`tests/testthat/test-utils-sha.R:1002`); `the pinned fixtures carry exactly
       the keys datom's writers emit` (`tests/testthat/test-utils-sha.R:1035` -- `kind` joins the
       `always` vector); `every field a metadata builder emits is classified`
       (`tests/testthat/test-utils-sha.R:1069` -- the forcing function, and the one to **extend** to
       the set builder); `nothing is classified before something writes it, except by decision`
       (`tests/testthat/test-utils-sha.R:1114` -- `document_sha` comes **off** the exception vector
       once the set builder emits it); `every field the metadata builder emits is in the metadata
       vocabulary` (`tests/testthat/test-forward-compat.R:210`); and `the metadata builder emits no
       kind, which is the only reason the rebuild may hardcode it`
       (`tests/testthat/test-manifest-rebuild.R:404`).
    5. **THAT LAST ONE IS A HANDOFF, NOT A FAILURE TO SILENCE.** It exists to make this task notice
       `R/manifest-rebuild.R:241`, where a rebuilt manifest row is stamped `kind = "table"` because
       nothing in per-artifact metadata says otherwise. Once this task adds the field, change that line
       to read `kind` from the document and keep `"table"` as the fallback for documents written before
       it existed, then replace the test with one asserting a set's metadata yields a row typed
       `"set"`. Deleting it instead leaves a rebuilt set reported as a table: the set counters read
       zero while the artifact still lists, and nothing errors.
  - _Requirements: R1 (R1.3 is the field list, R1.4 the exclusions), R7.1, R7.2, R9.5 (classify each
    added field). Invariants: I1, I12.
    Properties: P36 as scoped by this task's audit (the classification half -- this is the first task
    to add a field after the allowlist exists). Acceptance: AC8 (metadata half), AC33 (d) **extended to
    the set builder** -- Task 19 could only exercise the table half, since this task is what creates the
    set builder -- plus **R1.3's own inline acceptance** (exactly seven keys, asserted with
    `setequal()` so an added field fails). **Scope note on all three**: nothing writes a set until
    Task 9, so each is assertable here on the **builder's output** only. "A written set's metadata"
    and AC8's "writing a set does not alter any member's lineage" belong to Task 9._
  - **DONE 2026-09-10.** Four edits, and the one that costs anything is the first.
    1. **`kind` is in per-artifact metadata and in the identity list.** `.datom_build_metadata()`
       stamps `kind = "table"` -- a field, not a parameter, because a table write is the only thing
       that reaches that builder and a set has its own. The predicted cost landed exactly as the
       audit said: **both pinned identity goldens moved**, which is the licensed exception, and the
       old values are recorded in a comment beside the new ones so the next reader can tell a
       licensed move from a drift. The consequence for users -- one extra version per existing table
       at its next write, on content that did not move -- is now in NEWS with the reason and the
       bound (`data_sha` does not move, so nothing is re-uploaded).
    2. **`.datom_build_set_metadata(payload, document_sha = NULL)`** in `R/read_write.R`,
       deliberately beside the table builder rather than in a file of its own, because the two
       documents are close enough that a field copied from the wrong one is easy to miss. It emits
       exactly the seven fields of R1.3 and computes `data_sha` itself from
       `.datom_canonical_set_hash()` rather than taking it, so no caller can hand a set a
       table-regime hash.
    3. **`document_sha` in the version-history entries**, on the same conditional-add terms as
       `parquet_sha`. Inert -- nothing computes one until Task 9 -- with a comment saying what makes
       it live.
    4. **The Task 22 handoff is discharged.** `.datom_rebuild_manifest_entry()` reads `kind` from the
       document and keeps `"table"` as the fallback for documents written before the field existed.
       The forcing-function test that made this happen was **replaced, not deleted**, by one
       asserting all three cases (declared table, declared set, absent).
  - **Two things a later change must not undo.** (1) `document_sha` is **declared** in the set
    builder (`document_sha = document_sha` in the `list()` call), not conditionally assigned:
    the conditional form drops the key from the document and breaks R1.3's seven-key contract --
    probed, and it reddens 3 tests. (2) `kind` is on the **identity** list. Moving it to the excluded
    list reddens 3 assertions including the dedicated one, and what it would allow is a table and a
    set sharing one version string.
  - **CORRECTION, made during this task's review (2026-09-10): the first of those two said the
    declared and conditional spellings "produce identical files while the value is NULL". That is
    false and it mattered.** `jsonlite` does **not** omit a NULL element -- it writes `{}`, and
    reading that back gives an empty list rather than an absent key (verified; design.md section 4
    carried the same wrong claim and is corrected there too). Nothing is wrong with the shipped code:
    the case is unreachable because no set is written yet, and `parquet_sha` avoids it by accident,
    since `meta$parquet_sha <- NULL` **removes** an element rather than nulling it. But it makes the
    seven-key assertion unable to tell a populated document from an unpopulated one, so **Task 9 must
    populate `document_sha` before it writes** and assert on the written bytes. Recorded in the
    builder's own roxygen, in Task 9's body, and in `dev/engineering-notes.md`.
  - **Four probes, each reverted, each naming what it reddened**: misclassifying `kind` as
    not-identity reddens 3 (the dedicated test plus both goldens); the set builder claiming
    `"datom-cv1"` reddens 1; reverting the rebuild to a hardcoded kind and disabling the
    `document_sha` history line reddens 1 each; an unclassified field on the set builder reddens 3,
    each naming the field. A fifth, the conditional-assign tidy-up above, reddens 3. One earlier
    probe was **discarded as imprecise**: deleting `kind` from both classification lists reddens 12,
    but through the write door's vocabulary check rather than through identity, which conflates the
    two mechanisms.
  - **Left for Task 9, both stated at the site rather than left to memory.** A rebuilt **set** row
    recovers its `kind` but not its `member_count`, because that number is in the payload rather than
    in either document the rebuild reads -- noted in `.datom_rebuild_manifest_entry()`'s docs and on
    the pathways card. And `.datom_update_manifest_entry()` still hardcodes `kind = "table"`, which
    is correct while only tables are written.
  - Tests 3053 -> **3077** (+24), FAIL 0 / WARN 0 / SKIP 0. `dev/check-spec.R` 9/9.
    **Pathway impact: yes** -- the reconstruction card's field-copying step and its closing warning
    both said `kind` was not in per-artifact metadata.

- [x] **8. `datom_member()` + the member and tag validators** &nbsp; **[DONE 2026-09-11. The
  heading said "+ self-reference check" until this task landed; that half is Task 9's, per the
  owner decision on the cold-start audit below.]**
  - `datom_member(conn, name, version)` mirroring `datom_parent()` (`R/lineage.R`): validate,
    read `{name}/.metadata/{version}.json`, derive `project` from `conn$project_name` and `kind`
    from the snapshot (defaulting to `"table"` for pre-`kind` metadata). Returns
    `{id: {project, name, kind, version}, tags: {...}}` as pure data.
  - **Signature gains tags**: `datom_member(conn, name, version, tags = NULL)` -- an optional named
    list of text values, validated against the R2.11 grammar at construction time (R4.6). Tags are
    **per-member** because they replace dpbuild's `dp$input` / `dp$output` / `dp$metadata` nesting,
    which classifies items rather than the collection. A value may be a string **or** a character
    vector, because the whole point of tags over folders is that an item can be in several
    categories at once.
  - `.datom_validate_members()` mirroring `.datom_validate_parents()`, including the `remedy`
    string pointing at `datom_member()`. It owns the **per-member** half of AC27 -- cases (a) non-text
    value, (b) `NA`, (c) `""` tag value. It **cannot** own the payload-level half: it sees one member
    at a time, so "same `id` twice with different `tags`" is invisible from here, and set-level `tags`
    never pass through it at all. Those are Task 9's (AC27 d/e). An earlier draft assigned all of
    AC27 here while Task 2 also claimed it; **retired** -- one half each, stated explicitly.
  - ~~**Refuse self-reference** (R4.5, AC9): a set listing itself as a member. One cheap check. The
    set's own identity is known from `project.yaml` (R10.3a).~~ **MOVED TO TASK 9 (owner-decided
    2026-09-10, on this task's cold-start audit; do not implement it here.)** Both R4.5 and AC9 say
    "at write time", and the set's own declared name -- R10.3a's precondition for the check -- is
    neither written nor read by anything until Task 9 reaches for it. This constructor could not
    trust it anyway: the connection it takes belongs to the **member's** project, so on a
    cross-project member it would be reading a different repo's `set:` field. What stays here is the
    half that actually delivers acyclicity: reading the member's snapshot, so a member can only point
    at something that already exists (R4.4).
  - **Deliberately NOT built: cycle detection, a visited-set guard, or a depth limit** (R4.3/R4.4,
    design.md 5 and 20.11). Members pin immutable versions, so the graph is acyclic **by
    construction** -- a set cannot reference something that contains it, because that thing did not
    exist when its members were chosen (same property as git history). And datom resolves **one
    level** and never traverses, so nothing could loop even if a cycle existed. An earlier draft
    specified all three; they solved a problem that cannot occur. **Do not reintroduce them as
    defensive code** (I10a).
  - **COLD-START AUDIT, 2026-09-10** -- the documented path (`dev/README.md` -> the state block ->
    this task -> design.md section 5 -> `dev/engineering-notes.md`) was walked as a fresh reader and
    every claim checked against the tree. **Startable, once the first item below is settled** -- it is
    a scope question, not an implementation one. **No escalation flag**: design.md section 12 carries
    E1 and E2 only, so nothing is owed under rule 5d.
    1. **THE SELF-REFERENCE REFUSAL CANNOT LIVE IN `datom_member()`, AND THIS TASK'S BULLET SAYING SO
       IS WRONG.** Three things settle it. AC9 says "refused **at write time**"; R4.5 says "cheap
       check **at write time**"; and R10.3a makes the `name == project.yaml$set` gate "the
       precondition the self-reference check (R4.5) relies on -- it needs to know the set's own
       identity before the write". Nothing in `R/` reads or writes a `set:` or `mode:` field today
       (verified by grep across every `yaml::read_yaml()` site: the developer conn reads
       `project_name` and the `storage` block, `datom_init_repo()` writes nine keys and neither of
       those two is among them), and the field only starts being written at Task 11. Worse, the
       `conn` this constructor takes is scoped to the **member's** project, exactly as
       `datom_parent()`'s is -- so for a cross-project member it would be reading a different repo's
       `set:` field, which says nothing about the set being built. **The check belongs in Task 9**,
       which knows its own name authoritatively because R10.3a's gate has just established it, and
       which sees every member at once. What this task legitimately keeps is the half that actually
       delivers acyclicity: reading the snapshot, which is what makes a member a pointer at something
       that already exists (R4.4). **Default: move AC9 and R4.5's refusal to Task 9** and strike the
       bullet here; nothing else in the task changes.
    2. **"MIRRORING `.datom_validate_parents()`" WOULD INHERIT A HOLE THAT AC27(b) FORBIDS.** That
       validator's per-field test is `is.character(val) && length(val) == 1L && nzchar(val)`, and
       **`NA_character_` passes all three** -- verified in R: it is character, length 1, and
       `nzchar(NA_character_)` is `TRUE`. AC27(b) requires `NA` refused. So the mirror must be
       **stricter than its model**, and a session that copies the field loop verbatim ships the
       defect while every test it wrote passes. (The looseness in `.datom_validate_parents()` itself
       is pre-existing and out of scope here -- recorded so it is not discovered a third time.)
    3. **`tags` MUST BE OMITTED WHEN ABSENT, NEVER DECLARED NULL -- AND NOTHING WOULD FAIL IF YOU GOT
       IT WRONG.** `list(id = ..., tags = NULL)` keeps the name, and the encoder is indifferent
       because an absent map and an empty map both encode `h(0x03)` (R2.10's pinned edge case) -- so
       no golden moves, no hash changes, no test reddens. What breaks is one layer down: Task 9
       serialises the payload with `jsonlite`, which writes `"tags": {}` for a NULL element rather
       than omitting the key, so every untagged member would carry the one spelling R2.10 says
       "writers never emit" and R2.7 forbids as a form of absence. This is the trap Task 7's review
       found in `document_sha`, one level down and with the failure mode inverted: there the field had
       to be **declared**, here it has to be **omitted**. Use the conditional-assign form and say why
       at the site.
    4. **THE ENCODER ALREADY REFUSES MOST OF AC27(a) AND (b), SO BE PRECISE ABOUT WHAT THE VALIDATOR
       ADDS.** `.datom_sv1_as_strings()` (`R/hashable-set.R:112`) already refuses a `NULL` value, `NA`
       in every form, a named list in a value position, an unnamed list holding a non-scalar-string,
       and any non-character atomic -- each with a message naming the key path and the allowed types.
       `.datom_sv1_map()` already refuses a blank or duplicated tag **key**. What is genuinely new:
       the **empty-string** refusal (AC27(c)) -- there is no `nzchar()` check anywhere in the encoder,
       so `""` currently hashes as an ordinary label; the **`id` shape**, since
       `.datom_sv1_member()`'s own docs say enforcing "exactly these four keys, each single-valued" is
       validation's job and it does not do it; `kind` being one of exactly `"table"` / `"set"`; and
       messages that arrive **before** the encoder's, since validation runs first. Do not re-implement
       what the encoder already says -- and note the encoder's aborts carry **no condition class**, so
       tests key on message text there.
    5. **A SPEC CONTRADICTION THAT LANDED EXACTLY HERE, NOW SETTLED (owner-decided 2026-09-10): what a
       zero-length tag value does.**
       R2.10 says "an empty tag value is **refused by validation**"; R2.14's tidy table says
       `domain = character(0)` has its **key dropped** silently. Both are live instructions and they
       disagree, and this task is where it bites, because `datom_member()` validates at construction:
       read one way it aborts, read the other it drops. **Resolved: R2.14 wins** -- it is the later
       owner decision (tidy-then-validate, 2026-08-18: handle trivial errors silently, refuse only
       what needs intent guessed), so `datom_member()` **drops the key**, and R2.10's sentence plus
       design.md 7.2's "all three are refused" have both been corrected rather than followed (the
       design copy also wrongly lumped the exact-duplicate member in with the refusals; it is tidied,
       not refused). Worth knowing why it cannot simply be passed through untouched: a present
       key with an empty value hashes as `h(0x03 || str(k) || h(0x02))` while an absent key hashes as
       `h(0x03)`, so an untidied payload mints a **different `data_sha` for the same fact**.
    6. **THE RETURN SHAPE IS NOT `datom_parent()`'s, and "mirrors it beat for beat" is about the
       sequence, not the result.** `datom_parent()` returns five flat fields including `data_sha`; a
       member returns `{id: {project, name, kind, version}, tags}` and carries **no `data_sha`** on
       purpose (design.md section 5: the version already pins content, and a second copy is a second
       thing to keep consistent). This one is at least loud -- `.datom_sv1_member()` aborts on any
       field outside `id` / `tags`.
    7. **A NEW EXPORT OWES FOUR THINGS HERE, NOT ONE.** Verified mechanically: all 38 current exports
       appear in `_pkgdown.yml`, and `pkgdown` is a required status check, so an entry there is not
       optional. The other three are NAMESPACE (via roxygen), a `man/` page, and a **runnable
       example** -- the house pattern for this package is a real offline walkthrough guarded by
       `requireNamespace("git2r")`, building a bare git repo as the remote and a temp dir as the
       store, **not** wrapped in `\dontrun{}` (see `datom_parent()`'s). A `datom_member()` example
       needs no set: write a table, take its version from `datom_history()`, call the constructor.
    8. **NO `schema_version` CHECK ON THE DOCUMENT IT READS, matching `datom_parent()`.** Verified:
       `datom_parent()` reads the version-pinned snapshot with no `.datom_check_schema_version()`
       call; the only two call sites in `R/` are the `datom_read()` entry and the manifest rebuild.
       **Default: mirror the gap rather than close it here.** Adding the check to `datom_member()`
       alone would make two sibling constructors disagree about the same document, and closing it for
       both is a behaviour change to a shipped read path that no requirement in this spec asks for.
       Recorded so it reads as a decision rather than an oversight.
    9. **Two smaller corrections.** design.md section 5's sub-heading writes
       `datom_member(conn, name, version)` while R4.6 and R12.1 both give `tags = NULL` -- the heading
       is stale. And `.datom_validate_name()` hardcodes `{.arg name}` in all six of its messages,
       which is finally **correct** for this constructor's argument name (it has always been mildly
       wrong for `datom_parent(table = )`).
    10. **Test fixtures to follow.** `tests/testthat/test-parent.R` is fully mocked --
        `mock_datom_conn()` from `helper-mock.R` plus
        `local_mocked_bindings(.datom_storage_read_json = ...)` -- and its header records that
        versions must be 6-64 lowercase hex because `.datom_validate_sha()` runs first. That is the
        model for `datom_member()`. `tests/testthat/test-hashable-set.R` already has `mid()` and
        `mem()` helpers that build exactly the four-key `id` map; they are the model for member
        fixtures, and its refusal tests (lines 383-493) are where the encoder-side grammar cases
        already live, so the new validator's tests should not restate them.
  - _Requirements: R4 (incl. R4.3, R4.4), R2.11, R2.7. Invariants: I9, I10, I10a, I24.
    Acceptance: **AC27 (a, b, c -- the per-member half)**. **AC9 and R4.5 are NOT this task's** per
    the audit above (item 1): both say "at write time", and the set's own identity does not exist
    until Task 9's R10.3a gate reads it -- the owner settled it the same day, and they now sit with
    Task 9._
  - **DONE 2026-09-11.** Everything is the new `R/member.R`, plus one constant.
    1. **`datom_member(conn, name, version, tags = NULL)`**, exported. Same step sequence as
       `datom_parent()` -- connection check, name check, version check including the guard that stops
       a version string escaping the namespace, snapshot read, pure data out -- and a different
       result: `{id: {project, name, kind, version}}` with `tags` present only when there are any,
       and **no `data_sha`**, because the version already pins the content. `project` comes from the
       connection, `kind` from the snapshot with `"table"` as the fallback for a snapshot written
       before the field existed.
    2. **`.datom_validate_members()`**, the checker Task 9 runs. Nothing calls it yet; that is the
       sequencing, not an oversight, and it is fully tested from the test file.
    3. **`.datom_validate_tag_map()` and `.datom_drop_empty_tags()`**, the tag grammar and the one
       tidy rule, in one place so that the constructor, the checker, and Task 9's set-level tags all
       share them rather than growing three copies.
    4. **`.datom_artifact_kinds`** in `R/utils-validate.R` beside the other internal vocabularies,
       append-only for the same reason they are: a build that stopped recognising a kind would refuse
       an **older** document. Task 10's read will want it too; the two existing `match.arg()` sites
       are local and were left alone.
  - **Three things a later change must not undo.** (1) An untagged member **omits** the tags key.
    Building the record as `list(id = ..., tags = tags)` looks equivalent and is not: `list()` keeps
    a NULL element where `$<-` removes it, and `jsonlite` writes such an element as `{}` rather than
    dropping it -- so every untagged member would land in the stored payload carrying an empty
    object. **No hash and no golden can see this**, since an absent tag map and an empty one both
    encode as `h(0x03)`, which is why the guard is an assertion on the emitted bytes and why a test
    pins the two hashes as equal so the next reader does not try to catch it through identity.
    (2) The field test is **stricter than `.datom_validate_parents()`**, which accepts a missing
    value -- character, length 1, and `nzchar(NA_character_)` is `TRUE`, so the obvious three-part
    test lets it through. A test pins that the older validator really is looser, so the divergence is
    evidence rather than a claim. (3) **Tidy runs before validate**, and the validator deliberately
    **passes** a key whose value is empty. Reversing the order makes the tidy rule unreachable.
  - **Six probes, each reverted, each naming what it reddened**: building the record with
    `tags = tags` inside `list()` reddens 5 assertions across 3 tests, including both byte-level
    ones; dropping the missing-value clause from the field test -- i.e. mirroring the parents
    validator verbatim -- reddens 3; disabling the empty-label refusal reddens 8 across 5 tests;
    disabling the unknown-kind refusal reddens 3; removing the tidy step reddens 4; disabling the
    fifth-`id`-field refusal reddens 2.
  - **Four decisions the task body did not settle.** (1) **A `NULL` tag value is dropped, exactly
    like `character(0)`.** The tidy table names only the second, but `list(domain = f())` where `f()`
    returned nothing is the same nothing, and dropping one spelling while refusing the other is the
    inconsistency tidy-then-validate exists to remove. The encoder still refuses a parsed `null`, and
    must -- there the value came from a file, so there is no caller intent to tidy toward.
    (2) **Per-value type checking delegates to `.datom_sv1_as_strings()`**, the encoder's own
    coercion, rather than restating its rules; two copies of "what counts as text here" would
    eventually disagree, and its messages already name the offending key and the allowed types. What
    the validator adds on top is the empty-label refusal, the four-key `id` shape, and `kind` being
    one of exactly two values -- which is what the audit predicted. (3) **A named character vector**
    (`c(type = "output")`) is refused rather than coerced to a list: it cannot express a multi-valued
    tag, so accepting it would add an unrequested tidy rule that Task 9's canonicalizer would also
    have to know about. (4) **Tag values are not sorted, deduplicated or unboxed here**, so canonical
    form has one implementation and it is Task 9's; a test pins that an out-of-order duplicated value
    survives the constructor untouched.
  - ~~**No format-number check on the snapshot it reads**, mirroring `datom_parent()` -- the audit's
    stated default. Closing it for one of two sibling constructors would make them disagree about the
    same document, and closing it for both is a behaviour change to a shipped read path that no
    requirement here asks for.~~ **REVERSED by review the same day; BOTH constructors now check, and
    the reason the original was wrong is worth keeping.** The audit's default was defensible on its own
    terms and stopped one question short: it asked whether the two siblings should agree, and not what
    the absent check was holding up. It is holding up the `kind` fallback. An absent `kind` is read as
    `"table"`, which is right for a document written before the field existed and **wrong for one
    written by a build this version cannot fully parse** -- there a **set** is recorded as a table, and
    the misreading is durable rather than momentary: it goes into the member record, into the stored
    payload, and into the set's own `data_sha`, so a citation names the wrong kind of artifact
    permanently with nothing failing. The format check is exactly what separates "old document,
    therefore certainly a table" from "newer document, therefore unknown". **The codebase had already
    settled this** and the audit missed it: `.datom_rebuild_manifest_entry()` checks the per-artifact
    document (`R/manifest-rebuild.R:228`) and then applies the identical fallback (`:210`), so of the
    three places that derive `kind` from such a document, one checked and two did not. `datom_parent()`
    is gated in the same commit for the same reason at one remove -- its two fields are durable too,
    the `data_sha` becoming a storage address and the `source_lineage` being unioned into the lineage
    of whatever table declares the parent -- and because leaving one sibling ungated is what turned a
    gap into a precedent in the first place. The check sits **outside** the not-found handler at both
    sites, or the upgrade instruction gets reworded as "member not found" (the Task 4 lesson). **The
    behaviour change is real and is the accepted direction**: a snapshot declaring a format above what
    this build supports now aborts where it previously half-worked. Owner's standing position, stated
    2026-09-11, is that the released versions are experimental and unannounced, and that support for
    them must not buy fragility for what comes next -- which is what licenses tightening a shipped
    read path here rather than deferring it. It is also the posture
    `.github/copilot-instructions.md` already states: breaking loudly is acceptable at this stage,
    degrading silently is not. Tests 3218 -> **3227** (+9), including the pairing test that asserts
    both halves together -- absent format plus absent `kind` yields a table, newer format plus absent
    `kind` is refused -- because either half alone reads as arbitrary. Probed: removing the check at
    both sites reddens 5 assertions across 3 tests. NEWS carries it.
  - Tests 3077 -> **3218** (+141), FAIL 0 / WARN 0 / SKIP 0. `dev/check-spec.R` 9/9; `R CMD check`
    0/0/0 on docs and code/documentation agreement. Four internal `man/` pages plus
    `man/datom_member.Rd`, a NAMESPACE entry, and a new **Sets** section in `_pkgdown.yml` (which
    Task 9 and Task 10 extend). The roxygen example was run and its output checked, not just built.
    **No pathway impact**: the constructor reads the same version-pinned snapshot `datom_parent()`
    already reads, through the existing storage read -- no new lookup and no traversal.
  - **Citations re-derived by content** after `.datom_artifact_kinds` shifted every line below it in
    `R/utils-validate.R`: six live citations moved, of which the gate caught one (the rest resolved to
    real but unrelated lines). Dated Decisions rows left frozen.

- [x] **9. `datom_write_set()`**
  - **Two gates first, before any hashing or IO** (R10.3a, I15): the repo must declare
    `mode: product`, and `name` must equal `project.yaml`'s `set:` field. These are what make
    "one repo = one set" real, and the second is the precondition the **self-reference check** (R4.5)
    relies on -- it needs the set's own identity before the write. **Not** a cycle walk: there is
    none, and I10a forbids reintroducing one.
  - **THE SELF-REFERENCE REFUSAL IS THIS TASK'S** (R4.5, AC9) -- moved here from Task 8, owner-decided
    2026-09-10 on Task 8's cold-start audit. A set listing itself, at any version, is refused. It has
    to be here and not in the member constructor for two reasons: both R4.5 and AC9 say "at write
    time", and this is the first moment the set's own identity is known, because the gate immediately
    above just established that `name` equals what `project.yaml` declares. The constructor could not
    do it -- the connection it takes belongs to the **member's** project, so on a cross-project member
    it would be reading the wrong repo's `set:` field. One cheap comparison against the member list,
    after tidying so a duplicate spelling cannot hide it. **It is a nonsense check, not cycle
    detection**: cycles are structurally impossible (R4.4) and I10a forbids a visited set or a depth
    limit creeping in beside it.
  - **Signature: `datom_write_set(conn, members, tags = NULL, ...)`** (R12.2). The `tags` argument
    is **required structure, not decoration** -- R2.12 puts `tags` at the payload root, R2.6 hashes
    it, and AC2's converse half (a changed description mints a version) cannot be tested without it.
    R1.4 deliberately withholds `metadata =`, so this is the only channel.
  - Payload derived from members (each with optional per-member tags) plus optional **set-level
    tags** -- and **nothing else**. No view or navigation config: folder structure is a consumer-side
    projection over tags, never stored (R4.7, I25). No `metadata =` parameter -- user metadata is
    tags (R1.4/R6.2).
  - Written **git-canonical + storage-mirrored**, with **different paths on each side** (R6.1a):
    git at the **stable path `{name}/set.json`** (modified in place, so `git diff` shows
    member-level changes and git owns the history), storage at the **content-addressed**
    `{name}/{data_sha}.json` via the Task 1 helper (so a reader fetches an exact version by
    address). **Do not content-address the git path** -- that makes every version a new file and
    forces history to be read by listing filenames, which is hand-maintaining what git maintains
    (R6.1b, R20, AC24). No retention rule is needed: git retention is definitional, and P17 holds
    via `git show <commit>:{name}/set.json`.
  - **TIDY, then VALIDATE, then hash** -- in that order (R2.14, R2.15, I26; design.md 21.4 steps
    0a/0b). Tidying first clears the benign spellings so validation only ever sees genuine ambiguity;
    validating first would make the tidy rules unreachable. Six things are tidied **silently and must
    not abort**: tag-value order, tag-value duplication, single-vs-array shape, member order, an
    exact-duplicate member (same `id` *and* `tags`), and `character(0)` dropping its key. Assert on
    the **file bytes** (AC29a), not the return value.
  - **Canonical order: map keys radix; tag values radix + dedupe; single values unboxed; members
    deduped by digest then sorted by `project` || `name` || `version`** (R2.15). Note the file sorts
    by **name, not digest** -- digest order would relocate a member whenever its tags change, so
    `git diff` would report a delete plus an insert instead of one changed field, undoing R6.1a's
    entire purpose. The hash still sorts by digest; two sort keys, each with its own reason.
    Unboxing rather than always-array because `auto_unbox = TRUE` is already the house default.
  - **This task owns the payload-level half of AC27** -- the cases only a whole-payload view can see:
    (d) the same `id` listed twice with **different** `tags` is **refused** (dedup does not catch it,
    since the digest covers tags, so both entries would survive and a consumer would find one member
    in two conflicting folders); (e) zero members; plus set-level `tags` grammar, which never passes
    through `datom_member()`. **And the allow-case (R2.14a)**: the same `project`+`name` at two
    different `version`s must write successfully with both members present -- its own test, because
    `project`+`name` looks like the natural duplicate key and tightening to it would silently break a
    legitimate use (a current table beside a locked baseline).
  - **Never re-emit a payload for a `data_sha` already in history** (R7.5 rule 1, I27, AC29b): reuse
    the stored object and **carry the recorded `document_sha` forward**. Mirror
    `.datom_resolve_parquet_sha()` (`R/read_write.R:516-536`) -- it already does exactly this for
    parquet, including the `upload = FALSE` return, and it is the function that decides; the scan it
    calls is `.datom_lookup_history_parquet_sha()` (`R/read_write.R:644-661`), which returns a hash or
    NULL and nothing else. (An earlier version of this bullet named the scan and cited two ranges
    belonging to neither function; corrected by the cold-start audit below, item 3.) **This is the defect that passes
    every per-chunk test**: recomputing `document_sha` from fresh bytes while reusing the stored
    object records a hash of bytes nobody stored, and it surfaces later as a refused read of a valid
    version. Reachable by an ordinary tag-value reorder, not just a dependency upgrade -- see
    design.md 7.2.3.
  - **Reuse unchanged**: change detection (`.datom_has_changes()`), the git-gates-storage ordering
    (`datom_write()` steps 7-10), and dedup. Git push stays the serialization point (I5).
  - Cross-kind name uniqueness refusal (AC4) -- checked against **storage**
    `{name}/.metadata/metadata.json`, not the manifest, which can lag.
  - Manifest entry with `kind = "set"` and `member_count`. **`member_count` is the count AFTER
    tidying** -- the canonical member count, not what the caller passed. Pinned because tidying can
    drop an exact duplicate, so the two can differ; today they rarely do, which is exactly why an
    unstated rule would be settled by accident.
  - **THE REBUILT SET ROW IS THIS TASK'S TOO, and it is wrong in two directions, not one** (found in
    Task 7's review). R8.1 says a set entry carries `member_count` **instead of** `size_bytes`;
    `.datom_rebuild_manifest_entry()` (`R/manifest-rebuild.R`) currently produces neither correctly
    for a set -- `member_count` is absent, because it lives in the payload rather than in the two
    documents the rebuild reads, and `size_bytes` is **present as 0**, because the default has length
    1 and so survives `purrr::compact()`. One field short and one field long, and a rebuilt repo then
    answers differently from a healthy one, which is the whole thing AC37(f) exists to prevent.
    **Extend `local_rebuild_project()` / the field-for-field test (`tests/testthat/test-manifest-rebuild.R:362`)
    to write a set**, because that test compares row field sets and would catch both -- but its
    fixture writes tables only, so today it cannot fire. This is the same shape as the `kind`
    hardcode Task 7 closed: a real guard exists and reaching it depends on somebody connecting two
    files.
  - **POPULATE `document_sha` BEFORE WRITING THE METADATA DOCUMENT, and assert on the written bytes.**
    `jsonlite` does not omit a NULL element -- it writes `{}` and reads it back as an empty list -- so
    a set metadata document written while the field is still unpopulated has its seven keys and one of
    them is an empty object. R1.3's `setequal(names(meta), ...)` check cannot see that, which is why
    AC29a's assert-on-the-file-bytes instruction covers this too. `parquet_sha` never hits it because
    its only outcomes are a real hash or `meta$parquet_sha <- NULL`, and assigning NULL removes the
    element rather than nulling it.
  - **COLD-START AUDIT, 2026-09-11** -- the documented path (`dev/README.md` -> the state block ->
    this task -> design.md 21.4 -> `dev/engineering-notes.md`) was walked as a fresh reader and every
    claim in this task checked against the tree. **Startable, and NOTHING IS OPEN: the two
    scope questions the audit raised were both APPROVED AT THEIR STATED DEFAULTS by the owner on
    2026-09-11 -- explicitly, not on silence -- so they are decisions rather than defaults that
    happened to hold. Each is marked DECIDED below, with what was approved.** **No escalation flag** -- design.md 12 carries
    E1 and E2 only -- so nothing is owed under rule 5d. What held: the rebuilt-set-row analysis is
    exactly right (`size_bytes = as.numeric(meta$size_bytes %||% 0)` yields `0`, which has length 1 and
    survives `purrr::compact()`, while `member_count` lives in the payload and so is unrecoverable from
    the two documents a rebuild reads); the field-for-field test really does compare row field sets and
    really does write tables only; and `.datom_write_metadata_local()` reads `document_sha` off the
    metadata object, which is what makes "populate it before writing" the right instruction rather than
    a plumbing change.
    1. **DECIDED (approved 2026-09-11) -- THE TWO GATES READ FIELDS NOTHING WRITES, AND TASK 11
       (WHICH WRITES THEM) RUNS AFTER THIS TASK.** Verified by grepping every `yaml::write_yaml()` site: there are two,
       `datom_init_repo()` (`R/conn.R:618`; at the time, nine keys with neither `mode` nor `set` among them -- Task 11 added both, conditionally) and
       `datom_repo_set_data_store()`, and no `mode` or `set` is read anywhere in `R/` either. So the
       moment this task lands, **`datom_write_set()` is unreachable through the public path**: no repo
       can declare `mode: product`, so every set write is refused at its own door, and the same is true
       of Task 10's read tests. This is the same shape as Task 4, whose gate landed tested-but-inert on
       purpose so that Task 6's writer bump was not the first exercise of untested gate code -- and it
       is fine, **but it has to be said**, because silence reads either as a defect or as an invitation
       to pull Task 11's init work forward. Pulling it forward is the wrong move: Task 11 is blocked on
       Task 23 precisely because writing `mode` needs a released build that already reads
       `project.yaml`'s format number, so moving the init half up drags Task 23 up with it. **APPROVED:
       keep the order; fixtures hand-write `project.yaml`, and the task states the inertness the way
       Task 4 did.** Second half of the same item, unstated anywhere: `mode` and `set` **do not ride on
       the conn** -- only `min_writer_version` does (`R/conn.R`, read in `.datom_get_conn_developer()`)
       -- so this task must decide between reading `project.yaml` directly at the gate and adding two
       conn fields. Task 11 inherits whichever is chosen, so choose it here rather than there.
       **APPROVED: read `project.yaml` at the gate.** Simpler now, and recorded here so Task 11
       inherits it rather than re-deciding; if that task later wants the two facts on the conn, it is a
       move with one caller to update rather than a question reopened.
    2. **`datom_write_set()` MUST CALL `.datom_check_write_entry()` ITSELF, and this task's body does
       not say so.** Three sites call it today -- `datom_write()` (`R/read_write.R:1143`),
       `.datom_sync_data_metadata()` (`R/sync.R:168`) and `.datom_sync_metadata()`
       (`R/utils-sha.R:610`) -- and a fourth write verb inherits nothing from any of them. Left out,
       the floor, the format check and the vocabulary check are all silently skipped for every set
       write. This is the exact finding that has now landed in three consecutive tasks (Task 6's open
       call 1, Task 6's purity audit, Task 21's review): **a route that reaches storage without going
       through the write verb keeps being missed**, and the remedy each time was to gate the shared
       function rather than the entry point. Place it after the conn class check and before any
       hashing, as the sequence requires (I34).
    3. **THE `.datom_lookup_history_parquet_sha()` CITATION IS WRONG, AND IT NAMES THE WRONG
       FUNCTION.** This task cited two line ranges belonging to neither function for the
       reuse-and-carry-forward
       pattern. The scan is at `R/read_write.R:644-646` and it does **not** return
       `upload = FALSE` -- it returns a hash or `NULL`. The pattern this task actually wants is
       `.datom_resolve_parquet_sha()` (`R/read_write.R:516-536`), which is the one that decides between
       carrying the current value forward on a metadata-only change, reusing a recorded value found in
       history, and uploading fresh -- returning `list(parquet_sha =, upload =)`. Mirror **that**;
       `.datom_lookup_history_parquet_sha()` is the scan it calls. The gate could not catch this: the
       cited lines are real prose, just not the prose claimed.
    4. **THE LIVE WRITER HAS THE SAME SET-ROW DEFECT AS THE REBUILD, and only the rebuild is flagged
       above.** `.datom_update_manifest_entry()` read `size_bytes` from the local metadata document
       and defaulted it to `0`. **Closed here**: that read now sits on the table branch only
       (`R/sync.R:1173`). A set's metadata has no `size_bytes` -- R1.4
       removed it -- so a **healthy** set write puts `size_bytes = 0` on the row and no `member_count`:
       one field long and one field short, which is the same two-directional wrongness this task
       attributes to the rebuild alone. Fix both, and note the healthy path is the more damaging of the
       two, because the rebuild only runs on a broken index.
    5. **`.datom_update_manifest_entry()` HARDCODED `kind = "table"`** and took no kind argument.
       Task 7's DONE record said so; this task's body did not, which is how a line handed forward twice
       gets missed a third time. **Closed here**: it now takes `kind` and `member_count`
       (`R/sync.R:1153`), and the `size_bytes` read moved onto the table branch.
    6. **DECIDED (approved 2026-09-11) -- "REUSE THE GIT-GATES-STORAGE ORDERING (`datom_write()`
       STEPS 7-10)" IS NOT A CALL -- those
       steps are inline in `datom_write()`'s body.** Verified: steps 0 through 10 are comments inside
       one function (`R/read_write.R:1039-1148`), not helpers. So this task either **extracts** the
       commit-push-then-upload sequence or writes a parallel copy of it, and that is the largest
       scoping decision in the task while being phrased as though it were free. Extraction is the
       better direction -- a second copy of "git must succeed before storage is touched" is a second
       place for I5 to be broken -- but it edits the table write path, so it wants saying out loud
       rather than discovering. **APPROVED: extract, and say in the commit that the table path was
       touched.**
    7. **`.datom_has_changes()` genuinely does work unchanged for a set**, verified rather than
       assumed: it keys off whether `metadata.json` exists, recomputes the recorded document's identity
       through the allowlist, and compares `data_sha`. Task 7 classified the set builder's fields, so
       the recompute is correct for a set document. Recorded because "reuse unchanged" is a claim a
       fresh session would reasonably want to check, and the check is not free.
    8. **The set payload is not in `git_paths`.** `.datom_write_metadata_local()` returns
       `git_paths = c(metadata_path, history_path)`, so `{name}/set.json` must be written separately
       and appended to the commit's file list -- which `datom_write()` builds by hand from that vector
       plus `.datom/manifest.json`. One more reason item 6 leans toward extraction.
    9. **`member_count` is deliberately absent from `.datom_manifest_entry_known_fields`** (eight names,
       `R/forward-compat.R:69-72`), so its forcing function trips the moment this task adds the field.
       That was Task 20's stated intent, not an oversight -- add the name, do not weaken the test.
  - _Requirements: R5, R6 (incl. R6.1a/b), R7.5, R2.14, R2.14a, R2.15, R10.3a, R12.2, R8 (set
    entries), **R4.5 (moved here from Task 8)**. Invariants: I2, I5, I6, I10a, I11, I15, I25, I26,
    I27. Properties: P7, P13, P17, P25, P29,
    P32. Acceptance: AC2, AC3, AC4, AC5, **AC9 (moved here from Task 8 -- it says "at write time",
    and this is the first moment the set's own identity is known)**, AC24, AC29 (a and b),
    **AC27 (d, e, set-level tags, every tidy assertion, and the R2.14a allow-case)**._
  - **DONE 2026-09-13.** The new `R/set.R` holds the verb and the canonical form; the rest is edits
    to four existing files.
    1. **`datom_write_set(conn, members, tags = NULL, name = NULL, message = NULL)`**, exported.
       R12.2 gives the first three and a `...`; `name` and `message` are the `...`, made explicit.
       **`name` defaults to the repo's declared set** rather than being required -- the gate's job is
       to refuse a *mismatch*, and a caller repeating what the repo already declares is a second
       place for the same fact. Supplying a different name still aborts, which is what R10.3a asks
       for.
    2. **`.datom_check_set_write_gates()`** -- the two refusals, reading `.datom/project.yaml`
       directly, and it returns the resolved name. **They run BEFORE the write entry check**, which
       is a deliberate deviation from I34's "directly after the conn class check": the entry check
       takes the name of the artifact being written, and `NULL` there means "inspect every artifact
       in the clone", so running it first would make the door's scope depend on whether the caller
       happened to pass `name`. The gates are what establish which artifact this is.
    3. **Canonical form in three pieces**, split by what each can safely touch.
       `.datom_tidy_tag_map()` / `.datom_tidy_tag_value()` sort keys, sort and dedupe values, and
       normalise the three spellings of a string set into a character vector so `auto_unbox = TRUE`
       does the unboxing; `.datom_tidy_set_payload()` applies that at both levels plus the `id` key
       order; `.datom_order_set_members()` dedupes by member digest and sorts by
       `project` || `name` || `version`.
    4. **`.datom_check_set_payload()`** -- zero members, the same `id` twice with different tags, and
       self-reference. All three need the whole payload, which is why none of them is in the member
       validator.
    5. **`.datom_resolve_document_sha()` and `.datom_lookup_history_document_sha()`**, in
       `R/read_write.R` **beside their parquet siblings** rather than in `R/set.R`, because the
       decision is the same decision and adjacency is the only thing that stops the two drifting. The
       scan itself is now one function, `.datom_lookup_history_object_sha(conn, name, data_sha,
       field)`, with a thin wrapper per kind -- the existing parquet wrapper keeps its signature, so
       the tests that mock it needed no edit.
    6. **`.datom_commit_and_mirror()`**, the extraction: commit, push, then the payload upload, then
       the metadata mirror, then the manifest mirror. `datom_write()`'s steps 7-10 are now one call
       to it. The payload object is passed as `list(path =, key =)` or `NULL`, so "this content is
       already stored and must not be rewritten" is expressed by the absence of an upload rather than
       by a flag each caller interprets.
    7. **`.datom_check_artifact_kind()`** -- one name is one artifact, checked against the document
       change detection has just read, so it costs no extra round trip. Called from **both** write
       verbs: AC4 says "or vice versa", and the table-over-set direction is the more damaging one.
    8. **`.datom_update_manifest_entry()` gained `kind` and `member_count`** and no longer hardcodes
       the kind -- the line handed forward three times. The `size_bytes` read moved onto the table
       branch, because a set's metadata has none and reading it there would default a real absence
       to `0`.
    9. **The rebuilt set row** now carries `member_count`, from a third storage read
       (`.datom_rebuild_member_count()`, at the content-addressed payload key), and no `size_bytes`.
       An unreadable payload leaves the count out rather than guessing, on the same trade the rest of
       that file makes.
  - **Six things a later change must not undo.**
    1. **The file's member order is not the hash's member order.** The hash sorts digests, which is
       what keeps the encoder from needing to know what an `id` looks like; the file sorts by name,
       which is what keeps an entry in place when its tags change. Digest order in the file would make
       `git diff` report a delete plus an insert -- undoing the entire reason the git copy sits at a
       stable path.
    2. **Tidy is tolerant on purpose, and that is what lets it run first.** A value this build does
       not recognise as text is returned **untouched** rather than normalised, so the validator is
       what reports it. A tidy step that reached for `sort()` on a list or a function would fail with
       a base-R message naming nothing, and the fix for that is not to validate first -- validating
       first makes every tidy rule unreachable.
    3. **`document_sha` is populated before the metadata document is written.** `jsonlite` writes a
       NULL element as `{}`, so the alternative is a seven-key document one of whose values is an
       empty object -- unverifiable on read and indistinguishable from corruption. A NULL decision
       aborts rather than being written, because a set has no legacy population to be lenient about.
    4. **The payload is uploaded from the same file git holds.** Not re-serialized for storage: that
       is what makes "one `data_sha`, one byte spelling" true by construction rather than by two
       serializations agreeing.
    5. **`member_count` is the count after tidying.** Tidying can drop an exact duplicate, so the two
       can differ; today they rarely do, which is exactly why an unstated rule would be settled by
       accident.
    6. **The self-reference check keys on `project` **and** `name`, and stays a nonsense check.**
       Another project's artifact that happens to share this set's name is an ordinary member, and has
       its own test. Nothing here may grow into cycle detection (I10a): a member pins a version that
       already exists, so a set cannot reference anything containing it.
  - **Eight probes, each reverted, each naming what it reddened**: skipping the tidy step reddens 10
    assertions across 5 tests; sorting the file by member digest reddens 4 across 3; making the reuse
    scan always return NULL -- i.e. recomputing `document_sha` for content already stored -- reddens 3
    across 2; removing the write-entry call reddens 3 across 2; putting `size_bytes = 0` on a set row
    beside `member_count` reddens 4 across 3 **including the rebuild-parity test**; removing the
    self-reference refusal reddens 2; content-addressing the git payload path reddens 17 across 13;
    leaving `document_sha` declared-but-unpopulated (with the abort guard disabled too, or the probe
    only measures the guard) reddens 6 across 4, including the field-set assertion on the written
    bytes.
  - **The digest-order probe is the one worth recording as a method note.** It first reddened
    **nothing**, because the fixture had two members and digest order agreed with name order by
    chance -- a coin flip masquerading as a guard. The fixture is now five names pinned at one version
    where digest order is the exact **reverse** of name order, asserted in the test itself so the
    pinning is visible rather than incidental.
  - **Four decisions the task body did not settle.** (1) **The payload's own two keys are not
    sorted**: R2.15 step 1 enumerates which maps get radix-sorted keys -- set-level tags, each
    member's `id`, each member's tags -- and the payload root is not among them, so it keeps the
    `tags` then `members` order of R2.12's example. Deterministic either way, since it is constructed
    rather than passed through. (2) **A `metadata_only` change is handled and unreachable.** A set's
    hashed fields are `data_sha`, `hash_algo` and `kind`, so unchanged content means an unchanged
    version; the branch carries the recorded hash forward anyway, because an encoder or a decision
    function whose correctness rests on an upstream impossibility breaks silently the day the
    impossibility moves. (3) **`.datom_check_artifact_kind()` uses `switch()` rather than a named
    lookup** for the "write it with this verb instead" hint: `found` comes off a document, and a
    third value would otherwise raise a subscript error inside the function that exists to explain
    the problem. (4) **The row-vocabulary forcing test now writes a row of each kind.** A set row
    carries `member_count` instead of `size_bytes`, so no single row can carry every name on the
    list; the alternative was an exception vector, which hides the asymmetry rather than asserting
    it. The test additionally pins that the two rows really do differ in that one field, so the union
    cannot pass because both rows came out the same shape.
  - **REVIEWED after it landed; one finding, fixed (tests 3413 -> 3418). Key order was canonicalized
    at two levels and needed three.** `.datom_tidy_set_payload()` sorted the set's tag map and each
    member's `id`, and left the member record's **own** two keys alone -- so a hand-built
    `list(tags = , id = )` serialised differently from `list(id = , tags = )` while producing an
    identical `data_sha`. The encoder reaches both member slots **by name**, so it cannot see the
    difference; only the file can. **Where it bites is exactly the case the reuse machinery exists
    for**: on a revert to content already in history, the clone's payload is rewritten from the
    current spelling while the stored object is deliberately reused, so git would hold bytes that do
    not match the recorded `document_sha` while storage holds bytes that do -- a refused read of a
    valid version, from the copy that looks canonical. That is the failure
    `.datom_resolve_document_sha()`'s own documentation warns about, reached through a path it did not
    cover. **Narrow but supported input**: `datom_member()` emits `id` first and a JSON round trip
    preserves that, so it takes a hand-built record -- which `.datom_validate_members()` accepts by
    design, since a member is documented as pure data. One line, in the function that already sorted
    the level below, and **no existing payload changes** because alphabetically the canonical order is
    `id`, `tags`, which is what was already emitted (asserted, not claimed: the constructor's spelling
    of the same member re-writes as a no-op). The reason to fix it is the inconsistency rather than the
    odds -- sorting `id`'s keys exists so the file spelling is canonical, and stopping one level short
    left that guarantee incomplete for no stated reason. **The sort is guarded, and the guard has its
    own test**: `order(NULL)` is `integer(0)`, so an unconditional sort would **empty** a record with
    no names instead of leaving it recognisable for the validator to report. Probed both directions:
    removing the sort reddens 1, making it unconditional reddens 1.
  - Tests 3227 -> 3413 -> **3418** (+191), FAIL 0 / WARN 0 / SKIP 0. `dev/check-spec.R` 9/9; `R CMD check`
    0/0/0 on docs, code/documentation agreement and examples. Thirteen new internal `man/` pages plus
    `man/datom_write_set.Rd`, a NAMESPACE entry, and the **Sets** section of `_pkgdown.yml` extended
    (Task 10 extends it again). The roxygen example was run and its output checked, not just built --
    it hand-writes the two `project.yaml` fields, which is the honest form of the example while Task
    11 is still ahead.
  - **Pathway impact: yes** -- the write card's storage side now has a second shape (a JSON payload at
    a content-addressed key, mirrored from the git copy rather than serialized twice), and there is a
    new gate reading `project.yaml` on the write path.
  - **Left for later tasks, stated here rather than left to memory.** `datom_get_set()` and the
    `datom_read()` refusal are Task 10. `datom_validate()` still treats every artifact as a table, so
    it reports a set's payload missing (R11, Task 11's group). The repair half of R7.5 -- that
    `datom_validate(fix = TRUE)` must neither re-upload a stored payload nor recompute its
    `document_sha` -- is **not** implemented here and is AC29(c)'s clause in Task 14; this task owns
    rule 1 only.

- [x] **10. `datom_get_set()` + `datom_read()` refusal + the member link**
  - **SCOPE, settled 2026-09-13 after a design round on ergonomics.** This task delivers: the getter,
    both kind refusals, the `datom_set` class and its `print` method, and **`$fetch` on every member**
    -- the callable link that makes a member resolvable without the caller reassembling a call. The
    surface built **on top** of the result is split off so each half can be deferred without unpicking
    the other: **Task 24** is the read-side ergonomics (`datom_fetch_member()`,
    `datom_list_members()`, `datom_structure_members()`), **Task 25** the write-side
    (`datom_assemble_set()`, `datom_add_member()`, draft support in `datom_write_set()`). Both are
    appended, both execute after this task, and both state the dependency back.
  - **SIGNATURE AND RESULT** (specified nowhere before; both are public shape, so both were owner
    decisions rather than defaults): `datom_get_set(conn, name, version = NULL)` -- the three
    arguments `datom_read()` actually uses, **without** its two dead ones (`context`, `...`). Result:
    a list of `name`, `project`, `version`, `data_sha`, `tags`, `members`, classed **`datom_set`**
    (single class name, matching `datom_conn` and `datom_summary`; putting `"list"` in the vector
    opens `*.list` dispatch for no gain). The four identifying facts are there because a caller who
    passed `version = NULL` otherwise cannot say which version they got, and a set exists to be
    **citable**. **`version` is the version RECORDED in the history, never recomputed** -- so a caller
    who passed an 8-character prefix gets the full one back. Reuse
    `.datom_recorded_current_version()` (`R/manifest-rebuild.R`), which already solves this and
    already documents why recomputing is wrong.
  - `datom_get_set()`: resolve version -> download payload -> **verify `document_sha` before
    parsing** -> return references. A missing `document_sha` is an **error, not a skip**
    (design.md section 8) -- sets have no legacy population, so reproducing the `parquet_sha`
    grace would build a silent-degradation path on purpose.
  - **THE INTEGRITY GATE FORBIDS THE CONVENIENT READ, AND THE CONVENIENT READ WORKS.**
    `.datom_storage_read_json()` parses, so it cannot be used for the payload: download with
    `.datom_storage_download()`, hash the file, **then** parse it with
    `jsonlite::fromJSON(simplifyVector = FALSE)` (which is what keeps `members[]` a list of records
    rather than a data frame -- R2.5's one residual condition). Verified both halves: the download
    plus `digest(file =)` reproduces the recorded `document_sha`, and `.datom_storage_read_json()`
    returns a structure **identical** to parsing the downloaded file -- so nothing fails if you reach
    for it, and there is then nothing left to hash but bytes you re-serialized yourself. That is the
    write path's "hash of bytes nobody stored" defect, inverted.
  - **THE READ NEVER TIDIES.** `.datom_tidy_set_payload()` is right there and
    `.datom_tidy_tag_value()`'s own comment says the spelling it normalises is "what a payload read
    back from storage looks like". Run it on a healthy payload and **nothing changes**, because the
    write already canonicalized -- so you reach for it, every test passes, and it diverges later.
    Three reasons, in this order: (1) **load-bearing, R7.5 rule 2** -- repair must neither re-upload
    payload bytes nor recompute `document_sha` for an already-stored version, and a repair built on a
    tidying read does **both**, re-emitting reshaped bytes over an object whose recorded hash
    describes different bytes; that is **Task 14's failure, caused here**, which is why the rule
    belongs in this task. (2) **The read reports what was cited** -- R2.12 says a reorder must not
    mint a *version*, not that a *reader* may perform one. (3) **Dropping an empty-valued key removes
    a key the document contains**, which R2.12's ordering table does not cover. An earlier version of
    this rule argued from information loss and was **refutable by the spec** -- R2.12 states nothing
    in the payload is ordered, so "sorting loses the stated order" falls to the spec's own terms.
    Recorded because the conclusion was right and the argument was not.
    **Canonicalization belongs to the write; the read normalizes representation only.**
  - **THE ONE ALLOWED NORMALIZATION, and it must cover `id` as well as `tags`.** `jsonlite` unboxes on
    write, so one tag key returns in three R shapes -- verified: `["a","b"]` parses to a list of 2,
    `"a"` to `character(1)`, and **`["a"]` to a list of 1**. Normalise a character-only array to a
    character vector: same strings, same order, same count, via the element test
    `.datom_sv1_as_strings()` already applies. **Never touch the presence axis** -- absence stays
    `NULL`, never `character(0)`, never `NA`. **`id` values get the same normalization and then a
    refusal**: if a value is still not a text scalar, **abort as a malformed document naming the
    member** rather than comparing it. `id` values are spliced into storage keys, and
    `.datom_validate_members()` enforces that contract on **write only**, so the read is where it has
    no enforcement at all; Task 24's project comparison would otherwise compare a list against a
    string and report a member of *this* project as belonging to another. Say at the site that
    `datom_write_set()` cannot produce the case.
  - **EVERY MEMBER CARRIES `$fetch(conn)`, AND IT IS A SELF-DESCRIBING LINK.** Not an add-on: it is
    how the read constructs a member. Without it, a downstream projection cannot be built without
    reimplementing datom's kind dispatch and version pinning -- the duplicated machinery this whole
    spec exists to prevent. **This sentence said "the project check" until 2026-09-14 and the link
    never did one**; it cannot, and the reason is in Task 24's body -- a reader's `project_name` is an
    unvalidated label, so a comparison there refuses working reads.
    - **`fetch`, not `read` or `get`.** It resolves a pointer to whatever it points at: a table
      member yields data, a set member yields another `datom_set`. `read` would promise content and
      `get` would promise references, and it is genuinely both -- so a neutral verb is the honest one.
      This is the **only** polymorphic door in the design, and the member level is where the domain
      forces it: iterating members, the caller cannot know each kind in advance. At the top level they
      named one artifact they chose, which is why `datom_read()` / `datom_get_set()` stay separate.
    - **No `...`.** `datom_get_set()` takes none and `datom_read()`'s is one of the two dead
      parameters this task refuses to copy, so dots would reach nothing for half the kinds.
    - **The factory is a NAMESPACE-LEVEL function, and every argument is `force()`d.** Both are
      load-bearing and the first is the one that gets missed: a factory defined *inside*
      `datom_get_set()` puts that frame -- which holds `conn` -- on the closure's parent chain, and
      `saveRDS()` of the member then writes the PAT into the file. **Demonstrated**, same code both
      ways: nested, 2094 bytes with the token present; namespace-level, 1609 bytes without.
      **Pin it on the serialized bytes, not on `environment(f)`** -- an environment check passes on
      the broken shape, because the connection is one frame up.
    - **The link carries its own pointer**: `attr(f, "datom_member")` holds the whole member record
      and the closure is classed `datom_link` with a `print` method. Verified callable, printable, and
      intact across a save/load round trip. This is what closes the loop -- a consumer holding only a
      projection can still cite what they used and add it to a new set (Task 25's
      `datom_add_member()` accepts a link). **It has to ship with the factory**: links built without
      the attribute cannot be repaired after the fact. The record is ~6 strings of pure data, so
      carrying it does not weaken the purity rule, which was about connections and not about size.
      **Do not** make the closure return its record when called with no connection -- that is the type
      instability refused at the top-level read, in miniature.
    - Docs must state that **a link pins the version it was read at**, since someone will expect
      "latest".
    - **`identical()` ON TWO READS OF THE SAME SET IS NOW `FALSE`**, and it needs saying in two places
      rather than discovering. Closures compare by environment, so two links built from the same facts
      in separate calls are not identical (verified; `identical(..., ignore.environment = TRUE)` is
      `TRUE`, and comparing `m["id"]` is `TRUE`). This matters because **`datom_read()`'s own roxygen
      example asserts `identical()`** for a table, so the asymmetry will be met by anyone reading the
      two help pages together. One sentence in `datom_get_set()`'s docs, and one note at the test
      fixture saying assertions compare `m[c("id", "tags")]` rather than `m` -- said once at the
      fixture, not at every assertion.
    - **Do not reach for "re-serializing a link fails loudly" as a safety property.** It was proposed
      as a backstop for R7.5 rule 2 and is **false**: verified, `jsonlite::write_json()` on a member
      carrying a closure succeeds and emits `"fetch":["function (conn) ", ...]` -- the deparsed source
      -- so the outcome is exactly the silent corruption it was offered as preventing. The write verb
      is protected because `.datom_validate_members()` and `.datom_sv1_member()` both refuse the extra
      field, and R7.5 rule 2 is protected by the never-tidy rule above. Recorded because a verified
      falsehood is worth keeping so it is not re-proposed.
  - **`print.datom_set()`** shows the description, one line per member (name, kind, compact
    `key=value` tags, `-` when untagged, truncated for large sets), and **names the best route that
    exists** -- the cheapest available fix for "how do I get data out of this", and worth more to the
    learning curve than any amount of structure. Tags are open-keyed, so fixed columns are impossible;
    do not try.
    - **At this task the hint is `x$members[[1]]$fetch(conn)`, NOT `datom_fetch_member()`.** That verb
      is Task 24's, and Phase F says either of those tasks can be deferred without unpicking this one
      -- which is only true if this message does not point at a function that may not exist. Task 24
      upgrades the hint when the named lookup lands. So the hint is correct at each stage rather than a
      compromise at either.
  - **`datom_write_set()` must accept a `datom_set`**, because `$fetch` breaks the read-modify-write
    loop in two places: `.datom_validate_members()` and `.datom_sv1_member()` both refuse a member
    field outside `id` / `tags`. Fix in the **write verb**, before validation, and strip `fetch`
    **only when `is.function()`** -- so the loop works from either spelling (`datom_write_set(conn, x)`
    or `datom_write_set(conn, x$members)`) while a hand-built `fetch = "junk"` still aborts. **Do not
    add a carve-out to the validator**: it keeps saying "a member is exactly `id` plus `tags`", and the
    write knows how to get there from a read. **And it must carry `x$tags` forward** unless `tags` is
    supplied explicitly -- otherwise read-append-write silently drops the set's description and mints
    a version without it.
  - Works with **no git clone** (AC1a) -- storage-only readers are the primary consumer. Verified: a
    reader-role conn with `path = NULL` reads a set's `metadata.json` and `version_history.json`
    without complaint, and `mock_datom_conn()` already defaults to exactly that, so the criterion
    needs no new fixture machinery. Nothing on this path may touch `conn$path`.
  - **ONLY ONE OF THE TWO HASHES IS A READ-TIME CHECK.** `document_sha` covers the stored bytes and is
    verified. `data_sha` must **not** be recomputed: it is the address the payload was fetched from,
    so it catches nothing `document_sha` did not, and it **would refuse a payload a newer datom
    wrote**, because the sv1 encoder aborts on a top-level payload key it does not know. Same reason
    the parsed payload is not re-validated. Precedent: `.datom_read_parquet()` verifies `parquet_sha`
    and never recomputes the cv1 hash. Reads limp.
  - **Return member pointers; do not resolve them to data.** AC1 distinguishes *resolving the
    pointers* (always works through this one conn) from *resolving to data* (needs a conn for the
    member's project). `$fetch` is how the caller crosses that line **deliberately**, one member at a
    time; the read itself crosses it never. Same-project members work through the same conn;
    cross-project members are the caller's to resolve (R18.1) -- datom has no name-to-location lookup.
    Getting this wrong mis-implements a set read as "requires access to everything in it", which would
    contradict the non-conjunctive access decision (R3.3).
  - **Both kind-mismatch directions abort with a pointer** (R12.3): `datom_read()` on a set ->
    `datom_get_set()` (AC6); `datom_get_set()` on a table -> `datom_read()` (AC14). Without the
    converse, a healthy table gets reported as a missing payload.
  - **WHERE THE CODE GOES.** The verb, the payload read, the link factory, the normalization and both
    `print` methods belong in **`R/set.R`** beside `datom_write_set()`; the two edits to shared
    machinery (`.datom_resolve_version()` gaining a field argument and a resolved version,
    `.datom_check_artifact_kind()` gaining `operation`) stay in **`R/read_write.R`** with their
    siblings, for the same adjacency reason Task 9 kept `.datom_resolve_document_sha()` next to
    `.datom_resolve_parquet_sha()`. Tests in a new **`tests/testthat/test-get-set.R`**;
    `write_product_config()` in `helper-mock.R` is the shared fixture step that makes a set writable,
    and `local_set_project()` in `test-write-set.R` is the fixture to mirror (duplicated per file, as
    this suite does deliberately). A new export owes four things here: NAMESPACE, a `man/` page, an
    entry in `_pkgdown.yml`'s **Sets** section -- all exports are listed and pkgdown is a required
    check, including all six existing `print` methods -- and a **runnable** example, which for this
    task means hand-writing `mode: product` and `set:` into `project.yaml` as Task 9's example does.
  - **One level only -- do not traverse** (R4.3, I10, AC15). A member that is itself a set is
    returned as a **pointer**; its own members are not fetched. Resist "helpfully" flattening the
    tree: a consumer wanting the full tree composes repeated reads, exactly as
    `datom_get_parents()` leaves further steps to the caller. Read cost must be a function of this
    set's direct member count, never of the depth beneath it (P16).
  - **THE ERGONOMICS LAYER IS TASK 24, NOT THIS TASK** (owner-decided 2026-09-13, on the audit
    below). This task delivers the read itself, the two kind refusals, the `datom_set` class and its
    `print` method -- "the read works, and its result can be read at a console". `datom_member_map()`
    and `datom_read_member()` are **Task 24**, appended and executing immediately **after** this one.
    Split because they are two logical changes with different risk: the member resolver alone roughly
    doubles this task's test surface (ambiguity, tag narrowing, project mismatch, kind dispatch), and
    a checkpoint between them lets the second be deferred without unpicking the first. **Task 24
    states the dependency back**, so the edge holds from both ends rather than depending on somebody
    reading the order at execution time -- the same two-directional pattern Task 23 and Task 11 use.
  - **RE-AUDITED 2026-09-13 after the design round, and the shape above is what changed.** Eight
    mechanical checks against the tree, all clear: the six new names collide with nothing on the
    current 40 exports; `.datom_read_metadata()` still has exactly **one** production caller, so
    extending it stays cheap; **no** existing test compares `.datom_resolve_version()`'s whole return
    value, so adding a field and a resolved version to it breaks nothing; both refusal points for an
    extra member field are live (`.datom_validate_members()` and `.datom_sv1_member()`), which is why
    the `fetch` strip goes in the write verb and covers both; `.datom_check_artifact_kind()` takes
    `(current, name, expected)` and needs only the `operation` word added;
    `.datom_recorded_current_version(meta, history)` is reusable as-is for the returned version; and
    `.datom_storage_download()` dispatches on both backends, so download-verify-parse is available
    without new plumbing. **The original audit below stands as written**, with items 1, 4, 12, 13 and
    14 now restated as scope bullets above -- it is kept because it is the record of how each was
    decided, and because five of its findings were verified against the tree rather than reasoned.
  - **COLD-START AUDIT, 2026-09-13** -- the documented path (`dev/README.md` -> the state block ->
    this task -> design.md 8 -> `dev/engineering-notes.md`) was walked as a fresh reader and every
    claim in this task checked against the tree. **Startable. Eleven findings, plus two more from the
    review round on the audit itself. The two scope questions it raised were both DECIDED by the owner
    on 2026-09-13 -- explicitly, so they are decisions rather than defaults that happened to hold --
    and each is marked DECIDED below with what was approved.** No escalation flag -- design.md 12
    carries E1 and E2 only -- so nothing is owed under rule
    5d. **What held**, verified rather than assumed: design.md 8's citation still resolves
    (`R/read_write.R:233` is the `parquet_sha` guard line); `document_sha` is present on a set's
    current `metadata.json` **and** on every `version_history.json` entry, so a version-pinned read
    has one to check; a set's versioned snapshot is written like any artifact's, so a set can be a
    member of a set; and `.datom_resolve_version()` resolves a set's `data_sha` correctly for both the
    current version and a pinned one, prefix matching included.
    1. **DECIDED (approved 2026-09-13) -- THE SIGNATURE AND THE RETURN SHAPE WERE SPECIFIED
       NOWHERE.** Not in this task, not in R12.3, not in design.md. "Return members + payload" is
       circular: the payload **is** members plus tags. Both are public shape, which is why neither was
       a default to take quietly. **APPROVED: `datom_get_set(conn, name, version = NULL)`** -- the
       three arguments `datom_read()` actually uses, in the same order and with the same meaning,
       minus its two dead ones (item 10). **APPROVED result: `name`, `project`, `version`, `data_sha`,
       `tags`, `members`**, classed `datom_set` (item 12). The identifying four are there because a
       caller who passed `version = NULL` otherwise cannot say which version they got, and a set
       exists to be **citable** -- forcing a second call to name what you just read is the one thing
       this artifact kind is for. **`version` is the version RECORDED in the history, never
       recomputed**, so a caller who passed an 8-character prefix gets the full version back;
       `.datom_recorded_current_version()` (`R/manifest-rebuild.R`) already solves exactly this
       problem for the current document and already documents why recomputing is wrong, so reuse it
       rather than hashing the document here.
       **`members` is a flat, UNNAMED list in payload order**, and every reason is silent if got
       wrong: the same `project` + `name` at two different versions is legal (R2.14a), so a name-keyed
       list is ambiguous exactly where the design says it must not be; `STUDY_001/ae` and
       `STUDY_002/ae` are both legal, so names collide across projects; and R's `$` **partial-matches
       on lists** (verified: `list(alpha = 1)$al` returns `1`) while a duplicated name silently
       returns the first, so a named list would answer plausibly and wrongly. The unique key is the
       **full `id`**, never the name.
       **Members carry no resolved data.** Excluded by R3.3 / AC1: materialising it needs a connection
       for every member's project, which is the "requires access to everything in it" reading this task
       forbids. ~~And no closures either.~~ **SUPERSEDED the same day by the design round -- members DO
       carry a closure, `$fetch`, and the scope bullets above are what to build.** The three reasons
       recorded here against a closure are kept because two of them still constrain its *shape* and one
       was simply wrong. Still true: the record is **defined by the payload**, which is why `$fetch` is
       stripped by the write verb rather than admitted to the payload; and the consumer builds their own
       wrapper in the projection case, which is why datom's leaf carries no policy. **Wrong**: that a
       callable record saves nothing, because it was measured on iterating every member, an operation
       nobody performs -- the operation that matters is reaching one leaf, and there the closure *is*
       the leaf a projection is built from, so without it a downstream package reimplements datom's kind
       dispatch, project check and version pinning. **Also wrong, and worth keeping as a correction**:
       a closure was said to be excludable because it would capture credentials. A projection's leaf
       **takes** a conn as a parameter rather than capturing one, so that is an implementation hazard
       rather than a reason -- and it is a real one, which is why the factory above is namespace-level
       (see design.md's consumer-boundary section).
    2. **THE INTEGRITY GATE FORBIDS THE CONVENIENT READ, AND THE CONVENIENT READ WORKS -- WHICH IS
       WHY A NAIVE IMPLEMENTATION USES IT.** `.datom_storage_read_json()` parses; the payload must be
       **downloaded, hashed, and only then parsed**, exactly as `.datom_read_parquet()` does. Verified
       both halves: `.datom_storage_download()` + `digest(file =)` reproduces the recorded
       `document_sha` bit for bit, and `.datom_storage_read_json()` returns a structure **identical**
       to parsing the downloaded file -- so nothing fails if you reach for it, and there is then
       nothing to hash but bytes you re-serialized yourself. That is the write path's
       "hash of bytes nobody stored" defect, inverted. Parse the downloaded file with
       `jsonlite::fromJSON(simplifyVector = FALSE)`, which is what keeps `members[]` a list of records
       rather than collapsing it to a data frame (R2.5's one residual condition); verified that the
       payload's `data_sha` recomputes from the parsed file.
    3. **`.datom_resolve_version()` HANDS BACK A `parquet_sha` AND A SET NEEDS A `document_sha`.**
       Verified: on a set's metadata it returns the right `data_sha` and `parquet_sha = NULL`. So this
       task either gives that function a field argument or grows it a sibling. **The precedent is one
       function with a field argument and a thin wrapper per kind** -- Task 9 did exactly that to the
       history scan (`.datom_lookup_history_object_sha()`), and for the same reason: two copies of
       "which recorded hash pins this version" would eventually disagree. Note the function takes a
       parsed `metadata_list` and does no IO, so whichever shape is chosen is unit-testable without a
       fixture.
    4. **DECIDED (approved 2026-09-13) -- THE KIND CHECK IS FREE, AND THE FUNCTION TO REUSE IS
       WRITE-FLAVOURED.**
       `.datom_read_metadata()` already returns the current document, so `current$kind` costs **no
       extra storage read** at either verb (verified). But `.datom_check_artifact_kind()`, which Task 9
       added, says "{name} already exists in this project as a {found}" and closes with "Write the
       existing {found} with {verb}, or pick another name" -- wrong at three points for a read, and it
       names the two **write** verbs. **APPROVED: give it an `operation` word (`"read"` / `"write"`)
       selecting the wording and the verb pair, following `.datom_check_schema_version()`, which took
       exactly that shape for exactly this reason. Not a read-side twin.** The reason to record: the
       rule is **one** invariant -- one name is one artifact -- and a twin lets the two directions
       drift silently, each passing its own tests. Note this word does more than the format check's
       precedent, because it selects the suggested **verbs** as well as the wording -- so **assert both
       directions' full messages, not just the condition class**. Target wording:
       `datom_read(conn, "study001-adam")` -> `"study001-adam" is a set, not a table.` plus
       `i Read it with datom_get_set().` **One condition class for one invariant**, for the same
       reason as the one function: a second class would let a test key on the write direction only.
       Related and settled: the check goes in each verb after its `.datom_read_metadata()` call rather
       than inside that function, because the two verbs want **different** answers from it -- the
       shared-function lesson from the write door does not transfer to a shared function whose callers
       disagree. `.datom_read_metadata()` has exactly one production caller, so the other route is
       cheap if it is ever wanted.
    5. **AC6's "cryptic missing-parquet error" IS CONFIRMED, NOT ASSUMED.** `datom_read()` on a real
       set today aborts with "File not found in local store" naming the store root, with nothing in it
       about sets or about `datom_get_set()`. Reproduced on the fixture from Task 9.
    6. **ONLY ONE OF THE TWO HASHES IS A READ-TIME CHECK, and "verify integrity" could easily be read
       as both.** `document_sha` covers the stored bytes and is verified. `data_sha` must **not** be
       recomputed on read: it is the address the payload was fetched from, so recomputing it catches
       nothing `document_sha` did not, and it **would refuse a payload a newer datom wrote**, because
       the sv1 encoder aborts on a top-level payload key it does not know. Same reason the parsed
       payload is not re-validated. Precedent: `.datom_read_parquet()` verifies `parquet_sha` and never
       recomputes the cv1 hash. Reads limp.
    7. **AC15 AND P16 NEED A NESTED SET, AND ONE REPO HOLDS ONE SET.** So a *real* inner set costs
       either a second project or rewriting `project.yaml`'s `set:` field between two writes. A
       **hand-built** member carrying `kind = "set"` is sufficient and cheaper -- `datom_member()` is
       documented as producing pure data and the member validator accepts one -- and if the inner set
       does not exist in storage at all, a traversing implementation **errors** rather than silently
       flattening, which is a louder signal than a count. Assert the count as well: the read-counting
       mock has two precedents to copy, `tests/testthat/test-forward-compat.R:670` and
       `tests/testthat/test-member.R:403`.
    8. **AC1(a) NEEDS NO NEW FIXTURE MACHINERY.** `mock_datom_conn()` already defaults to reader role
       with `path = NULL`, and such a conn reads a set's `metadata.json` and `version_history.json`
       without complaint (verified against a real local store). Nothing on the set read path may touch
       `conn$path`.
    9. **AC28(a)'s "before parsing" NEEDS A VALID IMPOSTER, and the engineering note for this
       technique is written about parquet.** Replace the stored payload with a **different but valid**
       JSON document; then the abort can only have come from the hash check. Garbage bytes would fail
       the parse too, so they prove less.
    10. **DO NOT COPY `context` OR `...`.** `datom_read()` carries both and its body ignores both;
        its docstring still claims dispatch via `dispatch.json`. A dead parameter on a **new** export
        is worse than on an old one, because nothing has to keep it. The stale line in `datom_read()`'s
        own documentation is pre-existing and out of scope here -- recorded so it is not inherited as
        fact.
    11. **Two bookkeeping items.** `_pkgdown.yml`'s **Sets** section needs `datom_get_set` (all
        exports are listed there and pkgdown is a required check, and all six existing `print` methods
        are listed, so `print.datom_set` needs an entry too), and the **New exports** table above
        still showed `datom_write_set()` unmarked though it shipped 2026-09-13. Four NAMESPACE entries
        across this task and Task 24, not five: three functions plus `S3method(print, datom_set)` --
        the class itself is not an export.
    12. **THE CLASS FOLLOWS THE HOUSE PATTERN: a single `"datom_set"`** (owner-decided 2026-09-13),
        matching `datom_conn` and `datom_summary`, which are both `structure(list(...), class = <one
        name>)`. `class(x) <- c("datom_set", "list")` was considered and rejected: `is.list()` is TRUE
        either way, nothing in datom tests `inherits(x, "list")`, and putting `"list"` in the vector
        opens S3 dispatch to `*.list` methods -- surprise surface for no gain.
    13. **THE READ NEVER TIDIES, AND THE TIDY FUNCTION IS RIGHT THERE INVITING IT.** Found on the
        review round after this audit, and it is a trap rather than an oversight:
        `.datom_tidy_set_payload()` exists, and `.datom_tidy_tag_value()`'s own comment says the list
        spelling it normalises is "what a payload read back from storage looks like". Run it on a
        healthy payload today and **nothing changes**, because the write already canonicalized -- so
        you reach for it, every test passes, and it diverges later. Three reasons, in this order:
        - **Load-bearing: R7.5 rule 2.** Repair must neither re-upload payload bytes nor recompute
          `document_sha` for an already-stored version. A repair built on a tidying read does **both**
          -- it re-emits reshaped bytes over an object whose recorded hash describes different bytes.
          That is **Task 14's failure, caused here**, which is why the rule is stated in this task
          rather than in that one.
        - **The read reports what was cited.** R2.12 says a reorder must not mint a *version*; it does
          not say a *reader* may perform one. A transformation the hash is blind to is still a change
          to what the reader is told.
        - **Dropping an empty-valued key removes a key the document contains**, and R2.12's
          ordering/duplication table does not cover that case at all.
        An earlier version of this finding argued from information loss and was **refutable by the
        spec**: R2.12 states that nothing in the payload is ordered, one rule with no exceptions, so
        "sorting loses the stated order" and "deduplicating loses duplicate labels" both fall to the
        spec's own terms. Only the empty-key row survived on that footing. Recorded because the
        conclusion was right and the argument was not, which is the failure mode this spec keeps
        catching. **Canonicalization belongs to the write. The read parses, normalizes representation
        only, and never reshapes content.**
    14. **THE ONE ALLOWED NORMALIZATION, and it must cover `id` as well as `tags`.** `jsonlite`
        unboxes on write, so one tag key comes back in three R shapes -- verified: `["a","b"]` parses
        to a list of 2, `"a"` to `character(1)`, and **`["a"]` to a list of 1**. Normalise a
        character-only array to a character vector: same strings, same order, same count, using the
        element test `.datom_sv1_as_strings()` already applies. **Do not touch the presence axis**:
        absence stays `NULL`, never `character(0)` and never `NA`, because inventing either adds
        information the document does not state.
        **`id` values get the same normalization and then a refusal** (owner-decided 2026-09-13): if a
        value is still not a text scalar afterwards, **abort as a malformed document naming the
        member**, and do not go on to compare it. `id` values are spliced into storage keys, so a
        non-conforming one is worse than a non-conforming tag, and `.datom_validate_members()` --
        which requires a text scalar there via `.datom_is_text_scalar()` -- runs on **write only**, so
        the read is where that contract has no enforcement at all. Normalising alone would silently
        accept a document `datom_write_set()` cannot produce; Task 24's project comparison would then
        compare a list against a string, fail to match, and report a member of *this* project as
        belonging to another one. Say at the site that `datom_write_set()` cannot produce the case.
  - **DONE 2026-09-14.** The read is the second half of `R/set.R`; the two edits to shared
    machinery are in `R/read_write.R` beside their siblings, as planned.
    1. **`datom_get_set(conn, name, version = NULL)`**, exported, returning a `datom_set` of
       `name`, `project`, `version`, `data_sha`, `tags`, `members`. Metadata read, kind check,
       version resolve, download-verify-parse, normalize, link -- in that order, and the order of
       the last three is what the task is about.
    2. **`.datom_resolve_version()` gained a `field` argument** and now returns
       `list(data_sha, object_sha, version)`. `object_sha` is the recorded stored-object hash for
       the field asked for -- `parquet_sha` for a table, `document_sha` for a set -- and it is
       **one function with an argument rather than a wrapper per kind**: the wrappers would have
       held a constant string and nothing else, where Task 9's history-scan wrappers each held a
       documented difference. `version` is read from the matched history entry, or from
       `.datom_recorded_current_version()` for an unpinned read.
    3. **`.datom_check_artifact_kind()` gained `operation`**, defaulting to `"write"` so no
       existing message moved. The read wording is `"{name}" is a {found}, not a {expected}.` plus
       the verb that fits, and **both directions carry the one condition class**, so no test can
       key on one of them.
    4. **`.datom_read_set_payload()`** downloads, hashes, then parses -- `document_sha` verified
       before `jsonlite::fromJSON(simplifyVector = FALSE)` ever sees the bytes. A missing or empty
       `document_sha` aborts.
    5. **`.datom_read_string_array()` / `.datom_read_tag_map()` / `.datom_read_set_member()`** are
       the whole of the read's normalization: three R shapes of one JSON string array become a
       character vector, and an `id` value that is still not a text scalar aborts naming the
       member.
    6. **`.datom_member_link()`**, namespace-level with every argument forced, plus
       `print.datom_link()` and `print.datom_set()`.
    7. **`datom_write_set()` accepts a `datom_set`** -- tags carried forward unless supplied,
       links stripped by `.datom_strip_member_links()` and only when callable.
  - **Six things a later change must not undo.**
    1. **The read never tidies.** `.datom_tidy_set_payload()` changes nothing on a healthy payload,
       so reaching for it is green today and shows up later as a repair that re-uploads reshaped
       bytes over an object whose recorded hash describes different bytes. The never-tidy tests
       therefore hand-write payloads that are deliberately uncanonical -- a healthy fixture cannot
       see the difference.
    2. **`.datom_storage_read_json()` must not read the payload.** It parses, so after it there is
       nothing left to hash but bytes re-serialized locally. It returns an identical structure, so
       nothing fails; the integrity check simply stops meaning anything.
    3. **The link factory stays namespace-level, with every argument forced.** Both halves matter,
       and the second is why: with the factory nested inside the read verb, `saveRDS()` of a member
       was verified to write the fixture's token into the file -- but only once `conn` had actually
       been forced, because an unforced promise pointing at the global environment serializes as a
       reference. So the guard is a byte search for a token value, and the frame walk beside it is
       a complement rather than the guard.
    4. **`data_sha` is not recomputed and the payload is not re-validated.** It is the address the
       payload came from, and the sv1 encoder aborts on a top-level payload key a newer datom
       added. A test writes such a key and expects the read to succeed.
    5. **`fetch` is stripped only when it is a function.** A hand-built `fetch = "junk"` must still
       reach `.datom_validate_members()`; stripping by name turns a typo into a silent success.
    6. **`id` is refused, tag values are tolerated.** `id` values are spliced into storage keys and
       compared against project names, and the write-side validator never sees a document read back
       from storage -- so this is the only place that contract is checked. A tag value nothing
       downstream requires to be text is left for whoever uses it.
  - **Eleven probes, each reverted, each naming what it reddened**: tidying the parsed payload
    reddens 6 tests; copying `parquet_sha`'s skip-on-absent guard for `document_sha` reddens 3;
    dropping the hash comparison reddens 2; nesting the link factory reddens 2; normalizing an `id`
    without refusing a non-scalar reddens 4; keeping the write wording on the read-side kind check
    reddens 4; dropping the read-side kind check entirely reddens 2; stripping `fetch` by name
    reddens 1; not accepting a `datom_set` reddens 3; not carrying its tags forward reddens 3;
    recomputing the returned version instead of reading it reddens 1. **Two are thin on purpose and
    worth stating**: stripping by name is caught by exactly the `fetch = "junk"` test, and
    recomputing the version agrees with the recorded value on every healthy document -- only the
    pinned read catches it, because there the recomputed answer describes the current version
    rather than the one asked for.
  - **One process failure worth more than the code note.** A probe harness reverted with
    `git checkout -- R/set.R R/read_write.R`, which restored HEAD and **deleted the whole of this
    task's uncommitted implementation**. It was rewritten from the session transcript and the
    generated `man/` pages and verified identical by line count and by a green suite, so nothing
    was lost -- but the harness now snapshots to a temp directory and restores from that, and the
    rule is in `dev/engineering-notes.md`: a probe reverts from a copy it made itself, never from
    git, because the code under probe is by definition uncommitted.
  - **REVIEWED after it landed; one finding, half accepted and half refused, plus one doc gap
    (tests -> 3557).** The link's factory took a `project` argument, forced it, and used it nowhere --
    while this task's body claimed the link did "kind dispatch, the project check and version
    pinning". The dead argument is gone and the sentence is corrected. The reviewer's fix, moving the
    comparison into the factory, was **refused on evidence**: a reader's `project_name` is a label
    passed to `datom_get_conn()` and nothing validates it against the repo, so a gate would abort a
    working fetch for the very consumer this task is built for -- reproduced with a reader labelled
    `"a-label-nobody-validated"` reading a set written by `set-project`. Two tests pin the no-gate
    behaviour. The reviewer's structural point is kept and moved into Task 24: the hint belongs in the
    shared link core, not in `datom_fetch_member()`, because a projection's leaf is a link and never
    enters that verb. Also fixed, from the same review: `datom_get_set()`'s docs now say that
    `version` can be `NULL` on a truncated history and that `project` is the connection's label rather
    than a recorded fact -- and a Decisions row surfaces the unverified-`project_name` question, which
    wants its own issue.
  - Tests 3418 -> 3553 -> **3557** (+139), FAIL 0 / WARN 0 / SKIP 0; `dev/check-spec.R` 9/9;
    `R CMD check` 0/0/0 on docs, code/documentation agreement and examples (the two new examples
    were run and their output read, not merely built). New `tests/testthat/test-get-set.R`.
    `_pkgdown.yml`'s Sets section gained all three new exports. **Pathway impact: yes** -- a new
    route card, "Given a set + version, resolve its members", plus a correction to the table read
    card, whose `.datom_resolve_version()` return shape it stated.
  - _Requirements: R12.3, R7.1, R7.2, R6.4, R4.3. Invariants: I3, I8, I10. Properties: P9, P16.
    Acceptance: AC1, AC6, AC14, AC15, **AC28**. AC28 is the integrity gate -- both halves: a
    mismatched payload is refused before parsing, **and** a missing/empty `document_sha` is an error
    rather than a skip. The second half is what a naive copy of `.datom_read_parquet()`'s
    `if (!is.null(...) && nzchar(...))` guard gets wrong._
  - _Pathway impact: new route card "Given a set + version, resolve its members"._

---

## Phase D -- Project mode, validation, docs

- [x] **11. Project mode gating the import path** &nbsp; **[DONE 2026-09-18, in three commits -- see the DONE record]**
  - **BLOCKED ON TASK 23, which must land first.** Not a preference: this task is what starts writing
    `mode: product`, and Task 23 is what gives an older build a way to notice. The reading half cannot
    be added to a build that has already shipped, so any release that writes `mode` without a release
    that reads the number leaves a permanent population that treats a product repo as an ordinary
    data repo. Landing Task 23 immediately before this one is what makes "same release" structural
    instead of something to remember at release time. See Task 23 for the reasoning and the scope
    limit.
  - `project.yaml` gains `mode: product` + `set: {name}` (R10.2). One repo = one set = one
    product.
  - **Decide whether this bump moves `project.yaml`'s format number, using R9.5's table rather than
    instinct.** Adding `mode` is an addition, so the default answer is **no bump** -- and the default
    is probably right, because an older build that ignores `mode` gets a silent no-op from
    `datom_sync()` rather than a wrong write. Record the call either way; a bump here costs every
    pinned build its access to the repo.
  - `datom_sync_manifest()` / `datom_sync()` refuse on a product repo with a clear message
    instead of silently no-op'ing.
  - `datom_status()` reports mode.
  - The table write path is **not** gated -- product repos legitimately write derived tables.
  - `datom_init_repo()` gains the means to declare `mode`/`set` at init; the Task 9 gates read it.
  - `mode: product` is also the **identity badge** the build package checks at attach time
    (R10.5) -- the mode carries two meanings, both of which must hold.
  - **New namespace-separation guard** (R17.3, AC22): initializing a `mode: product` repo refuses a
    namespace that already holds another project's manifest, naming the occupying project and
    pointing at using a distinct prefix. Extends the existing `.datom_check_namespace_free()` path
    rather than adding a parallel check. **Justify it in the message and docs on blast radius**
    (prefix-delete and teardown operate on a whole namespace, so a shared prefix means deleting the
    product can delete raw data) -- **not** on access control, which is per-artifact and finer than
    a namespace anyway (R17.4, R19.1).
  - **COLD-START AUDIT, 2026-09-17**, run immediately after Task 23 landed, every claim checked
    against the tree rather than reasoned about. **STARTABLE. Ten findings, TWO that must be decided
    before the first line** (1 and 2) -- both carry stated defaults, so a cold session is not blocked,
    but finding 1 changes a claim three documents already make and finding 2 reopens a decision Task 9
    deliberately left to this task. **No escalation flag is owed**: design.md section 12 carries E1
    (Task 2) and E2 (Task 6) only. **No new export**, so no `_pkgdown.yml` entry and no NAMESPACE step
    -- init gains arguments, two sync verbs gain a refusal, one diagnostic gains a line.

    **What held**, verified rather than assumed. The block is discharged -- Task 23 shipped. The
    "silent no-op" this task exists to replace is real and now pinned to a line: `datom_init_repo()`
    always creates `input_files/`, so on a product repo the directory exists and is empty, and
    `datom_sync_manifest()` answers with an info message and a zero-row frame (`R/sync.R:572-582`) --
    not silence, but an unhelpful answer rather than a refusal. **Neither sync verb has an internal
    caller anywhere in `R/`**, so unlike the write entry -- where a repair verb reached storage without
    passing the door, three times running -- there is no third route to find here. The table write path
    is a genuinely separate function, so "not gated" needs no code and no test beyond one that says so.
    Task 9's gates read `cfg$mode` (`R/set.R:124`) and `cfg$set` (`R/set.R:143`) straight from the
    file and need no change. **Nothing in a machine-written document moves**: no manifest key, no
    metadata field, so no vocabulary-list entry, no format bump for either document, and no
    writer-refusal consequences at all -- unusual for this spec and worth knowing before hunting for
    them. And `status$connection` is not asserted by name in any test, so a field added there is
    additive.

    1. **DECIDE FIRST: the key-set tripwire does NOT fire if `mode` and `set` are written only for a
       product repo -- and that is the likely design.** Task 23 recorded in three places that this task
       fires it immediately. That holds only if `datom_init_repo()` writes the keys on **every** init;
       the tripwire calls it with no mode (`tests/testthat/test-conn.R`, the key-set test) and compares
       against a fixed list, so conditional emission leaves it green. Conditional emission is also the
       established local precedent -- `project` in the two metadata builders is emitted only when
       non-NULL. **DECIDED 2026-09-17: emit conditionally, and add a second tripwire case that inits a
       product repo**, because writing `mode: data` into every config adds a key with no consumer, and
       "absent means not a product repo" is already the semantics the set-write gate implements
       (`R/set.R:124`). Then **correct the three places** that say the tripwire fires immediately, or
       the first cold session reads a promise, sees green, and assumes it broke something. The declared
       number stays `1L` on either branch, so the decision that mattered is untouched.

       **THE RULE GOES IN THE TEST'S COMMENT, NOT JUST THE EXTRA CASE** (review amendment, accepted).
       The blind spot is not about `mode`: the tripwire watches the one creation path it exercises, so
       **any** conditionally written key is invisible the same way, and the next path somebody adds is
       unwatched again while the test still looks like a guard. So the comment states the standard --
       **this test must exercise every path that writes `project.yaml`, and adding such a path means
       adding a case here** -- which is what makes it a tripwire rather than a snapshot of one path.

       **That rule has a second member TODAY, so it is actionable rather than a note for later.**
       `datom_repo_set_data_store()` also writes this file, by read-modify-write, and its test asserts
       only that two fields survive (`tests/testthat/test-repo.R:176`). A refactor to rebuilding the
       document would silently drop `schema_version`, `created_at`, `datom_version`, `sync` and `renv`
       with nothing failing -- which is exactly why Task 20 tested its two read-edit-write surfaces
       even though they needed no code.
    2. **DECIDE FIRST: where `mode` is read from, which Task 9 explicitly left to this task.** That
       task's docs say only `min_writer_version` rides on a `datom_conn`, that `mode` and `set` are
       read at the one site needing them, and that moving them to the connection is "a move with one
       call site to update rather than a decision to reopen". This task is the reopening: it adds two
       consumers (the sync refusal and the status line).

       **DECIDED 2026-09-17, AND THE FIRST-STATED DEFAULT WAS WRONG** -- amended by review, which
       applied this audit's own rule and got a different split. The rule: a check that **authorises a
       write** must see the file as it is *now*, because a hand edit or a pull can replace it after the
       connection was built; a report is fine with the connection's snapshot. Three sites, sorted by
       that test rather than by convenience:

       | Site | Authorises a write? | Reads the mode from |
       |---|---|---|
       | refuse the file-import route on a product repo | **yes** | the file |
       | `datom_status()`'s mode line | no | the connection |
       | the set-write gate (`R/set.R:124`) | yes | the file, already |

       The first-stated default put the import refusal on the connection by grouping it with the status
       line as "not a gate". It **is** a gate -- it is the thing that stops an import from happening, the
       same job the set-write gate does -- so a repo hand-edited to `mode: product` after the connection
       opened would have gone on accepting file imports, which is precisely the window the rule exists
       to close. Cost of the correction: one extra local parse on the import path, which the set-write
       path already pays.

       **State the rule as the TEST a future site applies**, not as three site-by-site facts, so the
       next consumer does not need adjudicating: does this site authorise a write? Then it reads the
       file.

       **ONE CONSEQUENCE NEITHER SIDE OF THAT EXCHANGE STATED, AND IT MUST SHIP WITH THE REFUSAL.** A
       new parse of `project.yaml` is a new **gated** parse: Task 23's rule is that every site parsing
       this file checks its declared format first, so the import refusal carries
       `.datom_check_project_schema(cfg, source = yaml_path, operation = "write")` -- `"write"`, because
       an import is a write. So the shared helper finding 8 calls for is three steps in one place: parse,
       format check, mode check. Miss the middle step and this task quietly reopens the hole Task 23
       closed, on a path that writes.
    3. **`datom_status()` on a reader connection cannot report the mode, and the honest answer is that
       it should not try.** A reader has no clone and never parses `project.yaml` -- every parse site
       is developer-path, verified. The misleading output this task fixes is the input-files
       block (`R/query.R:526`, ending in "Input files: directory empty" at `R/query.R:540`), which
       already sits inside the developer-only branch, so the fix lands where the mode is knowable.
       **Default: report the mode only when there is a clone, and put it in no stored document** --
       reaching readers would mean adding a field to a machine-written file, which is precisely the
       forced-fleet-upgrade cost this task otherwise avoids entirely.
    4. **R17.3's "one remaining hole" is two holes, and the one it does not name is the larger.** The
       namespace check runs under `if (data_backend == "s3" && !isTRUE(.force))` (`R/conn.R:422`).
       `.force` is the hole R17.3 names -- and there is an existing test pinning that bypass
       (`tests/testthat/test-conn.R:2263`), so closing it must be conditional on the mode or that test
       changes. The unnamed one: a **local** backend gets no namespace check at all, while
       `.datom_check_namespace_free()` (`R/utils-validate.R:194`) works through storage dispatch and
       would function unchanged on local -- so AC22 is unsatisfiable for a product repo on a local
       store, which is the backend every set fixture in the suite uses. **Default: widen both
       conditions for product repos only**, leaving ordinary repos byte-for-byte as they are, and
       record the local gap for ordinary repos rather than closing it here.

       **WIDENING TO LOCAL FALSIFIES THE MESSAGE, and nothing would fail if that is missed** -- added
       2026-09-17, stated by neither the audit nor the review. The refusal is hardcoded to one backend
       in words and in format: it opens "S3 namespace is already occupied", advises "a unique S3
       namespace (bucket + prefix)", and builds its location as `paste0("s3://", conn$root, ...)`
       (`R/utils-validate.R:237`). On a local store that prints `s3://` in front of a filesystem path
       and tells the user to change a bucket they do not have. The message has to become
       backend-neutral in the same change, and `.datom_storage_*` already carries the label
       vocabulary `datom_status()` uses for this (`s3` -> "S3", `local` -> "local").

    5. **DONE 2026-09-17 as chunk A, before finding 4 as the ordering requires. AC22's "refused" was
       best-effort, and the wrapper was why.** The check sat inside a `tryCatch` whose handler
       downgraded any error that was not "already occupied" to a message and continued, so a credentials
       or network failure created the repo unchecked. It also re-raised by **matching the message text**
       with `grepl("already occupied", ...)`, the string-matching pattern this spec replaced with
       condition classes everywhere else. What shipped: the occupied abort carries
       `datom_namespace_occupied`; the blanket handler is gone; init wraps only the client construction;
       and `.datom_check_namespace_free()` owns the one tolerated failure itself, returning `NA` for
       "could not reach the store" -- never `TRUE`, which would report an unreadable namespace as
       verified-free. Its refusal is also backend-neutral now, and the backend-label table that was
       written out at four sites is one helper (`.datom_backend_label()`), because a fifth copy is how
       the artifact-kind predicate lost a term.

       **Why before finding 4, and NOT for the reason first offered.** The review's argument was that
       widening the backend condition "puts more traffic through the fragile part", which does not hold:
       the fragility is per-call, so volume does not change it. The real reason is that finding 4's new
       AC22 test is what would encode the fragile path -- write it against a text-matched re-raise and
       the test passes *through* the coupling, so the coupling then has a test defending it. Class
       first, then widen, and the new test dispatches on the class from the start.

       **One over-claim corrected, because it changes how urgent this is.** The review has it that
       rewording the message degrades the refusal to a warning "with nothing failing and nothing to
       notice". **Six** tests grep that exact string, two of them through `datom_init_repo()`
       (`tests/testthat/test-conn.R:1986` and `:2028`), and those two fail on a reword: the abort gets
       swallowed, init proceeds, and `expect_error()` finds no error. So today the coupling is noisy,
       not silent. (This audit first said four, which is the restated-count defect these documents keep
       catching elsewhere; derive it from `grep`, not from memory.)

       **AND THE CLASS ALONE DOES NOT CLOSE THE HAZARD THIS AUDIT CLAIMED FOR IT** -- second review
       amendment, accepted, and it was a defect in the reasoning rather than in the plan. The audit
       justified the class partly by "the silent case is a new abort added inside
       `.datom_check_namespace_free()`, which the handler would swallow". After classing, the handler
       reads `if (inherits(e, "datom_namespace_occupied")) stop(e) else warn()` -- and a new
       **unclassed** abort still falls to the `else` and is still swallowed. The class closes the
       reword fragility and nothing more.
       Closing the swallow needs the catch narrowed the other way: **tolerate only a genuine
       storage-access failure and let everything else propagate.** Both in one change, since it is one
       line either way.

       **How that was implemented, because the obvious spelling is worse.** Testing the error to decide
       whether it was "storage-access" would be message-matching again, one layer along. Instead the
       tolerance moved to **where the storage call is**: `.datom_check_namespace_free()` wraps its own
       `.datom_storage_exists()` call, returns `NA` for "unknown" (never `TRUE`, which would report an
       unreadable namespace as verified-free), and the caller's blanket handler is gone -- init now
       wraps only the client construction, which can fail for credential reasons that say nothing about
       occupancy. Less code than before, and there is no handler left for a later abort to fall into.

       **THE RESIDUAL IS CLOSED, NOT NARROWED -- AND FOR EVERY REPO, NOT JUST PRODUCT ONES.** The
       first pass left "a store that cannot be reached still lets a repo be created unchecked" as a
       deliberate tolerance for an offline developer, with AC22 qualified to "refused *when the namespace
       could be read*". A third review round traced that path end to end and the tolerance does not
       survive it: it **does not defer the check, it drops it.** Store unreachable -> warn, return
       unknown -> init continues and pushes the git repo -> the manifest upload aborts -> and the verb
       that abort points at performs no occupancy check of any kind. Meanwhile init **cannot finish
       without storage** because that upload is part of it, so the tolerance never produced a working
       offline init; its only reachable effect was getting past the check, with a manifest written over
       another project's as the outcome. **So it fails closed**, with `datom_namespace_unverified`, and
       AC22's "refused" is unconditional. **The posture makes this a rule rather than a judgement
       call**: breaking a behaviour loudly is acceptable at this stage, and silently disabling a
       verification check is not acceptable at any stage -- this was the second thing wearing the
       clothes of the first.

       **Two details the trace produced that change the code beyond the policy.** (1) The refusal must
       **not** offer `.force`, which skips this check but not the manifest upload, so it cannot rescue an
       init without storage either -- advice that does not work is worse than none. (2) The manifest
       upload's own recovery hint named `datom_sync_manifest()`, which scans `input_files/` and returns a
       data frame of statuses and **writes nothing to storage**; the verb that mirrors metadata is
       internal and reached through `datom_validate(fix = TRUE)`. Fixed in the same commit and pinned by
       a test, because a recovery instruction that cannot work is how the original tolerance stayed
       plausible for this long.

       **Rejected, with the reason, because it is the obvious fix and it is wrong**: adding the
       namespace check to `datom_sync_manifest()`. That verb is also the ordinary path for your own
       repo, where the namespace is legitimately occupied by you, so it would need a project-name
       comparison rather than an occupancy test -- and a connection's project name is an unvalidated
       label, which is the defect Task 26 spent a whole task on. (A name comparison does exist, in
       `datom_validate()` at `R/validate.R:266`, which is detection after the fact rather than
       prevention.)

       **One test relocated after a probe caught it testing the wrong layer.** A test that the check
       lets other failures propagate was first written against
       `.datom_check_namespace_free()` -- where an abort has always escaped, so it proved nothing. The
       swallowing belonged to the **caller**, so the test belongs with `datom_init_repo()`, and the
       probe confirms it: restoring the blanket handler reddens the two init-level tests and neither of
       the helper-level ones.
    6. **Four exported examples hand-edit `project.yaml` to declare the mode, and they are how users
       will learn this.** `R/set.R:599`, `R/set.R:1441`, `R/set-draft.R:189` and `R/set-members.R:628`
       each write `cfg$mode <- "product"` into a config after init. Once init can declare it, those
       examples teach the superseded route on the very release that provides the supported one.
       **Default: switch all four to the init argument** and confirm they still run under
       `R CMD check` -- they are executed examples, not `dontrun`.
    7. **The two fields need each other, and init is where that gets decided.** `mode: product` with no
       `set:` produces a repo that passes the mode gate and fails the name gate on every set write --
       an inert product repo whose failure surfaces much later. **Default: init refuses
       `mode = "product"` without a set name, refuses a set name without the mode, and validates the
       name through `.datom_validate_name()`** -- the same function the gate calls, so the two cannot
       disagree about what a legal name is.
    8. **`datom_sync()` must refuse on its own, not only through `datom_sync_manifest()`.** It is
       exported and takes a manifest data frame, so a caller can hand it rows that a refusing
       `datom_sync_manifest()` would never have produced. **Default: one shared refusal helper, called
       from both**, which is also what keeps the message identical.
    9. **The refusal goes above the input-file scan, not in the empty branch.** A product repo with a
       file accidentally dropped in `input_files/` would otherwise be imported -- the exact thing R10.1
       forbids -- because the no-op only happens when the directory is empty. So the gate lands above
       the input-directory resolution (`R/sync.R:365`), before anything is listed.
    10. **`input_files/` is still created for a product repo.** Not creating it would change what
        `datom_init_repo()` guarantees about the tree and break an existing test, for a cosmetic gain.
        **Default: keep creating it**, and let `datom_status()` relabel or skip the line rather than
        making init's output depend on the mode.
  - _Requirements: R10 (incl. R10.3a, R10.5), R17. Invariants: I15. Acceptance: AC22.
    **Pathway impact: none** -- no new lookup and no new traversal. The config is already parsed while
    a connection is built, and R10.5's identity badge is checked by the downstream build package, not
    by datom._
  - **DONE 2026-09-18, tests 3841 -> 3900, in three commits** because the guard work had to precede
    the mode work and is a behaviour change of its own: (A) the namespace guard stops swallowing what
    it cannot name, (B) an unverifiable namespace fails closed, (C) the project mode itself. All ten
    audit findings were implemented at their decided values.

    **What shipped.** `datom_init_repo(mode = "product", set = <name>)` records both fields in
    `.datom/project.yaml`; both are refused without the other, and the set name goes through
    `.datom_validate_name()` -- the same validator the set-write gate runs, so the two cannot disagree
    about what a legal name is. `.datom_refuse_import_on_product()` in `R/sync.R` refuses both import
    verbs with `datom_import_on_product`, naming the two verbs that do work there.
    `datom_status()` reports the mode and skips the input-files line. A product repo's namespace is
    checked on **every** backend and `.force` does not skip it.

    **Six things a later change must not undo.**
    1. **`mode` and `set` are emitted only for a product repo.** Absent already means "ordinary data
       repo" to everything that reads this file, so a `mode: standard` line would be a key nothing
       consults. The cost is that the key-set tripwire only sees keys written on every init, which is
       why it has a second case that inits a product repo -- and a third for the store-pointer verb.
    2. **The two fields are added by assignment, after the `list()`, not inside it.** In a constructor
       a NULL is a present element and yaml writes it as `mode: ~`, a declared empty value rather than
       an absent key. **The `if` is not what protects this and the code comment says so** -- probing
       removed the `if` and reddened nothing, because `$<-` with NULL removes; moving the two fields
       into the constructor reddens two tests. The placement is load-bearing, the guard is not.
    3. **The import refusal reads the file; only `datom_status()` reads the mode off the connection.**
       A check that authorises a write must see the config as it is now, since a hand edit or a pull
       can replace it after the connection was built. The test asserts the refusal fires on a
       connection whose own `mode` is NULL, which is what makes it meaningful.
    4. **That refusal carries the config format check**, because parsing this file makes it a new
       *gated* parse. Without it a build that cannot interpret the file would still read `mode` out of
       it and decide on a field it may have misread -- reopening Task 23's hole on a path that writes.
       Removing the one line reddens exactly the test written for it.
    5. **Both import verbs refuse independently, and above the input-file scan.** `datom_sync()` takes
       a data frame, so a caller can hand it rows a refusing scan never produced (dropping its call
       reddens one test); and the refusal sits above the directory resolution, because a file left in
       `input_files/` by accident would otherwise be imported -- the unhelpful no-op only happened when
       the directory was empty (moving it below reddens four).
    6. **The namespace widening is scoped to product repos, both halves.** Ordinary repos keep the
       s3-only scope and the `.force` override. The local gap for an **ordinary** repo is recorded, not
       closed: closing it changes behaviour for every local repo and is its own decision.
    7. **A refusal must not advise an override the caller does not honour.** Added by the review that
       followed (below). `overridable =` is the caller's policy to declare, exactly as the backend label
       is, and `.force` with `mode = "product"` is an **error** rather than a dropped argument.

    **Seven probes**, each reverting one defect: unconditional `mode` in the constructor reddens 2, a
    missing format check 1, reading the conn instead of the file 5, `datom_sync` without its own
    refusal 1, no refusal above the scan 4, an unwidened namespace check 1, and a product status that
    still scans input files 1. **One probe reddened nothing and that is the useful one** -- see item 2.

    **REVIEWED after it landed; one finding, ACCEPTED and fixed (tests 3900 -> 3909). The occupancy
    refusal sent a product-repo user in a circle, and it is the same defect this function was fixed for
    one commit earlier.** The refusal's last line read "pass `.force = TRUE` to override" whatever the
    caller's policy was -- while a product repo's check consults `.force` at all, so the message routed
    exactly those users into a flag that changes nothing there. The backend-neutrality fix had already
    established the principle and stopped one line short of it: **this function cannot know its caller's
    policy any more than it knew the backend**, so both are arguments now. Two fixes, and the probes
    confirm each is needed without the other -- dropping the argument check reddens 2 tests, making the
    bullet static again reddens 1.
    (a) `.force = TRUE` with `mode = "product"` **aborts at the argument check**, beside the mode/set
    co-validation, rather than being silently dropped. Same rule as refusing a version supplied beside a
    member record that carries one: ignoring an argument reports success for an action nobody asked for,
    and here the caller would have gone on believing an override exists. (b) The override bullet is
    conditional on `overridable =`, and the product wording **says why** there is none rather than
    merely omitting the route -- a bare "use a different prefix" leaves the user looking for the flag.
    `.force`'s own docs now name both exceptions, the unreachable store and the product repo.

    **Also done here**: the four exported examples that hand-edited `project.yaml` to declare the mode
    now use the init argument and were run with their output read; the stale claim that nothing writes
    these fields is corrected in `R/set.R` and in the fixture helper; and the namespace check now builds
    its probe connection through `.datom_build_init_conn()` rather than an inline S3 client, which is
    what makes the local-backend widening work at all.

- [x] **12. Foreign-content discipline + `datom_repo_commit()`** &nbsp; **[DONE 2026-09-18, in two commits -- see the DONE record]**
  - **Elevate machine-commit isolation from accident to guarantee** (R14.1, I16). Already true by
    implementation -- `.datom_git_commit()` takes an explicit file list (`R/utils-git.R:182`) --
    so this is primarily a **test** so a future add-all refactor fails CI rather than an audit:
    dirty `R/foo.R` + `datom_write()` of a table, assert the commit tree excludes it **and** it is
    still dirty afterward (AC16). Both halves -- the second catches a helpfully-cleaned tree.
  - **Assert tolerance of non-datom paths** (R14.2). This already holds by construction --
    `.datom_validate_tables()` filters on the presence of `metadata.json`, so `dp/` is skipped for
    that reason, not because of the hardcoded exclusion list (design.md section 19.7). So again:
    tests, not new code. `datom_status()` may *report* foreign dirty files as git state; it must
    not classify them as a datom defect, and `datom_validate()` must not surface them at all.
  - **New exports: `datom_repo_commit(conn, message, paths = NULL, push = TRUE)` and
    `datom_repo_push(conn)`** (R15) -- the sanctioned git-mutation surface, so downstream packages
    never import `git2r` (I17). **Both verbs are required**: `push = FALSE` without a standalone
    push verb means "push what I already committed" is only expressible as another commit attempt,
    and in a product repo `paths = NULL` is add-all -- so a push-only caller would risk committing
    human WIP (design.md section 19.8, I20).
  - **Commit is idempotent, push is convergent, neither implies the other.** R15.5's no-op means no
    *commit*; with `push = TRUE` and the branch ahead, the push still runs -- otherwise one failed
    push leaves the remote silently behind forever, since every later call finds a clean tree and
    returns early. The ahead count needs no new machinery: `.datom_check_git_current()` already
    calls `git2r::ahead_behind()` and reads `[[2]]` (behind); `[[1]]` is ahead (R15.9).
  - **Mind the two delta corrections** (design.md section 19.6), both of which change the
    implementation:
    - `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It
      aborts on an **empty `files` argument** and on **nonexistent files**. So `paths = NULL`
      cannot delegate with `files = character(0)`, and the wrapper must determine "nothing to do"
      itself (status check, or HEAD before/after) to honor R15.5's `invisible(NULL)` no-op.
    - The on-a-branch guard lives in `.datom_git_branch()` and is only reached via
      `.datom_git_push()`, so it does **not** fire when `push = FALSE`. Assert it explicitly up
      front (R15.7).
  - Roxygen: document that `paths = NULL` means what `git add .` means, including that it may
    sweep in dirty datom files left by a previously failed write -- intentional, and
    `datom_validate(fix = TRUE)` is the repair path (design.md section 19.7).
  - Tests: gitignore-respecting add-all; explicit `paths` stages exactly those; reader conn
    refused; empty staging creates no commit and is not an error; `push = FALSE` leaves the remote
    untouched; **clean tree + `push = TRUE` + branch ahead advances the remote with no new commit**
    (AC17). For `datom_repo_push()`: advances the remote, second call is a no-op, reader conn
    refused, on-a-branch guard inherited (AC21).
  - _Requirements: R14, R15 (incl. R15.8/R15.9). Invariants: I16, I17, I20. Properties: P19, P22,
    P23, P24. Acceptance: AC16, AC17, AC21. No pathway impact._
  - **COLD-START AUDIT, 2026-09-18**, run after Task 11 landed, every claim checked against the tree and
    the two git-behaviour questions settled by **running git2r** rather than reasoning about it.
    **STARTABLE. Ten findings, ONE that must be decided before the first line** (finding 9) -- it carries
    a stated default. **No escalation flag is owed**: design.md section 12 carries E1 (Task 2) and E2
    (Task 6) only. **Two new exports, so NAMESPACE and `_pkgdown.yml` both need an entry** -- the body
    does not say so, and the natural home is the section that already holds
    `datom_repo_set_data_store()` and `datom_repo_attach_governance()` (`_pkgdown.yml:112-113`), not a
    new section.

    **What held**, verified rather than assumed. All three delta corrections are exactly right:
    `.datom_git_commit()` aborts on an empty `files` vector (`R/utils-git.R:185`) and on nonexistent
    files (`R/utils-git.R:200`), and **returns HEAD's SHA** rather than aborting when nothing ends up
    staged (`R/utils-git.R:226`). The on-a-branch guard really is inside `.datom_git_branch()`
    (`R/utils-git.R:158`) and is reached from `.datom_git_push()` (`R/utils-git.R:265`), so `push =
    FALSE` would never touch it. `.datom_check_git_current()` really does call `git2r::ahead_behind()`
    and read `[[2]]` (`R/utils-git.R:486`), so the ahead count needs no new machinery. Neither export
    exists yet, and nothing in the package passes `staged_deletions = TRUE` today. `datom_status()` does
    report foreign dirty files as git state and never as a datom defect, because the git block is built
    from `git2r::status()` and sits beside `status$tables` rather than inside it. AC16's fixture is
    **newly constructible through the public path**, thanks to Task 11's `mode = "product"` argument;
    before that it needed a hand-edited config.

    1. **THE THREE DELTA CORRECTIONS ARE ALREADY TESTED, so that part of this task is reading, not
       writing.** `tests/testthat/test-utils-git.R:332` covers the empty-`files` abort, `:337` the
       nonexistent-file abort, and `:345` the "returns HEAD SHA when files are unchanged" branch. The
       body reads as though each needs establishing. They need **citing** in the wrapper's comments
       instead, so the next reader does not re-derive them.
    2. **AC16'S TEST MUST ASSERT ON THE REAL COMMIT TREE, AND THE OBVIOUS SPELLING DOES NOT.** There is
       already a test that captures `.datom_git_commit()`'s `files` argument through a mock and asserts
       `.datom/manifest.json` **is in** it (`tests/testthat/test-read-write.R:1654`). Extending that one
       with an exclusion assertion is the cheap move and it defends nothing: the mock replaces the very
       function whose file list is the guarantee, so the test would stay green through exactly the
       add-all refactor R14.1 exists to catch. AC16 says "a commit whose tree does not contain the
       change", and that is the layer the test has to work at -- a real git repo, a real
       `datom_write()`, and `git2r` reading the commit's tree. The second half is a working-tree
       assertion (`R/foo.R` still dirty), which no mock can fake either.
    3. **R14.2's "holds by construction" is TWO mechanisms on TWO surfaces, and one test covers one of
       them.** Table discovery filters on the presence of `metadata.json`
       (`R/validate.R:391`), so a foreign directory is skipped there. But the repo-level half never
       enumerates the repo at all: `.datom_validate_repo_files()` walks an explicit list of files it
       expects (`R/validate.R:286`), so a foreign path is structurally invisible to it. Two different
       reasons, two tests, and neither implies the other -- a refactor of the repo-level check into a
       directory walk would satisfy the discovery test and break R14.2.
    4. **THE FOREIGN-PATH FIXTURE MUST NOT BE A NAME ON THE HARDCODED EXCLUSION LIST, or the test passes
       through the mechanism the requirement does not rely on.** `.datom_validate_tables()` drops
       dot-directories and then seven hardcoded names -- `input_files`, `renv`, `man`, `R`, `tests`,
       `vignettes`, `src` (`R/validate.R:388`) -- **before** the `metadata.json` filter runs. So a test
       asserting "`R/` is ignored" is satisfied by the list and would stay green if the filter were
       deleted. `dp/` is not on that list, which is exactly why design 19.7 chose it. **Probe the test
       rather than trusting it**: deleting the `metadata.json` filter must redden it, and deleting the
       hardcoded list must not.
    5. **`paths = NULL` CAN delegate to `.datom_git_commit()`, and the body implies it cannot.** Verified
       by running: `fs::file_exists(".")` is `TRUE`, so `files = "."` passes the existence guard, and
       `git2r::add(repo, ".")` with default flags **respects `.gitignore`** and **stages deletions**.
       That is precisely AC17's `paths = NULL` semantics, from the helper, with no new staging code. The
       body's true claim is narrower than its wording: delegation with `files = character(0)` is
       impossible, which is not the same as delegation being impossible.
    6. **THE WRONG DELEGATION IS `staged_deletions = TRUE`, IT SILENTLY VIOLATES AC17, AND IT IS THE
       TEMPTING ONE.** That flag exists to skip the existence check, which is what a naive add-all
       author reaches for -- and it sets `git2r::add(force = TRUE)` (`R/utils-git.R:211`), which
       **stages gitignored files**. Verified by running: with `force = TRUE` an ignored file appears in
       the staged set; with default flags it does not appear at all. It is also unnecessary, since
       default flags already stage deletions. AC17's "minus gitignored files" clause is the test that
       catches this, so write that clause as a test with a real `.gitignore` rather than as prose.
    7. **R15.5's `invisible(NULL)` still needs the wrapper's own nothing-to-do detection, even under
       that delegation.** The helper's empty-staging branch returns **HEAD's SHA**, which is a success
       value, so a wrapper that just returns what the helper returned can never emit the no-op R15.5
       requires. Default: capture HEAD before, compare after, and treat "unchanged" as the no-op --
       cheaper and more robust than parsing a status object, and it also gets the R15.5 qualification
       right, since the push decision is made separately from the commit outcome.
    8. **THERE IS A FIFTH COMMIT SITE AND IT BYPASSES THE HELPER ENTIRELY.** Four sites go through
       `.datom_git_commit()` -- `.datom_commit_and_mirror()` (`R/read_write.R:982`, shared by the table
       write and the set write), both `repo.R` verbs (`R/repo.R:136`, `R/repo.R:416`) and the metadata
       sync (`R/utils-sha.R:650`). `datom_init_repo()` stages four named files with a direct
       `git2r::add()` (`R/conn.R:704`) and commits without the helper. The guarantee holds there (the
       list is explicit, and a brand-new repo has nothing foreign to sweep), but I16 is worded about
       "a datom machine-moment commit" without qualification, so say in the test or the invariant which
       sites the AC16 test actually covers rather than implying all of them.
    9. **DECIDED 2026-09-18: `datom_repo_commit()` does NOT run the staleness gate, and it asserts the
       branch guard explicitly.** The reason the default was right: a commit is local and a push is
       shared, so gating the local verb makes saving your own work depend on somebody else's push or on
       being online, and `.datom_git_push()` already pulls before pushing
       (`R/utils-git.R:257`).

       **AND THE REDUNDANCY WORRY THIS AUDIT RAISED IS FALSE -- corrected by review, checked line by
       line.** The audit said calling the gate "would satisfy the on-a-branch guard transitively", which
       overstates it badly. `.datom_check_git_current()` reaches `.datom_git_branch()` only after **four**
       early returns: no remote, the fetch failed, no upstream, and local SHA identical to upstream
       (`R/utils-git.R:434`, `:460`, `:468`, `:474`, with the branch call at `:478`). So the transitive
       guarantee fires **only when you are out of sync with the remote**. A detached HEAD while
       up to date -- the ordinary shape of this mistake -- sails straight through. **The explicit assert
       is therefore not duplication; it is the only one that runs in the common case**, and this
       correction belongs in R15.7's note naming the identical-SHA return, because the risk is not
       failing to add the guard but somebody deleting it in a year for looking redundant.

       **Why a cheap guard is worth it at low frequency, which is the part that justifies the line of
       code**: a commit onto a detached HEAD succeeds, prints a SHA, and becomes unreachable the moment
       you switch branches -- and with `push = FALSE` there is no later push failure to reveal it.
       Silent plus unrecoverable is the combination that earns a guard regardless of rate. Detached
       checkouts are also routine in CI rather than exotic; the frequency claim stops there, because the
       exact trigger-by-trigger behaviour depends on how the checkout step is configured and is not
       something this audit verified.
    10. **`datom_repo_push()` needs one behaviour the body does not name: what it does when there is no
        remote at all.** `.datom_git_push()` reads `git2r::remotes(repo)[[1L]]`
        (`R/utils-git.R:264`), which subscripts an empty list on a repo with no remote and fails with
        R's own out-of-bounds error rather than anything a user can act on. A data repo is required to
        have a remote, so this is an edge rather than a scenario -- but a standalone push verb is the
        first thing a user points at a half-configured repo. Default: check for a remote up front and
        refuse with the recourse, in the new verb rather than in the shared helper, so no existing
        caller's behaviour changes.

  - **DONE 2026-09-18, in two commits**, split because the two halves are different logical
    changes: chunk A elevated two existing guarantees to tested ones with **no `R/` change at all**
    (new `tests/testthat/test-foreign-content.R`, 5 tests, 3909 -> 3926), chunk B added the two
    exports (`R/repo.R`, 3926 -> **3974**). Docs: NAMESPACE, five `man/` pages, `_pkgdown.yml` under
    the existing **Storage Extension API** section beside `datom_repo_set_data_store()`, and a NEWS
    section. Both new examples run with their output read. `dev/check-spec.R` 9/9.

    **Eight things a later change must not undo.**
    1. **The AC16 test reads the real commit tree, and must not be consolidated with the mocked
       one.** `test-read-write.R`'s "datom_write commits manifest.json" mocks `.datom_git_commit()`
       and inspects the file list it captured; the new test uses real git and reads the commit's
       tree with `ls_tree()` + `lookup()` + `content()`. Merging them back into one mocked test
       would leave the suite green through the add-all refactor R14.1 exists to catch, because the
       mock replaces the function whose file list *is* the guarantee.
    2. **Asserted as bytes, not as presence.** `R/foo.R` is committed in the fixture and then
       edited, so the path is in the tree either way -- the claim is that the tree still holds
       `"original"`. A `%in%` check on tree paths passes whatever the write staged.
    3. **The foreign directory is `dp/`, never `R/` or `renv/`.** `.datom_validate_tables()` drops
       seven hardcoded names **before** the `metadata.json` filter runs, so a test named after one
       of them is satisfied by the list and would survive deletion of the filter.
    4. **R14.2's repo-level test asserts the whole expected set** (`expect_setequal(..., "manifest
       .json")`), not the absence of the two foreign files it plants. The mechanism there is that
       `.datom_validate_repo_files()` walks an explicit list and never enumerates the repo; a
       refactor into a directory walk is exactly what must fail, and it surfaces every foreign file
       at once.
    5. **`paths = NULL` delegates to `.datom_git_commit()` with `files = "."`, and must never use
       `staged_deletions = TRUE`.** That flag exists to skip the existence check -- which is what an
       author reaches for to make deletions work -- and it sets `git2r::add(force = TRUE)`, which
       stages gitignored files. Default flags already stage deletions, so the flag buys nothing and
       silently breaks AC17's "minus gitignored files" clause.
    6. **Nothing-to-do is detected by HEAD before/after, never from the helper's return value.**
       `.datom_git_commit()` returns HEAD's SHA when nothing ends up staged, which is a success
       value, so a wrapper that passed it through could not emit R15.5's `invisible(NULL)`.
    7. **The no-op must not return before the push decision.** No-op means no *commit*; with
       `push = TRUE` and the branch ahead, the push still runs. Returning early there is the silent
       failure R15.5's qualification exists for: one failed push and every later call finds a clean
       tree and returns, leaving the remote behind for good.
    8. **These verbs call no forward-compatibility write gate, deliberately.** Every other write
       verb in this spec had to call `.datom_check_write_entry()`; this one writes none of datom's
       documents -- it commits whatever the caller named -- so gating it would refuse a commit of
       somebody's code because of a manifest's shape. The dirty-datom-file sweep-in that `paths =
       NULL` allows is a **local** write by this same build, which already passed the gate.

    **One deviation from what R15.8 implies, found by probe rather than by reading, and the code
    changed because of it.** The explicit on-a-branch assert is in `datom_repo_commit()` only.
    Adding one to `datom_repo_push()` reddened **nothing**: the nothing-to-push early return needs
    an ahead count, the count needs an upstream tracking ref, and a detached HEAD has none -- so
    that verb always reaches `.datom_git_push()`, which carries the guard. So the push verb
    inherits it (which is what R15.8 says), the commit verb asserts it (which is what R15.7 says,
    and the probe confirms: removing it reddens 2 assertions), and the asymmetry is now stated at
    both sites and in the test name rather than looking like an oversight.

    **Seven probes, each run rather than argued.**

    | Broken on purpose | Reddened |
    |---|---|
    | `git_files <- "."` in `.datom_commit_and_mirror()` (the add-all refactor) | 4 assertions, both AC16 tests |
    | the `metadata.json` filter in `.datom_validate_tables()` deleted | 3 assertions, including the `dp/` test |
    | the seven hardcoded directory names deleted | **nothing** -- the test rests on the filter, which is what R14.2 relies on |
    | `staged_deletions = TRUE` on the delegation | exactly 1: the gitignored-file assertion. Deletions still worked, which is the evidence that default flags stage them |
    | `created <- TRUE` (no before/after detection) | 4 assertions across 3 tests |
    | `return(invisible(NULL))` before the push block | 3 assertions, including the R15.5 qualification test |
    | the explicit branch guard removed from the commit verb / from the push verb | 2 / **0** -- see the deviation above |

    **Two smaller things worth carrying.** git2r reports an untracked **directory** rather than
    recursing into it, so the entry to assert is `"dp/"`, and that is true of `git2r::status()` and
    of what `datom_status()` passes through from it. And `cli` refuses a `{}` expression that starts
    with a dot, so `{.datom_git_branch(...)}` inline in a message is an error -- bind it first.

    **Audit finding 1 needed no test work**, as it said: the three delta corrections are already
    covered at `test-utils-git.R:332`, `:337` and `:345`. They are cited in the wrapper's comments
    so the next reader does not re-derive them.

    **One residual, named rather than left implicit, and it belongs to Task 16's sweep**: nothing
    tests the interaction design 19.7 accepts, where `paths = NULL` sweeps in datom files left dirty
    by a previously failed write. It is documented in the roxygen and is a *tolerated* behaviour
    rather than a requirement with a criterion, and the fixture for it is a half-failed write.
    **Task 16 states it from its own end**, so the deferral does not depend on anyone reading this
    record.

    **REVIEWED after it landed (2026-09-18): NO FINDINGS, and nothing is owed.** Recorded because
    every other task in this spec records its review outcome, so an absent line reads as a review
    not yet done rather than one that found nothing. Three things the review checked independently
    rather than taking on trust, all holding. The removed assert's chain was re-derived end to end
    (`NA` ahead count -> the early return is unreachable on a detached HEAD -> the push helper's
    guard is what fires), so the asymmetry between the two verbs is confirmed rather than merely
    explained. The two tests behind that probe (`tests/testthat/test-repo.R:1001`, `:1023`) were
    confirmed to be **real coverage rather than an absence**, which is the thing a probe that
    reddens nothing usually fails to establish. And the pull-that-precedes-the-push was traced on a
    detached HEAD: the merge is gated on a non-NULL upstream, so that repo gets a fetch and **no
    working-tree change** before the guard aborts. The Task 16 deferral above was agreed in the same
    round, on the grounds that the contract is stated in `datom_repo_commit()`'s own help with
    `datom_validate(fix = TRUE)` named, which is where a caller meets it.

- [x] **13. `datom_write_set(include_paths = )` -- the joint commit** &nbsp; **[DONE 2026-09-18 -- see the DONE record]**
  - Follow-on to Task 9 rather than folded into it: Task 9 is already large (two gates, dual-write,
    dedup, name uniqueness, manifest), and the dedup edge below deserves its own commit.
  - `include_paths`: repo-relative paths staged **into the same commit** as the payload and
    metadata, so the joint version is **structural, not recorded** (R12.5). Ordering unchanged:
    local writes -> one commit -> push -> storage mirror.
  - **Storage mirror stays datom-artifacts-only** -- `include_paths` content is never mirrored
    (I18, AC18).
  - **Validation before any hashing or IO** (matching R10.3a placement): a nonexistent path is an
    **error**, not a skip; a path overlapping `{artifact}/**` or `.datom/**` is **refused**
    (AC20). **Two separate test cases**, not one bundled assertion, so a regression identifies
    which gate broke.
  - **The sharp edge**: an unchanged set stays a **no-op even when `include_paths` files are
    dirty** -- no commit, no version, informational message pointing at `datom_repo_commit()`
    (R12.5, I19, AC19). AC2's idempotency must not acquire a side channel that commits code; that
    would be the machine-moment add-all failure arriving through a different door.
  - Update P17's claim in the docs: with `include_paths`, checkout of a set version's commit
    yields code + environment + data pointers, not pointers alone.
  - _Requirements: R12.5. Invariants: I18, I19. Properties: P17 (strengthened), P20, P21.
    Acceptance: AC18, AC19, AC20._
  - **SCOPED PRE-START AUDIT, 2026-09-18**, run after Task 12 landed and deliberately narrow: the
    reviewer scoped it to the one claim in this task that nothing pins, **I19** -- an idempotent set
    re-write stays a no-op even when `include_paths` files are dirty -- on the grounds that a hazard
    claim whose stake is already named in the Decisions log ("the add-all failure through a different
    door") needs a test that can fail rather than another reading. **STARTABLE, nothing open**: its
    one scope question was decided by the owner the same day (below). **No escalation flag is owed**:
    design.md section 12 carries E1 (Task 2) and E2 (Task 6) only. **No new export**, so unlike the
    last five tasks there is no NAMESPACE or `_pkgdown.yml` step -- `datom_write_set()`'s Rd
    regenerates and NEWS gains an entry.

    **I19 HOLDS TODAY, AND THE REASON IS PLACEMENT RATHER THAN A CHECK.** The no-change branch is at
    `R/set.R:978` and returns above everything that could stage a file: the payload write, the
    metadata document, the manifest row, and the single `.datom_commit_and_mirror()` call. So the
    obvious implementation of this task -- validate the paths up front, hand them to that same commit
    call -- keeps the guarantee for free. This is Task 12's shape exactly: true because of where one
    line sits, and **nothing in the suite fails if that line moves.**

    1. **THE EXISTING NO-OP COVERAGE IS THE SPELLING THAT CANNOT FAIL, so AC19 must not extend it.**
       `tests/testthat/test-write-set.R:675` and `:807` assert `action == "none"` on the returned
       list. That is a claim about the value handed back, not about git. The hazard I19 names is a
       write that commits the dirty code **and still reports no change** -- and both assertions stay
       green through precisely that. AC19's test reads git: capture HEAD before the second write and
       assert it is unchanged after.
    2. **THE FIXTURE NEEDS A DIRTY-BEFORE AND A DIRTY-AFTER ASSERTION, or the test passes
       vacuously.** If the edit lands somewhere the `include_paths` argument does not name, the test
       asserts that nothing moved in a repo where nothing changed -- green forever, proving nothing.
       Same class as the two tests the Task 6 purity audit found passing whatever the code did.
    3. **AC19's message can be matched on the verb's name now that Task 12 shipped it.** The
       informational message must point at `datom_repo_commit()`, which exists, so the assertion
       names the function rather than a phrase that a reword would break.
    4. **DECIDED 2026-09-18 (owner): a path the caller lists that happens to be gitignored is
       REFUSED, not silently dropped.** Verified by running git2r rather than reasoning:
       `git2r::add(repo, <gitignored path>)` with default flags raises no error and stages nothing,
       and `.datom_git_commit()` cannot notice because it only objects when **nothing at all** is
       staged -- datom's own files always are. So the commit succeeds and the set version claims a
       joint commit that omits the file the caller asked for, which is AC18's guarantee failing
       quietly. It is Task 12's finding 6 in mirror image: there the danger was a flag that stages
       ignored files, here it is the default that skips them. One refusal, one test, in this task.
    5. **`include_paths` are repo-relative by contract and must be absolutised before the commit
       call.** `.datom_commit_and_mirror()` relativises what it is given against `conn$path`
       (`R/read_write.R:978`), and `fs::path_rel()` with a relative first argument resolves it
       against the working directory -- `fs::path_rel("dp/build.R", "/tmp/repo")` is
       `"../../private/tmp/dp/build.R"`. Passing them through raw aborts with "files do not exist",
       so this is loud and costs minutes rather than correctness; it is recorded to save the minutes.
    6. **One consequence of the gate placement, stated so nobody later "fixes" it into tolerance**:
       validation runs before any hashing, and the change detection needs the hashes, so a
       nonexistent or overlapping path is an **error even when the set is unchanged**. The refusal
       wins over the no-op. That is the correct reading of AC20 plus AC19 together -- a joint commit
       is deterministic or it is refused -- and it means the AC20 cases do not need a changed payload
       to reach the gate.

  - **DONE 2026-09-18, in one commit.** `R/set.R` gains the argument, one gate
    (`.datom_check_include_paths()`) and one git reader (`.datom_git_ignored()`); the commit call
    grows one element in its file list. 11 new tests in `tests/testthat/test-write-set.R`
    (3974 -> **4012**), FAIL 0 / WARN 0 / SKIP 0. Docs: `datom_write_set()`'s Rd plus two internal
    ones, a NEWS section, and the set-write route card in `dev/datom_pathways.md` -- **pathway impact
    is real**, since the card's step list gained a gate and its commit step now says what else is in
    the commit. No export, so no NAMESPACE or `_pkgdown.yml` step. `dev/check-spec.R` 9/9;
    `R CMD check` 0/0/0 with examples run.

    **Six things a later change must not undo.**
    1. **The no-change return sits above every line that stages a file, and that placement is the
       whole of I19.** Payload write, metadata document, manifest row and the single
       `.datom_commit_and_mirror()` call are all below it. Nothing checks the ordering, so the
       comment at the return says both halves out loud: do not move the return down, and do not add
       a staging step above it.
    2. **AC19's test reads git HEAD, and must not be "simplified" into an assertion on the returned
       value.** Probe P1 -- commit the listed paths on the no-op path -- reddens the HEAD assertion,
       the dirty-after assertion and the file-content assertion, and leaves `action == "none"`
       **green**. That is the shape the audit predicted: the two pre-existing no-op tests
       (`:675`, `:807` at the time) cannot fail on this hazard, so AC19 got its own test rather than
       an extra line in theirs.
    3. **The same test asserts the foreign file is dirty BEFORE and AFTER.** Probe P2 -- drop the
       edit -- reddens the before assertion, so the test cannot pass by finding nothing moved in a
       repo where nothing happened.
    4. **Validation runs above the first hash, so a bad path is an error even when the set is
       unchanged.** The refusal wins over the no-op, and that is AC20 plus AC19 read together: a
       joint commit is deterministic or it is refused. There is a test saying so; do not soften it
       into "skip the check when nothing changed", which would make the answer depend on content the
       caller cannot see.
    5. **The gitignore refusal is the only thing between a listed path and a silent omission.**
       `git2r::add()` on an ignored path raises nothing and stages nothing, and
       `.datom_git_commit()` objects only when the staging area ends up empty -- datom's own files
       are always in it. Matching is **prefix-based on a slash-stripped list**, because git reports
       an ignored *directory* (`cache/`) and never recurses into it, so equality matching would miss
       every file inside one.
    6. **Paths are normalised before the owned check and absolutised before the commit call.**
       Normalised, or `./.datom/manifest.json` walks past a gate that `.datom/manifest.json` fails
       (probe P6 reddens exactly that test). Absolutised, because
       `.datom_commit_and_mirror()` relativises against `conn$path` and `fs::path_rel()` on an
       already-relative path resolves it against the working directory -- loud rather than
       dangerous, but it costs a debugging session. Escape is judged **after** normalising, so
       `a/../b` is `b` and allowed while `../x` and `/etc/passwd` are refused: the gate is about
       leaving the clone, not about spelling.

    **Nine probes, each reverted.** Every one reddened only its intended test, which is also how the
    attribution below was established rather than assumed.

    | Probe | What was broken | What reddened |
    |---|---|---|
    | P1 | commit the listed paths on the no-op path | AC19's HEAD, dirty-after and content assertions -- **not** `action == "none"` |
    | P2 | never make the edit the test describes | AC19's dirty-before assertion (plus the two after it) |
    | P3 | delete the gitignore refusal | the gitignore test |
    | P4 | delete the datom-owned refusal | the owned test (3 cases) and the dot-prefixed test |
    | P5 | delete the nonexistent-path refusal | AC20a, including its "nothing left behind" half, and the refused-even-when-unchanged test |
    | P6 | stop normalising the caller's paths | the dot-prefixed test |
    | P7 | delete the outside-the-clone refusal | the outside test (an absolute path became a missing-path error) |
    | P8 | leak a foreign object into the storage namespace | both I18 assertions |
    | P9 | commit the listed paths separately, before the write's own commit | AC18's "exactly one commit" assertion |

    **Two residuals, both stated rather than fixed.**
    * **An explicit path handed to `datom_repo_commit()` is still dropped in silence when
      `.gitignore` excludes it.** The refusal built here is on the set write only. That asymmetry is
      deliberate for now -- Task 12's contract for that verb is "stage exactly those paths", and it
      has no version claiming to contain them -- but the mechanism is now one function
      (`.datom_git_ignored()`) away if the sweep decides the human-moment verb should refuse too.
    * **A path that is both tracked and matched by `.gitignore` is not refused**, because git does
      not report a tracked file as ignored and stages it regardless of the rules. Correct rather
      than tolerated: the file really does reach the commit.

- [x] **14. `datom_validate()` branches on `kind`** &nbsp; **[DONE 2026-09-18]**
  - `.datom_validate_one_table()` built the payload key with the kind
    **hardcoded** to `"table"`: `.datom_artifact_payload_key(name, meta$data_sha, "table")`, which
    resolves to `.parquet` and so fails 100% of the time on a set. (Task 1 replaced the original
    `paste0()` here, and the helper already accepts `kind = "set"` -- so this is a call-site change,
    not new key logic. Earlier drafts of this task described the `paste0()` form.) The branch now
    sits at `R/validate.R:501-505`; it was `R/validate.R:444` when the defect was recorded.
  - **table**: existing parquet check, unchanged. **set**: payload exists at
    `{name}/{data_sha}.json` **and** every member resolves *as far as the connections allow* --
    same-project members fully checked, cross-project members checked as well-formed pointers
    unless the caller supplies that project's conn (R11.2). datom does no name-to-location lookup
    of its own (R18.1), so a validator claiming to fully check cross-project members would either
    be lying or silently requiring governance.
  - New status code `members_unresolvable`, distinguishable from a missing payload (P14).
  - **Member checking is one level deep** (R4.3, I10): each member pointer resolves to an existing
    artifact. The validator does not descend into nested sets -- validating an inner set is a
    separate `datom_validate()` call against that set's own project.
  - Scope note: R11.2 specifies a **storage-side** check (payload exists, members resolve). An
    earlier draft here promised a git-vs-storage comparison "which R6.1b's git retention makes
    possible" -- **removed**, because R6.1b reversed per-version payload files in git: git now holds
    one mutable `{name}/set.json`, so only the *current* version is comparable without `git show`.
    Do not add unrequested git-side comparison.
  - **`fix = TRUE` must not break `document_sha`** (R7.5 rule 2, I27, AC29c). Repair re-uploads from
    the clone, so it is a live path to overwriting a stored payload. It must **reuse the recorded
    `document_sha` and never recompute it** for an existing version. Same trap shape as the
    `commit_sha` one (R21.7, I22): a repair path silently undoing a write-path guarantee. AC29c is
    the clause a naive implementation fails while passing everything else.
  - _Requirements: R11, R4.3, R7.5. Invariants: I10, I27. Properties: P14, P16, P32.
    Acceptance: **AC29 (c)** -- named here explicitly because an earlier draft discussed it in this
    task's body while listing it in no acceptance line anywhere, leaving the clause the spec twice
    calls "the one a naive implementation fails while passing everything else" owned by nobody. AC15
    (one-level member checking). **P14 has no AC of its own** -- add one here asserting `ok` for a
    healthy set and *distinguishable* statuses for a missing payload versus an unresolvable member;
    R11.3 calls this in scope rather than deferred, so it must not ship untested._

  **DONE RECORD (2026-09-18).** Shipped in one commit; 4012 -> 4065 tests, `dev/check-spec.R` 9/9,
  `R CMD check` 0/0/0. The payload key now comes from the kind the artifact's **own metadata**
  declares, a set is checked past its payload's existence, and `fix = TRUE` gained the one payload
  upload that is safe to give it.

  **Five things a later change must not undo.**
  1. **An unknown kind is reported, never fatal.** `.datom_declared_artifact_kind()` returns `NA`
     for a kind this build does not know, and the payload check is skipped with `data_s3 = NA` and
     status `kind_unsupported`. Passing that value to the key builder instead aborts the **whole
     run** on `match.arg()`, and a validator that cannot finish reports nothing about the artifacts
     it never reached. The same helper returns `"table"` when there is no readable metadata at all,
     which is what keeps the pre-existing "no metadata, payload reported missing" behaviour intact.
  2. **The same-project test compares against the project the SET's metadata records**, not
     `conn$project_name`. On a reader connection the connection's name is a label nobody verified,
     so comparing against it misclassifies every member when the label differs -- and the two
     failure directions are not symmetric: a cross-project member wrongly treated as local is
     reported rotten, on a repo that is fine.
  3. **A member's resolution is its version snapshot's existence, and nothing deeper.** No member's
     own payload is fetched (a same-project member has a row of its own in the same result) and no
     inner set's member list is opened. Descending would make the cost of validating a set depend on
     the tree beneath it, which is the property P16 states.
  4. **The restore uploads only when the stored object is ABSENT and only when the clone's bytes
     hash to the recorded `document_sha`.** Both conditions, not either: dropping the absence check
     overwrites bytes a version pins, and dropping the hash check publishes bytes no version
     describes. The recorded hash is read, never recomputed -- I27.
  5. **`kind` is a column on the per-artifact frame, including the zero-row one.** The repair's
     "cannot be fixed" list reads it to keep a set out (a set's payload *is* in the clone), so a
     frame without it is a silent misclassification. Same shape as the Task 6 lesson about
     `.datom_empty_artifact_frame()`.

  **Seven probes, all of which reddened exactly what they should.**

    | Probe | Reddened |
    |---|---|
    | P1 | put the hardcoded `"table"` kind back | 17 assertions across 10 tests |
    | P2 | read an inner set's payload after confirming it | the nesting test's two read assertions |
    | P3 | drop the "stored object absent" condition from the restore | the never-re-upload test |
    | P4 | merge `document_sha_missing` into `members_unresolvable` | the document_sha test |
    | P5 | check cross-project members for existence | the pointer-only test, all three assertions |
    | P6 | drop the kind filter from the unrepairable list | the restore test **and** the unit test |
    | P7 | drop the hash comparison from the restore | the declines-loudly test |

  **The probe that changed a test rather than confirming it.** The first spelling of "a stored
  payload that is present is never re-uploaded" modified the clone's copy first, so it passed
  through the **hash** check and stayed green with the absence check deleted -- the guarantee it
  names was unasserted. It now leaves the clone matching and watches for the upload call instead.
  The same shape as Task 13's I19 finding: a test asserting a returned value where the behaviour
  lives somewhere else.

  **Three decisions, taken at their stated defaults on 2026-09-18.**
  * **No `member_conns` argument.** R11.2 allows a full cross-project check "unless the caller
    supplies that project's conn", and nothing today can express that, so the clause is unbuilt
    rather than partly built. The route that exists is better than the argument would have been:
    running `datom_validate()` against that project checks every artifact in it, which is a superset
    of one member pointer. **Residual, owned by nobody**: if a caller ever needs the narrow check,
    the shape is a named list keyed by project name, and `.datom_unresolved_members()` is the one
    function that changes.
  * **No byte-integrity download.** The validator checks that the payload is there and that its
    members resolve; it does not fetch the object to compare it against `document_sha`. That check
    exists on the read path, where it guards the bytes actually being used.
  * **The repair uploads a missing set payload.** Beyond R11's letter and taken anyway, for two
    reasons: without it a set whose upload failed after the commit had **no** repair route at all
    (the write verb correctly does nothing on unchanged members), and with no upload path in the
    code AC29c's "leaves the stored bytes unchanged" would pass forever whatever the code did.

  **REVIEW FINDING THAT FOLLOWED (2026-09-18), accepted in full: the restore landed on TWO public
  routes, and only one of them was described.** `.datom_sync_one_artifact()` is reached from
  `.datom_sync_data_metadata()`, which has two callers -- `datom_validate(fix = TRUE)`
  (`R/validate.R:212`) and **`datom_write(conn)` with no `data` and no `name`**
  (`R/read_write.R:1148`), the mirror-everything route. The behaviour there is correct and was kept:
  that route exists to push the clone's authoritative state to storage, and mirroring a set's
  metadata while leaving the payload it describes missing would be the odd half. What was wrong was
  the vocabulary around it, in four places, all now fixed: `datom_write()`'s `name` parameter said
  "manifest + per-table metadata", the interactive prompt counted sets while saying "table" and
  called the operation metadata-only, `dev/datom_specification.md`'s `datom_validate()` section said
  the same, and **`.datom_sync_table_metadata()` was a misnomer twice over** -- it handles either
  kind and can upload a payload -- so it is now `.datom_sync_one_artifact()`, with the old name
  recorded at the definition. One root cause: the path went kind-agnostic and kept its table-only
  words, the same class Task 6 closed in the manifest. **The second route now has a test of its own**
  (`.datom_sync_data_metadata(.confirm = FALSE)` restores the payload), called at that level because
  the write route asks for interactive confirmation a test session cannot give -- which is also worth
  knowing: non-interactively, that route is unreachable.

  **One residual stated rather than fixed.** A `members_unresolvable` finding survives
  `fix = TRUE` unmentioned -- nothing in the clone can restore another artifact's lost version, and
  the fix's closing line already says to re-run the verb rather than claiming completeness. If the
  sweep wants it named, the naming helper is `.datom_validate_unfixable_tables()` and it already
  reads the `kind` column it would need.

- [x] **15. Version-to-commit link (`commit_sha`)** &nbsp; **[DONE 2026-09-19 -- see the DONE record]**
  - Applies to **all** artifact kinds, not just sets -- `version_history.json` is shared. Placed
    after Task 14 because the repair-path behavior below needs `datom_validate()` to exist.
  - Add `commit_sha` to the **storage copy** of the `version_history.json` entry, beside `author`
    and `commit_message` (R21.5). **No volatile-list entry needed**: `metadata_sha` hashes
    `metadata.json`, not `version_history.json`, so this has zero identity impact.
  - Captured in `.datom_push_metadata_s3()` (step 7 of the write order, after the push), because
    the git copy of the history file is **inside** the commit it would name (R21.6). The git copy
    therefore never carries it, and does not need to -- `git log -p {name}/set.json` gives it to
    anyone with the clone (R21.8).
  - **The trap, and the reason this is its own task** (R21.7, I22, AC25): `datom_validate(fix =
    TRUE)` re-uploads metadata from the clone and would **silently strip `commit_sha`**. Treat the
    field as **derived, never authored** -- the repair path must **re-derive** it from `git log` on
    the artifact path. A naive implementation passes every other test and fails only this one,
    silently.
  - Document the version semantics this encodes (R21.1-R21.3): a version is content-derived and
    **code-invariant**, so a code-only change producing identical content mints **no** new version
    and leaves the recorded `commit_sha` alone (AC26). Roxygen should say this plainly -- it is the
    behavior most likely to be reported as a bug.
  - _Requirements: R20, R21. Invariants: I21, I22, I23. Properties: P26, P27. Acceptance: AC25,
    AC26. No pathway impact (no new lookup route -- the existing history read gains a field)._

  **PRE-START AUDIT (2026-09-19), cold, and it moves the centre of this task. NOTHING IS OPEN --
  both decisions were settled by the owner the same day, at the defaults (findings 5 and 6).** Eleven
  findings. Every claim below was
  checked against the tree or probed by running code -- the probes are named where they matter,
  because this task's whole subject is a field that disappears silently.

  1. **THE STRIP TRAP HAS THREE DOORS, AND THE BODY ABOVE NAMES ONE.** Derive the list rather than
     trusting this one (`grep -n version_history R/*.R`); today it is:

     | Function | Reached from |
     |---|---|
     | `.datom_push_metadata_s3()` (`R/read_write.R:940`) | **every ordinary write**, via `.datom_commit_and_mirror()` |
     | `.datom_sync_one_artifact()` (`R/sync.R:272`) | `datom_validate(fix = TRUE)` **and** `datom_write(conn)` with no `data`/`name` |
     | `.datom_sync_metadata()` (`R/utils-sha.R:576`) | `datom_write(conn, name = X)`, the metadata-only route |

     Four public entry points over three functions. Guarding only the repair leaves the field
     strippable by two **write** verbs, which is worse: a repair is at least something a person
     chose to run.
  2. **THE FIRST DOOR IS THE ORDINARY WRITE, AND IT STRIPS EVERY PRIOR ENTRY.** `.datom_push_metadata_s3()`
     reads the clone's `version_history.json` and uploads it **wholesale**, and the clone's copy can
     never carry `commit_sha` (R21.6). So without a merge the field survives on the newest version
     only, and the defect lands on write **#2** -- long before any repair is involved. **Probed, not
     read**: on a three-write fixture the stored and clone copies of that file are today
     `identical()`, which is exactly the property that makes the wholesale upload lossy the moment
     one copy is meant to carry more.
  3. **The capture point needs the commit threaded in, and one caller must pass `NULL`.**
     `.datom_commit_and_mirror()` already holds the sha (`R/read_write.R:997`) and, as of the audit,
     called `.datom_push_metadata_s3()` without it -- it now passes it (`R/read_write.R:1015`). One
     new argument; two callers -- that one, and the test-only legacy wrapper
     `.datom_write_metadata()` (`R/read_write.R:1042`), which makes **no commit** and must pass
     `NULL`. So a test spelled "every stored entry carries a `commit_sha`" passes or fails depending
     on which of those two produced the fixture; write it against a real write.
  4. **Deriving from git is implementable, and the derivation is exact -- probed on a real repo
     (git2r 0.36.2).** `git2r::commits(repo, path = "{name}/metadata.json")` filters to the commits
     touching that path, newest-first; a blob at a commit reads through `tree(cmt)[...]` +
     `git2r::content()`; and recomputing `.datom_compute_metadata_sha()` on the parsed blob
     reproduces the **recorded** version exactly. Iterating oldest-first therefore yields "the first
     commit that introduced that version" (R21.3) with no extra bookkeeping. The same probe confirmed
     a code-only commit is no version's producer, which is AC26 from the other side. Cost: one blob
     read plus one hash per commit touching that path.
  5. **SETTLED 2026-09-19 (owner): keep what storage has AND derive the gaps, in ONE shared helper
     all three doors call. It is REQUIRED, not preferred, and the reason is the sentence in finding
     8.** The three candidates were: (a) merge from the stored copy only, (b) derive everything from
     git on every upload, (c) both -- merge, then derive only what is missing. **(a) alone makes
     finding 8's tolerance a lie**: "an older build strips the field, and that is tolerable because
     the value can always be re-derived" is only true if something, somewhere, derives. Under (a)
     nothing ever does, so a stripped field is gone for good -- and an implementation of (a) passes
     every test this task will write while quietly removing the property that justifies the whole
     design. That is why (c) is a requirement of the design rather than the nicer of two options.
     **Cost is one-time and there is no standing tax**: derivation runs per **missing** entry, so an
     upgraded repo backfills once and the steady state is 0-1 derivations per write. Backfilling has
     no identity impact and is precisely "derived, never authored". One helper, because three copies
     of "keep `commit_sha`" is three places to lose it.
  6. **SETTLED 2026-09-19 (owner): `datom_history()` gains a `commit_sha` column.** R21.8 says the
     stored copy exists *purely* for the git-less reader, and that reader's only public route into
     this file is `datom_history()` (`R/query.R:202`), which built a fixed five-column frame. Drop
     the column and the feature does not exist for the only audience it was built for -- the field
     would be reachable only by hand-parsing JSON. `NA` where there is none, abbreviated under
     `short_hash = TRUE` like the other two hashes, and **present on the zero-row frame too**, which
     is the clause Task 14 and Task 6 both had to fix after the fact.
  6a. **One rule, stated once rather than as two separate facts: `commit_sha` is DERIVED, NEVER
     AUTHORED, so no user-facing verb accepts it.** `.datom_push_metadata_s3()` takes it as an
     argument only because it sits one layer below the caller that already holds it
     (`R/read_write.R:997`), and none of the three doors is exported -- no `.datom_push_metadata_s3`,
     `.datom_sync_one_artifact` or `.datom_sync_metadata` entry exists in `NAMESPACE`, checked. That
     one sentence covers both the internal threading and why the repair path re-derives instead of
     trusting whatever it was handed.
  7. **The clone's copy must never gain the field.** The patch happens on the way to storage and
     nothing may write the merged history back to disk -- AC25's second clause is what pins it. And a
     value that cannot be derived (shallow clone, rewritten history) must be **omitted**, never
     assigned as `NULL` into the entry, or `jsonlite` writes `{}` where a sha belongs (the Task 7
     trap, corrected in four places once already).
  8. **No vocabulary entry and no format bump, and that is a real asymmetry rather than an
     oversight.** The three append-only field vocabularies cover `metadata.json`, manifest entries
     and the manifest top level; **version-history entries have none**, so adding `commit_sha` trips
     no writer refusal. State the consequence rather than fixing it here: a 0.1.x build that has
     never heard of the field still strips it through any of the three doors and nothing stops it.
     That is tolerable *only* because the field is derived -- which is the argument R21.7 makes, and
     is worth restating at the code site.
  9. **P26 and P27 need per-door tests, by the guard-test rule** (the 2026-09-18 Decisions row): a
     test for a guard must fail when that guard alone is removed. So one case per door, and the way
     to know each case isolates its door is to delete that door's merge and watch **only** that case
     redden. A single "after a repair the field is still there" test satisfies neither property.
  10. **AC26's roxygen needs the worked example, not the principle.** Since Task 13 a set carries its
      code into the same commit, so the concrete shape of the behaviour most likely to be reported as
      a bug is: someone refactors, re-runs, gets byte-identical data, sees **no new version**, and
      finds `commit_sha` pointing at a commit that **does not contain their current code**. Say that;
      "versions are code-invariant" does not land.

  **DONE 2026-09-19.** Tests 4067 -> **4107** (+40), FAIL 0 / WARN 0 / SKIP 0; `R CMD check` 0/0/0
  with examples and vignettes run; `dev/check-spec.R` 9/9.

  - **One shared helper, three call sites, and a new file to hold it.**
    `.datom_history_with_commit_shas()` (`R/version-commit.R:61`) is called from
    `R/read_write.R:951`, `R/sync.R:296` and `R/utils-sha.R:676` -- the three uploads of
    `version_history.json`. It merges what storage already records, then derives only what is still
    missing, and only when something is (`R/version-commit.R:102` and `R/version-commit.R:146`). The
    file exists rather than three lines in the uploader because the whole subject is a field that
    disappears in silence; a reader looking for "where does `commit_sha` come from" now has one
    place to look.
  - **The capture point is threaded, not re-derived.** `.datom_commit_and_mirror()` passes the commit
    it just made (`R/read_write.R:1015`), so the ordinary write pays no git walk. The legacy wrapper
    passes `NULL` (`R/read_write.R:1046`) and its roxygen now says why a test that means "every
    stored entry names its commit" cannot use it.
  - **Derivation is `revparse_single(repo, "<sha>:<path>")`, not tree indexing**, and that choice is
    load-bearing: indexing a tree with a path that is not there returns an empty `list()` rather than
    raising, so absence and success look the same. Written up in `dev/engineering-notes.md` with the
    two other git2r facts the walk rests on.
  - **`datom_history()` gains the column** (`R/query.R:202`), abbreviated with the other hashes under
    `short_hash = TRUE` and present on the zero-row frame. Tested as three separate cases, because
    each is a separate mistake.
  - **Eleven deliberate breakages, and ten reddened the case they should have.** The eleventh found a
    real coverage hole rather than a spare guard, and it is the one worth carrying: the rule "do not
    repoint a version that storage already records" never fires on an ordinary write, because every
    ordinary write mints a **new** version. Deleting it left all nine existing cases green. The route
    that reaches it is **reverting an artifact to earlier content** -- the version already exists so
    nothing is appended to history, but a new commit is made and handed to the uploader, and without
    the rule that version's recorded commit moves to it. A test for that now exists, and the
    generalisation is in `dev/engineering-notes.md`: build the state that makes a guard fire, because
    a guard whose tests all run the common path is untested by however many of them there are.
  - **Door 1's breakage reddens six cases, and that is not a coverage gap.** Every fixture in the
    file is built by an ordinary write, so removing that merge disturbs everything downstream. The
    isolation that matters holds in the other direction: door 1's own case reddens for **D1 only**,
    door 2's for D1/D2/D4 and door 3's for D1/D3/D4 -- i.e. for its own door and for the two things
    genuinely upstream of it.
  - **Storage's copy wins over the derived value, which is the half derivation cannot cover.** A
    recorded commit that git can no longer reproduce -- shallow clone, rewritten history -- survives
    the next upload, and there is a case for it. Removing the merge while keeping derivation reddens
    that one case and nothing else, which is what tells the two halves apart.
  - **Nothing writes the field into the clone**, asserted twice: the tracked file carries no such key
    after two writes, and the repo is left with nothing staged and nothing unstaged.
  - **No identity impact, no vocabulary entry, no format bump.** `metadata_sha` hashes
    `metadata.json`, not `version_history.json`, so no artifact gains a version. Finding 8's
    asymmetry stands as recorded: an older build still strips the field and nothing refuses it, which
    is stated at the top of `R/version-commit.R` rather than treated as a gap.
  - **Pathway impact: none** -- no new lookup route; an existing history read gains a field.

  **REVIEW 2026-09-19, one finding, accepted and fixed.** Tests 4107 -> **4115**; `R CMD check`
  0/0/0; `dev/check-spec.R` 9/9.

  - **The finding: reading the stored history swallowed its failure, so "storage has none" and
    "storage could not be read" became the same answer.** Both produced no known values, the gaps
    were then filled from git, and the merged file was uploaded wholesale -- so a version git cannot
    attribute lost a value only storage had. The narrow case is the only one where it matters: if git
    can attribute everything, the same values come back and nothing is lost. Reachable in the repair
    route, which has no earlier storage read to gate it. Accepted as the same shape the spec keeps
    closing -- a silent handler inside the function whose output decides whether a guarantee holds.
  - **Fixed by making the two states distinguishable, not by refusing.** Refusing was considered and
    rejected on evidence: both backends raise the *same* condition for an unreachable store and for
    unparseable bytes (`R/utils-s3.R:185`), so they cannot be told apart, and the repair verb shares
    this helper -- so a refusal would leave a repo with a corrupt stored history and no route to
    replace it. That file is a projection for git-less readers and rebuilding it is what the repair is
    for; what must not happen is rebuilding it in silence. So: `.datom_stored_commit_shas()` returns
    `list(shas =, unreadable =)`, and the caller warns (`datom_commit_shas_lost`).
  - **The report fires on loss, not on the read failure**, which is the difference between a useful
    warning and noise: if git attributed every version, the same values were reconstructed and
    nothing is degraded.
  - **An existence probe separates absence from failure**, and its own failure counts as *could not
    look* -- an unreachable store cannot report that a file is missing. Without it a first-ever write
    would report commit links as lost when storage had never held any, which is worse than noise: it
    points at recovering a value that never existed.
  - **The review's own defect reddened nothing on the first probe, and that was the review being
    right twice.** Reverting the existence probe left the loss report intact, because the read still
    fails; the actual swallow is one line lower, where a failed read returned the same answer as an
    empty one. Probing the two separately found a missing case -- nothing stored *and* nothing
    derivable had no test asserting silence. Fifteen defects now, each reddening its own case.
  - **Six existing tests in `test-read-write.R` gained one mock binding** and no assertion changed.
    They drive the legacy no-commit wrapper against a store whose reads were never mocked, so the
    uploader correctly reported lost links; declaring the store empty is what those fixtures always
    meant. They assert on local git files only.
  - **The tolerance statement is qualified.** "The value can always be recomputed" now reads
    **from a complete clone**, because the unqualified form contradicted the same file's own
    admission two paragraphs down that a shallow clone cannot attribute a version.
  - **Which silences are safe is now stated rather than left to look uniform.** Every give-up in the
    git walk signals absence -- it leaves a gap that had no stored value either, which is why it was
    a gap -- so nothing is lost and nothing needs saying. Failing to read the stored copy is the one
    loss signal. The review was right to separate them rather than call the module defensive.

- [ ] **16. Acceptance-criteria test sweep + E2E** &nbsp; **[soft escalation: coverage review]**
  - Confirm **every AC defined in `requirements.md`** has a dedicated test -- derive the list, do not
    trust a range written here. A hardcoded range has now gone stale **twice**: it once stopped at
    AC26 and omitted AC27, and it then stopped at AC28 and omitted AC29. `dev/check-spec.R` now
    asserts this line names no explicit upper bound, so the defect cannot recur. Then add what the
    per-chunk tests
    missed. **AC15** (nesting resolves one level) is the one easiest to skip: it needs a
    set-containing-a-set fixture and an assertion that the inner payload is *not* read.
    **AC16** (machine-commit isolation) is **already covered as of Task 12** --
    `tests/testthat/test-foreign-content.R` seeds the foreign dirty file this line used to say no
    test creates, and reads the real commit tree. Verify rather than rewrite it, and do not replace
    it with a mocked version; the reasoning is in Task 12's DONE record.
  - **Inherited from Task 12, one test it deliberately did not write.** `datom_repo_commit(paths =
    NULL)` sweeps in datom's own files if an earlier write failed after writing local metadata but
    before committing. Design 19.7 **accepts** that -- excluding datom paths silently would make the
    argument lie, and it moves git ahead of storage, the safe direction -- and the roxygen says so,
    naming `datom_validate(fix = TRUE)` as the repair. What is missing is a test, and the reason it
    was deferred here rather than skipped is that its fixture is a **half-failed write**, which this
    task builds anyway for the E2E. Assert the sweep-in happens (it is the documented contract, not a
    defect) and that the repair verb then reports the repo consistent.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
    Include a `mode: product` repo with foreign `R/`, `dp/`, and `renv.lock` content so the joint
    commit and the machine-commit isolation are exercised end to end, not only in unit tests.
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: every AC defined in `requirements.md` -- derive the list, do not restate a bound._
  - **Escalation rationale**: the full acceptance-criteria set plus a new hash regime is a lot
    of surface to claim covered on a default model's word.

- [ ] **17. Docs + Spec Completion Procedure**
  - `dev/datom_pathways.md`: the set-resolution route card; note the `kind` branch and the
    `schema_version` gate on the read route (R13.1).
  - `dev/datom_specification.md`: set artifact kind, `datom-sv1`, `schema_version` contract,
    `artifacts` namespace (R13.2).
  - `NEWS.md`: the `artifacts` rename with its discovery-only exposure, the `schema_version`
    gate, the new exports (R13.4).
  - `dev/engineering-notes.md`: gotchas discovered (expect at least the relative-vs-full key
    distinction from Deviation D1).
  - `.github/copilot-instructions.md`: the **guard-test rule** from the 2026-09-18 Decisions row --
    a guard's test must fail when that guard alone is removed, and the way to know is to delete it
    and watch. Two tasks produced an instance of the same defect, which is what makes it a
    convention rather than an anecdote.
  - `_pkgdown.yml` reference entries for all new exports.
  - `dev/README.md`: move the spec Active -> Completed with date, test count, summary. **The spec
    persists -- do not delete it.**
  - Also document the two forward-compatibility mechanisms **together**, never separately: the
    vocabulary check and the schema number cover complementary sets and neither is sufficient alone
    (R23.5). And say plainly that every write-side refusal binds **0.1.1 forward only** (R23.7).
  - PR into `dev`, merge, delete branch.
  - _Requirements: R13, R9.6 (the schema history table ships here if #103 has not landed
    separately), R23.5, R23.7. Acceptance: **none of its own by design** -- this task ships no
    behaviour, so it has no criterion to assert. Its gate is the Spec Completion Procedure in
    `dev/README.md` plus AC10/AC11 (suite green, `R CMD check --as-cran` 0E/0W), both already owned
    by Task 16. Stated explicitly because silence in this slot previously read as an omission: this
    clause was **absent** until 2026-08-23 and the gate did not catch it, since Task 17's body ran to
    the end of the file and absorbed a later `Acceptance:` string._

---

## Phase E -- Forward-compatibility controls for 0.1.1 **[appended; five run EARLY, one does not]**

**These are appended but they do NOT run last.** Appending avoids a third renumber (see the
2026-08-23 shift record in the Decisions log); the execution order is stated here instead.

```
18 -> 19 -> [Task 5] -> [Task 6] -> 20 -> 21 -> 22 -> 7 -> 8 -> 9 -> 10 -> 26 -> 24 -> 25 -> 23 -> 11 -> 12 -> 13 -> 14 -> 15 -> 27 -> 28 -> 16 -> 17
```

- **18** is a prerequisite defect fix; the write-entry sequence sits on that function.
- **19** must land before **Task 7**: an allowlist seeded from *table* metadata and landed after the
  set metadata builder would silently drop set-specific semantic fields from identity -- the
  classification failure, on the first artifact of a brand-new kind.
- **20**, **21**, **22** need Phase B's single reader (Task 5) and the upgrade chain (Task 6).
- **23 must land before Task 11, and that is the one edge in this phase that does not point early.**
  Task 11 is what starts writing `mode: product` into `project.yaml`; Task 23 is what lets an older
  build notice. Writing the field first would leave a permanent population treating a product repo as
  an ordinary data repo. It sits immediately before Task 11 rather than at the front, because that is
  exactly sufficient -- nothing between here and Task 10 writes to `project.yaml` -- and rather than
  last, because a note saying "ship these together" is checked by memory at release time while a task
  order is not.

**Why these six and not others.** The filter is **does deferring it postpone the cost, or permanently
exclude every install shipped meanwhile?** All six only ever help builds that already contain them,
so deferring any one strands every 0.1.1 install forever. Everything else from the same review round
-- the bump rules, the schema history table, the policy prose, the floor's tooling -- lands later
without stranding anyone. If 0.1.1 gets crowded, those slip; these do not.

**Task 23 was added on 2026-09-10, after Task 22 shipped**, so it is the one item here that did not
come out of the 2026-08-23 review round. It meets the same filter, which is why it lives in this phase
rather than in Phase D beside the task it blocks.

**The aim, stated so it can be checked**: 0.1.1 is the **last** release that needs a transition plan.

- [x] **18. Fix `.datom_check_git_current()`'s fetch-failure return** &nbsp; **[DONE 2026-08-26]**
  - `return(invisible(TRUE))` sat inside the `tryCatch` error handler (`R/utils-git.R:435-448`
    post-fix; it was `422-429` when the defect was recorded), so
    it returned from the **handler**, not from the function. After a failed fetch, execution continued
    and compared `HEAD` against **stale cached** upstream refs. An offline user whose cached upstream
    is ahead got a hard abort where the comment says "network errors should not block offline work".
  - A live defect independent of this spec, and Task 21's entry sequence is proposed to sit on this
    function -- so it is fixed first and on its own.
  - Filed as [#104](https://github.com/amashadihossein/datom/issues/104); it is a bug fix, not spec
    work, and it is reachable in ordinary use (fetch once on a good connection, go offline, run the
    sync route).
  - **The fix**, restated here so this task does not depend on the issue being reachable: capture the
    fetch outcome and return from the function proper.

    ```r
    fetched <- tryCatch({
      git2r::fetch(repo, name = remote_name, credentials = cred)
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("Could not fetch from remote: {conditionMessage(e)}")
      FALSE
    })
    if (!fetched) return(invisible(TRUE))
    ```

  - **How to test it -- no git2r mocking required.** Tests go in `tests/testthat/test-utils-git.R`,
    in the existing `.datom_check_git_current()` block. `create_repo_with_remote()` gives
    `info$work_path` and `info$bare_path`, and the neighbouring "aborts when behind remote" test
    already builds most of the scenario. Sequence for the failing case: build the repo, have a second
    clone push a commit, fetch once so the remote-tracking ref is **cached ahead**, then break the
    remote (point its URL at a nonexistent path, or remove `info$bare_path`), then call the function.
    Today it warns and then **aborts** on the stale-but-ahead refs; after the fix it warns and
    returns. Add the companion case too -- fetch fails with cached refs **level** -- since that one
    passes today by accident and must keep passing for the right reason.
  - Keep the healthy-connection tests in that block green unchanged: they are what proves the fix did
    not turn the guard off.
  - _Requirements: none (defect fix). Acceptance: a repo whose fetch fails **warns and proceeds**,
    including when cached upstream refs are ahead of local -- the case that aborts today. Assert both
    the warning and the absence of an abort. No pathway impact -- record explicitly._
  - **DONE 2026-08-26.** The fix is the captured-outcome form above, with the reason it is written
    that way in a comment at the site so the next reader does not "tidy" the `return()` back inside
    the handler. Two tests added to the existing `.datom_check_git_current()` block in
    `tests/testthat/test-utils-git.R`, both no-mock as specified. tests: **2664** (+4),
    FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No pathway impact --
    the write route is unchanged; this restores the offline tolerance the route already claimed.
  - **The ahead-case test was proven non-vacuous before being trusted**, per the rule this spec
    applies to its own gates: stashing the `R/` change and re-running the file makes it **error** on
    the stale-ahead abort, and restoring the change makes it pass. The level-case test passes either
    way by design -- it exists because that case passes today for the wrong reason (nothing
    unfavourable to compare against, rather than the failure being handled), so it pins the accident
    as deliberate.
  - **No git2r mocking, and the mechanism is worth knowing**: `git2r::remote_set_url()` pointed at a
    nonexistent path makes `fetch()` raise for real ("unsupported URL protocol"), so the offline
    condition is genuine rather than stubbed. The neighbouring "tolerates network errors gracefully"
    test still stubs `git2r::fetch` and still has **no upstream branch**, which is why it never
    caught this: with no upstream the function returns before the comparison, so it passed on the
    defect. Left as-is -- it covers the no-upstream path.
  - **The warning is a cli alert, so it is a MESSAGE, not a condition of class `warning`.** Assert it
    with `expect_message()`; `expect_warning()` fails and reads as the fix not warning at all.
  - **This narrows a live safety check, deliberately.** An offline write now proceeds without knowing
    it is behind. The backstop is `.datom_git_push()`, which pulls and aborts if the push is rejected
    (`R/utils-git.R:267-277`, with the storage steps after it), so a write cannot land on storage from
    a stale base -- the same argument design.md 10.7 already makes for warn-and-proceed at the door.
    Recorded in the function's roxygen too, since "warns and returns TRUE" looks like a swallowed
    error to anyone reading the guard cold.

- [x] **19. Allowlist identity hashing (#100) + the classification test** &nbsp; **[DONE 2026-08-28]**
  - `.datom_compute_metadata_sha()` selected fields by **exclusion**, which
    cannot be forward-compatible: a build that has never heard of a field cannot know to ignore it, so
    it folds the field into the hash and reports a change on content that did not move. (Line numbers
    in this task's body describe the **pre-change** file; after the change the two constants are at
    `R/utils-sha.R:434-470` and the two functions at `R/utils-sha.R:492` and `R/utils-sha.R:524`.)
  - Hash a **named list** of fields; ignore everything else. **Seed it with exactly the fields hashed
    today so every existing identity is byte-identical.** Optional fields need marking optional --
    `parents`, `source_lineage`, `original_file_sha`, `custom` are conditionally present.
  - **An allowlist fails the opposite way from a denylist.** A denylist silently *includes* an unknown
    field; an allowlist silently *excludes* a new one, so identity quietly stops responding to real
    content changes. The classification test is the only thing that catches that direction: assert
    every field any metadata builder can emit -- **table and set** -- is classified, in the hash list
    or on a documented excluded list, so a new field cannot ship without a decision.
  - **Its justification has changed and the old one must not survive into the code comments.** Filed
    as "older writers keep working"; after the vocabulary decision (Task 21) they do not, by design.
    What it buys now: **readers compute correct identities, and a repo does not accumulate spurious
    versions**.
  - **THE CLASSIFICATION TEST MUST DERIVE THE FIELD SET FROM THE BUILDERS, NOT HARDCODE IT.** This is
    the difference between a forcing function and a decoration. AC33(d) names table **and** set
    fields, but the set builder does not exist yet -- Task 19 runs before Task 7 by design -- so at
    this point only the table half is exercisable. A hardcoded list of today's field names would
    therefore pass forever and never notice Task 7 adding `kind`. Instead enumerate what a builder
    actually emits (call `.datom_build_metadata()` with every optional argument supplied and take
    `names()`), then assert each name is in the hash list or on the documented excluded list. Written
    that way the test **fails the moment Task 7 touches the builder**, which is what makes the
    forward obligation self-enforcing rather than remembered.
  - **The field inventory is fully discoverable from one function, verified 2026-08-26.** Every
    top-level key of a metadata document is assigned inside `.datom_build_metadata()`
    (`R/read_write.R:325-329` for the five conditional ones) with exactly one exception,
    `meta$parquet_sha` at `R/read_write.R:1098`, which is volatile. Nothing else in `R/` writes a
    top-level metadata key. So seeding the allowlist does not require a hunt: the semantic set today
    is `data_sha`, `hash_algo`, `table_type`, `nrow`, `ncol`, `colnames` always, plus
    `original_file_sha`, `parents`, `source_lineage`, `custom` when present. Recorded because an
    allowlist seeded from an incomplete inventory silently drops content out of identity, and the
    grep that proves the inventory complete is cheaper to record than to redo.
  - **AC33(a)'s pinned value exists but its fixture is NOT a realistic document. DECIDED
    2026-08-26 -- implement the two steps below; do not re-deliberate.** The golden
    `59f1f1d936c5d65472733a924493ce2362255d442ebea6d41f7c3c9e7069d326`
    (then at `tests/testthat/test-utils-sha.R:899-904`; the repurposed test is now at
    `tests/testthat/test-utils-sha.R:921`) hashes
    `list(data_sha, name, nrow, ncol, table_type, hash_algo)` -- and **`name` is a field no builder
    emits.** Verified: `metadata.json` is written as exactly the object `.datom_build_metadata()`
    produced (`R/read_write.R`, `write_json(metadata, ...)` inside
    `.datom_write_metadata_local()`), and that object has no `name` key; the `name` at
    `R/read_write.R:1193` and `R/read_write.R:1255` is `datom_write()`'s **return value**, not the
    document.
    So a builder-derived allowlist will not contain `name`, this fixture's hash **will** change, and
    the golden test fails -- while **no real identity moves at all**, because no stored document ever
    carried the field. The fixture is unrealistic in a second way too: it has no `colnames`, which
    the builder always emits. Hitting that on day one and reflexively re-pinning the constant would
    destroy the only pinned evidence AC33(a) rests on.
  - **The two steps, in this order** (owner-decided 2026-08-26):
    1. **Anchor first, before touching `.datom_compute_metadata_sha()`.** Add a pinned fixture built
       by `.datom_build_metadata()` itself, with every optional argument supplied, and record its
       `metadata_sha` under **today's** code. That value is AC33(a)'s evidence and **must not move**
       across this task. Do this as its own step: a pin computed in the same edit as the change it
       polices is worth much less.
    2. **Repurpose the `name`-bearing golden as AC33(b)'s test rather than retiring it.** `name` *is*
       an unknown extra field, which is exactly the case AC33(b) asserts -- a document carrying one
       hashes identically to one without it. So assert that equality, and its pinned constant becomes
       the no-`name` value. The fixture that was going to break becomes the assertion for the
       property that breaks it.
  - **Rejected: adding `name` to the allowlist** to keep the old golden byte-identical. It is the
    tempting option and the cheapest in test churn, but the allowlist would then name a field datom
    never writes, breaking the one property that makes the list readable -- that it *is* what the
    builders emit. A later reader would reasonably conclude a `name` field exists somewhere.
  - **Superseded wording**: an earlier draft of this bullet called the above a "recommendation, not a
    decision" and told the implementer to settle it first. It is settled.
  - _Requirements: R9.5, R23.1 (the excluded list is the vocabulary's other half). Properties: P36.
    Acceptance: AC33 (all four clauses). The cv1 identity-contract suite
    (`tests/testthat/test-identity-contract.R`) must stay green, and the pinned-value assertion in
    AC33a is the one that proves this was behaviour-preserving. No pathway impact -- record
    explicitly._
  - **DONE 2026-08-28, in two commits, the ordering being the point.** Commit 1 (`fb84a72`) added the
    pins under the **unchanged** denylist code; commit 2 changed the selection. Two namespace-level
    constants in `R/utils-sha.R` -- `.datom_metadata_identity_fields` (ten fields, seeded to exactly
    what was hashed before) and `.datom_metadata_excluded_fields` (the seven-name `volatile` vector,
    promoted from a local variable so Task 21 can read the union as its vocabulary). Selection is
    `intersect(names(metadata), .datom_metadata_identity_fields)`. tests: 2675 -> **2686** (+11),
    FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No pathway impact --
    route shapes and gate positions are unchanged.
  - **Behaviour preservation is asserted, not inferred from a green suite.** Both pins from commit 1
    hold unchanged after the change: `f4d88543...` (every optional field supplied) and
    `d0c1ea75...` (none), which is AC33(a) and AC33(c). Before implementing, the two selections were
    also run side by side over six document shapes -- builder output with and without optionals, both
    again after a JSON round trip, and two hand-built fixtures -- byte-identical on all six.
  - **The whole suite showed exactly TWO failures under the change, both anticipated**, which is
    worth recording because it bounds the blast radius: the `metadata_sha` golden and Property 13.
    Everything in `test-read-write.R` and `test-identity-contract.R` survived untouched, because
    every one of those call sites computes-then-compares over real field names rather than pinning a
    value.
  - **THE FUNCTION IS NOW TWO FUNCTIONS, and Property 13 is why.** `.datom_compute_metadata_sha()`
    selects; the new `.datom_metadata_sha_from_fields()` sorts, serialises and digests. Property 13
    proves field ordering does not move with `LC_COLLATE`, using a fixture of names that genuinely
    collate differently (`Zeta`, `_leading`, `beta`). An allowlist drops all of them, leaving one
    field and nothing to order -- the test would have passed while asserting nothing. And it cannot
    be rebuilt from real names: **all ten identity field names sort identically under `C` and
    `en_US.UTF-8`** (checked), so no fixture made of them can discriminate. The split gives the
    ordering property something honest to bind to.
  - **Rejected: declare the list in radix order and drop the sort.** Locale independence would become
    structural, since nothing would be sorted at runtime. Rejected because hash stability would then
    depend on how somebody *types a constant* -- reordering it for readability would silently change
    every recorded version. Sorting keeps the order derived. The reasoning is in
    `.datom_metadata_sha_from_fields()`'s roxygen so the next reader does not "simplify" it back.
  - **The classification test derives its inventory from the builder and was proven to fail before
    being trusted**, per this spec's own rule. Adding a junk field to `.datom_build_metadata()` makes
    it go red naming the field -- **while every pinned hash stays green**, which is precisely the
    failure direction an allowlist has and a denylist does not. It carries a converse arm too:
    nothing in the identity list may be a field datom never writes, which is what mechanically blocks
    the rejected shortcut of allowlisting `name`. Adding `"name"` to the list turns that arm red, plus
    AC33(b). Both probes were reverted; the workspace carries neither.
  - **Three tests were quietly going vacuous and are re-fixtured**: `metadata SHA is deterministic`,
    `is order-independent` and `is a 64-char hex string` were built from `name` / `author` / `x`, all
    of which the allowlist drops -- leaving `data_sha` alone to carry assertions about several fields.
    They now use real field names, and the order-independence one gained a positive check that the
    shared fields really do reach the hash.
  - **The `name`-bearing golden was reused rather than retired, as decided.** It now asserts AC33(b)
    with its constant re-pinned to the no-`name` value
    `cce751b3f74d9f45c79ec96e4a19529580fec36b6ea37b39800b3a8a58e94ac8` -- which is what today's code
    already produced for that fixture minus the field, so it is not a fresh pin off the new
    implementation. A second unknown key (`some_future_field`) was added beside it: `name` is a
    historical accident, whereas a field arriving from a newer datom is the case the allowlist exists
    for, and only the second one reads as forward-looking.
  - **Two documentation sites were going to contradict the code, and one was ALREADY stale.**
    `dev/engineering-notes.md` said new non-versioning fields must be added to the `volatile` vector
    -- exactly inverted now -- and told the reader to keep the `59f1f1d9` fixture as-is; both entries
    are rewritten, the second carrying the transferable lesson that a pinned identity fixture must be
    a document the package can actually write. `vignettes/design-version-shas.Rmd` prints the
    algorithm as runnable-looking code and **listed five excluded fields when Task 4 had made it
    seven**, so it was wrong before this task touched it; it now shows the allowlist form and
    explains the forward-compatibility reason in plain terms.
  - **Deliberately NOT done here: [#98](https://github.com/amashadihossein/datom/issues/98).** The
    `dev/README.md` backlog row suggests pairing it with #100 so there is one identity-affecting
    change to verify. They cannot ship together: removing `jsonlite` from the identity path changes
    the hashed **bytes**, so every recorded identity moves -- the direct negation of AC33(a). #98
    stays a separate, deliberately breaking change.
  - **One gap left open, named rather than closed quietly.** A document with **no** identity fields at
    all now hashes an empty object instead of hashing its junk, so two unrelated corrupt documents
    hash equal. Reachable only from a corrupt file, and adding a refusal is an unrequested behaviour
    change, so no guard was added (I10a's spirit: no defensive code for a state nothing produces).
    Recorded so a later reader knows it was seen.

- [x] **20. Carry unrecognised fields forward on write (#100's missing half)** &nbsp; **[DONE 2026-09-08]**
  - Today the write path rebuilds metadata from scratch (`.datom_build_metadata()`), so an older build
    does not merely miscompute -- it **deletes** the field it did not understand.
  - Preserve unrecognised **top-level** keys at **three** levels: per-artifact metadata documents,
    manifest **entries**, and manifest **top-level** keys.
  - **The reason is information loss, not churn.** Churn settles after one version per handoff either
    way, because a build that deletes the field agrees with itself on its next run. Today most such
    fields are recomputable; the rule exists for the ones that will not be. So the test asserts the
    field **survives a round trip**, never a version count.
  - Note this now only bites where a write is permitted at all (Task 21 refuses most such writes), and
    it is kept because the manifest-level and cross-role cases still exercise it.
  - _Requirements: R23.8. Properties: P38. Acceptance: AC34. No pathway impact -- record explicitly._
  - **FIVE OPEN CALLS, ALL FIVE EXPLICITLY APPROVED (2026-09-08).** Recorded in Task 6's shape so the
    round stays checkable. These were **approved outright, not taken on silence** -- the owner
    answered "choices are fine" -- so each is a decision rather than a default that happened to hold.
    1. **The prior document is read from the clone, not from storage.** *Approved.* Shipped as
       `.datom_prior_metadata()`. Storage's copy is free to read at the point the merge happens, so
       this was a real choice: the clone wins because it is the file being overwritten, it costs no
       round trip, and it is where a pull from a newer collaborator lands.
    2. **A new file, `R/forward-compat.R`, rather than folding the helper into an existing one.**
       *Approved.* Task 21 adds three more functions to the same concern, which would otherwise land
       in three different files.
    3. **A preserved field is not announced.** *Approved.* Nothing is lost, so there is nothing to
       act on, and Task 21's refusal will make most of these writes stop anyway -- a message added
       now would be dead within one task.
    4. **The manifest row's vocabulary does not pre-list the set row's `member_count`.** *Approved.*
       Task 9 trips the forcing function when it adds the field, which is the point.
    5. **All three levels are built even though Task 21 makes two of them hard to reach.**
       *Approved.* See the bullet on that below: the row-level case is never covered by Task 21 at
       all, and `datom_validate(fix = TRUE)` bypasses the door.
  - **DONE 2026-09-08.** New `R/forward-compat.R` holds the whole of it:
    `.datom_carry_unknown_fields()` (copy onto a rebuilt document every top-level field of the prior
    document whose name this build cannot place), `.datom_metadata_known_fields()`,
    `.datom_manifest_entry_known_fields` and `.datom_prior_metadata()`. Two call sites:
    `datom_write()` step 5a (`R/read_write.R:1109-1113`) for the per-artifact document, and
    `.datom_update_manifest_entry()` (`R/sync.R:1004-1018`) for the artifact's manifest row. New
    `tests/testthat/test-forward-compat.R`, three internal `man/` pages, no new export, NAMESPACE and
    `_pkgdown.yml` untouched. tests 2867 -> **2902** (+35), FAIL 0 / WARN 0 / SKIP 0;
    `Rscript dev/check-spec.R` 9/9. **No pathway impact** -- no new lookup and no new traversal; two
    documents gain fields on the way out of a step that was already there.
  - **THERE IS A FOURTH SURFACE THE REQUIREMENT DOES NOT NAME: an entry in `version_history.json`.**
    Safe by the same property as the manifest's top level -- the history list is read and the new
    version is **prepended** (`R/read_write.R:752`), so an entry already in it is never rebuilt -- and
    equally unpinned until now. It is worth pinning rather than arguing because **two later tasks add
    fields to these entries**: Task 7's `document_sha` and Task 15's `commit_sha`. A build that
    normalised an old entry to today's field set would destroy exactly those, on a document describing
    a version it may know nothing about. One test (an unfamiliar field on an existing entry survives a
    later write, in git and in storage) and a comment at the site. Proven non-vacuous: rebuilding the
    existing entries from known names reddens both halves.
  - **`document_sha` IS THE ONE NAME THIS BUILD RECOGNISES AND NEVER WRITES, and that interacts with
    the narrowness rule -- decide it in Task 7 rather than meeting it.** Verified mechanically: the
    vocabulary holds 17 names, the metadata builder emits 16, and the odd one out is `document_sha`,
    which Task 4 classified as not-identity before anything wrote it. Because the merge carries only
    names it **cannot** place, a metadata document arriving with `document_sha` on it would have that
    field **dropped** on rewrite -- and dropped silently, since the field takes no part in identity, so
    no version moves to signal it. Unreachable today (nothing writes the field) and still unreachable
    after Task 7 as currently specified, which puts `document_sha` in `version_history.json`, where the
    fourth-surface property above protects it. What Task 7 must not do is put `document_sha` into a
    metadata document without also deciding what a build that does not emit it should do with one --
    the answer is not "carry it", because the rule cannot see it as unplaceable. The general shape,
    which is the reusable part: **a name that is classified but never emitted is invisible to
    carry-forward**, so classifying a field ahead of writing it is not free.
  - **THE THIRD LEVEL NEEDED NO CODE, AND THAT IS THE ONE WORTH KNOWING BEFORE TOUCHING THIS AREA.**
    The manifest's **top level** already survives, because `.datom_update_manifest_entry()` reads the
    document, edits three keys and writes it back -- an unfamiliar key beside `artifacts` is never
    touched. It is tested anyway: the guarantee is a property of *editing rather than rebuilding*, so a
    later refactor that assembled a fresh document would take it away without failing anything else.
    Proven by probe: making that function build from the skeleton instead of reading the file reddens
    the top-level test. A comment at the site says so.
  - **ONLY UNPLACEABLE FIELDS ARE CARRIED, and the alternative is worse rather than merely different.**
    A field datom knows keeps exactly today's behaviour, including disappearing when the write does not
    set it. The deciding case is `original_format` on a manifest row: a table imported from a CSV and
    later written straight from a data frame has no format to declare, and the row must stop claiming
    one. A blanket "keep whatever the new document does not mention" would leave that claim standing
    against a version it does not describe -- a wrong statement, where the thing being avoided is only
    a missing one. Two tests pin it (`custom` on the metadata document, `original_format` on the row)
    plus a unit test, and all three redden under a blanket merge.
  - **The merge happens after the version identity is computed**, next to the `parquet_sha`
    assignment, not inside the builder. Identity already ignores fields it cannot place, so both
    positions give the same hash today; attaching afterwards means a carried field cannot reach a hash
    **at all**, so no later change to the identity field list can pull one in. A test asserts the
    other half of the same point from outside: planting an unfamiliar field in both copies of a
    document leaves the next write a no-op, so such a field mints no version by itself.
  - **The prior document is read from the CLONE, not from storage** (`.datom_prior_metadata()`). It is
    the file being overwritten, it is a local read rather than a round trip, and it is where a pull
    from a collaborator on a newer datom lands. Storage cannot legitimately hold a newer document than
    the clone, because git is written first and gates the mirror; if it does, that is drift and
    `datom_validate()` owns drift. Same copy Task 21's checks read (R23.1a), so the door and this
    merge cannot disagree about which document they are talking about.
  - **`.datom_metadata_known_fields()` is a function, not a stored vector, and it has to be.** `R/` is
    sourced alphabetically (DESCRIPTION declares no `Collate`), and `forward-compat.R` sorts **before**
    `utils-sha.R` where both halves of the classification live -- so a constant built from them here
    would be built from values that do not exist yet and the package would fail to install. Same trap
    the `R/manifest-upgrade.R` header records for its step table, reached from the opposite direction.
  - **The manifest row gets its own vocabulary and its own forcing function.** Eight names today,
    listed by hand rather than derived from the row builder -- a vocabulary read off the builder's own
    output could never disagree with it. The test writes a real artifact with both optional row fields
    supplied and asserts every field on the resulting row is classified, so adding one without
    classifying it fails rather than making that field look unplaceable and get carried forward stale
    on every later write. **Task 9 will trip it** when it adds `member_count`, deliberately: the field
    is not pre-listed.
  - **EVERY GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED, and each probe was reverted.** (a) Removing
    the metadata merge reddens both halves of the metadata round trip, git and storage. (b) Removing
    the row merge reddens both halves of the row round trip. (c) Rebuilding the manifest instead of
    editing it reddens the top-level test **and** the row test. (d) Widening the merge to keep every
    absent field reddens all three narrowness tests. (e) Adding an unclassified field to the metadata
    builder reddens the metadata forcing function **while every pinned identity hash stays green** --
    which is the allowlist's failure direction, visible only to that test. (f) Adding one to the row
    builder reddens the row forcing function. Each of (e) and (f) names the offending field.
  - **What Task 21 will make hard to reach, kept anyway -- and the first version of this bullet had
    the scope wrong.** It said the refusal inspects top-level keys only, so an unplaceable field
    **inside a manifest row** would never trigger it, which made the row merge the live case.
    **Wrong**: R23.1 scopes the check to three documents and names manifest **entries** as one of them,
    so "top-level keys only" means *do not descend into a value* -- not *ignore entries*. Corrected
    2026-09-08 by the Task 21 cold-start audit, and swept in all four places it had reached.
    The accurate position: once the refusal lands, **all three** of the levels this task coded become
    unreachable through `datom_write()`'s door. Two things keep them earning their place, and the first
    is stronger than what the wrong version claimed: the **version-history entry** is not in R23.1's
    scope list at all, so its survival rests on nothing but this task's property -- which is why the
    test for it matters rather than being belt-and-braces; and `datom_validate(fix = TRUE)` reaches
    storage through `.datom_sync_data_metadata()` without passing that door.
  - **Three code citations elsewhere in this spec were ALREADY WRONG before this change**, found while
    re-deriving the ones this change shifted, and fixed: two lines cited as `datom_write()`'s return
    value and one cited as its in-pipeline manifest read all pointed at unrelated statements, as did
    the `meta$parquet_sha` citation in Task 19's body. Check 5 cannot see this class -- it asserts a
    cited line is not blank, nothing more -- so re-read citations by content after any insertion into
    `R/`. This is the third consecutive session to find some.

- [x] **21. Writer refusals: vocabulary check, floor read, unreachable-shape check, entry sequence** &nbsp; **[DONE 2026-09-09]**
  - **Vocabulary check** (R23.1): refuse a write when a datom-owned document carries a **top-level**
    key this build cannot classify. Evidence-based -- no version comparison, no config, no network.
    `custom` is **opaque** and classified as a whole.
  - **THREE SCOPES, THREE LISTS -- and Task 20 already built two of them.** R23.1's scope is three
    documents (per-artifact `metadata.json`, manifest **entries**, manifest **top level**), and
    "top-level keys only" means *do not descend into a value*, not *skip the entries*. So there are
    three vocabularies to check against, and as of 2026-09-08 the state is:
    | Scope | List | Status |
    |---|---|---|
    | per-artifact `metadata.json` | `.datom_metadata_known_fields()` (`R/forward-compat.R`) | exists -- the union of the identity list and the documented not-identity list |
    | a manifest **entry** | `.datom_manifest_entry_known_fields` (`R/forward-compat.R`) | exists -- eight names, with a test asserting every field a written row carries is on it |
    | the manifest's **top level** | none | **write it.** Five names today: `schema_version`, `project_name`, `artifacts`, `summary`, `updated_at` -- verified by grepping every top-level assignment (`R/sync.R:761-763`, `R/sync.R:1030-1031`, `R/manifest-upgrade.R:134`, `R/conn.R:523-524`) |
    Both existing lists are **append-only** and are read by the carry-forward rule as well, so the
    check and the carry-forward cannot disagree about what "unrecognised" means -- keep the new one on
    the same footing. **One decoy while grepping**: `datom_sync()` has a local data frame also called
    `manifest` and assigns `manifest$result` / `manifest$error` to it (`R/sync.R:560-561`); those are
    result columns, not manifest keys.
  - **Read the CLONE's copies, not storage** (R23.1a). This is the detail that makes the check
    possible at entry at all: the sequence has the manifest by then but **not** per-artifact
    metadata, which `datom_write()` does not touch until pipeline step 4 inside
    `.datom_has_changes()` (`R/read_write.R:405-413`, the storage read being the last of those lines).
    All three documents exist as local files
    (`{conn$path}/.datom/manifest.json`, `{conn$path}/{name}/metadata.json`), so this is a file read,
    it costs no round trip, and it works on the mirror-everything route where there is no single
    artifact name. **Do not implement the manifest half and skip the artifact half** -- that is the
    likely silent outcome if nothing is at hand, and it would remove the check from the one document
    that is never rebuildable and is where identity lives.
  - **The vocabulary list is append-only** (R23.2, I31). Never stop recognising a name that has ever
    existed, including names no longer written; retire by marking. A build that forgets a name refuses
    an **older** file and blocks the upgrade direction, which must always work. Give this the same
    weight as the frozen upgrade steps.
  - **Do not write directional logic** (R23.2a): a newer build's vocabulary is a superset of every
    older one's, so the check cannot fire on the upgrade path. A guard for it would be dead code
    guarding an unreachable state.
  - **Floor: the reading half only** (R23.3). One **optional** `project.yaml` field; absent means no
    floor, so no existing repo changes behaviour. It rides on the conn, since `datom_get_conn()`
    already parses that file. Compare and refuse at the write entry. One guard: whoever sets it must
    already satisfy it. **Deferred**: the purpose-built raising verb, tooling, docs.
    Ship the reading half now because it **cannot be retrofitted** -- a build that does not look for
    the field can never be bound by it, which is exactly why nothing can stop a 0.1.0 writer.
  - **Unreachable shape** (R23.4, I33): run the chain first; if the expected key is present
    afterwards, proceed; if still absent, refuse -- do **not** overwrite. Note the earlier phrasing
    ("refuse when the expected key is absent") would have **deadlocked the v1-to-v2 upgrade itself**.
  - **The entry sequence** (design 10.7): fetch, floor, read-and-check-then-chain, unreachable-shape,
    vocabulary, proceed -- all directly after the `datom_conn` class check and **above** the routing
    returns at `R/read_write.R:1137` and `R/read_write.R:1141`, because `.datom_sync_data_metadata()`
    mirrors the whole manifest to storage (`R/sync.R:212`) without reaching the manifest-writing step.
    All of it before any hashing, local write, or commit (I34).
  - **The double read is already decided, by Task 6**: the entry updater reads the same file again at
    pipeline step 6, and Task 6 accepted two reads of a small local file rather than threading the
    door's copy down. **The reason is not staleness on the table-write route** -- an earlier draft said
    the sync route pulls from the remote between the two, and on that route it does not: the pull is
    inside the push, after both reads. The reason is that the door runs before any hashing so a refusal
    leaves nothing half-written, and threading its document to the updater would carry state through
    every step in between, each of which must stay free to abort. Nothing left to decide there; keep
    it that way or say why.
  - **ON THE METADATA-ONLY ROUTE THE DOOR'S READ REALLY IS STALE, AND THIS SEQUENCE HAS TO ACCOUNT FOR
    IT.** `datom_write(conn, name = )` reaches `.datom_sync_metadata()`, which **pulls from the remote
    as its first act** (`R/utils-sha.R:571`) -- after the door has already read and checked the clone's
    manifest. So a collaborator's newer-format manifest can arrive in that pull, and the route carries
    on into a repo this build has just been told it understands. **Harmless in Task 6's shipping code**,
    because this route writes per-artifact metadata and never the manifest, so there is no way for it
    to leave a document half in each format. It stops being harmless here: step 1 of the entry sequence
    is a fetch, and if the checks at steps 2-5 run before a route's own pull, they are checking a state
    the route then replaces. Either the sequence owns the pull -- one fetch at step 1, no route pulling
    again afterwards -- or the checks that matter re-run after it. Decide which; do not leave both.
  - **THE ONE HOLE TASK 6'S PURITY AUDIT LEFT FOR THIS TASK, so it is not met by surprise.** The write
    door added by Task 6 inspects the **manifest** only. `.datom_sync_metadata()` (`R/utils-sha.R:576`)
    copies a per-artifact metadata document from the clone straight to storage, so a document pulled
    from a collaborator on a newer datom goes through unchecked. Pre-existing -- before Task 6 there was
    no write-side check at all, so that task narrowed the hole rather than opening it -- and this
    sequence is where it closes, because step 5 already reads all three documents at the door. Note
    this is the **same route** as the staleness item below: it pulls after the door has read, so
    whichever way that is settled has to cover this too.
  - **Say plainly that this binds 0.1.1 forward only** (R23.7). 0.1.0 has none of these checks and
    cannot be given them.
  - _Requirements: R23 (R23.1, R23.2, R23.2a, R23.3, R23.3a, R23.4, R23.5, R23.6, R23.7), R22.10.
    R23.1a. Invariants: I31, I32, I33, I34. Properties: P37. Acceptance: AC35, AC36, AC38 (a). Add a
    case asserting the check covers **per-artifact metadata**, not only the manifest -- an
    implementation that checks the manifest alone passes every other clause. **Pathway impact: yes**
    -- the write route gains an entry gate; update `dev/datom_pathways.md`._
  - **DONE 2026-09-09, in one commit.** The whole sequence is `.datom_check_write_entry(conn, artifact)`
    in `R/forward-compat.R`, called from `datom_write()` where the manifest-only door used to sit --
    directly after the `datom_conn` class check, above both routing returns, above any hashing or local
    write. Four steps in order: the floor (`.datom_check_writer_floor()`), the manifest through
    `.datom_read_manifest(conn, "clone", operation = "write")` which checks the format and then
    converts, the reachable-shape refusal, and the vocabulary check on the manifest's top level, on
    each artifact entry, and on each per-artifact `metadata.json` this write will touch. Tests 2905 ->
    **2959** (+54), FAIL 0 / WARN 0 / SKIP 0; `dev/check-spec.R` 9/9; `R CMD check` docs and
    code/documentation agreement 0/0/0. Four `man/` pages added, one deleted, two updated; no new
    export, NAMESPACE and `_pkgdown.yml` untouched. **Pathway impact recorded**: a new route card,
    "Given a write request, decide whether this build may write here", and the schema card's write-side
    paragraph now points at it instead of describing a door that no longer exists.
    - **`.datom_check_write_schema()` IS GONE, absorbed rather than kept beside the new sequence.** It
      read the clone's manifest itself and checked nothing else. Keeping it would have meant two doors
      reading the same file at the same moment with no way to say which ran first, and the order is
      load-bearing: the floor is a policy refusal that should fire before anything about format is
      considered, and the format check has to run before the conversion because there is no conversion
      step for a version this build has never heard of. Its three tests now drive
      `.datom_check_write_entry()`.
    - **`.datom_read_manifest()` gained an `operation` argument** and nothing else, so the entry
      sequence reads the manifest through the one shared reader as R23.1a requires rather than reading
      it a second way. Without it the refusal would have said the format was one this build "cannot
      read", on a write it had just stopped.
    - **THE FETCH -- step 1 of design 10.7 -- IS DELIBERATELY NOT IMPLEMENTED, and this is the one
      deviation in the task.** A fetch updates remote-tracking refs and **not the working tree**, so it
      cannot make any of steps 2-5 read a fresher document; the only thing that would is the
      behind-comparison in `.datom_check_git_current()`, which **aborts**. Adding that abort to
      `datom_write()` would newly refuse an offline write that works today, and would make the
      mirror-everything route -- which touches no git at all -- depend on `git2r`, a **Suggests**
      package. Cost of leaving it out: none of the four checks is any less correct, because each reads
      a file the route is about to write. What is left uncovered is the narrow race in the other
      bullet below, which is covered there instead. Reversible in one line if the abort is wanted.
    - **THE STALENESS QUESTION IS ANSWERED BY RE-CHECKING, NOT BY OWNING THE PULL.** The task named two
      options and said to pick one. `.datom_sync_metadata()` pulls from the remote as its first act,
      after the door has read the clone, so a collaborator's newer manifest or metadata document can
      arrive in that pull. That route now calls `.datom_check_write_entry(conn, name)` again
      immediately after the pull, against what the pull left on disk. The rejected option was for the
      sequence to own the freshness -- one fetch at the door and no route pulling afterwards -- which
      fails on its own terms twice: a fetch does not refresh the working tree, and dropping that
      route's pull would leave its commit on a stale base. Re-running is free: every step is a local
      file read and none of them mutates anything, which is why the function is documented as callable
      more than once. Pinned by a test that mocks the pull into planting an unfamiliar field and
      asserts the write is refused naming it.
    - **THE HOLE TASK 6's PURITY AUDIT HANDED FORWARD IS CLOSED.** `.datom_sync_metadata()` copies a
      per-artifact metadata document from the clone straight to storage, and nothing checked its
      declared format. Step 4 of the sequence now runs `.datom_check_schema_version()` on each
      per-artifact document as well as the vocabulary check, so a document pulled from a collaborator
      on a newer datom is refused. Same route as the staleness item above, and the re-check after the
      pull is what makes the closure hold there.
    - **THREE SCOPES, THREE LISTS -- the third one shipped here.** `.datom_manifest_known_fields` holds
      six names: the five a manifest carries plus **`tables`, marked retired**. That is the append-only
      rule made mechanical rather than remembered, and it is what AC35(c) asserts: a build that pruned
      the old name would meet an **older** document, fail to place a key it should know, and refuse
      it -- blocking the upgrade direction. In practice the conversion renames the key before the check
      sees it, so the entry earns its place as the worked example and as insurance if the check is ever
      consulted on an unconverted document. Its forcing function writes a real artifact and asserts
      every top-level field of the resulting manifest is classified.
    - **The vocabulary check runs on the CONVERTED manifest, never the raw one**, and getting this
      backwards is how the forward path deadlocks: a pre-rename document's list is under `tables`, so a
      check on the raw document would refuse every existing repo -- turning R23.4's first row into a
      refusal by a different mechanism than the one R23.4 warns about. AC35(d)'s test asserts a v1-shaped
      clone manifest writes normally, and asserts the pre-state so it cannot pass by the fixture edit
      silently not having taken.
    - **`artifact = NULL` means every artifact in the clone**, which is the mirror-everything route --
      the one with no artifact name in its arguments. Enumeration goes through the new
      `.datom_clone_artifact_names()` in `R/sync.R`, factored out of `.datom_sync_data_metadata()`,
      which now calls it too. One helper rather than two spellings, because the door has to inspect
      exactly the set the route writes; discovering it twice is how those two drift apart.
    - **The floor rides on the conn** (`conn$min_writer_version`, read from `project.yaml` in
      `.datom_get_conn_developer()`) as R23.3a specifies. A value that will not parse as a version
      **aborts** rather than being treated as no floor: reading a typo in a policy field as an absent
      policy field is the failure the mechanism exists to prevent, arriving through the mechanism.
      **AC36(c) is not implemented and is not owed here** -- "setting a floor above the setting build's
      own version is refused" is a guard on the *setter*, and R23.3 defers the setter. There is no code
      path in this build that sets the field, so the clause has nothing to bind to; it ships with the
      raising verb, which the `dev/README.md` Backlog row already owns.
    - **A consequence worth stating plainly: the refusal makes all three of Task 20's coded levels
      unreachable through `datom_write()`.** Expected, and the four round-trip tests that drove them
      through the real write path now hold the door open with a mock on the vocabulary check, named and
      explained at the fixture. What stays genuinely live is the **version-history entry**, which R23.1
      does not scope, so the test written for it in Task 20's review round is the load-bearing one. The
      merge is kept and kept tested for one forward-looking reason: the day a release widens what the
      door accepts, the merge behind it has to already work, and a merge that quietly broke while
      unreachable would ship as a silent field deletion on the first write that got through.
    - **EVERY NEW GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED**, seven probes, each reverted and each
      naming the tests it reddened. Disabling the vocabulary check reddens **6** tests; the floor **3**;
      the reachable-shape refusal **1**; emptying the per-artifact loop **5**, which is the clause an
      implementation checking only the manifest would fail; pruning `tables` from the manifest
      vocabulary **1**, the retired-name arm; dropping the per-artifact schema check **1**, the hole
      Task 6 left; and disabling the re-check after the pull **1**. The last three would each have
      shipped green without their probe.
    - **THREE REVIEW FINDINGS, all verified against the code before acceptance; two fixed in a
      follow-up commit, one recorded.** Two of them are the same route arriving for the third task
      running, which is itself the finding worth carrying: `datom_validate(fix = TRUE)` reaches storage
      by calling `.datom_sync_data_metadata()` **directly** (`R/validate.R:183`), so it does not pass
      `datom_write()`'s door at all.
      1. **The repair path bypassed the whole sequence.** No floor, no vocabulary, no per-artifact
         format check -- and the NEWS entry claimed the checks run on every write route, which was
         false. Damage was bounded, because that route copies documents rather than rebuilding them,
         so nothing was being deleted. It still mattered for the floor, whose stated purpose includes
         a block for a reason that is **not about format**, and those cannot be enumerated ahead of
         time -- so "this route only copies" is not an argument that the floor may be skipped there.
         **Fixed by putting the entry on the function rather than on each caller**, directly after its
         role and path guards. The `datom_write()` route now runs it twice, which costs nothing (local
         reads, no mutation, and the function is documented as callable more than once) and means the
         next caller cannot forget. Probed: removing it reddens two tests.
      2. **The same route read the manifest with the wrong verb.** `R/sync.R` used the shared reader's
         default `operation = "read"`, so a too-new manifest met on the way to storage would report a
         format this build "cannot read" -- during a write. Fixed with one argument. **Unreachable in
         practice once finding 1 is fixed**, since the entry refuses first, so the test has to mock the
         entry out to reach it; without that mock the assertion passed whatever the read said, which
         the probe caught. Kept anyway on the rule this spec applies everywhere: a message that is
         correct only because something upstream refused first starts lying the day the refusal moves.
      3. **The staleness fix covers one of the two pulling routes -- ACCEPTED RESIDUAL, not fixed.**
         The table-write route also pulls, inside `.datom_git_push(pull_first = TRUE)` at step 7
         (`R/read_write.R:976`), which is **after** step 6 has already written the metadata document and
         edited the manifest. So the door's answer can be stale there too, and re-checking cannot help:
         the write is already built by then. Left as it is, deliberately, because the backstop is real
         and design 10.7 already argues for it -- the push aborts on rejection or on a merge conflict,
         and the storage steps are 8-10, so a write cannot land on storage from a base this build has
         not seen. Recorded because the Task 21 summary said the staleness problem was "solved", which
         is true of the metadata-only route and overclaims for this one.
    - **Live code citations re-derived by content**, in all three spec files, after this change shifted
      lines in five `R/` files: the two routing returns, the mirror route's manifest read, the entry
      updater, `datom_sync_manifest()`'s read and its artifact lookup, `.datom_has_changes()`'s storage
      read, and the local metadata write's `git_paths`. Dated Decisions rows were left frozen per the
      2026-08-23 policy. Check 5 sees none of this class -- it asserts only that a cited line is not
      blank.

- [x] **22. Self-healing manifest rebuild (#101) + persist `original_format`** &nbsp; **[DONE 2026-09-10]**
  - Rebuild when the expected artifact key is **absent**, or when the declared version is **above**
    what this build supports (R22.11, R22.12). **Never on empty** -- empty is what a new repo and a
    truncated file both look like, so rebuilding on empty costs a listing per call on healthy repos
    and hides corruption.
  - **Reader warns and rebuilds; writer refuses** (R22.11). Same condition, opposite responses. A
    storage-only reader rebuilds **in memory for that session** and writes nothing. Warn **once**,
    pointing at the upgrade -- a silent repair is a silent degradation.
  - **The rebuild reads the recorded `version`** from `version_history.json` (`R/read_write.R:703`) and
    **never** recomputes it. Recomputing walks into the denylist defect in precisely the scenario the
    rebuild exists for, and would publish a `current_version` matching no version in the history --
    worse than the empty list it replaced. (Task 19 removes that defect, but the rebuild must not
    depend on having been run by a build that has the fix.)
  - **Persist `original_format` into per-artifact metadata.** It is written into the manifest entry
    (`R/sync.R:1060`) and never into metadata, so it is the one manifest field a rebuild cannot recover.
    Additive, and free now that Task 19 has landed -- **which is why it is sequenced here and not
    earlier**.
  - **Guard the dispatcher loop and test the no-op** (R22.10): R's `seq()` counts **down** when
    `from > to`, so guard with `if (declared < supported)` and assert a current-version document runs
    **zero** steps. **Already done by Task 6 -- see the audit below; do not rewrite it.**
  - **This task AMENDS THE TESTS Task 5 wrote**, though not the criterion they test. Task 5 shipped
    "a too-new manifest aborts at all five readers"; from here the manifest **reader** warns and
    rebuilds while the **writer** refuses, and per-artifact metadata still aborts at any role. AC32
    and P35 are worded to hold on both sides of that change, so nothing in the spec needs restating --
    but the assertions do, and leaving them would leave the suite asserting the opposite of the design,
    which is the one place this spec's recurring swept-some-places defect must not reach. **It is three
    files and eight assertions, not one file -- enumerated in the audit below.**
  - **COLD-START AUDIT, 2026-09-09** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim in this task
    checked against the tree. **Startable, after the eight items below.** Two of this task's own code
    citations had drifted and are repointed above (`R/read_write.R:602` -> `493`, `R/sync.R:1002` ->
    `1060`); the "never into metadata" claim **verifies** -- nothing in `R/` writes a top-level
    `original_format` onto a metadata document.
    1. **THE TEST SURFACE IS THREE FILES AND EIGHT ASSERTIONS.** This task's body said "the assertion
       in `test-query.R`", which undercounts by enough to leave the suite asserting the opposite of the
       design. Every assertion on the `datom_schema_unsupported` class was enumerated. **These must
       flip to warn-and-rebuild**: `datom_list refuses a manifest declaring a newer schema`
       (`tests/testthat/test-query.R:903`), `datom_status aborts on a newer schema rather than
       reporting it` (`tests/testthat/test-query.R:961`), `datom_status refuses a local clone declaring
       a newer schema` (`tests/testthat/test-query.R:996`, which is the input-file scan's clone read
       reached through `datom_status()`), `datom_summary refuses a manifest declaring a newer schema`
       (`tests/testthat/test-summary.R:157`), `datom_sync_manifest refuses a local manifest declaring a
       newer schema` (`tests/testthat/test-sync.R:1266`), and **the load-bearing one** --
       `.datom_read_manifest throws a too-new document rather than returning it`
       (`tests/testthat/test-sync.R:1453`), which is the shared reader's own returned-versus-thrown
       contract, plus its two `names the copy it refused` assertions
       (`tests/testthat/test-sync.R:1540`, `tests/testthat/test-sync.R:1574`). **These must NOT be
       touched**: the per-artifact read path (`tests/testthat/test-read-write.R:182`), the three write
       routes (`tests/testthat/test-read-write.R:2596`, `2610`, `2631`), the two write-entry tests
       (`tests/testthat/test-forward-compat.R:760`, `922`), and the two unit tests of the check itself
       (`tests/testthat/test-utils-validate.R:451`, `491`). All five readers do have coverage today, so
       none has to be written from scratch.
    2. **TASK 21 ALREADY SHIPPED THE WRITER HALF OF R22.11. Do not build it twice.** A writer meeting a
       too-new manifest is already refused at the write entry (`datom_schema_unsupported`, with
       `operation = "write"` in the message), and a writer meeting an **absent** artifact list after the
       chain is already refused (`datom_shape_unreachable`). Both of R22.12's triggers therefore already
       produce the writer's response. **What is left of R22.11 is the reader half**, plus
       `original_format`.
    3. **TASK 21 ALSO SUPPLIED THE DISCRIMINATOR, by accident, and it removes the hard part.**
       "Reader warns and rebuilds, writer refuses" needs the shared reader to know which it is serving,
       and until Task 21 it could not: `.datom_read_manifest()` took only a scope. It now takes
       `operation`, added for a message-wording reason, and **every writer call site already passes
       `"write"`** -- verified: the write entry and the mirror route both do, and the entry updater
       calls `.datom_check_schema_version()` directly with `"write"`. So the branch is
       `operation == "read"` -> warn and rebuild, `"write"` -> throw, with no new plumbing and no
       role inspection.
    4. **R22.10 IS ALREADY IMPLEMENTED AND AC38(b) AND (c) ARE ALREADY TESTED**, both by Task 6. The
       guard is `if (declared >= .datom_supported_schema) return(manifest)` in
       `.datom_manifest_upgrade()`, and the tests are `the dispatcher runs zero steps on a
       current-version document` (`tests/testthat/test-manifest-upgrade.R:92`) and `applying the
       dispatcher twice equals applying it once` (`tests/testthat/test-manifest-upgrade.R:114`). The
       first one **counts** step invocations through a mocked step table rather than comparing output,
       which is what makes it real. Nothing to add; re-deriving them would waste the chunk.
    5. **THERE IS NO STORAGE-SIDE ARTIFACT ENUMERATOR TO REUSE, and a Task 6 audit row says
       otherwise -- that row is WRONG.** It claimed `.datom_validate_tables()` "enumerates artifacts
       from a storage listing". It does not: it enumerates from the **clone**
       (`fs::dir_ls(repo_path, type = "directory")`, `R/validate.R:386`) and then checks storage per
       name. That matters because a storage-only reader has no clone, and the rebuild exists precisely
       for that reader. What does exist is the primitive `.datom_storage_list_objects(conn, prefix)`
       (`R/utils-storage.R:126`), recursive, both backends; artifact names come from keys shaped
       `{name}/.metadata/metadata.json`. **It returns FULL keys** -- including the `{prefix}/datom/`
       portion -- which is the two-key-shapes trap in `dev/engineering-notes.md`, so strip before
       matching. Cost of a rebuild is one listing plus two reads per artifact; budget for that when
       deciding what AC37(c) is protecting.
    6. **A REBUILT ENTRY MUST STAMP `kind`, OR EVERY COUNTER READS ZERO.** `kind` is not in
       per-artifact metadata until Task 7, and this task runs before it, so the rebuild cannot recover
       the field from the document -- it must write `kind = "table"`. That is correct today because
       nothing writes a set until Task 9, and it is **not** optional: R22.8 deliberately gives the
       counters no missing-`kind` fallback, so an untyped rebuilt entry is silently uncounted by
       `.datom_artifacts_of_kind()` and a rebuilt repo reports zero artifacts while listing them. Task 7
       and Task 9 must revisit this line; a comment at the site should say so.
    7. **`original_format`'s CLASSIFICATION IS A DECISION WITH A CONSEQUENCE, not a formality.**
       `original_file_sha` is already **in** the identity list (`R/utils-sha.R:434-437`), so the
       symmetric-looking choice for its sibling is identity too -- and that would re-mint a version for
       **every imported table in every repo**, on content that did not move. Classifying it excluded
       costs nothing and keeps this task's own claim ("additive, and free") true. State the choice and
       its reason rather than letting the classification test's red be settled by whichever list is
       typed first.
    8. **AC37(c)'s EMPTY-REPO FIXTURE MUST BE CURRENT-SHAPED.** The clause is that a genuinely empty
       repo triggers no rebuild and performs **no storage listing**. A current-shape empty manifest
       carries `artifacts` present-and-empty, so the absent-key trigger does not fire -- that is the
       fixture the test needs. An **empty v1** manifest is a different state: the conversion leaves no
       artifact key at all (deliberately, per the v1 step's own docs), so it *does* trigger a rebuild.
       Both behaviours are correct under R22.12, but a v1 fixture here fails the test for the right
       reason with a misleading diagnosis.
  - _Requirements: R22.11, R22.12, R22.10, R22.4 (the Design A qualification), R9.5 (per-file rule).
    Invariants: I32. Properties: P34, P36, P35, P11. Acceptance: AC37 (all six clauses), AC38 (b and
    c), and AC32 **still holding** after the behaviour change -- assert the new outcome is not reported
    as an unreadable manifest either. **Pathway impact: yes** -- the
    manifest read route gains a reconstruction branch; update `dev/datom_pathways.md`._
  - **DONE 2026-09-10.** tests: **3050** (+85). New file `R/manifest-rebuild.R`; the branch lands in
    `.datom_read_manifest()` at the point Task 6 left for it. `dev/datom_pathways.md` gains a card of
    its own ("Given a manifest whose artifact list this build cannot reach, still list the repo") and
    the schema card gains the one exception plus a fifth step. New test file
    `tests/testthat/test-manifest-rebuild.R`, plus two shared fixtures in `helper-mock.R`
    (`mock_stored_artifact()`, `mock_rebuildable_store()`) so a test can hand a reader a manifest it
    must reconstruct and still get a correct answer back.
  - **Eight assertions in three files were flipped, as the audit above enumerated**, and every one of
    them **passed unchanged after the code change for the wrong reason** -- the mock storage had no
    listing, so the rebuild failed and the original refusal was re-signalled. That is exactly the
    "suite asserting the opposite of the design" failure this task was warned about, and it would have
    survived a green run. Each flipped test now says AMENDED at the top and states what did *not*
    change, since the reason those assertions existed still holds: the outcome must be its own, never
    reworded into "could not read manifest".
  - **The writer's half was not rebuilt** (audit item 2) and R22.10 was not re-derived (audit item 4).
    What Task 21 shipped is reused as-is; two new tests assert the refusal still fires for a writer on
    the same document a reader rebuilds, so the asymmetry is pinned in the one function that decides
    it rather than inferred from two files.
  - **Three decisions this task took, each with the consequence rather than the principle.**
    (1) **`original_format` is classified NOT identity.** Its sibling `original_file_sha` *is*
    identity, so the symmetric choice looks right and is wrong: it would re-mint a version for every
    imported table in every repo, on content that did not move. (2) **`kind = "table"` is hardcoded on
    a rebuilt row**, with a comment naming Task 7 and Task 9 as the owners of that line -- an untyped
    row is uncounted, so a rebuilt repo would list its artifacts while reporting zero of them.
    (3) **A rebuild persists nothing, at any role.** Design 10.4 only requires in-memory for a
    storage-only reader; writing the clone's copy from a read was available for a developer and was
    not taken, because a read that quietly rewrote a repo's index is a larger surprise than the one it
    is fixing. The recorded copy is repaired by the next ordinary write.
  - **One thing the requirement does not name, decided here: which recorded version is the current
    one.** "Read the `version` from `version_history.json`" reads as "take the newest entry", and that
    is wrong in a case that already exists -- a write reverting to content already in the history
    appends **no** entry, so the current state is an older row and the newest one describes different
    content. Selection narrows by `data_sha`, then by the `created_at` the history entry copies
    verbatim (`.datom_recorded_current_version()`, three unit tests). Nothing is recomputed in any
    branch, and a history that records nothing usable yields a row with **no** version rather than a
    manufactured one.
  - **AC37(f) has one documented exception: `last_updated`.** The writer stamps the wall clock at the
    moment it rewrites a row and that moment is in no document, so the rebuild uses the version's own
    `created_at`. The test asserts every other field equal and this one present and plausible, and
    says so at the assertion -- so it reads as a decision rather than as a gap to be "fixed" by
    inventing a timestamp.
  - **Two R-level traps cost most of the debugging and are now in `dev/engineering-notes.md`**
    ("Two ways a condition's class silently disappears on its way to a handler"). Both matter here
    because the whole fork is decided *by* a condition's class: `stop(cnd)` inside one `tryCatch()`
    handler is caught by that same `tryCatch()`'s `error` handler, and `purrr::map()` re-signals a
    mapped function's condition as its own indexed error with the original demoted to a parent. The
    first turned every compatibility refusal into an IO failure; the second is why the artifact loop
    in `R/manifest-rebuild.R` is `lapply()` and must stay `lapply()`.
  - **Every guard was verified by breaking it on purpose**, per this spec's standing rule that a green
    run is not evidence. Dropping the namespace-root strip reddens the rebuild file past testthat's
    failure cap; triggering on *empty* instead of *absent* reddens 9; removing `kind = "table"`
    reddens 9 across three files; recomputing `current_version` reddens 1.
  - **The empty-v1 distinction from audit item 8 is now mechanical, not a comment.** A current-shape
    empty manifest carries its artifact list present-and-empty and triggers nothing; an empty **v1**
    manifest comes out of the conversion with no artifact key and does trigger. Both are correct under
    the same rule, and the two tests sit next to each other so the pair reads as one statement.
  - **REVIEWED after it landed; three findings, two fixed and one recorded (tests -> 3053).**
    (1) The hardcoded `kind = "table"` was guarded by a comment. It now has a forcing function in the
    rebuild's own test file, asserting the metadata builder emits **no** `kind`, so the day Task 7 adds
    the field the failure lands next to the line that has to change. Something did already redden --
    `test-utils-sha.R`'s pinned fixture list -- but in a test about identity hashing that says nothing
    about the rebuild, so the revisit still depended on memory. (2) `.datom_recorded_current_version()`
    fell back to the newest history entry when **nothing** matched the current content, contradicting
    the test two lines away that pins "no version beats a manufactured one". It now returns nothing;
    the remaining ambiguous case still takes the newest **candidate**, which is different in kind
    because both candidates describe the current content. (3) Recorded rather than fixed: nothing
    memoises the rebuild, so it repeats per call while the repo stays broken -- see the Decisions row
    and the note now in the `R/manifest-rebuild.R` file header. Both fixes were probed by reversion.

- [x] **23. `project.yaml` declares its format** &nbsp; **[DONE 2026-09-17. EXECUTED IMMEDIATELY BEFORE TASK 11 -- see the scheduling bullet]**
  - **The gap.** `project.yaml` carries fields a writer must **obey**, and has no way to say "this repo
    needs a newer datom". A build that does not recognise such a field walks past it and acts as
    though the repo had not asked for anything. `min_writer_version` is already in that position
    today: a build older than Task 21 does not read it, so a repo that raises the floor is not
    protected against exactly the builds the floor exists to stop. Task 11 adds `mode: product` and
    `set: {name}` to the same file, which is the second instance of the same shape and the reason this
    is worth doing now rather than later.
  - **Reading half -- CANNOT BE RETROFITTED.** `.datom_get_conn_developer()` parses the file at
    `R/conn.R:1070`. One call to the existing `.datom_check_schema_version()` after it, with `cfg` and
    the yaml path. Absent already means v1, so no existing repo changes behaviour. **Reader-role
    connections never see this file** (a reader has no clone), which is the right scope -- the harm is
    a *write* into a repo whose policy this build cannot read -- but say so, because "one gate covers
    every role" would be wrong.
  - **THERE IS A SECOND READ SITE, AND ONE GATE DOES NOT COVER IT.** Verified, not assumed:
    `.datom_resolve_data_location()` re-reads `project.yaml` **after a git pull** (`R/ref.R:327`), and
    it is called from `R/conn.R:1057` -- *after* the parse at 944. So a config arriving in that pull is
    never checked. The same parse is also what `conn$min_writer_version` is read from
    (`R/conn.R:1081`), so a pulled floor raise is missed in that session too -- pre-existing, and named
    here rather than left to be found later. Either gate the post-pull re-read as well, or record the
    residual explicitly the way the table-write pull staleness was recorded. Do not leave it
    unmentioned.
  - **Writing half -- retrofittable at any time.** Stamp the field in `datom_init_repo()`'s config
    block (`R/conn.R:509-521`, beside the existing `datom_version`). Increment it by R9.5's table like
    any other document, which means **Task 11's addition of `mode` does not move it** unless that task
    argues otherwise.
  - **DO NOT extend the vocabulary check to this file.** It was the first idea and it is the wrong
    tool. That check's power comes from the document being machine-written: an unrecognised key there
    **is** evidence a newer datom wrote it. `project.yaml` is hand-edited -- storage migrations,
    prefixes, descriptions, and whatever else a team keeps there -- so an unrecognised key is as likely
    a typo or a private note, and a refusal would block every write in the repo until somebody found
    it. R9.8 carries the general rule as a table, and AC39(d) is a test that a stray key is still
    tolerated, which is what stops the extension being made later as a tidy-up.
  - **SCHEDULING, and it is the whole reason this is a task rather than a note.** The reading half must
    ship **no later than** the release that starts writing `mode`. Order inside one release does not
    matter, so the constraint is only visible if datom-sets is ever split across releases with Task 11
    in the earlier one. Rather than leave that as something to remember at release time, this task
    **executes immediately before Task 11** and Task 11 states the dependency. That makes the
    guarantee structural.
  - **Correcting three things said while proposing this, so they are not inherited as fact.**
    (1) `project.yaml` is **not** the only datom-owned document without a format number --
    `version_history.json`, `governance.json`, `ref.json` and `dispatch.json` have none either.
    Verified: only the manifest and per-artifact metadata carry one. It is the only **hand-edited**
    one, and the only one carrying writer policy, which is the argument that actually supports a
    number here. (2) The harm is **not** "running `datom_sync()` on a set". Task 11's own body says
    today's behaviour on a product repo is a silent no-op, and that is what an older build gets -- an
    unhelpful answer, not a corrupting one. (3) Once a repo actually contains a set, an older
    **writer** is already stopped by Task 21's vocabulary check, because Task 7 adds `kind` to
    per-artifact metadata. Per R9.5 that addition does **not** bump any number, so the number would
    never have caught it -- the vocabulary check does. **So the window this task protects is narrower
    than it first looks: a product repo that does not yet hold a set** -- which is precisely the state
    a repo is in immediately after init, and the state in which somebody reaches for `datom_sync()`.
  - **COLD-START AUDIT, 2026-09-16**, run after Task 25 landed, every claim checked against the tree
    rather than reasoned about. **STARTABLE. Ten findings, ONE that must be decided before the first
    line** -- it carries a stated default, so a cold session is not blocked, but the wrong branch
    means a second constant and a changed checker signature. No escalation flag is owed: design.md
    section 12 carries E1 (Task 2) and E2 (Task 6) only.

    **What held**, verified rather than assumed. The developer path parses the file at
    `R/conn.R:1070` and reads `project_name` immediately after, so the reading half really is one
    call with `cfg` and the yaml path. `.datom_check_schema_version()` (`R/utils-validate.R:253`)
    already takes a parsed list plus a source label, already returns `invisible(1L)` when the field
    is absent, and its `operation` argument only picks a word -- so no signature change. **Reader
    connections really never parse this file**: `yaml::read_yaml()` has four call sites and all four
    are developer-path. The post-pull re-read at `R/ref.R:327` is real, reads only
    `cfg$storage$data$root`, and sits inside the migrated branch; `conn$min_writer_version` is
    assigned at `R/conn.R:1081` from the **pre-pull** parse, so the stale-floor claim in this task's
    body is exactly right. The init config block is where the body says (`R/conn.R:509`, with
    `datom_version` beside it). Task 11 states the dependency from its own end. And **nothing in the
    suite asserts `project.yaml`'s key set**, so stamping a field breaks no test --
    `datom_repo_set_data_store()` (`R/repo.R:90`) even read-modify-writes the file, so an unknown
    `schema_version` is carried forward rather than dropped, which is the edit-don't-rebuild property
    Task 20 relies on elsewhere.

    1. **DECIDED BY THE OWNER 2026-09-16, AND IT WENT AGAINST THIS AUDIT'S DEFAULT:
       `project.yaml` CARRIES ITS OWN FORMAT NUMBER, `.datom_project_schema`, which is `1L` today.**
       The audit had defaulted to stamping the shared `.datom_supported_schema`
       (`R/utils-validate.R:212`, currently `2L`) because every existing stamp site writes it
       (`R/read_write.R:391`, its set sibling, `R/manifest-upgrade.R:134`, the manifest skeleton), and
       priced the alternative as "a second constant kept in step by hand". **That price was wrong and
       the correction is the reason the decision went the other way**: there is nothing to keep in
       step, because the point of a per-file number is that it moves *independently* -- it stays `1L`
       through every manifest or metadata bump, and moves only when this file's own shape changes.
       Recorded explicitly because the shared constant is the intuitive answer and will be proposed
       again.

       **What the shared constant would actually have cost.** It never misses a change but sometimes
       refuses wrongly, and a wrong refusal here is not cheap: the check sits in connection
       construction (`R/conn.R:1070`), so it takes the **whole developer path**, including reads that
       would have worked. The escape hatch the audit offered -- a reader connection never reads this
       file -- does not help the person who is stuck, because the one refused is the developer, and
       their recovery is to hand-edit the very file whose hand-editability is why this task exists.

       **One mechanism claimed for that cost does NOT exist, checked rather than accepted.** The
       review had it that `datom_repo_set_data_store()` (`R/repo.R:90`) would silently raise the
       declared number, making the lockout ordinary churn between current users. It does not: that
       verb is a read-modify-write that carries `schema_version` forward untouched, and nothing but
       `datom_init_repo()` stamps a number. So the shared constant's blast radius is **repos
       initialised by the newer build**, not every store-pointer update. Narrower than argued -- and
       the decision stands anyway, because the asymmetry is what settles it: a per-file number has no
       false refusals at all.

       **B'S ONE REAL HOLE IS A FORGOTTEN BUMP, AND ITS FIX IS THE KEY-SET TRIPWIRE FINDING 10
       ALREADY POINTS AT.** A shape change that ships with an unmoved number is silently misread by
       an older build. So: a test that fails when `project.yaml`'s key set changes without
       `.datom_project_schema` changing -- which is exactly the "nothing in the suite asserts the
       config's key set" gap this audit found, turned into a guard. **State what that test means or it
       will be misread into the failure B was chosen to avoid**: it forces a *decision*, it does not
       mandate a bump. R9.5 is explicit that an addition does not move a number, so the correct
       response to it firing is often to extend the expected key set and leave the constant alone.
       **Task 11 fires it immediately**, by adding `mode` and `set` -- and per that task's own bullet
       the answer there is no bump. Same shape as the three vocabulary-list tests from Task 21.

       **THE TRIPWIRE'S FIRST EXERCISE IS TASK 11, AND THE WORKED ANSWER GOES BESIDE THE RULE** so
       the first person to meet a red test reads an answer rather than facing a choice: Task 11 adds
       `mode` and `set` to the init config, the test goes red, and the correct response is to extend
       the expected key set and leave `.datom_project_schema` at `1L` -- because an addition is
       reader-safe (R9.5) and the older build's misreading of `mode` is a silent no-op, not a wrong
       write. Task 11's own bullet already says the default answer there is no bump; this is the same
       call reached from the test's side.

       **B HAS ONE IMPLEMENTATION CONSEQUENCE NEITHER THE AUDIT NOR THE REVIEW STATED, AND IT MUST
       SHIP WITH THE CHECK RATHER THAN LATER.** `.datom_check_schema_version()` compares against the
       global `.datom_supported_schema` and names it in the message. Left that way, B's gate is
       nominal: the day this file's shape breaks and its constant becomes `2L`, a build whose global
       ceiling is already `2L` compares `2 > 2`, proceeds, and misreads the new shape -- the gate dead
       at exactly the moment it is needed. And because the reading half **cannot be retrofitted**,
       which is this task's whole premise, no later release can fix the builds already installed. So
       the checker gains a `supported =` argument, defaulting to `.datom_supported_schema` so every
       existing call site is unchanged, and **it must feed the message as well as the comparison**
       (`R/utils-validate.R:276` and `:281`), or a refusal reads "supports up to v2" while refusing a
       v2 file.

       **The argument stays optional rather than required, and the reason is that the default is
       CORRECT at every existing site rather than merely convenient.** Verified: the checker has
       exactly eight call sites -- `R/forward-compat.R:439`, `R/lineage.R:170`,
       `R/manifest-rebuild.R:228`, `R/member.R:553`, `R/read_write.R:104`, `R/sync.R:930`, `:937` and
       `:1137` -- and every one reads a **machine-written** document, a manifest or a per-artifact
       metadata snapshot, which genuinely do share the global number. Requiring the argument would
       repeat one constant at eight sites to guard against a future ninth. **The two other uses of the
       global constant need nothing**, also checked: `.datom_notify_manifest_upgraded()`
       (`R/sync.R:767`) is a notification rather than a gate and returns early when the document is
       current, and the upgrade chain (`R/manifest-upgrade.R:117`) is manifest-only -- `project.yaml`
       has no converter and gets none, only a refusal. **Note also that `.datom_check_write_entry()` is
       not a site for this**: its schema call covers per-artifact metadata, and the config gate does
       not belong inside it -- see finding 2 for where the write-side call does belong.

       **Two things carry the decision forward instead of a required argument.** (1) **The pairing of
       file and ceiling lives in one function, not at each call site**:
       `.datom_check_project_schema(cfg, source, operation)`, a three-line wrapper that supplies
       `supported = .datom_project_schema`. Two callers need it on day one -- connection construction
       and the set-write gate -- and the same precedent applies as
       `.datom_artifacts_of_kind()`, where one predicate written out at four sites lost a tolerance at
       one of them. A third caller then cannot forget the pairing, which is the failure a bare
       argument invites. (2) **The checker's own docs state the rule that predicts an override**, so a
       future caller derives it: a document **datom writes** takes the global ceiling; a document that
       outlives the build that created it and is **edited by hand** gets its own. The reason underneath
       is what makes it derivable rather than memorised -- the shared number works while every
       document on it is written by one build in one operation, and `project.yaml` is written once at
       init and then hand-edited for years, so its shape moves on its own clock.
    2. **THERE ARE NOW FOUR READ SITES, NOT TWO, AND THE NEW ONE READS EXACTLY THE FIELDS THIS
       REQUIREMENT IS ABOUT.** The body names `R/conn.R:1070` and `R/ref.R:327`; both still hold.
       Since it was written, Task 9 added `.datom_check_set_write_gates()` (`R/set.R:93`, parse at
       `R/set.R:107`), which reads `mode` and `set` on **every set write** -- the R10.2 fields that
       motivate the whole task. `datom_repo_set_data_store()` (`R/repo.R:90`) parses it too, and
       `datom_repo_attach_governance()` checks only that it exists. Default: **add the check to the
       set-write gates** as well -- `cfg` is already parsed there and `operation = "write"` gives the
       right wording -- and say in one line that the two `repo.R` verbs are covered by the
       connection-time gate because both require a developer connection, rather than leaving that
       silent.
    3. **THE HARM THIS TASK PREVENTS NOW EXISTS IN SHIPPED CODE, AND IT IS A SHARPER EXAMPLE THAN
       THE ONE IN THE BODY.** The body's case is a silent `datom_sync()` no-op on a product repo,
       which is unhelpful rather than corrupting. Since Task 9, a set write reads `set:` out of this
       file -- so a future format that renamed or moved that field would make the gate report "this
       repo declares `mode: product` but names no set" and tell the user to hand-edit a file that is
       already correct. An actionable-looking message that is wrong is worse than a no-op, and it is
       reachable today rather than hypothetically.
    4. **THE `operation` WORD, SO NOBODY ADDS A THIRD ONE.** Opening a connection is neither a read
       nor a write, and the refusal ends "...which this build cannot {operation}". Default: leave the
       connection-time call at the function's own default, `"read"` -- "this build cannot read" is
       literally true of the config file -- and do **not** widen the `match.arg()` set, which would
       touch the message text existing tests assert on. Pass `"write"` only at the set-write gate.
    5. **AC39(c) MUST ASSERT ON THE WRITTEN FILE, AND HERE THAT IS NOT PEDANTRY.** A test against
       the in-memory `project_config` list cannot see what `yaml::write_yaml()` did with an integer,
       which is the one thing the clause is about. Read the file back in the test.
    6. **AC39(b) IS A CHARACTERIZATION TEST, NOT NEW CODE.** `.datom_check_schema_version()` already
       returns `invisible(1L)` for an absent field, so "no warning, no refusal, no change of any
       kind" holds by reuse. Say so, or a call site grows a second absent-means-v1 branch that
       cannot disagree with the first only by luck.
    7. **AC39(d) IS THE CLAUSE A LATER TIDY-UP BREAKS, AND NOTHING TODAY WOULD CATCH IT.** Verified:
       `.datom_get_conn_developer()` ignores keys it does not know, so the tolerance is real but
       incidental -- it is a property nobody chose. The test is what converts it into a decision, and
       it is the reason the vocabulary check must never be pointed at this file.
    8. **THE STALE FLOOR IS NOT FIXED BY THE OBVIOUS FIX, AND THE TWO HONEST OPTIONS DIFFER IN
       SCOPE.** Gating the post-pull re-read covers the *format* but leaves `conn$min_writer_version`
       read from the pre-pull parse (`R/conn.R:1081`), because that assignment runs after the pull
       but off the older `cfg`. Fixing it means re-parsing once `.datom_resolve_data_location()`
       returns and reading the floor from the fresh copy -- a change to connection construction with
       Task 21's test surface attached. Default: **gate the re-read, record the floor residual** the
       way the table-write pull staleness was recorded, and do not widen scope.
    9. **THE PATHWAY CARD NEEDS ITS QUESTION WIDENED, NOT JUST A ROW ADDED.** "Given a repo, decide
       whether this build can read it" opens with "a metadata or manifest document just arrived from
       storage or from the local clone", and `project.yaml` is neither -- it is a hand-edited config
       parsed while a connection is built. Its step 3 also carves out the manifest-only rebuild
       hatch; this file has no hatch and aborts like per-artifact metadata. Default: widen the
       question line, add the file to the primary-files list, and add the developer-connection entry
       to "where it is called".
    10. **NO NEW EXPORT, SO NO `_pkgdown.yml` ENTRY AND NO NAMESPACE CHANGE** -- unlike the last four
        tasks, which all added exports and all needed that reminder. Both halves here are internal:
        one call inside connection construction and one field inside an existing config block.
  - _Requirements: R9.8, R9.4 (why not `datom_version`), R9.5 (the bump rule), R10.2 (the fields that
    make it matter), R23.1 (the mechanism this deliberately does not use). Acceptance: AC39 (all four
    clauses), with (d) as the one a later tidy-up would break. **Pathway impact: yes** -- the
    "decide whether this build can read it" card gains `project.yaml` as a third document, with its
    own row in that card's "where it is called" list._
  - **DONE 2026-09-17, tests 3781 -> 3836.** `.datom/project.yaml` now declares a format, and every
    place this build reads that file checks it first. All ten audit findings were implemented at the
    decisions and defaults recorded above; nothing was left open and nothing deviated.

    **What shipped.** `.datom_project_schema` (`1L`) beside the repo-wide
    `.datom_supported_schema`, deliberately a separate number.
    `.datom_check_schema_version()` gained `supported =`, defaulting to the repo-wide constant so
    all eight existing call sites and the message text their tests assert on are untouched; it feeds
    the comparison **and** the "supports up to vN" line. `.datom_check_project_schema(cfg, source,
    operation)` is the wrapper that pairs this one file with its own ceiling, and it is the only
    thing that supplies that ceiling. `datom_init_repo()` stamps the field.
    **Every site that parses this file is gated** -- enumerated by the review below rather than
    assumed, from `yaml::read_yaml()`'s call sites in `R/`. Four at the time this shipped, and Task 11
    adds a fifth, which is why the rule is stated rather than the number:
    connection construction (`.datom_get_conn_developer()`, at `operation = "read"` -- opening a
    connection is neither a read nor a write, and "cannot read" is literally true of the config file,
    so the `match.arg()` set did not widen), the post-migration-pull re-read in
    `.datom_resolve_data_location()`, `.datom_check_set_write_gates()` at `operation = "write"`, and
    `datom_repo_set_data_store()`, also at `"write"`. The last of those was added by the review that
    followed this task; the first commit argued it away, wrongly.

    **Five things a later change must not undo.**
    1. **The two constants are separate numbers, and `project.yaml` is never stamped with the shared
       one.** Collapsing them is the intuitive tidy-up and it buys a false refusal: the check runs
       while a developer connection is built, so a build one manifest bump behind would lose the whole
       developer path -- reads included -- on a config file whose shape never moved.
    2. **`supported =` must feed the message, not only the comparison.** Feeding only the comparison
       produces a refusal reading "supports up to v2" while refusing a v2 file, which reads as a datom
       bug rather than an upgrade prompt. Two tests, one per half.
    3. **The vocabulary check must never be pointed at this file.** It is hand-edited, so an
       unrecognised key is as likely a typo or a private note; refusing on one would block every write
       in the repo until somebody found it. AC39(d) is the test that turns today's incidental
       tolerance -- the parser simply ignores keys it does not know -- into a decision.
    4. **The set-write gate's format check runs BEFORE `mode` and `set` are read.** Those two checks
       report *on* those fields, so a format this build cannot read would turn them into confident
       advice about the wrong thing: a future shape that moved `set:` makes the gate say "declares
       `mode: product` but names no set" and send the user to hand-edit a file that is already
       correct. The test edits the config **after** the connection is built, which is also what shows
       this gate is not a duplicate of the connection-time one.
    5. **The key-set tripwire forces a decision, not a bump.** Its comment carries the worked answer
       for Task 11 -- the correct response to `mode` and `set` is to extend the expected key set and
       leave `.datom_project_schema` at `1L` -- so the first person to meet a red test reads an answer
       instead of facing a choice. **Corrected 2026-09-17 by Task 11's audit**: it does not follow that
       Task 11 turns the test red. The tripwire inits with no mode, so it sees only keys written on
       **every** init, and if those two are emitted just for a product repo it stays green. The
       correction is in the test's own comment and in design 10.8; the fix is a second case, and it is
       Task 11 finding 1.

    **One residual, recorded rather than fixed (finding 8's stated default).**
    `conn$min_writer_version` is assigned from the **pre**-pull parse, so a floor raised in a
    migration pull is missed for that session. The *format* of the pulled file is checked, because the
    re-read is gated; the floor is not. Fixing it means re-parsing after
    `.datom_resolve_data_location()` returns, which is a change to connection construction with Task
    21's writer-floor test surface attached, and the window is one session on a migrating repo. The
    note lives at the assignment site in `R/conn.R`, not only here.

    **Four probes, by breaking the code on purpose and counting what reddened rather than by reading.**
    (1) Feeding the comparison but not the message -- the exact half-done change -- reddens 2
    assertions in the ceiling-in-message test. (2) Stamping `.datom_supported_schema` in
    `datom_init_repo()` reddens 6, and **three of them are the false refusal made concrete rather than
    argued**: beyond the two tests that assert which constant is written, three unrelated tests that
    open a connection on a freshly initialised repo **error**, because a repo stamped `2L` is one the
    build that just created it cannot open. That is the whole case for a per-file number, reproduced.
    (3) Deleting the format check from the set-write gate reddens 2 write-side tests while **every**
    connection-time test stays green, which is what shows the second site is not decorative -- and the
    "tolerates an absent number and an unknown key" test correctly stays green too, since removing a
    gate cannot break a tolerance. (4) Deleting the gate on the post-pull re-read reddens the migration
    test; that test starts from a readable config and has the mocked pull replace it with a too-new
    one, so it also fails if the check is ever moved above the pull.

    **One thing needing no code, said once so it is not silently discovered.** A **reader**-role
    connection never parses this file at all, which is the right scope -- the harm is a *write* into a
    repo whose policy this build cannot read -- but it does mean "one gate covers every role" would be
    wrong. (`datom_repo_attach_governance()` needs nothing either, but for a duller reason: it checks
    only that the file exists and never parses it.)

    **REVIEWED after it landed (2026-09-17); one finding, ACCEPTED and fixed (tests 3836 -> 3841).
    `datom_repo_set_data_store()` was the one site that parsed this file without checking it, and it
    is also the only writer of it besides `datom_init_repo()`.** The first commit argued the check away
    on the grounds that the verb requires a developer connection, so connection construction had
    already refused an unreadable config -- **and that argument is refuted by this same commit's own
    words elsewhere**: `.datom_check_set_write_gates()`'s docs say the connection-time gate is not
    redundant, because a hand edit or a pull can replace the file between opening a connection and
    writing through it. It applies harder here, for three reasons the review put in the right order.
    The verb does not merely write: it merges a `storage$data` block into the document **on this
    build's assumptions**, so a format that reparented those keys ends up with a stale block beside the
    real one. It then **commits and pushes**, so the wrongly-edited file reaches everyone sharing the
    repo -- the set-write gate only refuses a write, while this one publishes one. And the timing is
    not contrived: this is the storage-migration verb, called exactly when somebody is reorganising
    storage and therefore most likely to have hand-edited that file. The reading half cannot be
    retrofitted, so it could not wait. Fixed with the same two lines the set-write gate uses,
    `operation = "write"`, above the merge; the comment is **replaced rather than deleted**, because
    the claim it made is the thing that is false and a later session would otherwise re-derive it. Its
    true half is kept and now labelled as separate: the read-modify-write is why an unrecognised
    `schema_version` is carried forward untouched, and why this verb never raises the declared number.
    One test, asserting the refusal **and** that the file is byte-identical afterwards; removing the
    check reddens exactly it. **The review's earlier claim that this verb silently raises the number
    stays refuted** -- that was checked and is wrong, and the two findings are about different things:
    one about what the verb writes into the field, this one about writing the file at all without
    having checked it.

---

---

## Phase F -- Set ergonomics **[appended; executes after Task 10, before Task 23]**

**Appended rather than inserted, for the same reason Phase E was**: nothing renumbers. Both tasks
here are **pure additions over Task 10's result** -- neither changes a stored document, neither adds
a storage read that Task 10 did not already make, and either can be deferred without unpicking the
other or Task 10. That is why they are separate chunks rather than bullets inside Task 10: a
checkpoint between "reading a set works", "finding things in it is pleasant" and "building one is
pleasant" is worth more than one large commit.

**Why they exist at all.** Task 10 hands back a correct object that is unpleasant to use: a nested
list that prints as forty lines, whose members are reached positionally. A citable artifact whose
read output cannot be read at a console is half-delivered, and the two highest-value messages in the
whole design -- an ambiguous member name, and a member belonging to another project -- have nowhere
to live until these verbs exist. Weighed against rule 4 of the conventions file (resist complexity
that exists only for marginally better UX) and accepted on those two grounds specifically, not on
ergonomics in general.

**The naming rule these follow is in design.md** ("Verb families on the public surface"). In short:
`get` returns references, `read` returns materialised content, `fetch` resolves a pointer to whatever
it points at, `list` returns a data frame, `assemble` / `add` build. A name outside a family needs a
reason.

- [x] **24. Read-side ergonomics: finding and shaping members** &nbsp; **[EXECUTES AFTER TASK 10]**
  - **DEPENDS ON TASK 10** and says so from this end as well as that one: every verb here is a
    function of the `datom_set` object Task 10 returns, and `datom_fetch_member()` is implemented
    **over the same link factory** that builds `$fetch`, so there is one core with two entry points
    rather than two implementations of kind dispatch.
  - **`datom_fetch_member(conn, x, name, tags = NULL, version = NULL)`** -- resolves one member.
    Accepts a **name, a member record, or a link** as its third argument, all through one internal
    accessor, so a loop and a console call use the same verb. Dispatches on `id$kind` to
    `datom_read()` or `datom_get_set()`.
    - **An ambiguous name aborts and teaches.** Two members can legitimately share a name (R2.14a:
      the same artifact at two versions, a current table beside a locked baseline). List the
      candidates with their tags and point at the two ways to narrow. `tags =` is the one people will
      reach for, because tags are the navigation axis; `version =` stays for exact pinning.
    - **The project check is a HINT ON FAILURE, NOT A GATE, and that was settled by evidence on
      2026-09-14 rather than by preference.** The message is still the highest-value one in the
      design: without it, the non-conjunctive access model (R3.3) presents as a confusing
      missing-object error rather than as "this member lives in another project, open a connection to
      it". But it must not refuse the fetch, because **a connection's `project_name` is not a
      verified fact**. For a **reader** connection -- the primary consumer of a set -- it is a label
      passed to `datom_get_conn()`; the namespace comes from the store's root and prefix, and nothing
      compares the label against the repo.
      Verified end to end: a reader whose label is `"a-label-nobody-validated"` reads a set written by
      project `set-project` and fetches its members correctly. A gate would abort that. So: attempt
      the resolution, and when it fails **and** the two names differ, add the bullet naming the
      member's recorded project. Two tests in `test-get-set.R` pin the no-gate half from Task 10's
      side.
      **RESTATED 2026-09-15, because Task 26 moved half the premise.** This bullet used to add "and a
      reader is never told which string the writer used", which is no longer true: the writing repo's
      own project name is now recorded in per-artifact metadata, and a member's `id$project` is read
      from there rather than copied off the connection. **The no-gate conclusion is untouched**, and so
      are its two tests -- what makes a gate wrong is the **connection's** side of the comparison,
      which is still an unvalidated label, and comparing a verified value against an unverified one
      refuses working reads exactly as before. What did improve is the hint's wording: it can now name
      the project the member's **own writer recorded**, which is a stronger claim than naming a
      project someone typed.
    - **Where the check lives is decided by the projection path, not by this verb.** After
      `datom_structure_members()`, a leaf is a **link**, so `dp$output$adsl(conn)` never enters
      `datom_fetch_member()` -- a hint implemented only here would miss the route people actually use.
      Put it in the shared link core both entry points already go through, and do not write a second
      copy in this verb.
    - Note this is kind dispatch at the **member** level, which is the only level it belongs at
      (R12.3). A polymorphic top-level `datom_read()` stays refused.
  - **`datom_list_members(x)`** -- long format, one row per member **per tag**: `name`, `project`,
    `version`, `kind`, `key`, `value`. Long rather than wide because tags are open-keyed and
    multi-valued, so wide needs list-columns and a per-set column set. A plain `data.frame`, matching
    `datom_list()`, so tag filtering is `subset()` or dplyr and datom grows no query vocabulary. **An
    untagged member still gets a row** (with `NA` key and value), so `unique(map$name)` is complete.
  - **`print.datom_set()`'s hint is upgraded here** to name `datom_fetch_member()`, which is the better
    route once it exists. Task 10 ships that message pointing at the link form so it is never wrong;
    changing it is part of this task, not an afterthought in it.
  - **`datom_structure_members(x, by, missing = "untagged")`** -- the nested navigable view: group
    members by the values of the tag key(s) named in `by`, with each leaf the member's **link**, so
    `dp$output$adsl(conn)` works and tab-completes.
    - **A MULTI-VALUED AXIS PUTS ONE MEMBER UNDER SEVERAL BRANCHES, AND THAT IS THE WHOLE POINT.**
      R4.6 calls multi-valued tags "the point, not an extension" and "the **only** reason arrays exist
      in the grammar" -- a folder cannot hold an item twice, and a tag can. So a member tagged
      `domain = c("safety", "efficacy")` must appear under **both** `dp$safety` and `dp$efficacy` when
      `by = "domain"`. **Test it explicitly**: presence under both branches, **and** that the total
      leaf count exceeds the member count, which is what makes "in two places at once" observable
      rather than inferred. The spelling to guard against is taking the first value
      (`split()` on `m$tags[[by]][1]`), which is silent; note that `vapply(..., character(1))` over the
      axis **errors** instead, so the loud spelling is not the one that needs a test. Task 9's fixture
      already carries `domain = c("efficacy", "safety")`.
    - **A LEAF-NAME COLLISION ABORTS, NAMING BOTH MEMBERS** (owner-decided 2026-09-13). Two members
      may legitimately share `project` + `name` at different versions (R2.14a: a current table beside a
      locked baseline), and if both carry `type = "output"` then `by = "type"` asks for two leaves with
      one name. Refuse, name both members with their versions and tags, and point at adding an axis --
      `by = c("type", "release")`, which the vector argument already supports. **The payload stays
      entirely legal; only this projection request is refused.**
      - Rejected: **silently returning the first** is the exact hazard the unnamed top-level member
        list exists to avoid, reappearing where a projection has to name things. **A list-valued leaf**
        makes `dp$output$adsl` sometimes a function and sometimes a list of functions -- type
        instability at the leaf. **Suffixing with the version** was the closest alternative and loses
        on the direction of its failure: leaf names would become a function of whether a collision
        happens, so a script written against a single-version set breaks the day someone adds a
        baseline, silently at authoring time.
      - **This narrows R2.14a rather than contradicting it**, and that requirement has been amended to
        say so. Its "datom takes no position and adds no warning" clause was written when the
        projection lived entirely downstream; once datom builds the projection, "take no position" is
        not available to code that must produce a name. A pure function of `x` plus a caller-supplied
    axis: it stores nothing and takes no position on hierarchy, which is what keeps it inside R4.7
    rather than contradicting it -- ask for `by = c("domain", "type")` and you get a different tree
    from the same object, which is that decision working rather than being violated.
    - **A member missing the axis key goes under `missing`, never silently dropped.** Naming the
      bucket is the whole point; a dropped member is a member the consumer cannot find and cannot see
      is absent.
    - Named `structure`, not `project` / `nest` / `group`: `project` collides with datom's own noun
      for a repo-plus-namespace, and `nest` and `group` both collide with tidyverse meanings that are
      *close but different* -- `nest`'s worst, since its sibling `datom_list_members()` does return a
      data frame, so a tidyverse reader would expect the same here.
    - **Known rough edge, accepted rather than solved here**: the result prints as R's default nested
      list of functions. Add a `print` method only if it actually grates; the leaves at least print
      readably on their own, because Task 10 classes them `datom_link`.
  - **COLD-START AUDIT, 2026-09-15**, run after Task 26 landed and with every claim checked against
    the tree rather than reasoned about. **Startable, and NOTHING IS OPEN.** Ten findings; the two
    scope questions among them were **approved at their stated defaults by the owner the same day** --
    explicitly, so they are decisions rather than defaults that happened to hold. No escalation flag is
    owed (design.md 12 carries E1 and E2 only). **What held**, verified rather than assumed: the link factory really
    does take `(name, kind, version, record)` with the dead `project` argument gone, and `record` is
    on the closure, so `record$id$project` is reachable inside the link core and the project hint can
    live there exactly as this task says; a read member really is `id` plus optional `tags` plus
    `fetch`, built by `.datom_read_set_members()` as `c(record, list(fetch = ...))`, which is the
    shape the third-argument accessor has to handle; `print.datom_set()` really does end with a hint
    naming `x$members[[1]]$fetch(conn)`, so there is one real line to upgrade and it is already
    guarded for a zero-member set; Task 9's fixture really does carry
    `domain = c("safety", "efficacy")` (`tests/testthat/test-write-set.R:798`), so the
    two-branch test has a fixture waiting; and R2.14a really was amended on 2026-09-13 to license the
    collision refusal, so implementing it does not contradict the requirement it narrows.
    1. **THIS TASK'S STATED REASON FOR THE NO-GATE RULE IS NOW PARTLY FALSE, AND THE FIX MADE THE HINT
       STRONGER RATHER THAN WEAKER.** The bullet above says "a reader is never told which string the
       writer used". After Task 26 that is wrong: the writing repo's own project name is recorded in
       per-artifact metadata, and a member's `id$project` is read from there. **The conclusion is
       unchanged and the two tests that pin it stay** -- what makes a gate wrong is the
       **connection's** side of the comparison, which is still a label nobody validated, and that has
       not changed at all. But the sentence must be restated, or a session reading it after Task 26
       concludes the premise was retired along with the defect and adds the gate. Restate as: the
       member's side is now trustworthy, the connection's side is not, and comparing a verified value
       against an unverified one still refuses working reads. The hint's **wording** gets stronger for
       free -- it can say the project the member's own writer recorded, rather than merely the project
       named in the record.
    2. **THE THIRD ARGUMENT CANNOT BE CALLED `name`.** It accepts a name, a member record, or a link,
       so for two of the three shapes the parameter name is a lie, and
       `datom_fetch_member(conn, x, name = m$fetch)` reads as a bug at the call site. Default:
       **`member`**, giving `datom_fetch_member(conn, x, member, tags = NULL, version = NULL)`. It
       reads correctly for all three shapes and matches the noun the rest of the spec uses.
    3. **`datom_list_members()` NEEDS A ZERO-ROW FRAME, AND A ZERO-MEMBER SET IS REACHABLE.** The
       **writer** refuses an empty member list; the **reader** does not -- `.datom_read_set_members()`
       maps over `seq_along()` and returns `list()` for an empty payload, so a hand-built payload or
       one from a future datom reads back with no members. Without an explicit empty path the frame is
       built from zero rows and loses its columns, which is **exactly** the defect that took two
       commits on `datom_list()` during Task 6. Default: a `.datom_empty_member_frame()` beside the
       builder, mirroring `.datom_empty_artifact_frame()` (`R/query.R:16`), with a test that
       `rbind()` of a populated and an empty result works -- the assertion that caught the second half
       of the `datom_list()` defect.
    4. **A `missing` BUCKET NAME CAN COLLIDE WITH A REAL TAG VALUE, and nothing in this task's body
       says what happens.** `missing = "untagged"` produces a leaf **name**, so a set where some
       member genuinely carries `type = "untagged"` merges the real branch and the missing bucket
       into one, silently -- the same class of defect as the leaf-name collision this task already
       refuses, arriving by a different door. Default: refuse it the same way, with the same shape of
       message, naming the axis and the colliding value and pointing at passing a different
       `missing`. One test.
    5. **LONG FORMAT IS ONLY POSSIBLE BECAUSE THE TAG GRAMMAR IS TEXT-ONLY**, which is worth one line
       in the code rather than being rediscovered. `.datom_validate_tag_map()` refuses numbers,
       booleans, `null` and nesting, so a tag value is always a character vector and the `value`
       column is a plain character column with no list-column anywhere. If the grammar ever widened,
       this verb is one of the things that would have to change.
    6. **THE MULTI-VALUE EXPANSION AND THE NESTING ARE THE SAME OPERATION, DONE TWICE.**
       `datom_list_members()` expands one member into one row per tag; `datom_structure_members()`
       with a multi-valued axis expands one member into one leaf per axis value, and with
       `by = c("domain", "type")` it has to expand on the first axis **before** nesting on the second,
       or a two-domain member lands under one domain only. Default: one internal expander, used by
       both verbs, rather than a `split()` in each -- which is also what rules out the silent
       first-value spelling the task warns about, since there is no place left to write it.
    7. **THE COLLISION ABORT CAN NAME VERSIONS FOR FREE.** A read member's `id$version` is the full
       recorded version string (Task 10 made the resolver echo what was recorded), so "name both
       members with their versions and tags" costs nothing and needs no second lookup.
    8. **APPROVED AT ITS DEFAULT 2026-09-15 (was open) -- `datom_fetch_member()` accepts a member with
       no `fetch` on it.**
       That is the **payload** shape: what `.datom_strip_member_links()` produces, and what a caller
       who built a member with `datom_member()` holds. Default: yes, because the accessor keys on
       `id` and nothing else, so it costs a line and keeps read-modify-write symmetric -- the same
       argument that made `datom_write_set()` accept a `datom_set` back. Saying no would mean the two
       verbs disagree about what a member is.
    9. **APPROVED AT ITS DEFAULT 2026-09-15 (was open) -- `datom_list_members()` does NOT carry the
       set's own name and version as columns.** It would make a single frame self-describing when two sets' listings are `rbind()`ed,
       which is a real use for comparing products. Default: no -- one row per member per tag, and the
       set's identity is already on the object the caller passed, so two columns repeating one fact on
       every row is the kind of denormalisation that later disagrees with itself. A caller who wants it
       writes `transform(m, set = x$name)`.
    10. **THREE EXPORTS MEAN THREE `_pkgdown.yml` ENTRIES**, beside `datom_member` /
        `datom_write_set` / `datom_get_set` at `_pkgdown.yml:62-64`, plus the NAMESPACE entries
        `devtools::document()` generates. The spec's own exports table already lists all three against
        this task, so the omission would only show up in `R CMD check`'s pkgdown-adjacent noise, which
        is to say not loudly.
  - _Requirements: R4.3, R4.6, R4.7, R12.3, R18.1, R3.3. Invariants: I10, I25. Properties: P16.
    **Acceptance: none by design** -- these are additions over the read that AC1, AC15 and AC28
    already pin, and no criterion in this spec describes them. Each behaviour named above gets its own
    test instead: the ambiguity abort, the project-mismatch hint, the three accepted third-argument
    shapes, the `NA` row for an untagged member, the `missing` bucket, the two-branch multi-valued
    axis, the leaf-name collision, the `missing`-name collision, and the zero-row frame._
  - _Pathway impact: none -- no new lookup and no new traversal. `datom_fetch_member()` performs
    exactly the reads `datom_read()` / `datom_get_set()` already perform, and the other two verbs do
    no IO at all._
  - **DONE 2026-09-15.** Three exports in the new `R/set-members.R`, one new helper in `R/set.R`, and
    two edits to files that already existed. Tests 3585 -> **3686** (+101), FAIL 0 / WARN 0 / SKIP 0;
    `dev/check-spec.R` 9/9; `R CMD check` 0/0/0 on docs and code/documentation agreement; the four
    affected examples run and their output was read. **The shipped shape**, so a later session does
    not re-derive it:

    | Verb | Signature | Returns |
    |---|---|---|
    | `datom_fetch_member()` | `(conn, x, member, tags = NULL, version = NULL)` | whatever the member points at |
    | `datom_list_members()` | `(x)` | `name`, `project`, `version`, `kind`, `key`, `value` |
    | `datom_structure_members()` | `(x, by, missing = "untagged")` | nested list, `length(by) + 1` deep |

    **ONE CORRECTION TO WHAT THIS TASK'S BODY SAID, because it changes the result rather than the
    wording.** The body describes the grouped view as "group members by the values of the tag key(s)
    named in `by`, with each leaf the member's link", which read alone builds a tree whose leaf name
    is the **tag value** -- and then two members sharing one label collide immediately, which is not
    the collision the task goes on to describe. The example `dp$output$adsl` settles it: the axis
    values are the branches and the **member's own name is the leaf**, so the tree is
    `length(by) + 1` levels deep. That is also what makes the collision the task specifies reachable
    -- two members named `adsl` both tagged `type = "output"` ask for one leaf.

    **SIX THINGS A LATER CHANGE MUST NOT UNDO.**

    1. **There is exactly one expander, it reads a tag map BY POSITION, and both shaping verbs go
       through it.** `.datom_expand_member_tags()` turns a member list into one row per member per
       tag value, and `datom_structure_members()` reads its axis values out of that frame rather than
       doing its own `split()`. The reason is the silent spelling: taking the first value of a
       multi-valued tag puts a member under one branch when it belongs under several, and nothing
       fails. With one expander there is no second place to write it. **The by-position half was
       added by the review below, and it is the half that had actually been got wrong** -- see that
       record for why a by-name read is the same defect one level up.
    2. **The project hint is in `.datom_link_failure()` (`R/set.R`), reached from the link core, and
       it is a hint on failure rather than a check that runs first.** Both halves matter. Putting it
       in `datom_fetch_member()` would miss the route people use, because a leaf of the grouped view
       is a link. Making it a gate would refuse working fetches, because a connection's
       `project_name` is a label nobody validated -- Task 26 made the **member's** side of that
       comparison trustworthy and changed nothing about the connection's side. Pinned from three
       directions: the hint fires through the named verb, it fires through a projection's leaf, and a
       mismatched label alone still fetches successfully.
    3. **When the two project names agree, the original condition is re-signalled with `stop(cnd)`,
       untouched.** Same object, same class. A rewrap that always fires would reword a failure that
       has nothing to do with projects, and callers dispatch on those classes -- the existing
       unresolvable-kind test is what catches it, and there is now a second one asserting the
       re-signal directly.
    4. **`.datom_member_id()` checks only what resolution needs, and deliberately does not call
       `.datom_validate_members()`.** That validator is the write-side contract and refuses an `id`
       field a newer datom added, which the read deliberately carries -- so reusing it here would
       make such a member readable but unfetchable. Reads limp; that rule does not stop at the read
       verb.
    5. **A `missing` bucket name that collides with a real tag value is refused unconditionally**, not
       only when some member currently lacks the axis key. The conditional version works today and
       starts failing the day a member without that key is added -- silently at authoring time, which
       is the direction of failure the leaf-suffix option was rejected for. Two tests: the colliding
       case, and the case where every member carries the key and it is still refused.
    6. **Links are built before the paths are computed.** A member whose `id` cannot be resolved is
       then reported as that, rather than as a branch called `NA` appearing in the view.

    **Also shipped, from the audit's ten findings.** The third argument is `member`, not `name` (2).
    `.datom_empty_member_frame()` mirrors `.datom_empty_artifact_frame()` and the guard is an
    `rbind()` of an empty listing onto a populated one, which is the assertion that caught the second
    half of the same defect in `datom_list()` (3). The `missing`-collision refusal (4). One line in
    the code saying long format is only possible because the tag grammar is text-only (5). One
    expander (6). The collision abort names both members with their versions, free because a read
    member's version is the full recorded string (7). A record with no `fetch` on it is accepted, and
    has its own test (8). No set-name or set-version columns on the listing (9). Three
    `_pkgdown.yml` entries beside the other set verbs (10).

    **Two things added beyond the task body, each with its reason.** `tags` or `version` supplied
    beside a **record or a link** is refused rather than ignored: ignoring it would resolve a
    different version than the one asked for and report success. And `.datom_line_bullets()` builds
    the candidate lists as interpolated **values** rather than as message text, because a tag value
    may legitimately contain a brace and cli reads `{anything}` in message text as markup -- an
    artifact called `dm{1}` would turn the ambiguity message into a cli parse error.

    **REVIEWED after it landed; one finding, accepted and fixed (tests 3686 -> 3697).** A tag map
    carrying the **same key twice** silently lost every label after the first, in all three verbs, and
    the reason is that the one expander read its own input **by name**: `tags[["type"]]` returns the
    first match every time. So `{"type": "output", "type": "baseline"}` listed `output` twice and
    dropped `baseline`, put the member under one branch instead of two, and reported **not found** when
    filtered on a label the document says it carries -- the last of which reads as missing data rather
    than as a bug.

    **It is reachable through the supported read path, which is what makes it a defect rather than a
    hypothetical.** `.datom_validate_tag_map()` is the thing that refuses a duplicate key and it runs
    on **writes only** -- Task 10 settled that a reader validates no tag map -- and `jsonlite` parses
    duplicate JSON keys into two same-named list elements rather than collapsing them, which was
    checked rather than assumed. So a hand edit or a foreign writer delivers one and nothing objects.
    **Not a newer datom**, which an earlier draft of this record claimed: a future format would still
    spell two labels as an array, so there is no version of datom that emits a repeated key.

    **Why the reviewer's framing is right and worth keeping**: this is must-not-undo item 1's own
    hazard arriving through a different door. Having one expander closed the silent-first-match failure
    on the **value** axis; reading that expander's input by name reopened the identical failure on the
    **key** axis, inside the function that exists so there is nowhere left to write it. Item 1 now says
    "by position" for that reason.

    Fixed by iterating `seq_along(tags)` and taking the key from `names(tags)[[i]]`, and by routing
    `.datom_member_has_tags()` through `.datom_tag_pairs()` so a member's tag values have genuinely one
    access path rather than two that agree on well-formed input. Four tests, built from the parsed JSON
    rather than from `list()` so the fixture is the shape that actually arrives. **Probed**: restoring
    the by-name read reddens 5 assertions across 4 tests, and the restore came from a copy taken once
    at a fixed path, never from git.

    Also fixed by the same change, and reported by the reviewer as incidental: a **blank** tag key used
    to come back with an `NA` value, because `tags[[""]]` matches no name and returns `NULL` instead of
    erroring. Confirmed, and it now reports the value that is there.

    **One thing the review checked and left alone, correctly.** `.datom_assign_leaf()`'s
    `!is.list(child)` guard is unreachable while every path is `length(by) + 1` long. It stays: a link
    is a **function**, so were the depth ever to become non-uniform, that line is what stops a member
    being replaced by an empty list.

    **Two edits to existing files.** `print.datom_set()`'s hint now names
    `datom_fetch_member(conn, x, "<first member>")`, and the test that pinned the link form was
    updated with it rather than left to fail. And the comment on the no-gate test in
    `test-get-set.R` still claimed "a reader is never told which string the writer used", which Task
    26 made false; it now states the live reason -- the member's side is verified, the connection's is
    not, and comparing the two still refuses working reads.

- [x] **25. Write-side ergonomics: assembling a set in steps** &nbsp; **[EXECUTES AFTER TASK 10]**
  - **DEPENDS ON TASK 10** for `datom_add_member()` accepting a **link** (the `$fetch` closure with
    its pointer attached), which is what lets a consumer holding only a projection add what they used
    to a new set. Independent of Task 24; the order between the two is free.
  - **Why an additive path when the list form already works.** Not brevity -- the pipe is about the
    same length. Two reasons, both about error handling. **Per-entry validation**: a malformed member
    aborts on the line that caused it, naming that member, rather than after the whole list is built
    and indexed. And the direct form repeats `conn` on **every** member and wraps the whole thing in a
    nested `list()`, which is bracket-heavy enough that a human miscounts. The build-script path keeps
    the direct form; this is the human path, and the multiplicity is accepted because the second way
    catches errors the first cannot.
  - **`datom_assemble_set(conn, name = NULL, tags = NULL)`** -> a draft, classed
    **`datom_set_draft`**. Named `assemble` rather than `new` because "new" is a bare state while
    `assemble` says a whole is being built from parts, which is what the pipe that follows does; and
    not `datom_set(...)`, which reads as a setter. **The draft holds the connection**, and that is
    structural rather than convenient: per-entry validation needs a storage read to learn the
    member's kind, so the draft cannot validate without one. Set-level tags are supplied here rather
    than by a third verb; editing them on a read-back set is `x$tags$description <- "..."`, plain R.
    **A draft is transient and must not be persisted** -- it holds a connection, so the rule that
    connections live in memory only applies to it.
  - **`datom_add_member(x, name, version, tags = NULL)`** -> the draft, one member longer. Validates
    immediately, builds the member record through the same path `datom_member()` uses, and appends.
    **Argument 2 also accepts a member record or a link** in place of a name, through the shape
    dispatch Task 24's resolver uses -- so a script holding a list already can
    `Reduce(datom_add_member, records, init = draft)` without a near-identical plural verb, which is a
    typo hazard rather than a convenience.
    - **THAT SHAPE IS LOAD-BEARING, NOT SUGAR, AND THE CONVENIENCE FRAMING ABOVE UNDERSELLS IT TO THE
      POINT WHERE A LATER SESSION COULD DROP IT** (raised in review of the cold-start audit,
      2026-09-15). A draft holds **one** connection, and a name is resolved through it -- so
      `datom_member()` reads the snapshot, its `schema_version`, its `kind` and the project cascade
      against **that** connection. A member of a *different* project therefore cannot be declared by
      name through a draft at all, and the record shape is the **only** route to a cross-project
      member in a pipe:

      ```r
      datom_assemble_set(conn_a, "product") |>
        datom_add_member("dm", v1) |>                       # this project, by name
        datom_add_member(datom_member(conn_b, "ae", v2))    # another project, only this way
      ```

      One test, and it is not a duplicate of the shape-acceptance test: a draft on connection A
      accepts a member declared on connection B, and the **written payload records B** as that
      member's project.
    - **Do not "fix" this by giving `datom_add_member()` a `conn` argument.** It would give the same
      draft two connections and make "the draft holds the connection" false, which is the property the
      whole verb is built on. The record shape already covers the case, and it covers it with a value
      that is pure data.
    - **`version` stays required**, and this is where the reason has to be stated rather than assumed:
      inferring "current" would leave a build script producing a *different set* on each run from
      byte-identical source. The pin makes the artifact immutable; requiring it makes the **code**
      reproducible, and those are two different guarantees. The refusal names the member and points at
      `datom_history()`.
  - **`print.datom_set_draft()`** -- what is assembled so far and that it is not yet written. Cheap,
    and it is what makes the pipe inspectable mid-build.
    - **It also says the draft holds a connection and should not be saved.** The rule is in this task's
      body, which is not where anyone will read it; the print method is where a user actually meets a
      draft. **It must not print the connection itself** -- `print.datom_conn` masks its token, and a
      message warning about a secret must not reproduce it.
  - **`datom_write_set()`'s first argument accepts a draft**, which already carries its connection,
    its name and its tags -- so the pipe ends `|> datom_write_set()` with no arguments. One overload,
    discriminated by class, documented in one line. Note the gates still run: a draft's name is
    checked against `project.yaml` exactly as a supplied one is.
    - **THIS IS THE SECOND TASK TO WIDEN THAT ARGUMENT, AND IT MUST NOT UNDO THE FIRST.** Task 10
      already makes it accept a `datom_set` -- a set read back, whose members carry a `fetch` field
      that gets stripped when it is a function. This task adds a third accepted shape,
      `datom_set_draft`. Extend the branch; do not replace it. A test asserting all three shapes reach
      the same write is what stops the next widening from dropping one.
    - **`datom_write()` is NOT overloaded to write a set.** Its second argument is a data frame, and
      one verb writing two artifact kinds is the polymorphism refused on the read side for the same
      reason -- the verb should say what it is writing.
  - _Requirements: R12.2, R10.3a, R2.14, R4.2, **R4.2a (version required at write, never inferred)**. Invariants: I15, I26. **Acceptance: none by design** --
    the payload this path produces is byte-identical to the direct form's, which AC2, AC5, AC27 and
    AC29 already pin; what is new is *where an error surfaces*, and no criterion describes that. Tests
    instead: the missing-version abort names the member, a malformed tag map aborts at its own
    `datom_add_member()` call, the draft and the direct form produce the same `data_sha`, and a draft
    written through the gates is refused on a non-product repo exactly as a direct write is._
  - _Pathway impact: none -- the write card's sequence is unchanged; this adds a second front door to
    it._
  - **COLD-START AUDIT, 2026-09-15**, run after Task 24 landed, every claim checked against the tree
    rather than reasoned about. **STARTABLE. Ten findings, ONE that must be decided before the first
    line is written** -- it has a stated default, so a cold session is not blocked, but taking the
    wrong branch means writing the widening twice. No escalation flag is owed: design.md section 12
    carries E1 (Task 2) and E2 only.

    **What held**, verified rather than assumed: `datom_member()` really does take
    `(conn, name, version, tags = NULL)` with `version` required and SHA-validated, so "version stays
    required" needs no new refusal, only its message; `datom_write_set()` really does already branch
    on `inherits(members, "datom_set")` (`R/set.R:910`) and strip `fetch` only when it is a function,
    so the read-back shape is live and testable; Task 24's `.datom_member_record()` really does
    dispatch on link / list-with-`id` / name, so the shape-dispatch half this task wants exists; and
    `datom_add_member()` accepting a link really is reachable, because a link carries its own record
    as an attribute.

    1. **THE ONE TO DECIDE FIRST: "`datom_write_set()`'s first argument" IS NOT THE ARGUMENT TASK 10
       WIDENED, AND THE TASK BODY CONFLATES THEM.** The signature is
       `datom_write_set(conn, members, tags = NULL, name = NULL, message = NULL)` -- the **first**
       argument is `conn`, and Task 10 widened the **second**, `members`. So "this is the second task
       to widen that argument... extend the branch, do not replace it" points at a branch that is not
       the branch this task touches, and "a test asserting all three shapes reach the same write"
       spans two different parameters. The pipe sentence is what settles it: `|> datom_write_set()`
       with no arguments puts the draft in the **`conn`** position. Default: **widen `conn`, leave
       `members`'s existing `datom_set` branch exactly as it is, and say in one comment that these are
       two independent widenings on two parameters.** Two accepted shapes for `conn`, two for
       `members`, and the test asserts three *routes* to one write -- plain list, `datom_set`, draft --
       rather than three shapes of one argument.
    2. **UNPACK THE DRAFT BEFORE THE THREE GUARDS AT THE TOP OF `datom_write_set()`.** Those guards
       are `inherits(conn, "datom_conn")`, `conn$role != "developer"` and `is.null(conn$path)`
       (`R/set.R:878-895`). A draft in the `conn` position fails the first one, so a pipe would abort
       with "conn must be a datom_conn" -- naming the argument the user never typed. The unpack has to
       come first, and it also supplies `name` and `tags`, which the gate below then uses.
       - **`members` IS MISSING ON THAT CALL, NOT `NULL`, AND THE DIFFERENCE BITES** (raised in review,
         2026-09-15). `datom_write_set(draft)` leaves `members` with no value and the formal has no
         default, so **`is.null(members)` errors** with `argument "members" is missing, with no
         default` -- verified. `is.null()` is the spelling somebody will reach for and it fails on the
         correct call rather than the incorrect one. The test is `missing(members)`, and nothing may
         evaluate `members` before the rebind.
       - **The `conn` guard's own message goes stale with the widening** and must be updated in the
         same edit, not after. It currently says `conn` must be a `datom_conn` from
         `datom_get_conn()`, which becomes wrong the moment a draft is legal there -- and it is the
         message a mistyped pipe lands on, so it is the one that most needs to name both accepted
         shapes.
    3. **THE SECOND ARGUMENT OF `datom_add_member()` CANNOT BE CALLED `name`** -- the identical finding
       Task 24 raised about `datom_fetch_member()`, approved there and shipped as `member`. It accepts
       a name, a record **or** a link, so for two of three shapes the parameter name is a lie and
       `datom_add_member(draft, name = m$fetch)` reads as a bug at the call site. Default:
       **`datom_add_member(x, member, version = NULL, tags = NULL)`**.
    4. **`version` AND `tags` BESIDE A RECORD OR A LINK MUST BE REFUSED, NOT IGNORED**, which is why
       `version` becomes `NULL`-defaulted in finding 3 rather than staying positional-required. A
       record already carries its own version and tags; silently preferring one over the other would
       add a member pinned to a version the caller did not ask for. Task 24 shipped exactly this
       refusal (`.datom_member_record()`'s `from_object()`), and its wording is name-lookup specific,
       so this task needs its own message rather than that one.
    5. **"THE SAME ACCESSOR TASK 24'S RESOLVER USES" DOES NOT FIT AS BUILT, AND CALLING IT ANYWAY
       SEARCHES THE WRONG THING.** `.datom_member_record(members, member, tags, version)` resolves a
       name **within a set's existing member list**. In `datom_add_member()` a name means "look this
       artifact up in the project's storage" -- that is `datom_member(conn, name, version, tags)`.
       Passing the draft's accumulated members would look the new name up among members already added.
       Default: **extract the shape dispatch** (link -> its record; list with `id` -> itself; string ->
       hand back to the caller) into one small helper both verbs call, leaving the name **lookup**
       different in each because it genuinely is.
    6. **`print.datom_conn` DOES NOT MASK A TOKEN -- IT IS AN ALLOWLIST THAT NEVER REACHES ONE.** The
       task's premise is wrong. That method emits one `cli_li()` per **named** field -- project, role,
       backend, data root, data prefix, data region, governance and its three, endpoint, path, repo URL
       (`R/conn.R:230-280`) -- and never iterates the connection, so `github_pat` is not omitted by a
       rule, it is simply never named. The **conclusion stands** -- the draft's print method must not
       print the connection -- but the reason has to be stated as an allowlist, for the same reason
       identity hashing is an allowlist here: **a credential field added to `datom_conn` later cannot
       leak through it.** Redaction would have to be taught each new secret; an allowlist is safe by
       default. So this must not be "fixed" into masking, and the draft's own print method follows the
       same shape -- name what it shows, never hand it an object to summarise. Stated because "masks
       its token" sends an implementer looking for a masking helper that does not exist, and inventing
       one is how a token reaches output.
    7. **A DRAFT DELIBERATELY HOLDS A CONNECTION, WHICH INVERTS TASK 10'S PURITY RULE**, and the two
       must not be reconciled. Task 10's guard is a test that a serialized member contains **no**
       token; a draft holds a live connection on purpose, because per-entry validation needs a storage
       read. So: no purity test for a draft, the print method warns instead, and if a test ever
       `saveRDS()`es one the fixture's fake token in the bytes is expected rather than a leak.
    8. **PER-ENTRY VALIDATION COSTS ONE STORAGE READ PER `datom_add_member()` CALL**, because that is
       what `datom_member()` does (`.datom_storage_read_json()` on the version's snapshot). Not a
       regression -- the direct form makes the same n reads -- but a cold session should know a
       50-member draft is 50 round trips, and that `datom_write_set()` must **not** re-read them when
       the draft arrives.
    9. **A DRAFT AND A `members` ARGUMENT TOGETHER MUST BE REFUSED.** With the draft in the `conn`
        position, `members` is still a formal argument, so `datom_write_set(draft, some_list)` parses.
        Silently preferring either one writes a set the caller did not describe. Same shape as finding
        4, one test.
    10. **THREE EXPORTS MEAN THREE `_pkgdown.yml` ENTRIES** -- `datom_assemble_set`,
        `datom_add_member`, `print.datom_set_draft` -- beside the six set entries now at
        `_pkgdown.yml:62-67`, plus the NAMESPACE lines `devtools::document()` generates. Task 24's
        equivalent finding was real: nothing in the suite catches the omission.
  - **DONE 2026-09-16.** Three exports in the new `R/set-draft.R`, one helper extracted into
    `R/member.R`, and two edits to files that already existed. Tests 3697 -> **3770** (+73),
    FAIL 0 / WARN 0 / SKIP 0; `dev/check-spec.R` 9/9; `R CMD check` 0/0/0 on docs and
    code/documentation agreement; every example runs and the new one's output was read. **The
    shipped shape**, so a later session does not re-derive it:

    | Verb | Signature | Returns |
    |---|---|---|
    | `datom_assemble_set()` | `(conn, name = NULL, tags = NULL)` | a `datom_set_draft` with no members |
    | `datom_add_member()` | `(x, member, version = NULL, tags = NULL)` | the draft, one member longer |
    | `print.datom_set_draft()` | `(x, ..., n = 20L)` | invisibly `x` |
    | `datom_write_set()` | `conn` now also accepts a draft | unchanged |

    **THE ONE THAT HAD TO BE DECIDED FIRST WAS TAKEN AT ITS DEFAULT, AND THE AUDIT WAS RIGHT THAT
    THE TWO WIDENINGS ARE TWO PARAMETERS.** `conn` accepts a `datom_set_draft`; `members` keeps its
    `datom_set` branch untouched. So the test asserts three **routes** to one write -- a plain
    list, a set read back, and a draft -- and all three produce the same `data_sha`, which is what
    stops a later change collapsing the two branches into one and dropping a route.

    **FIVE THINGS A LATER CHANGE MUST NOT UNDO.**

    1. **The draft is unpacked before the three guards at the top of `datom_write_set()`, and the
       test for a supplied `members` is `missing()`.** Both halves were audit findings and both are
       real. A draft reaching `inherits(conn, "datom_conn")` aborts naming an argument the user
       never typed; and on the correct call, `datom_write_set(draft)`, the `members` formal has no
       value and no default, so `is.null(members)` errors with R's own "argument is missing" on the
       call that is right rather than the one that is wrong. Nothing may evaluate `members` before
       the rebind.
    2. **`datom_add_member()` has no `conn` argument, and adding one would end the verb.** The
       draft holds one connection because validating a member as it is added means reading that
       artifact's snapshot; a second connection on one draft makes "the draft holds the connection"
       false. The cross-project case is already covered, by a **record** built on the other
       project's connection -- which is a capability, not sugar, and has its own test asserting the
       written payload records the other project. The by-name route is asserted to fail there in the
       same test, which is what makes the record shape's necessity visible rather than claimed.
    3. **The shape dispatch is `.datom_member_shape()` in `R/member.R`, shared with Task 24's
       accessor; the name LOOKUP is deliberately not shared.** A name means "a member of this set"
       to `datom_fetch_member()` and "an artifact in this project's storage" to
       `datom_add_member()`, so a shared lookup would search the wrong thing on one of the two
       routes -- the audit's finding 5, confirmed by reading both call sites. Each verb words its
       own refusal of `version` / `tags` beside a record, for the same reason: one is narrowing a
       search, the other is declaring a member twice.
    4. **The print method names every field it shows and is handed no object to summarise.** Same
       allowlist shape as `print.datom_conn`, which does **not** mask a token -- it never reaches
       one, because it emits one line per named field. There is no masking helper, and inventing one
       would have to be taught every future secret. The test puts a recognisable token on the
       fixture's connection and asserts it is absent from the output, so the assertion is not
       vacuous.
    5. **A draft holds a live connection on purpose, which inverts the purity rule members and
       links follow.** There is no serialize-and-search-for-a-token test for a draft; the print
       method's warning is the guard, and it is asserted.

    **Also shipped, from the audit's ten findings.** The second argument is `member`, not `name`
    (3). `version` or `tags` beside a record or a link is refused rather than ignored, with its own
    message and its own class (4). A draft together with a `members` argument is refused (9). The
    `conn` guard's message now names both accepted shapes, and there is a test on it, because it is
    what a mistyped pipe lands on (2). Three `_pkgdown.yml` entries beside the other set verbs
    (10). Per-entry validation still costs one storage read per call, and the write does **not**
    re-read them when a draft arrives (8).

    **Three things added beyond the task body, each with its reason.** Set-level tags are validated
    when the draft is **opened** rather than only at the write, which is the same argument the task
    makes for members -- a malformed description aborts on the line that wrote it. A record added
    to a draft goes through `.datom_validate_members()` there and then, which is the write-side
    contract run per entry and the whole point of the path; note this is deliberately the opposite
    of `.datom_member_id()`'s read-side leniency, because refusing early is correct on a write.
    And the draft's name and tags are **defaults** rather than overrides -- an explicitly supplied
    `name` or `tags` wins, matching what the `datom_set` branch already does with a read set's
    tags, so a draft can be written under different labels without being rebuilt.

    **One thing a test had to state differently than expected, and it is a fact about the write
    rather than about this task.** A member record that has been through a write and a read comes
    back with its four `id` keys in **alphabetical** order, because the write canonicalises them
    (Task 9's review). So the test that a link, a read member and a fresh record all reach the same
    pointer compares the four fields by name instead of comparing records with `identical()`. The
    hash does not depend on key order and the write re-canonicalises, so nothing is wrong -- but an
    `identical()` assertion there fails for a reason that has nothing to do with this path.

  - **REVIEWED after it landed; one finding, accepted and fixed (tests 3770 -> 3781).** A draft's
    printed member count could disagree with what the write produced, and the reviewer's framing of
    why it matters *more here than in the list form* is the part worth keeping: a list is one
    expression, so "reported once the whole list is built" is where the caller already was -- but
    this path exists so errors land on the line that caused them, and its print method is what makes
    a pipe inspectable mid-build, so the count is the one number a caller trusts.

    **Two mechanisms in the write that did not know about the draft.**
    `.datom_order_set_members()` drops an **exact** repeat -- same `id` *and* same tags -- silently,
    because the digest it dedupes on covers tags. So forty `datom_add_member()` lines with one
    accidental repeat printed 40 and wrote 39, with nothing said about the drop. The same `id` with
    **different** tags survives that dedup and is refused by `.datom_check_set_payload()`, which
    names the member but cannot name which of the forty lines introduced it.

    **Both now settle at the add, and the two cases are deliberately answered differently.** An
    exact repeat is **skipped, with an info message** -- not refused, because refusing would make a
    draft stricter than the equivalent list, and `Reduce(datom_add_member, records, init = draft)`
    over a generated list that happens to repeat would start failing where it works today; and not
    skipped in silence, because that moves the surprise rather than removing it. A same-version
    disagreement **aborts**, naming both label sets, reusing the write's own
    `datom_set_member_conflict` class so a caller dispatches on the rule rather than on the site.
    The draft is left untouched in both cases.

    **ONE THING THE FIX OVER-CLAIMED, CAUGHT BY PROBING RATHER THAN BY READING, AND THE CORRECTION
    IS THE REUSABLE PART.** The first version tidied the record on the way in and said both sides
    had to be tidied before they were digested, or `domain = c("a", "b")` and `c("b", "a")` would
    read as a conflict. Removing that tidy reddened **nothing**. The reason: `.datom_sv1_map()`
    sorts a map's keys and `.datom_sv1_strset()` encodes each value as a sorted, deduplicated set,
    so the digest is already blind to every spelling the write's tidy step collapses. The tidy was
    therefore doing nothing for the guarantee while changing what a caller reads back out of a
    draft, and it is gone. What **is** load-bearing is comparing digests rather than records:
    swapping `identical(digest(a), digest(b))` for `identical(a, b)` reddens exactly the reordered
    labels test, because that spelling refuses input the write accepts.

    **Two probes, both from a copy taken once at a fixed path and never from git.** Removing the
    skip reddens 5 assertions across 2 tests; the `identical()` spelling reddens 1.

    **Not extended to self-reference, and the reviewer was right to say so**: a draft's name may be
    `NULL` until `project.yaml` resolves it at the write, so a draft cannot know whether a member is
    itself. That check stays where it is.

    Also from the review: the empty-set refusal pointed only at `datom_member()`, which is the wrong
    verb for anyone who arrived through a draft -- it now names `datom_add_member()` as well.

    **What the reviewer verified rather than assumed, recorded so it is not re-derived**:
    `.datom_check_set_payload()` uses `project` only for the self-reference check, so a foreign
    member is not refused at the write and the cross-project capability works end to end rather than
    only at the add; `.datom_validate_members()` really does refuse an unknown top-level key, so a
    hand-built `fetch = "junk"` really does reach it; `.datom_member_shape()` really is shared by
    both entry points; and `print.datom_set_draft()` really does read named fields off `x$conn`
    without iterating it.

---

## Phase G -- The recorded project name **[appended; DONE 2026-09-15; ran before Task 24]**

**Appended rather than inserted, so nothing renumbers**, for the third time and the same reason.

**Why it runs next rather than later, and this is the whole scheduling argument.** What the change
costs is a **writer** upgrade for everyone sharing a repo -- an older build either recomputes identity
around a field it cannot classify (every release before this spec hashes by exclusion) or refuses
outright (every build after it, Task 21's vocabulary check). **This release already forces exactly
that upgrade**, because the artifact-namespace rename does. So the field is free inside this release
and costs a second fleet-wide upgrade in the release after it -- for a fix to a **citation**, which is
the kind of thing nobody schedules a forced upgrade for on its own. Free of upgrade tax, not of
effort: it delays Tasks 24, 25, 23 and 11 onward by one chunk. **Task 21 is the constraint, not the
vehicle**: it is done, and its check is *why* a late addition costs what it costs.

- [x] **26. A project name in a stored document comes from the repo, not from a connection label**
  - **THE DEFECT, stated so it is not mistaken for tidying.** `conn$project_name` is not a verified
    fact. On a **developer** connection it is read from the clone's `.datom/project.yaml`, so it is
    the repo's own declaration. On a **reader** connection it is a string the caller passes to
    `datom_get_conn()`, and nothing compares it against the repo: the namespace comes from the store's
    root and prefix. Verified end to end -- a reader labelled `"a-label-nobody-validated"` reads a set
    written by project `set-project` and fetches its members correctly. Two things then carry a name
    nobody checked: `datom_get_set()` reports it as the set's `project`, one of the four facts the
    result exists to make **citable**; and `datom_member()` writes it into `id$project`, where it
    enters a stored payload, is hashed into that set's `data_sha`, and is cited afterwards --
    **durable wrong data in a citable artifact, invisible to every hash and every validator.**
  - **What a wrong name does depends on the store shape**, read out of
    `.datom_resolve_data_location()` (`R/ref.R`): with **no governance** the function returns before
    the name is validated, so a wrong one is silent; with **governance plus a located store** an
    unresolvable ref warns "Proceeding with store-configured data location" and the connection
    succeeds; with **governance plus a credentials-only store** there is no fallback location and it
    aborts. And the case worse than all three: a wrong name that **matches another registered
    project** resolves that project's `ref.json`, and when the locations differ the connection is
    repointed at the other namespace with only a "Data has been migrated" warning -- a typo reads a
    different project's data while the warning blames a migration. Read-verified in `R/ref.R` and
    `R/conn.R:1159-1163`, not reproduced on a fixture; **reproducing it is part of this task**, since
    it is the one case that returns wrong bytes rather than a wrong label.
  - **THE RULE, and it names no artifact kind**: *a project name that enters a stored document comes
    from the manifest of the namespace the artifact lives in -- never from a label on the connection.*
    A set is not addressed differently and has no manifest of its own; it is a row in its project's
    manifest with `kind = "set"`. So set-in-set membership is covered by the same code path with no
    extra clause.
  - **What makes the fix real rather than laundering the same label: a write always has a clone.**
    Every write path requires `conn$path`, so on the write side the name comes from `project.yaml`.
    The unverified case is reader labels only, which is why recording the name at write time is
    enough and why nothing needs to be re-derived on read.
  - **THE CHANGE, as one commit.**
    1. **`project` is written into per-artifact metadata** by **both** builders --
       `.datom_build_metadata()` and `.datom_build_set_metadata()` (`R/read_write.R`) -- sourced from
       the writing repo's own configuration.
    2. **Classified `excluded` in the same change**, in `.datom_metadata_excluded_fields`
       (`R/utils-sha.R`). Never earlier: a name classified before a builder emits it is invisible to
       the carry-forward rule, which rescues only names a build cannot place, so a document arriving
       from a newer datom with that field would lose it on rewrite -- the trap Task 7's `document_sha`
       review found. The write-side vocabulary needs no separate edit, because
       `.datom_metadata_known_fields()` is the union of the two classification lists.
    3. **`datom_member()` reads it with the cascade** recorded field on the artifact's own snapshot ->
       the namespace manifest's `project_name` -> the connection's label **marked unverified in the
       message**. It already reads the snapshot, so the common case costs nothing; the manifest read
       is one GET and only for an artifact written before the field existed.
    4. **`datom_get_set()`'s cascade stops one step earlier**: recorded field -> connection label.
       **It must not read the manifest.** The data path never touches that document -- which is the
       reason the artifact-namespace rename was a discovery-only break, since a stale build still
       reads data -- and a manifest read there would put a derived, rebuildable, possibly too-new
       document in a read path that today cannot fail for its sake. The asymmetry is deliberate: one
       value is durable and hashed, the other is an echo for display.
  - **`project` IS NOT IDENTITY, and that is settled rather than open** (2026-09-14). Identical bytes
    in two projects **should** share a version -- that is what content addressing is for -- and a
    wrong-connection fetch that returned identical bytes returned the **right** bytes. The defect is a
    wrong citation, not a wrong identity. Making it identity is a one-way door with a fleet-wide
    re-mint behind it. So: excluded, and **no version moves for any existing artifact**, which is the
    opposite of what `kind` cost in Task 7 and is worth asserting rather than assuming.
  - **Two forcing functions fire, and neither is a test to update.** The classification test in
    `test-utils-sha.R` derives its field inventory from the builders, so it fails until `project` is
    classified -- that is where the decision gets made. And the vocabulary test in
    `test-forward-compat.R` asserts every field a real write produces is on the known list, which the
    union above satisfies; if it does not, the classification step was missed rather than the test
    being wrong.
  - **One existing test must be INVERTED, deliberately, and a cold session must not read it as a
    regression.** `test-get-set.R`'s "the set's project is the connection's label; a member's is
    recorded" pins today's behaviour, which this task changes: after it, a mislebelled reader gets the
    **recorded** name. Rewrite that test to assert the new behaviour and keep its comment explaining
    why the two facts were once of different quality. **Do not touch** its sibling, "a link does not
    gate on the connection's project name" -- that one stays true and stays needed, because the
    connection's label remains unverified even once the recorded name exists.
  - Tests: the field appears in a written `metadata.json` for a table **and** for a set (asserted on
    the bytes, since the field set is what matters); the version of an existing artifact does **not**
    move when the field is added; a member declared through a mislabelled reader connection records
    the repo's name rather than the label; the cascade's middle step is exercised by an artifact whose
    metadata predates the field; the fallback to the connection label says in its message that the
    value is unverified; and the set read still touches exactly two documents, which
    `test-get-set.R` already pins.
  - **COLD-START AUDIT, 2026-09-14** -- written the same day as the task, and every claim in the body
    checked against the tree rather than reasoned. **Startable. Nine findings, two of them OPEN scope
    questions, each marked with the default it takes if nobody answers.** No escalation flag is owed
    (design.md 12 carries E1 and E2 only). **What held**, verified rather than assumed: a developer
    connection's `project_name` really is read from the clone's `project.yaml` (`R/conn.R:939`), which
    is what makes recording it at write time a fix rather than laundering the same label; both write
    paths reach one builder call, because `datom_sync()` routes through `datom_write()`
    (`R/sync.R:622`); and the classification test really does derive its inventory from **both**
    builders and really does have a converse arm, so neither half of "write it and classify it" can be
    skipped (`tests/testthat/test-utils-sha.R:1080-1137`).
    1. **NEITHER BUILDER CAN SOURCE THE NAME ITSELF.** `.datom_build_metadata()` and
       `.datom_build_set_metadata()` take no connection -- by design, since they are pure -- so the
       change is a new argument on each plus the two call sites that fill it
       (`R/read_write.R:1243`, `R/set.R:964`). **The new argument goes LAST in the signature**:
       existing tests call `.datom_build_metadata(df, "sha", ...)` positionally in a dozen places, so
       an argument inserted in the middle silently shifts `custom` into `table_type`.
    2. **OPEN (default: yes, same commit) -- THE SAME DEFECT IS IN LINEAGE, AND THERE THE LABEL IS
       INSIDE IDENTITY.** `datom_parent()` records `source = conn$project_name` (`R/lineage.R:190`)
       from a connection scoped to the **parent's** project, with **no role check** -- so a reader
       connection's arbitrary label lands in `parents`, and `parents` and `source_lineage` are both in
       `.datom_metadata_identity_fields`. A wrong name there changes a **version**, not just a
       citation, which makes it the worse instance of the same one-line defect. Default: fix it in the
       same commit with the same cascade, because leaving it makes this half a fix and the two are one
       line each. State in NEWS that a table whose parents were declared through a mislabelled
       connection mints one new version at its next write -- the correct outcome, since the recorded
       name was wrong, but it must not arrive as a surprise. **Not affected and verified so**:
       `R/sync.R:616` builds a self-lineage entry from `conn$project_name` too, but that path requires
       a developer connection with a clone, so the name is already the repo's declaration.
    3. **"EXACTLY SEVEN FIELDS" IS STATED IN SIX PLACES AND PINNED BY A TEST.** Adding `project`
       makes a set's metadata eight: R1.3, R1.3's acceptance clause, `design.md:155`, `design.md:157`,
       the F4 row at `design.md:1238`, `.datom_build_set_metadata()`'s roxygen in two places
       (`R/read_write.R:385`, `R/read_write.R:422`), and
       `tests/testthat/test-write-set.R:790` ("a written set's metadata carries exactly seven
       populated fields"). A session that changes the builder and not the record produces something
       that reads as a contradiction of the spec. Update all of them in the same commit; the count is
       the thing that goes stale, so prefer wording that names the fields over wording that counts
       them.
    4. **OPEN (default: use the gated reader) -- THE MANIFEST FALLBACK IS NOT NECESSARILY ONE GET.**
       `.datom_read_manifest(conn, scope = "storage", operation = "read")` can enter the rebuild
       path, which lists the whole namespace recursively and warns once, so the cheap-fallback framing
       is wrong for an unusable manifest. The alternative is a raw `.datom_storage_read_json()` on
       `.metadata/manifest.json`, which is genuinely cheap and takes a value out of a document whose
       format this build has **not** checked -- exactly what the schema gate exists to prevent.
       Default: the gated reader, accepting the listing in the degraded case, since that case also
       means the repo needs attention anyway.
    5. **THE MANIFEST STEP IS THE COMMON PATH IN THIS RELEASE, NOT A RARE ONE.** Every artifact
       written before this task lacks the field, so the cascade's middle step is what gets a
       **cross-project** member right for the whole existing population. It is a no-op for a developer
       connection, whose label is already the repo's declaration -- so the step earns its place only
       on the reader-declared cross-project case, which is precisely R18.1's case.
    6. **`project` ON THE EXCLUDED LIST MOVES NO VERSION, AND THAT NEEDS ASSERTING RATHER THAN
       ASSUMING**, because it looks exactly like `kind`, which moved every version in Task 7. The
       difference is the classification, not the shape of the edit. One test: an existing artifact's
       version before and after the field exists.
    7. **ONE TEST TO INVERT, ONE TO LEAVE ALONE**, confirmed by name.
       `test-get-set.R`'s "the set's project is the connection's label; a member's is recorded" pins
       today's behaviour and must be rewritten to assert the recorded name. Its sibling, "a link does
       not gate on the connection's project name", stays exactly as it is -- the label remains
       unverified even once a recorded name exists, so the no-gate rule is unaffected.
    8. **THE DISPLAY SITES ARE DELIBERATELY NOT IN SCOPE.** `datom_summary()`, `datom_status()` and
       `print.datom_conn()` keep showing the connection's label, because that is what they are
       reporting -- the connection. Stated so a reader does not take their absence for an oversight.
    9. **THE WORST CASE IS STILL UNREPRODUCED.** The gov-plus-located-store path where a wrong name
       matches another registered project, and the connection is repointed at that namespace with a
       migration warning, is read-verified only (`R/ref.R`, `R/conn.R:1159-1163`). It is the one case
       that returns **wrong bytes** rather than a wrong label, so a fixture for it is worth the cost
       -- and if it turns out not to reproduce, that finding is worth more than the test.
  - _Requirements: none -- this task comes from the Task 10 review round rather than from #89, and no
    requirement in this spec describes where a project name comes from. **Acceptance: none by
    design**; the criteria are the tests above. R9.4's identity-versus-provenance distinction is what
    the excluded classification rests on, and R18.1 is why a cross-project member's recorded name
    matters at all._
  - _Pathway impact: yes -- the set read card gains the cascade, and the write cards gain the field.
    Neither route shape changes: no new lookup on the read path, and one conditional GET on the
    declaration path._
  - **DONE 2026-09-15.** Tests 3557 -> **3585**, FAIL 0 / WARN 0 / SKIP 0; `dev/check-spec.R` 9/9.
    **What shipped**, in the order a reader meets it:
    1. **`project` is written by both builders**, `.datom_build_metadata()` and
       `.datom_build_set_metadata()` (`R/read_write.R`), from `conn$project_name` at the two call
       sites -- which on a write is the clone's `.datom/project.yaml`, because every write path
       requires a clone.
    2. **Classified `excluded`** in `.datom_metadata_excluded_fields` (`R/utils-sha.R`), in the same
       change, never earlier.
    3. **One cascade, two callers.** `.datom_declared_project()` (`R/member.R`) is what
       `datom_member()` and `datom_parent()` both use: recorded field -> namespace manifest via the
       gated reader -> connection label with a warning.
    4. **`datom_get_set()` uses a two-step cascade of its own**, `.datom_set_project()` (`R/set.R`),
       which does not read the manifest.
    - **FIVE THINGS A LATER CHANGE MUST NOT UNDO.**
      1. **The field is assigned AFTER the builder's `list()`, never inside it.** Inside, a caller
         who supplies no name gets `project = NULL`, and `jsonlite` writes a NULL element as `{}` --
         an empty object where a project name belongs, on disk, unciteable. Outside, the field is
         simply absent, because assigning NULL to a list element removes it. Pinned by a test that a
         builder call with no name **omits** the key; probed by writing the inside-the-list spelling,
         which reddens it. **Two claims in this task's audit were wrong here and are corrected rather
         than repeated.** The `if (!is.null(project))` guard is *not* the mechanism -- with the
         assignment outside the list, dropping the guard changes nothing, which the first probe showed
         by reddening zero assertions. And "last in the signature or a dozen positional test calls
         shift silently" does not hold: every caller passes `data` and `data_sha` positionally and
         everything else by name, so moving the argument ahead of `custom` reddens **nothing**. Last
         is a convention here, not a guard, and the roxygen now says so.
      2. **`.datom_get_set()` must not gain the manifest step.** The data path never touches
         `.metadata/manifest.json` -- which is why the artifact-namespace rename was a
         discovery-only break -- and a manifest read there puts a derived, rebuildable, possibly
         too-new document into a read path that today cannot fail for its sake. Pinned by a test that
         records every storage key the set read touches and asserts none of them is the manifest.
      3. **The unverified warning is suppressed for a connection built from a clone**, because there
         the label *is* the repo's declaration and calling it unverified would be a wrong statement.
         The condition is `role == "developer" && !is.null(path)`, which is exactly what makes
         `project_name` come from `project.yaml`.
      4. **The member link still does not compare the member's project against the connection's.**
         Recording the writer's name makes the member's side trustworthy; the connection's side is
         still a label nobody checked, so the comparison would still refuse working reads. The Task 10
         test that pins this stays exactly as it was.
      5. **The field set of a set's metadata is named, never counted.** "Exactly seven" was in six
         places (R1.3, its acceptance clause, two spots in design section 4, the F4 row, and the set
         builder's roxygen twice) plus a test name. All rewritten to list the fields, so the next
         addition costs one edit rather than seven.
    - **ONE TEST INVERTED, DELIBERATELY.** `test-get-set.R`'s "the set's project is the connection's
      label; a member's is recorded" became "both the set's project and a member's come from the repo,
      not the label", with its comment explaining that the two facts were once of different quality and
      are no longer. Its sibling, "a link does not gate on the connection's project name", is
      untouched.
    - **THE WORST CASE REPRODUCES, AND THIS TASK DOES NOT FIX IT.** Finding 9 was read-verified only:
      a gov-attached **reader** whose project name matches a different registered project resolves
      that project's `ref.json`, and when the locations differ the connection is repointed at the
      other namespace. Built as a fixture with two real local projects and a governance store holding
      only the second one's `ref.json`: the connection is repointed, and `datom_read(conn, "dm")`
      returns the **other project's rows**, with a warning that says the data was *migrated* -- which
      is what a genuine migration says, so the message does not distinguish the two. The same
      mistyped name with **no** governance store reads correctly, because the name is then never used
      to resolve a location. Both halves are asserted in `test-ref.R` as a **characterization** test,
      labelled as such: recording the writer's name fixes what goes into a document, and this is a
      wrong name steering a **connection**, which is a different failure with a different fix.
      **Deliberately unfiled, and its home is `dev/datomanager_overview.md` section 4a** (owner
      decision, 2026-09-15). Nothing in datom can arm it -- `.datom_create_ref()`, which writes a
      project's location record, has no caller left in the package since attachment moved to
      `datomanager` -- so it is a constraint on a resolver nobody has built rather than a datom bug
      awaiting a patch, and it sits directly beneath the section that states the enabling rule.
    - **ONE GAP LEFT OPEN, NAMED IN THE CODE.** When the manifest has to be reconstructed and the
      document it replaced recorded no project name, the reconstruction fills that field from the
      connection (`.datom_rebuild_manifest()`), so the cascade's middle step can hand back the label
      while looking like the repo's declaration. What is lost is the **warning**, not the value: the
      string is the one the third step would have returned anyway. Closing it properly means the
      shared manifest reader reporting whether the document it returned was reconstructed, which is a
      change to that reader rather than to the cascade.
    - **BOTH FORCING FUNCTIONS FIRED AS DESIGNED**, and neither was weakened: the classification test
      in `test-utils-sha.R` failed until `project` was classified, and the "nothing is classified
      before something writes it" arm failed until the builder fixture emitted it. Three assertions
      were added rather than adjusted: the two goldens **did not move** (an excluded field cannot move
      them), and one test compares a document's `metadata_sha` with and without the field, for a table
      and for a set.
    - **NINE PROBES, AND TWO OF THEM ARE THE VALUABLE ONES BECAUSE THEY CAUGHT NOTHING.** Each guard
      was broken on purpose and the reddening counted, not reasoned about:

      | Deliberate defect | Reddens |
      |---|---|
      | `project = project` inside the set builder's `list()` (the `{}` spelling) | 1 assertion |
      | the argument moved ahead of `custom` | **0 -- the audit's reason was wrong** |
      | the cascade's first step returns `conn$project_name` | 6 assertions in 6 tests |
      | the manifest step removed from the cascade | 2 |
      | the unverified warning removed | 2 |
      | `datom_get_set()` reads the manifest for the name | 3 |
      | `datom_parent()` left on the connection's label | 3 |
      | `project` classified as identity | 4 assertions in 2 tests |
      | `project` left unclassified | 1 |

    - **ONE PROCESS FAILURE, AND IT IS A NEW VARIANT OF THE RULE TASK 10 WROTE.** Task 10's rule --
      a probe harness restores from a copy it made itself, never from git -- was followed. What broke
      instead: the harness crashed mid-probe leaving the tree mutated, and the **re-run took a fresh
      backup from that mutated tree**, so a second probe was layered on top of the first and the
      "pristine" copy recorded a defect as correct code. Two probes ended up applied at once and
      `R/read_write.R` had to be repaired by hand; the suite was back to 3585 with 0 failures before
      anything else was done. The harness now takes its backup **once, at a fixed path, and only from
      a tree that parses**, and reuses it on a re-run. Added to `dev/engineering-notes.md`.
  - _Also corrected while closing this task: the audit's line citations for `datom_parent()` and both
    builder call sites had gone stale, plus five more across the spec that `dev/check-spec.R` caught.
    Ninth consecutive session for that class._
  - **REVIEWED AFTER IT LANDED (2026-09-15). NO CODE CHANGED -- the review accepted the
    implementation, and everything it produced was documentation.** Five items. One finding was
    **withdrawn by the reviewer** and is kept as a decisions row because the reasoning is the reusable
    part: the cascade's manifest step goes through the repairing reader, so on a too-new manifest a
    one-field lookup can cost a full index reconstruction -- but the answer is still correct, and
    reaching it needs a three-way straddle, so the triage rule says record it. One suggestion was
    **rejected with its reason recorded**: reading the manifest document directly instead of through
    the gated reader would take a value out of a document whose format was never checked, and that
    value is hashed into a set's identity -- which was audit question 4, settled at the gated reader
    for exactly this. Three were **accepted**: the repointing hazard was rehomed from "unfiled issue"
    to a constraint on the resolver in `dev/datomanager_overview.md` section 4a, directly beneath the
    section stating the rule it exploits; `datomanager_overview.md` section 5 was marked stale in its
    mechanism, because it promised a future package a key refusal on an export that was dropped in
    August and never shipped; and the triage rule the spec had been applying without stating it was
    written into design.md 11. Tests unchanged at 3585.

## New exports introduced by this spec

Track so `_pkgdown.yml` and NAMESPACE stay complete:

| Export | Task |
|---|---|
| `datom_storage_read_json()` | 3 -- **shipped 2026-08-21** |
| ~~`datom_storage_write_json()`~~ | **dropped 2026-08-18** -- deferred to the Backlog; see Task 3 |
| `datom_member()` | 8 -- **shipped 2026-09-11** |
| `datom_write_set()` | 9 -- **shipped 2026-09-13** (extended with `include_paths` in 13) |
| `datom_get_set()` (renamed from `datom_read_set()`, 2026-09-13 -- it returns references, not data) | 10 -- **shipped 2026-09-14** |
| `print.datom_set()` | 10 -- **shipped 2026-09-14** |
| `print.datom_link()` | 10 -- **shipped 2026-09-14** |
| `datom_repo_commit()` | 12 -- **shipped 2026-09-18** |
| `datom_repo_push()` | 12 -- **shipped 2026-09-18** |
| `datom_fetch_member()` | 24 -- **shipped 2026-09-15** |
| `datom_list_members()` | 24 -- **shipped 2026-09-15** |
| `datom_structure_members()` | 24 -- **shipped 2026-09-15** |
| `datom_assemble_set()` | 25 |
| `datom_add_member()` | 25 |
| `print.datom_set_draft()` | 25 |

Task numbers here are **bare**, so the 2026-08-23 renumber did not touch them mechanically and they
were corrected by hand. Check 8 cannot see them either -- it only reads numbers written as
`Task N`. If this table is ever renumbered again, re-derive it from the task headings rather than
trusting the column.

---

## Phase H -- Editing a set that already exists **[appended; EXECUTES AFTER TASK 15, BEFORE TASK 16]**

**Appended rather than inserted, so nothing renumbers**, for the fourth time and the same reason. The
placement is not free choice: **Task 16 is the acceptance-criteria sweep and Task 17 is docs plus the
Spec Completion Procedure**, so verbs landing after either would leave the sweep testing a surface
that then grew and the docs describing one missing two exports. Nothing else waits on them -- they
depend only on Task 10's read and Task 24's finder, both done -- so they slot in at the one place that
satisfies that constraint and leaves the `23 -> 11` critical path untouched.

**Scheduled into this release rather than deferred, owner-decided 2026-09-16.** They were designed as
a deferral and then pulled in: repointing a member at a newer version is a fundamental operation on a
product, and removing one is close behind. The deferral would have been **free in the one dimension
that is usually expensive here** -- these verbs touch no stored document, so no field, no format
number, no vocabulary entry, and therefore no forced fleet upgrade if they arrived a release later.
That makes this a scope call and not a compatibility one, which is why it could be decided on value
alone.

**Task 27 comes first even though it is the larger one.** Both share a plural member selector that
does not exist yet -- Task 24's finder resolves exactly **one** member and aborts on ambiguity, while
both of these select a **set** of members. Building the harder consumer first is what gets that
selector's shape right; building the easier one first invites a selector shaped for a filter that then
bends for connection grouping. It also puts the risk in the right place: if the release squeezes, what
drops is the verb the owner called less fundamental.

- [ ] **27. `datom_update_members()` -- repoint members at newer versions** &nbsp; **[EXECUTES AFTER TASK 15]**
  - **DEPENDS ON TASK 10** for the object it edits and on **Task 24** for the three shapes a member is
    named by. Reuses `.datom_member_shape()` (`R/member.R`) rather than restating shape dispatch, the
    same way `datom_add_member()` does.
  - **`datom_update_members(x, conn, member = NULL, tags = NULL, version_from = NULL,
    version_to = NULL)`** -> the same class it was handed, with matching members repointed.
    `member = NULL` means **every** member, because refreshing everything is the common case and
    rerunning it is a no-op (R24.2). `conn` accepts one connection **or a list of them**, one per
    project the set spans. The two version arguments were split on 2026-09-19 -- see finding 2 of the
    pre-start audit for why one name could not carry both directions, and R4.2a for why
    `version_to` may default to current when `datom_add_member()`'s version may not.
    - **A plural selector is the new shared piece, and it belongs to this task.** Task 24's
      `.datom_find_member()` returns one member and aborts when a name is ambiguous, which is right
      for a fetch and wrong here: this verb legitimately acts on many. So one internal selector
      answers "which members does this call refer to", and Task 28 uses it unchanged.
    - **The version comes from each artifact's own project, and the cheap route is the manifest.** A
      project's manifest carries `current_version` per artifact (`R/query.R:113`), so learning what
      moved costs **one read per project**, not one per member -- and only the members that actually
      move then pay a snapshot read, through `datom_member()`, which is what keeps the pointer
      trustworthy. A naive implementation makes 100 snapshot reads for a 100-member set; the right one
      makes 3 plus however many moved.
    - **`version_to` beside a selection that resolves to one member repoints it to exactly that
      version**, and is refused beside a selection matching several. It is what makes this verb
      strictly better than remove-then-add for a retag, a rollback to a known-good, or a deliberate
      step to something that is not the newest: **it keeps the member's labels**, which
      remove-then-add makes the caller retype. Omitted, it means current.
  - **LABELS ARE CARRIED, NEVER REBUILT** (R24.3). Repointing changes one field of a pointer.
    Rebuilding the record from name plus new version drops its labels silently, and labels are
    content, so the set's identity would move for a reason nobody asked for. **Test byte-identity of
    the labels, not their presence** -- a rebuild that happens to re-add them in a different order
    passes a presence check and changes the payload.
  - **CONNECTIONS ARE MATCHED ON AN UNVERIFIED LABEL AND THE RESULT IS VERIFIED** (R24.4). Matching
    has to key on `conn$project_name`, which nothing compares against the repo -- that is the whole
    finding behind Task 26. So dispatch on the label, then compare the **rebuilt** member's recorded
    project against the one it replaced and refuse on a mismatch. Without it, a connection labelled
    for project A but pointing at project B's namespace silently repoints a member at B's same-named
    artifact. Unverified value chooses the route; verified value confirms it.
  - **UNKNOWN REFUSES, KNOWN-AND-BENIGN REPORTS** (R24.5), and stating the split is what stops it
    reading as an inconsistency.
    | Situation | Response | Why |
    |---|---|---|
    | a member's project has no supplied connection | **refuse the whole call**, naming the project | whether it moved is unknowable, and silence would assert something unchecked |
    | a member's artifact no longer exists there | **report it and leave the pin** | the answer is known, the pinned version still reads, and refusing a whole refresh over one retired input is the wrong trade |
    | two members share a name | **skip both and report** (R24.6) | only the caller's labels say which is live; choosing is a guess |
    - The refusal is actionable rather than a dead end, and that is what earns it:
      `unique(datom_list_members(x)$project)` enumerates a set's projects **offline, with no connection
      at all**, because a member's project is a recorded fact after Task 26. So the caller can see what
      connections they need before calling anything.
  - **THE REPORT, and it is the deliverable rather than decoration.** Grouped by project, one line per
    moved member as `name  old8 -> new8`, then the counts, then what was skipped and why, then that
    nothing has been written. Grouped by project because that is the axis connections are supplied
    along, so a surprise in the grouping is a surprise about which connection served what. Console
    lines truncate the way a set prints (first 20, then `... and N more`).
  - **NOTHING IS WRITTEN, SO THE REPORT IS THE DRY RUN** (R24.7). No confirmation prompt, unlike
    `renv`, which has to ask because it is about to act. And an update that finds nothing new returns
    a byte-identical payload, so the existing change detection reports no change and mints no version
    -- assert that **through the write**, because that is where "free" is observable.
  - **THE CHANGE LIST FEEDS THE COMMIT MESSAGE** (R24.8), which is the smallest slice here and the
    most droppable if the task has to be cut short. A set write commits `Update {name}` today, which
    says nothing in `git log`. When an update produced a change list and the caller passed no
    `message`, the write defaults to a summary naming what moved, full list in the body -- git is the
    durable record, so completeness belongs there rather than on screen. An explicit `message` still
    wins. **The change list rides as an attribute**, not as a field, following the link's carried
    member record, so it cannot reach the payload.
  - _Requirements: R24 (all clauses), R2.14a (the skip rule), R4.2a (why a version is still never
    inferred at write time). Acceptance: AC40, AC41 (a), (b), (d) -- (c) is Task 28's to share._
  - _Pathway impact: yes -- the set-read card gains a note that resolving "what is current" for a
    member goes through its project's manifest rather than through a per-member scan._

  **PRE-START AUDIT (2026-09-19), cold. THIRTEEN findings, and FOUR need the owner before a keystroke
  -- they are all public-API shape, which is the one thing that cannot be fixed later at this
  lifecycle stage without a rename.** Every claim below was checked against the tree; the two that
  were probed by running code say so. Two claims in the task body above are **wrong** and are
  corrected here (findings 5 and 12).

  1. **The plural selector genuinely does not exist, and the singular one actively refuses the shape
     this verb needs.** Verified exhaustively rather than by spot check: `grep -n "Filter(" R/*.R`
     returns exactly **three** hits, all inside `.datom_find_member()` (`R/set-members.R:423`), which
     ends `narrowed[[1L]]` after aborting on more than one match. And `.datom_member_record()`
     (`R/set-members.R:521`) **aborts** when `tags` or `version` arrive beside a record or a link.
     What is reusable is smaller than "the finder": `.datom_member_has_tags()`
     (`R/set-members.R:391`) is a clean per-member predicate, and the version half is a one-line
     `startsWith()` (`R/set-members.R:452`) that is not a helper at all. So the selector is new code
     built from one existing predicate, not a generalisation of an existing function.
  2. **SETTLED 2026-09-19 (owner): `version_from` selects, `version_to` targets, and `version_to`
     DEFAULTS TO CURRENT.** The two names are symmetric and unambiguous at the call site, which the
     single `to` floated in this audit was not. `version_from` is optional and needs no new
     machinery -- it is required only when a name resolves to more than one member, so the common
     call is `datom_update_members(x, conn, member = "ae")`. The default-to-current half is the one
     that needed writing down, because R4.2a refuses exactly that inference for
     `datom_add_member()`: the boundary is now recorded **inside R4.2a**, and the word carrying it is
     **silent**. A verb that says nothing about time must not quietly resolve newest; a verb whose
     meaning is *move forward from here* states the time-dependence in its own name and reports what
     it moved. Two consequences to implement rather than infer:
     - **`version_to` requires the selection to resolve to exactly one member**, and refuses
       otherwise. One explicit target version applied across several artifacts is not a meaning.
     - **An explicitly named member that is ambiguous ABORTS; only the sweep skips.** R24.6's
       skip-and-report is argued from the bulk case -- refusing a whole refresh because the set holds
       a baseline would make the first update on any such set an error. That argument does not reach
       a caller who named one member: there the request cannot be honoured, so it is a user error and
       `version_from` is what resolves it. Same shape as `.datom_find_member()`
       (`R/set-members.R:423`), which aborts and teaches the narrowing.
  3. **SETTLED 2026-09-19: `(x, conn, ...)` stands, and THIS AUDIT'S ORIGINAL JUSTIFICATION FOR IT WAS
     FALSE.** The claim was that object-first makes the verb pipe into the write. It does not:
     `datom_write_set()`'s first parameter accepts a `datom_conn` or a `datom_set_draft` and nothing
     else (`R/set.R:887`), while the `datom_set` widening is on **`members`** (`R/set.R:919`) -- so a
     piped set lands in the connection slot and aborts. Two further facts kill every repair of that
     claim: piping into the second argument needs the `_` placeholder, which is **R 4.2.0** while this
     package declares `R (>= 4.1.0)` (`DESCRIPTION:24`); and the read-modify-write idiom this spec
     already documents is not a pipe at all but three statements ending
     `datom_write_set(conn, x)` (`R/set.R:769`). So the pipe was never the idiom and cannot justify
     anything.
     **The order survives on a different and checkable rule, which the package already follows: a verb
     that EDITS an object in hand takes the object first; a verb that RESOLVES something takes the
     connection first.** `datom_add_member(x, ...)` (`R/set-draft.R:315`) edits and is object-first;
     `datom_fetch_member(conn, x, ...)` (`R/set-members.R:647`) resolves and is connection-first.
     `datom_update_members()` does both, so it is object-first **and** takes a connection, second.
     Decisive for the pair: `datom_remove_members()` cannot take a connection at all (R24.1, and the
     reason is structural), so connection-first for update would make the two sibling edit verbs
     disagree on argument order in the one place a reader compares them.
  4. **AC40(a) fails on the obvious implementation, and it fails quietly.** The natural spelling is
     `datom_member(conn, name, new_version, tags = old$tags)` -- and `datom_member()` runs
     `.datom_drop_empty_tags()` on what it is handed, so a label whose value is empty is **dropped**.
     Payloads datom wrote were tidied already, so this is invisible in every ordinary fixture and
     shows up only on a hand-built or foreign-written set. Build the pointer with **no** tags, then
     attach the old record's `tags` **verbatim**: that keeps the snapshot read and the `kind`
     resolution that make a pointer trustworthy while satisfying byte-identity. Assert with
     `identical()` on the tag element, not on its names.
  5. **CORRECTION to the body: the `$fetch` link on a repointed member is stale and nothing in the
     task says so.** A member read by `datom_get_set()` carries a closure pinning the version it was
     read at (`.datom_member_link()`, `R/set.R:1313`, built at `R/set.R:1558`). Repoint `id$version`
     and leave `fetch` alone and the object contradicts itself: `id` says the new version, `$fetch()`
     returns the old data, silently. Rebuild it **through the factory or through
     `.datom_member_as_link()`** (`R/set-members.R:308`) and never inline -- a closure built inside
     the verb puts the frame holding `conn`, and therefore the PAT, on its parent chain, which is the
     leak `R/set.R:1313`'s own docs record with byte counts. Rebuild **only for members that had
     one**, or a draft's members grow a field they never carried. Needs its own test: a repointed
     member's link resolves the **new** data.
  6. **SETTLED 2026-09-19: an edited set returns with `version` and `data_sha` blanked, in a helper
     Task 28 shares.** `datom_get_set()` sets both from the payload it read (`R/set.R:1746` onward);
     once members move they describe a payload that no longer exists, and a set exists to be cited, so
     a stale version is a wrong statement rather than a missing one -- the same argument that makes
     `version` legitimately `NULL` on a truncated history. Verified safe: the write reads only `$tags`
     and `$members` off a `datom_set` (`R/set.R:919`), and `print.datom_set` already renders a `NULL`
     version.
     **Returning a `datom_set_draft` instead was proposed and rejected on two checks.** It was
     attractive -- a draft has no `version`, no `data_sha` and no links, so it would have dissolved
     this finding and finding 5 outright. It fails because **a draft carries the connection it will be
     written through**, and `datom_write_set(draft)` requires that connection to be a **developer**
     connection on the **product** repo (`R/set.R:887` onward, then the `mode: product` gate). This
     verb's connections are the **members'** project connections, and a product whose members all live
     in other projects supplies none for its own repo -- so the draft would carry a connection that
     cannot write the set. Second: `datom_remove_members()` has no connection to put in a draft at
     all, so the pair would return different classes, which is what R24.1's "parallel in shape" exists
     to prevent, and remove's chain would stay broken anyway. The two problems the draft would have
     dissolved are solved directly instead, by this finding and by finding 5.
  7. **Task 27 edits `datom_write_set()`, which the body does not say.** R24.8 needs the change list
     to reach the commit-message default, and that default is built inside the write
     (`R/set.R:1074`). So this task touches the write verb, and the read of the attribute must happen
     **before** the unpack at `R/set.R:919`. Verified that the attribute cannot leak into a payload:
     that branch takes `members$tags` and `members$members` and nothing else, so an attribute on `x`
     is dropped by construction -- and a caller who passes `x$members` instead of `x` loses the
     better message and gets today's default, which is worth one line of documentation.
  8. **The cheap route to "what moved" has a trap that fails loudly, and a second that does not.**
     `datom_list()` reads the manifest **once per project** (`R/query.R:80`) and a row's
     `current_version` is a field off the parsed entry (`R/query.R:113`) -- so the body's cost claim
     holds. But `short_hash = TRUE` is the **default** and truncates that column to 8 characters
     (`R/query.R:126`), while `datom_member()` demands a full validated sha
     (`.datom_validate_sha()`, `R/member.R:518`). Loud, so it costs minutes. The quiet one is the
     second read: `.datom_declared_project()` (`R/member.R:391`) falls back to a **storage manifest
     read** (`R/member.R:395`) for any artifact whose snapshot does not record `project`, so a moved
     legacy member costs a manifest read of its own. Bounded by the number that moved, and not this
     task's to fix -- but it means "one read per project plus one per moved member" understates it on
     a pre-Task-26 repo.
  9. **R24.4's verification is sound, and the reason is the cascade rather than the label.** Traced
     rather than assumed: a connection labelled for project A but rooted at B's namespace reads **B's**
     snapshot, which records `project = "B"`, so the rebuilt member disagrees with the one it replaced
     and the refusal fires. If that snapshot predates the `project` field, step two of the cascade
     reads **B's** manifest and gets `"B"` -- so it still fires. It degrades to a trivial pass only
     when the snapshot **and** the project's manifest both omit the name, and
     `.datom_manifest_skeleton()` has always written it. State that residual; do not build for it.
  10. **The skip rule and the refusal rule are opposite responses to one situation, and both are
      right.** Two members sharing a name: Task 27 **skips and reports**, Task 28 **refuses**, and the
      existing `.datom_find_member()` also refuses (`datom_member_ambiguous`). The asymmetry is the
      consequence, not the taste -- skipping a repoint leaves a valid pin, skipping a removal silently
      does nothing. Document the two together, as Task 28 already instructs, or a later tidy-up
      unifies them.
  11. **Using the manifest means accepting its lag, and that surfaces as a wrong report rather than an
      error.** A member absent from its project's manifest reads as "the artifact no longer exists",
      which R24.5 handles by reporting and leaving the pin -- but the manifest is a projection that
      can lag a half-finished write, so a retired-input report is not proof the artifact is gone. One
      sentence in the report's wording covers it; the alternative (a per-member `datom_history()`) is
      the cost the body deliberately rejected.
  12. **CORRECTION to the body: AC41(d)'s fixture does NOT already exist.** The task's acceptance note
      says clause (d) "needs two stores and a mislabelled connection, which is the fixture that
      already exists for the no-gate tests". The no-gate test (`tests/testthat/test-set-members.R:689`)
      is **single-store**: it mutates `project_name` on one connection, so the member and the store
      agree and only the label differs -- which is the opposite of what (d) needs. The fixture that
      does fit is the parameterised two-project one in a different file,
      `local_draft_project(project_name, set_name, prefix)` (`tests/testthat/test-set-draft.R:37`, used
      at `tests/testthat/test-set-draft.R:535`). It will have to be duplicated, since testthat shares
      no definitions between files.
  13. **SETTLED 2026-09-19: `conn` stays required, and a draft's own connection is ignored.** A
      `datom_set_draft` carries the connection it was opened with (`R/set-draft.R:207`), but it carries
      exactly one while this verb legitimately spans several projects -- and silently preferring the
      embedded one would make the same call behave differently depending on how `x` was produced.
  14. **SETTLED 2026-09-19: consistency between a member's record and its link is prevented
      structurally, with one tripwire and the existing write gate behind it.** Three layers, and only
      the first is a mechanism:
      - **Structural.** A member's record and its `fetch` link are two copies of one fact, which is
        why they can drift. Every edit path rebuilds the link from the record through the one existing
        factory (`R/set.R:1313`, via `.datom_member_as_link()` at `R/set-members.R:308`), so drift is
        unrepresentable rather than checked for.
      - **A tripwire on touched members only.** Assert that a repointed member's record and link
        agree. Untouched members came from the read and were already consistent, so the cost scales
        with the edit and not with the set. This is not the guarantee -- it is what reddens if a later
        change edits a record without rebuilding.
      - **The write is the final gate and already exists.** `.datom_validate_members()` runs on every
        payload and links are stripped before hashing (`R/set.R:923`), so a **stored** set cannot be
        inconsistent however the in-memory object was produced.
      **Deliberately not chased:** a hand assignment such as `x$members[[3]]$id$version <- "..."` is
      outside every verb, so no tripwire sees it. The write catches it, and this spec already holds
      that a hand-built set is supported and untrusted -- defending the in-memory object against
      direct assignment is where the cost stops being proportional.

  **Verdict: STARTABLE COLD. Nothing is open.** Findings 2, 3, 6, 13 and 14 were settled by the owner
  on 2026-09-19; finding 1 sizes the new code; 4, 5 and 7 are implementation traps now written down;
  8-11 are consequences to state rather than problems to solve; 12 redirects the fixture. Two claims
  this audit itself made were checked and corrected in the same round -- finding 3's pipe
  justification was false, and the draft-returning alternative in finding 6 fails on the connection it
  would have to carry. No model escalation is owed: the task was not flagged for it at planning, and
  nothing here changes a stored document, a format number or an identity field.

- [ ] **28. `datom_remove_members()` -- drop members from a set** &nbsp; **[EXECUTES AFTER TASK 27]**
  - **DEPENDS ON TASK 27** for the plural selector, which lands there because the harder consumer
    shapes it correctly. Nothing else here is new machinery.
  - **`datom_remove_members(x, member, tags = NULL, version = NULL)`** -> the same class it was
    handed, minus the matching members. **No `conn` argument at all**, and that is the structural
    difference from both sibling verbs: removing only has to **find** a pointer already in hand, while
    adding and repointing have to **resolve** one. Say so in the docs, or the missing argument reads
    as an oversight.
  - **A SELECTION IS REQUIRED** (R24.2). `datom_remove_members(x)` with no selection would mean
    removing every member, which the writer refuses anyway -- so it aborts naming what a selection
    looks like, rather than building a payload the write then rejects. The safe default for a
    destructive verb is nothing, which is the opposite of Task 27's default and for the same reason.
  - **REMOVING NOTHING IS AN ERROR, NOT A SUCCESS.** A selection that matches no member is a typo, and
    the hand-rolled `Filter()` it replaces reports success. Name what was asked for and point at
    `datom_list_members()`.
  - **REMOVING THE LAST MEMBER IS REFUSED ON THE LINE.** The write already refuses an empty set, so
    this only moves the refusal to where the caller can see which removal emptied it -- the same
    argument that put per-member validation in `datom_add_member()`.
  - **A NAME ALONE REMOVES EVERY VERSION OF THAT NAME, AND THAT IS THE ONE THING THIS VERB MUST NOT DO
    QUIETLY.** It is exactly the silently-wrong hand-rolled spelling the verb exists to replace: a
    set holding a live table beside a frozen baseline loses both. So a name matching more than one
    member **refuses**, listing both with their versions and labels and pointing at narrowing -- the
    same shape as Task 24's ambiguity abort, and the opposite response from Task 27's skip, because
    skipping a removal would silently do nothing while skipping a repoint safely leaves a valid pin.
    **State that asymmetry where both are documented**, or a later change "unifies" them.
  - _Requirements: R24.1, R24.2, R2.14a. Acceptance: AC41 (c) shares the two-members-one-name fixture
    with Task 27; **the rest by test rather than criterion** -- the empty-selection abort, the
    matched-nothing abort, the last-member refusal, and the ambiguous-name refusal each get one._
  - _Pathway impact: none -- no lookup, no traversal, no IO of any kind._

---

## Decisions log

Record decisions as they are made, so a fresh session does not relitigate them.

| Date | Decision | Where |
|---|---|---|
| 2026-08-09 | Branched from `dev`, not `main`. `dev/README.md` "Branching During CRAN Submission" governs while 0.1.0 is in review; the `from main` wording in copilot-instructions item 0b is the no-freeze default. | requirements.md header |
| 2026-08-09 | #89's "keys go through `.datom_build_storage_key()`" cannot be followed literally -- that function returns a **full** key while `.datom_storage_*()` takes **relative** keys. Honor the intent with relative-key helpers instead. | design.md Deviation D1 |
| 2026-08-09 | `datom_member()` deliberately does **not** carry `data_sha` (unlike `datom_parent()`). `data_sha` exists on parents to support cross-project lineage resolution, which sets explicitly do not do. | design.md section 5 |
| 2026-08-09 | Missing `document_sha` on a set read is an **error**, not a skip. The `parquet_sha` skip branch is a pre-cv1 migration grace; sets have no legacy population. | design.md section 8 |
| 2026-08-09 | `metadata_sha`'s own emitter-drift exposure is filed as a separate issue, not folded into this spec. | design.md section 16, Task 1 |
| 2026-08-09 | **Independent spec review.** All 12 findings verified against the code and accepted; none rejected. Full audit trail with per-finding verification method and resolution. | design.md section 18 |
| 2026-08-09 | ~~**(F1)** Write-time cycle detection is exhaustive within a project only; read-side visited-set + depth guarding is a requirement.~~ **SUPERSEDED 2026-08-11 -- see the entry below.** The premise was false. | design.md 20.11 |
| 2026-08-09 | **(F2)** `datom-sv1` hashes the **parsed-JSON** data model, not the in-memory R object. Reproduced on the branch: `NA_real_` -> string `"NA"`, doubles -> integers, `NA_character_` -> `null`. A type-tagged encoder over the in-memory object would disagree with itself across the round trip. Elevated from open question to hard constraint. **Mechanism superseded 2026-08-15 by Q5** -- the original `serialize -> parse -> encode` normalization is replaced by eliminating each mutation at source; the constraint itself stands unchanged. | R2.5, design.md 7.1/7.3 |
| 2026-08-09 | **(F2/Q5)** Which serializer defines sv1's canonical form -- `jsonlite` vs an sv1-owned minimal emitter -- is now the load-bearing open question, because the round-trip constraint forces the choice into the open. Coupled to the section 16 issue. | design.md section 7 Q5, E1 |
| 2026-08-09 | **(F3)** The public `datom_storage_write_json()` refuses datom-managed keys (`.metadata/` segments, payload-shaped keys under existing artifacts). Reads unrestricted. Public-contract decision settled in the spec. | R12.4a, I14 |
| 2026-08-09 | **(F4)** A set's metadata is **exactly** R1.3's seven fields. `size_bytes` dropped (no consumer), `custom` dropped (payload already owns user metadata, R6.2) -- so `datom_write_set()` has no `metadata =` parameter. | R1.4, design.md section 4 |
| 2026-08-09 | **(F5)** `datom_write_set()` requires `mode: product` **and** a name matching `project.yaml`'s `set:`, both checked before any hashing or IO. This is what makes "one repo = one set" enforced rather than aspirational. | R10.3a, I15 |
| 2026-08-09 | ~~**(F7)** Set payloads live in git at `{name}/{data_sha}.json` and all historical payloads are retained.~~ **SUPERSEDED 2026-08-11 -- see the stable-path entry below.** Git now holds one mutable `{name}/set.json`; only storage is content-addressed, and the retention rule is redundant. What still holds from F7: the `governance.json` *ordering* transfers but its singleton *layout* does not, and P17 survives via `git show <commit>:{name}/set.json`. | R6.1a/b, P17 |
| 2026-08-09 | **(F12)** The stale "task 5.1" text is at `R/read_write.R:110-113, 205-206, 413`, with `393` already correct and therefore contradicting. #89's `95-97` citation was wrong and the first spec draft propagated it. | R13.3, Task 1 |
| 2026-08-11 | **Spec delta D1-D8 applied** from #89. **The `mode: product` repo IS the joint repo** (data + code + `renv.lock`); no separate fourth repo. Decisive reason: cross-repo pinning is circular -- the code repo wants to record which set version it produced and the set payload wants to record which code commit produced it, so one is always stale by one commit. A joint version requires one commit graph. | design.md section 19, R14 |
| 2026-08-11 | **datom is the single git-mutating actor** (I17). Downstream packages never import `git2r`; all stage/commit/push/pull goes through a datom export. Writing files on disk is *not* a git operation and needs no datom API -- hence **no `datom_gitignore_*` API**, ever. | I17, R16, design.md 19.5 |
| 2026-08-11 | **Machine vs human commit moments is the load-bearing distinction.** `dpbuild`'s add-all was safe only because every commit was human-invoked. datom commits at machine-chosen moments, so add-all there would snapshot arbitrary WIP human code. Machine moments stage datom paths only (R14.1); human moments get add-all via `datom_repo_commit(paths = NULL)` (R15.1). | design.md 19.4 |
| 2026-08-11 | `include_paths` (R12.5) is the **only** way a machine-moment commit may carry a non-datom path, and only because the caller enumerated it. Never add-all. | R14.3, I16 |
| 2026-08-11 | An idempotent set re-write stays a no-op **even with dirty `include_paths`** (I19). AC2 must not acquire a side channel that commits code -- that would be the add-all failure through a different door. Caller is directed to `datom_repo_commit()`. | R12.5, AC19 |
| 2026-08-11 | **(delta correction C1)** `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It aborts on an empty `files` **argument** and on nonexistent files. So `datom_repo_commit(paths = NULL)` cannot delegate with `files = character(0)`, and must determine "nothing to do" itself to honor the `invisible(NULL)` no-op contract. | design.md 19.6, R15.5, Task 12 |
| 2026-08-11 | **(delta correction C2)** The on-a-branch guard lives in `.datom_git_branch()`, reached only via `.datom_git_push()`, so it does not fire when `push = FALSE`. Assert it explicitly. | design.md 19.6, R15.7, Task 12 |
| 2026-08-11 | `datom_repo_commit(paths = NULL)` may sweep in dirty datom files left by a failed write. **Deliberately not special-cased**: it moves git ahead of storage (the safe direction), `datom_validate(fix = TRUE)` is the existing repair path, and excluding them would make the function lie about `git add .` semantics. | design.md 19.7 |
| 2026-08-11 | Tasks renumbered: two tasks inserted after 10 (foreign-content discipline + `datom_repo_commit()`; `include_paths`). Old 11/12/13 -> 13/14/15. | tasks.md Phase D |
| 2026-08-11 | **(F13)** Push decoupling had only one half -- `push = FALSE` with no way to push later. **Both proposed fixes adopted**, because they solve different problems. Add **`datom_repo_push()`** (R15.8): routing push intent through `commit()` would force a push-only caller through the `paths = NULL` add-all path, which in a product repo commits whatever human WIP it finds -- the R14 hazard through a third door -- and would leave `message` a silently-ignored required argument. **And** make push **convergent** (R15.5 qualified, R15.8): a no-op means no *commit*, not no push, because otherwise one failed push leaves the remote silently behind forever as every later call returns early on a clean tree. | design.md 19.8, I20, P23, P24 |
| 2026-08-11 | Supporting the export over the wrapper-only fix: datom **already exports standalone `datom_pull()`** (`R/sync.R:45`) with no push counterpart, and the `datom_repo_*` family already exists -- so this closes an asymmetry rather than inventing a shape. Cost is one thin wrapper plus one array index: `.datom_check_git_current()` already calls `git2r::ahead_behind()` and reads `[[2]]`; `[[1]]` is the ahead count. | design.md 19.8, R15.9 |
| 2026-08-11 | **(F14)** AC20 stays one criterion but is **tested as two cases** (nonexistent path; datom-owned overlap), so a regression identifies which gate broke. | AC20, Task 13 |
| 2026-08-11 | **Artifact topology settled**: one repo = one namespace (`{root}/{prefix}/datom/`) = one manifest, 1:1:1. A set lands in the **product repo's** namespace, never with onboarded source data. Two manifests with the same schema, zero shared files. Matches the documented house convention (`buckets-and-prefixes.Rmd`: "prefix per product"). | R17, design.md 20.1-20.5 |
| 2026-08-11 | **New init guard** (R17.3): a `mode: product` repo refuses a namespace already holding another project's manifest. Justified on **blast radius** -- prefix-delete/teardown operate on a whole namespace, so a shared prefix means deleting the product can delete raw data -- plus one-manifest ownership. Enforced rather than documented because the utility of mixing is ~zero (a second prefix costs nothing) while the failure is destructive. | R17.3/R17.4, AC22, Task 11 |
| 2026-08-11 | **Correction: datom needs NO governance for cross-project members or parents.** The mechanism is caller-supplies-connection; the project name is a label and datom performs no name-to-location lookup anywhere. An earlier claim that cross-bucket products "effectively expect gov attached" was wrong -- it conflated datom's write-time needs with the access layer's read-time SOURCES lookup. | R18.1, design.md 20.3 |
| 2026-08-11 | **Location precedence, inherited not invented**: explicit address in the project's own config works standalone; `ref.json` in the gov repo takes priority once governance exists; `governance.json` is the flag for whether it is attached. Member resolution follows this exact precedence. Therefore **member records carry a logical project name and never a location** -- an embedded location would go stale on a bucket move, which is what `ref.json` exists to prevent. | R18.2/R18.3 |
| 2026-08-11 | **Correction: the access unit is the artifact, not the namespace.** Roles are table-level and a derived table's requirement is the union of its **leaf ancestors'** roles, so two derived tables in one product/bucket/prefix get different requirements automatically. Per-artifact IAM is expressible because every artifact has its own folder. The namespace rule therefore **keeps its conclusion but changes its justification** (blast radius + ownership, not access) -- a rule defended by a wrong argument gets relitigated. | R19.1/R19.2, R17.4, design.md 20.6 |
| 2026-08-11 | **A set gates on nothing** -- no parents means the lineage walk finds no leaves, so no roles are required unless explicitly overridden. Same conclusion as the non-conjunctive access decision, now confirmed against the access layer's algorithm. Corollaries recorded because they surprise people: **granting a product does not grant its members**, and a **sensitive member list uses the explicit-override path**. | R19.3-R19.5, design.md 20.7 |
| 2026-08-11 | **SUPERSEDED 2026-08-18 -- the write export is retired, so this refusal has nothing to attach to; do not implement it.** ~~The JSON write export must also refuse **`.access/`** -- the namespace reserved for the access-enforcement package, where datom is safe today only *by construction*. This export is the first general-purpose write path that could break that reservation.~~ | R12.4a/R19.6, AC23, Task 3 |
| 2026-08-11 | **`role` terminology collision**: datom's `role` (developer/reader) vs the access layer's "role" (permission set). **datom keeps `role`; the burden is on the future package to pick a different term** -- it does not exist yet so the rename is free there and breaking here. Recorded in `dev/datomanager_overview.md` for whoever builds it. | design.md 20.9 |
| 2026-08-11 | **Clarified: there is no lineage walk.** `source_lineage` is a precomputed transitive union maintained at write time -- imported tables get a self-entry, derived tables get the union of their parents' unions -- so "which raw sources feed X" is **one read, zero hops**, and it cannot drift because parents pin immutable versions. Design section 20.6 initially repeated the access design's "walk upward" framing; corrected. | design.md 20.10 |
| 2026-08-11 | **`dev/datomanager_overview.md` is stale on this point and now says so.** It predates Phase 20, so it requires only `parents` and builds a walk -> session-cache -> *precomputed leaf map* ladder. `source_lineage` **is** that leaf map, already stored per table. Added item 3a plus stale-markers on the affected sections: delete the walk, do not rebuild `ROLE_LEAVES`, keep the access *semantics*. | dev/datomanager_overview.md |
| 2026-08-11 | **RESOLVED -- all nesting machinery removed** (supersedes F1 and the two OPEN entries that preceded this). Cycle detection, the visited-set guard, and the depth limit are **gone**, for two independent reasons either of which suffices: (1) **datom resolves one level and never traverses** -- a member that is a set comes back as a pointer and the consumer reads it separately, so nothing can loop; (2) **the graph is acyclic by construction** -- members pin immutable versions that must already exist, so a set cannot reference something containing it, exactly as git history cannot cycle. The "cross-project cycle" earlier constructed does not close: the second write creates a new version rather than mutating the referenced one, giving `B1@v2 -> A1@v1 -> B1@v1`, which terminates. | R4.3-R4.5, I10/I10a, P16, AC9/AC15, design.md 5 + 20.11 |
| 2026-08-11 | Replacements after the removal: **R4.3** one-level resolution, **R4.4** acyclic by construction, **R4.5** refuse self-reference (the one check that stays -- acyclic and harmless, but never meaningful). **I10** no traversal, **I10a** no cycle/depth guard may creep back as defensive code. **P16** restated as "read cost is bounded by direct member count". **AC9** restated as self-reference refusal, **AC15** restated as "nesting resolves one level" -- a test that the tree is *not* flattened. | requirements.md R4, design.md 13-14 |
| 2026-08-11 | **Retired: the transitive-member-closure question** (formerly E1 Q6). It existed only to replace a traversal with one read; there is no traversal, so it would be payload weight buying nothing and would enter set identity for no benefit. E1 is back to one hard constraint + five open questions. | design.md 7, 20.11 |
| 2026-08-11 | **Git owns history; datom writes projections** (R20). The test: *would someone holding the repo use this file to answer a history question?* `version_history.json` and `manifest.json` pass -- only git-less **readers** need them, and the giveaway that they are projections rather than duplicates is that they carry `author` and `commit_message`, literally git commit fields. | design.md 21.1 |
| 2026-08-11 | **Correction: the git payload moves to a stable path `{name}/set.json`**; storage stays content-addressed at `{name}/{data_sha}.json`. A content-addressed *git* filename makes every version a new file, so `git diff` reports "file added" instead of which members changed, and history gets read by listing filenames -- hand-maintaining what git maintains. The "retain all historical payloads" rule is dropped as redundant (git retention is definitional); P17 holds via `git show <commit>:{name}/set.json`. | R6.1a/b, P25, AC24, design.md 21.2 |
| 2026-08-11 | **Version semantics -- option 1 chosen.** A version stays **content-derived and code-invariant**, identically for tables and sets; the commit is recorded **provenance**, not identity. So a code-only change producing identical content mints **no** new version (already true for tables, deliberately kept true for sets), and one version maps to **one or more** commits with `commit_sha` naming the first. | R21.1-R21.3, I23, P27, AC26, design.md 21.3 |
| 2026-08-11 | **Rejected: commit-as-version** (circular -- the commit contains the metadata that would name it; a composite version would break `datom_read(version = )` as a single string). **Rejected: code/env content hashes in the payload**, which *would* work mechanically, because a set exists to be **citable** and a comment typo or lint fix would then mint a new product version. The strongest counter-argument -- restricting it to `renv.lock`, since env drift can silently change future behavior -- is recorded in case it returns. | R21.4, design.md 21.3 |
| 2026-08-11 | **`commit_sha` goes in the `version_history.json` entry**, storage copy only (the git copy is inside the commit it would name), captured after the push. Zero identity impact and **no volatile-list entry needed**, because `metadata_sha` hashes `metadata.json`, not `version_history.json`. | R21.5/R21.6, Task 15 |
| 2026-08-11 | **The trap: `datom_validate(fix = TRUE)` would silently strip `commit_sha`** when it re-uploads metadata from the clone. Resolved by treating the field as **derived, never authored** -- the repair path re-derives it from `git log`, so storage holds nothing unrecoverable and the "mirror is derived from git" invariant survives. AC25's third clause exists to catch this; a naive implementation passes everything else. | R21.7, I22, P26 |
| 2026-08-11 | **Precedent checked, not assumed** (public sources): dpbuild keeps no commit hash in the product repo -- `.daap/daap_log.yaml` is inside the commit -- and dpdeploy publishes it to a storage-side `dpboard-log` pin that dpi's `dp_list()` reads **with no git**. That log's composite key is `(dp_name, pin_version, git_sha)`, independently confirming that one content version can pair with several commits. datom needs no separate deploy pass (it already uploads after push) and adds no board-level index (per-artifact history already carries the sibling git fields). **Corrects an earlier claim in this conversation that dpbuild had no git-less readers -- dpi is exactly that.** | R21.9, design.md 21.5 |
| 2026-08-11 | Tasks: **new Task 15** (version-to-commit link) inserted after validate, since its repair-path behavior needs `datom_validate()` to exist. Old 14/15 -> 15/16. | tasks.md Phase D |
| 2026-08-15 | **E1 Q1 -- OWNER-DECIDED: whole-payload hashing.** `data_sha` covers members **and** their tags (a description is a tag). A set is citable, and "same cite, different tags" would lie to the consumer. A tag or description edit therefore **mints a new version** -- intended behavior. Consequence applied: **AC2 was wrong** as written ("identical member list is a no-op") and is now two-sided -- identical *payload* is a no-op, identical members with a changed tag is **not**. | R2.6, AC2, design.md 7.5 |
| 2026-08-15 | **E1 Q2 -- OWNER-DECIDED: dissolved by the omission rule.** A payload has no data cells, so `NA` could only arrive via optional fields. datom's existing "omitted, not nulled" convention (verified `R/read_write.R:302-305`) becomes the canonical form: absence means the field **does not exist**; `null` / `NA` / `""` are never representations of absence. A literal `NA` reaching the encoder is an **error**, not an encoding case, and goldens carry the refusal. Knock-on: the walk has **no `null` tag** (the earlier draft's `0x04` is dropped), and this is where sv1 legitimately diverges from cv1, which needs an NA mask byte because table cells *can* be missing. | R2.7, design.md 7.2/7.5 |
| 2026-08-15 | **E1 Q3 -- OWNER-DECIDED: empty set refused.** Mirrors cv1's zero-dim abort (verified `R/utils-sha.R:310-312`). Marginal utility -- the build package simply does not write the set until its first output exists -- and an empty citable product is semantically murky. Cheap to relax later, awkward to retract. AC5 updated: refusal is the **tested** behavior, not a documented maybe. | R2.8, AC5 |
| 2026-08-15 | **E1 Q4 -- OWNER-DECIDED: `schema_version` stays out of the payload and hash.** It describes the container format, not the content; in identity a format bump would re-mint every set with unchanged members -- the same failure the `volatile` list exists to prevent (verified `R/utils-sha.R:415-416`). | R2.9 |
| 2026-08-15 | **E1 Q5 -- OWNER-DECIDED: emitter-free structural hash.** Neither `jsonlite` nor a bespoke sv1 emitter is canonical, because **no serializer is in the identity path**. ~~sv1 is a deterministic walk of the parsed payload: radix-sorted keys recursively, fixed per-type leaf encoding with a domain-separation tag per type, `sha256("datom-sv1" \|\| encoded-walk)`.~~ **The walk formulation was SUPERSEDED 2026-08-16 by F-A** -- replaced by the hash-of-hashes construction; the *decision* (no serializer in the identity path) stands unchanged. Stored-file formatting is free, because stored-byte integrity is `document_sha`'s separate job -- **identity and storage integrity never share a dependency**. Goldens and `dev/datom_sv1_reference.R` are written against ~~the walk spec~~ **the encoding specification as it now stands (superseded wording: "the walk spec")**, not any emitter's output. | R2.10, design.md 7.2/7.4 |
| 2026-08-15 | **R2.5's force stands; its mechanism is superseded.** The write/read agreement constraint is unchanged, but it is no longer achieved by normalizing through `serialize -> parse -> encode`. Each mutation is eliminated at source instead: numbers always f64 (kills integer-vs-double), `NA` aborts (kills the `"NA"` string and `null` cases), and scalar-vs-array is decided by an explicit R-type rule. **Verified bonus**: the one supporting condition -- reading with `simplifyVector = FALSE` -- is *already* satisfied deliberately by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`, the latter documented as "keep lists as lists"). So the decision is supported by existing infrastructure rather than imposing a new read-path requirement. | R2.5, design.md 7.1/7.3 |
| 2026-08-15 | **sv1 does not inherit the `metadata_sha` emitter exposure** (section 16). The earlier "cannot both be right" tension is resolved one-sidedly: sv1 is clean by construction, which *sharpens* rather than softens the case for the separate `metadata_sha` issue, since it becomes the only hash in datom whose value depends on a third-party formatter. Scope of that issue unchanged; priority arguably rises. | design.md 7.4, 16 |
| 2026-08-15 | **E1 downgraded from open-question debate to design review.** Gate for Task 2 is now: exact byte rules, whether the tag table leaves a collision surface, and whether the goldens cover the 7.3 agreement cases. Goldens still freeze the encoding -- a later change needs a conscious `datom-sv2` bump. | design.md E1, Task 2 |
| 2026-08-17 | **Final pre-implementation review (independent, adversarial). 20 findings, all triaged; the 5 blockers are fixed.** Verified the factual ones against the tree first. **Blockers**: (1) Task 2's R2.5 bullet still instructed "numbers always f64" and "scalar-vs-array decided by an explicit R-type rule" -- both removed mechanisms, in the bullet that governs the goldens; (2) Task 2's Q5 bullet still specified the superseded type-dispatch walk *immediately before* the bullet declaring it superseded, so a top-down reader implements the wrong one; (3) **I13 as worded mandated the removed serialize/parse pass and contradicted AC13**; (4) **no public parameter existed for set-level tags**, which R2.12 requires, R2.6 hashes, and AC2's converse half tests -- while R1.4 withholds `metadata =`, so the surface could not express a required payload; (5) **a third manifest write site exists** at `R/sync.R:721` (the absent-manifest skeleton) that the "two write sites / eight total" enumeration missed. | R2.5, R12.2, I13, design.md 9 |
| 2026-08-17 | **(review) `R/sync.R:969` is the dangerous manifest site.** It builds `list(project_name = ..., tables = list(), summary = list())` when `.datom/manifest.json` is absent, so left unrenamed it writes a `tables` key *after* the rename -- and it fires only on a fresh or repaired repo, so per-chunk tests against an existing fixture pass while the bug ships. Counts corrected to **3 write + 6 read = 9 sites**. One sub-claim of the review was **wrong**: `R/conn.R:522` *is* the `tables` line (the review said 520); citation left as-is. | design.md 9, Task 6 |
| 2026-08-17 | **(review) three code citations were wrong when written** (verified `R/` is byte-identical since `b57cdba`, so this is not drift): `R/validate.R:386` -> **391**; the `parquet_sha` verification gate `R/read_write.R:217` -> **227**; `.datom_resolve_version()`'s history read `R/read_write.R:177` -> **187** (with `129` for the current-metadata read). Also `R/utils-git.R:154-159` -> `131-161`, abort at `160`. These matter because design.md section 1 instructs "cite these rather than re-deriving them", so wrong numbers propagate into code comments. | design.md 1 |
| 2026-08-17 | **(review) duplicate members were undefined -- now refused** (R2.14). ~~`set()` concatenates member digests with **no** `sort` and **no** `unique`, so `[m, m]` and `[m]` hash differently: members are the one position where duplication *is* identity.~~ **SUPERSEDED 2026-08-17 by D2** -- `set()` now sorts and dedupes, so `[m, m]` and `[m]` hash **equal** and the encoder was never ambiguous. The refusal survives with a different justification: R2.15 canonicalization would silently drop the second copy, and a set listing the same datom version twice has no meaning, so an abort is the honest outcome. Nothing said whether it was legal, so the goldens would have frozen an accident either way. | R2.14, AC27 |
| 2026-08-17 | **(review) the empty-tag-value refusal had no test, and `""` was undefined** -- both settled in R2.14 and AC27. `character(0)` means "no labels", which R2.7 spells by omitting the key; `""` is a label with no name and is likewise refused. R2.7 only said `""` never represents *absence*, which left the separate question of whether it is a legal *label* to be decided by the encoder by accident. | R2.14, AC27 |
| 2026-08-17 | **(review) the `document_sha` integrity gate had no acceptance criterion** -- the one thing design section 8 calls "building a silent-degradation path on purpose" if got wrong. New **AC28** covers both halves: mismatched bytes refused *before parsing*, and a **missing/empty** `document_sha` an **error rather than a skip**. The second half is what a naive copy of `.datom_read_parquet()`'s `if (!is.null(...) && nzchar(...))` guard gets wrong. Task 10 now claims it. | AC28, I3, P9 |
| 2026-08-17 | **(review) Tasks 6 and 14 had no `Acceptance:` line at all**, and Task 16's sweep stopped at AC26 (omitting AC27). Both fixed; Task 14 also now owns a test for P14, which had no AC despite R11.3 calling it "in scope rather than deferred". Seven properties were orphaned (defined, referenced by no task) -- P25/P29 attached to Task 9, P4/P8/P28/P30/P31 to Task 2. | Tasks 6, 9, 10, 14, 16 |
| 2026-08-17 | **(review) three more stale-mechanism references removed**: Task 9 named "the cycle walk's root" as a precondition (there is no cycle walk, and I10a forbids one); Task 14 promised a git-vs-storage payload comparison justified by "R6.1b's git retention", which R6.1b reversed; and the **pathway route card in design section 17 instructed "or recurse"**, contradicting I10 -- that one becomes shipped user documentation in Task 17. Also fixed: the section 19.3 repo sketch still showed `{data_sha}.json` in the git tree, the exact layout AC24 fails. | Tasks 8, 13, design.md 17, 19.3 |
| 2026-08-17 | **(review) "structural walk" wording survived in R2.2 and three design summary rows**, contradicting R2.10 three paragraphs later. That wording is what seeded F-A, so leaving it in the summaries is how it returns. Restated. Plus cosmetics: P8 asserted independence from `size_bytes`, which R1.4 removed from set metadata (vacuous); the AC count "nine" is now 28; and the one-spelling rule was cross-referenced to R2.10 instead of R2.7. | R2.2, P8, design.md 7 |
| 2026-08-16 | **(F-A, BLOCKER -- verified) the closed grammar could not derive the payload shape.** R2.11 said `value ::= string \| [string, ...] \| object`, but R2.12 required `members: [{...}, ...]` -- an **array of objects**, which had no production; R2.10 reinforced it ("only three types to tag") and the encoder's `0x05` was named *string* array. Confirmed by reading both against each other: two requirements that could not both be true, same class as F4. An implementer would have improvised -- read `0x05` as a generic array, or invent a fourth tag -- and **frozen the choice into the golden vectors**, which is what E1 exists to prevent. | design.md 7.2.1 |
| 2026-08-16 | **(F-B -- verified) tag-value array order was identity, and should not have been.** design.md justified order-as-identity with "member order is a curatorial choice the user sees and controls" -- right for `members[]`, wrong for tag values, which the same rule also caught. Confirmed: R2.12 covered member order and tag *key* order but was **silent on tag value order**, so it fell through to the generic array rule. Since a multi-valued tag models *simultaneous folder membership* (R4.6), which is unordered, `domain: ["safety","efficacy"]` vs reversed would have minted a new **citable version** for a semantically null reorder. Does not weaken Q1: a tag *edit* minting a version is intended, a *reorder* is not an edit. | design.md 7.2.2 |
| 2026-08-16 | **Resolution 1 -- `id` split from `tags` in the payload** (R2.12). The payload holds exactly two kinds of content: a well-specified reference record with fixed single-string keys, and an open tag map. Made structural rather than four fixed fields sitting loose beside a nested map. Tags stay per-member (R4.6 unchanged). | R2.12, R4.1, R4.6 |
| 2026-08-16 | **Naming: `id` -- CONFIRMED (owner, 2026-08-16).** Chosen over `ref` / `pointer` / `datom_id`: `ref` collides conceptually with `ref.json`, which means data *location*; `datom_id` is redundant inside datom's own payload; `pointer` is wordy; and project+name+version genuinely *is* the member's identity. **Now settled -- the key name is hashed, so it is frozen by the goldens exactly like the encoding.** Changing it after Task 2 is a `datom-sv2` bump, not an edit. | R2.12 |
| 2026-08-16 | **Resolution 2 -- the walk is replaced by a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10). `str` / `strset` / `map`, then `member` / `set`. Mirrors cv1's per-column-digests-then-hash-the-concat pattern. **Closes F-A** because there is no generic `value` type left to be incomplete: every position's shape is fixed by where it sits, so the encoder never dispatches on runtime type and cannot have a gap. **Closes F-B** because ~~`members` is the only `concat` without a `sort`~~ **SUPERSEDED 2026-08-17 by D2** -- members are now sorted and deduped too, so the claim is stronger than it was: *every* collection is sorted, with no carve-out at all. Tag keys and values were always sorted, and values deduped, so "is this ordered?" is never a judgment call. | R2.10, P30, P31 |
| 2026-08-16 | **`f64le` disappears from sv1 entirely.** Every intermediate is a fixed 32 bytes, so concatenation is already unambiguous (`h("a")||h("b")` is 64 bytes and cannot collide with `h("ab")` at 32) -- no length prefixes needed. Consequence: `.datom_encode_numeric()` is not used **at all**, not even for lengths, so sv1 shares no numeric primitive with cv1. | design.md 7.2 |
| 2026-08-16 | **`id` is encoded with `map`, not positionally.** A fifth id field later is then just another key -- no positional convention, no absent-versus-empty question -- and one encoder serves both `id` and `tags`. Id values are single strings encoded as one-element strsets; validation separately enforces "exactly these four keys, each single-valued", keeping the encoder out of validation's job. | R2.10 |
| 2026-08-16 | **Resolution 3 -- a single string equals a one-element set** (R2.13). `type: "output"` and `type: ["output"]` hash identically, because every map value passes through `strset`. This **reverses** AC13's surviving fixture, which required them to differ: both spellings mean one label named output, so distinguishing them would mint a citable version over a purely syntactic authoring choice -- the same objection that killed tag-value ordering. Net effect: **every AC13 hazard becomes unrepresentable rather than handled**, so P28's goal is reached completely rather than partially. | R2.13, P28, AC13 |
| 2026-08-16 | **R2.5's residual condition narrows to structure.** With leaves order-, duplication- and shape-insensitive, `simplifyVector = FALSE` matters only so `members[]` stays a list of records instead of collapsing into a data frame -- leaf-level simplification is now immaterial. Both backends already do it deliberately. | R2.5, design.md 7.3 |
| 2026-08-16 | **AC13 fixtures replaced**: (a) tag-value order equal, (b) tag-value duplication equal, ~~(c) member order different~~ **SUPERSEDED 2026-08-17 by D2 -- member order is now equal**, (d) single string vs one-element array equal. The old "length-1 vs bare string must differ" fixture is **inverted**, and the number/boolean fixtures were already inapplicable. | AC13 |
| 2026-08-15 | **The payload is text-only, and that is a closed grammar** (R2.11). Values are UTF-8 strings or arrays of strings; **no numbers, booleans, `null`, or nesting beyond the fixed shape** (R2.12). Rationale: tags replace folder-style organisation and folder labels are text, so numbers and booleans buy nothing datom uses while costing an integer-vs-double rule, a boolean tag, and a wider golden matrix. A numeric tag is written `"500"` and parsed downstream, exactly as a folder name would be. | R2.11, I24, AC27 |
| 2026-08-15 | ~~**Consequence: the walk collapses from five type tags to three** (string / string-array / object)~~ **SUPERSEDED 2026-08-16 by F-A** -- the type-dispatch walk is replaced outright by the hash-of-hashes construction, so there is no type-tag list at all. The *reasons* below still hold (numbers/booleans/null are not in the grammar); only the mechanism changed. (string / string-array / object). Three of R2.5's four agreement hazards become **unrepresentable rather than handled** -- int-vs-double and `NA_real_` because there are no numbers, `null` because absence is omission. Only scalar-vs-length-1-array remains an actual rule. `.datom_encode_numeric()` is no longer reused for payload values; only its `f64le` length framing is shared, for lengths datom computes itself. | design.md 7.2/7.3, Task 2 |
| 2026-08-15 | **Tags are per-member** (R4.6), and `datom_member()` gains `tags = NULL`. What they replace is dpbuild's nested product list (`dp$input$raw_ae()`, `dp$output$derived1`, `dp$metadata$data_def`), whose top-level names classify **items**, not the collection -- confirmed by #89's own rejected alternative, which flattened to `(name, project, version, tag_key, tag_value)`, one row per member per tag. Set-level tags are also allowed, for facts about the collection such as a description. | R4.6, Task 8 |
| 2026-08-15 | **A tag value may be a string OR an array of strings**, and that is the *only* reason arrays exist in the grammar. The motivating limitation of folders is that an item cannot be in two at once, so multi-valued tags (`domain: ["safety", "efficacy"]`) are the point rather than an extension. | R2.11, R4.6 |
| 2026-08-15 | **#89's "view config" is retired; no navigation structure is stored at all** (R4.7, I25). Folder-like hierarchy is a **projection**: prioritise one ordering of tag keys at gov level and you get one structure, prioritise another and you get a different one -- so structure is presentation, not content. This retires the "nested view config does not survive the flattening" argument, since navigation *is* the tags, and it is what makes the text-only grammar sufficient. Bonus property: arbitrarily many folder structures cost nothing because none is stored. | R4.7, I25, P29 |
| 2026-08-15 | Closures stay downstream: dpbuild's inputs are lazy closures, whereas a datom member is a pointer and `datom_read()` is the lazy fetch. Assembling closures is the build package's job -- the layering #89 asked for. No datom change. | design.md s4 |
| 2026-08-15 | **Git-commit-linkage follow-ups asked and confirmed as-is, no change** (R20/R21): (a) lagging `commit_sha` into the git copy on a subsequent write, (b) moving the linkage into governance, (c) recording *all* producing commits rather than the first. Examined; the existing spec answers hold -- (a) leaves the newest version permanently unlinked, (b) makes a git-less-reader convenience depend on gov being attached, (c) turns an immutable history entry into an append target. Logged so they are not re-litigated. | R20, R21 |
| 2026-08-11 | **Process lesson recorded, not patched over.** The nesting machinery entered via review finding F1, which correctly spotted a contradiction between two spec statements and was resolved by *adding* guards rather than by testing whether either statement was true. Both were false. When a review surfaces a contradiction, **check the premises before building something to reconcile them**. | design.md 18 (F1 row), 20.11 |
| 2026-08-11 | **AC1 split** into (a) resolve pointers -- always works, no clone -- and (b) resolve to data -- needs that member's project conn. Conflating them mis-implements a set read as "requires access to everything in it". `datom_validate()`'s member check scoped the same way (R11.2), reusing `members_unresolvable`. | AC1, R11.2, Tasks 9 and 13 |
| 2026-08-17 | **Task 1 scope deviation -- OWNER-APPROVED, the guard stays.** Folding `.datom_validate_sha()` into `.datom_artifact_payload_key()` exceeded the chunk's behavior-identical scope, because it closed a real path-traversal gap at `.datom_validate_one_table()` (`R/validate.R:393`) that #74's sweep missed -- a file-supplied `data_sha` spliced into a storage key unvalidated -- and cost one test fixture using an impossible `data_sha = "d1"`. Kept rather than reverted: the alternative leaves a known gap behind a tracking issue competing with 15 remaining tasks, for a purity cost of one fixture line. Behavior for valid data is unchanged. | Task 1, I9, `R/utils-path.R` |
| 2026-08-17 | **Reader-side version diff needs no schema change -- option 3 chosen.** A git-less reader can already diff two set versions with three small JSON reads: `version_history.json` (which carries `data_sha` per entry today, `R/read_write.R:485-491`) to map version -> `data_sha`, then the two content-addressed payloads. **Rejected: persisting per-member digests in metadata** as a `column_hashes` analogue (see design.md 15 for both rejected options). The decisive points: the payload diff reports **actual values** where digests report only "something changed"; `column_hashes` earns its place solely because the alternative is downloading parquet, which does not transfer to a small text payload (design.md 4, "a member index would be metadata-for-metadata"); and there is **no code to reuse** -- `column_hashes` has no consumer in `R/` and `datom_diff` is unbuilt (#73). Member digests remain **additive and volatile**, so they can be added later without a schema break or identity change if a cross-version change timeline proves to be a real need. **No impact on Task 2**: sv1's encoding is identical under this decision, since it would only have published intermediates the hash-of-hashes already computes. | design.md 4 + 15, R6, Task 10 |
| 2026-08-17 | **E1 design review (Task 2 gate) -- four deltas, all owner-approved before goldens freeze.** The encoding itself reviewed clean: domain separation is sound (distinct marker byte per constructor, so cross-type collisions reduce to sha256 collisions); "framing is free" verified (every entry fixed-width -- `map` entry 64 bytes, `member` 64, `set` 32+32n -- so concatenation parses unambiguously without length prefixes); `sort(method = "radix")` is C-locale byte order as claimed; `id`-vs-`tags` slot swapping cannot collide. The four findings are all **additive**, not a redesign, so no model escalation beyond this review. | design.md 7.2-7.2.3, R2.12-R2.17, R7.5 |
| 2026-08-17 | **(D2) Member order is NO LONGER identity** -- `set()` sorts and dedupes member digests like every other collection. **Owner-raised**: order buys nothing since nothing consumes a set positionally. Three arguments, any one sufficient: it contradicted R4.7 (arrangement is presentation, which is why no hierarchy is stored); it contradicted 7.2.2's own reasoning, which killed tag-value ordering for the identical reason; and decisively, the expected producer is a **script**, so an insertion-order refactor would mint a new product version with byte-identical content -- the #72 failure class. Costs one `sort()` over fixed-width digests. **Bonus: 7.2's only carve-out disappears** -- every collection is sorted and deduped, one rule with no exceptions. Reverses P3 and AC13(c); R2.14's duplicate-member rationale changes (the encoder was never ambiguous, and now R2.15 would drop the copy silently, which is better surfaced as an abort). | R2.12, R2.14, P3, P30, AC13(c), design.md 7.2 + 15 |
| 2026-08-17 | **(D1) The payload is canonicalized BEFORE the local write** (R2.15, I26) -- sort map keys, sort + dedupe tag values, **unbox single values**, sort + dedupe members. **Owner-proposed**, and better than the reviewer's original framing, which only guarded the write path: canonicalizing at the source means one content has exactly one byte spelling in git and in storage, so the ambiguity is removed rather than managed. Unboxing (not always-array) because `auto_unbox = TRUE` is already the house default in datom's metadata writers -- the free direction -- and it keeps the `git diff` of R6.1a readable. **Shape unification was a gap in the reviewer's first draft of this delta**, caught by the owner: sorting alone still leaves `"output"` vs `["output"]` as two spellings. sv1 stays order- and shape-insensitive regardless, since the hash domain is a *parsed file* that may predate this rule or have been hand-edited: canonicalization is belt, insensitivity is braces. | R2.15, I26, AC29a, Task 9 |
| 2026-08-17 | **(D3) One `data_sha`, one byte spelling, enforced over time** (R7.5, I27). Two rules, both required: never re-emit a payload for a `data_sha` already in history (reuse the stored object, **carry the recorded `document_sha` forward** -- the exact `.datom_lookup_history_parquet_sha()` pattern at `R/read_write.R:404-409`), **and** hold `datom_validate(fix = TRUE)` to the same rule, since it re-uploads from the clone and so is a live path to overwriting a stored object with non-matching bytes. Same trap shape as the `commit_sha` one (R21.7/I22): a repair path silently undoing a write-path guarantee. **Sharper for sets than tables**: divergent bytes for one `data_sha` need an `arrow` upgrade for a table but only a tag-value reorder for a set, and only sets keep the payload in git. **Deliberately assigned to Tasks 8 and 13, not 2** -- it is a consequence of Task 2's decisions but not encoder code, and a Task 9 implementer assuming "new bytes mean a new `document_sha`" ships a defect that every per-chunk test passes. | R7.5, I27, P32, AC29, Tasks 8 + 13 |
| 2026-08-17 | **(D4) No Unicode normalization; tag bytes are hashed as given** (R2.16). NFC and NFD are different tags. Rejected NFC-first because **normalization tables are versioned Unicode data**, so a Unicode release could re-mint hashes -- the #72 failure mode with the Unicode Consortium in `arrow`'s role, and sv1 exists to keep everything versioned out of its identity path (7.4). Also avoids adding `stringi` to a lean `Imports`, and stays consistent with cv1, which already treats NFC-vs-NFD as identity-relevant (`dev/e2e-cv1-identity.R`). Stated normatively because it would otherwise be settled by accident, and a non-R implementation might normalize by default. Golden asserts they differ. | R2.16, P33, AC13(f) |
| 2026-08-17 | **(D5) `strset(character(0)) = h(0x02)` is pinned** (R2.17). Validation refuses empty tag values and R2.15 cannot produce one, but the encoder must not depend on that -- the argument design.md 7.2 already makes for the empty map: an encoder whose correctness rests on an upstream refusal breaks silently the day the refusal is relaxed. Carried as a golden. | R2.17, AC13(g) |
| 2026-08-17 | **(D6) AC13 grows from four fixtures to seven**, and AC29 is new. Equal: tag-value order, tag-value duplication, **member order**, single-vs-one-element-array, **member duplication**. Different: **NFC vs NFD**. Constant: **empty strset**. Two fixtures now **reverse** earlier "must differ" versions -- member order (D2) and single-vs-array (the 2026-08-16 delta). AC29 covers canonicalization on the file bytes, no-re-upload on a known `data_sha`, and the `validate(fix = TRUE)` clause that a naive implementation fails while passing the other two. | AC13, AC29 |
| 2026-08-17 | ~~**Process: D2's sweep hit the four places tasks.md warns about**, confirming the documented defect pattern rather than discovering a new one.~~ **CORRECTED same day -- it was six sites, not four, and the first sweep missed two of them.** Independent review found three (Task 2's goldens bullet, plus two log rows in present tense); tightening `check-spec.R` then found a sixth. Worse, **two were live instructions, not log rows**: Task 2's fixture list still said "member order different" *in the task that freezes the goldens*, and `requirements.md` R2.10 still carried "`members` is the only `concat` without a `sort`". An implementer working top-down from either would have frozen the wrong fixture, and undoing that is a `datom-sv2` bump. | R2.10, R2.12, AC13, Task 2 |
| 2026-08-17 | **`check-spec.R`'s retired-wording check was close to vacuous, and this is the round that proved it.** It passed on all six D2 sites. Cause: `MARKER_RE` -- the suppression list -- carried generic negation and impossibility cues ("never", "cannot", "not needed", "not required", "acyclic", "impossible", "unrepresentable", "immaterial", "dissolve", "collapse") on the reasoning that the commonest legitimate mention is a sentence saying the thing is NOT done. That reasoning fails at scale: those are ordinary vocabulary in this spec, so nearly every +/- 2 line window contained one. **The clearest case is self-suppression** -- "`members` is the only `concat` without a `sort` ... is never a judgment call" was excused by the word `never` in its own sentence. Fixed by narrowing to explicit supersession and explicit prohibition only; the tightened check immediately found the sixth site unaided. Tradeoff stated in the script: a false positive costs one marker word, a false negative ships a retired instruction that reads authoritative. | dev/check-spec.R |
| 2026-08-17 | **Denylist additions from D2**: "only unsorted concat", "only `concat` without a `sort`", "order is curatorial", "duplication \*is\* identity", "member order different", "member order.{0,20}differ". The last two are the phrasings that actually survived the first sweep, so they are the ones with demonstrated escape history. | dev/check-spec.R |
| 2026-08-17 | **A recurring trap shape, now named after its second instance: a repair path silently undoing a write-path guarantee.** `datom_validate(fix = TRUE)` re-uploads from the clone, so it is a general-purpose way to overwrite storage with derived content. Instance 1 was `commit_sha`, which repair would have **stripped** (R21.7, I22, AC25's third clause); instance 2 is `document_sha`, which repair would **invalidate** by re-emitting bytes for an existing `data_sha` (R7.5 rule 2, I27, AC29c). Both were caught only because someone asked "what does `fix = TRUE` do to this field?" **Any future spec adding a metadata field should answer that question explicitly**, and the acceptance criterion belongs on the repair path, not only the write path -- in both instances the repair clause is the one a naive implementation fails while passing everything else. | R7.5, R21.7, I22, I27, AC25, AC29 |
| 2026-08-17 | **Thorough post-delta review: 19 findings, all fixed.** Prompted by two prior sweeps each missing defects. **The decisive one was self-inflicted**: the sv1 pseudocode exists in all three spec files, the D2 fix touched only `design.md`, and `requirements.md` + `tasks.md` were left stating `concat( member(m) ... )` with no sort -- the second of those inside the task that freezes the goldens, eleven lines above prose saying the opposite. Every multi-member golden would have been wrong. Seven blockers total; the rest were ownership gaps and stale counts. | R2.10, design.md 7.2, Task 2 |
| 2026-08-17 | **TIDY FIRST, THEN VALIDATE -- owner-decided, and it reverses the reviewer's recommendation.** The reviewer proposed validate-then-canonicalize to keep the R2.14 refusals reachable. The owner's principle is better: *handle any trivial error without pestering the user; refuse only what is deliberate or unhandleable*. Six spellings are now **tidied silently** because nobody can reasonably care about them -- tag-value order, tag-value duplication, single-vs-array shape, member order, an exact-duplicate member, and `character(0)` dropping its key. Five are **refused** because each would require guessing intent -- non-text values, `NA`, `""` as a tag value, same-`id`-different-`tags`, and zero members. Tidy-first also composes better than validate-first: it clears the benign cases so validation only ever sees genuine ambiguity. | R2.14, R2.15, AC27, design.md 21.4 |
| 2026-08-17 | **Working through "which duplicates are benign" exposed a case both sweeps missed: same `id`, DIFFERENT `tags`.** `set()` dedupes by `member()` digest and the digest covers tags, so these have *different* digests and **dedup does not catch them** -- both entries survive, and a consumer projecting tags finds one member in two conflicting folders. That is one fact with two spellings; the intended form is a single entry with a multi-valued tag. **Refused**, because both ways to tidy it guess: merging tags is right if the caller meant both categories and nonsense if two code paths disagreed, and picking one entry is arbitrary. | R2.14, AC27(d) |
| 2026-08-17 | **Same NAME at different VERSIONS is legal and is NOT a duplicate (R2.14a) -- owner-raised.** `adsl@a1b2` and `adsl@f9e8` are different members with different content; a product carrying a current table beside a locked baseline is atypical but entirely sensible. **The duplicate check keys on the FULL `id`, never on `project`+`name`.** Given its own test precisely because `project`+`name` looks like the natural key, so the first reader to "tighten" it would silently break a legitimate use. Three consequences recorded: the R2.15 file sort key **must** include `version` (or two versions of one name have no defined relative order and canonical form is undefined); consumers disambiguate by tag, datom adds no warning since one firing on legitimate use is noise; and a future reader-side diff cannot key on `project/name` alone -- it should key on `project/name` where unique and fall back to including `version` where not. **The diff demo shown in this conversation had exactly that bug.** | R2.14a, R2.15, AC27 |
| 2026-08-17 | **(L2) The file's member sort key differs from the hash's, deliberately -- owner-approved.** Hash sorts `member()` digests (self-contained: the encoder never needs to know what an `id` looks like, which is what keeps "a fifth id field is just another key" true). The **file** sorts by `project` \|\| `name` \|\| `version`, because digest order would relocate a member whenever its tags change -- so `git diff` would report a delete plus an insert in a different place, with everything between shifting, instead of one changed field. That undoes R6.1a's entire purpose, which is D1's own justification. Both keys are fully deterministic, so "one content, one byte spelling" holds either way. Cheap now, and **expensive later**: once payloads ship, changing canonical file order is a canonical-form change that I27 forbids. | R2.15, R6.1a, P25, AC24 |
| 2026-08-17 | **AC27 ownership split; AC29c given an owner.** AC27 was claimed by **both** Task 2 and Task 9 while `design.md` 7.2 says the encoder stays out of validation's job -- and neither owner could enforce two of its clauses: `datom_member()` sees one member at a time so cannot detect a duplicate, and set-level `tags` never pass through it. Resolved: per-member grammar (non-text, `NA`, `""`) to Task 8; payload-level cases (same-`id`-different-`tags`, zero members, set-level tag grammar, every tidy assertion, and the R2.14a allow-case) to Task 9; **Task 2 owns none of it**. Separately, **AC29c had no acceptance line anywhere** -- discussed in Task 14's body, listed nowhere, outside Task 16's sweep range. The clause the spec twice calls "the one a naive implementation fails while passing everything else" was owned by nobody; now Task 14's. | AC27, AC29, Tasks 2/8/9/14 |
| 2026-08-17 | **AC13 split into payload-level and encoder-level, because its umbrella was unsatisfiable.** The umbrella asserted write/read `data_sha` agreement for every fixture, but (g) `strset(character(0))` is a primitive constant with no payload and no `data_sha`, and (e) member-duplication cannot be built through the public path since R2.14 tidies it. **AC13-P** keeps the umbrella (a, b, c, d, f); **AC13-E** calls the encoder directly (e, g). Also pinned: (f) NFC/NFD fixtures **must use `\u` escapes**, since they ship in `tests/` and AC11 holds `R CMD check --as-cran` at zero warnings. | AC13, AC11 |
| 2026-08-17 | **`check-spec.R` gains a root-cause check, and it is verified non-vacuous.** The two classes that survived three sweeps were both **duplicated content**, which no prose denylist can reach: the encoder pseudocode is written out in all three files, and the AC count/range was hardcoded in four places and went stale twice (stopped at AC26 omitting AC27; then at AC28 omitting AC29). New check 6 compares the six encoder rules across files after whitespace normalization, and forbids any explicit AC upper bound. **Tested by reintroducing the exact `set(p)` defect that survived three sweeps** -- the check fails, names `set(p)`, and prints the odd file out. Recorded because the previous round's lesson was shipping a check nobody proved worked. | dev/check-spec.R |
| 2026-08-17 | **Lesser fixes in the same pass**: `design.md` 21.4's write-order table -- the only end-to-end set write order -- had **no canonicalization step and no validation step**, and uploaded the payload unconditionally in contradiction of R7.5/I27/AC29b; now carries steps 0a/0b and a conditional step 6. Member-digest sort collation pinned to lowercase hex + radix (`strset`/`map` spelled it; the member sort did not). R7.5 rule 2 now forbids **re-uploading the bytes** as well as recomputing the hash -- forbidding only the recompute still permitted the worst outcome. `member_count` pinned as the **post-tidy** count. Task 2's `Requirements:` line no longer claims R2.15. Three stale "the E1 review is still pending" blocks updated (`tasks.md`, `design.md` 12, `dev/README.md`). Call-site count corrected 8 -> 9 at `design.md` 12. R2.14/R2.13 numbering left out of reading order deliberately -- the numbers record decision order, and renumbering would churn every reference. | R2.15, R7.5, R8, design.md 12 + 21.4 |
| 2026-08-17 | **(review hardening 1) R2.15 step 4's sort tie is unreachable, and that is now stated.** Two members can share `project` \|\| `name` \|\| `version` in exactly one situation -- the **same `id` with different `tags`**, which survives dedup because the `member()` digest covers tags. Because tidy runs before validation, the sort can meet that tie and R's stable radix sort resolves it to caller input order; harmless, since R2.14 refuses that payload one step later so no tie reaches a written payload. Recorded because an implementer reaching step 4 will ask what to do about ties and might add a **dead-code tiebreaker** or escalate. Explicitly **not** fixed by hoisting the refusal before tidy: the phase separation is worth more than removing an unreachable edge, and inverting it would make the tidy rules unreachable instead. Also noted that the key omits `kind` safely -- AC4 refuses cross-kind name collisions, so `kind` could never break a tie the rest of the key did not already decide. | R2.15, R2.14, AC4 |
| 2026-08-17 | **(review hardening 2) `check-spec.R` check 6 detected disagreement but not ABSENCE -- fixed, and the reviewer found one hole while there were two.** Comparing present copies is insufficient: delete a rule from one file and the survivors still agree. **Demonstrated before fixing** -- deleting `str(s)` from `requirements.md` gave `ok  duplicated content agrees -- 6 encoder rules consistent`, exit 0, the count still reading 6 because the key survived via the other two files. The second hole, unreported: with a rule deleted from **all three** files the key vanished from the loop's index and was **not checked at all**. Both closed by iterating `CODE_KEYS` rather than observed keys and asserting presence in every spec file. Matters most for `requirements.md`, where R2.10 *defines* the encoding -- if the formula vanishes there the requirement stops stating what it requires, and the next editor updates the two files that still carry it without learning a third did. Verified non-vacuously in both directions: one-file deletion and all-file deletion each FAIL naming the missing file(s), and restore returns to pass. | dev/check-spec.R |
| 2026-08-17 | **Cold-start audit: five things would have tripped a fresh session; all fixed.** Asked whether Task 2 could be started in a new session, the documented cold-start path (`dev/README.md` Active Specs -> this file's state block -> the task) was walked as a cold reader. **(1) The state block contradicted itself** -- "it carries the E1 escalation, and per rule 5d that recommendation must be surfaced *before* implementing" followed two sentences later by "that review is DONE". A fresh session obeying rule 5d would have re-run the review, relitigating settled decisions and re-freezing specified goldens. Rewritten as an explicit **discharge record**, and Task 2's heading now reads "design review DONE 2026-08-17; implement, do not re-review". **(2) The `check-spec.R` description listed five checks when there are eight**, omitting check 6 -- the one that guards the pseudocode Task 2 is about to implement from. **(3) The "repeating defect pattern" advice was stale**: it said to add retired phrasing to the denylist, which is now known to be the weaker half; the pseudocode is guarded mechanically and prose is not, so the advice is split into four numbered steps. **(4) `R/hashable-set.R` vs extending `R/utils-sha.R` said "decide at the review"** -- a dangling instruction once the review closed. Decided: new `R/hashable-set.R`, because sv1 shares no primitive with `utils-sha.R`'s three unrelated concerns and that file is already 565 lines. **(5) One Q5 log row still said goldens are "written against the walk spec"**, retired wording outside its strikethrough. | tasks.md state block, Task 2 |
| 2026-08-17 | **Check 6 is strict enough to flag a spec author *quoting* a stale AC range as a bad example.** Hit while writing the anti-pattern guidance itself. Resolved by describing the shape in words rather than exempting the check -- same call as the `manifest$tables` note in the `retired` denylist, where a phrase is load-bearing in the instruction forbidding it. Recorded because the tempting fix is to loosen the check, and loosening is exactly what made the retired-wording check vacuous for six sites. | dev/check-spec.R |
| 2026-08-18 | **THE SV1 GOLDENS ARE PUBLISHED; THE ENCODING IS FROZEN.** Task 2 shipped the encoder, the standalone reference, and hard-coded goldens, with reference/package parity asserted on both architectures. Any byte-rule change from here is a conscious `datom-sv2` bump with a new `hash_algo`, not a spec edit and not a code fix -- so a failing golden means the code drifted. The values are tabulated in Task 2's DONE block. Nothing about the encoding as reviewed changed during implementation: all four E1 deltas (member order out of identity, canonicalize-before-write, `document_sha` byte identity, no Unicode normalization) plus the empty-`strset` pin landed as specified. | Task 2, R2.10, `R/hashable-set.R` |
| 2026-08-18 | **(implementation, and the one real find) a NAMED list in a value position must be refused, and the spec never said so.** Element-wise, `list(b = "c")` and `list("c")` are indistinguishable -- both are a one-element list holding one string -- so an encoder that validated only elements would hash `{"a": {"b": "c"}}` **identically to** `{"a": ["c"]}`. The inner key would sit outside identity, giving two different payloads one `data_sha` and therefore one storage address, which is the exact class of failure sv1 exists to prevent. Caught by a test written for P31 ("there is no object-valued position"), which is worth noting: the property was in the spec, the consequence was not, and it took writing the assertion to find the gap. Fixed in both the package and the reference (they must stay byte-identical), and it changes no golden -- it only converts a silent mis-encoding into an abort. | R2.11, P31, `R/hashable-set.R` |
| 2026-08-18 | **(implementation) the encoder also refuses an unexpected field at the payload root or inside a member record.** Same reasoning as the row above: an ignored field is content outside identity. Two useful consequences. It makes R2.9 **structural** rather than aspirational -- a payload carrying `schema_version` aborts instead of being quietly hashed without it -- and it means "a fifth `id` field is just another key" stays true at the `id` level (where `map` encodes whatever it is given) without also making the *member record* silently extensible. Not a contradiction of "the encoder does not validate": grammar enforcement with recourse (which key, what types are allowed) is still Tasks 7 and 8; these three refusals are the narrower "this cannot be encoded without losing content" class. | R2.9, R2.12, Tasks 2/7/8 |
| 2026-08-18 | **(implementation) `strset(list())` must equal `strset(character(0))`.** `[]` is the parsed-JSON spelling of an empty string set, and R2.5 write/read agreement requires both spellings to hash equal, so the R2.17 pin covers the parsed form too. Same shape of reasoning as R2.13 one level down. | R2.17, R2.5 |
| 2026-08-18 | **(implementation) two mechanical details, recorded because both are easy to get wrong on a re-read.** (1) Intermediates are **raw 32-byte vectors, not hex**: hex appears in exactly the two places the spec names it -- the member collation key and the final `data_sha`. Byte order and lowercase-hex C-locale order agree, so the collation claim holds either way. (2) The `NA` refusal sits **after** the type gate, with an all-`NA` logical caught ahead of it, because `is.na()` on a closure warns rather than answering -- a `tags = list(t = mean)` fixture otherwise emitted a warning against a suite held at WARN 0. A bare `NA` is logical, so it still gets R2.7's "omit the field" advice rather than a type error. | R2.7, `R/hashable-set.R` |
| 2026-08-18 | **(implementation) AC13-P is asserted through the real local-backend store**, not a hand-rolled `jsonlite` round trip, so the fixtures also prove the production write/read path preserves `members[]` as a list of records. That structural condition (the one residual of R2.5) is additionally asserted **on the parsed object** rather than inferred from the hashes matching, since a hash match cannot distinguish "structure preserved" from "two different structures that happen to hash the same". | R2.5, AC13, Task 2 |
| 2026-08-18 | **Cold-start audit for Task 3: enough context to start, after four additions.** The documented path (`dev/README.md` -> this state block -> the task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked against the tree. What was missing: **(1)** no file was named for the two exports -- decided **`R/storage.R`**, whose header already states the family contract, rather than a new file; **(2)** "the established bare-git-remote + local-store style" was a description with no citation, so it is now a pointer to a concrete exemplar (the example block above `R/storage.R:51`, used verbatim by all four existing storage exports); **(3)** "relative-key validation" implied a helper that **does not exist** -- `R/utils-validate.R` has only `.datom_validate_name()` (`R/utils-validate.R:18`) and `.datom_validate_sha()` (`R/utils-validate.R:68`) -- and the two things it must catch are different in kind, a traversal/shape concern that applies to **both** exports (reads are unrestricted as to *managed keys*, not as to escaping the namespace) and the full-key-where-relative-belongs case that silently double-prefixes rather than erroring; **(4)** no fixture or pkgdown location was named. Also recorded: **no `datom_storage_*` export checks `conn$role`**, including the destructive delete, so adding one here would break a family symmetry deliberately; `.access` appears nowhere in `R/`, so R19.6's by-construction claim verifies today; and P18 is satisfied by the managed-key refusal, not by any git interaction, so nobody should try to git-gate a byte-level primitive. | Task 3, R12.4a, I7, P18 |
| 2026-08-18 | **Two Task 3 decisions deliberately left for DESIGN rather than settled here.** (a) Whether the payload-key refusal is **existence-dependent** (R12.4a's literal wording, one storage probe per write) or **shape-only** (simpler, stricter, cheaper, and not defeatable by writing a payload before its artifact exists). Recommendation is shape-only -- a refusal is cheap to relax and a hole is expensive to find -- but it narrows a stated requirement, so it gets an explicit decision instead of a quiet reinterpretation. (b) How strict "payload-shaped" is: `{name}/{64-hex}` versus `.datom_validate_sha()`'s 6-64 hex range, which decides whether a downstream package may write `myset/abc123.json` as scratch. Both are public-contract choices of the same class as review finding F3, which is what produced R12.4a. | R12.4a, AC23, Task 3 |
| 2026-08-18 | **A trap noted for Task 3's docs**: the write export's roxygen example must use an **unmanaged** key. The natural-looking `"dm/abc.json"` after a `datom_write(name = "dm")` is precisely what the new guard refuses, so an example copied from a sibling export would abort under `R CMD check` -- a self-inflicted AC11 failure. | AC23, AC11, Task 3 |
| 2026-08-18 | **`CRAN-SUBMISSION` is not a tracked record and never was.** Verified with `git log --all -- CRAN-SUBMISSION` (empty) and its absence from `origin/main` and `origin/dev`, correcting the assumption that `main` held a submission record to protect. Per usethis, the file is a handoff artifact from `submit_cran()` that `use_github_release()` consumes and **deletes**, and **in its absence usethis assumes HEAD is the submitted state** -- so with the old acceptance order (merge `dev` into `main`, then tag) a missing artifact would silently name the merge commit rather than the submitted one. Resolved on this branch: `/CRAN-SUBMISSION` added to `.gitignore` (it sat untracked *and* un-ignored, so `git add .` could have carried it to `main` by merge -- newly relevant with Task 12 adding an add-all verb), `dev/README.md` gained a `CRAN-SUBMISSION` section plus a submitted-SHA table, and acceptance step 4 now publishes the release **before** merging. The artifact itself was left untouched. | dev/README.md, `.gitignore` |
| 2026-08-18 | **THE JSON WRITE EXPORT IS DROPPED -- owner-decided, and it dissolves both pending Task 3 decisions.** `datom_storage_write_json()` will not be built; Task 3 ships `datom_storage_read_json()` alone. **Owner-raised, and the challenge was the right one**: writing should be spelled `datom_write_set()`, and JSON is datom's internal design choice rather than a public surface. Verified before agreeing: the export's stated motivation in #89 was "a downstream package cannot write its own document into datom's namespace", the document was a set, and Task 9 now writes sets as first-class artifacts -- so **no consumer remains**. `datomanager` does not need it either: the Authority Principle in `dev/datomanager_scope.md` says "data-repo mutations always route through datom ... datomanager never touches the data repo directly", and its expression is a **purpose-built verb per need** (`datom_repo_set_data_store()`, `datom_repo_delete()`, `datom_repo_attach_governance()`), with the `governance.json` data-side mirror as the precedent for choosing a named export over a generic write. **A claim of mine was wrong and the owner caught it**: I said "datomanager does its own storage IO", which is true only of the **gov** namespace -- the `dev/README.md` backlog line I was paraphrasing has been corrected to say so. Retired with the export: R12.4a, I14, AC23. Restated: P18 (now satisfied because no general-purpose write exists, not because one is fenced) and R19.6 (`.access/` stays safe **by construction**, since datom adds no write path at all). Retained verbatim for revival: R12.4a's refusal analysis. **Deferral is the cheap direction** -- additive to add later, breaking to remove after release. | R12.4, R12.4a, I14, AC23, P18, R19.6, Task 3 |
| 2026-08-18 | **The one argument that survived for the write export, recorded as the Backlog trigger.** datomanager will need s3/local dispatch to write JSON into its **own gov namespace**, and reimplementing that duplicates platform code. That is a **different export** -- gov-scoped, with no managed-key refusal list -- for a package that does not exist yet, so it is speculative capability today. If the trigger fires, scope it to the caller's own namespace and **re-derive** the refusal list rather than assuming R12.4a's still fits. | R12.4a, `dev/README.md` Backlog |
| 2026-08-18 | **Process note: a review can be right about a hazard and still miss that the capability is unnecessary.** Review finding F3 correctly identified that a public JSON write could clobber managed keys, and its resolution (R12.4a's refusal list, I14, AC23) was sound *given* the export. What no round asked was **who still needs this export** -- a question that only had a new answer because `datom_write_set()` had since been specified. Recorded because the failure mode is invisible from inside a hardening exercise: every subsequent review inherits the premise that the capability is wanted. | design.md 18 (F3 row), R12.4a |
| 2026-08-18 | **The parity workflow was extended in place, as instructed, and its file name deliberately still says cv1.** It now runs both reference scripts and both parity test files across the x86_64 + arm64 matrix, keeping one matrix for a property that spans architectures, and it prints the sv1 goldens beside the cv1 ones so a divergence between jobs is readable in the logs rather than only as a failed expectation. The file keeps its name so existing links and any branch protection stay valid; the header comment now says it covers both regimes. | `.github/workflows/cv1-reference-parity.yaml`, R2.4, P12 |
| 2026-08-21 | **(implementation) the absent-key abort costs one extra storage round trip, on purpose.** `datom_storage_read_json()` probes `.datom_storage_exists()` before reading so the "not found" message is identical on both backends and names **the relative key the caller passed**. Without it the two backends diverge in the worst place: the local backend aborts clearly, while S3 surfaces the provider's own error naming the **full** key -- so a caller whose actual bug is key-shape confusion gets shown the very transformation they got wrong. Recorded because the probe looks like a redundant call to anyone optimizing reads later. | Task 3, `R/storage.R` |
| 2026-08-21 | **(implementation) the full-key refusal keys on a `datom` path segment, and that is exact rather than heuristic.** `datom` is in `.datom_reserved_names` (`R/utils-validate.R:2-6`), so it can never appear as a segment of a legitimate relative key -- which is what makes a cheap segment test a complete one for the double-prefix hazard. Also pinned in tests: the traversal guard fires on a whole `..` **segment**, not on the dot character, so `.metadata/manifest.json`, `my.data/abc.json` and `dm/..hidden.json` all remain valid keys. Worth stating because the tempting implementation is `grepl("\\.\\.", key)`, which would refuse datom's own metadata directory convention. | Task 3, `R/utils-validate.R` |
| 2026-08-21 | **(implementation) `.datom_validate_rel_key()` is deliberately NOT folded into the Task 1 key builders**, and the reasoning is the inverse of Task 1's own approved scope deviation. There, folding `.datom_validate_sha()` into a builder closed a real gap because a **file-supplied** sha reached a key unvalidated. Here there is no gap to close: the builders compose keys from parts already validated (`.datom_validate_name()` admits only `[a-zA-Z0-9_ ()-]` and must start with a letter; `.datom_validate_sha()` only hex), so their output cannot contain a `..` or `datom` segment and the check would be dead code. The distinction to carry forward is **composed from validated parts** versus **supplied whole by a caller** -- only the second needs a key validator, which is why the new export is its only call site. | Task 3, Task 1, I9 |
| 2026-08-21 | **(implementation) the no-role-check decision is now pinned by a positive test**, not left as an absence. A `role = "reader"` conn reads successfully, so the `datom_storage_*` family's policy-free symmetry (not even the destructive `datom_storage_delete_prefix()` gates on role) fails loudly if a future change breaks it. Same reasoning as Task 6's note that a silent failure mode needs a positive assertion rather than the absence of errors. | Task 3, Task 12 |
| 2026-08-21 | **The schema check covers SIX call sites, not the four Task 4 named -- owner-decided.** The task listed the reader paths that read through storage. The same manifest is also read from the **git clone** by `datom_sync_manifest()` and `.datom_status_input_files()`, and that copy goes ahead of the installed build by an ordinary route: a collaborator upgrades datom and writes, this developer pulls. The original justification for excluding them ("the spec says reader side") was scope citation rather than a reason, and did not survive being asked for. The four **in-pipeline** local reads stay excluded on a stated principle: the check belongs where a document **enters** datom, so a refusal happens before work starts rather than partway through a write. | R9.2, Task 4 |
| 2026-08-21 | **The WRITE-side schema check is Task 6's, not Task 4's -- owner-decided.** An **older** build writing into a **newer** repo is the more damaging direction: after the `artifacts` rename it would add `tables`-shaped entries to an `artifacts` manifest, leaving one file half in each format, where the read-side failure is merely a wrong or empty answer. Deferred rather than bolted on because a write is several steps (local files -> one commit -> storage mirror) and the check must sit ahead of **all** of them -- aborting mid-pipeline leaves a half-finished write, which is worse than the disagreement being prevented. Task 6 has those steps in view; Task 4 did not. | R9, Tasks 4 + 6 |
| 2026-08-21 | **(implementation) placing the check relative to existing error handling is the actual difficulty of Task 4, and gets a different wrong answer at each site.** Three of the six readers wrap their manifest read in a handler that softens failures. Inside it, `datom_list()` and `datom_summary()` reword the upgrade instruction as "Could not read manifest" -- demoting the one actionable line to a footnote under a wrong headline. `datom_status()` is worse: its handler turns errors into `available = FALSE` and continues, so that one command would have stayed **silent** while the other five stopped, which is precisely the degradation R9 exists to end. All three now read inside the handler and check outside it. A companion test pins that an ordinary storage failure is **still** tolerated by `datom_status()`: making the schema check fatal must not make an unreachable bucket fatal. | R9.1, R9.2, Task 4 |
| 2026-08-21 | **(implementation) two condition classes, so "all six behave consistently" is provable rather than asserted.** `datom_schema_unsupported` for a too-new document, `datom_schema_invalid` for a present-but-unusable value. Every call site's test asserts the **class**, not message text, which is what makes a future divergence at one site fail loudly. Recorded because the question that produced it -- "can you confirm all six behave consistently?" -- could not be answered from the code as it stood: the answer was no, and the three softening handlers were why. | Task 4 |
| 2026-08-21 | **(implementation) a present-but-unusable `schema_version` aborts rather than being coerced**, which R9's pseudocode did not cover. Two reasons, either sufficient: `as.integer("two")` is `NA` and `NA > 2` surfaces through `if()` as "missing value where TRUE/FALSE needed" -- an internals-looking error for what is really a corrupt file (the same `nzchar(NA)` class already recorded in `dev/engineering-notes.md`); and an uncoerced string comparison against a number can read as *supported* by accident. Refused: non-numeric, `NA`, fractional, below 1, non-scalar, logical, list. | R9, Task 4 |
| 2026-08-21 | **(implementation) the constant is `.datom_supported_schema`, and its leading dot is a cli trap.** R9 writes `SUPPORTED_SCHEMA`; house style for internal constants is dot-prefixed (`.datom_reserved_names`, `.datom_import_formats`), so R9's spelling is read as pseudocode. The dot then makes `{.datom_supported_schema}` a **cli style** rather than a value inside a message string -- it must be spliced `{(.datom_supported_schema)}`, the same trap already recorded for `{.val {(.datom_import_formats)}}`. A test asserts the ceiling renders as `v2` rather than disappearing into markup. | Task 4, `dev/engineering-notes.md` |
| 2026-08-21 | **(implementation) adding `schema_version` + `document_sha` to the `volatile` list is inert for every document already written**, since no metadata carries either field yet -- so I4 holds by construction, with no migration and no re-minted versions. Pinned by a test that presence-versus-absence of both is immaterial to `metadata_sha`, rather than inferred from the suite staying green. The roxygen paragraph above the list, which enumerates each excluded field **and its reason**, was updated in the same edit: leaving it stale is the Task 1 defect class exactly. | I4, R7.4, R9.3 |
| 2026-08-21 | **(implementation) the version boundary is strictly greater-than, with its own test.** At `>=`, the entire read path would break the moment Task 6 writes `schema_version: 2` -- a one-character defect that no other test in this task would catch, since every other fixture is either far newer or absent. | R9.1, Tasks 4 + 6 |
| 2026-08-21 | **Spec code citations were re-derived after Task 4 shifted line numbers in five files**, including every site in Task 6's nine-site checklist -- left stale, the next session would have opened the wrong lines while following an instruction that says to cite rather than re-derive. Verified **by content** (`SPEC_CHECK_SHOW_CITATIONS=1`), not by arithmetic, which is how two pre-existing off-by-ones were found. Bare numbers inside historical log rows were deliberately **not** touched (e.g. the 2026-08-17 row recording `R/read_write.R:217 -> 227`): they record what was true on that date, and rewriting them would falsify an audit trail to fix a number nobody follows. Check 4 only asserts a cited line **exists**, so it cannot catch this class -- content review is still required after any insertion into `R/`. | dev/check-spec.R, Task 6 |
| 2026-08-21 | **`.kiro/steering/communication.md` added (not a task).** Task 4's design round needed three restatements before it landed, all for the same reason: responses led with spec vocabulary (`gate`, `R9.2`, `AC7`) and assumed the owner held the spec in working memory. The rule captures what worked -- explain the thing before naming it, 1-2 sentences per point, questions in their own tagged section, reasons rather than scope citations -- and is scoped to **chat responses only**, explicitly not to `R/` comments, roxygen, spec documents, or commit messages, which keep the existing conventions. | `.kiro/steering/communication.md` |
| 2026-08-21 | **Cold-start audit for Task 6: startable as written, after two corrections.** The documented path was walked as a fresh reader and every claim verified against the tree. The nine-site enumeration holds. **(1) `datom_validate()` does not read `manifest$tables`** -- its only manifest read is `.datom_validate_project_name()`, which looks at `project_name`, and `.datom_validate_tables()` enumerates from a **storage listing** instead; the escalation rationale named it anyway, which would have sent a reader hunting in a file with nothing in it. Rationale corrected to name `datom_status()`, which does read the key. **(2) Three decoy sites** are return-value fields also called `tables` -- `datom_sync()`'s result (`R/sync.R:171`, `R/sync.R:208`), `datom_validate()`'s (`R/validate.R:184`), `datom_status()`'s (`R/query.R:495`). A `grep tables` sweep hits all three, and renaming them is a separate breaking change to three public return shapes that R8 does not ask for. Recorded because the rename's failure mode is silent either way: touch them and three return shapes change unannounced; miss a real site and the list just reads empty. Also recorded: the test surface spans ten files, so the fixture sweep is the bulk of the chunk. | R8.1, Task 6 |
| 2026-08-23 | **E2 DESIGN AUDIT -- BLOCKING GAP: there was no v1-to-v2 transition, and the rename would have blanked discovery on every existing repo.** Verified in the tree before acceptance. An existing manifest keeps its list under `tables` and declares no `schema_version`; `.datom_check_schema_version()` tolerates the absence as v1, so the document passes and the reader then finds nothing under `artifacts` -- `datom_list()` empty (`R/query.R:94`), `datom_summary()` zero (`R/summary.R:69`), `datom_status()` zero (`R/query.R:488`), no error. `datom_read()` is unaffected (`R/read_write.R:93`), so it is a discovery blackout, not data loss -- **silence is the disqualifier, not severity**. Nothing self-heals it: `.datom_update_manifest_entry()` stamps no version on either branch, and a no-change write returns at `R/read_write.R:787` before the manifest is touched. **Design.md section 11 does not cover this** -- it analysed an old reader meeting a new repo, where the recourse is "upgrade"; here the upgrade is the cause. Two things recorded as met by Task 4 were falsified by the queued rename: **P10** and AC7's tolerate-older half. | **R22** (new), I28/I29/I30, P10 restated, P34/P35, AC30/AC31/AC32, design.md 10.1/10.2 |
| 2026-08-23 | **OWNER-DECIDED: read upgrades in memory, write upgrades on disk.** `read -> upgrade in memory -> use` leaves the file alone; `read -> upgrade in memory -> edit -> stamp -> write` changes it. The decisive argument is **who can act**: a loud refusal would be the posture's usual preference, but a reader holds storage credentials and no clone, so refusing a v1 manifest strands the population least able to repair it until some developer happens to write. Three alternatives rejected in design.md 15 with reasons: an inline `%||%` fallback (five copies of the same logic, the next schema change misses one silently), refuse-plus-repair-verb (readers cannot repair), and a clean break on pre-release grounds (the `datom-cv1` precedent does not carry -- that break was in content identity, which a re-export regenerates, and the manifest has no rebuild verb; a break must also be loud, which costs the detection step, leaving the transform only a few lines more). | R22.2/R22.3, design.md 10.2 + 15 |
| 2026-08-23 | **OWNER-DECIDED: Phase B splits into Task 5 (contract-neutral) and Task 6 (the rename); old Tasks 6-16 shift to 7-17.** As one task it carried a nine-site rename, the inherited write-side refusal, five counter filters, two read consolidations, the transition above, and a fixture sweep across ten test files -- and its failure mode is silent, so a green suite would not have distinguished working from broken (Operational Discipline rule 3: ambiguous scope before starting is the signal to split). Task 5 creates the one reader and the one skeleton builder and changes nothing observable, so the upgrade has a single place to live instead of five; Task 6 then renames the key there. Renumbering was done in descending order and every `Task N` reference across the three spec files was repointed, including historical Decisions rows -- unlike stale *code* citations, a stale task number points a reader at the wrong task rather than merely recording what was once true. **`dev/check-spec.R` gained check 8** for exactly this: every `Task N` reference must resolve to a task that exists, verified by reintroducing a dangling reference and confirming a FAIL. | tasks.md Phase B, dev/check-spec.R |
| 2026-08-23 | **The upgrade's shape: one step per adjacent version pair, and a shipped step is frozen** (I30). A dispatcher reads the declared version and applies every step up to current, in order, so a v1 file on a v3 build runs v1-to-v2 then v2-to-v3. No direct v1-to-v3 function is written -- one-per-pair grows with the square of the version count and gives the two paths somewhere to disagree. A released step is never edited, not even to tidy it: it is written against files that exist unchanged in the world, and mis-converting one yields a well-formed file for the wrong version, which is silent. Same discipline as the frozen sv1 goldens, for the same reason -- the inputs are no longer in our hands. | R22.5, I30, P34 |
| 2026-08-23 | **The failure-kind split, which replaces a comment with structure.** The shared reader **returns** an IO failure as data and **throws** a schema refusal. Task 4 found three readers wrapping their manifest read in a handler that softens failures, and a check placed inside one reworded the upgrade instruction as "could not read manifest" while `datom_status()` downgraded it to a warning and continued; Task 4 held the line with a comment at each site. Returning one failure and throwing the other removes the handler the check could be placed inside, while callers keep their differing IO policies because the IO outcome is a value they inspect. AC32 tests both halves together, since the regression is a trade between them. | R22.4, P35, AC32 |
| 2026-08-23 | **OWNER-DECIDED: no missing-`kind` fallback in the counters.** Filter on `kind == "table"` and add no "or absent" arm. Every entry has a `kind` by the time a counter runs, because the upgrade stamps it -- so the fallback would only ever fire on a read path that skipped the upgrade, and it would make that mistake produce roughly-correct numbers instead of visibly wrong ones. A safety net that catches the one failure we want noisy is worse than none. One line, reversible if a real case for tolerance appears. | R22.8, design.md 15 |
| 2026-08-23 | **OWNER-DECIDED: "surface `kind`" means two different things.** `datom_list()` returns per-artifact rows, so it gains a `kind` column -- **including both empty-result returns** (`R/query.R:94,103`), which already omit `current_data_sha` that populated rows carry, so the column set has drifted there once already. `datom_summary()` has no per-artifact axis: it gains `set_count` beside `table_count` plus a line in `print.datom_summary()`, and `table_count` keeps its tables-only meaning. Recorded because "surface `kind`" was undefined for an aggregate object and would otherwise have been settled by whoever typed first. | R8.4, Task 6 |
| 2026-08-23 | **Three audit corrections of substance, each verified against the tree.** (1) **Five counters widen to include sets, not three**: the three in the summary block (`R/sync.R:1016,1017,1020`) plus two computed independently of it -- `datom_summary()`'s `table_count` (`R/summary.R:69`) and `datom_status()`'s count (`R/query.R:488`), both of which count entries rather than reading the summary. No test catches any of them until a fixture contains a `kind: "set"` entry, because there are no sets until Task 9. (2) **The write-side refusal must sit above the two routing returns** at `R/read_write.R:702` and `R/read_write.R:706`: `.datom_sync_data_metadata()` mirrors the whole local manifest to storage (`R/sync.R:177`) without reaching the manifest-writing step, so a check after the router misses it -- and it needs the *manifest*, which `datom_write()` never reads. (3) **`.datom_check_schema_version()`'s message says "which this build cannot read"** (`R/utils-validate.R:269`), which is wrong on a refused write; give it an operation word or accept it knowingly. | Task 6, R22.3 |
| 2026-08-23 | **Two v1-compatibility tests must survive Task 6's sweep, and a third has to be added.** `datom_list` / `datom_summary` "tolerates a manifest with no schema_version" (`test-query.R:894`, `test-summary.R:163`) each build a `tables` block **with an entry** and assert a non-empty result; rewritten to `artifacts` they go green while asserting nothing, and the regression ships clean. The cold-start audit's two fixture categories (sweep, or leave as a decoy) did not cover them, so a **third category** exists: v1-compatibility fixtures, which stay on `tables` and keep asserting non-empty. The same-named `datom_sync_manifest` test (`test-sync.R:1283`) is **not** one of them -- its block is empty, so it passes either way -- which means the clone-copy readers have no old-format coverage at all and need a new test. Made structural rather than remembered by moving the evidence into a frozen file (R22.7). | AC30, R22.7, Task 5 |
| 2026-08-23 | **E2 discharged without a model switch, and recorded so the flag does not read as unaddressed.** The working model is already the most capable one available to the owner, so the escalation is answered by an independent close review of the spec before implementation, owned by the owner. The design spot-check half of the trigger was performed and produced the eight rows above; the purity-audit half still applies **after** Task 6 lands. | design.md 12 (E2) |
| 2026-08-23 | **One audit claim was overstated and is recorded as such.** The review argued that leaving the local-manifest read duplicated means "a repo with no local manifest reports every input file as new". True mechanically, but close to unreachable: `.datom/manifest.json` is git-tracked, so any clone has it, and it is absent only before init or after someone deletes it. The consolidation is still worth doing because Task 5 touches those sites anyway and the dangerous write-side skeleton lives in the same group -- but the justification is one-place-to-change, not a live bug. | Task 5 |
| 2026-08-23 | **The renumber's own defect pattern, caught by reading rather than by the gate.** Two places held task numbers the mechanical sweep could not see, both because the number is not written as `Task N`: the **New exports** table's bare `Task` column (`datom_member()` said 7, now 8; `datom_write_set()` 8 -> 9; `datom_get_set()` 9 -> 10; `datom_repo_commit()` / `datom_repo_push()` 11 -> 12; `include_paths` 12 -> 13) and two spelled-out counts of `check-spec.R`'s own checks ("eight", and "Six checks" in `dev/README.md`, the latter already stale by one before today). Check 8 cannot see either, and its comment says so. Same class as the five review rounds recorded above: **a change swept some places and left others stating the old thing.** The countermeasure that works is the one already written into this spec -- never restate a count or a range, derive it -- so the exports table now carries a line telling the next reader to re-derive from the task headings. | dev/check-spec.R (check 8 limitation), tasks.md exports table |
| 2026-08-23 | **OWNER-DECIDED: `kind` entering identity is accepted.** Because it is semantic, the first write after upgrading mints a `metadata_only` version for every existing table -- same content, same storage address, parquet reused, nothing re-uploaded. Accepted as a bounded one-time cost in the safe direction: it produces an extra version rather than changing an existing one, so the reproducibility guarantee is not violated. The alternatives were closed off before the decision: `kind` cannot be excluded from the hash (a table and a set could then share a version identity) and cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata precisely because the manifest can lag a partial write). Recorded because nothing in the spec acknowledged it and it is the shape #72 was fought over -- a package upgrade producing versions. | R1.1, Task 7 |
| 2026-08-23 | **OWNER-DECIDED: stamp the schema number always, increment it only on a break.** Review had these as one question and they separate cleanly. Stamping costs nothing -- the field is excluded from identity, so a stamped file mints no version -- and it lets any build state what shape it holds; the owner's framing was good housekeeping. Incrementing costs every pinned build its access to everything written afterwards, because the check is a refusal. So the number moves only for a rename, a removal, a meaning or type change, or a container restructure; an added field leaves it alone. **This supersedes the recommendation earlier the same day to leave per-artifact metadata unstamped** -- that concern was right about the harm and wrong about the cause, which is incrementing rather than stamping. The test is written into R9.5 as a table so it is not a judgment made under release pressure, and the call is made at design time alongside the escalation flags. Also **corrected in the same round**: an earlier claim that stamping costs *current* pinned readers their access was wrong -- no released build checks the number at all, so the entire cost is for builds from this release onward. | R9.5, design.md 10.3 |
| 2026-08-23 | **Publish the schema-to-package mapping** (R9.6). One schema version spans many releases, so neither `schema_version` nor `datom_version` answers the only question a refusal raises -- *which datom do I need?* A table in the package docs maps each schema version to the release range that reads it. Filed as [#103](https://github.com/amashadihossein/datom/issues/103) rather than built here. | R9.6 |
| 2026-08-23 | **REJECTED: a declarative transform file travelling with the repo**, so an older build could translate a newer manifest back to the shape it knows (owner-proposed, and the strongest alternative considered). Merits acknowledged: it is data rather than code, so nothing is executed from a data store; it composes exactly as the forward chain does; and it can hide a new concept so an old build never learns sets exist. Rejected because **the interpreter must ship in the old build**, so it cannot help anything already released -- the wall it was meant to remove; because **the mapping format is frozen the day it ships**, so the first thing it cannot express leaves us where we are today with a language to maintain as well; because a rename map covers renames and moves but not meaning changes, container restructures or concept splits, and supporting those means designing a language; and because **the cost is the testing** -- worth nothing unless CI installs historical releases and reads current repos through them, a matrix that grows every release and is the first thing dropped under deadline. Decisive: its own simplest case, dual-write, delivers most of the value with none of the machinery and does work for released builds -- specified in [#102](https://github.com/amashadihossein/datom/issues/102), to be built only when a break needs it. | design.md 15, #102 |
| 2026-08-23 | **The division that came out of this round, and the most durable thing in it: the manifest may break, per-artifact metadata may never.** The manifest is **derived** -- every fact in it also lives in per-artifact metadata or the storage listing -- so a build that cannot read it can rebuild one, which is what makes an escape hatch possible. Per-artifact metadata **is** the source of truth: nothing can rebuild it, and a legacy-shaped second copy hashes differently from the recorded version (`R/read_write.R:342` recomputes identity from the stored file), so dual-write there would help old readers by making older writers mint a version on every run. **This spec has the division the right way round by accident** -- it breaks the file with a hatch and only adds to the file without one. Recorded so the next change has that shape on purpose. Written into `.github/copilot-instructions.md` so it outlives this feature. | R22.9, design.md 10.4 |
| 2026-08-23 | **Forward compatibility is a writer-side problem, and the four rules that follow from it.** A new build can always read old files, because it knows both shapes; an old build can only read new files if the writer left it something it already understands. Nothing can be retrofitted into an installed package. So: (1) additive only by default; (2) a field's name and meaning are fixed forever; (3) dual-write with a declared sunset when a break is genuinely unavoidable; (4) the schema number is the alarm for when 1-3 failed, not the mechanism. Recorded in `.github/copilot-instructions.md` rather than here, since it governs every future change and not just this one. | `.github/copilot-instructions.md` |
| 2026-08-23 | **Found while vetting "additive changes are free": they are free for readers and NOT for writers, because identity hashing uses a denylist.** `.datom_compute_metadata_sha()` hashes every field in the document minus a list of seven to ignore (`R/utils-sha.R:415-416`). A build that has never heard of a field cannot know it was meant to ignore it, so it folds the unknown field into the hash, disagrees with the recorded version, and reports a change on content that did not move -- on **every run**, not once. Remedy is an **allowlist**: hash a named list of fields and ignore anything else. Set the list to the fields hashed today and every existing identity is byte-identical, so it is behaviour-preserving now and forward-compatible later. Honest limit: it makes *bookkeeping* additions free (the common case) and not *semantic* ones, so the `kind` cost above stands. Filed as [#100](https://github.com/amashadihossein/datom/issues/100) -- not sets work, and it touches the identity function every artifact depends on. Paired with [#98](https://github.com/amashadihossein/datom/issues/98), which removes the JSON emitter from the same function: one identity-affecting change to verify instead of two. | R9.5, #100 |
| 2026-08-23 | **`original_format` is manifest-only, which would make a manifest rebuild lossy.** Verified: it is written into the manifest entry (`R/sync.R:1002`) and never into per-artifact metadata, so it is the one manifest field not recoverable from a storage listing plus per-artifact files. Rather than accept a lossy rebuild, persist it into metadata -- additive, and free once identity hashing uses an allowlist. Bundled into [#101](https://github.com/amashadihossein/datom/issues/101), since the rebuild is what makes it matter -- and ordered after #100, because persisting a metadata field is only free once identity hashing uses an allowlist. | R22.9, #101 |
| 2026-08-23 | **RENUMBER SHIFT RECORD, and the policy that replaces sweeping.** The 2026-08-23 Phase B split moved **old Tasks 6-16 to 7-17**; Task 5 became Task 6 and a new contract-neutral Task 5 was inserted. **This is the last sweep of historical rows.** From here, dated Decisions rows are **FROZEN**: a renumber adds one shift record like this one and touches nothing else. Reason: three renumbers produced three crops of stale references, and the last one left a row *half* swept -- three references bumped, two not -- so it read as a claim about a task that did not exist on its date. A shift record is self-maintaining; a sweep never is. The pre-existing 2026-08-11 row mixing three numbering generations ("new Task 15 ... Old 14/15 -> 15/16") is left as the illustration. Reconciled once today rather than reverted to as-of-date numbering, because prior rounds had already swept most rows and finishing one half-done sweep is smaller and safer than undoing three. `dev/check-spec.R` check 8 now **notes** how many `Task N` references sit inside dated rows, as a reminder at the moment a renumber is happening. | tasks.md, dev/check-spec.R |
| 2026-08-23 | **DESIGN A: the manifest's schema number keeps bumping and stays true to the shape.** For the manifest specifically the **reader's** response to a too-new number becomes **warn and rebuild**; a **writer** still refuses. Design B (manifest carries no number; dispatch by shape) rejected on three grounds, the third decisive: it would stamp then freeze the number, so a file would read v2 while carrying a v5 shape; it would leave the upgrade chain with one step forever, paying for a generality never exercised; and **it cannot distinguish corruption from the future** -- a truncated manifest and a future-shaped manifest both present with the expected key missing, so both would rebuild, contradicting the requirement that a corrupt manifest still fails visibly. The number is the only thing separating the two. **Task 6 bumps to 2, unchanged.** Note this supersedes a proposal from the same review round to never bump for a manifest shape change once the rebuild exists. | R9.5 (per-file rule), R22.11, design.md 10.5, AC37 |
| 2026-08-23 | **OWNER-DECIDED: writer refusal is a VOCABULARY check, not a version comparison.** A build refuses a write when a datom-owned document carries a **top-level** key it cannot classify -- neither in its identity list nor on its documented excluded list. Evidence-based: no version comparison, no configuration, no network. Chosen over a declared minimum writer version as the primary mechanism for one reason -- **it cannot be forgotten.** A floor protects a repo only if somebody remembers to raise it; the vocabulary check fires on the evidence regardless. The objection that this makes every addition writer-breaking, contradicting "additive changes are free", was **raised and overruled**: writes are infrequent, done by few people, and change content, so **a false refusal costs one person an install while a miss costs corrupted data**. Refusing too often is the right direction to err. | R23.1, R23.6, design.md 10.6, AC35 |
| 2026-08-23 | **The vocabulary list is APPEND-ONLY, with the same weight as a frozen upgrade step.** No build may stop recognising a field name that has ever existed, **including names it no longer writes**; retire by marking, never by deleting. A build that forgets a name meets an **older** file, fails to classify a key it should know, and refuses it -- **blocking the upgrade direction, the one direction that must always work.** Corollary recorded so nobody codes around it: the good direction is **structurally safe**, because a newer build's vocabulary is a superset of every older one's, so the check cannot fire on the upgrade path. No directional logic; a guard for it would be dead code guarding an unreachable state. | R23.2, R23.2a, I31, P37 |
| 2026-08-23 | **Coverage is complementary; neither mechanism is sufficient alone, and saying so is part of the requirement.** The vocabulary check catches **additions and renames**. It cannot catch **removals** (the old name is still in an append-only vocabulary, so nothing looks unrecognised), **type or meaning changes**, or **container restructures** -- none of which introduce a new name. Every one of those bumps the schema number by R9.5, so the version check catches them. A **policy block for a non-format reason** is caught by neither and is the floor's own case. | R23.5, R9.5 |
| 2026-08-23 | **OWNER-DECIDED: the floor ships its READING half in 0.1.1; everything else about it is deferred.** One **optional** `project.yaml` field, absent meaning no floor so no existing repo changes behaviour; it rides on the conn since `datom_get_conn()` already parses that file; compare and refuse at the write entry; one guard, that whoever sets it must already satisfy it. Deferred: the purpose-built raising verb (agreed in principle, consistent with the R15 named-verbs precedent -- a normal commit cannot validate that the raiser satisfies the new value), tooling, docs. **Reason the reading half cannot wait**: a build that does not look for the field can never be bound by it, which is precisely why nothing can stop a 0.1.0 writer. Its trigger cases, recorded so a later reader knows why it exists: a **meaning** change that adds no field, and a policy block for a non-format reason ("0.1.4 wrote bad hashes"). | R23.3, R23.3a, AC36 |
| 2026-08-23 | **#100's justification changed and the old one must not survive into the code.** Filed as "older writers keep working". After the vocabulary decision they do not, by design. What the allowlist now buys: **readers compute correct identities, and a repo does not accumulate spurious versions.** Both still hold. Recorded because a stale rationale in a comment outlives the discussion that produced it. | #100, Task 19, design.md 10.6 |
| 2026-08-23 | **Three corrections accepted from the reviewing side, each verified against the tree first.** (1) The `seq()` loop-guard finding was mis-attributed: **there is no `seq(` anywhere in the three spec files**, so a sketch written in conversation had been reclassified as a defect in a written artifact. It is implementation guidance -- guard the loop, test that a current-version document runs zero steps -- not a spec fix (R22.10). (2) The rationale for carrying unknown fields forward was wrong: churn settles after one version per handoff **either way**, because a build that deletes the field agrees with itself on its next run. The real argument is **information loss**, so the test asserts a round trip rather than a version count (R23.8, AC34). (3) The connectivity concern was overstated: `.datom_git_push()` **aborts** on push failure (`R/utils-git.R:267-277`) and the storage steps are 8-10, after it, so a write cannot reach storage without a successful push -- warn-and-proceed at the door is defensible with the push as the backstop, and the residual is narrow (fetch fails, push succeeds). | R22.10, R23.8, design.md 10.7 |
| 2026-08-23 | **Found and scheduled as its own fix: `.datom_check_git_current()` does not return early on a failed fetch.** `return(invisible(TRUE))` sits inside the `tryCatch` **error handler** (`R/utils-git.R:422-429`), so it returns from the handler rather than the function; execution continues and compares `HEAD` against **stale cached** upstream refs. An offline user whose cached upstream is ahead gets a hard **abort** where the comment states network errors should not block offline work. A live defect independent of this spec -- and Task 21's write-entry sequence is proposed to sit on that function, which is why it is Task 18 and lands first. Filed as [#104](https://github.com/amashadihossein/datom/issues/104). | Task 18, #104 |
| 2026-08-23 | **Scope filter for 0.1.1, and the five items it selects.** The filter: *does deferring it postpone the cost, or permanently exclude every install shipped meanwhile?* Five items only ever help builds that already contain them -- allowlist hashing, carry-unknown-fields, the writer refusals, the floor's reading half, and the rebuild -- so deferring any one strands every 0.1.1 install forever. Everything else from this review round (bump rules, the schema history table, policy prose, the floor's tooling) lands later without stranding anyone. **If 0.1.1 gets crowded, those slip; these five do not.** #101 pulled into 0.1.1 on exactly this basis. Appended as Phase E rather than inserted, to avoid a third renumber; execution order is stated in the phase preamble and in the state block, because appended does **not** mean last. | tasks.md Phase E |
| 2026-08-23 | **The write-path entry sequence is fixed in one place** (design 10.7): fetch, floor check, read-and-schema-check-then-chain, unreachable-shape check, vocabulary check, proceed. All of it directly after the `datom_conn` class check and **above** the two routing returns at `R/read_write.R:702` and `R/read_write.R:706`, because `.datom_sync_data_metadata()` mirrors the whole manifest to storage without ever reaching the manifest-writing step. All six steps precede any hashing, any local file write, and any commit, so a refusal leaves no partial state -- the spec's own argument being that aborting mid-pipeline leaves a half-finished write, which is worse than the disagreement prevented. The step-7 pull inside `.datom_git_push()` stays as the backstop for the genuine race (a floor raised between entry check and push). | I34, R22.10, R23.4, design.md 10.7, Task 21 |
| 2026-08-23 | **Enforcement begins at 0.1.1; 0.1.0 writers cannot be stopped, and the spec now says so.** 0.1.0 has no schema check, no vocabulary check and no floor read, and none can be added to a released build. Previous wording ("an older build writing into a newer repo") did not separate the population that can be stopped from the one that cannot. For 0.1.0 the remedy is a **NEWS entry, not engineering**: the only lever that would make it fail loudly -- relocating the manifest so its existing "could not read manifest" abort fires -- costs a storage-layout change, a `datom_validate()` change (`R/validate.R:236-238`) and two filenames carried forever, against an exposed population that is the team. | R23.7 |
| 2026-08-23 | **(review) Design A had not been swept into the criteria, and it reached FIVE sites, not the three the review named.** Design A changed the manifest **reader's** response to a too-new version from abort to warn-and-rebuild. R22.11 and AC37b said so; **AC32** still asserted the abort "at all of them", **R22.4** still said a schema refusal is "thrown" unqualified, and -- found while checking those two -- **P35** -- now superseded -- stated that no handler may convert the abort into a warning, which forbade the exact remedy Design A adopts, while **P11** claimed a below-current reader aborts at both entry points. Two of the five are a **property** and an **acceptance criterion**, which is the worst place for a stale mechanism: the suite would have asserted the opposite of the design. **The fix is a scoping, not a reversal** -- refuse-newer still holds absolutely for per-artifact metadata at any role and for the manifest on the writer path. What P35 and R22.4 were really protecting is restated as the thing that survives: **a schema outcome is never reported as an unreadable manifest**, whether it aborts or takes its own deliberate path. This is the spec's recurring swept-some-places defect, on its sixth appearance, and the count went up again on inspection -- the review found three, a re-derivation found five. | AC32, R22.4, P35, P11, Tasks 5 + 22 |
| 2026-08-23 | **AC32 is deliberately recorded as true in two forms rather than reworded once.** Task 5 ships the abort at all five readers and claims AC32; Task 22 replaces the manifest reader's half with warn-and-rebuild. Rather than back-date the criterion, both forms are stated with the task boundary that separates them, Task 5's citation says "in its Task 5 form", and Task 22 explicitly **restates** AC32 and P35 the way Task 6 restates P10. Task 5 also carries an instruction not to bury the abort assertion in a loop over the five readers, because one of the five stops aborting later -- a loop is exactly what makes that amendment easy to miss. | AC32, P35, Task 5, Task 22 |
| 2026-08-23 | **(review) the vocabulary check had no per-artifact document in hand where it was placed, and the resolution is a third option neither side had proposed.** Verified: `datom_write()` does not touch stored artifact metadata until pipeline step 4, inside `.datom_has_changes()` (`R/read_write.R:334-343`), while the check sits at entry step 5 -- so as written it could only ever cover the manifest, and the likely silent outcome was an implementer skipping the artifact half because nothing was at hand. That would remove the check from the document that is **never rebuildable** and where identity lives. The two options offered were an extra storage GET at entry (a second read of an object `.datom_has_changes()` reads anyway, and N reads on the mirror-everything route) or moving the artifact half down to pipeline step 4 (still pre-mutation, but it makes "before any hashing" false for one check). **Chosen instead: read the CLONE's copies** -- all three documents exist as local files (`{conn$path}/.datom/manifest.json`, `{conn$path}/{name}/metadata.json`, `R/read_write.R:463-469`), so it is a file read with no round trip, it works on every route including the one with no single artifact name, and it targets the copy a pull from a newer collaborator actually lands in. Sound because git is written before storage (I5), so storage cannot legitimately hold a newer document than the clone; if it does, that is drift and `datom_validate()` owns it. AC35 gains clause (e) because an implementation checking only the manifest passes every other clause. | R23.1a, AC35 (e), design.md 10.7, Task 21 |
| 2026-08-23 | **(review) the write-entry sequence read the manifest without naming WHICH manifest -- the sibling of the gap closed one round earlier.** `.datom_read_manifest()` takes a scope, and step 3 of design 10.7 did not supply one. **It is the clone**, and R23.1a now governs the whole sequence rather than only its vocabulary step: the manifest at step 3 and all three documents at step 5. The two steps needed saying for **opposite** reasons, which is why one sentence would not have covered both. At step 5 the sequence does not hold the per-artifact document at all (`datom_write()` reaches stored artifact metadata only at pipeline step 4, `R/read_write.R:334-343`), so silence means an implementer checks the manifest alone. At step 3 the unstated default pulls the other way -- the too-new-repo framing reads as storage-flavoured and every check Task 4 wired was, so silence lands on **storage**, adding a network read to every write and inspecting the wrong copy. The clone is right at both for the same four reasons: it is the document the write mutates (`R/sync.R:964`), it is a file read rather than a round trip, it is where a pull from a newer collaborator lands, and storage cannot legitimately be ahead of git (I5). | R23.1a, design.md 10.7, Task 21 |
| 2026-08-23 | **(review) AC32 collapsed to ONE invariant form; accepted, with one part of the proposal declined.** The insight had been applied to P35 and not to the criterion: the invariant was never the abort, it was that a schema outcome is not disguised as an IO failure. AC32 now asserts only that the outcome is **its own** -- not reworded as "could not read manifest", not downgraded to a storage warning -- and says nothing about *which* outcome, which is AC37b's job and differs by role and by task. So it holds unchanged across the Task 5 / Task 22 boundary. Removed with it: the two-forms record, Task 5's "in its Task 5 form" citation, and Task 22's restatement of AC32. **Declined**: dropping the don't-bury-it-in-a-loop instruction. Its justification never depended on AC32's wording -- the **behaviour** still changes at Task 22, so the assertion in `test-query.R` still has to be found and amended, and a loop over the five readers is exactly what makes that easy to miss. Recast as an instruction about test shape rather than about the criterion, and Task 22 now says it amends the test rather than restating the criterion. | AC32, Task 5, Task 22 |
| 2026-08-26 | **(implementation) Task 18 narrows a live safety check, and that is the accepted trade rather than an oversight.** With the fetch-failure return fixed, an offline write proceeds **without knowing whether it is behind** -- the cached upstream refs are deliberately not compared, because they can be arbitrarily stale and acting on them is what produced the abort. Accepted because the backstop is real: `.datom_git_push()` pulls and aborts if the push is rejected (`R/utils-git.R:267-277`) and the storage steps come after it, so a write cannot land on storage from a stale base. Recorded in the function's roxygen as well as here, since a guard that warns and returns `TRUE` reads as a swallowed error to anyone meeting it cold. Same argument design.md 10.7 already makes for warn-and-proceed at the write entry. | Task 18, #104, design.md 10.7 |
| 2026-08-26 | **(implementation) the defect was invisible to the test that existed for exactly this path.** `.datom_check_git_current tolerates network errors gracefully` stubs `git2r::fetch` to raise -- but its fixture has **no upstream branch**, so the function returns before reaching the comparison and the test passed on the defect. Both new tests therefore establish an upstream first, and the ahead-case one was **proven to fail** against the unfixed function before being trusted (stash the `R/` change, re-run, it errors on the stale-ahead abort). The level-case test passes either way by design: it pins an accident (nothing unfavourable to compare against) as deliberate. Also recorded in `dev/engineering-notes.md`: the handler-`return()` trap is a general R gotcha, and a `cli_alert_warning()` needs `expect_message()`, not `expect_warning()`. | Task 18, `dev/engineering-notes.md` |
| 2026-08-26 | **Two operator-facing fixes landed with Task 18, not as tasks -- both are recourse quality for the state a rejected push leaves behind.** Task 18 makes an offline write *proceed*, so it also makes "rejected at push" more reachable, and the recourse was examined in the same session. (1) The merge-conflict abort told the caller to "pull latest changes" -- but the pull is what produced the conflict, so the first line a confused operator read was wrong. Replaced with the resolution that actually works for datom's own generated JSON: keep the remote copy (`git checkout --theirs`) and re-run the write, because step 6 rebuilds `metadata.json` outright, appends to history behind a dedup guard, and rewrites only this artifact's manifest entry. Also states that storage is untouched, since "conflict" reads as "half-published" to anyone who does not know git gates storage. (2) `datom_validate(fix = TRUE)` printed "Fix applied" for findings it cannot fix: the repair calls `.datom_sync_data_metadata()`, which uploads manifest and per-artifact metadata **only** -- a missing parquet is not in the clone and never was. It now names those artifacts and points at re-running `datom_write()` with the source data. Same trap shape the log already names twice (a repair path quietly not delivering what it claims), and the third instance, so the pattern is now: **any repair path must state what it does NOT repair.** tests 2664 -> **2675**. | `R/utils-git.R`, `R/validate.R`, Task 18 |
| 2026-08-26 | **Cold-start audit for Task 19: startable, after closing one gap that spanned two tasks.** The documented path was walked as a fresh reader and every claim checked against the tree. What held: the citation `R/utils-sha.R:410-420` is accurate, the `volatile` denylist is the seven fields described, AC33's four clauses and P36 are complete and unambiguous, and AC33(a)'s pinned value already exists (`test-utils-sha.R:899-904`). **The gap: Task 7 adds `kind` plus an entire set metadata builder and said nothing about classifying either.** After Task 19 an unclassified field is silently *outside* identity, so `kind` would stop affecting `metadata_sha` and a table and a set could share a version identity -- exactly what the 2026-08-23 decision closed off, and invisible to every other test in Task 7. **The fix is a forcing function, not a reminder**: Task 19's classification test must **derive** the field set from what the builders emit rather than hardcode today's names, so it fails the moment Task 7 touches a builder. A hardcoded list would have passed forever, which is the same swept-some-places shape this log records six times -- caught here before implementation rather than after. Task 7 now carries the obligation explicitly, with R9.5, P36 and AC33(d) added to its criteria line. | Tasks 19 + 7, AC33, P36 |
| 2026-08-26 | **OWNER-DECIDED: anchor AC33(a) on a realistic fixture, and repurpose the `name`-bearing golden as AC33(b)'s test.** Two ordered steps, now in Task 19's body. **(1)** Before touching `.datom_compute_metadata_sha()`, pin the `metadata_sha` of a document built by `.datom_build_metadata()` with every optional argument supplied, computed under **today's** code -- that is AC33(a)'s evidence and it must not move. Ordering is the point: a pin computed in the same edit as the change it polices is worth much less. **(2)** The `name`-bearing golden is not retired but **reused** -- `name` *is* an unknown extra field, precisely AC33(b)'s case, so the fixture that was going to break becomes the assertion for the property that breaks it, with its constant becoming the no-`name` value. **Rejected: adding `name` to the allowlist** to keep the old constant byte-identical -- cheapest in churn, but the list would then name a field datom never writes, destroying the one property that makes it readable (that it *is* what the builders emit) and inviting a later reader to conclude a `name` field exists. | Task 19, AC33 (a) + (b) |
| 2026-08-26 | **RESOLVED SAME DAY by the row above -- retained for the verification it records, not as an open item.** ~~(audit) OPEN FOR THE OWNER AT TASK 19 START~~: **the pinned `metadata_sha` golden's fixture carries a field no builder emits, so a correct allowlist changes that hash.** The fixture is `list(data_sha, name, nrow, ncol, table_type, hash_algo)` and **`name` is not a metadata field** -- verified that `metadata.json` is written as exactly `.datom_build_metadata()`'s object, which has no `name` key (the `name` at `R/read_write.R:774` / `R/read_write.R:834` is `datom_write()`'s return value). So under a builder-derived allowlist the golden fails while **no stored identity moves**, because no real document ever had the field. The hazard is the reflex: re-pin the constant and AC33(a) loses the only pinned evidence it rests on, in the task whose entire claim is behaviour preservation. **Recommendation, not a decision**: pin a *realistic* fixture under today's code first, so there is a true before/after anchor, and let the `name`-bearing golden change for a stated reason. Flagged rather than settled because AC33(a) is the clause that proves this task was safe, and how it is anchored is a public-contract-shaped choice. | Task 19, AC33 (a) |
| 2026-08-26 | **(audit) the metadata field inventory is provably complete from one function, and that is what makes the allowlist safe to seed.** Every top-level key of a metadata document is assigned inside `.datom_build_metadata()`, with exactly one exception -- `meta$parquet_sha` (`R/read_write.R:786`), which is volatile. Verified by grepping every `meta$<key> <-` and `metadata$<key> <-` in `R/`. This matters because an allowlist seeded from an incomplete inventory drops content out of identity **silently**, which is the failure direction an allowlist has and a denylist does not; recording the result means the next session does not repeat the grep or, worse, skip it. The semantic set today: `data_sha`, `hash_algo`, `table_type`, `nrow`, `ncol`, `colnames`, plus `original_file_sha`, `parents`, `source_lineage`, `custom` when present. | Task 19, R9.5 |
| 2026-08-26 | **(implementation) the new helper's own test caught a substring bug in it, which is worth the row because the same shape will recur.** `.datom_validate_unfixable_tables()` selects the artifacts whose payload is missing, and status codes are comma-joined -- so `grepl("data_missing_s3", ...)` matches **`metadata_missing_s3`**, which contains it. That reported every metadata-only finding as unrepairable: exactly backwards, since those are the ones the sync does fix. Now split on `,` and compared as whole tokens. Second correction in the same helper: it originally guarded `all(c("name","status") %in% names(...))` and the real column is **`table`**, so the guard converted a wrong column name into a silent `character()` -- reinstating the overclaiming message the helper exists to remove. Guard deleted deliberately: a renamed column must error here. Same reasoning as the no-missing-`kind`-fallback decision -- a safety net that fires only when something upstream is already broken hides the breakage. | `R/validate.R` |
| 2026-08-23 | **(review footnote, pre-existing) a retired phrase was suppressing on an incidental word, and it is now pinned to an intentional one.** The `tasks.md` occurrence of "convert the abort into a warning" sat inside a record whose nearest marker was **"reversal"**, matching via the `revers` stem -- the right outcome by accident, and fragile, because `revers` is ordinary vocabulary in this spec and could mask a genuine hit later. The record now carries an explicit "superseded". Verified by re-running the gate's window test with `revers` removed from `MARKER_RE`: still suppressed. `MARKER_RE` itself is left alone -- the maintenance lesson already in `dev/check-spec.R` is that broadening it toward ordinary vocabulary is what made the check nearly vacuous once, and `revers` is close to that line. Worth revisiting the next time that list is touched. | dev/check-spec.R |
| 2026-08-29 | **`.kiro/steering/communication.md` extended (not a task).** Three additions, each from a message the owner could not act on. (1) **Every section is labelled by purpose** -- TLDR, What changes, Why, FYI, Need from you -- because a reader cannot otherwise tell background from a decision request from the agent's own justification, and the cost of guessing wrong is either an unanswered question or an unwanted implementation. (2) **No homework**: a sentence that needs a file opened, a task re-read or a decision recalled is not written yet; name a thing and gloss it in the same breath, and never signal that something is significant instead of saying what happens. (3) **Questions must be answerable without having read the rest of the message**, with no type names inside them, naming the two outcomes being chosen between. Two real messages from this session are recorded in the file as the worked counter-examples. | `.kiro/steering/communication.md` |
| 2026-08-29 | **(implementation) the failure record carries the whole condition, not its message text.** Two callers want different things from it: `datom_list()` / `datom_summary()` splice `conditionMessage()` into their own abort, while the two clone readers re-signal the original with `stop()` so a corrupt local manifest still fails with the parser's own error and no datom wrapper around it. Text alone would force the second case to build a look-alike error, losing the condition class -- and class, not wording, is what the suite asserts on at every other schema site. | Task 5, R22.4 |
| 2026-08-29 | **(implementation) `absent = TRUE` is a positive claim, and the storage scope never makes it.** For the clone copy it is a free `fs::file_exists()`. For storage it would need an extra request on every `datom_list()`, `datom_summary()` and `datom_status()` call to separate a missing object from an unreachable store, and no caller treats those differently -- so the field stays `FALSE` there, meaning "not known to be absent". Pinned by a test, because the tempting later shortcut is to infer absence from the error message; the right move if a caller ever needs it is `.datom_storage_exists()`. Contrast Task 3, which bought exactly that probe on purpose -- there it improved a user-facing message, here there is no message to improve. | Task 5, Task 3 |
| 2026-08-29 | **(implementation) a corrupt manifest in the clone is a failure, not an absence.** Both clone readers fall back to an empty manifest when the file does not exist. A present-but-unparseable file must not take that branch: it would report every input file as new -- a confident wrong answer, which is the failure class this whole phase exists to remove. The record separates the two states and each reader re-signals the parse failure, with a test at both readers. | Task 5, R22.6 |
| 2026-08-29 | **(implementation) both new guards were proven to fail before being trusted.** Pointing `datom_list()` at `manifest$artifacts` -- what Task 6 does -- turns the frozen-fixture test red, so it is real evidence that old-format repos still list their contents. Wrapping the schema check in a handler inside `.datom_read_manifest()` turns three tests red, including `datom_sync_manifest`'s pre-existing refusal test, so the returned-versus-thrown split is pinned rather than assumed. Both probes reverted. This is the rule the spec already applies to `check-spec.R` gates, applied to `R/` guards. | Task 5, AC30, AC32 |
| 2026-08-29 | **(implementation) `datom_status()` lost its `read_ok` flag, and it was not dropped -- it moved.** The flag existed because a manifest that legitimately parses to `NULL` must still count as read, which a `NULL` check on the document cannot express. The shared reader's `ok` field carries that distinction for every caller now. | Task 5 |
| 2026-08-29 | **(implementation) the entry updater keeps its own direct read; only its empty shape moved.** `.datom_update_manifest_entry()` (`R/sync.R:946`) reads the clone's manifest mid-write, and a compatibility refusal there would stop a write partway through rather than at the door -- Task 4's stated principle. So the read stays out of the shared reader while the hand-built empty manifest becomes a call to `.datom_manifest_skeleton()`. A comment at the site says why, because routing the read through the shared reader is the obvious tidy-up and it is wrong. | Task 5, Task 4 |
| 2026-08-29 | **Spec code citations re-derived by content after Task 5's insertions**, in all three spec files plus the two `design.md` survey tables. Three had drifted onto blank lines and were caught by the gate; the rest were checked with `SPEC_CHECK_SHOW_CITATIONS=1` rather than by arithmetic. Two citations were **removed** rather than repointed: the comments at `datom_list()` and `datom_summary()` that held the check outside their read handlers no longer exist, because the helper's shape holds that line now. Dated Decisions rows left frozen, per the 2026-08-23 policy. | dev/check-spec.R, Task 5 |
| 2026-08-29 | **One operator-facing fix landed after Task 5, not as a task: terminal escape codes stripped from stored error text.** `cli` formats abort messages with colour and hyperlink escapes, and `conditionMessage()` returns them, so any field that **stores** the text stores `\033[31m` with it. Invisible when the message is printed and ugly when the string is, which is why no test caught it -- plain `Rscript` and CI have colour off, so cli emits none. Three returned fields carried it, and the worst was not the one that surfaced: `datom_sync()`'s `error` column is a data frame cell, so a failed sync prints escape codes inline in a table. Fixed with `cli::ansi_strip()` at the three stored copies only; every printed message keeps its colour. **Verified pre-existing before being fixed** -- the previous commit was checked out into a throwaway worktree and run with colour forced on, giving a byte-identical 305-character string, so Task 5 neither caused nor worsened it. Scope was checked rather than assumed: the five other places that capture `conditionMessage()` into a local use it for pattern matching or splice it into a message, so three sites is the whole of it. Each test forces colour **on**, because with it off the assertion passes no matter what the code does; all three were confirmed to redden when the fix is reverted. tests 2740 -> **2748**. | `R/query.R`, `R/sync.R`, `dev/engineering-notes.md` |
| 2026-08-29 | **Spec citations re-derived twice in one session, and the second round found the class the gate cannot see.** The escape-code fix added three comment lines to `R/sync.R`, which shifted every citation below them. Three resolved to blank lines and the gate caught those; **four others had drifted onto unrelated code and passed** -- `R/sync.R:744-756`, cited as the manifest entry builder's field list, was pointing at the import-format vector, and `R/sync.R:570-574`, cited as the imported self-lineage entry, was pointing at the sync loop. Two of the four were already wrong before this session. The lesson is the one `dev/README.md` already states and this is now the second consecutive session to prove it: check 4 asserts only that a cited line is **not blank**, so after any insertion into `R/` the citations must be re-read with `SPEC_CHECK_SHOW_CITATIONS=1` and compared against what they claim. A green gate is not evidence. | dev/check-spec.R |
| 2026-08-29 | **OWNER-DECIDED: the frozen upgrade steps get their own file, `R/manifest-upgrade.R`.** `.datom_manifest_upgrade_v1_to_v2()` and the dispatcher live there rather than beside the reader in `R/sync.R`. Reason: a released step is never edited -- it is written against files that exist unchanged in the world -- and one more step arrives with every future format change, so they accumulate. A file whose entire contents are "never edit these" is easier to protect than a section of a file that is already 881 lines and holds sync, import and manifest concerns. Same reasoning that split `R/hashable-set.R` out of `R/utils-sha.R`. Recorded because Task 6 named the functions and no file, which is the dangling-instruction class the Task 2 audit flagged. | Task 6, I30, R22.5 |
| 2026-08-29 | **OWNER-DECIDED: `.datom_manifest_skeleton()` stamps `schema_version: 2` itself.** A manifest built from scratch declares its format immediately, so no repo exists in a state that declares nothing -- not even between being created and receiving its first artifact. **The consequence that needs saying**: this covers only the no-file path, since the skeleton is unreachable when a manifest exists. A document read from disk in the old shape still gets its number from the upgrade step, so stamping lives in two places by design -- one for a document being created, one for a document being converted -- and an implementer who stamps only in the builder leaves every existing repo unstamped. | Task 6, R9.5, R22.3 |
| 2026-09-01 | **PARKED MID-DESIGN ON TASK 6 for a CRAN interrupt.** 0.1.1 was accepted and CRAN then reported a failure in its automated check runs, which takes priority and is worked on `main`, not here. Task 6's design was proposed and the session stopped for go-ahead per rule 5b, so **nothing was implemented**: clean tree at `dbae253`, 2748 tests, `check-spec.R` 9/9. The plan, the test plan and **five open calls each carrying the default to take on silence** are recorded in Task 6's PAUSE block rather than in this row, so there is one copy to keep true. Two things the interrupt does to this branch, recorded because neither is visible from inside it: the fix will land on `main` and merge in, staling `R/` line citations in a way check 4 catches only when they go fully blank; and the acceptance bookkeeping (publish the release, then merge `dev` into `main`, then delete `dev`) may end the submission freeze that governs this branch's PR target, so `dev/README.md` "Branching During CRAN Submission" must be re-read on resume rather than assumed. | Task 6, dev/README.md |
| 2026-09-08 | **RESUMED. The CRAN interrupt is closed and it changed nothing in this spec.** The failure CRAN reported after accepting 0.1.1 was in test fixtures, not package code: they hardcoded `refs/heads/master` when pushing to a throwaway remote, and `git2r::init()` honours git's `init.defaultBranch`, so on a machine configured for any other name the push named a branch that had never been created -- 26 failures on four Linux flavors, all the same error, all during setup. Shipped as **0.1.2** ([#106](https://github.com/amashadihossein/datom/issues/106) / [#108](https://github.com/amashadihossein/datom/issues/108), PRs #107/#109/#110), **no `R/` file touched**, so Task 6's design stands as proposed and its five open calls are still unanswered. **Both hazards the 2026-09-01 row flagged are discharged, and the answers differ from what that row expected**: the fix merged in via `main -> dev -> spec/datom-sets` and staled **no** citations, because it touched only `tests/` (re-verified: 107 citations, all in range, none blank); and the submission freeze **did not end** -- 0.1.2 is now in flight, so `main` must still match what CRAN received and this branch still PRs into `dev`. Branch at `7dc3d78`, level with origin and with `main`, clean tree, **2748** tests verified after the merge under both `init.defaultBranch=master` and `=main`, `check-spec.R` 9/9. **One durable lesson came out of it, and it is git-adjacent rather than datom-adjacent**: in a git worktree `.git` is a FILE, so any tool testing for a `.git` *directory* silently gets the wrong answer -- `R CMD build` swept the pointer file into the tarball, `devtools::submit_cran()` skipped writing `CRAN-SUBMISSION` altogether (`devtools:::uses_git()` is `dir_exists()`), and the `.gitignore` rule for that artifact turned out to exist only on this branch. All three fail without saying anything and leave the submission intact, which is why they went unnoticed. Recorded in `dev/engineering-notes.md`. | Task 6, dev/README.md, dev/engineering-notes.md |
| 2026-09-08 | **TASK 6 IMPLEMENTED: `manifest$tables` is now `manifest$artifacts`, and every existing repo still reads.** Landed in one commit as planned, with all six of the task's defaulted items taken at their defaults. What shipped: the rename plus `kind` on every entry; `schema_version: 2` stamped on both manifests and on every per-artifact metadata document; the conversion chain in a new `R/manifest-upgrade.R` (a v1 step that renames the key **in place** so unrecognised sibling keys survive with their position, plus a dispatcher that runs each step in order and records the version reached); five counters filtered on `kind == "table"` with `total_sets` / `set_count` beside them; a `kind` column on `datom_list()` including both empty returns; and a write-side refusal at `datom_write()`'s door, above the routing returns and before any hashing. **Three things the plan did not settle, decided while implementing.** (1) The dispatcher **takes the declared version as an argument** rather than reading it off the document, because the only correct source for that number is the check that refuses a document too new to convert -- so "check first, then convert" is structural rather than remembered (I32). (2) The entry updater **runs that check on what it read from disk** purely to obtain the number; it cannot fire for a write that came through `datom_write()`, whose door already refused a too-new manifest, and the alternative was editing a document whose version was guessed. Task 5's decision that the updater keeps its own **read** is unchanged. (3) A document that did not parse to a named list is **returned untouched** -- stamping one would turn `null` on disk into an object in memory. **Every guard was proven to fail before being trusted, and two of the four would otherwise have shipped green**: disabling the conversion reddens 18 assertions across all four frozen-fixture readers, both tolerance tests and the mirror route; removing the `kind` filters reddens five tests across all three counting sites; moving the door below the routing returns reddens both non-table write routes; dropping the conversion from the entry updater reddens the ten assertions that say a pre-existing table is still counted. All probes reverted. Tests 2748 -> **2836**, FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. **Citations across all three spec files were re-derived by content afterwards** -- this change shifted every line below its edits in six `R/` files, and the gate catches only the ones that land on a blank line. **The purity audit E2 asks for is now due**, in-line, before Task 20. | Task 6, R8, R9.5, R22, I29, I30, I32, P10, P34, AC7, AC30, AC31 |
| 2026-09-08 | **OWNER-DECIDED: bump `schema_version` only when an old reader would get a WRONG answer, not merely a stale one -- and stop old writers by other means.** Recorded because the mechanism cannot express the combination a future change will want. `.datom_check_write_schema()` runs the *same* comparison every reader runs, so the number is one dial driving two gates: raise it and old readers are refused along with old writers. "Old readers proceed, old writers refused" is therefore unreachable by bumping. The two mechanisms that reach it are the **vocabulary check** (a build refuses a document carrying a top-level key it cannot classify -- this is the one that covers a plain added field, where the number must NOT move) and the **writer floor** (for stopping writers for reasons that are not about format at all). Task 6's bump to 2 is correct under this rule: an old reader meeting `artifacts` reports an empty repo silently, which is a wrong answer, not a stale one. The rule earns its keep at the next change, where the tempting move is to bump for a content-bearing addition and refuse a reader that could have read the file perfectly well. | R9.5, R23.2, R23.3, Task 21 |
| 2026-09-08 | **REVERSED, one sitting later: `datom_list()`'s empty results now carry `current_data_sha`.** Task 6 recorded the opposite default with the reason "fixing it changes a public shape nobody asked to change." That reason was already spent when it was written -- the same commit added a `kind` column to that very shape and announced it in NEWS -- and the drift is a real defect, not a cosmetic one: `rbind()` of two frames with different columns errors outright, so a caller collecting listings across projects breaks the moment one of them is empty. Spending the break once, inside a window that is already breaking, beats owing it a release of its own. Recorded as a reversal rather than edited into the original call, because the useful lesson is the shape of the mistake: a "do not change a public shape" argument is worth much less in a release that is already changing that shape, and it should be re-tested against the rest of the commit rather than carried over from the plan. | R8.4, Task 6, AC30 |
| 2026-09-08 | **A write that converts a manifest now announces it; reads stay silent.** From the post-landing review. Conversion is one-way for everybody else sharing the repo: after it, a build predating the rename lists the repo as empty **without erroring**, though `datom_read()` still works because the data path never touches the manifest -- a discovery blackout, not lost access. The flip was silent, and `datom_validate(fix = TRUE)` reaches it while reading as a repair, so a colleague's install could degrade because someone else ran a verification command. One line now fires from the two places that **persist** a conversion (the entry updater, which rewrites the tracked file, and the metadata sync, which mirrors to storage), naming the consequence and pointing at NEWS for the format-to-release mapping. **Reads deliberately say nothing**: a read changes nothing on disk, and a line on every `datom_list()` call is noise nobody can act on. The reader's record gained `declared` so the persisting caller does not re-derive the comparison or read the file twice. | R22.2, R22.3, R9.6, Task 6 |
| 2026-09-08 | **The counters' kind filter is one helper, because a predicate written out four times is a predicate that can differ once.** The post-landing review found the three counting sites aborting on an entry that is not a named list -- with "$ operator is invalid for atomic vectors" -- which the v1 conversion step **deliberately preserves**, since an entry with no shape has nothing to convert. `datom_status()` was the damaging one: it exists to describe a connection when the manifest cannot be trusted, and the count sits outside the error handling that gives it that tolerance, so a hand-edited manifest took the whole diagnostic down. Fixed by routing all four selections through `.datom_artifacts_of_kind()` rather than adding the same guard in four places. **What deliberately did not change**: an entry with no `kind` is still uncounted, no fallback to `"table"` -- skipping a shapeless entry and tolerating a missing type are different, and the second would let a read path that skipped the conversion produce roughly-right numbers instead of visibly wrong ones (R22.8). | R22.8, I28, Task 6 |
| 2026-09-08 | **PURITY AUDIT DISCHARGED for Task 6 -- run LAST, after the review fixes, on owner's call.** The sequencing decision is worth keeping: an audit of a state about to change produces findings that go stale, and two of the four review fixes landed squarely in what an audit inspects (three fresh copies of one predicate, and a public return shape). So the audit went last. **Both questions it existed to answer were settled mechanically, not by reading.** (1) Is the suite blind to the silent blackout? No -- deleting the artifact key from the shared reader's returned document reddens **64 assertions across 36 tests**, covering all five readers and five `datom-cv1` end-to-end scenarios, so the ~40-fixture sweep did not cost the suite its teeth. (2) Did any swept fixture declare the version but omit `kind`, which counts as zero artifacts? No -- making an untyped entry abort inside the selection helper reddens exactly **one** test, the one that deliberately passes an untyped entry to prove it is not counted. That probe replaced a regex over the fixtures, which cannot see an entry spread across lines and fails silently when it misses one. **Two tests were passing whatever the code did and were tightened**: a print test asserting that a `Sets:` line exists (true with a count of zero -- now asserts the number) and a pattern-filter test asserting an empty result from a non-empty fixture (equally true if the manifest was never read -- now asserts the unfiltered call returns a row first). Nothing else changed: each of the five concerns has one home, stamping is still the two sites I29 requires, no read of the old key survives in `R/`, and `R CMD check` is 0/0/0. **One gap named rather than fixed**: the write door inspects the manifest only, and `.datom_sync_metadata()` (`R/utils-sha.R:538`) copies a per-artifact document from the clone to storage unchecked -- pre-existing, narrowed rather than introduced by Task 6, and it belongs with Task 21's entry sequence, which already reads all three documents at the door. | Task 6, Task 21, E2, I29, R22.8, R23.1a |
| 2026-09-08 | **Two loose ends from a second review pass, both closed the same day.** (1) **The zero-row frame was still one column short**, in the case the first fix did not reach: `version_count` is opt-in, so `datom_list(include_versions = TRUE)` on an empty repo returned five columns where the same call on a populated repo returns six -- and a comment asserted no caller could ask for that. Fixed by having the frame take the flag rather than by rewording the comment, because it is the same defect the `current_data_sha` reversal was about and the same argument settles it. Proven non-vacuous: dropping the column reddens the new test. (2) **The metadata-only write route makes the door's check stale.** `datom_write(conn, name = )` reaches `.datom_sync_metadata()`, which pulls from the remote as its first act (`R/utils-sha.R:559`) -- after the door has read and checked the clone's manifest -- so a collaborator's newer-format manifest can arrive in that pull and the route carries on. Harmless in shipped code, because the route writes per-artifact metadata and never the manifest, so nothing can end up half in each format. Not harmless for Task 21, whose entry sequence begins with a fetch and then checks: if a route pulls again afterwards, the checks describe a state the route has already replaced. Written into Task 21's bullets as a decision it must make -- own the fetch, or re-check after it, not both. Also tightened: Task 6's record said "the only pull is inside the push", which is true of the table-write route and not of this one. | Task 6, Task 21, R8.4, I34, R23.4 |
| 2026-09-08 | **TASK 20 IMPLEMENTED: a field this build cannot place now survives a write instead of being deleted by the rebuild.** New `R/forward-compat.R` with one merge helper and two vocabularies, called from `datom_write()` and from the manifest entry updater. **The finding that shaped it: only two of the three levels needed code.** The manifest's **top level** already survives, because that document is read, edited and written back rather than rebuilt -- so the guarantee there is a property of *editing*, and a later refactor to assembling a fresh document would remove it without failing anything else. Tested for exactly that, and proven by probe: building from the skeleton instead of reading the file reddens the top-level test. **The narrowness is the other decision, and the alternative is wrong rather than merely different**: only unplaceable fields are carried, so a field datom knows still disappears when the write does not set it. `original_format` decides it -- a table imported from a CSV and later written straight from a data frame has no format to declare, and a blanket keep-what-the-new-document-omits would leave that claim standing against a version it does not describe. A wrong statement is worse than a missing one, and three tests redden under the blanket form. **Placed after the version identity is computed**, beside the `parquet_sha` assignment: identity already ignores what it cannot place, so both positions hash the same today, but attaching afterwards means a carried field cannot reach a hash at all and no later change to the identity list can pull one in. **Six probes, each reverted**: removing either merge reddens both halves of its round trip (git and storage); rebuilding the manifest reddens the top-level test and the row test; widening the merge reddens all three narrowness tests; and an unclassified field added to either builder reddens that builder's forcing function, naming the field -- the metadata one while every pinned identity hash stays green, which is the allowlist's failure direction and visible only there. Tests 2867 -> **2898**, FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. No pathway impact. | Task 20, R23.8, P38, AC34 |
| 2026-09-08 | **`.datom_metadata_known_fields()` is a function and not a stored vector, because `R/` is sourced alphabetically.** DESCRIPTION declares no `Collate`, so `forward-compat.R` is sourced **before** `utils-sha.R`, where the identity list and the not-identity list both live. A constant joining them here would be built from values that do not exist yet and the package would fail to install. Same trap `R/manifest-upgrade.R`'s header records for its step table, arrived at from the opposite direction -- there the rule is that a step must be defined *above* the table in the same file, here it is that a derived constant must not reach across files that sort later. Deriving at call time also means the union cannot fall out of step with either half. Worth a row because the obvious tidy-up is to make it a constant "for symmetry" with the two it joins. | Task 20, `R/forward-compat.R` |
| 2026-09-08 | **The manifest row's vocabulary is hand-listed, not derived, and that is what makes its test a forcing function.** Eight names today. A vocabulary read off the row builder's own output could never disagree with the builder, so it would assert nothing; listing it by hand and then asserting every field of a real written row appears in it is what fails when someone adds a field without classifying it. The failure matters more than it looks: an unclassified row field would be treated as unplaceable and carried forward from the previous row on every later write, so it would go stale rather than being recomputed. **Task 9 will trip this deliberately** when it adds the set row's member count -- the name is not pre-listed. The metadata document needs no equivalent new list, since Task 19's classification test already polices that builder and this task only joins its two halves. | Task 20, Task 9, Task 19 |
| 2026-09-08 | **Three live code citations were already wrong before this change, found while re-deriving the ones it shifted.** Two lines cited as `datom_write()`'s return-value `name` and one cited as its in-pipeline manifest read all pointed at unrelated statements, as did Task 19's citation of where `parquet_sha` is assigned. None was caused by this session: verified against the previous commit before repointing. Check 5 cannot see this class -- it asserts only that a cited line is not blank -- so the standing instruction holds and is now proven for a third consecutive session: after any insertion into `R/`, re-read citations **by content** with `SPEC_CHECK_SHOW_CITATIONS=1`. One imprecise citation was deliberately left: `R/sync.R:179` lands on the comment above the mirror route's manifest read rather than on the read itself, and the surrounding claim in Task 4's record -- that this site is an excluded raw local read -- was overtaken by Task 6 routing it through the shared reader. Left as a historical record rather than rewritten. | dev/check-spec.R, Task 20, Task 19 |
| 2026-09-08 | **A FOURTH SURFACE the carry-forward requirement does not name: an entry in `version_history.json`.** Raised in review of Task 20. It is safe by the same property as the manifest's top level -- the history list is read and the new version is **prepended**, so an entry already in it is never rebuilt -- so no code was needed. It was worth **pinning** rather than leaving as an observation for one specific reason: **two later tasks add fields to those entries** (Task 7's `document_sha`, Task 15's `commit_sha`), and a build that normalised an old entry to today's field set would destroy exactly those, on a record describing a version it may know nothing about. One test plus a comment at the site telling the next reader not to normalise entries on the way past. Proven non-vacuous: rebuilding the existing entries from known names reddens both halves of it. Same reasoning as the manifest top level, which is also code-free and tested anyway -- **a guarantee that rests on the shape of a function rather than on a check needs a test, because a refactor removes it without failing anything else.** tests 2898 -> **2902**. | Task 20, Task 7, Task 15, R23.8 |
| 2026-09-08 | **`document_sha` is the one name this build classifies and never writes, which makes it invisible to carry-forward -- Task 7 owns the consequence.** Verified mechanically rather than by reading: the vocabulary holds 17 names, the metadata builder emits 16, and the difference is `document_sha`, classified as not-identity by Task 4 before anything wrote it. Carry-forward only rescues names a build **cannot** place, so a metadata document arriving with `document_sha` on it loses the field on rewrite -- and silently, because the field takes no part in identity, so no version moves to signal the loss. **Unreachable today and still unreachable under Task 7 as specified**, which puts the field in `version_history.json`, where the fourth-surface property protects it. Recorded because the tempting later tidy-up is to move it into `metadata.json` beside the other hashes, and that is a decision with a consequence rather than a relocation. The reusable shape: **classifying a field ahead of writing it is not free** -- it buys identity-stability early and costs carry-forward protection until a builder emits it. | Task 20, Task 7, Task 4, R23.8 |
| 2026-09-08 | **Process, from review of Task 20's own checkpoint message: a summary asserted five open calls "taken as defaulted" when the task's record contained none, and asserted the commit was unpushed without checking.** Both are the same failure in different clothes -- reporting a state from memory of what was planned rather than from what is written down or true. Fixed by recording the five calls in Task 6's shape, with the correction that they were **explicitly approved** rather than defaulted on silence, which is a stronger claim and the accurate one. The countermeasure for the second is procedural: verify remote state before describing it, exactly as the operational rule already requires before *retrying* a remote-mutating action. Recorded because Task 6's open-call discipline is what made the last two rounds checkable, and a summary that invokes that discipline without the record behind it spends its credibility for nothing. | Task 20, Task 6 |
| 2026-09-08 | **CLASSIFY A FIELD WHEN YOU START WRITING IT, NEVER EARLIER -- now guidance plus a guard, owner-approved.** The `document_sha` finding generalises into a rule for whoever edits this package: classifying a name ahead of the code that produces it looks like preparation and quietly costs the field its protection, because carry-forward rescues only names a build **cannot** place. **The asymmetry that let it through, found by asking whether any guard existed**: the identity list has always carried a converse arm (nothing on it may be a field datom never writes -- added to block the rejected `name` shortcut), and neither the **not-identity** list nor the **manifest-row** list had one. `document_sha` sits on the first of those two. Both now do, with an explicit exception vector holding exactly one name and its reason; the row list needs no exception, since its eight names are precisely what a row carries with both optional fields supplied. **Three probes, each reverted**: a junk name on either list reddens that list's arm naming the field, and emptying the exception vector reddens it naming `document_sha` -- so the vector is load-bearing rather than decorative. The prose half is in `.github/copilot-instructions.md` (always loaded) and `dev/engineering-notes.md` (the mechanism, read before editing `R/`); the same edit fixed two stale claims there -- the carry-forward bullet said three levels where there are four, and the section heading said "two pitfalls" while carrying three, which is the restate-a-count defect these documents keep catching elsewhere. **Deliberately not user-facing**: this is a test and two developer documents, nothing in a user's session. tests 2902 -> **2905**. | Task 20, Task 7, R23.8, `dev/engineering-notes.md` |
| 2026-09-08 | **COLD-START AUDIT FOR TASK 21: startable, after one correction and three additions. No escalation flag on it** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. The documented path was walked as a fresh reader and every claim in the task's body checked against the tree. **What held**: `R/utils-sha.R:559` really is the pull that makes the metadata-only route's door read stale; `R/sync.R:177` is the mirror route; the routing-return citations are right after this session's repointing; `datom_get_conn()` does parse `project.yaml` (`R/conn.R:930`), so the floor can ride on the conn as specified; and `custom` is on the identity list and hashed whole, so "opaque and classified as a whole" is true in code. **THE CORRECTION, and it is one I introduced yesterday**: Task 20's record claimed the refusal "inspects top-level keys only, so an unplaceable field inside a manifest row never trips it". R23.1 scopes the check to **three** documents and names manifest **entries** as one of them -- "top-level keys only" means *do not descend into a value*, not *ignore entries*. So all three of Task 20's coded levels become unreachable through the write door, and the case that stays live is the **version-history entry**, which R23.1's scope list does not include: the test written for it in the review round is load-bearing rather than belt-and-braces. The wrong claim had reached four places and is swept in all of them -- the classic defect this log records seven times, this time self-inflicted within one day of writing the rule against it. **THREE ADDITIONS to Task 21's body.** (1) **Three scopes means three lists, and Task 20 built two of them** -- `.datom_metadata_known_fields()` and `.datom_manifest_entry_known_fields` -- leaving only the manifest's **top level**, whose five names (`schema_version`, `project_name`, `artifacts`, `summary`, `updated_at`) were derived by grepping every top-level assignment rather than guessed, with the `datom_sync()` result-frame columns of the same name flagged as a decoy. Without this a reader would have reached for the metadata lists, which name `data_sha` and `colnames`. (2) **The hole Task 6's purity audit handed forward is now in the task's own body** -- `.datom_sync_metadata()` copies a per-artifact document to storage unchecked -- rather than only in Task 6's record, and it is noted as the same route as the staleness item, so one decision covers both. (3) One citation repointed: `R/read_write.R:334-343` landed on roxygen, and the storage read it was pointing at is at `349`. | Task 21, Task 20, R23.1, R23.1a |
| 2026-09-09 | **TASK 21 IMPLEMENTED: a write now stops when this build cannot fully account for the repo it is writing into.** One function, `.datom_check_write_entry()` (`R/forward-compat.R`), called where the manifest-only door used to sit -- after the `datom_conn` class check, above both routing returns, above any hashing or local write. Four steps in a fixed order: the **floor** (`min_writer_version` in `project.yaml`, read onto the conn, absent means no limit), the **manifest** through the one shared reader with the refusal worded for a write, the **shape the conversion reached**, and the **vocabulary** on the manifest's top level, on each artifact entry, and on each per-artifact `metadata.json` the write will touch. All clone copies -- local file reads, no network. `.datom_check_write_schema()` is **gone**, absorbed rather than kept beside the new sequence: two doors reading the same file at the same moment have no way to say which runs first, and the order is load-bearing (a policy refusal before anything about format; the format check before the conversion, because there is no conversion step for a version this build has never heard of). **Seven probes, each reverted and each naming what it reddened**: the vocabulary check 6 tests, the floor 3, the shape refusal 1, emptying the per-artifact loop 5, pruning the retired name 1, the per-artifact schema check 1, the re-check after the pull 1. The last three would each have shipped green without their probe. Tests 2905 -> **2959** (+54), FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. **Pathway impact**: a new route card, and the schema card's write-side paragraph now points at it. | Task 21, R23, I31, I32, I33, I34, P37, AC35, AC36, AC38(a) |
| 2026-09-09 | **DEVIATION, recorded rather than quiet: design 10.7's step-1 fetch is NOT implemented.** A fetch updates remote-tracking refs and **not the working tree**, so it cannot make any of the four checks read a fresher document -- every one of them reads a file the route is about to write. The only thing that would refresh them is the behind-comparison in `.datom_check_git_current()`, which **aborts**; adding that to `datom_write()` would newly refuse an offline write that works today, and would make the mirror-everything route -- which touches no git at all -- depend on `git2r`, which is in **Suggests**. So the step buys nothing for the checks and costs two behaviour changes. What it was really aimed at, staleness on the one route that pulls, is solved directly by the row below. Reversible in one line if the abort is wanted for its own sake. | design.md 10.7, Task 21 |
| 2026-09-09 | **THE STALENESS QUESTION IS ANSWERED BY RE-CHECKING, NOT BY OWNING THE PULL.** Task 21's body named two options and required one. `.datom_sync_metadata()` pulls from the remote as its first act, after the door has read the clone, so a collaborator's newer manifest or metadata document can arrive in that pull and the route would carry on into a repo it had been told it understands. That route now calls `.datom_check_write_entry()` **again** immediately after the pull, against what the pull left on disk. Rejected: the sequence owning the freshness -- one fetch at the door, no route pulling afterwards -- which fails twice on its own terms, since a fetch does not refresh the working tree and dropping that route's pull would leave its commit on a stale base. Re-running costs nothing: every step is a local file read and none mutates anything, which is why the function is documented as callable more than once. Pinned by a test that mocks the pull into planting an unfamiliar field. | R23.4, I34, Task 21, Task 6 |
| 2026-09-09 | **The hole Task 6's purity audit handed forward is closed, on the same route.** `.datom_sync_metadata()` copied a per-artifact metadata document from the clone straight to storage with nothing checking its declared format, so a document pulled from a collaborator on a newer datom went through unexamined. The entry sequence now runs `.datom_check_schema_version(operation = "write")` on each per-artifact document alongside the vocabulary check. Worth noting the two items are one item: it is the same route whose door read goes stale, so the re-check above is what makes the closure hold rather than only appearing to. | Task 21, Task 6, R23.1a |
| 2026-09-09 | **`tables` is on the manifest vocabulary, marked retired, and that is the append-only rule made mechanical.** The list holds the five names a manifest carries plus the artifact list's pre-v2 name. In practice the conversion renames the key before the check sees it, so the entry earns its place two other ways: it is the worked example of retiring a name by marking rather than deleting, and it is insurance if the check is ever consulted on an unconverted document. AC35(c) tests exactly this, and pruning the name reddens it. The reason it matters is directional and easy to get backwards -- a build that forgets a name meets an **older** document, fails to place a key it should know, and refuses it, blocking the upgrade direction, which is the one direction that must always work. | R23.2, I31, AC35(c) |
| 2026-09-09 | **The vocabulary check runs on the CONVERTED manifest, never the raw one.** Getting this backwards deadlocks the forward path by a different mechanism than the one R23.4 warns about: a pre-rename document holds its list under `tables`, so a check on the raw document would refuse every existing repo. Same shape of trap as R23.4's own wording -- "refuse when the expected key is absent" versus "still absent after the chain has run" -- and both are settled the same way, by asking what the conversion can reach rather than what the file says. AC35(d)'s test asserts a v1-shaped clone manifest writes normally, **and asserts the pre-state**, so it cannot pass by the fixture edit silently not having taken. | R23.1, R23.4, AC35(d) |
| 2026-09-09 | **AC36(c) is not implemented, and it is not owed by Task 21.** "Setting a floor above the setting build's own version is refused" is a guard on the **setter**, and R23.3 defers the setter (a normal commit cannot validate that the raiser satisfies the new value, so it needs a purpose-built verb -- the R15 named-verbs precedent). No code path in this build sets the field, so the clause has nothing to bind to. It ships with the raising verb; the `dev/README.md` Backlog row for that verb owns it. Recorded rather than left as an absence, because Task 21's criteria line names AC36 whole and silence there reads as an omission. | AC36, R23.3, `dev/README.md` Backlog |
| 2026-09-09 | **A malformed floor value aborts rather than being read as no floor.** `min_writer_version` is optional and absent means no limit, which makes the tempting implementation `if (is.null(x) \|\| !parses(x)) return()`. That turns a typo in a policy field into a silently disabled policy -- the failure the mechanism exists to prevent, arriving through the mechanism. Refused with its own class, `datom_writer_floor_invalid`, and the message says how to mean "no floor" (remove the field). Same call as the schema check's refusal of a present-but-unusable `schema_version`, for the same reason. | R23.3, Task 21 |
| 2026-09-09 | **Artifact discovery is one helper, because the door has to inspect exactly the set the route writes.** `.datom_clone_artifact_names()` (`R/sync.R`) was factored out of `.datom_sync_data_metadata()`, which now calls it too. On the mirror-everything route there is no artifact name in the arguments at all, so the door enumerates -- and discovering the set twice, in two spellings, is how the door ends up checking a different set than the one that gets written. The discriminator stays what it was: a directory holding a `metadata.json`, with the fixed non-artifact directory list as a convenience rather than the test, so a foreign directory is tolerated (R14.2) rather than misread. | R23.1, R14.2, Task 21 |
| 2026-09-09 | **Task 21 makes all three of Task 20's coded levels unreachable through `datom_write()`, and the four round-trip tests now hold the door open with a mock.** Expected, predicted, and not a reason to remove the merge. What stays genuinely live is the **version-history entry**, which R23.1 does not scope -- so the test written for it in Task 20's review round is the load-bearing one rather than belt-and-braces. The merge is kept and kept tested for one forward-looking reason: the day a release widens what the door accepts, the merge behind it has to already work, and a merge that quietly broke while unreachable would ship as a silent field deletion on the first write that got through. The mock is named `fc_hold_door_open()` with the reasoning at the fixture, so nobody later reads it as a test working around its own subject. | AC34, AC35, Task 20, Task 21 |
| 2026-09-09 | **Live code citations re-derived by content for a fourth consecutive session; dated rows left frozen.** This change shifted lines in five `R/` files, and eight distinct citations had drifted: the two routing returns, the mirror route's manifest read, the entry updater, `datom_sync_manifest()`'s read and its artifact lookup, `.datom_has_changes()`'s storage read, and the local metadata write's `git_paths`. Two of them were already wrong before this session. Repointed only where the citation is a live instruction -- dated Decisions rows record what was true on their date and stay frozen per the 2026-08-23 policy. Check 5 sees none of this class: it asserts only that a cited line is not blank. | dev/check-spec.R, Task 21 |
| 2026-09-09 | **REVIEW OF TASK 21: the write entry goes on the FUNCTION, not on each caller.** `datom_validate(fix = TRUE)` reaches storage by calling `.datom_sync_data_metadata()` directly (`R/validate.R:183`), so it never passed `datom_write()`'s door -- no floor, no vocabulary, no per-artifact format check, while the NEWS entry claimed the checks covered every write route. Bounded damage, because that route copies documents rather than rebuilding them, so nothing was being deleted. **The argument that settles it is the floor's**: its stated purpose includes a block for a reason that is *not about format* ("0.1.4 wrote bad hashes"), and those cannot be enumerated ahead of time -- so "this route only copies" cannot license skipping it. Fixed by moving the call into `.datom_sync_data_metadata()` after its role and path guards; the `datom_write()` route now runs the sequence twice, which costs nothing and means the next caller cannot forget. **This is the third task running in which this route has been the gap** (Task 6's open call 1, Task 6's purity audit, now this), which is the more durable finding: a repair verb that reaches storage without going through the write verb will keep being missed, so gate the shared function rather than the entry points. Probed: removing it reddens two tests. | Task 21, R23.1, R23.3, `R/validate.R` |
| 2026-09-09 | **A probe caught a test asserting the wrong thing, which is the reusable part of this round.** The mirror route read the manifest with the shared reader's default `operation = "read"`, so a too-new manifest on its way to storage reported a format this build "cannot read" -- during a write. One argument fixes it. But the test written for it **passed with the fix reverted**, because the entry sequence refuses a too-new manifest a few lines earlier with the right verb already, so the abort came from there. The test now mocks the entry out so the read answers for itself, and reddens on reversion. Kept rather than dropped as unreachable, on the rule this spec applies elsewhere: a message that is correct only because something upstream refused first starts lying the day the refusal moves. **The transferable bit is the method** -- the probe was what distinguished "my fix works" from "something else already covered this", and reading the code would not have. | Task 21, Task 6, R22.4 |
| 2026-09-09 | **ACCEPTED RESIDUAL: the door's answer can be stale on the table-write route, and re-checking cannot fix it.** `.datom_git_push(pull_first = TRUE)` pulls at step 7 (`R/read_write.R:849`), **after** step 6 has written the metadata document and edited the manifest -- so a collaborator's newer-format document can arrive after the door passed, with the write already built. The metadata-only route's remedy (re-run the sequence after the pull) does not transfer: there is nothing left to re-check before. Left as it is deliberately, because the backstop is real and design 10.7 already argues for exactly this trade -- the push aborts on rejection or on a merge conflict, the storage steps are 8-10, so a write cannot reach storage from a base this build has not seen, and abort-after-commit is acceptable for a rare race while unacceptable as a primary mechanism. Recorded because Task 21's summary said the staleness problem was "solved", which holds for one route and overclaims for the other. | design.md 10.7, I34, Task 21 |
| 2026-09-09 | **COLD-START AUDIT FOR TASK 22: startable, after eight additions to its body. No escalation flag on it** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. Every claim in the task was checked against the tree; two of its own citations had drifted and are repointed, and its "`original_format` never reaches metadata" claim verifies. **The one that would have done real damage: the test surface is three files and eight assertions, not "the assertion in `test-query.R`".** Every `datom_schema_unsupported` assertion was enumerated and split into the six that must flip to warn-and-rebuild and the nine that must not be touched -- including the load-bearing one, `.datom_read_manifest`'s own returned-versus-thrown contract test, which the task's body did not mention at all. Leaving five of them would have left the suite asserting the opposite of the design, which is this spec's recurring defect arriving in the one place the task itself says it must not. **Two findings shrink the task.** Task 21 already shipped the **writer** half of R22.11 -- a too-new manifest and an unreachable shape both already refuse at the write entry -- so what is left is the reader half plus `original_format`. And R22.10's dispatcher guard plus AC38(b) and (c) were already done by Task 6, with the zero-steps test counting step invocations through a mocked step table rather than comparing output. **One finding removes the hard part**: Task 21 gave `.datom_read_manifest()` an `operation` argument for a message-wording reason, and every writer call site already passes `"write"` -- so "reader rebuilds, writer refuses" is a branch on an argument that already exists, with no role inspection and no new plumbing. **Three findings are traps.** A rebuilt entry must stamp `kind = "table"` or every counter reads zero, because R22.8 deliberately has no missing-`kind` fallback and the field is not in per-artifact metadata until Task 7. `original_format`'s classification is a real decision -- `original_file_sha` is already in the identity list, so the symmetric choice would re-mint a version for every imported table in every repo. And AC37(c)'s empty-repo fixture must be current-shaped, since an empty **v1** manifest legitimately does trigger a rebuild. **One correction to an earlier audit**: a Task 6 row claims `.datom_validate_tables()` enumerates artifacts from a storage listing. It enumerates from the **clone** (`R/validate.R:386`), which matters because the rebuild exists for the reader who has no clone -- so there is no storage-side enumerator to reuse, only the primitive `.datom_storage_list_objects()`, which returns **full** keys. | Task 22, Task 21, Task 6, R22.8, R22.10, R22.11, R22.12, AC37, AC38 |
| 2026-09-09 | **`dev/check-spec.R`'s citation check now covers `tests/testthat/` as well as `R/`, and it found three stale citations on the round that added it.** The gate had guarded only `R/file.R:NNN`, so every test-file line number in this spec was unchecked -- including Task 5's and Task 6's lists of the tests that must **not** be swept, which are instructions a reader is meant to walk. Task 22 made the gap expensive: it has to flip six named assertions and leave nine others alone, and a stale number there points at the wrong assertion in a file of a thousand lines rather than at nothing. One regex. It immediately failed on three pre-existing citations (`test-summary.R:163` and `test-sync.R:1283` had gone blank; seven more resolved to unrelated lines and were repointed by content), and it was **verified by planting a wrong number and confirming a FAIL**, per this spec's rule that a green run is not evidence. Same lesson as the round that added check 6: the checks that matter are the ones derived from a defect that already shipped, and this one had shipped invisibly in two task bodies. | dev/check-spec.R, Task 22, Task 5, Task 6 |
| 2026-09-10 | **A rebuild persists nothing, at any role -- stricter than the design required.** Design 10.4 only constrains a **storage-only** reader to rebuild in memory, which left writing the clone's copy available for a developer. Not taken. A read that quietly rewrote a repo's index is a larger surprise than the one it is fixing, and the recorded copy is repaired by the next ordinary write anyway -- so persisting buys nothing and costs the "reads never write" property that makes the rebuild safe to reach from five call sites. Recorded because the design text reads as permission. | design.md 10.4, R22.12, Task 22 |
| 2026-09-10 | **Which recorded version is the current one is a decision the requirement does not make.** "Read the `version` from `version_history.json`" reads as "take the newest entry", and that is wrong in a case that already exists: a write reverting to content already in the history appends **no** entry (`exists_already` in `.datom_write_metadata_local()`), so the current state is an older row and the newest one describes different content. `.datom_recorded_current_version()` narrows by `data_sha` first -- one match settles the revert case -- and by the `created_at` that a history entry copies verbatim second, which separates two metadata-only versions of the same content. Nothing is recomputed in any branch, and a history recording nothing usable yields a row with **no** version rather than a manufactured one, because an index pointing at a version that does not exist is worse than one admitting it does not know. | R22.12, AC37(e), Task 22 |
| 2026-09-10 | **`original_format` is classified NOT identity.** Its sibling `original_file_sha` is in the identity list, so the symmetric choice looks right and is wrong: this build already writes `original_format` onto the manifest row and is only now persisting it into metadata, so in identity it would re-mint a version for **every imported table in every repo**, on content that did not move -- destroying the task's own claim that the field is additive and free. The extension also says nothing about the data that `data_sha` does not already fix. | R9.5, AC33(d), Task 22 |
| 2026-09-10 | **AC37(f) has one exception, stated at the assertion rather than left implicit: `last_updated`.** The writer stamps the wall clock at the moment it rewrites a manifest row, and that moment is in no document -- so a reconstruction cannot reproduce it. The rebuild uses the version's own `created_at`, which is the closest true statement available. The test asserts every other field equal and this one present and plausible, and says why, so the next reader does not "fix" it by inventing a timestamp. | AC37(f), Task 22 |
| 2026-09-10 | **All eight assertions Task 22's audit told us to flip PASSED UNCHANGED after the code change, for the wrong reason.** The mock storage in those tests had no listing, so the rebuild failed and the original schema refusal was re-signalled -- the same class the old assertions checked for. A green run would have shipped a suite asserting the opposite of the design, in the one place the task body said that must not happen. The audit's enumeration is what caught it; nothing in the suite would have. **The transferable rule: when a behaviour flips, the old assertion passing is evidence of nothing until you have checked which code path satisfied it.** Each flipped test now says AMENDED and states what did **not** change, since AC32's reason still holds. | AC32, AC37, Task 22, Task 5 |
| 2026-09-10 | **Two R-level traps that make a condition's class disappear on its way to a handler, both hit in one session and both now in `dev/engineering-notes.md`.** They matter here because the whole reader/writer fork is decided **by** class: a compatibility refusal has to keep travelling while a storage failure becomes a return value. (1) `stop(cnd)` inside one `tryCatch()` handler is caught by that same `tryCatch()`'s `error` handler -- so the natural spelling "re-raise this class, catch everything else" does the opposite, and it turned every refusal raised inside the rebuild into an IO failure. Catch once, decide afterwards, re-signal from outside every handler. (2) `purrr::map()` re-signals a mapped function's condition as its own `purrr_error_indexed`, with the original demoted to a `parent`, so `inherits()` is FALSE and a class-specific handler never fires -- which is why the artifact loop in `R/manifest-rebuild.R` is `lapply()` and must stay `lapply()`, with the reason at the site. Both defects go green in a suite that only checks that something failed. | dev/engineering-notes.md, Task 22 |
| 2026-09-10 | **A rebuilt row is stamped `kind = "table"`, and Task 7 owns that line.** Per-artifact metadata does not say what kind an artifact is until Task 7, so the rebuild has nothing to recover the field from. Hardcoding is not optional: R22.8 deliberately gives the counters no missing-`kind` fallback, so an untyped row is silently uncounted and a rebuilt repo would list its artifacts while reporting zero of them. Correct today because nothing writes a set until Task 9. The comment at the site names both tasks. | R22.8, Task 22, Task 7, Task 9 |
| 2026-09-10 | **Live code citations re-derived by content for a FIFTH consecutive session, and this round the test citations dominated.** Four `R/` citations had gone blank (two in `R/read_write.R`, one in `R/utils-sha.R`, one in `tests/testthat/test-summary.R`) and **fifteen test citations** needed repointing because this change renamed tests in three files -- the flipped assertions Task 22's audit had named by line. Check 5 caught only the four blank ones; the other eleven resolved to unrelated lines and were repointed by content. Dated Decisions rows left frozen per the 2026-08-23 policy. The 2026-09-09 round that extended check 5 to `tests/testthat/` predicted exactly this cost and was right to. | dev/check-spec.R, Task 22 |
| 2026-09-10 | **REVIEW OF TASK 22, finding 1: the hardcoded `kind = "table"` on a rebuilt row now has a forcing function instead of a comment.** The review said "nothing fails" when Task 7 adds `kind` to the metadata builder, which is not quite right -- `test-utils-sha.R`'s pinned fixture list reddens, because it asserts the builder emits exactly a named set. But it reddens in a test about identity hashing and says nothing about the rebuild, so the revisit still depended on somebody remembering. A test in the rebuild's own file now asserts the metadata builder emits **no** `kind`, next to the line that hardcodes it, with instructions for what to do when it fails. **The failure it prevents is the one Task 6 exists to prevent**: once Task 9 writes a set, a rebuilt repo would type it as a table, so the set counters read zero while the artifact still appears in `datom_list()`, and nothing errors. Probed: adding `kind` to the builder reddens that test and no other. | R22.8, Task 22, Task 7, Task 9 |
| 2026-09-10 | **REVIEW OF TASK 22, finding 3: no history entry matching the current content now returns NO version, where it had fallen back to the newest entry.** The fallback and the test two lines from it disagreed. `.datom_recorded_current_version()` narrows candidates by `data_sha`; when nothing matched it took the newest entry, which is a version of **different content** -- while the neighbouring test pins that three other unusable histories yield no version at all, on the stated grounds that a manufactured version is worse than a missing one. Fixed in favour of the test, because it is the same trade the carry-forward rule already makes: a claim that outlives what it described is worse than an absent one. No match means the history does not record the state `metadata.json` describes -- a truncated or partly-synced history, which `datom_validate()` owns. The remaining ambiguous case still takes the newest **candidate**, and that is different in kind: both candidates describe the current content, so the worst case is naming the wrong one of two versions of the same bytes. Probed: restoring the fallback reddens the new test. | AC37(e), Task 22 |
| 2026-09-10 | **ACCEPTED RESIDUAL from the Task 22 review: the rebuild repeats on every call, and nothing memoises it.** One listing plus two reads per artifact means a 300-artifact repo spends ~601 storage requests **per command** for as long as the index stays broken, and `datom_status()` reads two copies of the manifest, so a repo broken on both sides pays twice in one call. The user experiences it as datom hanging, because the warning only arrives once the work is finished. That is precisely the cost the manifest exists to avoid (`dev/datom_specification.md:1694`). Not fixed, and the reason is not effort: a session cache is already deferred package-wide pending its invalidation design (`dev/datom_specification.md:2031`), so memoising here would put session state into a library that has none, in order to speed up a state the next ordinary write removes. Recorded in the `R/manifest-rebuild.R` file header as well as here, the way the table-write staleness residual was, so it is met as a known trade rather than as a surprise. | R22.12, Task 22, dev/datom_specification.md |
| 2026-09-10 | **NEW TASK 23 -- `project.yaml` gets a format number, and the general rule for which mechanism a document gets.** Accepted from a proposal, with three of its premises corrected. **The rule is the durable part**: a **machine-written** document (manifest, per-artifact metadata) gets a **vocabulary check**, because an unrecognised key there *is* evidence a newer datom wrote it; a **hand-edited config** (`project.yaml`) gets a **version number**, because an unrecognised key there is as likely a typo or a private note, and refusing on one would block every write in the repo until somebody found it. AC39(d) tests that a stray key is still tolerated, which is what stops the vocabulary check being extended to that file later as a tidy-up. **Three corrections to the proposal, recorded so they are not inherited as fact.** (1) `project.yaml` is **not** the only datom-owned document without a format number -- `version_history.json`, `governance.json`, `ref.json` and `dispatch.json` have none either; only the manifest and per-artifact metadata carry one. It is the only **hand-edited** one and the only one carrying writer policy, which is the argument that actually supports a number. (2) The harm is not "running `datom_sync()` on a set": Task 11's own body says today's behaviour on a product repo is a silent **no-op**, so an older build gets an unhelpful answer rather than a corrupting one. (3) Once a repo holds a set, an older **writer** is already stopped by Task 21's vocabulary check, because Task 7 adds `kind` to metadata -- and per R9.5 that addition moves **no** number, so a number would never have caught it. **The window this protects is therefore narrower than proposed: a product repo that does not yet hold a set**, which is exactly the state right after init and the state in which somebody reaches for `datom_sync()`. The stronger motivation the proposal did not make is that **`min_writer_version` already lives in that file** (Task 21), so it already carries policy an older build silently ignores; the number is the general mechanism that makes the *next* policy field enforceable rather than advisory. **One verified finding the proposal left as "confirm this": one gate does NOT cover every read.** `.datom_resolve_data_location()` re-reads `project.yaml` after a git pull (`R/ref.R:327`) and is called from `R/conn.R:1030`, *after* the parse at `R/conn.R:1070` -- so a config arriving in that pull is unchecked, and `conn$min_writer_version` is read from the same pre-pull parse (`R/conn.R:1081`), meaning a pulled floor raise is missed in that session too. Pre-existing; the task must either gate the re-read or record the residual, not omit it. | R9.8, AC39, Task 23, Task 11, Task 21, R23.1 |
| 2026-09-10 | **Task 23 executes immediately before Task 11 rather than last, and Task 11 states the dependency.** The proposal put it at the end of the list with a note that it "must ship in the same release as Task 11". Same guarantee, but enforced by memory at release time -- and the failure it insures against is precisely a release split with Task 11 in the earlier half. Making it the task immediately before Task 11, with the dependency written into Task 11's body, makes the constraint structural and removes the cross-reference that would otherwise have to be kept true in two places. Phase E's own filter argues for this: an irretrofittable half belongs early relative to the thing it protects, not at the end of a list where it can be deferred while the thing it protects ships. | Task 23, Task 11, Phase E |
| 2026-09-10 | **The execution order was swept in one copy of three, and `check-spec.R` check 6 now guards it.** Adding Task 23 updated the state block's order and left Phase E's preamble and the `dev/README.md` status cell both saying the sequence ended at Task 7. **Found by the owner reading the file, not by the gate** -- which is the same defect class check 6 was built for, arriving in a third kind of content after the encoder pseudocode and the AC bounds. Check 6 now extracts every arrow chain beginning `18 -> 19` from all three spec files **and** from `dev/README.md`, and fails when two copies disagree, naming which one is behind. Two design points worth keeping: the copies are compared **against each other** rather than against an expected sequence, because the order changes legitimately and a gate holding today's answer would need editing every time it moved -- which is how a gate stops being trusted; and the text is collapsed to one string before matching, because the state block's copy **wraps across two lines**, so a line-by-line scan sees two short chains and the disagreement hides in the split. Verified by reintroducing the exact defect the owner found, and separately by staling only the README: both FAIL. `dev/README.md` is read for this one clause only, since that is where the third copy lives and the copy a person meets first. | dev/check-spec.R, Task 23, Phase E |
| 2026-09-10 | **COLD-START AUDIT FOR TASK 7: startable, after two corrections to its own body, one property rescoped and five additions. No escalation flag** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. **Two statements in the task were wrong.** (1) It cited "design.md section 4 matrix" for the set's collapsed field set; section 4 is about tags replacing structure and contains **no** field matrix, so the citation sent a fresh reader after a table that does not exist. The authoritative list is **R1.3** (seven named fields) with R1.4 for the exclusions. (2) It said to **keep `document_sha` out of the metadata document**, which contradicts R1.3 -- that field is one of the seven -- and would break the read gate, since R7.1 requires the stored payload verified *before parsing* and the reader has nowhere else to get the expected hash. The Task 20 concern behind the old wording does not survive R1.3 either: carry-forward only matters for a field **nothing writes**, and once the set builder writes it no rewrite can lose it. **The finding that would have done real damage: adding `kind` re-mints a version for every existing table, and a fresh session would have read that as a defect.** Verified by computing the hash both ways. It is an accepted owner decision (2026-08-23) that lives **only** in a dated Decisions row, and both fixes a fresh session would reach for were closed off in that same decision -- `kind` cannot leave the hash (a table and a set could then share a version identity) and cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata, because the manifest can lag a partial write). Now stated in the task body. **P36 rescoped**: its first clause said adding *any* field leaves every `metadata_sha` unchanged, which is false for a field added **into** identity and therefore contradicted that decision -- the same correction P35 and AC32 needed when Task 22 changed their subject. **Three additions.** Task 7 **legitimately moves two pinned goldens** (`test-utils-sha.R:1002`), which is the first licensed exception to "if a golden fails the code drifted"; the tests it reddens are **six** sites, now enumerated with live citations rather than left to be found; and the sixth of those (`test-manifest-rebuild.R:381`) is a **handoff**, not a failure to silence -- it exists to make this task change `R/manifest-rebuild.R:200`, where a rebuilt row is stamped `kind = "table"` because nothing in metadata says otherwise, and deleting the test instead leaves a rebuilt set reported as a table with the set counters reading zero. Also recorded: the set builder's two concrete values (`.datom_canonical_set_hash()` for `data_sha`, the literal `"datom-sv1"` for `hash_algo`, both easy to get wrong by copying the table builder), that `document_sha` is **inert until Task 9** so whether its plumbing lands here is a choice with a stated default, and that all three acceptance criteria are assertable here on the **builder's output** only, since nothing writes a set until Task 9. | Task 7, R1.3, R1.4, R7.1, R7.2, P36, AC33, Task 9, Task 19, Task 22 |
| 2026-09-10 | **(implementation) `kind` is a field on the table builder, not a parameter of it, and `document_sha` is declared rather than conditionally assigned.** Two small spelling choices, each closing off a plausible tidy-up. **(1)** `.datom_build_metadata()` hardcodes `kind = "table"`: a table write is the only thing that reaches it, sets have their own builder, and a parameter would advertise a flexibility no caller has -- while inviting a future caller to build a set through the table builder and get a document with `nrow` and `colnames` on it. **(2)** `.datom_build_set_metadata()` declares `document_sha = document_sha` inside its `list()` call, so the key exists even while the value is NULL, exactly as `.datom_build_metadata()` declares `parquet_sha`. The alternative spelling (`if (!is.null(x)) meta$x <- x`) looks equivalent and is not: `list(a = NULL)` keeps the name while `meta$a <- NULL` removes it, so the conditional form drops the key from the document and breaks R1.3's seven-key contract. Probed: it reddens 3 tests. Recorded in `dev/engineering-notes.md` as its own note, because the same trap applies to every "declared now, populated later" field. **This row originally added a third clause -- that the two spellings "produce identical files" because `write_json` drops a NULL element -- and it is FALSE, corrected the same day during this task's review: `jsonlite` writes `{}` for a NULL element and reads it back as an empty list. The shipped code is unaffected (no set is written yet, and `parquet_sha` escapes by the removal accident above), but a declared field must be populated or explicitly removed before a write, which is now Task 9's obligation.** | Task 7, R1.3, R7.2, Task 9 |
| 2026-09-10 | **(implementation) one probe was discarded for being imprecise, which is worth a row because the probe technique can mislead.** Deleting `kind` from **both** classification lists reddens 12 tests -- but through the write door's vocabulary check, which refuses a write on any top-level field it cannot classify, not through identity. That is the wrong mechanism for the claim being tested. The precise probe is to **move** the field from the identity list to the excluded one, which keeps it classified and reddens 3 assertions: the dedicated one plus both goldens. Both mechanisms are real and complementary, and a probe that trips the wrong one reads as confirmation while proving nothing about the guard under test. | Task 7, Task 21 |
| 2026-09-10 | **(implementation) a rebuilt SET row is still incomplete, and the gap is stated at the site rather than left to memory.** `.datom_rebuild_manifest_entry()` now recovers `kind` from the metadata document, so a rebuilt set is at least counted as a set. It does **not** recover `member_count`, because that number lives in the payload rather than in `metadata.json` or `version_history.json` -- the two documents the rebuild reads. Left to Task 9, which owns the set row's shape, and recorded in the function's own docs plus the pathways card. Nothing writes a set row today, so there is no shape to match against and no test that can fail; the pinning test that compares a rebuilt row against a written one covers tables only. | Task 7, Task 9, Task 22 |
| 2026-09-10 | **OWNER-DECIDED, on Task 8's cold-start audit: the self-reference refusal moves from Task 8 to Task 9.** Task 8's body had `datom_member()` refusing a set that lists itself, and three things say it cannot: AC9 says "refused **at write time**", R4.5 says "cheap check **at write time**", and R10.3a makes `name == project.yaml$set` the precondition, "the set's own identity before the write". Verified that no `set:` or `mode:` field is read or written anywhere in `R/` today -- the developer conn reads `project_name` and the `storage` block, `datom_init_repo()` writes nine keys, neither field among them -- so at Task 8 there is nothing to compare against. **And the constructor could not be trusted with it even later**: its `conn` is scoped to the **member's** project, exactly as `datom_parent()`'s is, so on a cross-project member it would read a different repo's `set:` field. Task 8 keeps the half that delivers the guarantee people confuse this check with: reading the member's snapshot, which is what makes the member graph acyclic by construction (R4.4). Task 9's body and criteria line now own R4.5 + AC9, and Task 8's bullet is struck rather than deleted. | Task 8, Task 9, R4.5, AC9, R10.3a |
| 2026-09-10 | **OWNER-DECIDED, same audit: an empty tag value is TIDIED AWAY, not refused -- and the spec said both.** R2.10 said "an empty tag value is **refused by validation**"; R2.14's tidy table said `domain = character(0)` has its **key dropped** silently. Both were live instructions for the same spelling. The later owner decision wins (tidy first, then validate, 2026-08-17: handle the trivial spellings silently, refuse only what needs intent guessed), so `datom_member()` drops the key. It mattered at Task 8 specifically because that constructor validates **at construction**, so a session following R2.10 would abort on a spelling the write path quietly accepts -- two behaviours for one payload depending on which door the caller entered. **Four copies corrected, two of them outside the spec**: R2.10's sentence; design.md 7.2, which additionally lumped the **exact-duplicate member** in with the refusals when it is tidied too; the roxygen of `.datom_sv1_as_strings()` in `R/hashable-set.R`, which leant on "validation refuses an empty tag value upstream"; and the matching bullet in `dev/engineering-notes.md`. The encoder's own behaviour is unchanged and still must not depend on the upstream rule -- `strset(character(0))` stays pinned at `h(0x02)` (R2.17). One thing a later reader must not "simplify": the key cannot merely be passed through untouched, because a present key with an empty value hashes as `h(0x03 || str(k) || h(0x02))` while an absent key hashes as `h(0x03)`, so the same fact would mint two different `data_sha`. | Task 8, R2.10, R2.14, R2.17, design.md 7.2, `R/hashable-set.R` |
| 2026-09-11 | **TASK 8 IMPLEMENTED: a member of a set is constructible as pure data.** `datom_member()` resolves one artifact version through one project connection and returns `{id: {project, name, kind, version}}` plus optional per-member tags -- no `data_sha`, because the version already pins the content and a second copy is a second thing to keep consistent. Reading the version's snapshot is the whole of the acyclicity guarantee: a member can only point at something that already exists. Alongside it, `.datom_validate_members()` is the checker Task 9 runs, and `.datom_validate_tag_map()` / `.datom_drop_empty_tags()` hold the tag rules in one place so the write reuses them for set-level tags rather than growing a third copy. All of it is the new `R/member.R`, plus `.datom_artifact_kinds` in `R/utils-validate.R`. **Six probes, each reverted, each naming what it reddened**; the two that would otherwise have shipped green are the tags-key omission (5 assertions across 3 tests, both byte-level ones among them) and the missing-value refusal (3). Tests 3077 -> **3218** (+141), FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9; `R CMD check` 0/0/0 on docs and code/documentation agreement. No pathway impact -- the same version-pinned snapshot read `datom_parent()` already performs. | Task 8, R4, R2.11, R12.1, I9, I10, I10a, I24, AC27 |
| 2026-09-11 | **(implementation) an untagged member OMITS the tags key, and no hash can tell.** An absent tag map and an empty one both encode as `h(0x03)`, so no golden moves and nothing in the identity suite reddens -- while `jsonlite` writes a NULL element as `{}` rather than dropping it, which would put the one spelling a writer must never emit into every untagged member of the stored payload. The trap is narrower than it looks and that is what makes it dangerous: `member$tags <- NULL` is safe (assignment removes the element) while `list(id = ..., tags = tags)` is not (the constructor keeps the name). Same jsonlite fact as Task 7's `document_sha`, with the correct answer **inverted** -- there the field had to be declared, here it has to be omitted. Guarded by an assertion on the emitted bytes, with a companion test pinning the two hashes as equal so the next reader does not try to catch it through identity. | Task 8, Task 7, R2.7, R2.10 |
| 2026-09-11 | **(implementation) the member field test is deliberately STRICTER than `.datom_validate_parents()`, and a test pins the model as looser.** That validator's per-field check is `is.character(val) && length(val) == 1L && nzchar(val)`, and `NA_character_` passes all three -- so a verbatim mirror would have accepted a missing value in a member's `id`, which AC27(b) refuses and which would be spliced into a storage key or written into a citable payload. `.datom_is_text_scalar()` adds the missing-value clause. The looseness in the parents validator is pre-existing and out of scope, so rather than assert it as prose there is now a test that calls it with `data_sha = NA_character_` and records that it returns TRUE -- so the divergence is evidence, and a later tightening of the older validator fails there rather than leaving this note quietly wrong. | Task 8, AC27 |
| 2026-09-11 | **(implementation) a `NULL` tag value is TIDIED AWAY, like `character(0)`, and the encoder still refuses one.** R2.14's tidy table names `character(0)` only. `list(domain = f())` where `f()` returned nothing is the same nothing, arrived at the way a script arrives at it, and dropping one spelling of no-labels while refusing the other is exactly the inconsistency the tidy-then-validate decision exists to remove. The encoder's refusal of a parsed `null` stands and must: there the value came out of a file, so there is no caller intent to tidy toward, and R2.7's "absence is omission" is a statement about stored documents. | Task 8, R2.7, R2.14 |
| 2026-09-11 | **(implementation) the tag grammar delegates per-value type checking to the ENCODER's coercion rather than restating it.** `.datom_validate_tag_map()` calls `.datom_sv1_as_strings()` per value, which already refuses a number, a logical, a factor, a function, a nested object, and every form of missing value, each with a message naming the key path and the allowed types. Two copies of "what counts as text here" would eventually disagree, and the encoder's copy is the one the goldens freeze. What the validator adds on top is exactly what the cold-start audit predicted: the **empty-label** refusal (there is no `nzchar()` check anywhere in the encoder, so `""` hashes as an ordinary label), the four-key `id` shape, and `kind` being one of exactly two values. Not a breach of "the encoder does not validate" -- the borrowing runs the other way, and validation still runs first so its messages arrive first. | Task 8, R2.11, AC27 |
| 2026-09-11 | **(implementation) canonical form is NOT computed at construction, deliberately.** `datom_member()` drops an empty-valued key and validates what remains; it does not sort keys, sort or deduplicate values, unbox a single value, or order members. Those are R2.15's, they belong to the set write, and having one implementation of canonical form is worth more than showing a caller the tidy spelling one step earlier. A test pins that an out-of-order duplicated tag value survives the constructor untouched, so the boundary is asserted rather than assumed. Related: a **named character vector** (`c(type = "output")`) is refused rather than coerced to a list -- it cannot express a multi-valued tag, so accepting it would add an unrequested tidy rule that Task 9's canonicalizer would also have to know about. | Task 8, Task 9, R2.15 |
| 2026-09-11 | **(implementation) a snapshot declaring a kind this build does not know is refused, and the message says to upgrade.** `kind` absent means a snapshot written before the field existed, and every one of those describes a table, so the fallback is sound. A snapshot declaring something else -- a third kind from a newer datom -- is a different case: passing it through would put a pointer nothing can classify into a citable payload, and a reader meeting it would not know whether to resolve it as a table or as a set. `.datom_artifact_kinds` (`R/utils-validate.R:17`) is the vocabulary, **append-only** for the same reason the write-side field lists are: a build that stopped recognising a kind would refuse an older document and block the upgrade direction. | Task 8, Task 10, R22.8, I31 |
| 2026-09-11 | **REVERSED the same day by review: BOTH version-pinned snapshot readers now check the format they are handed.** Task 8 shipped `datom_member()` with no `.datom_check_schema_version()` on the snapshot it reads, on the audit's stated default of mirroring `datom_parent()`. The default asked whether the two siblings should agree and stopped one question short of what the absent check was holding up: **the `kind` fallback**. An absent `kind` is read as `"table"` -- right for a document written before the field existed, wrong for one written by a build this version cannot fully parse, where a **set** is recorded as a table. That misreading is durable, not momentary: it enters the member record, the stored payload, and the set's own `data_sha`, so a citation names the wrong kind of artifact permanently and nothing fails. **The codebase had already settled the pattern and the audit missed it**: `.datom_rebuild_manifest_entry()` checks the per-artifact document (`R/manifest-rebuild.R:196`) and then applies the identical fallback (`:210`) -- so of three sites deriving `kind` from such a document, one checked and two did not, which makes the two the anomaly rather than the check the innovation. `datom_parent()` was gated in the same commit: its two fields are durable at one remove (`data_sha` becomes a storage address, `source_lineage` is unioned into the lineage of whatever table declares the parent), and leaving one sibling ungated is precisely what turned a gap into a precedent. **Verified rather than assumed** before agreeing: the snapshot is written from the same object as `metadata.json` (`.datom_push_metadata_s3()` writes one object to three keys), so it carries the format number and the check is live rather than theatre; and `datom_read(version = )` does **not** read the snapshot at all -- it resolves from `version_history.json` -- so the gap really was exactly two functions. Both checks sit **outside** the not-found handler, or the refusal is reworded as "member not found" (the Task 4 lesson). **The behaviour change is accepted, not incidental**: a snapshot declaring a newer format now aborts where it previously half-worked. Licensed by the owner's standing position, stated the same day -- the released versions are experimental and unannounced, and support for them must not buy fragility for what comes next -- and by the posture already in `.github/copilot-instructions.md`: breaking loudly is acceptable here, degrading silently is not. Tests 3218 -> **3227** (+9). | Task 8, Task 22, Task 4, R9.2, I4, `R/lineage.R` |
| 2026-09-11 | **The `kind` fallback STAYS, and the reason is a use case rather than back-compatibility sentiment.** With the format check in place, the obvious next move -- drop the fallback and require `kind` -- was considered and rejected. Every version written before Task 7 has a snapshot with no `kind`, and requiring the field would make those versions **uncitable**: a set could name only versions written by this release onward. R2.14a wants exactly the opposite, since its worked example is a current table sitting beside a **locked baseline**, and a baseline is by definition an older pinned version. So the fallback is not the past being carried at the future's expense; it is what makes historical versions citable at all, and the format check is what makes it safe by construction rather than by convention. Recorded because the owner's standing position on not supporting released versions would otherwise point at removing it. | Task 8, R2.14a, R22.8 |
| 2026-09-11 | **COLD-START AUDIT FOR TASK 9: startable, nine findings, two of them OPEN scope questions with stated defaults. No escalation flag** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. Full detail in Task 9's body; the two that would have cost real time are recorded here because they change how the task is sequenced rather than how it is written. **(1) THE TWO GATES READ `project.yaml` FIELDS NOTHING WRITES UNTIL TASK 11, WHICH RUNS AFTER THIS TASK.** Verified by grepping every `yaml::write_yaml()` site -- there are two, and neither writes `mode` or `set`; nothing reads them either. So `datom_write_set()` lands **unreachable through the public path**: no repo can declare `mode: product`, so every set write is refused at its own door, and Task 10's read inherits the same. Same deliberate inertness Task 4's gate had, and the fix is **not** to pull Task 11's init half forward: Task 11 is blocked on Task 23 because writing `mode` needs a released build that already reads `project.yaml`'s format number, so moving it up drags Task 23 with it. Default: keep the order, fixtures hand-write the file, and the task states the inertness. Second half of the same item: `mode` and `set` do **not** ride on the conn the way `min_writer_version` does, so Task 9 chooses between reading the file at the gate and adding two conn fields, and Task 11 inherits the choice. **(2) "REUSE `datom_write()`'S STEPS 7-10" IS NOT A CALL** -- those steps are inline comments in one function body (`R/read_write.R:841-950`), so the task either extracts the commit-push-then-upload sequence or writes a second copy of "git must succeed before storage is touched", which is a second place for I5 to break. Largest scoping decision in the task, currently phrased as free. Default: extract, and say in the commit that the table path was touched. **Also found:** a fourth write verb inherits nothing from the three existing `.datom_check_write_entry()` sites and must call it itself -- the route-was-the-gap finding for the fourth task running; the **healthy** writer has the same set-row defect the task attributes to the rebuild alone, because `.datom_update_manifest_entry()` reads `size_bytes` off the metadata document and defaults it to `0` while a set has no such field; `.datom_update_manifest_entry()` still hardcodes `kind = "table"`, a line handed forward three times now; and the `.datom_lookup_history_parquet_sha()` citation named the **wrong function** -- the pattern wanted is `.datom_resolve_parquet_sha()`, and the gate could not see it because the cited lines are real prose. **Two claims verified rather than trusted, both holding**: `.datom_has_changes()` genuinely works unchanged for a set (it keys off the document's existence, recomputes identity through the allowlist, and compares `data_sha`, and Task 7 classified the set builder's fields), and the rebuilt-set-row analysis is exactly right. | Task 9, Task 10, Task 11, Task 21, Task 23, R10.3a, I5, I34 |
| 2026-09-11 | **Both of Task 9's scope questions APPROVED at their stated defaults -- explicitly, not on silence, so they are decisions and a fresh session must not reopen them.** (1) **The execution order stands and the set write lands inert**: `datom_write_set()` will be unreachable through the public path until Task 11 writes `mode: product`, its fixtures hand-write `project.yaml`, and the task says so the way Task 4 said it -- rather than pulling Task 11's init half forward, which would drag Task 23 up with it. The gates **read `project.yaml` directly** rather than carrying `mode` and `set` on the conn; recorded here so Task 11 inherits the choice, and if it later wants them on the conn that is a move with one caller to update rather than a question reopened. (2) **The commit-push-then-upload sequence gets extracted** out of `datom_write()`'s body so both write verbs share one copy, with the commit message stating that the table write path was touched -- the alternative being a second place for I5 ("git must succeed before storage is touched") to break independently. | Task 9, Task 11, Task 23, I5 |
| 2026-09-14 | **TASK 10 IMPLEMENTED: a set is readable end to end.** `datom_get_set(conn, name, version = NULL)` returns a `datom_set` of `name`, `project`, `version`, `data_sha`, `tags`, `members` -- references and labels, no data -- with `version` read from the history rather than recomputed. The payload is downloaded, hashed against the recorded `document_sha`, and only then parsed with `simplifyVector = FALSE`; a version recording no `document_sha` aborts rather than skipping the check. Reading one kind with the other verb aborts in both directions from one function and one condition class (`.datom_check_artifact_kind()` gained an `operation` word, defaulting to `"write"` so no existing message moved). Every member carries `$fetch(conn)`, a `datom_link` closure built by a namespace-level factory. Tests 3418 -> **3553** (+135). | Task 10, R12.3, R7.1, R7.2, R4.3, I3, I8, I10, AC1, AC6, AC14, AC15, AC28 |
| 2026-09-14 | **(implementation) `.datom_resolve_version()` took a `field` ARGUMENT and NO wrapper per kind, which departs from the precedent it was told to follow.** Task 9's history scan got one function plus `.datom_lookup_history_parquet_sha()` / `_document_sha()`, and Task 10's audit named that as the pattern. Here the wrappers would have held a constant string and nothing else -- Task 9's each hold a documented difference about what an absent value means -- so the call sites pass `field = "parquet_sha"` / `field = "document_sha"` directly and the function's own docs carry the per-kind meaning. The return value is now `list(data_sha, object_sha, version)`: the stored-object hash comes back under one name rather than under the name of the field asked for, because a slot whose name varies with an argument reads as clever at the call site and as a mystery in the docs. Four existing assertions in `test-read-write.R` were renamed accordingly; no behaviour changed for a table read. | Task 10, Task 9 |
| 2026-09-14 | **(implementation) the read normalizes REPRESENTATION and nothing else, and the tidy functions sitting next to it are the trap.** `.datom_tidy_set_payload()` run on a healthy payload changes nothing, because the write canonicalized -- so a tidying read passes every test built on a written fixture and diverges only later, as a repair that re-emits reshaped bytes over an object whose recorded hash describes different bytes (R7.5 rule 2, Task 14's failure caused here). The never-tidy tests therefore hand-write payloads that are deliberately uncanonical -- keys out of order, values out of order, a duplicated label, a key pointing at nothing -- and a helper re-pins `document_sha` to those bytes so the integrity gate passes and the test observes the behaviour it is actually about. The one allowed normalization is `.datom_read_string_array()`: an all-text JSON array becomes a character vector with the same strings in the same order and the same count, because `auto_unbox = TRUE` on the write means one tag key comes back in three R shapes. The presence axis is never touched -- absent stays absent, `NULL` stays `NULL`, and nothing becomes `character(0)` or `NA`. | Task 10, Task 14, R2.12, R7.5 |
| 2026-09-14 | **(implementation) an `id` value is REFUSED on read where a tag value is tolerated.** `.datom_validate_members()` enforces the text-scalar contract on **write only**, so a payload read back from storage is checked nowhere else -- and `id` values are spliced into storage keys and compared against project names, so a list where a string belongs would make Task 24's project comparison report a member of this project as belonging to another. A tag value this build does not recognise as text is left alone instead: nothing downstream requires it to be text, so refusing would block a document a newer datom wrote. Fields **outside** the four `id` keys are carried untouched for the same reason, and a test writes one. | Task 10, Task 24, R2.5 |
| 2026-09-14 | **(implementation) the member link's purity is pinned on serialized BYTES, and the probe that proves the pin needed `conn` forced.** With the factory nested inside `datom_get_set()` the connection lands on the closure's parent chain and `saveRDS()` writes the PAT into the file -- but a first probe found no token, because the nested factory's enclosing frame held `conn` as an unforced promise pointing at the global environment, which serializes as a reference. Forcing it reproduced the leak exactly. So two things are load-bearing rather than one: the factory is namespace-level **and** every argument is `force()`d. Two further notes for whoever edits that test: a dev-loaded package keeps source references, so the serialized closure carries the text of `R/set.R` -- which mentions `github_pat` in an example -- hence the search is for a token **value** the fixture invents and no source file contains; and `rawToChar()` refuses the embedded NULs in serialized R objects, so the search is `grepRaw()`. | Task 10, design.md 23 |
| 2026-09-14 | **(process) a probe harness must restore from a copy it made itself, never from git.** A harness that reverted its deliberate defects with `git checkout -- R/set.R R/read_write.R` deleted the whole of Task 10's uncommitted implementation, since HEAD predates it. Recovered from the session transcript and the already-generated `man/` pages, verified identical by line count and by a green suite. The class of the mistake is what matters: the code under probe is **by definition** uncommitted, so git is the one thing that cannot be the restore source. In `dev/engineering-notes.md`. | Task 10 |
| 2026-09-14 | **REVIEW FINDING ON TASK 10, half accepted and half refused on evidence: the link carried a dead `project` argument, and a project check must NOT be added to it.** The observation was right and is fixed: `.datom_member_link()` took `project` as its first argument, forced it, and referenced it nowhere -- reaching the record only through `record` -- while Task 10's body claimed the link performed "kind dispatch, **the project check** and version pinning". A forced-and-unused argument reads as a check that was meant to be there, so the argument is gone (four parameters now) and the sentence is corrected. **The recommended fix -- move the comparison into the factory -- was refused, and the reason was verified rather than argued**: for a **reader** connection, which this task documents as the primary consumer of a set, `project_name` is a label passed to `datom_get_conn()`. The namespace comes from the store's root and prefix, nothing validates the label against the repo, and a reader is never told which string the writer used. Reproduced end to end: a reader labelled `"a-label-nobody-validated"` reads a set written by project `set-project` and fetches its members correctly, and a gate in the link would have aborted that. So the mismatch is the ordinary case, not the error case. Two tests now pin the no-gate behaviour, so adding the gate reddens rather than passing. Task 24's own bullet is rewritten: the project comparison is a **hint on an already-failed resolution**, and it belongs in the shared link core rather than in `datom_fetch_member()` alone -- because after `datom_structure_members()` a leaf is a link, so the projection path never enters that verb, which is the strongest part of the review and is preserved. | Task 10, Task 24, R3.3, R18.1 |
| 2026-09-14 | **(surfaced, NOT fixed -- owner decision needed) a connection's `project_name` is unverified, and three things quietly depend on it being true.** Found while refusing the review's project check, and **corrected 2026-09-14 after a second review round showed the first wording understated it**. Nothing compares a connection's `project_name` against the repo it reads, and what a wrong one does depends on the store shape -- three cases, read out of `.datom_resolve_data_location()` (`R/ref.R`): with **no governance** it returns before the name is even validated, so the name is a pure label and a wrong one is silent; with **governance plus a located store** an unresolvable ref warns "Proceeding with store-configured data location" and the connection succeeds; with **governance plus a credentials-only store** there is no fallback location and it aborts. And one case worse than any of those, which the second round did not name either: a wrong name that **matches another registered project** resolves that project's `ref.json`, and when the two locations differ the reader's connection is repointed at the other project's namespace with only a "Data has been migrated" warning -- so a typo reads a different project's data while the warning blames a migration. Read-verified in `R/ref.R` and `R/conn.R:1159-1163`, not reproduced on a fixture. Consequences, in increasing order of cost: (1) `datom_get_set()` reports `project` from the connection, so a mislabelled reader gets a set whose `project` field is their own label -- documented in the roxygen and pinned by a test, since it is one of the four facts the result advertises **for citation**; (2) `datom_member()` records `project = conn$project_name` at declaration time, so a member declared through a mislabelled connection writes a wrong project name into a **citable payload** permanently, and no hash or validator can see it (pre-existing, Task 8); (3) no project comparison anywhere can be a refusal until this is settled. **The candidate fix is to verify a reader's `project_name` against the repo at connection time** -- the manifest's top-level `project_name` is the only recorded copy -- which would make all three truthful at once. It is a behaviour change for existing readers (a wrong label reads today and would abort after), it is outside this spec's scope, and it wants filing as its own issue rather than folding in here. | Task 8, Task 10, Task 24, R18.1 |
| 2026-09-14 | **CLOSED, not left open: a project name is NOT part of version identity.** Raised as an owner call while analysing the unverified-`project_name` problem, and closing it is right because it is a one-way door with a fleet-wide re-mint behind it. Identical bytes in two projects **should** share a version -- that is what content addressing is for, and a wrong-connection fetch that returns identical bytes returned the **right** bytes. The defect being fixed is a wrong **citation**, not a wrong identity, and a citation is fixed by recording the name, never by hashing it. So when `project` is added to a metadata document it goes on the documented **excluded** list, in the same change that starts writing it -- never earlier, or it becomes a classified-but-unwritten name and loses the carry-forward protection that rescues only names a build cannot place (the trap Task 7's `document_sha` review found). Recorded here rather than in the future issue, because the issue can then state it as settled instead of reopening it. | Task 7, Task 19, R9.4 |
| 2026-09-14 | **The cheap moment to add `project` to per-artifact metadata is THIS release, and after it the same change costs a second forced upgrade.** Owner's scope note, 2026-09-14: nothing on this branch is merged, let alone released, so no repo in the wild is affected by anything here. What an added field costs is a **writer** upgrade for everyone sharing a repo -- an older build recomputes identity around a field it does not know (releases before this spec hash by exclusion) or refuses outright (after it, Task 21's vocabulary check). **This release already forces exactly that upgrade**, because the artifact-namespace rename does. So the marginal cost of one more field inside this release is zero, and the marginal cost of the same field in the release after it is a fresh fleet-wide upgrade for a citation fix. **Task 21 is the constraint, not the vehicle** -- it is done, and its vocabulary check is *why* a late addition costs what it costs; nothing currently schedules the field. Not scheduled by this row either: whether it becomes a task here or an issue for later is the owner's call, but the window is what the decision turns on rather than the size of the change. | Task 6, Task 7, Task 21, R9.1, R9.4 |
| 2026-09-14 | **The name cascade is ASYMMETRIC between the two callers, and the reason is what the value is used for.** `datom_member()` writes `id$project` into a stored payload, where it is hashed into the set's `data_sha` and cited afterwards, so it is worth an extra read to get right: recorded field on the artifact's own document, then the namespace manifest's `project_name`, then the connection's label **marked unverified**. `datom_get_set()`'s `$project` is an echo of the connection for display and citation, so its cascade stops at the recorded field and the connection label. It must **not** read the manifest: the data path never touches that document -- which is the reason the artifact-namespace rename was a discovery-only break, since a stale build still reads data -- and a manifest read there would put a derived, rebuildable, possibly too-new document in a read path that today cannot fail for its sake. A test in `test-get-set.R` pins the set read at two documents, so the boundary reddens rather than drifting. | Task 8, Task 10, Task 24 |
| 2026-09-15 | **(implementation, Task 26) The `{}` hazard lives in the `list()`, not in the missing `if`.** Both audit-era claims about how the new field is written turned out to be wrong, and the probes are what said so. Assigning `NULL` to a list element **removes** it, so `meta$project <- project` outside the builder's `list()` is already safe -- dropping the guard reddens nothing. The spelling that reaches disk as an empty object is `project = project` **inside** `list()`, which is where `document_sha` deliberately sits and why that field has a must-populate rule attached. And "last in the signature or a dozen positional callers shift" does not hold: every caller passes `data` and `data_sha` positionally and everything else by name, so moving the argument reddens nothing either. Last is a convention, and the roxygen now says that instead of claiming a guard. | Task 26 DONE record, `R/read_write.R` |
| 2026-09-15 | **(implementation, Task 26) The unverified-name warning is suppressed for a connection built from a clone**, because there `project_name` is read out of `.datom/project.yaml` and calling it unverified would be a wrong statement. Only a reader connection reaches the warning. The condition is exactly the one that makes the label repo-sourced: developer role plus a non-NULL clone path. | `.datom_declared_project()`, `R/member.R` |
| 2026-09-15 | **(Task 26) The gov-plus-wrong-name repointing hazard REPRODUCES, and this release does not fix it.** Built as a fixture rather than argued from the code: a reader who means project A, holds A's location in their store, and types B's name gets **B's rows**, because with governance attached the name selects which `ref.json` is read and the connection is repointed at B's namespace -- reported as a data *migration*, which is what a real migration says. The same mistyped name with no governance store reads A correctly. Kept in `test-ref.R` as a characterization test, labelled as one: recording the writer's project name fixes what goes **into** a document, and this is a wrong name steering a **connection**. **Deliberately unfiled, and not a datom defect** (owner decision, 2026-09-15). The hazard needs governance attached, so it cannot fire until `datomanager` exists -- nothing in datom writes `projects/{name}/ref.json` any more, since `.datom_create_ref()` has no caller left in the package. The candidate fix, verifying a reader's name against the namespace's manifest at connection time, would change behaviour for existing readers in order to defend against a component that is not built. Recorded instead as a **constraint on the resolver** in `dev/datomanager_overview.md` section 4a, directly beneath the section that states the enabling rule in its own words, because whoever builds that resolver reads that section and would never find an issue filed against datom. The hard edge is `datomanager`'s attach. **Do not file this as a datom issue.** | Task 26 DONE record, `dev/datomanager_overview.md` 4a, `tests/testthat/test-ref.R` |
| 2026-09-15 | **TRIAGE RULE FOR OLD-BUILD COMPATIBILITY, generalised from how this spec has actually been scheduling.** Two classes, two answers. **Irretrofittable mechanisms** -- where a build that does not look can never be made to look (the reader-side format gate, the vocabulary check, the writer floor's reading half, a format number on `project.yaml`) -- are built **now**, even speculatively, because the window closes at release and cannot be reopened. **Behaviour inside those mechanisms** -- a slow path, a bad message, an awkward coupling -- is fixed **when it bites**, because fixing it later asks nothing of old builds. The governing asymmetry: *corruption caused by an old build is never acceptable; graceful **function** of an old build is not a supported guarantee.* 0.1.0-0.1.2 is a closed, unannounced, experimental population that the v2 manifest bump already stops from writing, so a degradation confined to it is recorded rather than fixed. **This is also the rule that says which of the two 2026-09-15 findings below got fixed and which did not**: the decisions-log wording was fixed (it would have misdirected a future session), the manifest-reader coupling was recorded. | design.md 11, and the two rows below |
| 2026-09-15 | **(review finding, WITHDRAWN by the reviewer, kept because the reasoning is the useful part) the name cascade's manifest step goes through the repairing reader, and on a too-new manifest that costs a full index reconstruction.** `.datom_declared_project()` reads the manifest via `.datom_read_manifest(conn, scope = "storage", operation = "read")`, whose read path carries the reader-side rebuild: one namespace listing plus two reads per artifact. So a lookup of one field can cost 2N+1 requests. **Withdrawn on two counts, both verified rather than argued.** The answer is still **correct** -- the rebuild carries `prior$project_name` forward, and that name is on an append-only vocabulary, so a too-new manifest still supplies it; the path is expensive, not wrong. And reaching it needs a three-way straddle: an artifact written before the project name was recorded, in a namespace some *future* release has since touched, read by this build. Nothing written, nothing silent, no corruption -- so by the triage rule above it is recorded and not fixed. | `.datom_declared_project()`, `R/member.R` |
| 2026-09-15 | **REJECTED, with the reason recorded so it does not come back: the manifest step must NOT be changed to read the document directly instead of through the gated reader.** Offered as an optional tidy alongside the withdrawn row above -- *a lookup that wants one field should read the document, not the reader that repairs it* -- and it is a good aphorism that happens to invert this spec's own gate discipline. A raw `.datom_storage_read_json()` on `.metadata/manifest.json` takes a value out of a document whose format **this build has never checked**, which is the precise thing the format gate exists to prevent: in a future shape where `project_name` moved or changed meaning, the raw read returns a wrong value silently, and the value in question then gets hashed into a set's identity and cited. This was the audit's open question 4 and was settled at its stated default (the gated reader, accepting the listing in the degraded case) for exactly this reason; the tidy would reopen it and trade a loud expensive path for a quiet wrong one. | Task 26 audit question 4, `.datom_declared_project()` |
| 2026-09-15 | **Both of Task 24's scope questions APPROVED at their stated defaults**, explicitly rather than by silence, so they are decisions and a later session does not reopen them. **(1) The member-fetch verb accepts a member with no `fetch` attached** -- the plain-data shape `datom_member()` returns and `.datom_strip_member_links()` produces -- because the accessor keys on `id` and nothing else, so it costs a line and keeps the read and write verbs agreeing about what a member is. Saying no would make one verb's idea of a member narrower than the other's. **(2) `datom_list_members()` does NOT repeat the set's own name and version on every row.** It would make two products' listings self-describing when `rbind()`ed, which is a real use, but the set's identity is already on the object the caller passed and two columns repeating one fact per row is the denormalisation that later disagrees with itself. A caller who wants it writes `transform(m, set = x$name)`. | Task 24 audit, findings 8 and 9 |
| 2026-09-15 | **(implementation, Task 24) The grouped view's leaf is the MEMBER'S NAME, not the tag value, so the tree is `length(by) + 1` levels deep.** The task's prose ("group members by the values of the tag key(s) named in `by`, with each leaf the member's link") reads as a tree whose deepest name is a tag value -- and that tree collides the moment two members share one label, which is not the collision the same task specifies. The `dp$output$adsl` example settles it: axis values are branches, the member's own name is the leaf. Recorded rather than fixed silently, because it is the difference between the specified collision being reachable and being unreachable. | Task 24 DONE record |
| 2026-09-15 | **(implementation, Task 24) A `missing` bucket name colliding with a real tag value is refused UNCONDITIONALLY, not only when a member currently lacks the axis key.** The conditional version works today and starts failing the day a member without that key is added -- silently at authoring time, which is exactly the failure direction the version-suffixed leaf name was rejected for. Two tests, one per half. | Task 24 DONE record, `R/set-members.R` |
| 2026-09-15 | **(implementation, Task 24) `tags` / `version` supplied beside a member RECORD or LINK is refused, not ignored.** Not in the task body. Ignoring the filter would resolve a different version than the one asked for and report success, which is a correctness-shaped silence rather than a convenience. | `R/set-members.R` |
| 2026-09-15 | **(implementation, Task 24) The member-resolution check must NOT reuse `.datom_validate_members()`.** That is the write-side contract and it refuses an `id` field a newer datom added -- which the set read deliberately carries. Reusing it would make such a member readable but unfetchable, which is a reads-limp violation arriving by a side door. A focused check on the four fields resolution actually needs replaces it. | `R/set-members.R`, `.datom_member_id()` |
| 2026-09-15 | **(review finding, ACCEPTED and fixed, Task 24) A tag map is read BY POSITION, never by name, and item 1 of Task 24's must-not-undo list says so now.** A map can carry the same key twice -- a reader validates no tag map (Task 10), and `jsonlite` parses duplicate JSON keys into two same-named elements rather than collapsing them, verified rather than assumed -- and `tags[["type"]]` returns the first match every time. So all three verbs lost every label after the first: the listing showed one value twice, the grouped view put the member under one branch instead of two, and a filter reported **not found** on a label the document says the member carries, which reads as missing data. The reviewer's framing is the durable part: this is the one-expander rule's own hazard on the **key** axis, written inside the function that exists so the value-axis version has nowhere to live. Fixed by `seq_along()` plus `names(tags)[[i]]`, and by routing `.datom_member_has_tags()` through the expander so a member's tag values have one access path. Probed: the by-name read reddens 5 assertions across 4 tests. | Task 24 DONE record, `R/set-members.R` |
| 2026-09-16 | **(review finding, ACCEPTED and fixed, Task 25) A draft's member count must equal the count the write produces, so an exact repeat is skipped as it is added and a same-version label disagreement aborts there.** Two write-side mechanisms did not know about the draft: `.datom_order_set_members()` drops an exact repeat silently (its digest covers tags), and `.datom_check_set_payload()` refuses the same `id` with different tags -- naming the member but not which of forty lines introduced it. So a pipe with an accidental repeat printed 40 and wrote 39, and a label disagreement surfaced after every line had run, which is the one thing this path exists to prevent. The exact repeat is **skipped with a message, not refused**: refusing would make a draft stricter than the equivalent list, so `Reduce(datom_add_member, records, init = draft)` over a generated list that repeats would fail where it works today; skipping in silence would move the surprise rather than remove it. Deliberately **not** extended to self-reference -- a draft's name may be `NULL` until `project.yaml` resolves it at the write, so a draft cannot know whether a member is itself. | Task 25 DONE record, `R/set-draft.R` |
| 2026-09-16 | **(implementation, Task 25) Comparing member DIGESTS rather than records is what makes the duplicate check agree with the write, and no tidying is needed first.** The first fix tidied each record on the way in, on the theory that `domain = c("a", "b")` and `c("b", "a")` would otherwise read as a conflict. Probing removed that tidy and reddened **nothing**: `.datom_sv1_map()` sorts a map's keys and `.datom_sv1_strset()` encodes each value as a sorted, deduplicated set, so the digest is already blind to every spelling the write's tidy step collapses. The tidy was changing what a caller reads back out of a draft while buying nothing, and it is gone. Swapping the digest comparison for `identical()` on the two records reddens exactly the reordered-labels test, which is the guard. | `R/set-draft.R`, `.datom_draft_member_clash()` |
| 2026-09-16 | **(owner decision, Task 23) `project.yaml` carries ITS OWN format number (`.datom_project_schema`, `1L` today), not the shared `.datom_supported_schema` every other document is stamped with.** Decided against the cold-start audit's stated default, because the price the audit put on a per-file number -- "a second constant kept in step by hand" -- does not exist: a per-file number moves *independently*, staying `1L` through every manifest or metadata bump. What the shared constant would have cost is a false refusal, and an expensive one: the check sits in connection construction (`R/conn.R:1070`), so it takes the whole **developer** path including reads that would have worked, and the reader escape hatch does not help the developer, who is the one stuck and whose recovery is hand-editing the file. **One mechanism argued for that cost does not exist**, checked rather than accepted: `datom_repo_set_data_store()` (`R/repo.R:90`) is a read-modify-write that carries `schema_version` forward untouched, so it does not raise the number -- only `datom_init_repo()` stamps, which makes the shared constant's blast radius "repos initialised by the newer build" rather than every store-pointer update. Narrower than argued; the decision stands on the asymmetry, since a per-file number has no false refusals at all. | Task 23 finding 1 |
| 2026-09-16 | **(owner decision, Task 23) The per-file number's one hole -- a forgotten bump -- is closed by a key-set tripwire test, and that test forces a DECISION rather than mandating a bump.** A shape change shipping with an unmoved number is silently misread by an older build, and nothing in the suite asserts `project.yaml`'s key set today. So: a test that fails when the key set changes without `.datom_project_schema` changing. The framing is load-bearing -- R9.5 is explicit that an addition does not move a number, and **Task 11 fires this test immediately** by adding `mode` and `set`, where the correct answer is to extend the expected set and leave the constant alone. Read as "key set changed, therefore bump", it would manufacture exactly the false refusal the per-file number was chosen to avoid. Same shape as Task 21's three vocabulary-list tests. | Task 23 finding 1 |
| 2026-09-16 | **(implementation, Task 23) The `supported =` argument stays OPTIONAL, and the file-to-ceiling pairing lives in a wrapper rather than at each call site.** Requiring it was considered and rejected on evidence: the checker has exactly eight call sites (`R/forward-compat.R:439`, `R/lineage.R:170`, `R/manifest-rebuild.R:228`, `R/member.R:553`, `R/read_write.R:104`, `R/sync.R:930`, `:937`, `:1137`) and every one reads a machine-written manifest or metadata snapshot, where the global ceiling is the **correct** answer rather than a convenient one -- so requiring it would repeat one constant eight times to guard against a future ninth. The trap it would have closed is real though: a later caller for another hand-edited document that forgets the argument gets the global ceiling silently, which is the identical dead gate. Two things close it instead. A wrapper, `.datom_check_project_schema(cfg, source, operation)`, supplies `supported = .datom_project_schema` in one place -- two callers need it on day one (connection construction and the set-write gate), and the precedent is `.datom_artifacts_of_kind()`, where one predicate written out at four sites lost a tolerance at one. And the checker's docs state the rule that predicts an override, so it is derived rather than remembered: a document **datom writes** takes the global ceiling, a document that outlives its writing build and is **hand-edited** gets its own -- because the shared number only works while every document on it is written by one build in one operation, and `project.yaml` is written once at init then edited by hand for years. | Task 23 finding 1, `R/utils-validate.R:253` |
| 2026-09-16 | **(implementation, Task 23) `.datom_check_schema_version()` gains a `supported =` argument in the SAME commit as the config gate, feeding the message as well as the comparison.** Neither the audit nor the review stated this, and without it the per-file number is a nominal gate: the checker compares against the global `.datom_supported_schema` and names it in the refusal, so the day this file's shape breaks and its own constant becomes `2L`, a build whose global ceiling is already `2L` compares `2 > 2`, proceeds, and misreads the new shape. Because the reading half **cannot be retrofitted** -- this task's whole premise -- no later release can fix the builds already installed, so it cannot be deferred. Defaulting the argument to `.datom_supported_schema` leaves every existing call site and its asserted message unchanged. | Task 23 finding 1, `R/utils-validate.R:253` |
| 2026-09-16 | **(owner decision, no task) A set may hold the SAME artifact at two versions, and that rule is KEPT** -- re-examined during a design round on a prospective member-update verb, and kept because unwinding it now costs about what the future tax saves. Two things this settles, both written into R2.14a rather than here so the next challenge meets them where the rule is: the cost tally (trivial on the identity side, roughly a third of the read-side ergonomics already spent, and a per-verb tax on every future verb that names a member -- heaviest on a *write* verb, since "refresh everything" is the operation that would collapse two members into one), and the one use case that survives scrutiny. "Reproduce the interim analysis" does **not** need a baseline member, because a set is itself versioned and citable; what survives is **freezing one input while the rest refresh**, which has no cheap alternative under one-repo-one-set. **The rule handed forward: a member-update verb SKIPS two members sharing a name and reports them**, never refuses the sweep and never guesses which is live -- only the caller's labels say that. | R2.14a |
| 2026-09-16 | **(design round, NOT YET BUILT) Three set-editing verbs are designed and deferred: remove, update, and an update report that feeds the commit message.** Deferred rather than appended as tasks because 0.1.2 is at CRAN and Tasks 23 and 11 are the critical path. The design, so it is not re-derived: `datom_remove_members()` and `datom_update_members()` are parallel -- same object, same three ways to name a member, same label and version narrowing, each returning the class it was handed -- with two divergences that follow from what the verbs do rather than from style. Remove **requires** a selection (selecting nothing would mean removing everything, which the writer refuses anyway) and needs no connection at all, because it only has to *find* a pointer already in hand. Update defaults to **all** members and takes one connection **per project**, because it has to *resolve* a pointer, which is also why `datom_add_member()` is draft-only. Three things the update verb must get right: a member's labels are carried forward rather than rebuilt (rebuilding drops them silently, and labels are content); connections are matched to members on `conn$project_name`, which is unverified, so the rebuilt member's **recorded** project is compared against the one it replaced and a mismatch refuses; and a member whose project has no supplied connection **refuses up front** naming that project, because whether it moved is unknowable -- while a member whose artifact no longer exists is **reported and left**, because the answer is known and its pinned version still reads. `datom_add_member()` stays singular on purpose: a plural add needs a parallel list of versions, which is the typo hazard Task 25 rejected it for. | `dev/README.md` Backlog |
| 2026-09-16 | **(owner decision, scope) The two set-editing verbs ship in THIS release, as Phase H (Tasks 27 and 28), rather than as a deferral.** Reversing the same-day default recorded above, which had them as a backlog row. Repointing a member at a newer version is fundamental to a product -- a hundred inputs, thirty of them moved -- and dropping one is close behind; a citable artifact that cannot be safely edited is half a surface. **The decision was made on value alone, and that is possible because these verbs are unusual here: they touch no stored document**, so no field, no format number, no vocabulary entry, and therefore no forced fleet-wide writer upgrade if they had arrived a release later. Deferring them would have been free in the one dimension that is normally expensive, which is exactly why the argument came down to worth rather than timing. **Placement is forced, not chosen**: Task 16 is the acceptance sweep and Task 17 is docs plus the Spec Completion Procedure, so anything landing after either would leave the sweep testing a surface that then grew and the docs describing one missing two exports -- hence after Task 15, before Task 16, with the `23 -> 11` critical path untouched. **Task 27 before Task 28**, even though 27 is larger: both need a plural member selector that does not exist (Task 24's finder returns exactly one member and aborts on ambiguity), the harder consumer is what shapes that selector correctly, and if the release squeezes the thing that drops is then the verb the owner called less fundamental. | Phase H, R24 |
| 2026-09-16 | **(design, Task 28) A name matching two members REFUSES on a removal but SKIPS on a repoint, and that asymmetry is deliberate.** Same evidence, opposite responses, for the same reason the reads-limp / writes-stop split exists elsewhere: skipping a **removal** silently does nothing, so the caller believes a member is gone when it is not, while skipping a **repoint** safely leaves a valid pin and says so. The removal refusal is the direct replacement for the hand-rolled `Filter()` on name, which drops every version of that name and takes a frozen baseline with it. State the asymmetry wherever either verb is documented, or a later change unifies them into whichever half it met first. | Phase H Tasks 27 and 28 |
| 2026-09-17 | **(implementation, Task 23) The set-write gate's format check runs BEFORE `mode` and `set` are read, and it is not a duplicate of the connection-time one.** Ordering first: the two checks below it report *on* those fields, so a format this build cannot read turns them into confident advice about the wrong thing -- a shape that moved `set:` makes the gate say "declares `mode: product` but names no set" and send the user to hand-edit a file that is already correct. Non-redundancy second, and it is what the test asserts: the config is edited **after** the connection was built, because a git pull or a hand edit between opening a connection and writing through it replaces the file the connection was built from -- the same reason `.datom_check_write_entry()` is re-run after a route's own pull. Deleting this call reddens the three write-side tests while every connection-time test stays green, which is what proves the second site is not decorative. | Task 23 DONE record, `R/set.R` |
| 2026-09-17 | **(implementation, Task 23) The post-migration-pull re-read is gated, and the writer-floor staleness beside it is RECORDED rather than fixed** -- finding 8's stated default, taken. `.datom_resolve_data_location()` re-reads `project.yaml` after pulling git, and that copy is the one the connection-time gate structurally cannot see, so without a check there a config arriving in a migration pull is the one config never checked. The probe starts from a readable config and has the mocked pull replace it with a too-new one, so it fails if the gate is ever moved above the pull. What stays open is `conn$min_writer_version`, assigned from the **pre**-pull parse: a floor raised in that pull is missed for that session. Fixing it means re-parsing after the resolve returns -- a change to connection construction with Task 21's writer-floor test surface attached -- against a window of one session on a migrating repo, with the next connection reading the pulled file. The note lives at the assignment site in `R/conn.R`, not only in the spec, because that is where somebody would otherwise re-derive it. | Task 23 DONE record, `R/conn.R`, `R/ref.R` |
| 2026-09-17 | **(implementation, Task 23) Two `repo.R` verbs get no check of their own, and the reason is written at one of them rather than left silent.** `datom_repo_set_data_store()` and `datom_repo_attach_governance()` both require a developer connection, so building one already refused a config whose format this build cannot read. The comment at the former's read-modify-write also records the second half, which the shared-constant argument had got wrong: carrying `schema_version` forward untouched is why that verb never raises the declared number -- only `datom_init_repo()` stamps one. Stating it at the site is what stops a later session either adding a redundant gate or repeating the claim that this verb raises the number. | Task 23 finding 2, `R/repo.R` |
| 2026-09-17 | **(review finding, ACCEPTED and fixed, Task 23) `datom_repo_set_data_store()` was the one site that parsed `project.yaml` without checking it, and it is the only verb besides `datom_init_repo()` that WRITES that file.** The first commit argued the check away -- the verb needs a developer connection, so connection construction already refused an unreadable config -- and **that argument is refuted by the same commit's own words at `.datom_check_set_write_gates()`**: the connection-time gate is not redundant, because a hand edit or a pull replaces the file between opening a connection and writing through it. It applies harder here on three counts. The verb merges a `storage$data` block in **on this build's assumptions**, so a format that reparented those keys gets a stale block beside the real one; it then **commits and pushes**, so the wrongly-edited file reaches everyone sharing the repo, where the set-write gate only refuses a write; and the timing is not contrived, since this is the storage-migration verb and is called exactly when somebody is hand-editing that file. Reading halves cannot be retrofitted, so it could not wait for a later release. Fixed with the same two lines the set-write gate uses at `operation = "write"`, above the merge. **The comment is replaced rather than deleted**, because what it asserted is the false part and a later session would otherwise re-derive it; its true half is kept and labelled separate -- the read-modify-write is why an unrecognised `schema_version` is carried forward untouched. One test, asserting the refusal **and** that the file is byte-identical afterwards; removing the check reddens exactly it. **Distinct from the reviewer's earlier claim about this verb, which stays refuted**: that one said the verb silently raises the declared number, which it does not. Tests 3836 -> 3841. | Task 23 DONE record, `R/repo.R` |
| 2026-09-17 | **(decision, Task 11) `mode` and `set` are written by `datom_init_repo()` only for a product repo, and the key-set tripwire gains the RULE rather than just a second case.** Taken at the audit's stated default: a `mode: standard` line in every config adds a key nothing reads, and "absent means not a product repo" is already the semantics the set-write gate implements. **The amendment is the part worth keeping** -- the tripwire's blind spot is not about `mode`. It watches only the creation path it exercises, so **any** conditionally written key is invisible the same way and the next path added is unwatched again, while the test still reads as a guard. So its comment now states the standard: exercise every path that writes `project.yaml`, and adding such a path means adding a case. **That rule has a second member today**, which makes it actionable rather than a note: `datom_repo_set_data_store()` writes this file too, its test asserts only that two fields survive, and a refactor to rebuilding the document would silently drop `schema_version`, `created_at`, `datom_version`, `sync` and `renv` -- the same hazard Task 20 tested its two read-edit-write surfaces for despite them needing no code. **Also corrected: Task 23's claim that this task fires the tripwire immediately**, which does not follow from conditional emission; the live statements are fixed and the frozen Decisions rows left alone. | Task 11 finding 1, `tests/testthat/test-conn.R` |
| 2026-09-17 | **(decision, Task 11) The import refusal reads `mode` from the FILE; only `datom_status()`'s report reads it from the connection. THE AUDIT'S FIRST-STATED DEFAULT WAS WRONG and was amended by review.** The rule is the one Task 23's review settled: a check that **authorises a write** must see the file as it is *now*, because a hand edit or a pull can replace it after the connection was built, while a report is fine with the connection's snapshot. The audit then grouped the import refusal with the status line as "not a gate", which inverts what it is -- it is the thing that **stops an import**, the same job the set-write gate does -- so on the connection, a repo hand-edited to `mode: product` after the connection opened would have gone on accepting file imports, which is precisely the window the rule closes. Cost of the correction is one extra local parse on a path that already does git and storage work. **State the rule as the test a future site applies** -- does this site authorise a write? then it reads the file -- rather than as three site-by-site facts. **One consequence neither side stated, and it must ship with the refusal**: a new parse of `project.yaml` is a new **gated** parse, so the refusal carries `.datom_check_project_schema(..., operation = "write")` and the shared helper is three steps in one place (parse, format check, mode check). Missing the middle step would quietly reopen the hole Task 23 closed, on a path that writes. | Task 11 finding 2, R10.1 |
| 2026-09-17 | **(review finding, ACCEPTED with the reason re-derived, Task 11) The namespace guard's condition class lands BEFORE the backend widening, and the reason first offered for that order does not hold.** The review argued that widening `if (data_backend == "s3" && ...)` to local "puts more traffic through the fragile part" -- the text-matched re-raise at `R/conn.R:440`. Volume is not the issue; the coupling is per-call. The real reason is that the widening's own AC22 test is what would **encode** the fragile path: written against a text-matched re-raise, it passes *through* the coupling and then defends it. Class first, widen second, and the new test dispatches on the class from the start. **One over-claim corrected, because it changes the urgency**: rewording the message does not fail silently today -- four tests grep that string and two of them go through `datom_init_repo()`, so a reword swallows the abort, lets init proceed, and reddens both. The coupling is noisy, not silent. It is still worth removing, for the case that genuinely would be silent: a **new** abort added inside `.datom_check_namespace_free()` for some other reason, which the handler swallows with nothing watching. | Task 11 findings 4 and 5 |
| 2026-09-17 | **(audit finding, Task 11) Widening the namespace guard to local stores falsifies its message, and nothing would fail if that were missed.** Stated by neither the audit nor the review that followed it. The refusal is hardcoded to one backend in words and in format: it opens "S3 namespace is already occupied", advises "a unique S3 namespace (bucket + prefix)", and builds its location as `paste0("s3://", conn$root, ...)`. On a local store that prints `s3://` in front of a filesystem path and tells the user to change a bucket they do not have -- a message that is confidently wrong, which this spec has repeatedly judged worse than no message. The message becomes backend-neutral in the same change, using the label vocabulary `datom_status()` already has for this. | Task 11 finding 4, `R/utils-validate.R` |
| 2026-09-17 | **(review finding, ACCEPTED and fixed, Task 11) An unverifiable storage namespace now FAILS CLOSED, for every repo rather than only product ones -- the tolerance was not a deferred check, it was a dropped one.** Traced end to end rather than argued: store unreachable -> the check warns and reports unknown -> `datom_init_repo()` continues and pushes the git repo -> the manifest upload aborts -> and the verb that abort pointed at performs **no** occupancy check of any kind. Meanwhile init **cannot finish without storage**, because that upload is part of it, so the tolerance never yielded a working offline init; its only reachable effect was getting past the check, and the outcome is a manifest written over another project's. **The posture makes this a rule, not a judgement call**: breaking a behaviour loudly is acceptable at this stage and silently disabling a verification check is not acceptable at any stage, and this was the second wearing the clothes of the first. So it aborts with `datom_namespace_unverified` and AC22's "refused" is **unconditional**, replacing the "when the namespace could be read" qualifier the first pass recorded. **Two code details the trace produced beyond the policy.** The refusal must not offer `.force`, which skips this check but not the upload, so it cannot rescue an init without storage -- advice that does not work is worse than none. And the upload's own recovery hint named `datom_sync_manifest()`, which scans `input_files/` and writes nothing to storage; the verb that mirrors metadata is internal and reached via `datom_validate(fix = TRUE)`. Both fixed here and pinned, because an unusable recovery instruction is how the tolerance stayed plausible. **Rejected, with the reason**: adding the namespace check to `datom_sync_manifest()`. That verb is also the ordinary path for your own repo, where the namespace is legitimately yours, so it would need a project-name comparison rather than an occupancy test -- and a connection's project name is the unvalidated label Task 26 spent a task on. A name comparison does exist in `datom_validate()` (`R/validate.R:266`), which is detection after the fact rather than prevention. Tests 3854 -> 3860. | Task 11 finding 5, `R/utils-validate.R`, `R/conn.R` |
| 2026-09-18 | **(implementation, Task 11) `mode` and `set` are appended to the config by ASSIGNMENT, not declared in the `list()` constructor -- and a probe showed the guard beside them is not what makes that safe.** In a `list()` constructor a NULL is a present element, which yaml writes as `mode: ~`: a declared empty value rather than an absent key, and the same defect shape as a NULL field in a JSON document with a different serializer. Assignment is the opposite, because `$<-` with NULL **removes**. So the `if (!is.null(mode))` wrapper is belt-and-braces: deleting it reddens **nothing**, while moving the two fields into the constructor reddens two tests. The comment at the site says which half is load-bearing, because the reverse reading -- that the `if` is the protection -- invites someone to keep the `if` and move the fields. Same correction the `parquet_sha` note needed in Task 26. | Task 11 DONE record, `R/conn.R` |
| 2026-09-18 | **(implementation, Task 11) The namespace check builds its probe connection through `.datom_build_init_conn()`, which is what makes the local-backend widening possible at all.** It previously spelled out an S3 client inline, so there was nothing to widen: a local store needs a connection with no client, and that builder already knows which shape to make -- it is the same one init uses for the real data connection. Recorded because the widening reads as a one-line condition change and is not: without this, "check local stores too" would have constructed an S3 client for a filesystem path. | Task 11 DONE record, `R/conn.R` |
| 2026-09-18 | **(implementation, Task 11) `datom_status()` skips the input-files block entirely on a product repo rather than relabelling it, while `datom_init_repo()` still creates the directory.** Two decisions that look inconsistent and are not. The directory stays because not creating it changes what init guarantees about the tree and breaks an existing test, for a cosmetic gain -- finding 10's default. The report skips because "Input files: directory empty" describes a repo with nothing to onboard rather than one that never will, which is the same misreport the import verbs were giving. So the honest split is: the tree is unchanged, the description of it is corrected. | Task 11 DONE record, `R/query.R` |
| 2026-09-18 | **(review finding, ACCEPTED and fixed, Task 11) A refusal must not advise an override its caller does not honour -- and this is the same defect the same function was fixed for one commit earlier.** The occupied-namespace refusal ended with "pass `.force = TRUE` to override" whatever the caller's policy was, while a product repo's check ignores `.force` entirely: so the message routed exactly those users into a flag that changes nothing, and the test asserting `.force` is refused sat two files away from the message telling people to use it. The backend-neutrality fix had already established the principle -- **this function cannot know its caller's policy any more than it knew the backend** -- and stopped one line short of applying it. **Two fixes, each pinned independently** (dropping the argument check reddens 2 tests, making the bullet static again reddens 1). (a) `.force = TRUE` with `mode = "product"` **aborts at the argument check**, beside the mode/set co-validation, rather than being dropped: same rule as refusing a version supplied beside a member record that already carries one, since ignoring an argument reports success for an action nobody asked for and would leave the caller relying on an override that does not exist. (b) The override bullet is conditional on a new `overridable =` argument, and the product wording **says why** there is none -- a bare "use a different prefix" leaves the user hunting for the flag. `.force`'s docs now name both exceptions, the unreachable store and the product repo. Tests 3900 -> 3909. | Task 11 DONE record, `R/utils-validate.R`, `R/conn.R` |
| 2026-09-18 | **(decision + audit correction, Task 12) `datom_repo_commit()` does NOT run the staleness gate -- and this audit's stated reason for worrying about that, that the gate would make R15.7's explicit branch guard redundant, is FALSE.** The decision itself is the audit's default, taken: a commit is local and a push is shared, so gating the local verb makes saving your own work depend on somebody else's push or on being online, and `.datom_git_push()` already pulls before pushing. **The correction is the part worth keeping.** `.datom_check_git_current()` reaches `.datom_git_branch()` only after four early returns -- no remote, fetch failed, no upstream, and **local SHA identical to upstream** (`R/utils-git.R:434`, `:460`, `:468`, `:474`; branch call at `:478`) -- so the transitive guard fires only when you are out of sync with the remote. A detached HEAD **while up to date**, which is the ordinary shape of the mistake, passes straight through. The explicit assert is therefore not duplication but the only check that runs in the common case, and the risk was never failing to add it: it was somebody deleting it later for looking redundant. Written into R15.7 naming the identical-SHA return, so it cannot be re-derived the wrong way. **Why it earns a line at a low rate**: a commit onto a detached HEAD succeeds, prints a SHA, and is unreachable the moment you switch branches -- and with `push = FALSE` no later push failure reveals it. Silent plus unrecoverable is the combination that justifies a cheap guard. Detached checkouts are routine in CI; the claim stops there, because trigger-by-trigger behaviour depends on how the checkout step is configured and was not verified. | Task 12 finding 9, R15.7 |
| 2026-09-18 | **(implementation, Task 12) The explicit on-a-branch assert goes in `datom_repo_commit()` and NOT in `datom_repo_push()`, and the asymmetry was settled by probe rather than by reading R15.8.** An explicit assert in the push verb reddened **nothing**, and the reason is structural rather than incidental: the nothing-to-push early return is taken only when the ahead count is a real number, the count comes from `git2r::branch_get_upstream()`, and a detached HEAD has no upstream -- so the count is `NA`, the verb always reaches `.datom_git_push()`, and the guard inside `.datom_git_branch()` fires there. The commit verb has no such backstop with `push = FALSE`, which is where R15.7's assert earns its line (removing it reddens 2 assertions). Recorded because the two verbs now *look* inconsistent: a later reader who "fixes" the push verb adds a line that cannot fail, and one who deletes the commit verb's line removes the only check that runs in the common case. Both sites and the test name state which is which. **The residual, stated rather than implied**: the push verb's guard depends on `NA` meaning "push anyway". A future change that made an unknown ahead count return early would silently take the guard with it. | Task 12, R15.7, R15.8 |
| 2026-09-18 | **(implementation, Task 12) `datom_repo_commit()` and `datom_repo_push()` call no forward-compatibility write gate, and that is a decision rather than an omission.** Every other write verb in this spec had to call `.datom_check_write_entry()` itself -- the route-was-the-gap finding, three tasks running -- so the absence here needs a reason on the record. These verbs write **none** of datom's documents: they stage and commit whatever the caller named, so gating them would refuse a commit of somebody's R code because a manifest in the same clone carries a field this build cannot classify. The one datom-document interaction is `paths = NULL` sweeping in files left dirty by a **failed local write from this same build**, which already passed the gate when it ran. Recorded with the boundary that makes it hold: if either verb ever *produces* a datom-owned document (Task 13's `include_paths` does not -- it stages caller-named paths into the artifact write's commit, and that write is gated), the gate comes with it. | Task 12, Task 21, Task 13, I5 |
| 2026-09-18 | **(decision, Task 13) An `include_paths` entry that is gitignored is REFUSED rather than silently dropped, and the refusal ships with that task.** Settled by running git2r, not by reading it: `git2r::add(repo, <gitignored path>)` raises no error and stages nothing, and `.datom_git_commit()` cannot catch it because it only objects when **nothing at all** is staged -- and datom's own payload and metadata files always are. So the commit succeeds while omitting the file the caller explicitly named, and the set version claims a joint commit it does not contain, which is AC18 failing with no symptom. Scope was weighed against a Backlog row and rejected on the same ground this spec has used before: a silently incomplete guarantee is worse than a loud refusal, and the whole point of `include_paths` is that the joint version is structural. **It is Task 12's finding 6 in mirror image** -- there the hazard was `force = TRUE` staging ignored files, here it is the default flags skipping them -- so the two belong in one place, and both are now in `dev/engineering-notes.md`. | Task 13, AC18, R12.5, Task 12 finding 6 |
| 2026-09-18 | **(scoped audit, Task 13) I19 holds today by PLACEMENT, and its existing coverage is the spelling that cannot fail.** The reviewer scoped the pre-start pass to this one claim because the Decisions log already names its stake, and a hazard claim nothing pins needs a test rather than a re-reading. What was found: the no-change branch (`R/set.R:746`) returns above the payload write, the manifest row and the one commit call, so the guarantee is free -- and `test-write-set.R:675` / `:807` assert `action == "none"` on the **returned list**, which stays green through a write that commits the dirty code and then reports no change, i.e. through exactly the failure I19 exists to prevent. AC19's test therefore reads git HEAD before and after, and asserts the `include_paths` file is dirty **both** before and after, without which it passes vacuously in a repo where nothing changed. Also settled: a nonexistent or overlapping path is an error **even on the no-op path**, because validation precedes the hashing the change detection needs -- recorded so it is not later "fixed" into tolerance. | Task 13, I19, AC19, AC20 |
| 2026-09-18 | **(implemented, Task 13) The joint commit ships, and the gate grew a fourth refusal the requirement does not name: a path that leads outside the clone.** R12.5 lists two gates (nonexistent, datom-owned) and the audit added a third (gitignored). The fourth is there because `fs::path(conn$path, "/etc/passwd")` **joins** rather than replaces, so an absolute path would otherwise be reported as a missing path *inside* the repo -- a true refusal whose message names the wrong thing -- and a `../` path that resolves to a real file would reach `git2r::add()`, which stages nothing for it and says nothing, the same silent-omission failure the gitignore refusal exists to stop. Escape is judged **after** lexical normalisation, so `a/../b` is `b` and allowed: the gate is about leaving the clone, not about spelling. Normalisation is load-bearing for the owned gate too -- `./.datom/manifest.json` and `.datom/manifest.json` are one path, and a gate splitting the raw string lets the first past (probe P6 reddens exactly that test). | Task 13, R12.5, AC20 |
| 2026-09-18 | **(implemented, Task 13) I19's proof is a probe, and the probe is what shows the old coverage could not fail.** Committing the listed paths on the no-op path reddens AC19's HEAD assertion, its dirty-after assertion and its file-content assertion, and leaves `action == "none"` **green** -- the audit's prediction, confirmed by breaking the code rather than by reading it. A second probe that simply never makes the edit reddens the dirty-before assertion, so the test cannot pass by finding nothing moved in a repo where nothing happened. Nine probes in total, each reverted, each naming what it reddened; the table is in Task 13's DONE record. **The residual worth knowing**: `datom_repo_commit(paths = <gitignored>)` still drops the path in silence, deliberately unchanged here -- that verb promises to stage what it is given and mints no version claiming otherwise -- but the refusal is now one helper (`.datom_git_ignored()`) away if the acceptance sweep decides it should refuse too. | Task 13, I19, AC19, AC18, Task 12 |
| 2026-09-18 | **(decision, Task 14) Three calls on the scope of the kind branch, all taken at the defaults proposed before implementation.** (1) **No `member_conns` argument.** R11.2's "unless the caller supplies that project's conn" is left unbuilt rather than half-built: nothing today can express it, and the route that exists is strictly better -- running `datom_validate()` against that project checks every artifact in it, not one member pointer. (2) **No byte-integrity download.** Presence and resolution only; the `document_sha` comparison stays on the read path, where it guards the bytes actually in use. (3) **`fix = TRUE` DOES restore a missing set payload**, which is beyond R11's letter, for two reasons that are both about the alternative: without it a set whose upload failed after the commit had no repair route at all (the write verb correctly no-ops on unchanged members), and with no upload path anywhere in the code AC29c's "leaves the stored bytes unchanged" would have passed forever whatever the code did. | Task 14 DONE record, R11.2, AC29c |
| 2026-09-18 | **(implemented, Task 14) The kind branch forced a status the requirement does not name: `kind_unsupported`.** The payload-key builder validates its `kind` argument, so handing it a kind from a newer datom aborts the whole validation run -- and a run that cannot finish reports nothing about the artifacts it never reached. An unknown kind now leaves that row's payload unchecked (`data_s3 = NA`) and says so, rather than reporting a payload missing that this build cannot even address. Reads limp, and the rest of the repo is still checked. | Task 14 DONE record, `R/validate.R` |
| 2026-09-18 | **(implemented, Task 14) A test of mine was passing through the wrong guard, and the probe is what found it.** The never-re-upload test first modified the clone's payload, which made it pass through the hash comparison and stay green with the absence check deleted -- so the rule it names, that stored bytes a version pins are never overwritten, was unasserted. It now leaves the clone matching and watches for the upload call. Same shape as Task 13's I19 finding: a test asserting a value where the behaviour lives elsewhere. | Task 14 DONE record, `tests/testthat/test-validate-sets.R` |
| 2026-09-18 | **(review of Task 14, accepted) The set-payload restore fires on TWO public routes, and the behaviour stays on both.** `.datom_sync_data_metadata()` is called by `datom_validate(fix = TRUE)` **and** by `datom_write(conn)` with no `data` and no `name`. Restoring on the second is right -- that route mirrors the clone's authoritative state to storage, so syncing a set's metadata while leaving the payload it describes missing would be the odd half -- but every description said "repair", which would read as a bug the first time someone saw it fire under a write verb. Four wordings fixed (the `name` parameter, the interactive prompt, the specification's `datom_validate()` section, and this spec's own summary) and **`.datom_sync_table_metadata()` renamed to `.datom_sync_one_artifact()`**: it handles either kind and can upload a payload, so both halves of the old name were false and a grep for where a set reaches storage on that route missed it. Root cause is one thing, not four: the path went kind-agnostic and kept its table-only vocabulary -- the class Task 6 closed for `manifest$tables`. | Task 14 DONE record, `R/sync.R`, `R/read_write.R`, `dev/datom_specification.md` |
| 2026-09-18 | **(rule, from two instances) A guard's test must fail when that guard ALONE is removed.** Task 13's I19 coverage asserted a returned value while the behaviour lived in git, and Task 14's never-re-upload test passed through the hash comparison while the absence check was the rule it named. Twice makes it a pattern, so it is stated as a rule rather than logged as a second incident: when a behaviour is protected by more than one condition, each condition needs a case that isolates it, and the way to know is to delete that condition and watch. A test that stays green under the deletion is testing a different guarantee than its name claims. **Task 17 harvests this into `.github/copilot-instructions.md`**, where the test discipline lives. | Task 13 and Task 14 DONE records, Task 17 |
| 2026-09-19 | **(pre-start audit, Task 15) The `commit_sha` strip trap has THREE doors, and the body named the one that matters least.** Three functions write the storage copy of `version_history.json`: the ordinary write path (`.datom_push_metadata_s3()`, `R/read_write.R:939`), the mirror/repair path (`.datom_sync_one_artifact()`, `R/sync.R:292`, reached from both `datom_validate(fix = TRUE)` and `datom_write(conn)`), and the metadata-only write route (`.datom_sync_metadata()`, `R/utils-sha.R:673`). The first reads the clone's file and uploads it **wholesale**, and the clone's copy can never carry the field (R21.6) -- so the second ordinary write erases the first version's id, with no repair involved. Probed rather than read: the stored and clone copies are `identical()` today, which is what makes a wholesale upload lossy the moment one copy is meant to carry more. Guarding only the repair path would leave the field strippable by two **write** verbs. | Task 15 audit findings 1-3 |
| 2026-09-19 | **(decision, Task 15) Keep what storage has AND derive the gaps, in one shared helper -- and it is REQUIRED, not preferred.** Merging alone (no derivation anywhere) makes the design's own tolerance false: "an older build strips it, which is survivable because it can always be re-derived" holds only if something derives. An implementation that merges and never derives passes every test this task will write while quietly removing the property that justifies storing the field at all -- so this belongs in the **task body**, not only here. Cost is per **missing** entry: an upgraded repo backfills once and the steady state is 0-1 derivations per write, so there is no standing tax to mitigate. | Task 15 audit finding 5 |
| 2026-09-19 | **(decision, Task 15) `datom_history()` gains a `commit_sha` column, zero-row frame included.** The stored copy exists purely for a reader with no clone (R21.8), and that verb is their only route into the file -- without the column the field is reachable only by hand-parsing JSON, so the feature would not exist for its only audience. | Task 15 audit finding 6 |
| 2026-09-19 | **(rule, Task 15) `commit_sha` is derived, never authored: no user-facing verb accepts one.** `.datom_push_metadata_s3()` takes it as an argument only because it sits one layer below the caller that already holds the commit, and none of the three doors is exported (checked against `NAMESPACE`). Stating it as one rule rather than as two facts is deliberate -- it covers both the internal threading and why the repair path re-derives instead of trusting what it was handed. | Task 15 audit finding 6a, I22 |
| 2026-09-19 | **(pre-start audit, Task 15) Deriving the producing commit from git is exact, and was probed rather than assumed (git2r 0.36.2).** `git2r::commits(repo, path = "{name}/metadata.json")` filters to the commits touching that path; a blob at a commit reads through `tree(cmt)[...]` + `git2r::content()`; and recomputing `.datom_compute_metadata_sha()` on the parsed blob reproduces the **recorded** version exactly, so iterating oldest-first yields "the first commit that introduced that version" (R21.3) with no extra bookkeeping. The same probe confirmed a code-only commit is no version's producer, which is AC26 from the other side. Cost: one blob read plus one hash per commit touching that path. | Task 15 audit finding 4 |
| 2026-09-19 | **(decision, Task 27) The version argument splits: `version_from` selects, `version_to` targets, and `version_to` defaults to CURRENT.** One name could not carry both directions -- the signature narrowed by `version` while the body used it to state a destination. Names chosen for symmetry at the call site over the single `to` the audit floated. `version_from` is optional, needed only when a name resolves to more than one member. Two consequences to implement rather than infer: `version_to` refuses a selection matching several members, since one target version across several artifacts is not a meaning; and an **explicitly named** ambiguous member **aborts** while only the bulk sweep skips, because R24.6's skip argument is about not failing a whole refresh and does not reach a request the caller spelled out. | R24.2, R4.2a, Task 27 |
| 2026-09-19 | **(decision, Task 27) `version_to` may infer current even though `datom_add_member()`'s version may not, and the boundary is recorded inside R4.2a.** The word carrying it is **silent**: R4.2a refuses a verb that says nothing about time quietly resolving newest. A verb whose meaning is *move forward from here* states the time-dependence in its own name and reports every version it moved before anything is written. **A verb that constructs a pointer requires a pin; a verb whose meaning is time-dependent may infer current and must then say what it inferred.** The guarantee R4.2a protects survives by a different route rather than being traded: an update is the snapshot moment and its own output is a pin, so whoever later reads the written set is as reproducible as ever. Same split `renv` draws between `update()` and `restore()`. | R4.2a, R24.2, Task 27 |
| 2026-09-19 | **(correction, Task 27) The pre-start audit's justification for `(x, conn, ...)` was FALSE, and the order stands on a different rule.** The claim was that object-first lets the verb pipe into the write. `datom_write_set()`'s first parameter accepts a `datom_conn` or a `datom_set_draft` only (`R/set.R:887`); the `datom_set` widening is on `members` (`R/set.R:919`), so a piped set lands in the connection slot and aborts. Piping into the second argument needs the `_` placeholder, which is R 4.2.0 against this package's declared `R (>= 4.1.0)` (`DESCRIPTION:24`); and the read-modify-write idiom already documented is three statements ending `datom_write_set(conn, x)` (`R/set.R:769`), not a pipe. **The rule that does hold, and that the package already follows: a verb that EDITS an object in hand takes the object first, a verb that RESOLVES something takes the connection first** -- `datom_add_member(x, ...)` versus `datom_fetch_member(conn, x, ...)`. Decisive for the pair: `datom_remove_members()` cannot take a connection at all, so connection-first for update would split the two sibling edit verbs in the one place a reader compares them. | R24.1, Task 27 |
| 2026-09-19 | **(decision, Task 27) An edited set returns with `version` and `data_sha` blanked, via a helper Task 28 shares. Returning a `datom_set_draft` instead was proposed and REJECTED on two checks.** The draft was attractive because it has no version, no `data_sha` and no links, dissolving two audit findings outright. It fails because a draft carries the connection it will be written through, and `datom_write_set(draft)` needs that to be a **developer** connection on the **product** repo -- while this verb's connections are the **members'** projects, which for a product whose members all live elsewhere includes none for its own repo. Second, `datom_remove_members()` has no connection to put in a draft, so the pair would return different classes, which R24.1's "parallel in shape" exists to prevent, and remove's chain would stay broken regardless. The two problems are solved directly instead: blank the two fields, and rebuild each repointed member's link through the existing factory. | R24.1, Task 27, Task 28 |
| 2026-09-19 | **(decision, Task 27) Record-versus-link consistency is prevented structurally, with one tripwire and the existing write gate behind it.** A member's record and its `fetch` link are two copies of one fact, so every edit path rebuilds the link from the record through the one factory (`R/set.R:1313`) and drift becomes unrepresentable rather than checked for. A tripwire asserts agreement on **touched** members only, so cost scales with the edit; it is not the guarantee but what reddens if a later change edits a record without rebuilding. `.datom_validate_members()` plus link-stripping before hashing (`R/set.R:923`) means a **stored** set cannot be inconsistent however the in-memory object was made. Deliberately not chased: a direct hand assignment into `x$members[[i]]$id` is outside every verb, and the write catches it -- a hand-built set is already supported and untrusted. | R24.1, I10, Task 27, Task 28 |
| 2026-09-19 | **(decision, Task 27) `conn` stays required even when `x` is a draft that already carries one, and the embedded one is ignored.** A draft holds exactly one connection while this verb legitimately spans several projects, and silently preferring the embedded one would make the same call behave differently depending on how `x` was produced. | R24.1, Task 27 |
| 2026-09-19 | **(correction, Task 27) AC41(d)'s fixture does not already exist, and the one the task pointed at cannot express it.** The no-gate test (`tests/testthat/test-set-members.R:689`) is single-store: it mutates `project_name` on one connection, so the member and the store agree and only the label differs -- the opposite of a connection whose label matches while its store holds another project's same-named artifact. The fitting base is the parameterised two-project fixture `local_draft_project(project_name, set_name, prefix)` (`tests/testthat/test-set-draft.R:37`), which will have to be duplicated since testthat shares nothing between files. | AC41, Task 27 |
| 2026-09-19 | **(pre-start audit, Task 27) Carrying a member's labels through `datom_member()` breaks AC40(a) silently.** The natural spelling passes the old record's `tags` to the rebuild, and `datom_member()` runs `.datom_drop_empty_tags()` on what it is handed (`R/member.R:518` area), so a label whose value is empty is dropped. Invisible on every payload datom wrote, because those were tidied at write; it surfaces only on a hand-built or foreign-written set. Build the pointer with **no** tags and attach the old record's `tags` verbatim, which keeps the snapshot read and `kind` resolution while satisfying byte-identity. | AC40, Task 27 |
