# Load Example Clinical Trial Data

Returns one of five small, made-up tables from a simulated clinical
trial of 48 subjects: demographics, exposure (dosing), lab results,
adverse events or vital signs. Set `cutoff_date` to get the data as it
stood on that date, which mimics a new data delivery each month;
[`datom_example_cutoffs()`](https://amashadihossein.github.io/datom/reference/datom_example_cutoffs.md)
lists the dates the examples use.

## Usage

``` r
datom_example_data(
  domain = c("dm", "ex", "lb", "ae", "vs"),
  cutoff_date = NULL
)
```

## Arguments

- domain:

  One of `"dm"` (demographics, 48 rows), `"ex"` (exposure, 48 rows),
  `"lb"` (labs, 720 rows: 3 visits x 5 tests per subject), `"ae"`
  (adverse events, ~80 rows), or `"vs"` (vital signs, 432 rows: 3 visits
  x 3 tests per subject, taken on the same dates as the labs).

- cutoff_date:

  Optional date string (`"YYYY-MM-DD"`) to filter rows whose primary
  date column is on or before this date, simulating a point-in-time EDC
  extract. The date column used per domain: `RFSTDTC` (dm), `EXSTDTC`
  (ex), `LBDTC` (lb), `AESTDTC` (ae), `VSDTC` (vs).

## Value

A data frame.

## Details

The data simulates STUDY-001, a Phase II study enrolling over six
months; table and column names loosely follow SDTM.

## Examples

``` r
# Full demographics
dm <- datom_example_data("dm")

# Month-3 snapshot (subjects enrolled by 2026-03-28)
dm_m3 <- datom_example_data("dm", cutoff_date = "2026-03-28")

# Labs collected through Month 3
lb_m3 <- datom_example_data("lb", cutoff_date = "2026-03-28")
```
