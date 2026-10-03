# Which Project an Artifact Belongs To, From the Repo Rather Than a Label

The cascade both pointer constructors use –
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
and
[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
– to answer "which project is this artifact in" without trusting the
connection it was reached through.

## Usage

``` r
.datom_declared_project(conn, snap, what = "member")
```

## Arguments

- conn:

  The connection the artifact was read through.

- snap:

  The artifact's metadata snapshot, already read and already checked for
  a format this build understands.

- what:

  What is being declared – `"member"` or `"parent"` – used only to word
  the unverified-fallback warning.

## Value

A single non-empty string.

## Details

**Why a label cannot be trusted.** On a connection built from a clone,
datom reads `project_name` out of `.datom/project.yaml`, so it is the
repo's own declaration. On a **reader** connection it is a string the
caller passed to
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md):
the namespace comes from the store's root and prefix, and nothing
compares the label against the repo. Both constructors write the name
they settle on into a stored document – a member's `id$project` is
hashed into the set's `data_sha` and cited afterwards, and a parent's
`source` is part of the declaring table's version – so a label nobody
checked would be durable wrong data that no hash and no validator can
notice.

Three steps, cheapest and most trustworthy first:

1.  **The artifact's own snapshot**, which the caller has already read.
    Free, and it is the writing repo's declaration.

2.  **The manifest of the namespace the artifact lives in**. One extra
    read, and only for an artifact written before datom recorded the
    field – which is every artifact in every existing repo, so this is
    the common path in this release rather than a rare one. Goes through
    the gated reader, so a manifest whose format this build cannot read
    is handled the one way datom handles that anywhere; when the
    manifest is unusable, that reader can escalate to reconstructing the
    index from a namespace listing, which is accepted because a repo in
    that state needs attention regardless.

3.  **The connection's label**, said out loud to be unverified.

**One gap, named rather than guarded.** When the manifest has to be
reconstructed and the document it replaced recorded no project name, the
reconstruction fills that field from the connection
([`.datom_rebuild_manifest()`](https://amashadihossein.github.io/datom/reference/dot-datom_rebuild_manifest.md)),
so step 2 can hand back the label while looking like the repo's
declaration. What is lost there is the *warning*, not the value: the
string is exactly the one step 3 would have returned. Closing it
properly means the shared manifest reader reporting whether the document
it returned was reconstructed, which is a change to that reader rather
than to this cascade.
