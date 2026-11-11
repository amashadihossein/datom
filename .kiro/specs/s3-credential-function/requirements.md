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
FM14, FM15, FM16, AC7, AC11 and decision 2 changed; decisions 10 and 11 added.
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

1. `datom_store_s3()` gains `credentials`, a function, added after the existing arguments so
   positional calls keep working. A store is built from **either** `credentials` **or**
   `access_key` + `secret_key` (+ `session_token`), never both; giving both, or neither, stops with a
   message naming the two forms.
2. `access_key` / `secret_key` / `session_token` keep working exactly as in 0.2.0.
3. `datom_store_s3_creds()` (the credentials-only component used with governance) gets the same
   `credentials` argument and the same either/or rule (decision 5), so single sign-on readers keep
   the governance lookup of where the data lives.

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
4. The server address a request goes to also depends only on datom's arguments (decision 2):
   - if `AWS_ENDPOINT_URL_S3` or `AWS_ENDPOINT_URL` is set, building an S3 store or connection
     stops with a message naming the variable and pointing at `datom_get_conn(endpoint = )`;
   - every client datom builds is given the address explicitly: the `endpoint` the caller passed, or
     the standard AWS address for the store's region, keeping today's bucket-address style. That
     closes `endpoint_url` in `~/.aws/config` too, which datom cannot check without reading the file;
   - datom builds the standard address only for regions whose S3 address is
     `s3.<region>.amazonaws.com`: AWS's standard regions and GovCloud (decision 10). For any other
     region (China, the US government secret clouds, the EU Sovereign Cloud, a made-up region name),
     a client built with no `endpoint` stops, naming the region and `datom_get_conn(endpoint = )`.
     With an `endpoint`, any region is accepted. `datom_store_s3(validate = TRUE)` checks the bucket
     at the address datom builds, so for such a region it stops and says to use `validate = FALSE`
     and pass `endpoint =` at connect. (Until 2026-11-10 this item refused China regions at the store,
     which blocked `endpoint =` as the way out.)
5. Region already comes only from the store.

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
| FM7 | `AWS_ENDPOINT_URL*` set, or `endpoint_url` in `~/.aws/config` | Refused, or overridden by the explicit address | test | yes |
| FM8 | The function returns malformed or expired keys, or raises | `datom_credentials_invalid` / `datom_credentials_failed`, no value echoed | test | yes |
| FM9 | Local clock wrong by more than the 15-minute margin | AWS refuses the request | | yes |
| FM10 | Session saved (`.RData`, a cache) with a function-built store or connection | No key in the file; a fresh R calls the function again | test | yes |
| FM11 | Session saved with a store built from keys passed directly | The keys are in the file | | yes |
| FM12 | Connection sent to a fresh-process parallel worker | The worker calls the function once; on macOS the keychain may prompt per process. A function that uses the caller's global variables fails there with "object not found" (R4.1) | test | yes |
| FM13 | Keys held in the user's own variables, or written literally inside the function | Saved with the session; outside datom's control | | yes |
| FM14 | The function returns keys with 15 minutes or less left: keys that live that briefly (an assumed role at its 15-minute minimum), or a source that keeps handing back the same keys until just before they expire (a cache another tool refreshes late) (added 2026-11-10, widened the same day) | Works, but datom calls the function before every request while the keys it returns have 15 minutes or less left; a function that assumes a role on each call may be slowed or throttled by AWS | | yes |
| FM15 | A datom error handler, or a `purrr` loop that reaches storage, added later without letting credential failures through (added 2026-11-10) | A misleading message, as in the examples in `design.md` section 5 | test (R2.7), for the commands it covers | |
| FM16 | Login expires during `datom_init_repo()` after its push (added 2026-11-10, reworded the same day) | The credential failure. Re-running `datom_init_repo()` after logging in refuses and names the repair (`datom_get_conn()`, then `datom_validate(conn, fix = TRUE)`) | test | yes |

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
   (R4a.1). Added 2026-11-10.

### R6. Documentation

1. `?datom_store_s3` and `?datom_store_s3_creds`: the `credentials` argument, the returned list, an
   example function reading keys from the OS keychain (`keyring`), and the credential rule in plain
   words: what datom never reads, what it never stores.
2. A "When credentials run out or leak" section in `?datom_store_s3` covering every failure mode
   R4b marks documented: what the user sees and what to do.
3. The trade-off between the two forms: keys passed directly are the easy route and the way out, and
   a saved session or cache can write them to disk; the function form keeps them out. Recommend
   never saving the workspace (`usethis::use_blank_slate()`).
4. A `NEWS.md` line.

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
   server. Cost: a user who points datom at MinIO through that variable must pass `endpoint =` to
   `datom_get_conn()` instead. (The China refusal was replaced on 2026-11-10 by decision 10.)
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
    own region patterns; any other needs `endpoint =`. The refusal sits where datom builds the
    address, not in the store constructor, so `endpoint =` always works as the way out. In the
    owner's words, US and EU are the primary focus; regions outside them may go unsupported, and this
    rule keeps the standard ones that work today at no extra code. Set aside: refusing a list of
    known odd regions, which gives a new odd group a wrong address and a confusing "could not
    resolve host" error instead of a message.
11. **`datom_init_repo()` after its push has no exception. DECIDED (owner, 2026-11-10) (R2.7).** A
    credential failure there reaches the caller as everywhere else. Set aside: init's own stop with
    the failure as its cause, which would show "re-run the command" above "running
    `datom_init_repo()` again refuses", since R includes a cause's text in an error's message.

## Parity with datom-py

Owner, 2026-10-27: whatever R settles here is passed on to datom-py afterwards, as its own issue and
PR (one repo per change). Points to carry over:

| Point | R (this spec) | datom-py 0.1.0 today |
|---|---|---|
| Who renews | datom, before each request, 15 minutes early | botocore's refreshable credentials, through botocore internals (option A) |
| `AWS_ENDPOINT_URL*` set | Refused, naming the variable | Silently ignored |
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
| AC7 | `AWS_ENDPOINT_URL*` set is refused; otherwise requests go only to the given or standard address; a region with no standard `amazonaws.com` address is refused when no `endpoint` is given and accepted with one | R3.4 |
| AC8 | A credential failure at each storage request of a write, in turn, followed by the same command re-run, leaves git and storage as one uninterrupted run would; a credential failure ends `datom_sync()`, which first says which tables it synced | R4a |
| AC9 | Every failure mode in R4b marked guarded has its test, and every one marked documented appears in `?datom_store_s3` | R4b, R6.2 |
| AC10 | Each test for AC1-AC9 and AC11 is recorded going red when its guard alone is removed | R5.3 |
| AC11 | For each command, a credential failure at its 1st, 2nd, 3rd... storage request reaches the caller as `datom_credentials_failed` itself, not as the cause of another error, with datom's message | R2.7 |
