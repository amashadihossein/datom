# Looking Ahead: datom in the daapr Stack

You’ve now seen datom’s core surface, from a single first extract
through monthly versioning, bulk imports, and data lineage. This article
steps back and frames where datom fits in the wider **daapr** ecosystem
– and, just as importantly, what datom deliberately does **not** do.

## What datom is

A versioned table store. That’s the whole product.

- A **table** is a data frame stored once per content (parquet, content
  addressed by a SHA over its bytes).
- A **version** is a metadata commit in git that points at a data SHA.
- A **project** is a private data git repo per study, combined with a
  storage location for parquet bytes. A shared governance repo for
  portfolio-wide registration is available on demand through the
  governance companion package.

Everything you’ve read in the previous nine articles is built from those
three primitives. The combination of *git for metadata* and *object
store for data* is what makes the whole system serverless, auditable,
and reproducible. (See [Serverless and Distributed by
Design](https://amashadihossein.github.io/datom/articles/design-serverless.md)
for the full argument.)

## What datom is not

The boundary is just as important as the surface:

- **datom is not a build system.** It versions inputs you hand it. It
  does not orchestrate transformations, schedule jobs, manage
  dependencies between tables, or know what a “derived dataset” is.
- **datom is not a query engine.**
  [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
  returns a data frame. Joins, aggregations, filters – those happen in
  your R session, in your analysis code, or upstack.
- **datom is not a UI.** There is no dashboard, no web app, no central
  service. The only “shared state” is the data git repo on GitHub and
  the parquet objects in S3 (or local filesystem). Both are durable and
  inspectable without datom.
- **datom is not a permissions system.** Access is whatever GitHub and
  your object store grant. datom reads and writes through your existing
  credentials; it does not layer authentication on top.

This list is deliberate. Each item exists to keep datom small enough
that the *next* layer can be opinionated without fighting the
foundation.

## The daapr stack

**daapr** – *data as a product, in R* – is the umbrella name for a small
family of packages that build on datom. The vision is a set of
tightly-scoped tools, each owning one job:

| Package | Role | Status |
|----|----|----|
| **datom** | Versioned table storage. Source of truth for raw + derived tables. | Shipped. |
| **dpbuild** | Construct **data products** – bundles of tables, derivations, metadata, and tests – from a datom-backed input set. Owns the build graph. | Planned. |
| **dpdeploy** | Promote and deploy data products to consumption environments. Owns release semantics. | Planned. |
| **dpi** | Consumer-facing access. The R package an analyst or app uses to *read* a published data product, without thinking about stores or version SHAs. | Planned. |

The arrows are one-directional: dpi reads from a deployed product;
dpdeploy publishes what dpbuild builds; dpbuild reads from datom. datom
does not know any of those packages exist – they consume its public API
the same way your analysis scripts do.

The split exists because the four jobs have genuinely different shapes.
A versioned table store wants to be tiny, durable, and boring (this
package). A build system wants opinions about graphs, caching, and test
discipline (dpbuild). A deploy tool wants opinions about environments,
approvals, and rollbacks (dpdeploy). A consumer client wants opinions
about discoverability, schema stability, and offline caching (dpi).
Bundling them produces a worse version of each.

## What this means for you today

You are reading the foundational layer. If you only ever use datom, you
have:

- Versioned, auditable tables.
- Reproducibility by SHA pin.
- Clean project teardown via
  [`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md).
- Cross-team handoff via the reader role.

That set is enough for many clinical workflows – particularly extract
management, simple monthly snapshots, and regulator-friendly history.

When the upstack packages ship, the work you’ve done here keeps working.
dpbuild will read tables out of datom the same way you do today. dpi
will pin to version SHAs the same way the audit script in the previous
article does. The contract is the public API of this package; nothing
about how you’ve structured your projects will need to change.

## Where to go next

- **Credentials**: PAT and AWS credential setup is shown inline where
  each store is built – see [First
  Extract](https://amashadihossein.github.io/datom/articles/first-extract.md)
  (local) and [Starting on
  S3](https://amashadihossein.github.io/datom/articles/start-on-s3.md)
  (S3).
- **Design Notes**: the articles under the *Design* group on the sidebar
  explain *why* datom looks the way it does. They’re not required
  reading – the user journey already runs end-to-end – but they’re the
  right next step if you want to extend datom or build on top of it.
- **Source**:
  [github.com/amashadihossein/datom](https://github.com/amashadihossein/datom).
  Issues and discussion welcome.
