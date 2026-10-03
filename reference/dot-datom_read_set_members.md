# Turn a Parsed Member List into Resolvable Member Records

Turn a Parsed Member List into Resolvable Member Records

## Usage

``` r
.datom_read_set_members(members, name)
```

## Arguments

- members:

  The payload's parsed member list.

- name:

  The set's name, for error messages.

## Value

An unnamed list of member records, each carrying `$fetch`.
