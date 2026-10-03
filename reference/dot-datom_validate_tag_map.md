# Validate a Tag Map

The tag grammar, in one place, shared by
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
(its `tags` argument), the member validator (each member's `tags`), and
the set write (set-level `tags`). A tag map is a named list whose values
are UTF-8 strings or arrays of them – no numbers, booleans, `null`, or
nesting.

## Usage

``` r
.datom_validate_tag_map(tags, what = "tags", remedy = NULL)
```

## Arguments

- tags:

  A named list, or `NULL` (no tags).

- what:

  Label used in error messages, e.g. `"tags"` or `"members[[2]]$tags"`.

- remedy:

  Optional `cli` bullet appended to every abort.

## Value

Invisibly `TRUE`.

## Details

Per-value type checking delegates to
[`.datom_sv1_as_strings()`](https://amashadihossein.github.io/datom/reference/dot-datom_sv1_as_strings.md),
the same coercion the hash encoder uses, rather than restating its
rules. That is deliberate: two copies of "what counts as text here"
would eventually disagree, and the encoder's messages already name the
offending key and the allowed types. What this function adds on top is
the **empty-label** refusal, which the encoder does not make – there,
`""` hashes as an ordinary label.

An empty value is **not** refused, because it is a tidy case rather than
an error: call
[`.datom_drop_empty_tags()`](https://amashadihossein.github.io/datom/reference/dot-datom_drop_empty_tags.md)
first, which every caller does.
