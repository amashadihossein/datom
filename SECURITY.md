# Security Policy

## Reporting a vulnerability

datom handles cloud storage credentials (AWS keys, GitHub PATs). If you
discover a security vulnerability, **please do not open a public GitHub
issue**.

Report privately by emailing <amashadihossein@gmail.com> with:

- A description of the vulnerability and its potential impact.
- Steps to reproduce, if applicable.

You should receive a response within 7 days. We will coordinate a fix
and disclosure timeline with you.

## Credential handling

datom never persists credentials to disk. Credentials are passed
explicitly at connection time and stored in memory only for the lifetime
of the R session. For best practices on supplying credentials safely
(keychain, environment variables, CI secret stores), see the “Start on
S3” article
([`vignette("start-on-s3", package = "datom")`](https://amashadihossein.github.io/datom/articles/start-on-s3.md))
and the package website.

Because `datom_store` objects hold credentials in memory as plaintext,
do not [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) a store or
save a workspace (`.RData`) that contains one – doing so would write
your AWS keys and GitHub PAT to disk in the clear. Rebuild the store
from your credential source (keychain / environment) in each session
instead.
