# Turn a Vector of Description Lines into cli Bullets

Each line is interpolated as a **value** rather than embedded as message
text, because a tag value may legitimately contain a brace and cli reads
`{anything}` in message text as markup. Embedding the lines directly
turns an artifact called `dm{1}` into a cli parse error instead of a
message.

## Usage

``` r
.datom_line_bullets(lines)
```

## Arguments

- lines:

  A character vector. Must be bound to the name `lines` in the frame
  that calls
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html),
  which is what the interpolation refers to.

## Value

A character vector of bullets, each named `*`.
