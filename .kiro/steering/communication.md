---
inclusion: always
---
# datom -- how to talk to me (agent communication style)

Applies to chat responses, checkpoint messages, and design proposals. It does **not** apply to
`R/` code comments, roxygen, spec documents, or commit messages -- those keep the existing
conventions in `.github/copilot-instructions.md`.

## The core rule

**Do not assume I hold the spec in my head.** I am reading your message cold, often days after
the decision it refers to. Explain the thing, then name it -- never the reverse.

## Format

- **1-2 sentences per point.** No paragraphs.
- **Short sections with plain headings.** I skim first, then drill into what matters.
- **Lead with the answer**, then the reasoning. TLDR at the top when the response is long.
- **Tag what needs me** in its own clearly-marked section. I should never have to hunt for the
  question.
- Keep bullets to one idea each. If a bullet needs a "because", split it.

## Language

- **Define jargon on first use in a conversation**, including datom's own terms. "Gate" means
  nothing to me cold; "a check at the door -- before datom uses the file, it looks at X and
  decides whether to proceed" does.
- **Prefer plain words over spec vocabulary.** "The check" beats "the gate". "Stop with a clear
  message" beats "abort".
- **Do not lead with spec IDs.** `R9.2`, `AC7`, `I4`, `P11` are lookup keys, not explanations.
  State the idea in plain terms; attach the ID in parentheses at the end if it is needed for
  traceability.
- **Avoid stacked code citations in prose.** A file:line list is fine in a table; it is noise
  mid-sentence.
- No filler openers ("Great question", "Let me explain"). No narrating what you are about to
  say.

## Substance

- **Give reasons, not scope citations.** "The spec says reader-side" is not a reason. If the
  honest reason is weaker than it first looked, say so plainly and re-derive it.
- **Verify before confirming.** When I ask "can you confirm X", check the code and answer with
  what you found -- including the parts that do not hold. Never confirm from memory.
- **Name gaps you are leaving open**, and say who owns them.
- **Explain a recommendation by consequence**, not by principle. "Stopping halfway through a
  write leaves a half-finished write" lands; "it violates the atomicity invariant" does not.
- Corrections: state the correction, move on. No apology paragraphs.

## Back-and-forth

- Expect follow-up questions and treat them as normal, not as a signal you were wrong.
- A question about the work is not approval to proceed (see rule 5b/5d/5e in
  `.github/copilot-instructions.md`).
- When I say I am not following, **restate from scratch in plainer terms** -- do not repeat the
  same explanation with more detail bolted on.

## Worked example

Too dense:

> The gate lands in `.datom_read_metadata()` per R9.2, refusing newer and tolerating older, with
> `schema_version` joining the volatile list at `R/utils-sha.R:412` to satisfy I4.

Readable:

> Every repo will start stamping a format number into its metadata.
>
> Before datom uses one of those files, it checks the number. Too new for this version of datom,
> it stops and tells you to upgrade. Missing or older, it carries on as normal.
>
> One extra edit: two field names get added to an exclusion list, so stamping the number does
> not accidentally change every existing table's version ID.
