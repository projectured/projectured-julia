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
4. Give the outer canvas a computed `selection` instead of `Cell(nothing)`, so a
   parent can find the caret inside a card.
5. Re-root in the reader: the press route and the keyboard route must prepend
   `content` to a path-bearing operation the content returned. An
   `InvokeActionOperation` names its own target and passes on unchanged.

No container widget maps forward today, so this is new ground in this file.
Expect the pointer paths (`_route_click_to_children`,
`_route_crossing_to_children`, `_route_move_to_children`,
`_route_downup_to_children`) to need the same re-rooting, and check each one.

**Warning.** This changes behaviour every card shares. The one card with a
document body today is the conversation composer
([ConversationEditor.jl:477](../../package/domain/main/conversation/ConversationEditor.jl#L477)).
Run `test_conversation_editor()` before and after, and read the counts.

Test: `test_conversation_editor()`, `test_widget()`.

### A2. Let a card with a document body fold

File: [WidgetToGraphics.jl](../../package/visual/main/widget/WidgetToGraphics.jl)

1. Read `w.collapsed` inside `_card_build`.
2. When the card is collapsed, do not push the content entry and do not add its
   height. Keep the recursed `cim` alive outside the build cell.
3. Check that the header click already produces `ToggleCollapseOperation`, and
   that the default handler flips the cell.

Test: `test_widget()`, and a manual fold in the editor.

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

Test: `test_marker_vocabulary()`, `test_file_project_s4()`, `test_file_project_s5()`.

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
5. The title reads the file name for a `FileDocument` and the marker text for a
   stub. The width stays at the default: a vertical layout hands its own
   `available_width` down
   ([LayoutToGraphics.jl:608-612](../../package/visual/main/layout/LayoutToGraphics.jl#L608-L612)),
   so a card in a page fills the page.

### B2. Turn the card on in the graphics table

File: [NaturalProjection.jl](../../package/domain/main/insertion/NaturalProjection.jl)

Change the two entries at lines 222-223 to pass `wrap = :card`. Leave the
to-syntax fabric alone: a syntax tree has no place for a card, and that table is
what the by-marker save path and the plain-text renders go through.

### B3. Tests

File: [MarkdownEmbedTest.jl](../../package/domain/test/serializer/MarkdownEmbedTest.jl)

Add to `test_markdown_embed()`:

1. A resolved JSON embed draws its content and the card title.
2. The save path is unchanged: `document_to_text` before and after the resolve
   gives the same text, and that text holds the marker.
3. A caret set inside the embedded document maps forward to a point, and the same
   point maps back to the path it came from.
4. A key event reaches the embedded document through the card.
5. An unforced embed still draws its marker, with no card around it.

Test: `test_markdown_embed()`, then `test_domain()` for the sweep.

### B4. Check it in the editor

Headless probes miss two failure classes: a start with no reference, and a card
whose controls are not wired. Open a page with a JSON embed and a Julia embed in
the real editor. Click into the embedded document, type, and fold the card.

## Part C — RST embeds and the RST card

RST has no embed at all, so most of this part builds the mechanism the card sits
on. Nothing here is a card problem.

### C1. The marker convention

File: [RstFile.jl](../../package/domain/main/rst/RstFile.jl)

1. Name the directive: `.. pred-ref:: <<file("data.json")>>`. Add
   `const PRED_REF_DIRECTIVE = "pred-ref"`, next to markdown's
   `PRED_REF_LANGUAGE`.
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

### C3. The save path

File: [RstToSyntax.jl](../../package/domain/main/rst/RstToSyntax.jl)

1. Add `ReferenceStubToRstSyntaxLeaf` and
   `EmbeddedFileDocumentToRstSyntaxLeaf`, after the markdown pair in
   [MarkdownToSyntax.jl:647-669](../../package/domain/main/markdown/MarkdownToSyntax.jl#L647-L669).
   Each prints one leaf holding `.. pred-ref:: <<…>>`.
2. Put both in `_source_rules`, so the two styles share them.
3. Check the round trip: a file that holds a marker must parse, emit and parse
   again to the same tree.

Test: `test_rst_parser()`, `test_rst_round_trip()`.

### C4. Teach the natural renderer about RST

File: [NaturalProjection.jl](../../package/domain/main/insertion/NaturalProjection.jl)

Add `RstDocument => RstToSyntax(style = :rendered)` to
`natural_to_syntax_dispatch`. Without it an RST document inside the natural
renderer falls through to the reflection tail and draws its field names.

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

### C6. Tests

New file: `package/domain/test/serializer/RstEmbedTest.jl`, after
`MarkdownEmbedTest.jl`. Assert the same five things B3 asserts, plus:

1. A `pred-ref` directive survives a parse, an emit and a parse.
2. An embed inside a section renders in its card, and the caret reaches it.

Add `test_rst_embed()` to
[ProjecturedDomainTest.jl](../../package/domain/test/ProjecturedDomainTest.jl),
next to `test_markdown_embed()`.

## Order and commits

One commit per step: A1, A2, A3, B1+B2, B3, C1+C2, C3, C4, C5, C6. Part A must
land first. Part B and part C do not depend on each other after that.

Do the work in a dedicated worktree, not in the main checkout. The user works in
the same checkout, so commit explicit paths and never a bare pathspec.

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

## Status

Not started.
