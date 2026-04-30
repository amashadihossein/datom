# Load Example EDC Data

Loads bundled clinical trial example data for use in examples and
vignettes. The data simulates a Phase II study (STUDY-001) with 48
subjects enrolled over 6 months across four SDTM-flavored domains.

## Usage

``` r
datom_example_data(domain = c("dm", "ex", "lb", "ae"), cutoff_date = NULL)
```

## Arguments

- domain:

  One of `"dm"` (demographics, 48 rows), `"ex"` (exposure, 48 rows),
  `"lb"` (labs, ~720 rows: 3 visits x 5 tests per subject), or `"ae"`
  (adverse events, ~80 rows).

- cutoff_date:

  Optional date string (`"YYYY-MM-DD"`) to filter rows whose primary
  date column is on or before this date, simulating a point-in-time EDC
  extract. The date column used per domain: `RFSTDTC` (dm), `EXSTDTC`
  (ex), `LBDTC` (lb), `AESTDTC` (ae).

## Value

A data frame.

## Examples

``` r
# Full demographics
dm <- datom_example_data("dm")

# Month-3 snapshot (subjects enrolled by 2026-03-28)
dm_m3 <- datom_example_data("dm", cutoff_date = "2026-03-28")

# Labs collected through Month 3
lb_m3 <- datom_example_data("lb", cutoff_date = "2026-03-28")
```
