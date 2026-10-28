# Design -- S3 credential function (DRAFT, not reviewed)

**Status (2026-10-27)**: a working draft recording the design discussion held while writing the
requirements, so a later session can resume. **Not approved.** The spec is paused until
[#155](https://github.com/amashadihossein/datom/issues/155) is fixed; resume here afterwards by
finishing "Not yet traced" below, then asking the owner to review this document.

Read first: `requirements.md` (approved) -- every decision referred to here is recorded there.

## Shape

The keys of a function-built store exist only in a private environment inside datom's namespace,
which R never writes when a session or object is saved; it writes a reference to the namespace by
name. datom alone decides when to renew them.

| Piece | Where (proposed) | Does |
|---|---|---|
| Private memory | `R/utils-s3.R`: `.datom_cred_registry <- new.env(parent = emptyenv())` at namespace level | Per id: the function, current keys, their expiry, the paws client |
| Register | new `.datom_cred_register(fn)`, called by `datom_store_s3()` / `datom_store_s3_creds()` | Makes a random id, files the function under it, returns the id |
| Accessor | new `.datom_s3_get_client(conn)` | Looks up the id; renews when expiry is within 15 minutes; builds the client if missing; falls back to `conn$client` when the connection has no id (keys form, tests' fake clients) |
| Result check | new `.datom_check_cred_result()` | R2.4 refusals (`datom_credentials_invalid`); converts `expiration` to `POSIXct` |
| Client builder | `.datom_s3_client()`, changed | Keys with **no** expiry time given to paws; the address always passed (caller's `endpoint`, else the standard AWS address for the region, keeping virtual-host bucket addressing); `cn-*` refused; `AWS_ENDPOINT_URL*` refused |

What each object holds:

| Object | Function form | Keys form (unchanged from today) |
|---|---|---|
| Store | bucket, prefix, region, id, function | bucket, prefix, region, keys |
| Connection | bucket, prefix, region, id, function; **no** `client` field | as today, with `client` |
| Private memory | id -> current keys, expiry, paws client | nothing |

## Flows

```
datom_store_s3(credentials = fn, validate = TRUE)
  -> register fn -> id
  -> call fn, check result, file keys + expiry under id
  -> HeadBucket through the shared client builder
  -> store { bucket, prefix, region, id, fn }

each S3 request -> .datom_s3_get_client(conn)
  -> id found, keys good for 15+ min       -> reuse client
  -> id found, keys within 15 min of expiry -> call fn, check, rebuild client
  -> id not found (fresh R, fresh-process worker) -> re-register under the same id,
                                                     call fn, build client

each write -> key check (renew if needed) BEFORE any local file write or git commit
datom_sync() -> a datom_credentials_* error ends the sync
```

## Proven mechanisms (research, 2026-10-27)

Scripts are in `research/`; fake keys only, nothing sent to AWS.

| Claim | Evidence | Rerun |
|---|---|---|
| paws searches the machine when its held keys are empty or past an expiry time, and not when given keys with no expiry time | `research/paws-credentials/probe.R` (cases A, B), against a local capture server | `python3 capture_server.py 18734 $PWD/requests.log` in one shell; `Rscript probe.R 18734 $PWD/requests.log` in another; read `requests.log` |
| paws does not check a provider's result (empty secret, NULL, expired, seconds-as-number) | `research/paws-credentials/probe_e.R` and cases E-K | as above |
| paws reads the address from `AWS_ENDPOINT_URL_S3` when none is given | `probe.R` case H, via paws's own resolver, so nothing is sent | as above |
| A saved session holding a connection with only an id contains no key; a connection holding the private environment or a paws client does | `research/saved-session/` (a throwaway package `credprobe`) | `R CMD INSTALL -l lib credprobe`; `Rscript session1.R $PWD/lib $PWD/saved.RData`; `Rscript session2.R $PWD/lib $PWD/saved.RData` |

A probe pitfall met on the saved-session check: the first run reported a leak because the marker
string was written literally in the probe's own `main()`, which the saved session contains. Build a
marker at run time.

## Not yet traced (the design work left)

1. **Store rebuilds from keys.** `R/conn.R` builds `effective_data_store` by calling
   `datom_store_s3()` with `store$data$access_key` etc. in the developer and the reader connection
   paths, after the governance lookup resolves the data location. It must carry the id and function
   instead.
2. **The bucket check at construction** (`.datom_validate_s3_store()` in `R/store.R`) builds its own
   paws client; it must use the shared builder.
3. **Direct client uses**: 17 lines in `R/conn.R`, `R/ref.R`, `R/storage.R`, `R/utils-s3.R`,
   including the exported `datom_storage_*()` functions.
4. **Set members**: a member's download function captures a connection; an existing test pins that
   it carries no credentials. Check how the id interacts with it.
5. **Address form**: confirm `s3_virtual_address = TRUE` with an explicit standard address keeps
   today's bucket addressing (paws switches to path style for any explicit endpoint otherwise:
   `custom_s3.R` in paws.common).
6. **Leftover entries**: private memory gains an entry per store built and never shrinks.
7. **Where the pre-write key check goes.** It must run before **any** local file write, not just
   before the commit: `datom_write()` writes the clone's metadata and manifest before committing, and
   `datom_sync_manifest()` compares input files against the clone's manifest, so a check that fails
   after those writes would make a re-run think the table is already synced. (Found 2026-10-27 while
   tracing #155; see that issue for the same effect after a failed upload.)

## Depends on #155

FM3 in the requirements (a login lost between a write's git push and its data upload) has no
repair until #155 lands. The long-job requirement (R4a) is designed on the assumption that a re-run
of the same command completes an interrupted write, which #155 makes true.

## Model escalation (flag at plan time)

- Design spot-check before implementation: the change spans store, connection, and every storage
  call site.
- Purity audit after the accessor change: 17 call sites in four files.
- Test coverage review before completion: the failure-mode table (R4b) has eight guarded rows.
