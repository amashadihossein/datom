# Simulate EDC data for datom vignettes
# Study: STUDY-001, Phase II, 48 subjects enrolled over 6 months
#
# Produces:
#   inst/extdata/dm.csv   -- Demographics (48 rows)
#   inst/extdata/ex.csv   -- Exposure (48 rows)
#   inst/extdata/lb.csv   -- Labs (~720 rows: 48 subjects x 3 visits x 5 tests)
#   inst/extdata/ae.csv   -- Adverse events (~80 rows: ~1.7 per subject)
#   R/sysdata.rda         -- study_cutoff_dates (named vector of monthly cuts)
#
# Vignettes filter these by enrollment / event date to simulate monthly
# EDC snapshots arriving over the life of the study.

set.seed(20260101)

n_subjects <- 48
months <- 6

# --- Enrollment dates: ~8 per month, spread across Jan-Jun 2026 --------------
enroll_dates <- as.Date("2026-01-05") + sort(sample(0:179, n_subjects))

# --- DM (Demographics) -------------------------------------------------------
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

# --- Treatment assignment (1:1 randomization) --------------------------------
arms <- rep(c("DRUG-X 200mg", "PLACEBO"), each = n_subjects / 2)
arms <- sample(arms)  # shuffle

# --- EX (Exposure) -- first dose on enrollment date --------------------------
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

# --- LB (Laboratory results) -------------------------------------------------
# 3 visits per subject (Week 1 / Week 4 / Week 12), 5 tests per visit.
# 48 * 3 * 5 = 720 rows.

lb_visits <- list(
  list(visitnum = 1L, visit = "WEEK 1",  offset_days = 0L),
  list(visitnum = 2L, visit = "WEEK 4",  offset_days = 28L),
  list(visitnum = 3L, visit = "WEEK 12", offset_days = 84L)
)

lb_tests <- data.frame(
  LBTESTCD = c("ALT", "AST", "GLUC", "HGB", "WBC"),
  LBTEST   = c("Alanine Aminotransferase", "Aspartate Aminotransferase",
               "Glucose", "Hemoglobin", "Leukocytes"),
  LBCAT    = c("CHEMISTRY", "CHEMISTRY", "CHEMISTRY", "HEMATOLOGY", "HEMATOLOGY"),
  LBORRESU = c("U/L", "U/L", "mg/dL", "g/dL", "10^9/L"),
  LBORNRLO = c("7", "10", "70", "12.0", "4.0"),
  LBORNRHI = c("56", "40", "100", "17.5", "11.0"),
  mean_val = c(28, 22, 90, 14.0, 7.0),
  sd_val   = c(8, 7, 12, 1.4, 1.6),
  stringsAsFactors = FALSE
)

lb_rows <- vector("list", n_subjects * length(lb_visits) * nrow(lb_tests))
i <- 1L
for (s in seq_len(n_subjects)) {
  for (v in lb_visits) {
    visit_date <- enroll_dates[s] + v$offset_days
    for (t in seq_len(nrow(lb_tests))) {
      tst <- lb_tests[t, ]
      raw <- round(stats::rnorm(1, tst$mean_val, tst$sd_val), 1)
      lo  <- as.numeric(tst$LBORNRLO)
      hi  <- as.numeric(tst$LBORNRHI)
      nrind <- if (raw < lo) "LOW" else if (raw > hi) "HIGH" else "NORMAL"
      lb_rows[[i]] <- data.frame(
        STUDYID  = "STUDY-001",
        DOMAIN   = "LB",
        USUBJID  = dm$USUBJID[s],
        SUBJID   = dm$SUBJID[s],
        VISITNUM = v$visitnum,
        VISIT    = v$visit,
        LBTESTCD = tst$LBTESTCD,
        LBTEST   = tst$LBTEST,
        LBCAT    = tst$LBCAT,
        LBORRES  = format(raw, nsmall = 1),
        LBORRESU = tst$LBORRESU,
        LBORNRLO = tst$LBORNRLO,
        LBORNRHI = tst$LBORNRHI,
        LBNRIND  = nrind,
        LBDTC    = format(visit_date, "%Y-%m-%d"),
        stringsAsFactors = FALSE
      )
      i <- i + 1L
    }
  }
}
lb <- do.call(rbind, lb_rows)
rownames(lb) <- NULL

