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
of the R session. See the credentials vignette
([`vignette("credentials", package = "datom")`](https://amashadihossein.github.io/datom/articles/credentials.html))
for best practices on supplying credentials safely.
