# Carry Unrecognised Top-Level Fields Onto a Rebuilt Document

Copies onto `rebuilt` every top-level field of `prior` whose name is not
in `known`, so a field this build cannot place survives being rewritten.

## Usage

``` r
.datom_carry_unknown_fields(rebuilt, prior, known)
```

## Arguments

- rebuilt:

  The document this build assembled, a named list.

- prior:

  The document that was already on disk, a named list, or `NULL` /
  anything unparsed when there was none – in which case there is nothing
  to carry and `rebuilt` is returned unchanged.

- known:

  Character vector of field names this build can place.

## Value

`rebuilt`, with the unrecognised fields of `prior` appended.

## Details

**Only unrecognised fields are carried, and that narrowness is the
design.** A field datom knows about keeps exactly the behaviour it has
today, including disappearing when this write does not set it.
`original_format` is the case that makes the difference concrete: a
table first imported from a CSV and later written straight from a data
frame has no format to declare, and the row is meant to stop claiming
one. Carrying every absent field forward instead of only the unplaceable
ones would leave that claim standing against a version it does not
describe – a wrong statement, which is worse than a missing one.

Where `rebuilt` already has a field, `rebuilt` wins. That cannot happen
for a genuinely unrecognised field, since this build only writes names
it knows; stating the precedence costs one term and removes the
question.

Top-level only, at each level separately. A field nested inside a value
datom does understand – inside `custom`, or inside the manifest's
`summary` block – is not this function's business: `custom` is carried
whole as one recognised field, and `summary` is a derived aggregate that
is meant to be recomputed.

A field whose value is JSON `null` gets no special handling. Absence in
a datom document is spelled by omitting the key, never by nulling it, so
such a field is already off-convention; it is carried, but a `null`
re-serialises as an empty object rather than as `null`.
