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

# Citations a reader is expected to follow: everything except those appearing
# only inside dated Decisions rows, which are frozen by policy and may record a
# number that was already known wrong.
dated_row_re <- "^\\| 20\\d\\d-\\d\\d-\\d\\d \\|"
live_lines <- c(spec$requirements.md, spec$design.md,
                spec$tasks.md[!grepl(dated_row_re, spec$tasks.md, perl = TRUE)])
live_citations <- all_matches(live_lines, cite_re)

out_of_range <- character()
blank_target <- character()
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
  # Show the first NON-BLANK line of the range, since a range's first line is
  # often the blank one above the thing being cited.
  cited <- trimws(src[nums[nums >= 1L & nums <= length(src)]])
  shown <- if (any(nzchar(cited))) cited[nzchar(cited)][[1L]] else ""

  # A citation whose ENTIRE range is blank is wrong by construction -- there is
  # nothing there to say what the spec claims. Added 2026-08-28 after an
  # insertion into R/utils-sha.R staled five citations while all nine checks
  # passed: two of the five had drifted onto blank lines, and this check reported
  # them only under SPEC_CHECK_SHOW_CITATIONS=1, without failing.
  #
  # SCOPE, both halves deliberate. Only an all-blank range fails: a range whose
  # first line is blank but which spans real content is cited correctly enough.
  # And a citation appearing ONLY inside a dated Decisions row is exempt, because
  # those rows are frozen by policy and some exist precisely to record a number
  # that was wrong (the 2026-08-17 row recording `R/read_write.R:217 -> 227`).
  #
  # LIMITATION: this catches the blatant half only. Three of those five drifted
  # onto real-but-unrelated lines -- a comment, a different constant -- and no
  # mechanical check can see that. The cited-lines report still needs an eyeball
  # after any insertion into R/.
  if (!any(nzchar(cited)) && cite %in% live_citations) {
    blank_target <- c(blank_target, sprintf("%s (every cited line is blank)", cite))
  }

  cite_report <- c(cite_report, sprintf("%-28s %s", cite,
                                        if (nzchar(shown)) shown else "<blank>"))
}

if (length(out_of_range) > 0L || length(blank_target) > 0L) {
  fail("code citations",
       c(if (length(out_of_range)) c("citations pointing outside the file:", out_of_range),
         if (length(blank_target)) c("citations resolving to nothing:", blank_target)),
       "re-derive by content, not by arithmetic: an insertion into R/ shifts every",
       "line below it, and SPEC_CHECK_SHOW_CITATIONS=1 prints each cited line.")
} else {
  pass("code citations",
       sprintf("%d citations, all in range and none blank", length(citations)))
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
  # Retired 2026-08-18 with the JSON write export (R12.4a, I14, AC23 retired;
  # P18 restated). The phrases below were live instructions for a capability
  # that is no longer being built, and each one reads authoritative on its own.
  "refuses managed keys",
  "refuses datom-managed keys",
  "payload-shaped key",
  "first general-purpose write path",
  # Task 19's AC33(a) anchoring was decided 2026-08-26. The old phrasing left the
  # implementer to settle it, which is the "hanging recommendation" failure this
  # spec's process notes keep flagging -- a decided item must not revert to
  # advisory wording.
  "Recommendation, not a decision",
  "recommendation, not a decision",
  "order is curatorial",
  "duplication \\*is\\* identity",
  "member order different",
  "member order.{0,20}differ",
  # Retired 2026-08-23 by Design A: a too-new MANIFEST makes a reader warn and
  # rebuild (R22.11), it does not abort. The old wording survived in AC32, R22.4,
  # P35 and P11 -- two of them a criterion and a property, i.e. the suite would
  # have asserted the opposite of the design. Phrases kept narrow on purpose:
  # "aborts at all five readers" is a LIVE statement of Task 5's form and must
  # not be caught.
  "aborts with the upgrade message at \\*\\*all\\*\\*",
  "convert the abort into a warning"
)
# Deliberately NOT listed: "manifest$tables". The phrase is load-bearing in the
# rename requirement itself ("manifest$tables becomes manifest$artifacts") and in
# the rejected-alternative table, so it can never be flagged usefully here. The
# risk it would have guarded -- code still writing a `tables` key -- lives in R/,
# which this script does not read.

