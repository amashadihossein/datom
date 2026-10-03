# Check the Caller's Extra Paths Before a Set Write Does Anything

`include_paths` is the **only** way a commit datom makes on its own
initiative may carry a path datom does not own, and it is allowed only
because the caller enumerated it (R14.3). What it buys is that checking
out a set version's commit yields the data pointers **and** the code and
environment that produced them. So every refusal here is a refusal to
produce a commit that would claim more than it holds.

## Usage

``` r
.datom_check_include_paths(conn, name, include_paths)
```

## Arguments

- conn:

  A `datom_conn` object with a local path.

- name:

  The set being written, as resolved by
  [`.datom_check_set_write_gates()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_set_write_gates.md).
  Named rather than discovered because a first write has no directory to
  discover.

- include_paths:

  The caller's character vector, or `NULL`.

## Value

Absolute paths in the clone, or `NULL`. **Absolute**, because
[`.datom_commit_and_mirror()`](https://amashadihossein.github.io/datom/reference/dot-datom_commit_and_mirror.md)
relativises what it is given against `conn$path`, and
[`fs::path_rel()`](https://fs.r-lib.org/reference/path_math.html) on an
already-relative path resolves it against the working directory instead
– which aborts with "files do not exist" pointing somewhere the caller
never named.

## Details

Four refusals, in this order, each with its own condition class:

1.  **Not a path inside the clone.** An absolute path, or one climbing
    out through `..`, refused lexically before the filesystem is
    touched. [`fs::path()`](https://fs.r-lib.org/reference/path.html)
    joins an absolute second argument *onto* the clone path rather than
    replacing it, so `/etc/passwd` would otherwise be reported as a
    missing path inside the repo – a correct refusal whose message names
    the wrong thing.

2.  **A datom-owned path.** `.datom/`, the set being written, and any
    artifact directory already in the clone. The write stages those
    itself, so listing one is either a misunderstanding or an attempt to
    hand-place a datom document into a commit through a caller's
    argument.

3.  **A path that does not exist.** An error, never a skip: a joint
    commit is deterministic or it is refused.

4.  **A path git is ignoring.**
    [`git2r::add()`](https://docs.ropensci.org/git2r/reference/add.html)
    on a gitignored path raises nothing and stages nothing, and
    [`.datom_git_commit()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_commit.md)
    cannot notice, because it objects only when the staging area ends up
    empty and datom's own files are always in it. The commit would
    therefore succeed while omitting exactly the file the caller named,
    and the set version would claim a joint commit it does not have.
    Refused rather than dropped in silence (decided 2026-09-18).

**This runs before the first hash and the first local write**, the same
placement as the two gates above, so a refused joint commit leaves
nothing behind. One consequence, stated so nobody later softens it:
change detection needs the hashes, so a bad path is an error **even when
the set is unchanged**. The refusal wins over the no-op.
