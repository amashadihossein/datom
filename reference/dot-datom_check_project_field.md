# Refuse a Project Name That Cannot Be Cited

The `project` field a metadata builder records exists to be quoted back
by whoever cites the artifact, so a missing value or an empty string
there is worse than no field at all: it reads as a project called
nothing. Checked in the builders rather than at the call sites, because
both builders take the value from the same place and a third caller will
eventually appear.

## Usage

``` r
.datom_check_project_field(project)
```

## Arguments

- project:

  The value passed to a builder's `project` argument.

## Value

Invisibly `TRUE`.

## Details

`NULL` passes. It means "not recorded", which is what every document
written before the field existed looks like, and what a direct builder
call in a test that is not about this field looks like.
