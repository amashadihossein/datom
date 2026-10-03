# Say That a Manifest's Format Was Moved Forward

Called from the two places that **persist** a converted manifest: the
entry updater, which rewrites the git-tracked file, and the data-side
metadata sync, which mirrors the converted document to storage. Reads
convert too and stay silent, deliberately – a read changes nothing, and
a line on every
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
call would be noise nobody can act on.

## Usage

``` r
.datom_notify_manifest_upgraded(declared, where)
```

## Arguments

- declared:

  The version the document declared before conversion, as returned by
  [`.datom_check_schema_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_schema_version.md).

- where:

  Human-readable name of the copy being written.

## Value

Invisibly `NULL`.

## Details

Why say anything: conversion is one-way for everybody else. Once this
repo's manifest declares the newer format, a collaborator on an older
datom no longer finds the artifact list where their build looks for it,
and their
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
reports an empty repo **without erroring**. Their
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
keeps working, because the data path never touches the manifest. That is
a real consequence of a command whose stated job was something else –
`datom_validate(fix = TRUE)` in particular reads as a repair – and an
unannounced one is the silent degradation the whole schema contract
exists to remove.

No-op when the document was already current, which is every ordinary
write.
