# Every Artifact in One Project, With Its Kind and Current Version, in One Read

The same single manifest read as
[`.datom_current_artifact_versions()`](https://amashadihossein.github.io/datom/reference/dot-datom_current_artifact_versions.md),
and the same refusal when it cannot be read – that function is built on
this one. The set sync preview needs two things the name-to-version
vector drops: each entry's **kind**, which each preview row reports and
which drops any kind this build does not know, and the **project name
the manifest records**, which is how a mislabelled source connection is
caught before it shows every artifact as new.

## Usage

``` r
.datom_current_artifacts(conn)
```

## Arguments

- conn:

  A connection to the project.

## Value

A list of `project_name` (the name the manifest records, or `NULL` when
it records none) and `artifacts`, a data frame of `name`, `kind` and
`current_version`, with `NA` for a field an entry does not record
usably.
