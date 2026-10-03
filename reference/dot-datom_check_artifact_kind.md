# Refuse to Write One Kind of Artifact Over Another

One name means one artifact, whatever its kind, because both kinds store
everything under `{name}/` – a set named `dm` beside a table named `dm`
would write the same `dm/.metadata/metadata.json` and each would clobber
the other.

## Usage

``` r
.datom_check_artifact_kind(
  current,
  name,
  expected,
  operation = c("write", "read")
)
```

## Arguments

- current:

  The artifact's current metadata document, or `NULL` when the name is
  free.

- name:

  Artifact name.

- expected:

  `"table"` or `"set"` – the kind the caller's verb handles.

- operation:

  What the caller was about to do: `"write"` (default, so existing call
  sites and the messages they assert on are unchanged) or `"read"`.

## Value

Invisibly `NULL`. Aborts on a kind mismatch.

## Details

**Checked against the metadata document in storage, not against the
manifest.** The manifest is a projection and can lag behind a write that
got partway through, so it can say a name is free when it is not. The
document is also the copy
[`.datom_has_changes()`](https://amashadihossein.github.io/datom/reference/dot-datom_has_changes.md)
has just read, so the comparison costs no extra round trip – which is
why the current document is passed in rather than fetched here.

An absent `kind` reads as `"table"`: every document written before the
field existed describes a table, because sets did not exist. The pairing
with a format check is not needed here the way it is in
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
– a document from a future datom has already been refused at the write
entry, and on the read path
[`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md)
has just checked the same document.

**Both directions of the same invariant, in one function.** A read that
meets the other kind needs different words and a different suggested
verb from a write that does, which `operation` selects – following
[`.datom_check_schema_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_schema_version.md),
which took exactly that shape for exactly this reason. A separate
read-side twin would let the two directions drift, each passing its own
tests, while the rule they enforce is single: **one name is one
artifact**. For the same reason both aborts carry one condition class,
so no test can key on one direction alone.

The check is made by each verb after its own
[`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md)
call rather than inside that function, because the two verbs want
different answers from it.
