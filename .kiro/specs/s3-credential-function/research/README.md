# Research scripts for the s3-credential-function spec

Throwaway probes run on 2026-10-27 (paws.common 0.8.8, paws.storage 0.9.0). Fake keys only; no
request goes to AWS. Each script does its work inside `main()`, because `on.exit()` at the top level
of `Rscript` never fires. Findings and how to rerun them: `../design.md`, "Proven mechanisms", and
`../requirements.md`, "Research".

- `paws-credentials/`: how paws picks the keys and the address a request uses. `capture_server.py`
  is a local stand-in for S3 that logs which access key signed each request.
- `saved-session/`: whether a saved R session writes a package's private memory. `credprobe` is a
  minimal package used only for this.
