# A flat transcript for the conversation and the assistant

> **Status (2026-09-10): NOT STARTED.** This plan comes from a design discussion
> about `run_example(assistant_example)`. Every decision below is the user's,
> recorded in the discussion. No code changed yet.

## The problem

A turn renders as a `WidgetCard`, and every part inside it renders as a second
`WidgetCard`. A message of one prose part therefore draws two nested boxes, two
borders, two paddings of 16 px, and two bold headings. It looks cluttered.

Five separate causes, and only the first is the nesting:

1. **Two boxes say one thing.**
   [`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl)
   builds a card for the turn and a card for each part. For one prose part the
   inner box adds no information.
2. **The badge repeats what the content shows.** `¶ text` sits over the words
   `hi there`. `¶ markdown` sits over prose. The reader sees the kind first.
3. **The chrome outweighs the message.** The role and kind headings use
   `font_ubuntu_bold_22` in an accent color, and the body text is smaller and
   grayer. The metadata wins the page and the message loses it.
4. **There is no reading measure.** A card fills the pane, so two words occupy a
   line 1900 px wide.
5. **The composer does not match the transcript.** `_PART_WIDTH = 720` in
   [`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl)
   pins the draft to 720 px inside a full-width pane, and its box is a *part*
   box, not an *input* box. Nothing says "type here".

## The principle

Chrome must earn its place. Draw a container only where the reader cannot get
the structure from the content itself.

A part can hold anything: text, an image, Julia, JSON, markdown. That is the
argument for a frame around each part. But a frame does not say *what* a part
is — it only separates. The content says what it is: code looks like code, an
image looks like an image, a table looks like a table. Whitespace separates. So
a part frame is needed only for content that is not self-evident, or that
carries an action.

## The decisions

| Question | Decision |
| --- | --- |
| Role identity | Tint the user turn. Leave the assistant turn plain. |
| Kind marks | Mark only the parts whose kind is not obvious. |
| Transcript editing | Read-only. Selection must work, for copy out. |
| Reading measure | None. Text takes the full available width in both panes. |
| Avatar | Keep the small round avatar on the role line. |

Two decisions make the work smaller than the first sketch:

- **The tint keeps the turn as a card.** A tinted band is a surface, so the turn
  stays a `WidgetCard` and only its variant changes. The header click keeps
  emitting `ToggleCollapseOperation`, and `_find_collapse_target` keeps mapping
  it back to the domain node. No new click target is needed.
- **"Only non-obvious marks" removes the gutter column.** The first sketch
  reserved a fixed-width left gutter for a kind glyph. Under this rule the
  gutter is almost always empty: prose needs no mark, a code panel carries its
  language name in its own corner, a thinking part carries its own disclosure
  row, and an evaluation carries its own form and result frame. A reserved
  column would be dead space. A non-obvious part labels itself inline.

## Out of scope

**Free text selection across the transcript.** A check of the selection
machinery found three facts:

- The selection is one reference, not an anchor and focus pair. There is no
  anchor anywhere in [`source/kernel/selection/`](../../source/kernel/selection/).
- No gesture makes a text range.
  [`TextToGraphics.jl`](../../source/text/TextToGraphics.jl) handles no
  `MouseMove` and no `Shift`. Every producer of a `RangeReferenceStep` in the
  text stack writes `(k, k)`, a zero-width caret.
