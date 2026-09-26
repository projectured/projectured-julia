# The word wrap is local to each paragraph

**Status: pending, not started.** The design came out of
[paragraph-partial-render.md](../done/paragraph-partial-render.md), where it was
deferred because the Markdown page did not need it.

## Problem

A key in one paragraph of a plain text repaints the whole text. Measured on main,
2026-09-26, with the dirty-rectangle probe (a text of four paragraphs, an edit of
paragraph 2 that keeps its height):

| Pipeline | Dirty rectangle |
| --- | --- |
| `TextToGraphics` alone | only paragraph 2 |
| `WordWrapping` → `TextToGraphics` | the whole block |
| a `.txt` file, as the binary opens it | the whole block |

`WordWrapping` wraps the whole block in one cell (`both` in
`source/text/WordWrapping.jl`) and makes new sub-spans after each edit, so every
line below is new to `TextToGraphics`. The binary draws every `TextDocument` and
every `.txt` file through it.

A Markdown page does not have the problem: `MarkdownRootToVerticalLayout` gives
each block its own chain, so each paragraph has its own `WordWrapping`. The SDL
backend is ready: its walk compares the place of a paragraph by value, so a
paragraph below an edit that keeps its place is not repainted.

## Design

For a `TextBlock` of spans and `TextNewline` elements (the `TextDocument` row of
the binary, and every prose chain that holds more than one paragraph):

- `WordWrapping` groups its input into hard paragraphs at `TextNewline` elements.
  The grouping reads the structure only, as `_line_groups` of `TextToGraphics`
  does. Each paragraph has its own wrap cell, which reads only its own spans and
  the wrap width, and its own table of `WrapSegment`s.
- The output keeps one container for each paragraph, so a content edit does not
  change the membership of the output.
- `TextToGraphics` gives each paragraph container its own canvas and its own line
  cells, with a `y` chain of paragraphs. The stack reads only the count of
  paragraphs.

## Open choice for the owner

The container of a paragraph in the output of `WordWrapping`:

- a nested `TextBlock` for each paragraph, or
- a `TextLine` that may hold soft breaks.

Both change the flat offsets (`get_flat_offsets`, `TextBlockToString`) and the
mapping of the selection through `WordWrapping`.

## Limits that stay

- A `.txt` file opens as one `PrimitiveString`, which is one cell, so it stays
  whole-dirty: every cell below it goes stale on each key. Only a change of what a
  `.txt` opens as would change that.

## Steps

- [ ] 1. The owner chooses the container of a paragraph.
- [ ] 2. `WordWrapping` wraps each paragraph in its own cell, into that container,
  with the mapping of the selection and the flat offsets.
- [ ] 3. `TextToGraphics` lays out each container in a canvas of its own.
- [ ] 4. Check with the dirty-rectangle probe (the method is in
  [paragraph-partial-render.md](../done/paragraph-partial-render.md)) and a test
  in `test/sdl/backend/DirtyRectTest.jl` or a text test: an edit of paragraph 2
  that keeps its height repaints paragraph 2 only.
