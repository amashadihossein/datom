# Spec: rework `start-on-s3.Rmd` and `citable-sets.Rmd` (datom, `dev` branch)

## 1. Purpose

Together, these two vignettes walk a new user along the path a future
data-product package (a datom client) will take: onboard data, register it
as the inputs of a set, derive outputs from those inputs with full
provenance, then use and refresh the result.

- **start-on-s3** has two jobs: (1) stand alone as "datom on S3"; (2) leave
  the state that citable-sets starts from. Not everything in it has to serve
  citable-sets.
- **citable-sets** follows a typical data-product build workflow. It does
  **not** name "data product" or the future package. It may state the aim
  at the start so the steps make sense.
- Text stays plain. Remove jargon and side remarks that don't move a new
  user along.

## 2. Principles (the spirit)

1. **Onboard in bulk** with `datom_sync()`.
2. **Register all current inputs first**, and exclude later if needed. No
   version picking at registration: the set records exact versions. Choosing
   a non-latest version is the rare case.
3. **Derive only from what the set holds.** Never read a table just because
   you can reach it. Read inputs through the set, and record parents on every
   derived table.
4. **Only derivation code persists.** Scripts for setup, onboarding, updates
   and edits are not kept, because datom already records their effects. The
   derivation script is optional, and when present it is committed together
   with the set (`include_paths`).
5. **A set gives access to every input and output** through reader
   connections, one per project.

## 3. Conventions

### 3.1 Layout and names

One bucket per study, with a folder per project. datom manages a `datom/`
subfolder under each prefix, where it reads and writes data, metadata and
JSON.

```
s3://study001/
    imported/datom/        onboarded tables        (start-on-s3)
    liver-safety/datom/    the product             (citable-sets)
```

"imported" matches datom's own terms (imported vs derived) and doesn't
assume CDISC knowledge.

Product theme: **liver-safety**. It is an ongoing, study-scoped safety
question that changes with each data cut, and it fits the example data
(ALT/AST in `lb`, dose in `ex`, age/sex in `dm`).

Project, repo and set names match **by convention only**. Keep them as
separate variables so readers see they don't have to match.

### 3.2 Settings blocks (define once, reuse everywhere)

Any value used in more than one call is set up front. A reader who changes
a value changes it in one place.

start-on-s3:

```r
# --- Settings you control ----------------------------------------------------
study            <- "study001"
bucket           <- "study001"            # one bucket per study
region           <- "us-east-1"

project_imported <- "study001-imported"
prefix_imported  <- "imported/"
repo_imported    <- "study001-imported"   # GitHub repo name

workdir_imported <- fs::path(tempdir(), "study001-imported")
```

citable-sets (adds only its own):

```r
project_liver_safety <- "study001-liver-safety"
prefix_liver_safety  <- "liver-safety/"
repo_liver_safety    <- "study001-liver-safety"
set_liver_safety     <- "study001-liver-safety"
workdir_liver_safety <- fs::path(tempdir(), "study001-liver-safety")
```

### 3.3 Object names: `<object>_<role>_<project>`

```
workdir_imported          workdir_liver_safety          # local folder (never "path"/"dev_dir")
store_write_imported      store_write_liver_safety      # store with github_pat
store_read_imported       store_read_liver_safety       # store without github_pat
conn_write_imported       conn_write_liver_safety
conn_read_imported        conn_read_liver_safety
```

- `workdir_` makes clear this is a local working folder, not the persistent
  storage a `store` points to (S3 + GitHub).
- Role lives on the store (a PAT makes it a writer), and the connection
  follows it.
- No renaming partway through (drop `imported <- conn`).
- Version variables use one style: `<table>_version`.

### 3.4 Secrets

One block at the top of start-on-s3 loads keyring values into environment
variables. From then on, both vignettes read them with `Sys.getenv()` only.
Remove the Option A/B/C credential chunks.

```r
Sys.setenv(
  GITHUB_PAT            = keyring::key_get("GITHUB_PAT"),
  AWS_ACCESS_KEY_ID     = keyring::key_get("AWS_ACCESS_KEY_ID"),
  AWS_SECRET_ACCESS_KEY = keyring::key_get("AWS_SECRET_ACCESS_KEY")
)
```

