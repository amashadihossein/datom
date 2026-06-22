# Write the Data-Side Governance Attachment Record

Writes `governance.json` – the data-side pointer recording which
governance repository a project is attached to. This is the data-repo /
data-storage half of attaching governance; the gov-repo registration
(writing `ref.json` and `dispatch.json`, committing to the gov repo) is
performed separately by the governance layer
(`datomanager::gov_attach()`).

## Usage

``` r
datom_repo_attach_governance(conn, gov_repo_url, gov_store, message = NULL)
```

## Arguments

- conn:

  A `datom_conn` object with `role = "developer"` and a local data clone
  (`conn$path`).

- gov_repo_url:

  HTTPS clone URL of the governance git repository to record.

- gov_store:

  A `datom_store_s3` or `datom_store_local` component for the governance
  storage. Only its location fields are persisted; credentials are
  discarded.

- message:

  Optional commit message. Defaults to
  `"Attach governance: {project_name}"`.

## Value

Invisibly, the SHA of the resulting data-repo commit.

## Details

`governance.json` is the canonical data-\>gov pointer in the
bidirectional governance link: the gov repo's `ref.json` points
gov-\>data, and this file points data-\>gov, so either repo can find the
other. It is written to two locations, mirroring the manifest pattern
(git canonical, storage derived):

- `.datom/governance.json` in the local data clone (git canonical),
  committed and pushed to the data repo.

- `{prefix}/datom/.metadata/governance.json` in data storage (derived
  mirror; a failed mirror write warns but does not abort – the git copy
  is canonical and readers with gov access resolve location from the gov
  repo).

Routing this write through datom upholds the two-repos invariant: the
governance layer never mutates the data repo directly.

## See also

[`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md),
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Data-side half of governance attachment (gov-repo registration is
# performed by datomanager::gov_attach()).
datom_repo_attach_governance(conn, gov_repo_url, gov_store)
} # }
```
