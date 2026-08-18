#!/usr/bin/env Rscript
# ==============================================================================
# check-spec.R -- mechanical consistency checks for a Kiro spec
# ==============================================================================
# Run:  Rscript dev/check-spec.R [spec-dir]
#       (spec-dir defaults to .kiro/specs/datom-sets)
#
# Why this exists
# ---------------
# The datom-sets spec went through six review rounds and every one found real
# defects. They clustered into a handful of mechanical patterns -- dangling
# cross-references after renumbering, criteria defined but never implemented,
# wrong line numbers in code citations, and superseded wording left standing as
# a live instruction. Those patterns are cheap to detect and expensive to find
# by reading.
#
# What it does NOT do
# -------------------
# It cannot find reasoning defects. In the review round that prompted it, the
# checks below would have caught roughly half the findings; the other half were
# things like "a required payload field has no public parameter" and "the
# integrity gate has no acceptance criterion". Those need a reader. This script
# reduces review load; it does not replace review.
#
# Only base R. No package dependencies, so it runs anywhere Rscript does.
# ==============================================================================

# --- setup --------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
spec_dir <- if (length(args) >= 1L) args[[1L]] else ".kiro/specs/datom-sets"
repo_root <- getwd()

SPEC_FILES <- c("requirements.md", "design.md", "tasks.md")

failures <- character()
notes <- character()

fail <- function(check, ...) {
  failures <<- c(failures, check)
  cat(sprintf("FAIL  %s\n", check))
  for (line in c(...)) cat(sprintf("        %s\n", line))
}

pass <- function(check, detail = "") {
  cat(sprintf("ok    %s%s\n", check, if (nzchar(detail)) paste0(" -- ", detail) else ""))
}

note <- function(check, ...) {
  notes <<- c(notes, check)
  cat(sprintf("note  %s\n", check))
  for (line in c(...)) cat(sprintf("        %s\n", line))
}

read_lines_safe <- function(path) {
  if (!file.exists(path)) return(NULL)
  readLines(path, warn = FALSE)
}

# Definitions live in specific files; references may appear anywhere.
spec_paths <- file.path(spec_dir, SPEC_FILES)
names(spec_paths) <- SPEC_FILES
spec <- lapply(spec_paths, read_lines_safe)
names(spec) <- SPEC_FILES

missing_files <- SPEC_FILES[vapply(spec, is.null, logical(1))]
if (length(missing_files) > 0L) {
  cat(sprintf("FATAL missing spec file(s) under %s: %s\n",
              spec_dir, paste(missing_files, collapse = ", ")))
  quit(status = 2L)
}

all_lines <- unlist(spec, use.names = FALSE)

cat(sprintf("Checking spec: %s\n\n", spec_dir))

# --- helpers ------------------------------------------------------------------

# Capture group 1 from every line matching `pattern`.
defs_from <- function(lines, pattern) {
  hits <- grepl(pattern, lines, perl = TRUE)
  if (!any(hits)) return(character())
  unique(sub(pattern, "\\1", lines[hits], perl = TRUE))
}

# Every occurrence of `pattern` across a character vector.
all_matches <- function(lines, pattern) {
  m <- regmatches(lines, gregexpr(pattern, lines, perl = TRUE))
  unique(unlist(m))
}

# --- check 1: dangling references ---------------------------------------------
# Every R/I/P/AC token referenced anywhere must resolve to a definition.

req_top <- defs_from(spec$requirements.md, "^### (R\\d+) .*$")
req_sub <- defs_from(spec$requirements.md, "^- \\*\\*(R\\d+\\.\\d+[a-z]?).*$")
ac_defs <- c(
  defs_from(spec$requirements.md, "^\\| \\*\\*(AC\\d+)\\*\\*.*$"),
  defs_from(spec$requirements.md, "^- \\*\\*(AC\\d+)\\*\\*.*$")
)
inv_defs <- defs_from(spec$design.md, "^\\| \\*\\*(I\\d+a?)\\*\\*.*$")
prop_defs <- defs_from(spec$design.md, "^\\| \\*\\*(P\\d+)\\*\\*.*$")

defined <- unique(c(req_top, req_sub, ac_defs, inv_defs, prop_defs))

TOKEN_RE <- "\\b(?:R\\d+\\.\\d+[a-z]?|R\\d+|AC\\d+|I\\d+a?|P\\d+)\\b"
referenced <- all_matches(all_lines, TOKEN_RE)

dangling <- setdiff(referenced, defined)
if (length(dangling) > 0L) {
  fail("dangling references", sprintf("referenced but never defined: %s",
                                      paste(sort(dangling), collapse = ", ")))
} else {
  pass("dangling references",
       sprintf("%d tokens referenced, all defined", length(referenced)))
}

