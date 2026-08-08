# Wrap an embedded alien document in a widget card

An embedded document — a JSON file, a Julia definition, an XML tree — renders
today as a bare block in the page. It carries no frame, no title and no fold, so
a reader cannot see where the host page stops and the embedded document starts.

This plan puts the embedded document in a `WidgetCard`, in markdown and in RST,
and fixes the embed machinery that the card needs.

## What exists now

**Markdown.** A page is a stack of blocks:
[MarkdownToLayout.jl](../../package/domain/main/markdown/MarkdownToLayout.jl)
rewraps `MarkdownRoot` into a `VerticalLayout` and each block re-enters the
natural renderer by its own type. An embed is a `ReferenceStub` or a
`FileDocument`;
[EmbedToSyntax.jl](../../package/domain/main/insertion/EmbedToSyntax.jl) prints
the value the marker stands for through `recursion`. The graphics table names
the two rules in
[NaturalProjection.jl:222-223](../../package/domain/main/insertion/NaturalProjection.jl#L222-L223).
A resolved embed is therefore already its own graphics block. Only the frame is
missing.

**RST.** The slice has no marker vocabulary, so no alien document can be
embedded at all. `RstDocument` is also absent from `natural_to_syntax_dispatch`,
and there is no block-stack rewrap.

**The card.** `WidgetCard.content` is typed `Any`, and
`WidgetCardToGraphicsCanvas` recurses a `Document` content through the outer
renderer
([WidgetToGraphics.jl:3704](../../package/visual/main/widget/WidgetToGraphics.jl#L3704)).
The card declines both reference maps
([WidgetToGraphics.jl:3758-3759](../../package/visual/main/widget/WidgetToGraphics.jl#L3758-L3759)),
its build cell never reads `collapsed`, and its keyboard route declines every key
while `w.selection` reads nothing
([WidgetToGraphics.jl:3749](../../package/visual/main/widget/WidgetToGraphics.jl#L3749)).

The save path is separate and stays by marker: `document_to_text` runs the domain
projection alone. Every step below is a read-side change and cannot change a
file on disk.

## Decisions

**The card owns a reference step.** The card's reader is transparent today: it
routes a press by coordinate and returns the child operation unchanged. That
contradicts the card's own document shape, where the body hangs off `.content`.
Make the card honest, the way `WidgetScrollPaneToGraphicsCanvas` already is: the
backward map and the reader prepend `content`, and the forward map matches
`content` and descends. The embed wrapper then strips that one step. A single
rule in one place beats two conventions.

**The card is built once, in a cell.** A card rebuilt on every print gives the
child a new identity, and the IO map cannot reuse the child. Build it in a
`ComputedCell` that reads only the embedded value.

**One card, never two.** *(found while implementing)* A marker naming a whole
file evaluates to a `FileDocument`, whose own rule frames it. The stub rule
therefore leaves a value that frames itself alone, or `<<file("data.json")>>`
draws a card inside a card, titled twice. Whether a card really stands in the
way is asked of the printed child (`inner.input isa WidgetCard`), not of the
projection, so both maps and the reader agree with what was printed.

**A card header names the embed.** *(found while implementing)* The marker text
makes a noisy title: `<<definition(file("steps.jl"), "packet_queue_step")>>`
fills the header. A marker gives up its last quoted name instead, so the card
reads `packet_queue_step`. A marker that names nothing keeps its own text.

**A collapsed card keeps its child IO map.** Do not move the content recursion
inside the build cell. Recursion inside a rebuilt cell re-prints the whole
embedded document on every repaint. Print the child once, outside, and let the
build cell decide whether to place it.

**The RST marker is a directive.** `.. pred-ref:: <<file("data.json")>>` needs no
parser change: an unknown directive already parses into
`RstDirective(name, argument)`
([RstParser.jl:555](../../package/domain/main/rst/RstParser.jl#L555)) and emit
writes it back. A comment body would need a new rule for the same result.

**Inline RST markers wait.** Markdown splits a text run around a marker written
in a line of prose. RST gets block markers first; the inline case is a later
step and is not needed for a card, which is a block.

## Part A — fix the embed machinery

These three steps are shared. Do them first: parts B and C both need them.

### A1. Give `WidgetCardToGraphicsCanvas` real reference maps

File: [WidgetToGraphics.jl](../../package/visual/main/widget/WidgetToGraphics.jl)

1. Replace the two `nothing` maps at line 3758.
2. Forward: match `FieldReferenceStep("content")`, descend into the content
   entry of `child_iomaps`, and shift a `PointReferenceStep` result by the
   entry's `(x, y)` plus the child canvas origin. `_shift_child_image` in
   [LayoutToGraphics.jl:398](../../package/visual/main/layout/LayoutToGraphics.jl#L398)
   is the model. The build cell already stores `(padding, y, cim)`, so the offset
   is in hand.
3. Backward: prepend `FieldReferenceStep("content")`, as the scroll pane does at
   line 3133.
4. ~~Give the outer canvas a computed `selection`.~~ **Dropped.** Nothing reads
   a graphics canvas's `selection`: the caret is drawn by `TextToGraphics` from
   the text document's own selection, and the syntax layer is the only reader of
   `output.selection`. The cell would have been dead weight on every card.
5. Re-root in the reader: the press route and the keyboard route must prepend
   `content` to a path-bearing operation the content returned. An
   `InvokeActionOperation` names its own target and passes on unchanged.
   `reroot_operation` does the work; a self-contained operation (a hover flag, a
   control's activation) passes through it unchanged.
6. **A card has two document slots, not one.** Its header is a `Document` too, so
   the reader cannot re-root every child answer with `content` the way the scroll
   pane does. `_card_route` names the slot the answering child sits in.

No container widget maps forward today, so this is new ground in this file.
Expect the pointer paths (`_route_click_to_children`,
`_route_crossing_to_children`, `_route_move_to_children`,
`_route_downup_to_children`) to need the same re-rooting, and check each one.

**Warning.** This changes behaviour every card shares. The one card with a
document body today is the conversation composer
([ConversationEditor.jl:477](../../package/domain/main/conversation/ConversationEditor.jl#L477)).
Run `test_conversation_editor()` before and after, and read the counts.

**Done.** `test_widget_button_behavior()` and `test_conversation_editor()` pass
unchanged: every operation those cards return carries its own root, so
`reroot_operation` passes them through.

**Not fixed, and pre-existing.** Forward mapping a caret inside an embed to a
coordinate answers `nothing` through the whole graphics chain — measured with
the card and, on the same page, with the bare rules. The card is not the cause,
and the caret still draws, because `TextToGraphics` draws it from the embedded
document's own selection. Left alone.

### A2. Let a card with a document body fold

File: [WidgetToGraphics.jl](../../package/visual/main/widget/WidgetToGraphics.jl)

1. Read `w.collapsed` inside `_card_build`.
2. When the card is collapsed, do not push the content entry and do not add its
   height. Keep the recursed `cim` alive outside the build cell.
3. Check that the header click already produces `ToggleCollapseOperation`, and
   that the default handler flips the cell. It does — but only when the title is
   a `Document`, so the embed card's header is a reactive layout holding a
   chevron label, the way `_collapsible_card` in `ObjectToWidget` builds one.

**Done.** A fold drops the body and its height; unfolding restores the same
child IO map, so nothing re-prints. Asserted in `test_object_to_widget()`.

### A3. Make the `section` marker verb dispatch on the document

Files: [FileProject.jl](../../package/base/main/serialization/FileProject.jl),
[MarkdownFile.jl](../../package/domain/main/markdown/MarkdownFile.jl),
[RstFile.jl](../../package/domain/main/rst/RstFile.jl)

`register_marker_function!` writes into a `Dict` keyed by the verb, and the last
call wins. Markdown registers `:section` in its `__init__`. The moment RST
registers `:section` as well, one of the two formats loses its verb, and the
failure is silent and load-order dependent.

1. Add a generic `document_section(document, title)` to `FileProject`, and
   register `:section` once, in `FileProject.__init__`.
2. Markdown adds the method for `MarkdownRoot`, and moves the body of
   `markdown_section` behind it.
3. RST adds the method for `RstRoot` and `RstSection`, over the `rst_section`
   that already exists.
4. Make `register_marker_function!` refuse a silent overwrite: keep the first
   registration and warn, the way `register_natural_syntax!` does.

**Done.** The verb is registered once, in `FileProject.__init__`; markdown and
RST each add a `document_section` method. A `FileDocument` argument unwraps to
its content in the seam, so neither format repeats that.

## Part B — the markdown card

### B1. The card wrapper projection

File: [EmbedToSyntax.jl](../../package/domain/main/insertion/EmbedToSyntax.jl)

1. Add `wrap::Symbol = :none` to `ReferenceStubToSyntax` and to
   `FileDocumentToSyntax`. `:card` builds the card, `:none` keeps today's
   behaviour.
2. In `print_document`, when `wrap === :card`, build the card in a cell:

   ```julia
   card = ComputedCell(() -> value === nothing ? nothing :
                             WidgetCard(Point2D(0, 0); title = _embed_title(stub),
                                        content = value))
   ```

   and hand the card to `print_child` instead of the value.
3. Compute the card's `selection` cell from the embed's own selection, the way
   `MarkdownRootToVerticalLayout` does. Without it the card declines every key
   and the embedded document cannot be edited.
4. Forward map: `resolved` + rest → the card map of `content` + rest.
   Backward map: strip the card's `content` step and prepend `resolved`.
5. The title reads the file name for a `FileDocument` and the marker's last
   quoted name for a stub. The width stays at the default: a vertical layout
   hands its own `available_width` down
   ([LayoutToGraphics.jl:608-612](../../package/visual/main/layout/LayoutToGraphics.jl#L608-L612)),
   so a card in a page fills the page.

**Done.** `wrap = :card` and `card_width` on both rules; the card is built in a
cell, its `selection` reads the embedded document's own so the keyboard route
opens, and `_embed_into_wrapper` / `_embed_out_of_wrapper` add and drop the
card's step in both maps and in the reader.

### B2. Turn the card on in the graphics table

File: [NaturalProjection.jl](../../package/domain/main/insertion/NaturalProjection.jl)

Change the two entries at lines 222-223 to pass `wrap = :card`. Leave the
to-syntax fabric alone: a syntax tree has no place for a card, and that table is
what the by-marker save path and the plain-text renders go through.

### B3. Tests

File: [MarkdownEmbedTest.jl](../../package/domain/test/serializer/MarkdownEmbedTest.jl)

Add to `test_markdown_embed()`:

1. A resolved JSON embed draws its content and the card title, and exactly one
   card frames it.
2. The save path is unchanged: `document_to_text` before and after the resolve
   gives the same text, and that text holds the marker.
3. ~~A caret maps forward to a point.~~ **Dropped**: forward mapping through the
   graphics chain answers `nothing` for an embed with or without a card (see
   A1). What is asserted instead is that a **click** produces a path rooted in
   the page which really lands a selection in the embedded document.
4. A key event reaches the embedded document through the card.
5. An unforced embed still draws its marker, with no card around it.
6. A click on the card header folds the body away and leaves the header.

**Done.** `test_markdown_embed()` is 40 assertions and passes.

### B4. Check it in the editor

Headless probes miss two failure classes: a start with no reference, and a card
whose controls are not wired. Open a page with a JSON embed and a Julia embed in
the real editor. Click into the embedded document, type, and fold the card.

**Done** through `write_image`, which runs the real SDL renderer over the real
page: both pages draw their cards, and the click / key / fold round trips are
asserted against the rendered pixels in the two test files.

## Part C — RST embeds and the RST card

RST has no embed at all, so most of this part builds the mechanism the card sits
on. Nothing here is a card problem.

### C1. The marker convention

File: [RstFile.jl](../../package/domain/main/rst/RstFile.jl)

1. Name the directive: `.. pred-ref:: <<file("data.json")>>`. Add
   `const PRED_REF_DIRECTIVE = "pred-ref"`. It lives in `RstToSyntaxModule`, not
   next to markdown's `PRED_REF_LANGUAGE` in the file module: both the reader of
   a marker (the loader) and its writer (the projection) need the one name, and
   the loader is the later module of the two.
2. `populate_file!` runs a `_substitute_markers` walk after `rstparse`, the way
   `MarkdownFile.populate_file!` does.
3. A directive named `pred-ref` whose argument parses as a marker becomes a
   `ReferenceStub`. A directive whose argument does not parse stays a directive.

### C2. The substitution walk

File: [RstFile.jl](../../package/domain/main/rst/RstFile.jl)

Write one `_substitute_markers` method for each container. The fields, from
[Rst.jl](../../package/domain/main/rst/Rst.jl):

| Node | Field |
| --- | --- |
| `RstRoot`, `RstSection`, `RstListItem`, `RstField`, `RstBlockQuote`, `RstFootnote`, `RstAdmonition`, `RstDirective`, `RstTableCell` | `elements` |
| `RstSection` | also `title` |
| `RstParagraph`, `RstEmphasis`, `RstStrong` | `content` |
| `RstBulletList`, `RstEnumeratedList`, `RstDefinitionList` | `items` |
| `RstDefinitionItem` | `term` and `elements` |
| `RstFieldList` | `fields` |
| `RstGridTable` | `rows` |
| `RstTableRow` | `cells` |
| `RstLineBlock` | `lines` |
| `RstFigure` | `caption` |

Skip the inline split for now — see the decisions above.

**Done, and narrower than the table.** Only the containers that can hold a
*block* got a method: an inline container would find nothing to rewrite while an
inline marker is not read. That leaves out `RstParagraph`, `RstEmphasis`,
`RstStrong`, `RstLineBlock`, `RstFigure.caption`, `RstSection.title` and
`RstDefinitionItem.term`. Adding them is what the inline step will do.

### C3. The save path

File: [RstToSyntax.jl](../../package/domain/main/rst/RstToSyntax.jl)

1. Add `ReferenceStubToRstSyntaxLeaf` and
   `EmbeddedFileDocumentToRstSyntaxLeaf`, after the markdown pair in
   [MarkdownToSyntax.jl:647-669](../../package/domain/main/markdown/MarkdownToSyntax.jl#L647-L669).
   Each prints one leaf holding `.. pred-ref:: <<…>>`.
2. Put both in `_source_rules`, so the two styles share them.
3. Check the round trip: a file that holds a marker must parse, emit and parse
   again to the same tree.

**Done, with no parser work at all.** `.. pred-ref:: <<file("data.json")>>`
already parses into `RstDirective("pred-ref", "<<…>>")` and emits back
byte-identically, so C1 and C3 together are two rules and a walk.

### C4. Teach the natural renderer about RST

File: [NaturalProjection.jl](../../package/domain/main/insertion/NaturalProjection.jl)

Add `RstDocument => RstToSyntax(style = :rendered)` to
`natural_to_syntax_dispatch`. Without it an RST document inside the natural
renderer falls through to the reflection tail and draws its field names.

**Done.** One line, one import.

### C5. The block-stack rewrap

New file: `package/domain/main/rst/RstToLayout.jl`

1. `RstRootToVerticalLayout`, after
   [MarkdownToLayout.jl](../../package/domain/main/markdown/MarkdownToLayout.jl).
   The maps only relocate the head: `elements[i] + rest ↔ children[i] + rest`.
2. A section owns its blocks, so a root rewrap alone leaves an embed inside a
   section in one syntax tree, where a card cannot go. Add
   `RstSectionToVerticalLayout`: a section becomes a vertical stack of its
   printed title over its blocks.
3. `RstSectionToStyledNode` has no reference mappers today, which is a known
   limit of the rendered view. Write the maps for the new section rule rather
   than inherit that gap.
4. Register both in the graphics table, next to the markdown entry.

This is the largest step of the plan. If it grows, stop after step 1, and record
that an RST embed must sit at the top level until the section rewrap lands.

**Done, both rules.** The section rewrap needed one concession the plan did not
foresee: **the title is flat.** A rewrapped section stacks its title as one prose
line in the level's font, with inline markup flattened to text, because the
title's own runs would need the ambient `:rst_style` the syntax rule carries and
a layout child cannot receive one. A selection therefore maps through a section's
*blocks* — which the syntax rule does not offer at all — but not into its title.
The source view still maps the whole section.

### C6. Tests

New file: `package/domain/test/serializer/RstEmbedTest.jl`, after
`MarkdownEmbedTest.jl`. Assert the same five things B3 asserts, plus:

1. A `pred-ref` directive survives a parse, an emit and a parse.
2. An embed inside a section renders in its card, and the caret reaches it.
3. A `pred-ref` whose argument is not a marker stays the directive it was.
4. The `section` verb names an RST section, and fails loudly on a name no
   section wears.

Add `test_rst_embed()` to
[ProjecturedDomainTest.jl](../../package/domain/test/ProjecturedDomainTest.jl),
next to `test_markdown_embed()`.

**Done.** 29 assertions, and they pass.

## Order and commits

One commit per step: A1, A2, A3, B1+B2, B3, C1+C2, C3, C4, C5, C6. Part A must
land first. Part B and part C do not depend on each other after that.

Do the work in a dedicated worktree, not in the main checkout. The user works in
the same checkout, so commit explicit paths and never a bare pathspec.

**What landed**, on branch `embed-widget-card` in
`workspace/projectured-julia-embed-card`:

| Commit | Step |
| --- | --- |
| A card owns a reference step, so a path travels in and out of its body | A1 |
| A card whose body is a document folds to its header | A2 |
| One section verb, dispatched on the document, and no silent verb overwrite | A3 |
| An embedded document arrives in a titled, foldable card | B1 + B2 |
| The framed embed is asserted: one card, a click, a key and a fold | B3 |
| An RST page embeds another document through a pred-ref directive | C1 + C2 + C3 |
| An RST page is a stack of blocks, so an embed can be a widget | C4 + C5 |
| The RST embed is asserted: a directive, a card, a click and a marker on save | C6 |
| A card header says what the embed is, not how it was addressed | B1 follow-up |

C1, C2 and C3 landed as one commit: the directive needs no parser rule, so the
loader half and the save half are the same small change.

## Traps

- **A new dispatch entry needs a fresh Julia process.** A widget type or table
  entry added under Revise renders as an object dump, because the dispatch table
  is built once.
- **Test in the editor, not only headless.** An IO map reused across a live edit
  fails where a direct read passes.
- **Watch the pass count, not only the failures.** A changed IO map field count
  moves the pass count with no new failure.
- **Run the narrow test.** `test_markdown_embed()`, `test_rst_round_trip()`,
  `test_conversation_editor()`. Reach for `test_domain()` only after the narrow
  test passes.

## What is verified

- `test_markdown_embed()` — 40 assertions.
- `test_rst_embed()` — 29 assertions.
- `test_domain()` — 209308 pass, 5 broken, no failure and no error.
- `test_visual()` — 52460 pass, 1 broken.
- `test_base()` — 387 pass.
- `test_example(rst_example)` + `test_printer(rst_rendered_example)` — 8011 pass
  and 243 fail, which is **exactly** the count at the base commit. The 243 are a
  type-in baseline, measured on both sides rather than assumed.
- `test_all()`, run on this branch **and** at the base commit, in two worktrees:

  | | Pass | Fail | Error | Broken |
  | --- | --- | --- | --- | --- |
  | base `8d7ccd19` | 807345 | 479 | 4 | 2205 |
  | this branch | 808128 | 479 | 4 | 2205 |

  No new failure, no new error, no change in the broken count. The 783 extra
  passes are the 74 new assertions plus the structural walks, which assert per
  node and now walk a card's header and an RST page's layout stack: visual +5,
  domain +428, the printer sweep +350.

  Of the four errors, two are the known Rule C failures in `DocumentMacroTest`
  and two are Unexpected Passes on the `graph` navigation example. That example
  gives 9 pass / 2 error on both commits when run alone.
- Both pages rendered through the real SDL renderer with `write_image`, and read
  back as pictures.

## What is left

- **An inline RST marker.** A marker in a line of prose is not read. The
  markdown slice splits its text runs around one; RST has no counterpart yet.
- **A flat section title.** See C5.
- **Forward mapping a caret to a coordinate** through an embed answers
  `nothing`, as it did before this work. The caret draws, and a click round trips.

## Status

Implemented.
