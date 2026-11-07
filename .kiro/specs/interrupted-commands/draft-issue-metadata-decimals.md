# DRAFT issue, not yet filed: custom metadata decimals are rounded to four places, in storage and in the version id
Drafted 2026-11-06 from task 4b's checkpoint review of the interrupted-commands spec (#155), for the
owner to review. Not opened on GitHub; the owner decides whether and when. Once filed, replace this
file's pointer in `design.md` section 12 with the issue number.
---
**Title:** Custom metadata decimals are rounded to four places, in storage and in the version id

## What happens
`datom_write(conn, df, "dm", metadata = list(threshold = 0.123456))` stores `"threshold": 0.1235`
in `dm/metadata.json`, in the clone and in storage. A reader gets `0.1235` back.

The version id is computed from the same rounded form, so `threshold = 0.123456` and
`threshold = 0.12346` give the same version id: a write of the second after the first reports "No
changes detected" and records nothing, although the metadata the user passed differs.

## Why
Both places use `jsonlite`'s default of four decimal digits:
- `.datom_write_metadata_local()` (`R/read_write.R`) writes the document with
  `jsonlite::write_json(..., auto_unbox = TRUE, pretty = TRUE)`;
- `.datom_metadata_sha_from_fields()` (`R/utils-sha.R`) hashes
  `jsonlite::toJSON(sorted_fields, auto_unbox = TRUE)`.

Because both round the same way, the version id survives a trip to disk and back, so nothing
fails; the loss is silent. Found while checking which values survive that trip (#155: missing and
non-finite values are refused from task 4b's review on; this one was left because it changes ids).

## Why it is not a small fix
Writing and hashing more digits (`digits = NA`, or `I(15)`) changes the version id of every
existing version whose metadata holds a decimal with more than four significant decimals: a write
of unchanged content would report a metadata change and mint a new version, in every repo. It needs
a decision on version identity, like the `kind` field's addition (accepted there, noted in NEWS),
and a format note for datom-py, whose reader must hash the same way.

## Open questions for the owner
- Is losing precision past four decimals acceptable for custom metadata? If yes, document it in
  `?datom_write` and close.
- If not: change both sides together, and accept one new version per affected table on its next
  write, or refuse decimals past four places at write time (no id changes, a loud refusal)?
