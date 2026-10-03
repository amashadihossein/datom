# Refuse a Payload Only a Whole-Payload View Can Judge

Three refusals that
[`.datom_validate_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_members.md)
deliberately cannot make, because each needs the whole payload rather
than one member:

## Usage

``` r
.datom_check_set_payload(payload, name, project)
```

## Arguments

- payload:

  A tidied, validated, ordered payload.

- name:

  The set's own name.

- project:

  The set's own project.

## Value

Invisibly `TRUE`.

## Details

- **Zero members.** An empty citable product has no content to identify,
  and the recourse is simply to write the set once its first output
  exists.

- **The same `id` listed twice with different `tags`.** Deduplication
  does not catch this – the digest covers tags, so both entries survive
  – and the payload then holds one member twice with conflicting labels,
  which a consumer projecting tags into a folder view sees as one
  artifact in two places. Refused rather than tidied because both ways
  to tidy it guess: merging the tags is right if the caller meant both
  categories and nonsense if two code paths disagreed, and picking one
  entry is arbitrary.

- **Self-reference.** A set listing itself, at any version, is refused.

**The same `project` and `name` at two different `version`s is legal and
must stay legal**: a product carrying a current table beside a locked
baseline is atypical and entirely sensible. So the duplicate check keys
on the **full** `id`, never on `project` + `name` – which is the
tightening that looks natural and would break that use silently.

**Self-reference is a nonsense check, not cycle detection.** Cycles are
structurally impossible: a member pins a version that already exists, so
a set cannot reference anything containing it. Nothing here may grow
into a visited set or a depth limit.
