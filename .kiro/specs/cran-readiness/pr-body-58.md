Finishes the required items from #58 (items 1–3):

1. **`cran-comments.md`** — filled in real CI results from the post-merge R-CMD-check run (R 4.6.1 + 4.5.3, four platforms, 0E/0W/0N).
2. **`\dontrun{}` rationale** — added an "Examples note" section explaining why credential/network-gated functions use `\dontrun{}`.
3. **API-stability line in `NEWS.md`** — added "datom is experimental: the API may change without a deprecation cycle until it reaches a stable release" to align with the lifecycle badge.

Items 4–5 (lifecycle package wiring, README channels note) are deferred as optional nice-to-haves per the issue.

## What was tested

No code changes — docs only. CI will confirm the build still passes.
