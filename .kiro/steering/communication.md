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

## Say what each block is for

I cannot tell background from a decision request from your own reasoning unless you label it.
Every section is one of these, and its heading says which:

| Label | Means | What I do with it |
|---|---|---|
| **TLDR** | the answer in 2-3 sentences | read first, often read only this |
| **What changes** | the concrete edits proposed | check it is what I wanted |
| **Why** | justification for something already settled | skim; challenge if it smells wrong |
| **FYI** | background, no action from me | skim or skip |
| **Need from you** | a question or an approval request | answer it |

- **Default order**: TLDR, What changes, Need from you. `Why` and `FYI` only when they earn a spot.
- **One purpose per section.** Never fold a question into a paragraph of background.
- **`Need from you` is the only section I must act on.** If it is empty, say "nothing needed".
- Every item under `Need from you` states **the default you will take if I say nothing**, so
  silence is safe and I only have to reply about the parts I disagree with.

### Asking me something

- **A question must be answerable without reading the rest of the message.** Restate its subject
  inside the question, even if you defined it two paragraphs earlier.
- **No type names or jargon inside a question.** "Should the record carry the error object?" is
  unanswerable -- three of those words are yours, not mine.
- **Name the two outcomes I am choosing between**, and what each one costs. Not the mechanism.
- If a question needs a paragraph of setup, the setup belongs inside the question, not in a
  section I am assumed to have read.

Too dense (real message, 2026-08-29):

> The record carries the real error object, not just its text, so the one caller that needs to
> re-raise it unchanged can.

Readable:

> When a read fails, R hands us a bundle describing the failure: the message text, plus a label
> saying what kind of failure it was. I can keep the whole bundle or just the text. Keeping the
> bundle lets one caller pass the original failure straight through, so its error looks exactly
> as it does today. Keeping only the text means building a fresh error, which changes the label
> even when the wording matches.

## No homework

**Every sentence stands on its own.** If understanding a point needs me to open a file, re-read a
task, or recall an old decision, it is not written yet.

- **Name a thing and gloss it in the same breath.** Not `.datom_update_manifest_entry()`, but
  "the function that updates one table's row in the local manifest".
- **A `file:line` reference is evidence, not an explanation.** Say what is there before citing it.
- **A task number is not a subject.** "Task 5 excludes it" tells me nothing. "We deliberately do
  not check this file here, because the check belongs at the front door" does.
- **Do not signal that something is significant -- say what happens.** "The dangerous one",
  "worth knowing", "reads as a contradiction", "the load-bearing detail" all promise a revelation
  and deliver a lookup. Give the consequence in plain words instead.
- If a point needs three layers of context, it is probably two points. Split it, or drop it and
  offer it on request.

## Length

- A design proposal or checkpoint fits **one screen**. Detail goes behind an offer -- "want the
  reasoning on the fixture choice?" -- not into the message by default.
- Volume is not thoroughness. If I cannot act on a paragraph, leave it out.
- Prefer one small table over five bullets that share a shape.

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

### Second example -- a point that sends me digging

Too dense (real message, 2026-08-29):

> One thing that reads as a contradiction, so stating it plainly: `R/sync.R:721` sits inside
> `.datom_update_manifest_entry()`, which is one of the four in-pipeline reads Task 5 excludes.
> Its **read** stays excluded; only its hand-built empty shape moves to the helper. That site is
> the dangerous one for Task 6, because it fires on a fresh or repaired repo and would write the
> old key after the rename.

Readable:

> **FYI, nothing needed from you.** One function writes a blank manifest from scratch when the
> file is missing. I am swapping that hand-written blank for a shared one, so a future change to
> the manifest shape has a single place to land.
>
> That function only runs on a brand-new or freshly repaired repo, which is why a later change
> could otherwise slip past it untested. I am not touching anything else in it.

What the first version did wrong: it named three things without saying what they are, used a task
number as if it were a subject, and flagged something as dangerous without saying what breaks.