### 3.5 Code style

- Always name arguments explicitly: `f(x = x1)`, never `f(x1)`.
- Pick one form for `governance = NULL` (explicit or omitted) and use it in
  both vignettes.

## 4. start-on-s3: changes

1. Add the secrets block (3.4) and the settings block (3.2).
2. Rename throughout per 3.3. Store and connection builds use
   `bucket = bucket, prefix = prefix_imported, region = region`,
   `access_key = Sys.getenv("AWS_ACCESS_KEY_ID")`, and so on.
3. Storage is at `study001/imported/`. Add one line on the `datom/`
   subfolder datom manages. Replace the "raw at root, derived under `adam/`"
   advice with the layout in 3.1.
4. `datom_init_repo()` has no `mode`. Add one line saying that omitting
   `mode` gives an ordinary repo that onboards files.
5. **Keep the progressive onboarding steps** (one file → update → no-op →
   batch). The batch step is the bulk onboarding citable-sets relies on.
   Leave `dm`, `ex`, `lb` and `ae` onboarded.
6. The "Reading as a reader" section uses `store_read_imported` /
   `conn_read_imported`, built with `project_name = project_imported`.
7. **New short section after "Where you are"** and before "Governance and
   migration come later": two options, (a) continue to citable-sets to build
   on this data, or (b) tear down.
8. Teardown calls `datom_storage_delete_prefix(conn = conn_write_imported)`,
   then `datom_repo_delete(conn = conn_write_imported, confirm = project_imported)`.
   Remove the "use AWS CLI" advice.
