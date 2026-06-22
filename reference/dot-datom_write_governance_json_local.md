# Write governance.json to Local Git Clone

Writes `content` to `{path}/.datom/governance.json`. The directory must
already exist (created during
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
or
[`datom_repo_attach_governance()`](https://amashadihossein.github.io/datom/reference/datom_repo_attach_governance.md)).

## Usage

``` r
.datom_write_governance_json_local(path, content)
```

## Arguments

- path:

  Absolute path to the root of the local data git clone.

- content:

  Named list from
  [`.datom_create_governance_json()`](https://amashadihossein.github.io/datom/reference/dot-datom_create_governance_json.md).

## Value

Invisible NULL.
