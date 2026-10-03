# Build the Relative Key for an Artifact's Current-State Metadata

Build the Relative Key for an Artifact's Current-State Metadata

## Usage

``` r
.datom_artifact_meta_key(name, which = c("metadata", "version_history"))
```

## Arguments

- name:

  Artifact name (validated).

- which:

  `"metadata"` for `metadata.json` (current state) or
  `"version_history"` for `version_history.json` (the version index).

## Value

Character relative key, e.g. `"dm/.metadata/metadata.json"`.
