# Simulate EDC data for tbit vignette
# Study: STUDY-001, Phase II, 48 subjects enrolled over 6 months
#
# Produces:
#   inst/extdata/dm.csv       — Demographics (all 48 subjects)
#   inst/extdata/ex.csv       — Exposure (all 48 subjects)
#   R/sysdata.rda             — study_cutoff_dates (named vector of monthly cut dates)
#
# The vignette filters these to simulate monthly EDC snapshots.

set.seed(20260101)

n_subjects <- 48
months <- 6

# --- Enrollment dates: ~8 per month, spread across Jan–Jun 2026 ---------------
enroll_dates <- as.Date("2026-01-05") + sort(sample(0:179, n_subjects))

# --- DM (Demographics) --------------------------------------------------------
dm <- data.frame(
  STUDYID  = "STUDY-001",
  DOMAIN   = "DM",
  USUBJID  = sprintf("STUDY-001-%03d", seq_len(n_subjects)),
  SUBJID   = sprintf("%03d", seq_len(n_subjects)),
  AGE      = sample(25:72, n_subjects, replace = TRUE),
  AGEU     = "YEARS",
  SEX      = sample(c("M", "F"), n_subjects, replace = TRUE, prob = c(0.55, 0.45)),
  RACE     = sample(
    c("WHITE", "BLACK OR AFRICAN AMERICAN", "ASIAN", "OTHER"),
    n_subjects, replace = TRUE, prob = c(0.55, 0.20, 0.15, 0.10)
  ),
  ETHNIC   = sample(
    c("HISPANIC OR LATINO", "NOT HISPANIC OR LATINO"),
    n_subjects, replace = TRUE, prob = c(0.18, 0.82)
  ),
  COUNTRY  = sample(c("USA", "CAN", "GBR"), n_subjects, replace = TRUE, prob = c(0.6, 0.25, 0.15)),
  RFSTDTC  = format(enroll_dates, "%Y-%m-%d"),
  DMDTC    = format(enroll_dates, "%Y-%m-%d"),
  stringsAsFactors = FALSE
)

# --- Treatment assignment (1:1 randomization) ---------------------------------
arms <- rep(c("DRUG-X 200mg", "PLACEBO"), each = n_subjects / 2)
arms <- sample(arms)  # shuffle

# --- EX (Exposure) — first dose on enrollment date ----------------------------
ex <- data.frame(
  STUDYID  = "STUDY-001",
  DOMAIN   = "EX",
  USUBJID  = dm$USUBJID,
  SUBJID   = dm$SUBJID,
  EXTRT    = arms,
  EXDOSE   = ifelse(arms == "DRUG-X 200mg", 200, 0),
  EXDOSU   = "mg",
  EXSTDTC  = format(enroll_dates, "%Y-%m-%d"),
  VISITNUM = 1L,
  VISIT    = "SCREENING",
  stringsAsFactors = FALSE
)

# --- Monthly cutoff dates -----------------------------------------------------
study_cutoff_dates <- as.Date(paste0("2026-0", 1:6, "-28"))
names(study_cutoff_dates) <- paste0("month_", 1:6)

# --- Write outputs ------------------------------------------------------------
if (!dir.exists("inst/extdata")) dir.create("inst/extdata", recursive = TRUE)

write.csv(dm, "inst/extdata/dm.csv", row.names = FALSE)
write.csv(ex, "inst/extdata/ex.csv", row.names = FALSE)

# Save cutoff dates as internal data
if (!dir.exists("R")) dir.create("R")
save(study_cutoff_dates, file = "R/sysdata.rda")

cat("Wrote inst/extdata/dm.csv (", nrow(dm), " rows)\n")
cat("Wrote inst/extdata/ex.csv (", nrow(ex), " rows)\n")
cat("Wrote R/sysdata.rda (study_cutoff_dates)\n")