- `text_selection_substring` returns `nothing` when a range crosses a span
  boundary
  ([`TextDocument.jl:707-717`](../../source/text/TextDocument.jl#L707-L717)),
  and a styled prose block has many spans.

A free text range therefore needs an anchor in the selection model, a drag
gesture and Shift+Arrow at the text layer, and a multi-span substring. That is
kernel work. **This plan does node copy only**, which covers "copy this answer"
and "copy this code block".

## The target

**Transcript**

- A turn is a quiet full-width card. The role line holds a small avatar and the
  role word, at about 14 px, muted, colored by role.
- Gap of 28 px between turns. Gap of 8 px between parts.
- A part is bare content. Chrome only where the content earns it.
- No outline at rest. A 1 px outline on hover, and on the selected part, drawn
  inside the padding so nothing reflows.

| Content | Chrome |
| --- | --- |
| prose, markdown | none |
| julia, json, xml | one tinted panel, no title row, language name small and muted in the corner |
| evaluation (`EvaluatorForm`) | the form panel, a hairline, the result below |
| thinking | one disclosure line that expands |
| image, attachment | the image, and a caption line if it has one |

**Composer**

- One full-width surface with a border and a focus ring. The border is
  meaningful here: it says a person can type.
- The same part rules inside it. The active typein is a bare line with a caret
  and a placeholder.
- A `+` affordance at the bottom left, and one hint line:
  `Enter to send · Shift+Enter for a new line`.

## Stage 1 — a variant on `WidgetCard` ✅ DONE

Add `variant::Symbol` to `WidgetCard` in
[`WidgetDocument.jl:1391`](../../source/widget/WidgetDocument.jl#L1391), with
three values:

| variant | fill | border | use |
| --- | --- | --- | --- |
| `:card` | `theme.card` | `theme.border` | the default; every card today |
| `:tinted` | `theme.accent` | none | the user turn |
| `:plain` | none | none | the assistant turn |

**Decision: the tint is `theme.accent`, and not a new theme field.** The plan
first said to add a tint color to `WidgetTheme`. Every preset already carries
`accent`, which is exactly this role — a quiet tinted surface — and each preset
already picked a value that reads correctly on its own background
(`color_indigo_100` light, `color_indigo_950` dark, `color_zinc_100` and
`color_zinc_800` in the neutral pair). A new field would have needed the same
four values under a second name. The projection still takes it as its own
`tint_color`, so the renderer names no theme role.

There is no collision with the hover highlight that also uses `theme.accent`,
because Stage 6 draws hover as an outline and not as a fill.

`WidgetCardToGraphicsCanvas` reads `w.variant` in `_card_build` and picks the
fill and the border before it calls `_push_panel!`. For `:plain` it pushes no
panel at all. `_push_panel!` already draws no outline when `border === nothing`
([`WidgetToGraphics.jl:335-343`](../../source/widget/WidgetToGraphics.jl#L335-L343)).

The projection gains one theme field for the tint color. The theme entry is at
[`WidgetToGraphics.jl:6654`](../../source/widget/WidgetToGraphics.jl#L6654).
`color_indigo_50` and `color_slate_50` exist already in
[`Color.jl:189-206`](../../source/style/Color.jl#L189-L206).

This is the `variant` pattern that `WidgetBadge` and `WidgetAlert` already use
([`WidgetToGraphics.jl:3878`](../../source/widget/WidgetToGraphics.jl#L3878)),
so it needs no new widget type and no second projection entry.

**One call site breaks, and it is not optional.** A new field changes the
positional constructor that `@document` generates. Eight of the nine call sites
use the keyword constructor and need no change.
[`EmbedToSyntax.jl:249`](../../source/fileformat/EmbedToSyntax.jl#L249) does
not: it passes ten cells positionally, and the last is the `selection` cell.
Insert `Cell(:card)` after `Cell(false)` there, in the same commit that adds the
field. A new default is not a compatible change for a positional constructor.

**Test:** `test_object_to_widget()` and `test_widget_button_behavior()` pass.
A direct render of the three variants gives one rect with a fill and a border for
`:card`, one rect with a fill and no border for `:tinted`, and no rect at all for
`:plain`.

## Stage 2 — the turn becomes a quiet card ⬜

In [`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl),
change `print_document(::ConversationTurnToWidgetComposite, …)`:

1. Pass `variant = t.role === :user ? :tinted : :plain`.
2. Make the role line small and muted. Replace `_TITLE_FONT`
   (`font_ubuntu_bold_22`) with a 14 px font, and keep the role color.
3. Keep the avatar. Reduce `_AVATAR_SIZE` from 22 to 16.
4. Raise the gap between turns to 28 in
   `print_document(::ConversationConversationToWidgetComposite, …)`. Keep the
   gap inside a turn at `_GAP`.

**Test:** `test_printer(assistant_example)`, then look at the window with
`run_example(assistant_example)`.

## Stage 3 — the part becomes a flow ⬜

Change `print_document(::ConversationPartToWidget, …)` to return the body, and
not a card. Dispatch the chrome on the content:

- prose, markdown, and any other self-evident content — return the recursed
  content directly.
- code — wrap it in a `WidgetCard` of variant `:tinted` with no title, and put
  the language name in a small muted label in the corner. `FORMAT_LABELS` stays
  and feeds that label.
- an `EvaluatorForm` — keep `_eval_body`, and add a hairline between the form
  and the result.
- a `ConversationThinking` — one disclosure line that expands.
  `WidgetAccordionItem` exists already
  ([`WidgetDocument.jl:1764`](../../source/widget/WidgetDocument.jl#L1764)).

`FORMAT_GLYPHS` loses its only reader if no part draws a glyph. Delete it only
after Stage 4, because the composer reads it too.

**A part with no card cannot fold.** The part collapse rides on the card header
click today. Only a code part, a thinking part, and an evaluation keep a chrome,
and each of those keeps its own affordance. A prose part can no longer
fold, which is the right trade.

**Test:** `test_printer(assistant_example)` and `test_conversation()`.

## Stage 4 — the composer matches the transcript ⬜

In [`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl):

1. Delete `_PART_WIDTH`. The draft takes the width it is offered.
2. Replace the per-part cards with the same rules as Stage 3. The active typein
   is a bare line with a caret and a placeholder.
3. Put one surface around the whole draft, with a border and a focus ring.
4. Add the `+` affordance and the hint line.

The caret machinery must keep working. `print_document` installs a reactive
selection on the body
(`set_cell_function!(getfield(body, :selection), …)`), and the forward map walks
`children[i].content.elements[s].content{k}`. If a part is no longer wrapped in
a card, that path loses one step. Update the forward and backward maps together
and prove it with a click test.

**Test:** `test_repl(assistant_example)` and `test_conversation_editor()`.

## Stage 5 — selection and node copy ⬜

The transcript is read-only, but a person must be able to select a part and copy
it out.

1. **Name the part.** Today every transcript projection answers
   `map_reference_backward` with `EmptyReference()` and turns a `MousePress`
   into `ReplaceSelectionOperation(EmptyReference())`, so a click cannot name a
   part. Change the backward map to name the part that was clicked, and change
   the forward map to carry that selection down so the part draws its outline.
2. **Deny the mutations.** The assistant reader declines the operations that
   would change a turn. Decline by exact operation type, and pass
   `ReplaceSelectionOperation` and the clipboard operations through.
3. **Copy through the clipboard that exists.** Wrap the transcript in
   `ClipboardSliceToAnyProjection`
   ([`ClipboardToAny.jl:94-101`](../../source/clipboard/ClipboardToAny.jl#L94-L101))
   with a `to_text` converter and `text = false`. It already delegates
   non-clipboard gestures into the child reader, re-roots what comes back, and
   mirrors a copy out to the OS clipboard through `OsClipboardModule`. Nothing
   new is built here; the two compose.

**Test:** a new test that selects a part, sends `Ctrl+C`, and asserts the slice
holds the part's text.

## Stage 6 — hover ⬜

Draw a 1 px outline on the part under the pointer, and on the selected part,
inside the padding so nothing reflows. Add a `copy` affordance on the turn and
on a code panel, which does what `Ctrl+C` does.
[`WidgetHoverTracking.jl`](../../source/widget/WidgetHoverTracking.jl) already
tracks the pointer.

**Test:** `test_repl(assistant_example)`.

## How to test the whole thing

Run the narrowest test for the stage, as listed above. After every stage is
done, run `test_conversation()` and `test_example(assistant_example)`, and look
at the window with `run_example(assistant_example)`.
