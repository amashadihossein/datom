# Check Whether a Storage Namespace is Free

Checks for the existence of `.metadata/manifest.json` in the target
namespace. If found, the namespace is occupied by an existing datom
project and this aborts with `datom_namespace_occupied`, naming the
occupying project when it can be read.

## Usage

``` r
.datom_check_namespace_free(conn, overridable = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object (typically a temporary conn built by
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  before the repo is fully initialised).

- overridable:

  Whether the caller honours `.force` as a way past an occupied
  namespace. `TRUE` (the default) adds that route to the refusal's
  recourse; `FALSE` says the override does not apply and why.

  **It exists because this function cannot know its caller's policy,
  which is the same reason the backend label is an argument's worth of
  work rather than a constant.** A product repo is checked with no
  opt-out, so a static "pass `.force = TRUE` to override" bullet sent
  exactly those users into a flag that changes nothing – a message
  routing somebody in a circle, which is the failure this function's own
  backend-neutral wording was fixed for one commit earlier.

## Value

Invisible `TRUE` when the namespace is free. Aborts with class
`datom_namespace_occupied` when it is occupied, or
`datom_namespace_unverified` when the store could not be reached.

## Details

Checks for the object first (cheap) and only reads the manifest when the
namespace is occupied, to extract the project name for the error
message.

**A store this connection cannot reach means *unknown*, and unknown
fails closed.** It used to warn and continue, which was not a deferral
of the check but a silent removal of it:
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
went on to push the git repo and then aborted at the manifest upload,
and the recovery it pointed at performs no occupancy check of any kind.
So the tolerance never produced a working offline init – storage is
required to finish one – and its only reachable effect was getting past
this check, with the outcome being a manifest written over another
project's. Refusing here instead names the real problem at the moment it
is known, rather than surfacing later as an unrelated upload failure.

There is no `.force` advice in that refusal, deliberately: `.force`
skips this check but not the manifest upload, so it cannot rescue an
init without storage either. Offering it would be advice that does not
work.

**The tolerated-failure detection lives here, around the one call that
touches storage**, rather than in a handler wrapping this whole function
– which is what the caller used to do. That shape had two defects worth
not reintroducing: it recognised the occupied refusal by **matching its
message text**, so rewording the message would have quietly downgraded a
refusal to a warning; and it swallowed anything it could not recognise,
so any abort added to this function later would have been downgraded
too, with nothing failing to say so.

**The condition classes are what callers dispatch on** – never the
message.
