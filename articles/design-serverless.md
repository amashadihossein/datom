# Serverless and Distributed by Design

> **Companion to**: [Governing a Study
> Portfolio](https://amashadihossein.github.io/datom/articles/governing-a-portfolio.md).
> Read this when you want to understand what runs where — and what
> doesn’t run anywhere — when datom is in production.

There is no datom server.

Not “you can run it without one.” Not “we ship a default daemon you can
disable.” There is no datom server. There is no scheduler, no queue, no
API gateway, no health endpoint. The package you install is the entire
runtime, and it lives inside whatever R session happens to be using it.

This article explains why that’s the architecture, what falls out of it,
and what it costs.

## What datom needs to function

A working datom deployment needs exactly two infrastructural things,
both of which your organization almost certainly already has:

1.  **A git host.** GitHub, GitLab, internal Gitea — anything that
    speaks the git protocol over HTTPS. datom uses it for the data repos
    and the governance repo.
2.  **An object store.** S3, or a filesystem path that one or more
    machines can reach. datom uses it for parquet bytes (data store) and
    for the JSON files that readers without a gov clone fetch over the
    network (gov store mirror).

That’s it. No database. No application server. No long-running process
owned by datom. No hosted service from us.

## What runs where

When a developer commits a
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md),
the work happens **on their laptop**:

- Their R session computes the data SHA, serializes the parquet, writes
  metadata, stages git changes.
- Their R session uploads the parquet bytes to the object store using
  their object-store credentials.
- Their R session pushes the metadata commit using their git
  credentials.

When a reader calls
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md),
the work happens **on the reader’s machine**:

- Their R session resolves the project name through the gov store using
  their git/object-store credentials.
- Their R session fetches metadata, looks up the requested version’s
  data SHA, downloads the parquet bytes, returns the data frame.

There is no shared computation. There is no shared state outside the two
infrastructure pieces. Two developers writing to the same project at the
same time coordinate through git’s existing pull-before-push discipline,
not through a central lock manager. A reader far away from the writer
never has to talk to the writer’s machine — they both talk to the same
object store and the same git host.

## Why no server

Three reasons, in roughly the order they mattered to the design.

**Operational simplicity.** The single biggest cost of “managed data
tools” in clinical environments is the burden of running them. Whoever
runs the tool also has to keep its uptime, its backups, its secrets, its
upgrades, its compliance scope. A package that has no service has no
service to run. The git-host SLA and the object-store SLA become datom’s
SLA — both of which the organization is already paying for.

**Permission alignment.** Every credential a datom user needs is already
a credential the organization knows how to manage: git-platform PATs and
object-store IAM. There is no new auth surface, no new RBAC system to
onboard, no new audit log to ingest. When a person leaves the
organization, deprovisioning their git and cloud access deprovisions
their datom access automatically.

**Disaster recovery is your existing DR.** The data and the metadata
both live in services your organization already backs up, already
replicates across regions, already has runbooks for. There is no
datom-specific recovery path. If your git host comes back, your metadata
is back. If your object store comes back, your data is back. No
additional state to restore.

## What the absence of a server costs

Three things become harder, and we accept the trade.

**No real-time coordination.** datom does not push notifications.
“Someone wrote a new version of `lb`” is not an event datom emits; it is
a fact a teammate discovers next time they
[`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md).
For clinical pipelines that’s the right cadence — extracts arrive on a
weekly to monthly schedule, and the value of a real-time event bus is
low. For tighter loops, a thin notification layer can sit on top (GitHub
Actions, S3 event triggers); datom doesn’t ship one because the right
shape depends on the organization.

**No central enforcement of policy.** “Every write must include a PHI
review note in its commit message” is a policy you can document, review
in code review, and lint with a CI hook on the data repo — but datom
itself will not refuse a commit that lacks one. The trade-off is that no
central component knows about every project, so no central component can
be a single point of policy failure. Organizations that need server-side
enforcement layer a CI gate on top of their git host; the same hosting
they already trust to gate PRs.

**Heavier client.** A reader’s machine does the work a thin client might
offload to a server: parsing manifests, resolving versions, streaming
parquet. For most clinical analyses (datasets in the hundreds of MB to
single-digit GB) this is fine. For interactive querying of TB-scale
data, you don’t want to be reading parquet over the network into R; you
want a query engine. datom is not that, and points such workloads at
upstack tools.

## The “distributed by design” half

“No server” is one half. The other half is that datom is **trivially
distributable across machines**, because there’s no central state to
share.

- A new engineer joining a project:
  [`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md)
  on their laptop. No service to provision, no account to create.
- A new region or affiliate: same gov repo, same data store, same
  package. Or a regional gov mirror via the standard git mirroring
  features your host already supports.
- An air-gapped collaborator: hand them a tarball of the data git repo,
  the gov repo, and the parquet bytes; their datom works read-only
  against local filesystem stores using exactly the same code path the
  network setup uses. (This is what
  [`datom_store_local()`](https://amashadihossein.github.io/datom/reference/datom_store_local.md)
  enables on the writing side; the same mechanism applies to reading.)

The architecture is symmetric across machines on purpose. There is no
machine that has to be “the datom machine.” Any laptop with the package,
the credentials, and the network is a complete datom client.

## Where this leads

The serverless property is not a separate decision; it falls out of the
choices already made:

- Metadata in git — see [The datom Model: Code in Git, Data in
  Cloud](https://amashadihossein.github.io/datom/articles/design-datom-model.md).
- Two repos for project vs. organization scope — see [Two Repositories:
  Governance
  vs. Data](https://amashadihossein.github.io/datom/articles/design-two-repos.md).
- Indirection through `ref.json` for portable storage — see [`ref.json`
  and Always-Migration-Ready
  Storage](https://amashadihossein.github.io/datom/articles/design-ref-json.md).

If you’re picturing a deployment diagram for datom and feeling like
you’re missing something, you’re not. The diagram is your git host, your
object store, and the laptops of the people who use it. Nothing else.
