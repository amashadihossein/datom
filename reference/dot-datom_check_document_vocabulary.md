# Refuse a Document Carrying a Field This Build Cannot Place

Compares one document's **top-level** key names against the names this
build can classify, and aborts naming any it cannot. The evidence is in
the file: no version comparison, no configuration, no network.

## Usage

``` r
.datom_check_document_vocabulary(doc, known, source)
```

## Arguments

- doc:

  Parsed document. A non-list, or a list with no names, has no top-level
  keys to classify and passes through: it is not this check's job to
  report a malformed document, and the write fails on it moments later
  on its own terms.

- known:

  Character vector of field names this build can place.

- source:

  Path or key of the document, for the message.

## Value

Invisibly `NULL`. Aborts on an unclassifiable key.

## Details

Chosen over a declared version floor as the *primary* mechanism for one
reason – **it cannot be forgotten.** A floor protects a repo only if
somebody remembers to raise it; this fires on the evidence whether or
not anyone did anything.

**Top-level keys only, and that is a scope rather than a shortcut.** It
means do not descend into a value – `custom` holds arbitrary user keys
by design and is classified as one recognised field, and the manifest's
`summary` block is a derived aggregate that is rebuilt on every write.
It does **not** mean skip the manifest's artifact entries: an entry is
its own document for this purpose and gets checked against its own
vocabulary.

**The check cannot fire on the upgrade path**, and no code guards
against that: a newer build's vocabulary is a superset of every older
build's, so it can never meet a name it does not know. A directional
special case would be dead code protecting an unreachable state.

The accepted cost is that any release adding a field to a datom-owned
document forces a fleet-wide **writer** upgrade, cosmetic additions
included. Writes are infrequent, done by few people, and they change
content – a false refusal costs one person an install, a miss costs
corrupted data.
