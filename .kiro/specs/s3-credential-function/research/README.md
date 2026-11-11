# Research scripts for the s3-credential-function spec

Throwaway probes run on 2026-10-27 (paws.common 0.8.8, paws.storage 0.9.0). Fake keys only; no
request goes to AWS. Each script does its work inside `main()`, because `on.exit()` at the top level
of `Rscript` never fires. Findings and how to rerun them: `../design.md`, "Proven mechanisms", and
`../requirements.md`, "Research".

- `paws-credentials/`: how paws picks the keys and the address a request uses. `capture_server.py`
  is a local stand-in for S3 that logs which access key signed each request.
- `saved-session/`: whether a saved R session writes a package's private memory. `credprobe` is a
  minimal package used only for this.
- `condition-handling/probe.R` (added 2026-11-10, purrr 1.2.1, rlang 1.1.7, testthat 3.3.2): how a
  credential failure fares on its way to the caller: a second handler beside `error =`, the
  catch-all's first line, `purrr` loops against `lapply()`, `expect_error(class =)` with and without
  `inherit = FALSE`, an rlang error's message text, and a function using a global in a fresh R. Run
  with `Rscript condition-handling/probe.R` from this folder; it prints each result.
