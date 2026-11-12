# Requirements -- S3 credential function

**Issue**: [#134](https://github.com/amashadihossein/datom/issues/134), part 3b ("S3 credential
function"), split from part 3a in the issue's comment of 2026-10-24.
**Branch**: `spec/s3-credential-function`, cut from `dev` at `347a403`; `dev` merged in at `c539516`
on 2026-11-10, after #155. **PRs into `dev`.**
**Tier**: 3 (credential handling). Requirements, design and tasks each stop for the owner's approval;
decisions are taken one at a time.
**Status**: approved by the owner on 2026-10-27. Amended with the owner on 2026-11-10, after #155
(interrupted commands finish on a re-run) merged: R2.7 is new; R4.1, R4a.1, R4a.2, R4b (FM3, FM4,
FM14-FM16) and AC8 changed; AC11 is new; decisions 7-9 added. Amended again the same day, after a
design review evaluated with the owner (`design.md`, section 14): R2.5, R2.7, R3.4, R4.1, R5.6, FM12,
FM14, FM15, FM16, AC7, AC11 and decision 2 changed; decisions 10 and 11 added. Amended a third
time, after a second design review evaluated with the owner (`design.md`, section 14): the endpoint
moves to the store and into `ref.json` and `project.yaml`, and writes go only where governance and
the data repo agree. R1.1-R1.3, R3.4, R5.6, R6.4, FM7, FM15, decision 10 and AC7 changed; R3.6,
R3.7, R5.7, R5.8, FM17-FM19, decisions 12-15 and AC12-AC14 added. Amended a fourth time, after a
third design review decided with the owner on 2026-11-11 (`design.md`, section 14, review 3): R3.6,
R5.7, R6.5, FM19 and decision 14 changed; R3.8, R3.9, R5.9, decisions 16-17 and AC15-AC16 added.
The spec stays one spec (owner, 2026-11-11). Amended a fifth time, after a fourth design review
decided with the owner on 2026-11-12 (`design.md`, section 14, review 4): the writer floor becomes
a fixed `0.3.0`, raised by the first commit of a 0.3.0 build and checked at the start of every
command that commits or pushes. R3.8, R5.9, R6.4, R6.5, FM19, decision 16 and AC15 changed; FM20,
FM21 and decision 18 added. Amended a sixth time the same day, after a fifth review (`design.md`,
section 14, review 5): the floor is raised only at init, by the write routes at their opening pull
(once per `datom_sync()`), and by `datom_repo_set_data_store()`. R3.8, R5.10, R6.5 and AC15
changed; R6.7 and decision 19 added. Amended a seventh time the same day, after a sixth review
(`design.md`, section 14, review 6): the raise goes into the command's own commit everywhere, and
heal's reset restores a leftover floor edit. R3.8, R5.10 and decision 19 changed. Amended an
eighth time the same day, after a seventh review (`design.md`, section 14, review 7): the leftover
floor edit is restored by its own small step at the start of every pull, not by the reset of
unfinished artifact work. R3.8 and R5.10 changed.
**Test baseline**: 6354 expectations, 0 failed, 0 skipped (`devtools::test()` on this branch after
merging `dev` at `c539516`, 2026-11-10; 5142 on `347a403` before #155).
**Reference contract**: datom-py's `.kiro/specs/s3-reader/requirements.md`, R3. Where R differs, the
requirement says so under "R differs".

## Goal

`datom_store_s3()` accepts a function that returns AWS credentials, so a user can work with
short-lived credentials (single sign-on, an assumed role) without pasting keys in and without keys
sitting in the store object. datom calls the function when it needs credentials and again before they
expire. The rule this serves, unchanged: **datom receives secrets explicitly at runtime and never
discovers, persists or prints them.** So nothing ambient -- environment variables, `~/.aws/`,
instance metadata -- may ever supply the credentials a request is signed with.

## Research: what paws does with credentials

The split comment's open question: can a paws client call a credential function again on expiry,
and does it fall back to `~/.aws`, environment variables or instance metadata when the function's
result is incomplete? Answered 2026-10-27 by reading paws.common 0.8.8 (installed with paws.storage
0.9.0) and by a probe that sent signed requests to a local stand-in server, with fake keys planted in
the environment and in a credentials file. No request went to AWS.

**Short answer.** Yes on both counts. paws can call a function again near expiry, but only through
an undocumented setting. And it falls back to the ambient sources whenever the credentials it holds
are empty or expired. This spec uses neither behaviour: datom renews the keys itself and never gives
paws an expiry time (decision 1).

| # | Finding | Evidence |
|---|---|---|
| F1 | paws decides about credentials each time it signs a request. If the credentials it holds are missing, empty, or within 5 minutes of their `expiration`, it walks its lookup list: environment variables, `~/.aws/credentials`, `~/.aws/config` (including `credential_process`, SSO and assumed roles), the container endpoint, instance metadata. | `sign_with_body()` and `is_credentials_provided()` in paws.common; the default `Credentials$provider` list |
| F2 | Today's datom is safe from F1 only because it never passes an `expiration`. Static keys passed **with** an expiration that has passed were signed as `AKIDFROMENV`, the key planted in the environment. | Probe B |
| F3 | The lookup list is part of the client's config (`credentials$provider`) and can be replaced by a single function. Then paws calls it once, keeps the result, and calls it again when within 5 minutes of expiry, with no fallback to the planted keys. paws does **not** document this setting; `set_config()` documents only `creds` and `profile`. | Probes C and D |
| F4 | paws does not check what the function returns. An empty secret is signed with and sent; `NULL` sends the request **unsigned**; an already-expired result is sent; a missing `session_token` field fails with an internal error; a numeric `expiration` is read as milliseconds, so seconds since 1970 count as expired and the function runs before every request. | Probes E, F, J, K |
| F5 | An error raised by the function reaches the caller unchanged, with the function's own message. | Probe G |
| F6 | When datom gives no `endpoint`, paws takes one from `AWS_ENDPOINT_URL_S3`, `AWS_ENDPOINT_URL` or `endpoint_url` in `~/.aws/config`. Region is not affected, because datom always passes one. | `get_service_endpoint()` in paws.common |
| F7 | After its first request, a paws client holds the resolved secret, and `serialize()` of the client contains it. datom's connection holds the client. | Probe I |

**What follows for datom.** paws must never be told an expiry time, since that is what starts its
search (F2). datom therefore keeps the expiry itself, hands paws keys with none, and builds a fresh
client before the keys run out (decision 1). datom checks every result of the function before paws
sees it (F4), and always gives paws the server address (F6, decision 2).

**Footnote on F2 and botocore.** botocore does not do what F2 shows: keys passed to it explicitly are
used as they are, and when they expire requests simply fail. Searching the machine when no keys are
given is standard across AWS SDKs (the "credential provider chain"); swapping out keys that were
handed in is specific to paws.

## Requirements

### R1. The store accepts a credential function

1. `datom_store_s3()` gains `credentials`, a function, and `endpoint`, the server address of an
   S3-compatible service (decision 12), both added after the existing arguments so positional calls
   keep working. A store is built from **either** `credentials` **or** `access_key` + `secret_key`
   (+ `session_token`), never both; giving both, or neither, stops with a message naming the two
   forms. The data and the governance component each carry their own `endpoint`.
2. `access_key` / `secret_key` / `session_token` keep working as in 0.2.0, **except** for four
   breaking changes, all loud, all for users pointing datom somewhere other than standard AWS
   (amended 2026-11-10, owner):
   - `datom_get_conn(endpoint = )` is removed; pass `endpoint =` to the store (decision 12);
   - `AWS_ENDPOINT_URL*` set with no `endpoint` on the store is refused (R3.4);
   - a region with no standard AWS address, such as `cn-north-1`, needs `endpoint =` (decision 10);
   - `endpoint_url` in `~/.aws/config` is ignored: requests go to standard AWS and fail there
     (unknown key, no such bucket). datom never reads that file, so it cannot warn.
3. `datom_store_s3_creds()` (the credentials-only component used with governance) gets the same
   `credentials` argument and the same either/or rule (decision 5), so single sign-on readers keep
   the governance lookup of where the data lives. It gets **no** `endpoint`: everything about the
   data's location, the endpoint included, comes from governance's `ref.json` (decision 13).

### R2. What the function returns (datom-py R3)

1. `credentials` is a function taking no arguments and returning a named list with `access_key`,
   `secret_key`, and optionally `session_token` and `expiration`.
2. `expiration` is a date-time (`POSIXct`) or an ISO-8601 string carrying a time zone (`Z` or an
   offset such as `+00:00`). Absent or `NULL` means the credentials do not expire (static keys, for
   example read from the OS keychain).
   - **R differs**: datom-py asks for a time-zone-aware `datetime`. A `POSIXct` always names one
     instant, so there is nothing to check. A string without a time zone is refused, as in Python.
     A bare number is refused: it is ambiguous, and paws would read it as milliseconds (F4).
3. datom calls the function when it first needs credentials, and again before they expire. A
   request is never sent with credentials past their `expiration`.
   - **R differs, first call** (decision 4): `datom_store_s3(validate = TRUE)`, the default, checks
     the bucket when the store is built, so that is when the function is first called. Its keys are
     kept for the first request, so the function is not called twice. datom-py checks when
     connecting. With `validate = FALSE`, and for `datom_store_s3_creds()`, which has no bucket to
     check, the first call is at connect time, as in Python.
   - **Timing**: datom, not paws, decides when to renew (decision 1). It calls the function again
     once the held credentials are within 15 minutes of `expiration`, checked before **each**
     request rather than once per job, so a long job renews as it goes. 15 minutes matches
     botocore's first refresh point, which datom-py follows (datom-py decision 3), and also absorbs
     a small error in the local clock.
4. A result that is not a named list, lacks `access_key` or `secret_key`, has an empty one, has a
   `session_token` that is not a non-empty string, has an `expiration` that is unreadable, a bare
   number or without a time zone, or has **already expired**, stops with condition class
   `datom_credentials_invalid` (datom-py code `credentials_invalid`). The message names the field and
   the problem, never a value.
5. An error raised by the function stops with class `datom_credentials_failed` (datom-py code
   `credentials_failed`). datom's message does not include the function's output; the original
   error is attached as its parent.
   - **R differs** (reworded 2026-11-10; it said "in display only", which was wrong): datom adds
     none of the function's output to its own text, but R includes a cause's text in an error's
     message, both in its message text (`conditionMessage()`) and when printed ("Caused by error").
     A Python exception's `str()` leaves the chained exception out; only the traceback shows it. A
     function that puts a key in its own error message exposes it either way.
6. Results are never printed, logged, or included in a message.
7. **A credential failure reaches the caller as itself** (decision 8, owner, 2026-11-10). datom
   labels the failure `datom_credentials_failed` or `datom_credentials_invalid` where it calls the
   function, the one place it knows the cause, and nothing downstream relabels it, turns it into a
   warning, or swallows it, whichever command is running and wherever in it the call falls. The
   message says to log in again and re-run the command; under #155 a re-run finishes whatever the
   first run left unfinished.
   - **No exception, `datom_init_repo()` included** (decision 11). After its push, a re-run of
     `datom_init_repo()` refuses, and that refusal names the repair (#155, D5 as reversed).
   - **Not covered**: AWS refusing keys datom believed good (revoked keys, a clock off by more than
     the 15-minute margin, keys passed directly whose session token has run out). datom did not just
     call the function there; it sees only AWS's reply, so these stay ordinary storage errors, as
     today.

### R3. Nothing ambient supplies credentials

1. Which credentials sign a request depends **only** on the store's arguments. None of these may
   supply them: environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
   `AWS_SESSION_TOKEN`, `AWS_PROFILE` and the rest paws reads), `~/.aws/credentials`,
   `~/.aws/config` (`credential_process`, SSO, roles), container or instance metadata.
2. This holds for a credential function **and** for static keys, with wrong credentials planted in
   every source in 1, and with nothing configured anywhere.
3. It holds for every S3 client datom builds: the data client, the governance client, the bucket
   check at construction, and the governance lookup of a project's data location.
4. The server address a request goes to depends only on the store's arguments and on datom's own
   project documents, never on an ambient setting (decisions 2, 10, 12, 13; rewritten 2026-11-10):
   - every client datom builds is given the address explicitly: the location's `endpoint`, or the
     standard AWS address for its region, keeping today's bucket-address style. That closes
     `endpoint_url` in `~/.aws/config` too, which datom cannot check without reading the file;
   - the location is the store's (bucket, prefix, region, `endpoint`), or, with governance attached,
     the one `ref.json` records (bucket, prefix, region and, from this release, `endpoint`), which
     wins when it differs, as its bucket already does;
   - datom builds the standard address only for regions whose S3 address is
     `s3.<region>.amazonaws.com`: AWS's standard regions and GovCloud (decision 10). Any other
     region (China, the US government secret clouds, the EU Sovereign Cloud, a made-up name) needs an
     `endpoint`; with one, any region is accepted;
   - if `AWS_ENDPOINT_URL_S3` or `AWS_ENDPOINT_URL` is set while the location has no `endpoint`,
     datom stops, naming the variable and `datom_store_s3(endpoint = )`. With an `endpoint` the
     variable has no effect, so it is not refused (the AWS command line may need it);
   - **where these checks run**: in `datom_store_s3()`, which knows the store's region and endpoint,
     so a refusal comes at the line that built the store; and in `datom_get_conn()` for a location
     taken from `ref.json`, the first point datom knows it. So no command that changes things meets
     a refusal partway (an address refusal in `datom_init_repo()` after its push was the case found
     in review).
5. Region already comes only from the store, or from `ref.json`.
6. **Writes go only where governance and the data repo agree** (decision 14, owner, 2026-11-10).
   With governance attached, every command that writes to storage (every route of `datom_write()`,
   `datom_write_set()`, `datom_sync()`, `datom_validate(fix = TRUE)`) first requires `ref.json`,
   the clone's `.datom/project.yaml` and the connection to name the same location: bucket, prefix,
   region and `endpoint`. Otherwise it stops before changing anything, naming the locations, with two
   ways out: reconnect with `datom_get_conn()`, which pulls the data repo (a real move updates
   `project.yaml` there too); or, if `ref.json` changed alone and the change is expected, approve it
   once with `datom_repo_set_data_store(conn, <store for the new location>)`, which records it in
   `project.yaml`. A change made to `ref.json` alone therefore cannot redirect a write; it also takes
   a pushed commit to the data repo, which GitHub's permissions and history guard.
   - **Connecting does not stop on a disagreement**: `datom_get_conn()` warns instead, so the
     developer can connect and run the approve command. (Today it stops when the bucket disagrees
     after its pull, and does not compare at all for a credentials-only store.) The connection then
     uses `ref.json`'s location, so a developer's reads follow `ref.json` as a reader's do. This is a
     deliberate loosening of today's stop, accepted by the owner on 2026-11-11: reads change nothing,
     and writes still stop.
   - The check replaces today's write-time comparison of `ref.json` with the connection, which ran
     only on `datom_write()` with data and on `datom_write_set()`.
7. **A reader is told when the data is served from somewhere other than standard AWS**
   (decision 14). At `datom_get_conn()`, when the location came from `ref.json` and is anything but
   standard AWS S3 (an `endpoint`, a local folder, or any backend added later), datom says where the
   data comes from and that it was set by governance. No message when the caller chose the location
   in their own store. A forged `ref.json` can still feed readers forged data, as it can today by
   naming another AWS bucket: readers have no second record to check against. The help recommends
   tight write access to the governance store, with versioning and an audit log on it.
8. **Older writers are refused once a 0.3.0 build has committed to the repo** (decisions 16 and
   18; rewritten 2026-11-12, owner). An older datom ignores `endpoint` (its `.datom_parse_ref()`
   reads root, prefix and region only, and its write checks compare bucket and prefix only), so for
   a location with an endpoint it would write to standard AWS, into a same-named bucket if one
   answers (for example the old copy, kept until its sunset, after a move to another service that
   kept the bucket name). The owner's intent: a raised floor takes effect the moment the first build
   at or above it touches the repo, and nothing below it commits or pushes after that, apart from a
   write already in flight.
   - **The floor is one fixed number**, a constant in the code: `0.3.0`. It is not the running
     version, which would make a repo created by a later release refuse earlier ones that work. It
     has no endpoint condition. Only the owner raises it, when a real incompatibility calls for it.
     `DESCRIPTION` goes to `Version: 0.3.0` on this branch, so `dev` builds and the suite pass their
     own floor. `0.3.0`, not `0.2.1`: a CRAN fix of 0.2.0 would be 0.2.1, made from `main` without
     this feature, and must not pass the floor.
   - **The floor rises where data is written** (decision 19, amended 2026-11-12): three places raise
     `min_writer_version` in `.datom/project.yaml` to the constant when it is absent or lower, and
     none ever lowers it. One function does the raise.
     - `datom_init_repo()` writes it into the first `project.yaml`;
     - `datom_write()` and `datom_write_set()` write the raised floor into `.datom/project.yaml`
       with the clone's other files (step 2), when it changes anything, and commit it with the
       write's own commit. No write when there is nothing to write. Inside `datom_sync()` the first
       table whose write commits carries it. The rule (amended 2026-11-12, review 6): **the raise is
       part of the command's own commit, never a commit of its own**, so no step a caller tracks
       moves HEAD by itself. A table that fails at its data upload (step 1) has not touched
       `project.yaml`, so the sync moves on;
     - a write that stops after step 2 and before its commit leaves the floor edit uncommitted.
       Every pull, at its start, restores `.datom/project.yaml` from HEAD when its only difference
       is `min_writer_version` raised to the constant, which is certain to be datom's own leftover
       (amended 2026-11-12, review 7). Any other difference is left alone. Without it, a teammate's
       change to `project.yaml` would block the pull, and the re-run would find the floor already
       raised and never commit it. This is its own small step, not part of the reset of unfinished
       artifact work: that list is read as artifacts' files by four callers, which would report
       `project.yaml` as an artifact named `.datom`;
     - `datom_repo_set_data_store()` sets it inside its own commit, which already rewrites
       `project.yaml`.
     - `datom_repo_commit()`, `datom_repo_attach_governance()` and `datom_repo_push()` check the floor
       and never raise it: none of them writes data, so the floor need not reach GitHub before them,
       and a repo they alone touch gets its floor at the next write.
   - **One floor check at the start of every command that commits or pushes**: the write routes,
     through the entry check, as today, and now also `datom_repo_set_data_store()`,
     `datom_repo_attach_governance()`, `datom_repo_commit()` and `datom_repo_push()`, which check
     nothing today. Each pulls first, then checks, before anything changes. (`datom_repo_commit()`
     with `push = FALSE` checks the clone as it is, without a pull: a local commit should not need
     the network, and its later push goes through `datom_repo_push()`, which pulls and checks.)
   - **No re-check at the push** (decision 18): a write already running when a teammate pushes a
     higher floor still lands; every command after it refuses at its opening pull. Documented.
   - **A reader cannot raise the floor**: readers have no clone and do not push. Readers are never
     checked against it either, since it lives only in `project.yaml`.
   - Repos made by 0.2.0 or earlier carry no floor until their first commit by a 0.3.0 build; a
     0.2.0 writer can write there until then. Accepted.
   - 0.1.1 onward read the floor and refuse; 0.1.0 does not read it and cannot be stopped. 0.2.0
     checks the floor at the start of a write, before its only pull, which comes at push time, so an
     out-of-date 0.2.0 clone can make one more write after the raise; its next write is refused.
     Released code cannot change. The docs say so.
   - **Reads are not protected**: an older reader can read the old copy described above, with only
     the "Data was migrated from ..." warning. Accepted; new readers get R3.7's message.
9. **One shape for a data location** (decision 17, owner, 2026-11-11). Every record of where data
   lives (`ref.json`'s `current`, `project.yaml`'s `storage.data`, and the store) holds:
   - `type`, `root`, and `prefix`, left out when empty;
   - for S3: `region`, always, since AWS signatures name a region (AWS China and VPC endpoints need
     the real one; MinIO accepts `us-east-1`), and `endpoint` only when it is not standard AWS;
   - for a local folder: no `region` and no `endpoint`.

   One builder makes every record, and `datom_repo_set_data_store()` replaces the known location
   fields as a set (keeping any other key a newer datom put in `storage.data`), so a move off
   MinIO, or from S3 to a local folder, leaves no stale `endpoint` or `region` behind. (Today it
   merges the new block over the old with `utils::modifyList()`, which keeps a field the new block
   omits; `project.yaml` would then disagree with `ref.json`, every write would stop, and running
   the approve command again would not fix it.) One comparer decides whether two records name the
   same location, a missing field and an empty one counting as equal; the write check and connect
   both use it.

### R4. No key is held where a saved session can write it (decision 3)

1. **Function form.** The current keys and their expiry live only in a private environment inside
   datom's namespace, filed under an id unique across R sessions. No paws client is kept anywhere: one
   is built for each request (decision 9). The store holds the function and the id; the connection
   holds the id and the function. Neither holds a key, a token, an expiry or a paws client. `print()`
   says credentials come from a function.
   - **Parallel workers** (owner, 2026-10-27): a worker started as a fresh R process (`parLapply`,
     `future` multisession, `callr`, always on Windows) receives only the connection's bytes, so the
     id is not found there; because the connection carries the function, the worker calls it and
     carries on, once per worker. A forked worker (`mclapply`) starts with the private memory and
     finds the id. datom itself runs nothing in parallel.
   - The function then runs without the caller's global variables (checked 2026-11-10: a function
     reading a global failed in a fresh R with "object not found"), so the docs say to write it
     self-contained: packages called as `keyring::key_get()`, no global variables.
2. `serialize()` of such a store or connection, and a saved session (`.RData`) holding them, contain
   no key or token the function returned, including after requests have been made. (A function
   that carries keys inside itself, for example a closure over literal strings, is the caller's
   choice; the docs show reading from the keychain instead.)
3. When the id is not found (a fresh R that loaded a saved session), datom calls the function again.
4. **Keys passed directly** are unchanged from today: held in the store and the connection. The docs
   say so, and say a saved session or cache can then write them to disk.

### R4a. Long-running jobs (owner, 2026-10-27)

Single sign-on involves two lifetimes: the keys (about an hour, renewed by R2.3) and the login behind
them (set by the organisation, often 8-12 hours). Only the login's end can stop a job, because the
function then fails until the user runs `aws sso login` again.

1. **A re-run after logging in finishes the write** (rewritten 2026-11-10, decision 7). A credential
   failure at any storage request of `datom_write()` or `datom_write_set()` leaves a state that the
   same command, re-run once the user has logged in again, finishes: git and storage end as one
   uninterrupted run would have left them. No separate key check is added. Since #155 a write
   uploads its data file before it changes the clone, and its first storage request comes earlier
   still, so the renewal made before each request (R2.3) already stops a write there; a later failure
   leaves a version that is either not committed (reset by the re-run) or committed but not published
   (published by the re-run). (Until 2026-11-10 this item asked for a key check before any local file
   write, because a write then pushed to git before uploading its data file.)
2. **A credential failure stops `datom_sync()`.** Since #155, `datom_sync()` with its default
   `continue_on_error = TRUE` stops when a table's write failed after changing the clone, but moves on
   to the next table when the write failed before changing it, which is where an expired login fails.
   A `datom_credentials_failed` or `datom_credentials_invalid` error ends the sync instead; tables
   already synced stay synced, and the sync says which were synced and which were not attempted
   before the credential error reaches the caller (R2.7).

### R4b. Failure modes, guarded and documented

Every failure mode known from the research and the design discussion is listed here. Each is either
**guarded** (a test that goes red if the behaviour returns) or **documented** (stated in the user
docs, R6), and some are both. `design.md` carries this table forward; spec completion copies it into
`dev/engineering-notes.md` so later changes keep the guards.

| # | Failure mode | What the user sees | Guarded | Documented |
|---|---|---|---|---|
| FM1 | Keys expire during a session | Nothing; datom renews them | test (R5.4) | |
| FM2 | Single sign-on login expired before a command | The credential error, naming `aws sso login`; at `datom_store_s3()` already when it checks the bucket (`validate = TRUE`) | test | yes |
| FM3 | Login expires partway through a write (rewritten 2026-11-10) | At the reads that start the write, or at step 1 (data file to storage): readers see the previous version, the clone is unchanged apart from a pull. Steps 2-4 (clone files, commit, push) make no storage request. At steps 5-6 (metadata and manifest to storage): readers see the previous version and the new one is on GitHub. Either way, log in and re-run the same command, which finishes it (#155) | test (R4a.1) | yes |
| FM4 | Login expires during `datom_sync()` | The sync stops and says which tables were synced and which were not attempted; re-running the same call finishes | test | yes |
| FM5 | Code reaches a function-built connection's client directly, skipping renewal | Error at once (there is no `conn$client`). Code that tests for a client and skips when there is none would skip in silence, as the connect-time reachability check would have (found 2026-11-10) | test: no code under `R/` names the stored client outside the accessor and the connection builders | |
| FM6 | paws starts searching the machine even when given keys with no expiry time | Would be silent | test (R5.2), the only alarm | |
| FM7 | `AWS_ENDPOINT_URL*` set with no `endpoint` on the store, or `endpoint_url` in `~/.aws/config` | Refused, naming the variable and `datom_store_s3(endpoint = )`; the config file's endpoint is overridden by the explicit address, so requests fail at AWS | test | yes |
| FM8 | The function returns malformed or expired keys, or raises | `datom_credentials_invalid` / `datom_credentials_failed`, no value echoed | test | yes |
| FM9 | Local clock wrong by more than the 15-minute margin | AWS refuses the request | | yes |
| FM10 | Session saved (`.RData`, a cache) with a function-built store or connection | No key in the file; a fresh R calls the function again | test | yes |
| FM11 | Session saved with a store built from keys passed directly | The keys are in the file | | yes |
| FM12 | Connection sent to a fresh-process parallel worker | The worker calls the function once; on macOS the keychain may prompt per process. A function that uses the caller's global variables fails there with "object not found" (R4.1) | test | yes |
| FM13 | Keys held in the user's own variables, or written literally inside the function | Saved with the session; outside datom's control | | yes |
| FM14 | The function returns keys with 15 minutes or less left: keys that live that briefly (an assumed role at its 15-minute minimum), or a source that keeps handing back the same keys until just before they expire (a cache another tool refreshes late) (added 2026-11-10, widened the same day) | Works, but datom calls the function before every request while the keys it returns have 15 minutes or less left; a function that assumes a role on each call may be slowed or throttled by AWS | | yes |
| FM15 | A datom error handler, or a `purrr` loop that reaches storage, added later without letting credential failures through (added 2026-11-10) | A misleading message, as in the examples in `design.md` section 5 | test: the code-reading test (R5.7) for every loop and handler, and the sweep (R5.6) for the commands it covers | |
| FM16 | Login expires during `datom_init_repo()` after its push (added 2026-11-10, reworded the same day) | The credential failure. Re-running `datom_init_repo()` after logging in refuses and names the repair (`datom_get_conn()`, then `datom_validate(conn, fix = TRUE)`) | test | yes |
| FM17 | `ref.json` points somewhere `project.yaml` does not: a move not yet pulled, or a change made to governance alone (added 2026-11-10) | `datom_get_conn()` warns; every write stops before changing anything, naming the locations, reconnecting, and the approve command (R3.6) | test | yes |
| FM18 | `ref.json` sends readers somewhere other than standard AWS (added 2026-11-10) | A message at connect saying where the data comes from (R3.7). A forged `ref.json` can still feed readers forged data | test | yes |
| FM19 | An older datom meets a project whose location records an `endpoint` (added 2026-11-10, reworded 2026-11-11 and 12) | It ignores the field and goes to standard AWS. Usually that fails there; but after a move to another service that kept the bucket name, the old copy kept until its sunset answers. **Writes**: refused by the writer floor (R3.8) once a 0.3.0 build has committed to the repo, on 0.1.1 onward; 0.1.0 cannot be stopped; an out-of-date 0.2.0 clone makes one more write. **Reads**: an older reader reads the old copy with only the "Data was migrated" warning (accepted) | test (the floor is written, raised and checked, R5.10) | yes |
| FM20 | A teammate on a newer release pushes a higher floor while this clone's write is running (added 2026-11-12) | That one write lands; every command after it refuses at its opening pull. The write publishes one version of its own artifact and lowers nothing | | yes |
| FM21 | A repo made by 0.2.0 or earlier, not yet committed to by a 0.3.0 build (added 2026-11-12) | No floor yet: a 0.2.0 writer can still write there | | yes |

### R5. Tests

1. No test touches real AWS or needs any AWS configuration.
2. A test plants wrong credentials in the environment and in `~/.aws` stand-in files and shows that
   requests are signed only with the store's credentials and sent only to the given address, for both
   forms. It goes red if paws starts searching even when handed keys with no expiry time.
3. Each refusal in R2.4 and R2.5 has a test, and each new guard is shown going red when it alone is
   removed, recorded in the commit that adds it.
4. A test shows the function is called again once its credentials near expiry, and not before.
5. The existing suite still passes, with its count reported in every commit.
6. A test runs each command with a credential failure at its 1st, 2nd, 3rd... storage request, until
   the injected failure no longer fires, and checks that the caller gets the failure itself, not as
   the cause of another error, and that no run returns normally after the failure fired (R2.7;
   rules in `design.md`, section 5); for the write
   commands it then re-runs the command and checks git and storage against an uninterrupted run
   (R4a.1). Its test projects include a set with members, without which `datom_validate()` never
   reaches its check of a set's members. Added 2026-11-10.
7. **A code-reading test** (decision 15) fails if any `purrr` loop, or any `tryCatch()` error handler
   not starting with the pass-on line, wraps code that can reach the credential function, worked out
   from datom's own call graph. The graph counts every global name a function mentions
   (`codetools::findGlobals(merge = TRUE)`), so a function passed by name, as in
   `lapply(x, .datom_verify_one)`, is followed too. Skipped on CRAN and when `codetools` is not
   installed. Added 2026-11-10; the graph rule added 2026-11-11.
8. Tests for R3.6 and R3.7: each write route stops when `ref.json`, `project.yaml` or the connection
   disagree on any of bucket, prefix, region or endpoint; `datom_get_conn()` warns rather than stops;
   the approve command lets the next write through; the reader message appears for a location from
   `ref.json` that is not standard AWS, and not otherwise. Added 2026-11-10.
9. Tests for R3.8 and R3.9, added 2026-11-11:
   - a move off MinIO, then a write; a move from S3 to a local folder, then a write; a move onto
     MinIO, then a write: each write goes through after the approve command;
   - for the same store, every writer of a location record (`ref.json`, `project.yaml` at init,
     `project.yaml` after `datom_repo_set_data_store()`) produces a record the comparer calls equal;
   - a key in `storage.data` this build does not know survives a repoint.
10. Tests for the writer floor (R3.8), rewritten 2026-11-12, each guard shown going red when it alone
    is removed:
    - each of `datom_repo_set_data_store()`, `datom_repo_attach_governance()`, `datom_repo_commit()`
      and `datom_repo_push()`, with a floor above the installed version (`"99.0.0"`), refuses before
      changing anything;
    - the raise: `datom_init_repo()` writes the constant; a write and `datom_repo_set_data_store()`
      raise an absent or lower floor; a higher floor is never lowered; `datom_repo_commit()`,
      `datom_repo_attach_governance()` and `datom_repo_push()` do not raise, and
      `datom_repo_commit()` with staged files commits exactly them;
    - a write in a repo with no floor puts `min_writer_version` into its own commit, with no
      separate commit; with files the user staged, the write's commit holds them exactly as today;
    - a first 0.3.0 `datom_sync()` of a repo with no floor, where the first table's data upload
      fails and `continue_on_error = TRUE`, goes on to the next table, and the first table that
      commits carries the floor;
    - #155's break-at-each-step test: a break after step 2 leaves the floor edit; the re-run, with a
      teammate's `project.yaml` change pushed in between, pulls, finishes, and the floor lands in
      that write's own commit; a `project.yaml` with any other uncommitted difference is not reset;
    - after that break, `datom_repo_set_data_store()`, `datom_repo_commit()` and `datom_pull()` run
      without refusing, no message names an artifact `.datom`, and `datom_sync()`'s "failed
      partway" behaviour is unchanged.

### R6. Documentation

1. `?datom_store_s3` and `?datom_store_s3_creds`: the `credentials` argument, the returned list, an
   example function reading keys from the OS keychain (`keyring`), and the credential rule in plain
   words: what datom never reads, what it never stores.
2. A "When credentials run out or leak" section in `?datom_store_s3` covering every failure mode
   R4b marks documented: what the user sees and what to do.
3. The trade-off between the two forms: keys passed directly are the easy route and the way out, and
   a saved session or cache can write them to disk; the function form keeps them out. Recommend
   never saving the workspace (`usethis::use_blank_slate()`).
4. `NEWS.md`: the four breaking changes of R1.2 first, each with what to do instead, and the writer
   floor: the first commit by 0.3.0 makes a repo refuse writers older than 0.3.0. Next to the
   existing "upgrade everyone who writes to a repo at the same time": an out-of-date 0.2.0 clone can
   make one more write after the floor rises, and a write already in flight when it rises lands.
   Then the credential function, the endpoint on the store, and the agreement check before writes.
5. `?datom_store_s3`: the `endpoint` argument (moved from `datom_get_conn()`, with its notes on
   S3-compatible services); `?datom_repo_set_data_store`: its use as the approval of R3.6, that it
   replaces the location fields as a set. The help of each command that raises `min_writer_version`
   says so, and of every command that commits or pushes that it checks it (R3.8).
7. `dev/engineering-notes.md`, next to the writer floor: whoever raises `.datom_min_writer_version`
   bumps `DESCRIPTION`'s `Version` to at least that number in the same change, or `dev` builds and
   the suite refuse their own repos. A comment beside the constant points at the note.
6. **The pattern rule, where every session reads it** (decision 15): a line in the "Don'ts" of
   `.github/copilot-instructions.md`, and the credential case added to "Two ways a condition's class
   silently disappears" in `dev/engineering-notes.md`.

## Out of scope

- The single sign-on helper (its own checklist item on #134).
- `SECURITY.md` and the security article (their own checklist item).
- Pluggable git hosts (#153).
- Any change to how GitHub tokens are handled.

## Decisions

Each is taken one at a time with the owner and recorded here.

1. **Who renews the keys. DECIDED (owner, 2026-10-27): datom does ("option B").** datom keeps the
   current keys and their expiry in its private memory (decision 3), gives paws keys with no expiry
   time, and builds a new client when the keys near expiry. Every use of a stored client goes
   through one accessor (17 lines in four files under `R/` on 2026-10-27; 19 lines in three files
   after #155); a function-built connection has no
   `conn$client`, so a missed use errors at once. The accessor falls back to `conn$client` when the
   connection has no id, so stores built from keys, and the tests' fake clients, are unchanged.
   - **Rejected, "option A"**: replace paws's lookup list with datom's function (F3). Smaller, but
     it rests on a paws setting that is not documented, and if paws stopped honouring it the
     fallback would return **silently**. Under B, every failure found is **loud** (an "expired
     token" or a credential-function error). B relies only on documented behaviour: keys passed with
     no expiry time are used as given.
   - **Known limits of B**, all loud: a job that outlives the user's single sign-on login stops
     partway, as a network failure does today; R5.2's test is the one alarm if paws ever starts
     searching even when it was handed keys with no expiry time.
2. **The server address. DECIDED (owner, 2026-10-27): close it here (R3.4)**: refuse when
   `AWS_ENDPOINT_URL*` is set, always pass the address explicitly, and refuse China regions for now.
   A planted variable would otherwise send signed requests, and the data read back, to another
   server. Cost: a user who points datom at MinIO through that variable must pass `endpoint =`
   instead. (Amended 2026-11-10: the China refusal was replaced by decision 10, the endpoint moved to
   the store by decision 12, and the variable is refused only when the store has no `endpoint`.)
3. **Keys reaching disk through a saved session (F7). DECIDED (owner, 2026-10-27).**
   - **Function form**: the current keys and the paws client live only in a private environment in
     datom's namespace, filed under a random id; the store and the connection hold the id, never a
     key or a client. A probe (2026-10-27, throwaway package, fake keys) showed a saved session
     (`.RData`) holding such a connection contains no key, while a connection holding the
     environment itself or a paws client does. In a fresh R the id is not found, so datom calls the
     function again.
   - **Keys passed directly**: unchanged from today, kept in the store and the connection. This form
     is for users who choose ease over a stricter posture, and is the way out if the function form
     misbehaves. The docs state the risk: a saved session or cache can write the keys to disk.
4. **Call the function at construction when `validate = TRUE`. DECIDED (owner, 2026-10-27): yes
   (R2.3).** A broken function, an expired single sign-on login or no bucket access stops at the
   line that built the store. The keys from that call are reused for the first request.
5. **`datom_store_s3_creds()` accepts a function too. DECIDED (owner, 2026-10-27): yes (R1.3).**
   Without it, single sign-on readers would have to name the bucket themselves and lose the
   governance lookup, including following data that has been moved.
6. **Static keys take the same path? Settled by decision 1.** Keys built into a store go through the
   same client builder (explicit address, no expiry time given to paws), so neither form can fall
   back.
7. **No separate key check before a write. DECIDED (owner, 2026-11-10) (R4a.1).** #155 moved the
   data file upload ahead of every change to the clone, so a login lost partway through a write
   leaves a state the re-run finishes, and the renewal made before each storage request already
   stops a write at its first one. The check R4a.1 first asked for would add nothing.
8. **A credential failure is labelled where datom calls the function, and nothing downstream
   relabels it. DECIDED (owner, 2026-11-10) (R2.7).** In the owner's words: where the error occurs
   at a point we know we are dealing with credential expiry, because we just asked, catch it as
   that, and do not leave it to be caught downstream. Set aside: fixing only the two places in
   connection setup that turn the failure into a warning, which leaves every other message
   misleading and makes `datom_sync()` and scripts dig the failure out of a chain of causes.
9. **Private memory keeps the keys and their expiry only; a paws client is built for each request.
   DECIDED (owner, 2026-11-10) (R4.1).** Chosen as the least code: nothing has to be kept in step
   with the keys after a renewal. Neither cost was a concern: an entry is added per store built (not
   per renewal), about 40 KB with a cached client against about 1 KB without, and building a client
   takes about 1 ms (both measured 2026-11-10).
10. **Which regions datom builds an address for. DECIDED (owner, 2026-11-10) (R3.4).** Only those
    whose S3 address is `s3.<region>.amazonaws.com` (AWS's standard regions and GovCloud), from AWS's
    own region patterns; any other needs `endpoint =`. In the owner's words, US and EU are the
    primary focus; regions outside them may go unsupported, and this rule keeps the standard ones
    that work today at no extra code. Set aside: refusing a list of known odd regions, which gives a
    new odd group a wrong address and a confusing "could not resolve host" error instead of a
    message. (Amended the same day, after the second review: the check first sat where datom builds
    the address, because `endpoint =` was then an argument of `datom_get_conn()`; with the endpoint
    on the store it runs when the store is built, and at connect for a location from `ref.json`.)
11. **`datom_init_repo()` after its push has no exception. DECIDED (owner, 2026-11-10) (R2.7).** A
    credential failure there reaches the caller as everywhere else. Set aside: init's own stop with
    the failure as its cause, which would show "re-run the command" above "running
    `datom_init_repo()` again refuses", since R includes a cause's text in an error's message.
12. **The endpoint belongs to the store. DECIDED (owner, 2026-11-10) (R1.1, R3.4).**
    `datom_store_s3()` takes `endpoint =`, and `datom_get_conn()` loses its `endpoint` argument
    outright, with no stub (owner: "experimental phase, don't like to carry baggage"; an old call
    stops with R's "unused argument"). With the address in the store, every command reads it from
    one place, `datom_init_repo()` and `datom_clone()` included, which had no way to take one; the
    address checks run when the store is built; and data and governance can sit on different
    services. Set aside: an init-only up-front address check with endpoint support deferred, which
    would have been temporary code and left `datom_init_repo()` and `datom_clone()` unable to reach
    MinIO meanwhile; keeping `datom_get_conn(endpoint = )` as an override or a fallback, which leaves
    two places to set the address.
13. **`ref.json` records the endpoint; the credentials-only store takes none. DECIDED (owner,
    2026-11-10) (R1.3, R3.4).** So a move to another service is as seamless as a move to another
    bucket, which is what `ref.json` is for. `.datom_create_ref()` writes `endpoint`, and
    `.datom_parse_ref()` reads it. Set aside: the reader's own `endpoint =` on the credentials-only
    store (a move to another service would need every reader to change it), and no endpoint for that
    store at all. The security cost, a document in storage deciding where requests go, is already
    paid for buckets today; decision 14 adds the second record for writes.
14. **Writes need governance and the data repo to agree; readers are told about a non-AWS location.
    DECIDED (owner, 2026-11-10) (R3.6, R3.7).** The owner asked for a "two factor mindset": a change
    in one place must agree with another for it all to work. For writes, `project.yaml` in the data
    repo is that second place, so a change to `ref.json` alone cannot send a developer's data
    elsewhere. Approval is a one-time command (`datom_repo_set_data_store()`), not a question, since
    scripts and a product layer cannot answer one. For reads there is no cheap second record, so
    datom makes the location visible. In the owner's words the gain is mild, and worth it at this
    scope; the check closes a gap that exists today for a developer using the credentials-only store.
    Amended 2026-11-11 (owner, review 3): connecting warns, so a developer's reads follow `ref.json`
    like a reader's, a deliberate loosening of today's stop at connect.
15. **The pattern rule is written down and checked. DECIDED (owner, 2026-11-10) (R5.7, R6.6).** The
    pass-on line and `lapply()` are the only safe forms around code that can reach the credential
    function. The rule goes into the always-loaded conventions and the engineering note, comments sit
    at each site, and a code-reading test (about a second of CI, deterministic) fails on a new loop or
    handler that breaks it. The design had broken the engineering note's rule while the note was
    only loaded on demand.
16. **The writer floor is a fixed `0.3.0`, raised by a 0.3.0 build (where: decision 19). DECIDED
    (owner, 2026-11-12) (R3.8).** Replaces the decision of 2026-11-11 (a floor only where an
    endpoint is recorded, chosen to keep 0.2.0 teammates writing plain-AWS repos), and #155's D11
    (mixed-version teams not guarded) for every repo a 0.3.0 build commits to: the owner is cutting
    0.2.0 loose. A constant, not the running version, so a repo created by a later release does not
    refuse earlier ones that work. `0.3.0`, not the review's `0.2.1`, because a CRAN fix of 0.2.0
    made from `main` would be numbered 0.2.1 and lack this feature. The check runs at the start of
    every command that commits or pushes, where today only the write routes check.
17. **One shape for a data location. DECIDED (owner, 2026-11-11) (R3.9).** In the owner's model,
    governance changes `ref.json` first, the project owner carries the change into `project.yaml`
    with `datom_repo_set_data_store()`, and nothing about the location may be ambiguous afterwards.
    So one builder makes every location record, the repoint replaces it as a set, and one comparer
    decides "same location". Set aside: the owner's first idea, an endpoint replacing the region,
    because AWS signatures name a region.
18. **No floor re-check at the push. DECIDED (owner, 2026-11-12) (R3.8).** The review proposed
    checking the floor again inside `.datom_git_push()`, after its pull, and undoing the command's
    local commit when it refuses. Set aside: it would be the one refusal after a commit, against
    #155's rule that work found after its commit is finished; the undo must remove the commit after
    a merge without wiping the user's other uncommitted files, which is new recovery code; and
    without the undo the check gains nothing, since the upgraded re-run would publish the commit
    anyway. It closes a window as long as one write in flight, which opens only when a later release
    raises the floor, narrower than the 0.2.0 exposure already accepted. That one write lowers
    nothing: it does not change `project.yaml`, so its push carries the merged, higher floor.
19. **The floor is raised only where data is written. DECIDED (owner, 2026-11-12) (R3.8).** At init,
    at the opening pull of a write route (once per `datom_sync()`), and inside
    `datom_repo_set_data_store()`'s own commit. `datom_repo_commit()` and
    `datom_repo_attach_governance()` only check. Set aside: raising inside every committing command's
    own commit, or a separate raise commit refused when files are staged. The floor needs to be on
    GitHub only before an old build can write data, which only the write routes do. Amended the
    same day (owner, review 6): every raise goes into the command's own commit, never a commit of
    its own, since `.datom_git_commit()` commits the whole index and a separate commit would carry
    the user's staged files on every route, while reaching GitHub no sooner.

## Parity with datom-py

Owner, 2026-10-27: whatever R settles here is passed on to datom-py afterwards, as its own issue and
PR (one repo per change). Points to carry over:

| Point | R (this spec) | datom-py 0.1.0 today |
|---|---|---|
| Who renews | datom, before each request, 15 minutes early | botocore's refreshable credentials, through botocore internals (option A) |
| `AWS_ENDPOINT_URL*` set | Refused when the store has no `endpoint`, naming the variable | Silently ignored |
| Where the endpoint is given | On the store; with governance, from `ref.json` | No endpoint argument; standard AWS only (read in `src/datom/_s3.py`, 2026-11-10) |
| `ref.json`'s `endpoint` field | Read and followed | datom-py does not read `ref.json` (no governance lookup); nothing to carry until it does |
| Location from `ref.json` not standard AWS | A message at connect | None |
| Writes and the governance location | Must agree with `project.yaml` | Not applicable: datom-py never writes |
| Configured endpoints otherwise | Address always passed explicitly | Ignored through a botocore setting |
| Regions whose S3 address is not `s3.<region>.amazonaws.com` (China, government clouds, EU Sovereign Cloud) | Refused unless `endpoint =` is given | Resolved by botocore |
| Saved store or connection holds keys | Function form: no, keys live in private memory under an id; keys form: yes, documented | Open (its pickling task) |
| First call of the function | At store construction when the bucket is checked | At connect |
| Renewal fails 10-15 minutes before expiry | Stops at once with `datom_credentials_failed` | botocore (1.43) treats 15 minutes as advisory: a failed refresh is logged and the held keys are used until the mandatory point, 10 minutes before expiry |
| A credential failure inside a command | Reaches the caller as itself, never relabelled (R2.7) | Not checked |

## Acceptance criteria

| ID | Criterion | Requirement |
|---|---|---|
| AC1 | A store builds from a function or from keys; both, or neither, is refused | R1 |
| AC2 | Each malformed or expired result is refused with `datom_credentials_invalid`, echoing no value | R2.4 |
| AC3 | An error in the function surfaces as `datom_credentials_failed`, with the original as parent | R2.5 |
| AC4 | With wrong credentials planted in every ambient source, requests carry only the store's credentials, for both forms and every client | R3 |
| AC5 | The function is not called at construction under `validate = FALSE`, and is called again near expiry | R2.3 |
| AC6 | A function-built store and connection print, serialise and save (`.RData`) with no key or token, after requests too; in a fresh R the function is called again | R4 |
| AC7 | `AWS_ENDPOINT_URL*` set with no `endpoint` on the store is refused; otherwise requests go only to the location's endpoint or the standard address; a region with no standard `amazonaws.com` address is refused when no `endpoint` is given and accepted with one; both refusals come at store construction, or at connect for a location from `ref.json` | R3.4 |
| AC8 | A credential failure at each storage request of a write, in turn, followed by the same command re-run, leaves git and storage as one uninterrupted run would; a credential failure ends `datom_sync()`, which first says which tables it synced | R4a |
| AC9 | Every failure mode in R4b marked guarded has its test, and every one marked documented appears in `?datom_store_s3` | R4b, R6.2 |
| AC10 | Each test for AC1-AC9 and AC11-AC16 is recorded going red when its guard alone is removed | R5.3 |
| AC11 | For each command, a credential failure at its 1st, 2nd, 3rd... storage request reaches the caller as `datom_credentials_failed` itself, not as the cause of another error, with datom's message | R2.7 |
| AC12 | With governance attached, every write route stops before changing anything when `ref.json`, `project.yaml` and the connection disagree on location; `datom_get_conn()` warns instead of stopping; after `datom_repo_set_data_store()` the write goes through | R3.6 |
| AC13 | A location from `ref.json` that is not standard AWS S3 produces a message at connect; one from the caller's own store does not | R3.7 |
| AC14 | The code-reading test passes on the finished code and fails when one pass-on line is removed or one `lapply()` turned back into `purrr::map()` | R5.7 |
| AC15 | `min_writer_version` is written by init and raised to `0.3.0` by a write or `datom_repo_set_data_store()`, never lowered; every command that commits or pushes refuses before changing anything when the floor is above the installed version | R3.8 |
| AC16 | After a move off MinIO, from S3 to a local folder, or onto MinIO, approved once, the next write goes through; every writer of a location record agrees with the others for the same store | R3.9 |
