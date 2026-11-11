# Which purrr loops in datom can meet a storage request?
#
# Builds datom's internal call graph (codetools::findGlobals), marks every function that makes a
# storage request directly or through any function it calls, then lists every purrr iteration call
# whose mapped function reaches a marked one. purrr re-raises an error from the mapped function as
# its own (see probe.R), so each listed loop must be lapply()/vapply() for a credential failure to
# reach the caller as itself (design.md, section 5).
#
# The graph uses findGlobals(merge = TRUE): every global name a function mentions, so a function
# passed by name (lapply(x, .datom_verify_one)) is an edge too. merge = FALSE's $functions holds only
# names in call position and missed those (review 3, 2026-11-11). Over-reports rather than
# under-reports: a call that reaches storage only on some branch counts, and so does a variable that
# happens to share a function's name.
#
# Run from the datom repo root: Rscript .kiro/specs/s3-credential-function/research/condition-handling/purrr_loops.R
main <- function() {
  suppressMessages(pkgload::load_all(".", quiet = TRUE, export_all = TRUE))
  ns <- asNamespace("datom")
  names_all <- ls(ns, all.names = TRUE)
  fns <- Filter(function(n) is.function(get(n, ns)), names_all)

  calls_of <- function(f) {
    g <- tryCatch(codetools::findGlobals(f, merge = TRUE), error = function(e) character())
    intersect(g, fns)
  }
  direct_storage <- function(f) {
    txt <- paste(deparse(f), collapse = "\n")
    grepl("\\$client\\$|paws\\.storage::s3\\(", txt)
  }

  graph <- lapply(stats::setNames(fns, fns), function(n) calls_of(get(n, ns)))
  reaches <- vapply(fns, function(n) direct_storage(get(n, ns)), logical(1))
  repeat {
    before <- sum(reaches)
    reaches <- vapply(fns, function(n) reaches[[n]] || any(reaches[graph[[n]]]), logical(1))
    if (sum(reaches) == before) break
  }

  purrr_verbs <- c("map", "map_lgl", "map_chr", "map_int", "map_dbl", "map2", "imap", "imap_chr",
                   "walk", "iwalk", "keep", "discard", "pmap", "map_dfr", "some", "every",
                   "detect", "reduce", "compact")
  wraps <- setdiff(purrr_verbs, c("detect", "reduce", "compact"))

  fun_reaches <- function(expr) {
    if (is.name(expr)) {
      nm <- as.character(expr)
      return(nm %in% fns && reaches[[nm]])
    }
    f <- tryCatch(eval(expr, ns), error = function(e) NULL)
    if (is.function(f)) return(direct_storage(f) || any(reaches[calls_of(f)]))
    # a formula lambda (~ .x) or anything else: look at the names it mentions
    nms <- intersect(all.names(expr), fns)
    any(reaches[nms])
  }

  hits <- list()
  walk_ast <- function(e, owner) {
    if (!is.call(e)) return(invisible(NULL))
    head <- e[[1L]]
    if (is.call(head) && identical(head[[1L]], as.name("::")) &&
        identical(as.character(head[[2L]]), "purrr") &&
        as.character(head[[3L]]) %in% wraps) {
      args <- as.list(e)[-1L]
      fn_arg <- if (!is.null(args[[".f"]])) args[[".f"]] else if (length(args) >= 2L) args[[2L]] else NULL
      if (!is.null(fn_arg) && fun_reaches(fn_arg)) {
        hits[[length(hits) + 1L]] <<- data.frame(
          function_name = owner, verb = as.character(head[[3L]]), stringsAsFactors = FALSE
        )
      }
    }
    parts <- as.list(e)
    for (i in seq_along(parts)) {
      # an empty argument, as in x[, 1], is the missing symbol: skip it
      if (identical(parts[[i]], quote(expr = ))) next
      if (is.call(parts[[i]])) walk_ast(parts[[i]], owner)
    }
    invisible(NULL)
  }
  for (n in fns) walk_ast(body(get(n, ns)), n)

  out <- unique(do.call(rbind, hits))
  print(out[order(out$function_name), c("function_name", "verb")], row.names = FALSE)
  cat("\n", nrow(out), "purrr loops whose mapped function can reach a storage request\n")
  cat(sum(reaches), "of", length(fns), "functions can reach a storage request\n")
}
main()
