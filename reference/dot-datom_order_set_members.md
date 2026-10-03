# Deduplicate and Order a Member List for the File

Drops exact duplicates – same `id` **and** same `tags` – by `datom-sv1`
member digest, then sorts by `project`, `name`, `version`.

## Usage

``` r
.datom_order_set_members(members)
```

## Arguments

- members:

  An unnamed list of validated member records.

## Value

The members, deduplicated and ordered.

## Details

**Two sort keys exist and each has its own reason.** The identity hash
orders member digests, which is what keeps the encoder from having to
know what an `id` looks like. The file orders by name, which is what
keeps an entry in place when its tags change so that `git diff` shows
one changed field. `version` is in the key because two versions of one
name are legal members, and would otherwise have no defined relative
order.

**No tiebreaker is required, and none may be added.** The only way two
members can share `project` \|\| `name` \|\| `version` is the same `id`
with *different* `tags`, which survives dedup because the digest covers
tags – and that payload is refused one step later. R's radix sort is
stable, so the tie resolves to caller order in the meantime. A defensive
tiebreaker would be dead code.

Runs **after** validation, unlike the rest of canonicalization, because
the digest is computed by the identity encoder and the encoder refuses a
value it cannot encode. Reaching it first would report a bad tag value
in the encoder's words rather than the validator's.
