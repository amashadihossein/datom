# Say Which Commit Links Went Unrecorded, and Why

Split out so the wording lives next to the reasoning rather than inside
a branch. A warning rather than a refusal, and the reason is that
refusing would deadlock the only route out: the repair verb goes through
the same helper, so a stored history that will not parse could never be
replaced. That file is a projection for git-less readers and rebuilding
it is exactly what the repair is for – what must not happen is
rebuilding it in silence.

## Usage

``` r
.datom_warn_commit_shas_lost(name, lost)
```

## Arguments

- name:

  Artifact name.

- lost:

  Versions left with no commit recorded.

## Value

Invisibly `NULL`.

## Details

**It says that the unreadable copy is being replaced**, because of which
cause is the likelier one. The two are indistinguishable here, but a
reachable store holding bad bytes is more plausible than one that
refuses a read and accepts a write – and in that case this very
operation overwrites the evidence. Somebody who would have gone looking
should be told it will not be there. Worded as what this write does
rather than as a completed fact: the message is raised before the
upload, so a write that then fails leaves the bad copy in place.
