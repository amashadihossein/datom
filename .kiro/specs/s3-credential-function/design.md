# Design -- S3 credential function

**Status (2026-11-10)**: ready for the owner's review, **not approved**. Drafted 2026-10-27, paused
for [#155](https://github.com/amashadihossein/datom/issues/155), resumed once #155 merged into `dev`
(PR #159). The "Not yet traced" list of the draft was finished with the owner on 2026-11-10; where
each item landed is in section 13. Two reviews the same day (of `53b4a71` and of `030b07f`) were
evaluated with the owner point by point and their outcomes are applied here; the record is
section 14. The second moved the endpoint onto the store and added the location agreement check
(section 6).

Read first: `requirements.md` (approved 2026-10-27, amended three times on 2026-11-10). Decisions
1-15 referred to here are recorded there; DD1 and the choices in section 8 are this document's.

## 1. The shape

The keys of a function-built store exist only in a private environment inside datom's namespace,
which R never writes when a session or object is saved: it writes a reference to the namespace by
name. Every storage request asks one function, `.datom_s3_get_client()`, for a client. For a
function-built connection it renews the keys if they are due, builds a paws client from them, and
the client is used for that request and dropped (decision 9). datom alone decides when to renew.

```
datom_store_s3(bucket, region, endpoint = NULL, credentials = fn, validate = TRUE)
  -> address checks (region rule; AWS_ENDPOINT_URL* with no endpoint)   (section 6)
  -> new id (unique across R sessions, section 4)
  -> call fn, check the result, file keys + expiry under the id      (decision 4)
  -> HeadBucket at the store's address, through a client built from them
  -> store { bucket, prefix, region, endpoint, cred_id, credentials = fn }

datom_get_conn(path or project_name, store)
  -> location: the store's, or ref.json's when governance names one   (section 6)
  -> address checks for a location from ref.json; a message if it is not standard AWS
  -> a developer: warns if ref.json and project.yaml disagree (writes will stop)
  -> connection { ..., endpoint, cred_id, credentials = fn }   no client field

each write -> .datom_check_write_entry(): ref.json, project.yaml and the connection agree

each storage request -> .datom_s3_get_client(conn)
  -> connection has no cred_id                  -> conn$client (keys form; tests' fake clients)
  -> keys held, 15+ minutes left or no expiry   -> build a client from them
  -> no keys held (fresh R, fresh-process worker),
     or 15 minutes or less left                 -> call fn, check, file under the same id, build
  -> fn raises, or returns something unusable   -> datom_credentials_failed / _invalid,
                                                   passed on by every handler above (section 5)
```

## 2. What each object holds

| Object | Function form | Keys form |
|---|---|---|
| Store (`datom_store_s3`) | bucket, prefix, region, `endpoint`, `cred_id`, `credentials` (the function), `validated` | bucket, prefix, region, `endpoint`, keys, `validated` |
| Store (`datom_store_s3_creds`) | `cred_id`, `credentials`; no location, no endpoint (decision 13) | keys |
| Connection | as today, but `cred_id` + `credentials` (and `gov_cred_id` + `gov_credentials`) instead of `client` / `gov_client`; `endpoint` and `gov_endpoint` | as today, with `client` / `gov_client`; `endpoint` and `gov_endpoint` |
| Private memory (`.datom_cred_registry`) | per id: the current keys and their expiry (`POSIXct`, or `NULL` for keys that do not expire) | nothing |
| `ref.json` (governance) | `current` gains an optional `endpoint` beside type, root, prefix, region | same |
| `.datom/project.yaml` (data repo) | `storage.data` gains an optional `endpoint` beside type, root, prefix, region | same |

No object, in either form, holds a paws client for a function-built store: one is built per request
and goes out of scope with it. Today one `endpoint` (an argument of `datom_get_conn()`) applied to
both the data and the governance client; now each store component carries its own.

## 3. Functions, by file

The capability lives in one new file, `R/credentials.R` (owner's preference for new cross-cutting
code in its own file, recorded 2026-10-28). The S3 client builder stays with its backend peers in
`R/utils-s3.R`, the location logic with its peers in `R/ref.R`; each command keeps only a thin call.

| File | Function | New / changed | Does |
|---|---|---|---|
| `R/credentials.R` | `.datom_cred_registry` | new | `new.env(parent = emptyenv())` at namespace level: id -> current keys and expiry |
| `R/credentials.R` | `.datom_cred_new_id()` | new | An id unique across R sessions (section 4) |
| `R/credentials.R` | `.datom_cred_keys(id, fn)` | new | The keys to sign with: the held ones when 15+ minutes are left (or they never expire); otherwise calls `fn` through `.datom_cred_call()` and files the result under `id` |
| `R/credentials.R` | `.datom_cred_call(fn)` | new | Calls `fn` with no arguments. An error becomes `datom_credentials_failed`, the original as parent (R2.5); the result goes through `.datom_check_cred_result()` |
| `R/credentials.R` | `.datom_check_cred_result(x)` | new | R2.4: refuses with `datom_credentials_invalid`, naming the field and the problem, never a value; returns the keys with `expiration` as `POSIXct` or `NULL` |
| `R/credentials.R` | `.datom_pass_credentials(e)` | new | Raises `e` again, unchanged, when it is a credential failure (class `datom_credentials_error`); otherwise returns. Looks at `e` itself only, not its causes. Its comment says it must be the **first line** of the catch-all, and that `error =` must stay the **last** handler of its `tryCatch()` (section 5) |
| `R/credentials.R` | `.datom_s3_get_client(conn)` | new | The accessor in section 1. Reads `conn$region` and `conn$endpoint` for the client it builds (DD1) |
| `R/utils-s3.R` | `.datom_s3_check_address(region, endpoint)` | new | The address checks of section 6: a region outside the list with no `endpoint` stops, naming the region and `datom_store_s3(endpoint = )`; `AWS_ENDPOINT_URL_S3` / `AWS_ENDPOINT_URL` set with no `endpoint` stops, naming the variable. Called by `datom_store_s3()` and at connect |
| `R/utils-s3.R` | `.datom_s3_standard_address(region)` | new | `https://s3.<region>.amazonaws.com` for a region in section 6's list; otherwise stops (never reached after the checks above) |
| `R/utils-s3.R` | `.datom_s3_client()` | changed | Keys with no expiry time given to paws, as today. Always an explicit address: the `endpoint`, else `.datom_s3_standard_address()`. Does not re-check the environment (section 6) |
| `R/utils-s3.R` | the 9 wrappers, 11 client uses (`.datom_s3_upload()`, `_upload_absent()`, `_download()`, `_exists()`, `_read_json()`, `_write_json()`, `_list_objects()`, `_delete_prefix()`, `_object_sha256()`) | changed | `client <- .datom_s3_get_client(conn)` **above** each `tryCatch()`, so a credential failure is never reworded as "Failed to upload file to S3" (section 5) |
| `R/storage.R` | `.datom_copy_one()` | changed | Gets the source and destination clients before its handler, each only when that side is S3 |
| `R/storage.R` | `.datom_storage_byte_size()`, `.datom_storage_content_hash()` | changed | Their client uses go through the accessor; `datom_storage_verify()` reaches them |
| `R/store.R` | `datom_store_s3()` | changed | Gains `credentials` and `endpoint` after `validate` (R1.1); either/or rule; calls `.datom_s3_check_address()` (fail early); with `validate = TRUE` makes the id, gets the keys through `.datom_cred_keys()` **before** the bucket check's handler, and checks the bucket at the store's address |
| `R/store.R` | `datom_store_s3_creds()` | changed | Gains `credentials` (R1.3); makes the id; does not call the function (R2.3); takes no `endpoint` (decision 13) |
| `R/store.R` | `.datom_validate_s3_store()` | changed | Takes a client built by `.datom_s3_client()` instead of building its own (it passed no address) |
| `R/store.R` | `print.datom_store_s3()`, `print.datom_store_s3_creds()` | changed | Function form: "Credentials: from a function"; the endpoint when there is one |
| `R/conn.R` | `datom_get_conn()` | changed | Loses its `endpoint` argument (decision 12), with its documentation moving to `?datom_store_s3` |
| `R/conn.R` | `new_datom_conn()` | changed | Gains `cred_id`, `credentials`, `gov_cred_id`, `gov_credentials`, `gov_endpoint`; `client` optional |
| `R/conn.R` | `.datom_build_init_conn()` | changed | Reads each component's own `endpoint`. Function-form component: carries its id and function, builds no client |
| `R/conn.R` | `.datom_conn_for()` | changed | The governance view carries `gov_cred_id`, `gov_credentials` and `gov_endpoint` as its `cred_id`, `credentials` and `endpoint` |
| `R/conn.R` | `.datom_get_conn_developer()`, `.datom_get_conn_reader()` | changed | The location from `ref.json` (bucket, prefix, region, endpoint) goes through `.datom_s3_check_address()` and `.datom_note_location_source()`; the credentials-only store rebuilt from it keeps the original store's id and function (it rebuilt from `store$data$access_key` and friends); the developer's cross-check of the store against `project.yaml` compares the endpoint too |
| `R/conn.R` | `datom_init_repo()` | changed | Writes the store's `endpoint` into `project.yaml`'s `storage.data`; uses it for the namespace check and the manifest upload |
| `R/conn.R` | `print.datom_conn()` | changed | Function form: "Credentials: from a function"; the governance endpoint when it differs |
| `R/ref.R` | `.datom_create_ref()`, `.datom_parse_ref()` | changed | Write and read `current$endpoint` (decision 13) |
| `R/ref.R` | `.datom_resolve_data_location()` | changed | Returns the endpoint with the location. When `ref.json` and `project.yaml` disagree after its pull, **warns** instead of stopping (R3.6), and compares bucket, prefix, region and endpoint, not the bucket alone |
| `R/ref.R` | `.datom_check_location_agrees(conn)` | new | R3.6: re-reads `ref.json` from governance storage and the clone's `project.yaml`; stops when either disagrees with the connection on bucket, prefix, region or endpoint (section 6). Replaces `.datom_check_ref_current()` |
| `R/ref.R` | `.datom_note_location_source(location)` | new | R3.7: the message for a location from `ref.json` that is not standard AWS S3 (section 6) |
| `R/ref.R` | `.datom_build_gov_resolve_conn()` | changed | Carries the governance store's id, function and endpoint |
| `R/ref.R` | `.datom_check_data_reachable()` | changed | Gets its client through the accessor, **before** its handler. Today it returns early when `conn$client` is `NULL`, which a function-built connection always is, so the check would stop checking for every one of them (FM5). The early return stays only for a connection with no id whose client is not a paws client (the tests' fakes) |
| `R/forward-compat.R` | `.datom_check_write_entry()` | changed | Calls `.datom_check_location_agrees(conn)` when governance is attached. Every write route already passes through it |
| `R/read_write.R`, `R/set.R` | `datom_write()`, `datom_write_set()` | changed | Drop their `.datom_check_ref_current()` call, now in the entry check |
| `R/repo.R` | `datom_repo_set_data_store()` | changed | Writes `endpoint` from `new_store` into `project.yaml`. It is the approval of R3.6, and does not call the entry check, so it is never blocked by it |
| `R/heal.R` | `.datom_publish_artifacts()` | changed | Its loop uses `lapply()`, with `.datom_pass_credentials(e)` as the first line of its handler, so a credential failure stops at the first artifact rather than calling the function once per artifact |
| `R/sync.R` | `datom_sync()` | changed | On a credential failure: says which tables were synced and which were not attempted, then passes the failure on (R4a.2) |
| `R/utils-path.R` | `.datom_render_readme()`, `.datom_store_constructor_snippet()` | changed | The README snippet shows `credentials = <your function>` for a function-built store, and `endpoint =` when there is one |
| 6 files | 9 `purrr` loops that reach storage | changed | `lapply()`, with a comment saying why (section 5) |
| 16 files | 31 error handlers | changed | The first line of the catch-all calls `.datom_pass_credentials(e)` (section 5) |
| `tests/testthat/` | the code-reading test | new | R5.7, section 5 |
| `.github/copilot-instructions.md`, `dev/engineering-notes.md` | the pattern rule | changed | R6.6, section 5 |

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

**1. Handlers: the catch-all's first line passes it on** (section 14, review 1, point 1).

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
again goes past it. It relies on `error =` being the last handler listed, as it is in every
`tryCatch()` under `R/` today (the second review checked; only `http_412` ever comes before one). It
must **not** be written as a second handler beside `error =`
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

**3. Loops: `lapply()`, not `purrr`.** `purrr::map()`, `walk()`, `map_lgl()`, `map_chr()`, `imap()`
and `keep()` re-raise any error from the mapped function as their own (`purrr_error_indexed`), with
the original only as its cause (checked on purrr 1.2.1, 2026-11-10). A caller's `tryCatch()`
matching the credential class then never fires, and `.datom_pass_credentials()` does not recognise
it. A script that walks datom's call graph (`research/condition-handling/purrr_loops.R`) found
exactly nine loops whose mapped function can reach storage; each uses `lapply()` or `vapply()`, with
a comment saying why, as `R/set.R` and `R/sync-set.R` already do:

| Command | Loop (function) |
|---|---|
| `datom_storage_copy()` | over objects (`datom_storage_copy()`) |
| `datom_storage_verify()` | over objects (`datom_storage_verify()`) |
| `datom_validate()` | over files (`.datom_validate_repo_files()`), over tables (`.datom_validate_tables()`), and over a set's members (`.datom_unresolved_members()`) |
| `datom_validate(fix = TRUE)` | over set payloads to restore (`.datom_repair_restore_payloads()`) |
| `datom_projects()` | over projects (`datom_projects()`) |
| `datom_update_members()` | over members to repoint, which reads storage through `datom_member()` |
| every command that publishes (a write, heal, the repair) | over artifacts (`.datom_publish_artifacts()`): its handler gets the pass-on line too, so a credential failure stops at the first artifact |

**The handlers that get the line** (read on 2026-11-10; the code-reading test and the sweep below
prove the list complete):

| File | Handlers | What each does with an error today |
|---|---|---|
| `R/ref.R` | 3 | The governance lookup of the data location warns and carries on; reading `ref.json` and the write-time location check reword it as a stop |
| `R/sync.R` | 4 | The per-table handler rewords it or moves on to the next table; the manifest read returns "unreadable"; the manifest rebuild returns a failed result; the set-payload restore rewords it |
| `R/validate.R` | 3 | The stored manifest, a table's documents and a set's payload read as "nothing to compare" or empty |
| `R/storage.R` | 2 | Verify rewords the source's size read, and reads a failed destination size as missing |
| `R/heal.R` | 2 | The stored-manifest check returns "unreadable", which stops a write ("Could not read the stored manifest") or holds back the manifest with a warning; the publish step collects each artifact's failure |
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

**The sweep test (R5.6, AC11).** On the local backend, with the fixtures #155 built
(`helper-interrupt.R`) and a set with members, the storage dispatch functions in
`R/utils-storage.R` and the three helpers in `R/storage.R` (`.datom_copy_one()`,
`.datom_storage_byte_size()`, `.datom_storage_content_hash()`) are replaced by a stand-in that
raises a `datom_credentials_failed`, built by the real constructor, on the Nth call counted across
all of them, and records whether it fired. Each exported function that reaches storage (enumerated
from `NAMESPACE` in the task list) runs with N = 1, 2, 3... Three rules, so the test cannot pass with
the fault in place (section 14, review 1, point 3):

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

**The code-reading test (R5.7, decision 15).** The sweep sees only the code its test projects run.
A second test reads datom's own functions (`codetools::findGlobals()` on the loaded namespace),
marks every function that can reach `.datom_cred_call()`, and fails if a `purrr` loop's mapped
function, or the expression of a `tryCatch()` whose `error =` handler does not start with
`.datom_pass_credentials()`, can reach one. It follows the method of `purrr_loops.R`, which takes
about 0.7 seconds and is deterministic: it fails only on the commit that adds an unsafe loop or
handler. A false alarm (a path that never happens in practice) is fixed by the harmless safe form.
Skipped on CRAN and without `codetools` (which ships with R; added to Suggests). Blind spot: a call
passed in as a function argument; the sweep covers those paths. Guard probe: turning one `lapply()`
back into `purrr::map()`, and removing one pass-on line, must each turn it red.

**Preventing the pattern, not only catching it** (R6.6, decision 15): a line in the "Don'ts" of
`.github/copilot-instructions.md`, which every session reads: no `purrr` loop and no
`tryCatch(error =)` around code that can reach storage unless credential failures pass on, through
`lapply()` and `.datom_pass_credentials(e)` as the catch-all's first line, with a pointer to the
engineering note; the note gains the credential case, the wrong and right forms side by side; and a
comment at the helper and at each `lapply()` that replaced a `purrr` loop.

## 6. The server address, and where data may go (R3.4, R3.6, R3.7; decisions 2, 10, 12-14)

### Where the address comes from

- **The location** is the store's (bucket, prefix, region, `endpoint`), or, with governance
  attached, the one `ref.json` records (bucket, prefix, region, `endpoint`), which wins when it
  differs, as its bucket already does. The credentials-only store has no location of its own, so
  everything comes from `ref.json` (decision 13).
- **`.datom_s3_client()` always passes an address.** With no `endpoint`, it passes
  `.datom_s3_standard_address(region)` and `s3_virtual_address = TRUE`. With an `endpoint`, it passes
  that, **without** the flag, and accepts any region.
- **Why the flag, and only for datom's own address.** paws treats any explicit address as a custom
  one, and for a custom address puts the bucket in the path unless `s3_virtual_address` is `TRUE`
  (`update_endpoint_for_s3_config()` in paws.common 0.8.8, read 2026-11-10, unchanged on paws's
  GitHub main, 0.10.0). With the flag, the bucket stays in the hostname, as today; bucket names that
  cannot go in a hostname stay in the path, as today. An `endpoint` (MinIO and similar) keeps the
  path style it gets today.
- **Region redirects.** When AWS answers that a bucket is in another region, paws picks the new
  address from its own built-in endpoint table for that region and signs again with the same keys
  (`s3_redirect_from_error()`, read 2026-11-10). No environment variable or config file is read, so
  every address a client can switch to is a standard AWS one.
- **Newer paws.** paws.common 0.9.0 can switch to a dualstack address through
  `AWS_USE_DUALSTACK_ENDPOINT`; passing the address explicitly shuts that out too (paws's NEWS, read
  2026-11-10).

### The address checks, and where they run

`.datom_s3_check_address(region, endpoint)` makes two checks:

- **The region rule** (decision 10): with no `endpoint`, the region must match AWS's own patterns
  for its standard group (`^(us|eu|ap|sa|ca|me|af|il|mx)-\w+-\d+$`) or GovCloud
  (`^us-gov-\w+-\d+$`), as listed in botocore's `endpoints.json` and paws.common's endpoint table.
  Otherwise it stops, naming the region and `datom_store_s3(endpoint = )`. That covers China
  (`amazonaws.com.cn`), the US government secret clouds (`us-iso-*`, `us-isob-*`, `us-isof-*`),
  `eu-isoe-*`, the EU Sovereign Cloud (`eusc-de-*`, `amazonaws.eu`) and made-up names. A region AWS
  adds under a new prefix is refused, with the same way out, until datom adds it.
- **`AWS_ENDPOINT_URL_S3` / `AWS_ENDPOINT_URL`** with no `endpoint`: stops, naming the variable. With
  an `endpoint` the variable has no effect, so it is not refused (the AWS command line may need it).

They run where datom first knows the location: in `datom_store_s3()` (and so before
`validate = TRUE`'s bucket check), and in `datom_get_conn()` for a location taken from `ref.json`.
`.datom_s3_client()` does not re-check the environment: since every client gets an explicit address,
paws never reads the variable, so the refusal only explains why it is ignored. So no command that
changes things meets an address refusal partway: `datom_init_repo()` takes a store that has passed
them, and builds no address of its own (section 14, review 2, point 1b).

### Writes go only where governance and the data repo agree (R3.6, decision 14)

`.datom_check_location_agrees(conn)`, called from `.datom_check_write_entry()` on every write route
when governance is attached, compares three records of the data's location on bucket, prefix, region
and endpoint:

| Record | Read from | Changed by |
|---|---|---|
| `ref.json` | governance storage, read afresh | governance (datomanager, a move) |
| `.datom/project.yaml` | the clone | a pushed commit to the data repo, pulled |
| the connection | memory | `datom_get_conn()` |

If any two disagree, the write stops before changing anything, naming the locations, with two ways
out: reconnect with `datom_get_conn()`, which pulls the data repo, since a real move updates
`project.yaml` there too; or, if `ref.json` changed alone and the change is expected, approve it once
with `datom_repo_set_data_store(conn, <store for the new location>)`, which commits it to
`project.yaml`, after which writes go on as usual. A change made to `ref.json` alone therefore cannot
send a developer's data elsewhere: it also needs a pushed commit to the data repo, which GitHub's
permissions and history guard.

- **Connecting warns instead of stopping** on a disagreement between `ref.json` and `project.yaml`,
  so the developer can connect and run the approve command. Today `.datom_resolve_data_location()`
  stops when the bucket disagrees after its pull, and compares nothing for a credentials-only store.
- **The check replaces `.datom_check_ref_current()`**, which compared `ref.json` with the connection
  only, and only on `datom_write()` with data and on `datom_write_set()`. The repair, the
  metadata-only and mirror-everything routes of `datom_write()`, and the publish `datom_sync()` makes
  at its start relied on the connect-time stop; moving the check into the entry check covers them.
- **A proper move needs no approval**: it updates both records, and `datom_get_conn()` pulls the new
  `project.yaml`. Developers see the stop only when `ref.json` changed alone, or before they have
  reconnected after a move.

### Readers are told when the location is not standard AWS (R3.7, decision 14)

`.datom_note_location_source()` prints a message at `datom_get_conn()` (class
`datom_location_from_governance`, so tests can quiet it) when the location came from `ref.json` and
is anything but standard AWS S3: an `endpoint`, a local folder (`type: local`), or any backend added
later. The rule is written as "everything but standard AWS", so a new backend is covered without a
list to maintain. No message when the caller chose the location in their own store. This is
visibility, not enforcement: readers have no second record, and a forged `ref.json` can feed them
forged data, as it can today by naming another AWS bucket. The help recommends tight write access to
the governance store, with versioning and an audit log on it.

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
exactly where an expired login fails. The location agreement check (section 6) runs in the entry
check, before any of these steps, so its stop also leaves nothing half-done.

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
| Where the code goes | `R/credentials.R` for the credential capability; the location check in `R/ref.R`, called from the entry check | Spread over `R/utils-s3.R` and `R/store.R`: no new file, but the capability in pieces |
| FM5's guard | A test that reads the files under `R/` and fails if the stored client (`$client`, `$gov_client`) is named outside the accessor, the connection constructor and `.datom_conn_for()` | A test per call site: 19 tests, and none for a site added later |
| The id | Clock, process id, counter (section 4) | A random string: touches the caller's random seed unless saved and restored |
| The region patterns | AWS's own, copied from its endpoint list, with the source named beside them | Read paws's endpoint table at run time: an unexported paws object, which a CRAN package cannot reach |
| The location check's home | The entry check every write route already calls | A call in each route: the gap `.datom_check_ref_current()` had |
| The reader message | A message with its own class | A warning: louder, but would fire on every connect to a local or MinIO project with governance |

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
| Exactly nine `purrr` loops in datom can reach a storage request (135 of 421 functions can) | `research/condition-handling/purrr_loops.R`, a walk of datom's call graph, 2026-11-10; about 0.7 s | `Rscript .kiro/specs/s3-credential-function/research/condition-handling/purrr_loops.R` from the repo root |
| Regions whose S3 address is not under `amazonaws.com` | botocore 1.43's `endpoints.json` (in datom-py's environment) lists `aws-cn`, `aws-iso`, `aws-iso-b`, `aws-iso-e`, `aws-iso-f`, `aws-eusc` with their region patterns | -- |
| S3 does not use paws's bearer-token variables (paws.common 0.8.6) | paws.storage builds S3 with the `s3` signer: `new_handlers("restxml", "s3")` | -- |
| datom-py takes no endpoint and does not read `ref.json` | Read `src/datom/_s3.py` and grepped `src/datom/` (2026-11-10) | -- |

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
| FM7 | Refusal tests for each variable with and without an `endpoint`; address tests for both branches of section 6, and for a region outside its list with and without `endpoint`, at the store and at connect |
| FM10 | Serialised bytes of a store and a connection, after requests, contain no key (search for a marker value built at run time) |
| FM12 | A connection serialised and loaded where its id is unknown calls the function once |
| FM15 | The code-reading test (R5.7) and the sweep (R5.6), under the three rules in section 5 |
| FM16 | The sweep on `datom_init_repo()`, like every other command |
| FM17 | R5.8: each write route stops on each kind of disagreement; connecting warns; the approve command lets the next write through |
| FM18 | R5.8: the message for a location from `ref.json` that is not standard AWS, and none otherwise |

## 11. Correctness properties (what the tests pin)

1. The keys that sign a request come only from the store's arguments, with wrong keys planted in
   every ambient source, for both forms and every client datom builds (R3).
2. Every request goes to the location's endpoint or the standard AWS address for its region; never
   to one from the environment or `~/.aws/config` (R3.4).
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
10. Keys passed directly behave as in 0.2.0 except for the four breaking changes of R1.2: the
    existing suite passes with only the tests of those four changed (R1.2).
11. With governance attached, no write changes anything unless `ref.json`, `project.yaml` and the
    connection name the same location (R3.6).
12. No `purrr` loop and no `tryCatch()` handler that lacks the pass-on line wraps code that can reach
    the credential function (R5.7).

## 12. Model escalation (flag at plan time)

- **Design spot-check** before implementation: the change spans the store, the connection, every
  storage call site, 31 error handlers in 16 files, 9 loops, and the location records in `ref.json`
  and `project.yaml`.
- **Purity audit** after the accessor and handler changes: 19 call sites, 31 handlers, 9 loops.
- **Test coverage review** before completion: the failure-mode table has 14 guarded rows, the sweep
  covers every exported function that reaches storage, and the code-reading test covers the rest.

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

Nothing is left untraced. The handler and loop lists in section 5 come from reading the code and
from the call-graph script; the code-reading test and the sweep confirm them. Real S3 with a single
sign-on function is exercised at spec completion by an end-to-end script the owner runs with their
own credentials; which script, and whether it needs a function-form variant, is settled in the task
list.

## 14. Reviews

Both by another agent (Claude Code), reading the design against the code without running R. Each
finding was verified (in R where it turned on behaviour) and decided with the owner one at a time.

### Review 1, of `53b4a71` (2026-11-10)

| # | Finding | Verified | Outcome | Differs from the review |
|---|---|---|---|---|
| 1 | The "let it through" handler beside `error =` is caught by it | Yes: returned "reworded" | The catch-all's first line calls `.datom_pass_credentials(e)` (section 5, mechanism 1) | No |
| 2 | `purrr::map()` re-wraps the failure | Yes, and wider: `walk`, `map_lgl`, `imap` and `keep` too | Loops use `lapply()`; the helper looks at the error itself only (section 5, mechanism 3) | Seven loops, not six: `datom_update_members()` reads storage through `datom_member()`. The owner declined a helper that also looks beneath an error, which would hide a missed spot from the sweep instead of exposing it |
| 3 | The sweep would pass with no fix in place | Yes | Three test rules (section 5) | No |
| 4 | Two handlers the local-storage sweep cannot reach | Yes, by reading | The reachability check and the copy get their client before their handler (section 5, mechanism 2) | No |
| 5 | `datom_init_repo()`'s own stop would give contradictory advice; R2.5's "in display only" is wrong | Yes: an rlang error's message text includes its cause's; a re-run of init names the repair | No exception for init (decision 11); R2.5 reworded | The review leaned to keeping init's stop without its pasted text; the cause's text would still say "re-run", so the owner took the plain credential failure |
| 6a | FM14 is wider than stated | Yes | FM14 widened (section 4) | No |
| 6b | Other regions whose address is not under `amazonaws.com` | Yes: five more groups in botocore's list | Standard address only for AWS's standard and GovCloud patterns; any other region needs `endpoint =` (decision 10) | Added while checking: a refusal in `datom_store_s3()` blocked `datom_get_conn(endpoint =)` as the way out (superseded by review 2). The owner's scope: US and EU first, other regions may go unsupported |
| 6c | A function sent to a fresh-process worker must be self-contained | Yes: "object not found" in a fresh R | FM12 and R4.1 say so; the help will too | No |
| 6d | paws versions after 0.8.8 | Yes, from paws's NEWS and source on GitHub | One line each in section 6 (dualstack) and DD1 (region memory) | Also checked: S3 does not use paws's bearer-token variables |
| 6e | The new repo's README shows only the keys form | Yes | It shows `credentials =` for a function-built store (section 3) | No |

The design had repeated a spelling that `dev/engineering-notes.md` ("Two ways a condition's class
silently disappears") already marks wrong; findings 1-3 are all in that note. Decision 15 puts the
rule where every session reads it.

### Review 2, of `030b07f` (2026-11-10)

| # | Finding | Verified | Outcome | Differs from the review |
|---|---|---|---|---|
| 1a | `endpoint =` is no way out for `datom_init_repo()` or `datom_clone()`, which take none | Yes, by reading | **The endpoint moves to the store** (decision 12); `datom_get_conn()` loses its `endpoint` outright; each store component has its own | The review recorded a deferral the owner had agreed with it. The owner reconsidered once the deferral needed temporary code (row 1b) and left init and clone unable to reach MinIO |
| 1a' | Its two questions for later: what becomes of `datom_get_conn(endpoint = )`, and where the credentials-only store gets its address | -- | Removed with no stub; `ref.json` records the endpoint and that store takes none (decision 13) | The owner then asked for a "two factor" safeguard on `ref.json`: writes need `ref.json` and `project.yaml` to agree, and readers are told about a non-AWS location (decision 14, section 6). Checking it found today's write-time location check runs on two routes only, so the new one sits in the entry check every route calls |
| 1b | An unsupported region makes init stop after its push | Yes, by reading; also `AWS_ENDPOINT_URL` set after the store was built | The address checks run when the store is built and at connect; the client builder does not re-check the environment (section 6). No init-only check | The review proposed an up-front check in init |
| 2 | An eighth `purrr` loop, in `.datom_unresolved_members()` | Yes; the call-graph script found exactly nine loops (this one and the publish step's included) | `lapply()`; the sweep's projects include a set with members | No |
| 3 | The publish step calls the function again for each artifact after a credential failure | Yes, by reading | `lapply()`, with the pass-on line first in its handler | No |
| 4a | "Keys passed directly work as in 0.2.0" no longer holds | Yes | R1.2 lists the four breaking changes; NEWS leads with them (R6.4); property 10 amended | Added: `AWS_ENDPOINT_URL*` is refused only when the store has no `endpoint`, which avoids blocking MinIO users who keep it set for other tools |
| 4b | The helper's comment should say `error =` stays last | Yes | Section 3 | No |
| -- | (the owner's, during the review) Preventing the pattern, not only catching it | -- | A code-reading test, the always-loaded rule, the engineering note, comments at each site (decision 15) | -- |
