# The text of a syntax tree costs its lines, not its depth

> **Status: tentative.** This file records a fault for later work. It holds the
> measurements and the cause. No design is chosen, and nobody approved work on it.

## The fault

`SyntaxToText` makes, in each compound node, the whole text of the subtree of that
node. So a line of the text is made again in each compound above it, and the memory
of a print grows with the count of lines times the depth of the tree.

For each line of its subtree, a compound (`print_document` of `SyntaxCompoundToText`,
through `_splice_compound` and `_splice_result` in
`source/platform/syntax/SyntaxToText.jl`) keeps:

- a new `TextLine` in `elements`, because a compound moves the lines of its
  children by its own indentation and joins their first and last lines to its own;
- a cache key of that line in its `_DecoCache`, a tuple with a `Vector{UInt}` of the
  identities of the spans of the line, once in `spans` and once in `seen`;
- an entry in `chrome_lines`;
- each span of the line again, with a break and an indentation entry, in
  `flat_elements`.

## Measurements

Measured on 2026-11-15 on `main` `8541a3592`, with the stages of the fallback of the
natural renderer (`_make_natural_syntax_stages`) and a count of the lines that each
`SyntaxCompoundToTextIoMap` holds:

| Document | Lines of the text | Compounds | Lines that the compounds keep | Flat entries | Live memory |
| --- | --- | --- | --- | --- | --- |
| The reflected atom `task/stream_lines`, 44 objects deep | 21,818 | 27,428 | 1,226,673 (56.2 for each line) | 5,554,675 | 6,133 MB |
| The same atom with the two stream pages cut | 110 | 140 | 1,251 (11.4 for each line) | 5,313 | 47 MB |

For the large atom, the syntax stage alone keeps 252 MB, the text stage takes the
memory to 6,112 MB in 22 s, and the graphics stage adds 250 MB. The memory goes when
the IO map goes, so it is the cost of one print, not a leak.

The atom no longer reaches the reflection: the task slice draws a `TaskStreamLines`
alone with its own row. The fault stays for each other long and deep tree, for example
the reflection of any large object that the natural renderer has no row for, or a
deep JSON or Julia document.

## What a solution must keep

- The reference maps: a caret and a span of a child map through the flat offsets and
  the ranges of the children (`child_elem_ranges`, `own_spans`, `sep_indices`).
- The identity of a line that did not change, so that `TextToGraphics` keeps the cells
  of that line after an edit.
- A compound prints only its own level, and it does not walk the subtree below a child.

## Directions, not chosen

- A compound keeps only its own level, the offsets of its children and the change of
  indentation that it adds. The lines are made one time, at the root of the text, or
  when a reader reads them.
- A compound shares the `TextLine` of a child line that it does not change, and it
  makes a new line only for a line that it joins or moves.
- A bound on the size of the reflection in the fallback. This bound helps only the
  reflection, not a deep document of a domain.

## How to measure

Run this with `/home/projectured/workspace/bin/bounded-run` and a cap of 10 GB, in
`environment/all`. Give it a large document, such as an object with many nested
fields:

```julia
using ProjecturedPlatformExample
const E = ProjecturedPlatformExample
const S = E.SyntaxModule
(syntax, text) = S._make_natural_syntax_stages(E.Appearance())
context = E.PrinterContext(E.EmptyReference(), E.Cell(1200), E.Cell(800), Dict{Symbol,Any}())
iomap = E.print_document(E.ChainingProjection(syntax, text), nothing, document, context)
E.ProjecturedKernelExample.force_projected(E.get_iomap_output(iomap), -400)
# Walk the IO maps from `iomap` through `child_iomaps`, and add
# `length(x.output.elements)` for each `x isa S.SyntaxCompoundToTextIoMap`.
GC.gc(); Base.gc_live_bytes() ÷ 2^20
```
