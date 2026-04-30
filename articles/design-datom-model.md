# The datom Model: Code in Git, Data in Cloud

> **Companion to**: [First
> Extract](https://amashadihossein.github.io/datom/articles/first-extract.md).
> Read this when you want to understand *why* datom split storage in
> two.

The single design decision that shapes everything else in datom is this:
**metadata and data live in different places, and that’s intentional.**

This article explains the split, the consequences that fall out of it,
and the properties you get for free when you accept it.

## The split

    +------------------------+         +-------------------------+
    |    Git repository      |         |    Object store         |
    |                        |         |                         |
    |  manifest.json         |         |  dm/                    |
    |  metadata.json         |         |    a8ee7a31.parquet     |
    |  version_history.json  |  ---->  |    5c1a3f7b.parquet     |
    |  project.yaml          |  refers |  ex/                    |
    |                        |   to    |    f44910b5.parquet     |
    |  (everything text,     |         |                         |
    |   diffable, reviewable)|         |  (parquet bytes only,   |
    |                        |         |   keyed by SHA)         |
    +------------------------+         +-------------------------+

**Metadata** – the catalog of what tables exist, what their current and
historical versions are, and where the bytes live – goes in a git
repository. It’s small, text-based, diffable, reviewable, and protected
by all the access controls and audit machinery your organization already
has around git.

**Data** – the parquet bytes themselves – goes in an object store. Each
parquet file is named by a SHA of its content. The git repo never holds
data; it only holds *pointers* to data.

This is not a storage optimization. It’s an information-architecture
choice with downstream consequences.

## Property 1: Immutability is automatic

Parquet files are addressed by **SHA of their content**. Two
consequences fall out:

- **Writing the same data twice produces the same filename.** The second
  upload is either a no-op or a harmless overwrite of identical bytes.
- **Different data produces a different filename.** A new version never
  overwrites an old one; both files coexist in the store.

You don’t have to remember to copy old files before overwriting them.
The file *system* makes overwriting impossible by construction. The
history your
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
call shows is real – those parquet files are still in the store.

## Property 2: The metadata is reviewable like code

Because metadata lives in git, every change to a project’s catalog is a
commit. That means:

- `git log` shows the history of every table.
- `git blame` tells you which
  [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  introduced a specific version.
- Pull requests, branch protection, and code review apply to data
  changes the same way they apply to code changes.
- Restoring a project to “the way it was on March 15” is `git checkout`,
  no special tooling.

If you’ve ever debugged a missing column by reading commit messages, you
already understand why this matters.

## Property 3: Readers don’t need write access

The split lets datom support two roles cleanly:

- **Data developers** push to git and write to the object store.
- **Data readers** pull from git (or, in many real workflows, just read
  the object store directly through the cached manifest) and read from
  the object store.

Readers never need write credentials. A statistician with read-only S3
access can reproduce any historical analysis – the metadata they need is
already on the data side, cached when the developer wrote.

## Property 4: Storage is swappable

Because datom only knows the *address* of data through the metadata, not
the bytes themselves, the storage backend is a substitution point.
[`datom_store_local()`](https://amashadihossein.github.io/datom/reference/datom_store_local.md)
puts parquet on a directory;
[`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
puts parquet on S3; future backends (GCS, Azure Blob, etc.) drop in
without touching how versions are computed or how history is recorded.

What does *not* swap is git. The metadata still goes to a git remote,
always.

## What stays in the metadata

A datom project’s git repository holds, per table:

- `metadata.json` – the current state (current data SHA, table type,
  size, parents).
- `version_history.json` – an append-only log of every version ever
  written.
- A `manifest.json` at the project root summarizing all tables.

It does **not** hold the data, and it never will. The `.gitignore` in a
new project explicitly excludes parquet, csv, and other data formats so
nobody can commit them by accident.

## What this isn’t

datom is not a content-addressed *blob store* like git-LFS or DVC. The
key difference: datom’s metadata is a structured, queryable catalog –
not opaque pointer files in your repo. You ask
`datom_history(conn, "dm")` and you get a data frame, not a `git log` of
`.dvc` files. The metadata is designed to be read by code, not just by
humans.

datom is also not a database. It has no query engine, no ACID
transactions across tables, no joins. It is a content-addressed catalog
of immutable parquet files, and it’s deliberately not more than that.

## Where this leads

Once you accept “metadata in git, data in object store,” several other
datom design choices stop looking arbitrary:

- The two-repo split (governance vs. project) – see [Two Repositories:
  Governance
  vs. Data](https://amashadihossein.github.io/datom/articles/design-two-repos.md).
- The `ref.json` indirection layer – see [`ref.json` and
  Always-Migration-Ready
  Storage](https://amashadihossein.github.io/datom/articles/design-ref-json.md).
- The two-flavor SHA scheme (data SHA + metadata SHA) – see [Version
  SHAs: Data SHA vs. Metadata
  SHA](https://amashadihossein.github.io/datom/articles/design-version-shas.md).

Each is a direct consequence of the split, applied to a specific
problem. None of them stand on their own.