# --- check 2: orphaned criteria -----------------------------------------------
# An AC / invariant / property that nothing references is either dead or
# unimplemented. Sub-requirements are exempt: they are covered by a task
# citing their parent (e.g. "Requirements: R1" covers R1.1-R1.4).

count_refs <- function(token) {
  # Number of lines mentioning the token. Its own definition line counts as 1,
  # so a total below 2 means nothing else refers to it.
  sum(grepl(sprintf("\\b%s\\b", token), all_lines, perl = TRUE))
}

orphan_candidates <- c(ac_defs, inv_defs, prop_defs)
orphans <- orphan_candidates[vapply(orphan_candidates,
                                    function(tk) count_refs(tk) < 2L,
                                    logical(1))]
if (length(orphans) > 0L) {
  fail("orphaned criteria",
       "defined but referenced nowhere else (dead, or defined-but-unimplemented):",
       paste(sort(orphans), collapse = ", "))
} else {
  pass("orphaned criteria",
       sprintf("%d AC/I/P all referenced", length(orphan_candidates)))
}

# --- check 3: task coverage ---------------------------------------------------
# Task numbers contiguous from 0, and every task states its acceptance
# criteria -- or says explicitly that it has none, so silence is never
# mistaken for an omission.

task_starts <- grep("^- \\[.\\] \\*\\*\\d+\\.", spec$tasks.md, perl = TRUE)
task_nums <- as.integer(sub("^- \\[.\\] \\*\\*(\\d+)\\..*$", "\\1",
                            spec$tasks.md[task_starts], perl = TRUE))

if (!identical(task_nums, seq(0L, length(task_nums) - 1L))) {
  fail("task numbering",
       sprintf("expected contiguous 0..%d, got: %s",
               length(task_nums) - 1L, paste(task_nums, collapse = ", ")))
} else {
  pass("task numbering", sprintf("contiguous 0..%d", max(task_nums)))
}

bounds <- c(task_starts, length(spec$tasks.md) + 1L)
no_acceptance <- integer()
for (i in seq_along(task_starts)) {
  body <- spec$tasks.md[bounds[i]:(bounds[i + 1L] - 1L)]
  if (!any(grepl("Acceptance:", body, fixed = TRUE))) {
    no_acceptance <- c(no_acceptance, task_nums[i])
  }
}
# Task 0 is the spec-creation chunk; it has no code and needs no criteria.
no_acceptance <- setdiff(no_acceptance, 0L)
if (length(no_acceptance) > 0L) {
  fail("task acceptance coverage",
       sprintf("task(s) with no `Acceptance:` clause: %s",
               paste(no_acceptance, collapse = ", ")),
       "state the criteria, or write `Acceptance: none by design` with the reason.")
} else {
  pass("task acceptance coverage", "every task states criteria or why it has none")
}

# --- check 4: code citation liveness -----------------------------------------
# The spec instructs readers to cite its line references rather than
# re-deriving them, so a wrong number propagates into code comments and commit
# messages. This asserts the cited line exists; it cannot assert the line says
# what the spec claims, so cited lines are printed for review.

cite_re <- "R/[A-Za-z0-9_.-]+\\.R:\\d+(?:[,-]\\d+)*"
citations <- all_matches(all_lines, cite_re)

out_of_range <- character()
cite_report <- character()

for (cite in sort(citations)) {
  parts <- strsplit(cite, ":", fixed = TRUE)[[1]]
  rel <- parts[[1]]
  nums <- as.integer(unlist(strsplit(parts[[2]], "[,-]")))
  path <- file.path(repo_root, rel)
  src <- read_lines_safe(path)
  if (is.null(src)) {
    out_of_range <- c(out_of_range, sprintf("%s (file not found)", cite))
    next
  }
  bad <- nums[nums < 1L | nums > length(src)]
  if (length(bad) > 0L) {
    out_of_range <- c(out_of_range,
                      sprintf("%s (file has %d lines)", cite, length(src)))
    next
  }
  shown <- trimws(src[[nums[[1]]]])
  if (!nzchar(shown)) shown <- "<blank line -- likely a wrong number>"
  cite_report <- c(cite_report, sprintf("%-28s %s", cite, shown))
}

if (length(out_of_range) > 0L) {
  fail("code citations", "citations pointing outside the file:", out_of_range)
} else {
  pass("code citations", sprintf("%d citations, all in range", length(citations)))
}

if (nzchar(Sys.getenv("SPEC_CHECK_SHOW_CITATIONS")) && length(cite_report) > 0L) {
  cat("\n  cited lines (review that each says what the spec claims):\n")
  for (line in cite_report) cat(sprintf("    %s\n", line))
  cat("\n")
}

