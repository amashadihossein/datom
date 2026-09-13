# Frozen test fixtures

One preserved file per historical on-disk shape. **These files are never edited.**

They exist so a schema change can be shown not to break repos already written in an older shape.
A fixture rewritten to the current shape still passes its test while asserting nothing, which is
exactly the regression it was created to catch -- so treat any diff here as a mistake.

| File | Shape it preserves |
|---|---|
| `manifest-v1.json` | manifest as written before the artifact namespace existed: no `schema_version` field, artifacts listed under `tables`, one real table entry, a `summary` block |
