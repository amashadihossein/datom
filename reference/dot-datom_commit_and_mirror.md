# Commit, Push, Then Mirror to Storage

The tail of every artifact write, in the one order that is allowed:
local files are already on disk, this commits and pushes them, and only
then does it touch storage. **Git push is the serialization point** – a
clone that is behind fails to push before it can upload anything, which
is what makes the reuse decisions in
[`.datom_resolve_parquet_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_resolve_parquet_sha.md)
/
[`.datom_resolve_document_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_resolve_document_sha.md)
safe against a concurrent writer. Nothing may reorder these two halves.

## Usage

``` r
.datom_commit_and_mirror(
  conn,
  name,
  meta,
  metadata_sha,
  git_paths,
  message,
  upload = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object (developer, with a local path).

- name:

  Artifact name.

- meta:

  The metadata document to mirror.

- metadata_sha:

  The version being written.

- git_paths:

  Absolute paths of the files this write produced in the clone.
  `.datom/manifest.json` is added here rather than by each caller, since
  every write updates it.

- message:

  Commit message.

- upload:

  Optional `list(path =, key =)` naming a payload object to upload after
  the push – the freshly serialized parquet for a table, the payload
  JSON for a set. `NULL` when the object is already stored and must not
  be rewritten.

## Value

The commit SHA.

## Details

Extracted when the set write arrived, and the extraction is the point
rather than tidiness: this sequence was previously inline in
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md),
so a second write verb had to either call it or grow a parallel copy –
and a second copy of "git must succeed before storage is touched" is a
second place for that rule to be broken by a change that only looks at
one of them.
