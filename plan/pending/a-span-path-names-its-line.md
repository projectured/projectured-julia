# A span path names its line

> **Kind:** plan · **Status:** in progress, 2026-10-13, on the branch
> `span-path-lines` (worktree `projectured-julia-span-path-lines`). The owner asked
> for it on 2026-10-13 (item 3 of the report after the landing of
> [a-text-block-holds-only-lines.md](../done/a-text-block-holds-only-lines.md):
> "1: yes"). No question is open. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [a-text-block-holds-only-lines.md](../done/a-text-block-holds-only-lines.md)

## 1. The goal

A `TextBlock` holds only `TextLine`s, so a run is always in a line. A `SpanPath`
is `[line, run]`, and a structural path to a run is
`.elements[i].elements[j].content{a:b}`. The helpers of `TextDocument.jl` that
also take `[i]` or `.elements[i].content{a:b}`, a run at the top of a block, take
only the path with the line step. A path without it names no run, so they answer
`nothing` for it, as for any other path that names no run.

## 2. What it touches

`source/platform/text/TextDocument.jl`:
- the comment over `SpanPath`;
- `_get_container`, `_span_at` and `_span_content`, which have a branch for a path
  of one index;
- `get_flat_base`, which answers the start of element `i` for `[i]`;
- `_parse_selection_range`, whose hop into a line is optional, and the comment of
  `_text_selection_range`;
- `_collect_image_paths`, which looks for an image at the top of a block.

No caller makes a path of one index (2026-10-13): every path comes from
`_text_span_infos`, `_parse_selection_range`, `_parse_line_span_path` or a test
that writes `Int[line, run]`.

## 3. Steps

1. **The helpers** take only `[line, run]`.
   *Built (2026-10-13).* `get_flat_base` and `_span_content` answer `nothing` for
   a path of another length; two comments that named "either depth" follow.
2. **The tests** of the text slice: `test_text_document`, `test_text_to_graphics`,
   the decorators, the inline images, and `test_platform` once.
3. **The plan** moves to `plan/done`.
