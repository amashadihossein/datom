# One Member's Tags as Key/Value Pairs

A member with no tags yields one pair of `NA` / `NA`, which is what
keeps an untagged member visible in a listing rather than absent from
it.

## Usage

``` r
.datom_tag_pairs(tags)
```

## Arguments

- tags:

  A tag map, or `NULL`.

## Value

A data frame of `key` and `value`, at least one row.

## Details

A key whose value is empty also yields `NA` rather than no row. The
writer drops such a key, so this reaches only a hand-built payload – and
there the key IS in the document, so reporting the key with no value
states what is there while dropping the row would not.

**THE MAP IS READ BY POSITION, NEVER BY NAME, AND THAT IS THE WHOLE
POINT OF THE FUNCTION.** A tag map can carry the same key twice –
`jsonlite` parses `{"type": "output", "type": "baseline"}` into two
same-named elements, and a caller can write
`list(type = "a", type = "b")` – and nothing on the read side refuses
it, because a reader does not validate a tag map. `tags[["type"]]`
returns the **first** match every time, so a by-name read reports one
label twice and loses the other: the member lists a value it does not
have, vanishes from a branch it belongs under, and cannot be found by
the label the document says it carries. Verified in all three verbs
before this was positional.

That is the file header's one-expander rule reappearing on the **key**
axis. Having one expander closed the silent-first-value spelling on the
*value* axis; reading that expander's own input by name reopened the
identical failure one level up.

Duplicate keys are therefore treated exactly as one multi-valued key
would be, which is also what they mean. Identical pairs are **not**
collapsed across duplicate keys: the read reports what the document
holds, and deduplicating here would be a reader canonicalizing.
