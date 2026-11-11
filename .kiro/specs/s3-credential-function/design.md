# Design -- S3 credential function

**Status (2026-11-10)**: ready for the owner's review, **not approved**. Drafted 2026-10-27, paused
for [#155](https://github.com/amashadihossein/datom/issues/155), resumed once #155 merged into `dev`
(PR #159). The "Not yet traced" list of the draft was finished with the owner on 2026-11-10; where
each item landed is in section 13. A review of `53b4a71` the same day was evaluated with the owner
point by point and its outcomes are applied here; the record is section 14.

Read first: `requirements.md` (approved 2026-10-27, amended twice on 2026-11-10). Decisions 1-11
referred to here are recorded there; DD1 and the choices in section 8 are this document's.

## 1. The shape

The keys of a function-built store exist only in a private environment inside datom's namespace,
which R never writes when a session or object is saved: it writes a reference to the namespace by
name. Every storage request asks one function, `.datom_s3_get_client()`, for a client. For a
function-built connection it renews the keys if they are due, builds a paws client from them, and
the client is used for that request and dropped (decision 9). datom alone decides when to renew.

```
datom_store_s3(credentials = fn, validate = TRUE)
  -> new id (unique across R sessions, section 4)
  -> call fn, check the result, file keys + expiry under the id      (decision 4)
  -> HeadBucket through a client built from them
  -> store { bucket, prefix, region, cred_id, credentials = fn }

datom_get_conn(store = ...)
  -> connection { ..., cred_id, credentials = fn }   no client field

each storage request -> .datom_s3_get_client(conn)
  -> connection has no cred_id                  -> conn$client (keys form; tests' fake clients)
  -> keys held, 15+ minutes left or no expiry   -> build a client from them
  -> no keys held (fresh R, fresh-process worker),
     or 15 minutes or less left                 -> call fn, check, file under the same id, build
  -> fn raises, or returns something unusable   -> datom_credentials_failed / _invalid,
                                                   passed on by every handler above (section 5)
```

## 2. What each object holds

| Object | Function form | Keys form (unchanged from 0.2.0) |
|---|---|---|
| Store (`datom_store_s3`) | bucket, prefix, region, `cred_id`, `credentials` (the function), `validated` | bucket, prefix, region, keys, `validated` |
| Store (`datom_store_s3_creds`) | `cred_id`, `credentials` | keys |
| Connection | as today, but `cred_id` + `credentials` (and `gov_cred_id` + `gov_credentials`) instead of `client` / `gov_client` | as today, with `client` / `gov_client` |
| Private memory (`.datom_cred_registry`) | per id: the current keys and their expiry (`POSIXct`, or `NULL` for keys that do not expire) | nothing |

No object, in either form, holds a paws client for a function-built store: one is built per request
and goes out of scope with it.

## 3. Functions, by file

The capability lives in one new file, `R/credentials.R` (owner's preference for new cross-cutting
code in its own file, recorded 2026-10-28). The S3 client builder stays with its backend peers in
`R/utils-s3.R`; each command keeps only a thin call.

| File | Function | New / changed | Does |
|---|---|---|---|
| `R/credentials.R` | `.datom_cred_registry` | new | `new.env(parent = emptyenv())` at namespace level: id -> current keys and expiry |
| `R/credentials.R` | `.datom_cred_new_id()` | new | An id unique across R sessions (section 4) |
| `R/credentials.R` | `.datom_cred_keys(id, fn)` | new | The keys to sign with: the held ones when 15+ minutes are left (or they never expire); otherwise calls `fn` through `.datom_cred_call()` and files the result under `id` |
| `R/credentials.R` | `.datom_cred_call(fn)` | new | Calls `fn` with no arguments. An error becomes `datom_credentials_failed`, the original as parent (R2.5); the result goes through `.datom_check_cred_result()` |
| `R/credentials.R` | `.datom_check_cred_result(x)` | new | R2.4: refuses with `datom_credentials_invalid`, naming the field and the problem, never a value; returns the keys with `expiration` as `POSIXct` or `NULL` |
| `R/credentials.R` | `.datom_pass_credentials(e)` | new | Raises `e` again, unchanged, when it is a credential failure (class `datom_credentials_error`); otherwise returns. The first line of every catch-all error handler in section 5. Looks at `e` itself only, not its causes (section 14, point 2) |
| `R/credentials.R` | `.datom_s3_get_client(conn)` | new | The accessor in section 1. Reads `conn$region` and `conn$endpoint` for the client it builds (DD1) |
| `R/utils-s3.R` | `.datom_check_endpoint_env()` | new | R3.4: stops when `AWS_ENDPOINT_URL_S3` or `AWS_ENDPOINT_URL` is set, naming the variable and `datom_get_conn(endpoint = )` |
| `R/utils-s3.R` | `.datom_s3_standard_address(region)` | new | The address `https://s3.<region>.amazonaws.com`, for a region in section 6's list; otherwise stops, naming the region and `datom_get_conn(endpoint = )` (decision 10) |
| `R/utils-s3.R` | `.datom_s3_client()` | changed | Keys with no expiry time given to paws, as today. Always an explicit address: the caller's `endpoint`, else `.datom_s3_standard_address()` (section 6); calls `.datom_check_endpoint_env()` |
| `R/utils-s3.R` | the 9 wrappers, 11 client uses (`.datom_s3_upload()`, `_upload_absent()`, `_download()`, `_exists()`, `_read_json()`, `_write_json()`, `_list_objects()`, `_delete_prefix()`, `_object_sha256()`) | changed | `client <- .datom_s3_get_client(conn)` **above** each `tryCatch()`, so a credential failure is never reworded as "Failed to upload file to S3" (section 5) |
| `R/storage.R` | `.datom_copy_one()` | changed | Gets the source and destination clients before its handler, each only when that side is S3 (section 14, point 4) |
| `R/storage.R` | `.datom_storage_byte_size()`, `.datom_storage_content_hash()` | changed | Their client uses go through the accessor; `datom_storage_verify()` reaches them |
| `R/storage.R` | `datom_storage_copy()`, `datom_storage_verify()` | changed | Their loops use `lapply()` (section 5) |
| `R/store.R` | `datom_store_s3()` | changed | Gains `credentials` after `validate` (R1.1); either/or rule; calls `.datom_check_endpoint_env()` at construction (fail early); with `validate = TRUE` makes the id, gets the keys through `.datom_cred_keys()` **before** the bucket check's handler, and checks the bucket at the address `.datom_s3_standard_address()` gives. A region outside section 6's list stops there, saying to use `validate = FALSE` and pass `endpoint =` at connect |
| `R/store.R` | `datom_store_s3_creds()` | changed | Gains `credentials` (R1.3); makes the id; does not call the function (R2.3) |
| `R/store.R` | `.datom_validate_s3_store()` | changed | Takes a client built by `.datom_s3_client()` instead of building its own (it passed no address) |
| `R/store.R` | `print.datom_store_s3()`, `print.datom_store_s3_creds()` | changed | Function form: "Credentials: from a function" |
| `R/conn.R` | `new_datom_conn()` | changed | Gains `cred_id`, `credentials`, `gov_cred_id`, `gov_credentials`; `client` optional |
| `R/conn.R` | `.datom_build_init_conn()` | changed | Function-form component: carries its id and function, builds no client |
| `R/conn.R` | `.datom_conn_for()` | changed | The governance view carries `gov_cred_id` / `gov_credentials` as its `cred_id` / `credentials` |
| `R/conn.R` | `.datom_get_conn_developer()`, `.datom_get_conn_reader()` | changed | The credentials-only store rebuilt with the location from `ref.json` keeps the original store's id and function (it rebuilt from `store$data$access_key` and friends) |
| `R/conn.R` | `print.datom_conn()` | changed | Function form: "Credentials: from a function" |
| `R/ref.R` | `.datom_build_gov_resolve_conn()` | changed | Carries the governance store's id and function |
| `R/ref.R` | `.datom_check_data_reachable()` | changed | Gets its client through the accessor, **before** its handler (section 14, point 4). Today it returns early when `conn$client` is `NULL`, which a function-built connection always is, so the check would stop checking for every one of them (FM5). The early return stays only for a connection with no id whose client is not a paws client (the tests' fakes) |
| `R/heal.R` | `.datom_publish_artifacts()` | changed | Before it raises or returns the failures it collected, raises a credential failure among them on its own, so heal's "Could not finish publishing" and the repair's report never hold one |
| `R/sync.R` | `datom_sync()` | changed | On a credential failure: says which tables were synced and which were not attempted, then passes the failure on (R4a.2) |
| `R/utils-path.R` | `.datom_render_readme()`, `.datom_store_constructor_snippet()` | changed | The README of a repo set up with a function-built store shows `credentials = <your function>` instead of `access_key = "..."` |
| 5 files | 7 `purrr` loops that reach storage | changed | `lapply()`, with a comment saying why (section 5) |
| 16 files | 30 error handlers | changed | The first line of the catch-all calls `.datom_pass_credentials(e)` (section 5) |

## 4. When the function is called

- **First call**: at `datom_store_s3(validate = TRUE)`, for the bucket check; its keys are kept for
  the first request (decision 4). Otherwise, at the first storage request, which `datom_get_conn()`
  makes when it checks the data store can be reached.
- **Renewal**: before each storage request, when the held keys have 15 minutes or less left (R2.3).
  A long job renews as it goes.
- **Keys with no `expiration`** (static keys read from the keychain): the function is called once per
  id and never again in that R session.
- **One call per id, not per function.** A data and a governance component built from the same
  function each get their own id, so each calls it. Accepted: two calls per session.
- **Keys returned with 15 minutes or less left** (FM14): keys that live that briefly, or a source
  that hands back the same keys until just before they expire. They are due as soon as they arrive,
  so the function is called before every request until it returns fresher keys. Documented, not
  handled: AWS's shortest assumed-role session is 15 minutes, and handling it would need a second
  rule.
- **The id is unique across R sessions**: built from the clock to the microsecond, the process id and
  a counter. No random numbers, so the caller's random seed is untouched. It must not repeat across
  sessions because a connection loaded from a saved session would otherwise find keys a different
  store filed in the new session, and sign its requests with another account's keys.
- **A fresh-process parallel worker** receives the function without the caller's global variables,
  so the help says to write it self-contained: packages called as `keyring::key_get()`, no global
  variables (FM12; checked 2026-11-10).

## 5. A credential failure reaches the caller as itself (R2.7, decision 8)

**Labelled where datom calls the function.** `.datom_cred_call()` is the one place datom knows a
failure is a credential failure, so it labels it there:

| Class | When | Message |
|---|---|---|
| `datom_credentials_failed` (and `datom_credentials_error`) | the function raised an error | "The credential function failed." Then: if you use single sign-on, log in again (for example `aws sso login`) and re-run the command; a re-run finishes whatever this one left unfinished. The function's error is attached as the parent, never pasted in |
| `datom_credentials_invalid` (and `datom_credentials_error`) | the result is unusable or already expired (R2.4) | names the field and the problem, never a value |

**Nothing downstream relabels it.** Labelling at the source is not enough on its own: the handlers
between storage and the caller catch every error, labelled or not. Three mechanisms keep it intact,
each following "Two ways a condition's class silently disappears" in `dev/engineering-notes.md`.

**1. Handlers: the catch-all's first line passes it on** (section 14, point 1).

```r
tryCatch(
  .datom_storage_read_json(conn, key),
  error = function(e) {
    .datom_pass_credentials(e)   # must stay the first line: a credential failure goes on unchanged
    ...today's handling of any other error...
  }
)
```

This works because by the time the catch-all runs its `tryCatch()` has finished, so the error raised
again goes past it. It must **not** be written as a second handler beside `error =`
(`datom_credentials_error = function(e) stop(e)`): R nests the handlers of one `tryCatch()`, the
last listed outermost, so `error =` catches what the other raises and rewords it (checked
2026-11-10; the engineering note marks that spelling WRONG). An outer datom handler has the same
first line, so the failure passes it too.

**2. Get the client before the handler, where the request is datom's own.** The S3 wrappers in
`R/utils-s3.R`, the connect-time reachability check and the copy of one object get their client
before their `tryCatch()`, so a credential failure never enters those handlers and they need no
line. For the reachability check this also matters because it sorts errors by searching their text
for "403" or "NotFound", and R includes a cause's text in an error's message: a credential function
whose own error mentioned "NotFound" would otherwise be reported as a missing bucket.

**3. Loops: `lapply()`, not `purrr`.** `purrr::map()`, `walk()`, `map_lgl()`, `imap()` and `keep()`
re-raise any error from the mapped function as their own (`purrr_error_indexed`), with the original
only as its cause (checked on purrr 1.2.1, 2026-11-10). A caller's `tryCatch()` matching the
credential class then never fires, and `.datom_pass_credentials()` does not recognise it. The seven
loops that reach storage use `lapply()`, with a comment saying why, as `R/set.R` and `R/sync-set.R`
already do:

| Command | Loop (function) |
|---|---|
| `datom_storage_copy()` | over objects (`datom_storage_copy()`) |
| `datom_storage_verify()` | over objects (`datom_storage_verify()`) |
| `datom_validate()` | over files (`.datom_validate_repo_files()`) and over tables (`.datom_validate_tables()`) |
| `datom_validate(fix = TRUE)` | over set payloads to restore (`.datom_repair_restore_payloads()`) |
| `datom_projects()` | over projects (`datom_projects()`) |
| `datom_update_members()` | over members to repoint, which reads storage through `datom_member()` |

`.datom_publish_artifacts()` already catches each artifact's failure into a value inside its loop;
it raises a credential failure among them before reporting the rest (section 3).

**The handlers that get the line** (read on 2026-11-10; the sweep test below is what proves the list
complete for each command):

| File | Handlers | What each does with an error today |
|---|---|---|
| `R/ref.R` | 3 | The governance lookup of the data location warns and carries on; reading `ref.json` and the write-time location check reword it as a stop |
| `R/sync.R` | 4 | The per-table handler rewords it or moves on to the next table; the manifest read returns "unreadable"; the manifest rebuild returns a failed result; the set-payload restore rewords it |
| `R/validate.R` | 3 | The stored manifest, a table's documents and a set's payload read as "nothing to compare" or empty |
| `R/storage.R` | 2 | Verify rewords the source's size read, and reads a failed destination size as missing |
| `R/heal.R` | 1 | The stored-manifest check returns "unreadable", which stops a write ("Could not read the stored manifest") or holds back the manifest with a warning |
| `R/manifest-rebuild.R` | 2 | A history or set payload that fails to read is left out of the rebuilt row |
| `R/version-commit.R` | 2 | The stored history reads as "unreadable" |
| `R/utils-validate.R` | 2 | The namespace check at init rewords it as a refusal, or prints "unreadable" |
| `R/set.R` | 2 | A member snapshot read is reworded; a member's fetch adds a project-mismatch hint |
| `R/query.R` | 2 | "No version history found for table"; the metadata read is reworded |
| `R/conn.R` | 2 | A reader's check for `governance.json` treats it as absent; `datom_init_repo()`'s manifest upload after its push rewords it as its own stop (decision 11) |
| `R/member.R` | 1 | A snapshot read is reworded |
| `R/lineage.R` | 1 | "Parent ... not found in project" |
| `R/projects.R` | 1 | Skips the project with a warning |
| `R/utils-gov.R` | 1 | Listing projects is reworded |
| `R/repo.R` | 1 | The `governance.json` upload warns and carries on |

Two cases from the discussion, as a user would meet them without these mechanisms: a reader using
`datom_store_s3_creds()` whose login has expired gets a warning about `ref.json` and then a stop
telling them to update the governance clone (`datomanager::gov_pull()`); a developer partway through
a session gets "Could not read the stored manifest... if the file itself is damaged, run
`datom_validate(fix = TRUE)`", which fails the same way. Neither says to log in.

**`datom_sync()`** (R4a.2): its per-table handler's first line, on a credential failure, prints which
tables were synced and which were not attempted (the shape `.datom_inform_sync_stopped()` already
prints), then passes the failure on. Nothing else in the sync changes.

**`datom_init_repo()` after its push** (decision 11): no exception. Its manifest-upload handler gets
the line like the others. The user logs in again and re-runs `datom_init_repo()`, which refuses
because the folder is initialised and names the repair: `datom_get_conn("<path>", store)`, then
`datom_validate(conn, fix = TRUE)` (`.datom_check_init_folder_free()` in `R/conn.R`).

**Not covered** (R2.7): AWS refusing keys datom believed good. datom only sees AWS's reply there, so
those stay ordinary storage errors, as today.

**The test (R5.6, AC11).** On the local backend, with the fixtures #155 built (`helper-interrupt.R`),
the storage dispatch functions in `R/utils-storage.R` and the three helpers in `R/storage.R`
(`.datom_copy_one()`, `.datom_storage_byte_size()`, `.datom_storage_content_hash()`) are replaced by
a stand-in that raises a `datom_credentials_failed`, built by the real constructor, on the Nth call
counted across all of them, and records whether it fired. Each exported function that reaches
storage (enumerated from `NAMESPACE` in the task list) runs with N = 1, 2, 3... Three rules, so the
test cannot pass with the fault in place (section 14, point 3):

1. **The error itself is checked, not its causes**: `expect_error(class = "datom_credentials_failed",
   inherit = FALSE)`. testthat's default also matches the class of an error's causes, and nearly
   every handler that rewords keeps the original as its cause, so the default passes on a reworded
   error; matching the message text has the same problem.
2. **A run in which the stand-in fired and the command returned normally fails the test**, with or
   without a warning: that is a handler swallowing the failure.
3. **The sweep for a command ends at the first N where the stand-in did not fire**: the command made
   fewer than N storage requests.

For `datom_write()`, `datom_write_set()`, `datom_sync()` and `datom_validate(fix = TRUE)`, the same
call is then re-run with the stand-in removed, and the clone, the git remote and storage are compared
with an uninterrupted run (R4a.1, AC8). Injecting above the S3 wrappers is deliberate: the handlers
live above them. Replacing `.datom_copy_one()` whole loses nothing, since its client is fetched
before its handler. Unit tests, with a fake client, pin that each S3 wrapper, the reachability check
and the copy get their client before their handler. Guard probe: deleting one handler's first line
must turn the test red for a command that reaches that handler.

## 6. The server address (R3.4, decisions 2 and 10)

- **`.datom_s3_client()` always passes an address.** With no `endpoint`, it passes
  `.datom_s3_standard_address(region)` and `s3_virtual_address = TRUE`. With the caller's `endpoint`,
  it passes that, **without** the flag, and accepts any region.
- **Which regions get a standard address** (decision 10): those whose S3 address is
  `s3.<region>.amazonaws.com`, matched by AWS's own region patterns for its standard group
  (`^(us|eu|ap|sa|ca|me|af|il|mx)-\w+-\d+$`) and for GovCloud (`^us-gov-\w+-\d+$`), as listed in
  botocore's `endpoints.json` and paws.common's endpoint table. Every other region, with no
  `endpoint`, stops with a message naming the region and `datom_get_conn(endpoint = )`. That covers
  China (`amazonaws.com.cn`), the US government secret clouds (`us-iso-*`, `us-isob-*`, `us-isof-*`),
  `eu-isoe-*`, the EU Sovereign Cloud (`eusc-de-*`, `amazonaws.eu`) and made-up names. The check sits
  where the address is built, not in the store constructor, because `endpoint =` is an argument of
  `datom_get_conn()`: a check in the store would refuse a caller who passes the right address at
  connect. A region AWS adds under a new prefix is refused, with the same way out, until datom adds
  it.
- **Why the flag, and only for datom's own address.** paws treats any explicit address as a custom
  one, and for a custom address puts the bucket in the path unless `s3_virtual_address` is `TRUE`
  (`update_endpoint_for_s3_config()` in paws.common 0.8.8, read 2026-11-10, unchanged on paws's
  GitHub main, 0.10.0). With the flag, the bucket stays in the hostname, as today; bucket names that
  cannot go in a hostname stay in the path, as today. A caller's own `endpoint` (MinIO and similar)
  keeps the path style it gets today.
- **Region redirects.** When AWS answers that a bucket is in another region, paws picks the new
  address from its own built-in endpoint table for that region and signs again with the same keys
  (`s3_redirect_from_error()`, read 2026-11-10). No environment variable or config file is read, so
  every address a client can switch to is a standard AWS one.
- **`AWS_ENDPOINT_URL*`** is checked at both S3 store constructors, so the refusal comes at the line
  that built the store, and again in `.datom_s3_client()`, in case it is set later.
- **Newer paws.** paws.common 0.9.0 can switch to a dualstack address through
  `AWS_USE_DUALSTACK_ENDPOINT`; passing the address explicitly shuts that out too (paws's NEWS, read
  2026-11-10).

## 7. How this meets #155 (replaces the draft's "Depends on #155")

Since #155, a write runs: the reads at its start (the stored manifest; change detection), then
1 data file to storage, 2 the clone's files, 3 commit, 4 push, 5 metadata, history and snapshot to
storage, 6 manifest to storage. With renewal before every storage request:

| Login expires during | Readers see | Way out |
|---|---|---|
| the reads at the start, or step 1 | the previous version; the clone unchanged, apart from a pull of teammates' commits and a reset of this table's own leftovers from an earlier broken run, both of which a re-run repeats anyway | log in, re-run |
| steps 2-4 | cannot happen: no storage request | -- |
| steps 5-6 | the previous version; the new one is on GitHub | log in, re-run the same command, which publishes it |

So no separate key check is needed before a write (decision 7). `datom_sync()` still needs R4a.2:
its default carries on to the next table when a write failed before changing the clone, which is
exactly where an expired login fails.

## 8. Design decisions and choices

**DD1. Region after a data migration. DECIDED (owner, 2026-11-10).** When `ref.json` points at a new
location, `datom_get_conn()` overwrites the connection's region after building the keys-form client,
which keeps the old region and relies on AWS's redirect (section 6). A function-built connection
builds each client from `conn$region`, so it uses the new region directly. The keys form is left as
it is. No released tool can create this state; moving data is datomanager's, which is not released.
paws.common 0.10.0 remembers a bucket's region after a redirect, but not for an explicit address, so
a keys-form connection in that state is redirected on every request: slower, still correct.

**Choices in this document, for the review** (each with what it costs):

| Choice | Taken | Alternative |
|---|---|---|
| Where the code goes | `R/credentials.R`, a new file for the capability | Spread over `R/utils-s3.R` and `R/store.R`: no new file, but the capability in pieces |
| FM5's guard | A test that reads the files under `R/` and fails if the stored client (`$client`, `$gov_client`) is named outside the accessor, the connection constructor and `.datom_conn_for()` | A test per call site: 19 tests, and none for a site added later |
| The id | Clock, process id, counter (section 4) | A random string: touches the caller's random seed unless saved and restored |
| The region patterns | AWS's own, copied from its endpoint list, with the source named beside them | Read paws's endpoint table at run time: an unexported paws object, which a CRAN package cannot reach |

## 9. Proven mechanisms (research)

Scripts are in `research/`; fake keys only, nothing sent to AWS.

| Claim | Evidence | Rerun |
|---|---|---|
| paws searches the machine when its held keys are empty or past an expiry time, and not when given keys with no expiry time | `research/paws-credentials/probe.R` (cases A, B), against a local capture server | `python3 capture_server.py 18734 $PWD/requests.log` in one shell; `Rscript probe.R 18734 $PWD/requests.log` in another; read `requests.log` |
| paws does not check a provider's result (empty secret, NULL, expired, seconds-as-number) | `research/paws-credentials/probe_e.R` and cases E-K | as above |
| paws reads the address from `AWS_ENDPOINT_URL_S3` when none is given | `probe.R` case H, via paws's own resolver, so nothing is sent | as above |
| A saved session holding a connection with only an id contains no key; a connection holding the private environment or a paws client does | `research/saved-session/` (a throwaway package `credprobe`) | `R CMD INSTALL -l lib credprobe`; `Rscript session1.R $PWD/lib $PWD/saved.RData`; `Rscript session2.R $PWD/lib $PWD/saved.RData` |
| An explicit address keeps the bucket in the hostname only with `s3_virtual_address = TRUE`; a region redirect uses paws's built-in table | Read `update_endpoint_for_s3_config()` and `s3_redirect_from_error()` in paws.common 0.8.8 (2026-11-10), and the first on paws's GitHub main | `Rscript -e 'print(paws.common:::update_endpoint_for_s3_config)'` |
| A paws S3 client takes about 36 KB in memory and about 1 ms to build; paws builds every HTTP request afresh, so a client carries no connection between requests | Measured 2026-11-10 with `gc()` over 200 clients and a 50-build timing loop; read `issue()` and `request_aws()` in paws.common 0.8.8 | -- |
| A handler listed beside `error =` that raises again is caught by it; the catch-all's first line passes the error on; `purrr` re-wraps (`map`, `walk`, `map_lgl`, `imap`, `keep`), `lapply()` does not; `expect_error(class = )` passes on a reworded error unless `inherit = FALSE`; an rlang error's message text includes its cause's; a function using a global fails in a fresh R | `research/condition-handling/probe.R` (purrr 1.2.1, rlang 1.1.7, testthat 3.3.2, 2026-11-10) | `Rscript research/condition-handling/probe.R` |
| Regions whose S3 address is not under `amazonaws.com` | botocore 1.43's `endpoints.json` (in datom-py's environment) lists `aws-cn`, `aws-iso`, `aws-iso-b`, `aws-iso-e`, `aws-iso-f`, `aws-eusc` with their region patterns | -- |
| S3 does not use paws's bearer-token variables (paws.common 0.8.6) | paws.storage builds S3 with the `s3` signer: `new_handlers("restxml", "s3")` | -- |

A probe pitfall met on the saved-session check: the first run reported a leak because the marker
string was written literally in the probe's own `main()`, which the saved session contains. Build a
marker at run time.

## 10. Failure modes and their guards

The table is R4b in `requirements.md`; this maps each guarded row to its test.

| # | Guard |
|---|---|
| FM1 | Renewal timing test (R5.4): the function is called again at 15 minutes left, not before |
| FM2, FM8 | Each refusal of R2.4 and R2.5 has a test (R5.3) |
| FM3 | The sweep's re-run half (R5.6) |
| FM4 | The sweep on `datom_sync()` |
| FM5 | The source test in section 8; unit tests that the reachability check and the copy get their client through the accessor, before their handler |
| FM6 | R5.2: wrong keys planted in the environment and in stand-in `~/.aws` files; requests carry only the store's |
| FM7 | Refusal tests for each variable; address tests for both branches of section 6, and for a region outside its list with and without `endpoint` |
| FM10 | Serialised bytes of a store and a connection, after requests, contain no key (search for a marker value built at run time) |
| FM12 | A connection serialised and loaded where its id is unknown calls the function once |
| FM15 | The sweep (R5.6), under the three rules in section 5 |
| FM16 | The sweep on `datom_init_repo()`, like every other command |

## 11. Correctness properties (what the tests pin)

1. The keys that sign a request come only from the store's arguments, with wrong keys planted in
   every ambient source, for both forms and every client datom builds (R3).
2. Every request goes to the given address or the standard AWS address for the region; never to one
   from the environment or `~/.aws/config` (R3.4).
3. The function is called at construction when `validate = TRUE`, not again for the first request,
   and not at construction when `validate = FALSE` or for `datom_store_s3_creds()` (R2.3).
4. It is called again when 15 minutes or less are left, and not before (R2.3).
5. Every unusable result is refused with `datom_credentials_invalid` naming no value; an error in the
   function surfaces as `datom_credentials_failed` with the original as parent (R2.4, R2.5).
6. A credential failure at any storage request of any command reaches the caller as itself, not as
   the cause of another error (R2.7).
7. A write broken by a credential failure at any storage request finishes on a re-run (R4a.1).
8. A function-built store and connection contain no key or token when serialised or saved, after
   requests too (R4.2).
9. No code under `R/` reaches a stored client except through the accessor (FM5).
10. The keys form behaves as in 0.2.0: the existing suite passes unchanged (R1.2).

## 12. Model escalation (flag at plan time)

- **Design spot-check** before implementation: the change spans the store, the connection, every
  storage call site, 30 error handlers in 16 files and 7 loops.
- **Purity audit** after the accessor and handler changes: 19 call sites, 30 handlers, 7 loops.
- **Test coverage review** before completion: the failure-mode table has 12 guarded rows and the
  sweep covers every exported function that reaches storage.

## 13. The draft's "Not yet traced" list, resolved

| # | Item (2026-10-27) | Where it landed |
|---|---|---|
| 1 | Store rebuilds from keys in `R/conn.R` | Section 3, `.datom_get_conn_developer()` / `.datom_get_conn_reader()`: the rebuilt store keeps the id and function |
| 2 | The bucket check at construction builds its own client | Section 3, `.datom_validate_s3_store()` takes a client from the shared builder |
| 3 | Direct client uses | 19 lines in three files after #155 (11 in `R/utils-s3.R`, 6 in `R/storage.R`, 2 in `R/ref.R`), plus 4 places that build clients; section 3. One, the reachability check, would have stopped checking (FM5) |
| 4 | Set members | Nothing to change: a member's `$fetch` takes the connection when called and holds none; its error wrapper gets the first line (section 5) |
| 5 | Address form | Section 6 |
| 6 | Leftover entries in private memory | Decision 9: about 1 KB per store built, never per renewal |
| 7 | Where the pre-write key check goes | Decision 7 and section 7: not needed |

Nothing is left untraced. The handler and loop lists in section 5 come from reading the code; the
sweep test is what confirms them per command. Real S3 with a single sign-on function is exercised at
spec completion by an end-to-end script the owner runs with their own credentials; which script, and
whether it needs a function-form variant, is settled in the task list.

## 14. Review of `53b4a71` (2026-11-10)

A review by another agent (Claude Code), which read the design against the code but could not run R.
Each finding was verified (in R where it turned on behaviour) and decided with the owner one at a
time.

| # | Finding | Verified | Outcome | Differs from the review |
|---|---|---|---|---|
| 1 | The "let it through" handler beside `error =` is caught by it | Yes: returned "reworded" | The catch-all's first line calls `.datom_pass_credentials(e)` (section 5, mechanism 1) | No |
| 2 | `purrr::map()` re-wraps the failure | Yes, and wider: `walk`, `map_lgl`, `imap` and `keep` too | Seven loops use `lapply()`; the publish step raises a collected credential failure first; the helper looks at the error itself only (section 5, mechanism 3) | Seven loops, not six: `datom_update_members()` reads storage through `datom_member()`. The owner declined a helper that also looks beneath an error, which would hide a missed spot from the sweep instead of exposing it |
| 3 | The sweep would pass with no fix in place | Yes | Three test rules (section 5) | No |
| 4 | Two handlers the local-storage sweep cannot reach | Yes, by reading | The reachability check and the copy get their client before their handler (section 5, mechanism 2) | No |
| 5 | `datom_init_repo()`'s own stop would give contradictory advice; R2.5's "in display only" is wrong | Yes: an rlang error's message text includes its cause's; a re-run of init names the repair | No exception for init (decision 11); R2.5 reworded | The review leaned to keeping init's stop without its pasted text; the cause's text would still say "re-run", so the owner took the plain credential failure |
| 6a | FM14 is wider than stated | Yes | FM14 widened (section 4) | No |
| 6b | Other regions whose address is not under `amazonaws.com` | Yes: five more groups in botocore's list | Standard address only for AWS's standard and GovCloud patterns; any other region needs `endpoint =`; the check sits where the address is built (decision 10) | Added while checking: a refusal in `datom_store_s3()` blocked `endpoint =` as the way out. The owner's scope: US and EU first, other regions may go unsupported |
| 6c | A function sent to a fresh-process worker must be self-contained | Yes: "object not found" in a fresh R | FM12 and R4.1 say so; the help will too | No |
| 6d | paws versions after 0.8.8 | Yes, from paws's NEWS and source on GitHub | One line each in section 6 (dualstack) and DD1 (region memory) | Also checked: S3 does not use paws's bearer-token variables |
| 6e | The new repo's README shows only the keys form | Yes | It shows `credentials =` for a function-built store (section 3) | No |

The design had repeated a spelling that `dev/engineering-notes.md` ("Two ways a condition's class
silently disappears") already marks wrong; findings 1-3 are all in that note.
