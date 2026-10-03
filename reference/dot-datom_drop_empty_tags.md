# Drop Tag Keys Whose Value Is Empty

The one tidy rule this file owns: a key that points at nothing is
removed, because a tag with no values is spelled by omitting the key.
Note this is about a tag *value*, not about a member having no tags at
all – a member with no tags is the ordinary case and is simply accepted.
Nothing is lost here – an empty value states no fact – and leaving it in
would be worse than cosmetic: a present key with an empty value hashes
differently from an absent key, so the same fact would mint two
different `data_sha` values.

## Usage

``` r
.datom_drop_empty_tags(tags)
```

## Arguments

- tags:

  A named list, or `NULL`.

## Value

`tags` with empty-valued keys removed; `NULL` unchanged. A non-list is
returned untouched, so the validator reports the type rather than this
function failing on it.

## Details

Covers both empty spellings R produces. `character(0)` is the documented
one; `NULL` is what an absent value looks like when a tag map is
composed programmatically (`list(domain = f())` where `f()` returned
nothing), and it means exactly the same thing. Note the encoder still
refuses a `NULL` value, and must: there it arrives from a parsed file
rather than from a caller, so there is no caller intent to tidy toward.

Full canonicalization – sorting keys, sorting and deduplicating values,
unboxing single values, ordering members – is **not** done here. It
belongs to the set write, so that canonical form has exactly one
implementation.