# --- AE (Adverse events) -----------------------------------------------------
# ~1.7 events per subject (Poisson lambda = 1.7), capped at 4. Targets ~80 rows.

ae_terms <- data.frame(
  AETERM   = c("Headache", "Nausea", "Fatigue", "Dizziness",
               "Diarrhea", "Insomnia", "Rash", "Arthralgia"),
  AEBODSYS = c("Nervous system disorders", "Gastrointestinal disorders",
               "General disorders", "Nervous system disorders",
               "Gastrointestinal disorders", "Psychiatric disorders",
               "Skin and subcutaneous tissue disorders",
               "Musculoskeletal and connective tissue disorders"),
  stringsAsFactors = FALSE
)

ae_severity_levels  <- c("MILD", "MODERATE", "SEVERE")
ae_severity_probs   <- c(0.65, 0.28, 0.07)
ae_relationship_lvl <- c("NOT RELATED", "POSSIBLY RELATED", "RELATED")
ae_relationship_pr  <- c(0.55, 0.30, 0.15)
ae_outcome_lvl      <- c("RECOVERED", "RECOVERING", "NOT RECOVERED")
ae_outcome_pr       <- c(0.70, 0.20, 0.10)

n_events_per_subj <- pmin(stats::rpois(n_subjects, lambda = 1.7), 4L)

ae_rows <- list()
ae_idx <- 1L
for (s in seq_len(n_subjects)) {
  n_ev <- n_events_per_subj[s]
  if (n_ev == 0L) next
  for (k in seq_len(n_ev)) {
    # AE start: 1-150 days after enrollment, capped at 2026-06-30 study end
    start_offset <- sample(1:150, 1)
    aestdtc <- min(enroll_dates[s] + start_offset, as.Date("2026-06-30"))
    duration <- sample(1:21, 1)
    aeendtc  <- min(aestdtc + duration, as.Date("2026-06-30"))
    ae_rows[[ae_idx]] <- data.frame(
      STUDYID  = "STUDY-001",
      DOMAIN   = "AE",
      USUBJID  = dm$USUBJID[s],
      SUBJID   = dm$SUBJID[s],
      AESEQ    = k,
      AETERM   = sample(ae_terms$AETERM, 1),
      AEBODSYS = NA_character_,  # filled below from term
      AESEV    = sample(ae_severity_levels,  1, prob = ae_severity_probs),
      AEREL    = sample(ae_relationship_lvl, 1, prob = ae_relationship_pr),
      AEOUT    = sample(ae_outcome_lvl,      1, prob = ae_outcome_pr),
      AESTDTC  = format(aestdtc, "%Y-%m-%d"),
      AEENDTC  = format(aeendtc, "%Y-%m-%d"),
      stringsAsFactors = FALSE
    )
    ae_idx <- ae_idx + 1L
  }
}
ae <- do.call(rbind, ae_rows)
ae$AEBODSYS <- ae_terms$AEBODSYS[match(ae$AETERM, ae_terms$AETERM)]
rownames(ae) <- NULL

# --- Monthly cutoff dates ----------------------------------------------------
study_cutoff_dates <- as.Date(paste0("2026-0", 1:6, "-28"))
names(study_cutoff_dates) <- paste0("month_", 1:6)

# --- Write outputs -----------------------------------------------------------
if (!dir.exists("inst/extdata")) dir.create("inst/extdata", recursive = TRUE)

write.csv(dm, "inst/extdata/dm.csv", row.names = FALSE)
write.csv(ex, "inst/extdata/ex.csv", row.names = FALSE)
write.csv(lb, "inst/extdata/lb.csv", row.names = FALSE)
write.csv(ae, "inst/extdata/ae.csv", row.names = FALSE)

# Save cutoff dates as internal data
if (!dir.exists("R")) dir.create("R")
save(study_cutoff_dates, file = "R/sysdata.rda")

cat("Wrote inst/extdata/dm.csv (", nrow(dm), " rows)\n")
cat("Wrote inst/extdata/ex.csv (", nrow(ex), " rows)\n")
cat("Wrote inst/extdata/lb.csv (", nrow(lb), " rows)\n")
cat("Wrote inst/extdata/ae.csv (", nrow(ae), " rows)\n")
cat("Wrote R/sysdata.rda (study_cutoff_dates)\n")