# --- check 5: superseded wording ---------------------------------------------
# When a design decision is reversed, its old wording must not survive as a
# live instruction. MAINTENANCE RULE: reversing a decision includes adding its
# retired phrasing here. An occurrence is allowed only if a supersession marker
# appears within +/- 2 lines, which covers a struck-through table row or a
# paragraph that explains the removal.

retired <- c(
  "numbers always f64",
  "explicit R-type rule",
  "encoded-walk",
  "per-type leaf encoding",
  "three types to tag",
  "string-array",
  "cycle walk",
  "visited set",
  "depth limit",
  "or recurse",
  "all historical payloads are retained",
  "serialize -> parse -> encode",
  # Retired by the member-ordering delta: member order is no longer identity, so
  # every collection in sv1 is sorted and deduped with no carve-out. The old
  # wording survived in three places at once (requirements table, design
  # properties, task bullets), which is the exact defect pattern this list exists
  # for.
  "only unsorted concat",
  "only `concat` without a `sort`",
  "order is curatorial",
  "duplication *is* identity"
)
# Deliberately NOT listed: "manifest$tables". The phrase is load-bearing in the
# rename requirement itself ("manifest$tables becomes manifest$artifacts") and in
# the rejected-alternative table, so it can never be flagged usefully here. The
# risk it would have guarded -- code still writing a `tables` key -- lives in R/,
# which this script does not read.

# An occurrence is allowed when any of these appears within +/- 2 lines. Stems
# are used on purpose ("remov" covers remove/removed/removes) and negation cues
# matter as much as historical ones, since the commonest legitimate mention is a
# sentence saying the thing is NOT done.
MARKER_RE <- paste(
  # historical / supersession
  "supersed", "earlier draft", "retire", "remov", "revers", "formerly",
  "no longer", "~~", "SUPERSEDED",
  # prohibition
  "do not", "Do not", "deliberately not", "Deliberately NOT", "forbid",
  "not permitted", "permitted to creep", "must not",
  # negation / impossibility
  "\\bno depth", "\\bno visited", "\\bno cycle", "\\bNo cycle",
  "acyclic", "never", "cannot", "not needed", "not required",
  "impossible", "unrepresentable", "immaterial", "dissolve", "collapse",
  sep = "|"
)

violations <- character()
for (fname in SPEC_FILES) {
  lines <- spec[[fname]]
  for (phrase in retired) {
    hits <- grep(phrase, lines, perl = TRUE)
    for (h in hits) {
      window <- lines[max(1L, h - 2L):min(length(lines), h + 2L)]
      if (!any(grepl(MARKER_RE, window, perl = TRUE))) {
        violations <- c(violations,
                        sprintf("%s:%d  [%s]  %s", fname, h, phrase,
                                substr(trimws(lines[[h]]), 1L, 90L)))
      }
    }
  }
}

if (length(violations) > 0L) {
  fail("superseded wording",
       "retired phrasing with no supersession marker nearby:", violations,
       "either mark it historical, or delete it -- a live stale instruction is",
       "the defect class that has cost the most review rounds.")
} else {
  pass("superseded wording",
       sprintf("%d retired phrases, all marked where present", length(retired)))
}

# --- check 6: ASCII ----------------------------------------------------------
# dev/ and .kiro/ are Rbuildignored, but the spec's prose gets copied into
# roxygen and NEWS, where non-ASCII trips R CMD check.

non_ascii <- character()
for (fname in SPEC_FILES) {
  lines <- spec[[fname]]
  bad <- which(vapply(lines, function(l) any(utf8ToInt(l) > 126L), logical(1)))
  if (length(bad) > 0L) {
    non_ascii <- c(non_ascii, sprintf("%s:%s", fname,
                                      paste(bad, collapse = ",")))
  }
}
if (length(non_ascii) > 0L) {
  fail("ascii", "non-ASCII characters at:", non_ascii)
} else {
  pass("ascii", "all three files are ASCII-clean")
}

# --- summary ------------------------------------------------------------------

cat("\n")
if (length(failures) > 0L) {
  cat(sprintf("%d check(s) failed: %s\n", length(failures),
              paste(failures, collapse = "; ")))
  cat("Reminder: these checks are structural. They do not find reasoning\n")
  cat("defects -- a missing parameter, an untested invariant, an undefined\n")
  cat("edge case. Those still need a reader.\n")
  quit(status = 1L)
}

cat("All structural checks passed.\n")
cat("Set SPEC_CHECK_SHOW_CITATIONS=1 to print cited code lines for review.\n")
cat("These checks are structural only -- reasoning defects still need a reader.\n")
quit(status = 0L)