9. Factual fixes:
   - The no-op sync message must match the code:
     `No new or changed files. Nothing to sync.` (not "All files
     unchanged").
   - Re-check every printed output block against a real run. No
     hand-edited output.

## 5. citable-sets: new outline

### 5.0 Link and title
The opening link names the previous article by its real title, "Starting
on S3". Settings and secrets are reused from start-on-s3. No hard-coded
strings, and no fresh `Sys.getenv()` literals for bucket, region and the
like.

### 5.1 Aim (short intro)
Track liver safety for study001 as data arrives: a small, versioned
collection of the inputs used and the outputs derived from them, with full
provenance.

### 5.2 Info box: what a datom set is (placed right after the aim)
> **What a datom set is**
> - A named, versioned list of pointers to exact table versions. It holds no data.
> - It never drifts. Each member is pinned until you move it.
> - Any change (members or labels) makes a new version, and old versions stay readable.
> - Reading a set needs access to its own project only. Reading a member needs access to that member's project.

This replaces the scattered sections "What a set does not do", "A write
replaces the current version" and "Labels are content".

### 5.3 Set up the product
- Settings block (3.2).
- `store_write_liver_safety`, then `datom_init_repo(path = workdir_liver_safety,
  project_name = project_liver_safety, store = store_write_liver_safety,
  create_repo = TRUE, repo_name = repo_liver_safety, mode = "product",
  set = set_liver_safety)`, then `conn_write_liver_safety`.
- Note: `mode` is not a free string. It accepts `"product"` or nothing, so
  `mode = "yolo"` is an error.

### 5.4 Version 1: register every input
- Loop over `datom_list(conn = conn_write_imported, short_hash = FALSE)`
  and build `datom_member(conn = conn_write_imported, name = ..., version = ...,
  tags = list(type = "input"))` for each table. Keep the loop clean. A bulk
  helper is a future API item (section 7).
- `datom_write_set(conn = conn_write_liver_safety, members = ...,
  tags = list(description = ...))`.
- v1 is inputs only. That is a valid first version.
- Capture and show the version that comes back (the write returns it
  invisibly).

### 5.5 Version 2: derive the output
- The derivation script, `R/derive_liver_flags.R` in `workdir_liver_safety`,
  is sourced by the vignette.
- The script:
  1. `x <- datom_get_set(conn = conn_write_liver_safety, name = set_liver_safety)`
  2. Reads `dm`, `ex` and `lb` **through the set**:
     `datom_fetch_member(conn = conn_read_imported, x = x, member = "lb")`.
     `ae` stays registered and unused, to show "derive from a subset".
  3. Builds `liver_flags`: one row per subject with peak ALT and AST
     against the upper normal limit, dose, age and sex.
  4. `datom_write(conn = conn_write_liver_safety, data = liver_flags,
     name = "liver_flags", parents = list(datom_parent(conn = conn_read_imported,
     table = "lb", version = <lb version from x>), ...))`, with one parent per
     input used.
- Add the output with `datom_member(conn = conn_write_liver_safety,
  name = "liver_flags", version = ..., tags = list(type = "output"))` and
  write the set with `include_paths = "R"`, which commits the derivation
  script together with the set.
- Say it plainly: every output is derived from members of the set, so the
  set carries its full provenance.

### 5.6 Use it
- **Structure (the main one):**
  `dp <- datom_structure_members(x = x, by = "type")`, then
  `dp$output$liver_flags(conn_read_liver_safety)` and
  `dp$input$lb(conn_read_imported)`. Explain that `type = "input"` /
  `"output"` are the labels that produce `dp$input` / `dp$output`.
- Then list (`datom_list_members()`), history (`datom_history()` on the set)
  and reading v1 by version (`datom_get_set(..., version = ...)`).

### 5.7 Refresh: an input moves
- Write a **month-4 `lb`** (`datom_example_data(domain = "lb",
  cutoff_date = "2026-04-28")`) into `workdir_imported/input_files`, then
  `datom_sync()`. This fixes the current bug where the sync reports
  "1 changed" but no new file was written.
- `datom_update_members(x = x, conn = conn_read_imported, tags = list(type = "input"))`.
- Rerun the derivation script. The output member is updated, and the set
  is written as v3.
- The set never mixes new inputs with an output built from old ones.

### 5.8 Access
Emphasise that a set, together with reader connections (one per project),
opens every input and output. Use **reader** connections for fetching
throughout. The current draft wrongly uses the imported writer connection
to demonstrate fetching.

### 5.9 Closing and teardown
- One line: pooling several studies is a separate article.
- Teardown for both projects: `datom_storage_delete_prefix()` then
  `datom_repo_delete()`. Remove "datom removes only the namespaces it
  created", which is wrong because `datom_repo_delete()` doesn't touch
  storage.

### 5.10 Removed from the current draft
- "Retire a member" (`datom_remove_members`): dropped.
- The `imported <- conn` rename: dropped.
- `STUDY_ADAM`, `trial_product`, `study-001-datom`, `adam/`: replaced per 3.1.

### 5.11 Factual fixes carried from the current draft
- The citation string `9e0c05e6` appears without being captured. Capture it
  (5.4).
- "Resolves to those two tables": the set had three members. Now moot.
- Sync output showed `v Wrote "dm" (full)`, but `datom_sync()` prints
  `dm synced (changed).`
- Re-check every printed output against a real run.

## 6. Acceptance checks

- [ ] No value (bucket, region, prefix, project, repo, set, workdir) is typed
      more than once.
- [ ] Every function call names its arguments.
- [ ] All object names follow 3.3. No `conn`, `imported`, `product` or
      `dev_dir`.
- [ ] Secrets come from `Sys.getenv()` after the single keyring block.
- [ ] citable-sets runs on the state start-on-s3 leaves behind (same bucket,
      same `imported/` prefix, same projects).
- [ ] Every derived table records `parents`, and inputs are read through
      the set.
- [ ] The derivation script is committed with the set (`include_paths`).
- [ ] `dp$input$...` / `dp$output$...` is shown.
- [ ] The refresh writes a new `lb`, syncs, updates inputs, re-derives and
      writes v3.
- [ ] Fetching uses reader connections.
- [ ] Printed outputs match a real run.
- [ ] No "data product" wording in citable-sets beyond the aim.

## 7. API follow-ups (out of scope for this fix)

- A bulk "register all current tables as members" helper, to replace the
  loop in 5.4.
- Possibly an explicit value for the ordinary repo mode (today it's only
  "omit `mode`").
