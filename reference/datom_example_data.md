# Load Example EDC Data

Loads bundled clinical trial example data (DM and EX domains) for use in
examples and vignettes. The data simulates a Phase II study (STUDY-001)
with 48 subjects enrolled over 6 months.

## Usage

``` r
datom_example_data(domain = c("dm", "ex"), cutoff_date = NULL)
```

## Arguments

- domain:

  One of `"dm"` (demographics) or `"ex"` (exposure).

- cutoff_date:

  Optional date string (`"YYYY-MM-DD"`) to filter subjects enrolled on
  or before this date, simulating a point-in-time EDC extract.

## Value

A data frame.

## Examples

``` r
# Full demographics
dm <- datom_example_data("dm")

# Month-3 snapshot (subjects enrolled by 2026-03-28)
dm_m3 <- datom_example_data("dm", cutoff_date = "2026-03-28")
```
