# Work Out Which Commit First Produced Each of an Artifact's Versions

Walks the commits that touched `{name}/metadata.json`, oldest-first,
hashing the document as each commit left it. A commit whose document
hashes to version `V` is a commit that produced `V`, and the first one
reached is the one recorded – which is what makes a code-only commit
nobody's producer: it leaves that document untouched, so it is not in
the walk at all.

## Usage

``` r
.datom_git_commit_shas_by_version(repo_path, name)
```

## Arguments

- repo_path:

  Path to the local clone.

- name:

  Artifact name.

## Value

Named character vector, commit sha named by version. Empty when nothing
could be derived.

## Details

One version maps to one-or-more commits by design, because a version is
content-derived and code-invariant. Taking the oldest is not arbitrary
tie-breaking; it answers "where did this version come from".

A repo git cannot answer for – a shallow clone, a rewritten history, a
document that will not parse – yields no entry for the versions it lost.
Callers omit the field in that case rather than recording a blank.

**Every give-up here is silent on purpose**, and that is not a house
style: a version this cannot attribute is one the caller had no stored
value for either, since a stored value is what stops it being asked
about. So there is nothing to lose and nothing to report. The asymmetry
with reading the stored copy, where a failure does lose something, is
spelled out at the top of this file.