# An occurrence is allowed when any of these appears within +/- 2 lines. Stems
# are used on purpose ("remov" covers remove/removed/removes).
#
# MAINTENANCE LESSON, 2026-08-17 -- keep this list NARROW. It previously also
# carried generic negation and impossibility cues ("never", "cannot",
# "not needed", "not required", "acyclic", "impossible", "unrepresentable",
# "immaterial", "dissolve", "collapse"), on the reasoning that the commonest
# legitimate mention is a sentence saying the thing is NOT done. That reasoning
# is wrong at scale: those words are ordinary vocabulary in this spec, so nearly
# every +/- 2 line window contained one and the check was close to vacuous.
#
# It was caught when the D2 delta (member order out of identity) left FIVE live
# or logged occurrences of retired ordering wording and this check passed on all
# five. The clearest case: requirements.md's "`members` is the only `concat`
# without a `sort`" ended with "is never a judgment call" -- the retired phrase
# SELF-SUPPRESSED on the word "never" in its own sentence.
#
# The tradeoff is deliberate. A false positive costs one author-added marker
# word; a false negative ships a retired instruction that reads authoritative.
# Only explicit supersession and explicit prohibition suppress a hit now.
MARKER_RE <- paste(
  # historical / supersession -- explicit only
  "supersed", "earlier draft", "retire", "remov", "revers", "formerly",
  "no longer", "~~", "SUPERSEDED",
  # prohibition -- explicit only
  "do not", "Do not", "deliberately not", "Deliberately NOT", "forbid",
  "not permitted", "permitted to creep", "must not",
  # the three nesting-machinery negations, kept because the retired phrases they
  # cover ("cycle walk", "visited set", "depth limit") are only ever mentioned
  # alongside them
  "\\bno depth", "\\bno visited", "\\bno cycle", "\\bNo cycle",
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

# --- check 6: duplicated content must agree ----------------------------------
# ROOT-CAUSE CHECK, added 2026-08-17.
#
# The two defect classes that survived three separate review sweeps were both
# duplicated content, and neither is reachable by a prose denylist:
#
#   1. The sv1 encoding pseudocode is written out in all three spec files. A
#      delta fixed design.md and left requirements.md and tasks.md stating the
#      opposite -- inside the task that freezes the golden vectors.
#   2. The acceptance-criteria count/range was hardcoded in four places and went
#      stale twice (stopped at AC26 omitting AC27; stopped at AC28 omitting AC29).
#
# So: compare the pseudocode blocks against each other rather than against a
# denylist, and forbid an explicit AC upper bound anywhere.

norm_code <- function(x) {
  x <- gsub("[[:space:]]+", "", x)
  x <- gsub("method=\"radix\"", "radix", x, fixed = TRUE)
  x
}

# One line per encoder rule. Keyed by the constructor being defined.
CODE_KEYS <- c("str(s)", "strset(v)", "map(m)", "member(x)", "set(p)", "data_sha")

code_lines <- list()
for (fname in SPEC_FILES) {
  for (key in CODE_KEYS) {
    hits <- grep(paste0("^\\s*", gsub("([().])", "\\\\\\1", key), "\\s*="),
                 spec[[fname]], perl = TRUE)
    if (length(hits) > 0L) {
      # a rule may wrap across lines; join until the parens balance
      collected <- character()
      for (h in hits) {
        buf <- spec[[fname]][[h]]
        j <- h
        while (nchar(gsub("[^(]", "", buf)) > nchar(gsub("[^)]", "", buf)) &&
               j < length(spec[[fname]])) {
          j <- j + 1L
          buf <- paste(buf, spec[[fname]][[j]])
        }
        collected <- c(collected, norm_code(buf))
      }
      code_lines[[key]] <- c(code_lines[[key]],
                             stats::setNames(collected, rep(fname, length(collected))))
    }
  }
}

code_mismatch <- character()

# ABSENCE, not only disagreement. Comparing present copies is not enough: delete a
# rule from one file and the remaining two still agree, so the check passed and --
# worse -- still reported "6 encoder rules consistent", because the key survived via
# the other files. Verified by deleting `str(s)` from requirements.md before this
# clause existed: PASS, exit 0.
#
# Two holes, both closed here:
#   one copy deleted  -> survivors agree      -> was PASS, now FAIL
#   all copies deleted -> key absent entirely -> was NOT EVEN CHECKED, now FAIL
#
# The second matters most for requirements.md, where R2.10 *defines* the encoding.
# If the formula vanishes there the requirement stops stating what it requires, and
# the next person to edit the encoder updates the two files that still carry it
# without ever learning a third did.
for (key in CODE_KEYS) {
  vals <- code_lines[[key]]
  missing <- setdiff(SPEC_FILES, names(vals))
  if (length(missing) > 0L) {
    code_mismatch <- c(
      code_mismatch,
      sprintf("%s is missing from: %s", key, paste(missing, collapse = ", ")),
      sprintf("    every encoder rule must appear in all %d spec files", length(SPEC_FILES))
    )
    next
  }
  if (length(unique(vals)) > 1L) {
    code_mismatch <- c(code_mismatch, sprintf("%s disagrees across files:", key),
                       sprintf("    %-18s %s", names(vals), unname(vals)))
  }
}

# No explicit AC upper bound: "AC1-AC28", "AC13-AC28", "twenty-eight acceptance"
ac_bound <- character()
for (fname in SPEC_FILES) {
  hits <- grep("AC[0-9]+\\s*-\\s*AC[0-9]+|(twenty|thirty)-[a-z]+ acceptance",
               spec[[fname]], perl = TRUE, ignore.case = TRUE)
  for (h in hits) {
    ac_bound <- c(ac_bound, sprintf("%s:%d  %s", fname, h,
                                    substr(trimws(spec[[fname]][[h]]), 1L, 90L)))
  }
}

if (length(code_mismatch) > 0L || length(ac_bound) > 0L) {
  fail("duplicated content agrees",
       "the same fact is stated twice and the copies disagree:",
       c(code_mismatch,
         if (length(ac_bound)) c("hardcoded AC bound (derive it instead):", ac_bound)),
       "this is the class a prose denylist cannot catch -- it survived three sweeps.")
} else {
  pass("duplicated content agrees",
       sprintf("%d encoder rules present in all %d files and agreeing; no hardcoded AC bounds",
               length(CODE_KEYS), length(SPEC_FILES)))
}

# --- check 7: ASCII ----------------------------------------------------------
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

# --- check 8: task cross-references resolve ----------------------------------
# Added 2026-08-23, when splitting Phase B shifted ten task numbers.
#
# Check 3 already asserts the task numbers themselves are contiguous. Nothing
# asserted that a `Task N` mention resolves to a task that exists -- and there
# were 68 such mentions pointing at Task 5 or later, across all three files plus
# historical Decisions rows. A stale one is worse than a stale code citation: it
# reads authoritative and sends the reader to the wrong chunk.
#
# LIMITATION, stated because a green run here is not proof: this catches a number
# with no task, not a number pointing at the WRONG task. "Task 6" where "Task 9"
# was meant resolves fine. It also only sees numbers directly after `Task`/`Tasks`,
# so the trailing items of a list ("Tasks 4 + 6", "Task 2, 8 and 9") are invisible.
# Those need the eyeball, same as check 4's citations.

task_refs_raw <- all_matches(all_lines, "\\bTasks? \\d+")
ref_nums <- unique(as.integer(sub("^Tasks? ", "", task_refs_raw)))
unresolved <- sort(setdiff(ref_nums, task_nums))

if (length(unresolved) > 0L) {
  fail("task cross-references",
       sprintf("referenced but no such task: %s",
               paste(sprintf("Task %d", unresolved), collapse = ", ")),
       sprintf("defined tasks: 0..%d", max(task_nums)),
       "renumbering is the usual cause -- sweep every file, including the",
       "Decisions log, and re-run.")
} else {
  pass("task cross-references",
       sprintf("%d distinct task numbers referenced, all defined", length(ref_nums)))
}

# Dated Decisions rows are FROZEN by policy (2026-08-23). A renumber adds one
# shift record and touches nothing else. This is a NOTE, not a failure: the rows
# legitimately contain task numbers, and no mechanical check can tell an
# as-of-date number from a swept one. It exists to fire at the one moment it
# matters -- when somebody is renumbering and is about to run a sweep.
frozen_rows <- grep("^\\| 20\\d\\d-\\d\\d-\\d\\d \\|", spec$tasks.md, perl = TRUE)
frozen_refs <- sum(grepl("\\bTasks? \\d+", spec$tasks.md[frozen_rows], perl = TRUE))
if (frozen_refs > 0L) {
  note("frozen decisions rows",
       sprintf("%d dated Decisions row(s) contain a `Task N` reference.", frozen_refs),
       "These are FROZEN. If you are renumbering, do NOT sweep them -- add one",
       "shift record instead (see the 2026-08-23 row). Three sweeps produced three",
       "crops of stale references, the last one half-done.")
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
