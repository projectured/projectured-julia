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
| `:tinted` | `theme.accent`, pulled toward `theme.card` | none | the user turn |
| `:muted` | `theme.muted` | none | a part panel inside a turn |
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

## Stage 2 — the turn becomes a quiet card ✅ DONE

In [`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl),
change `print_document(::ConversationTurnToWidgetComposite, …)`:

1. Pass `variant = t.role === :user ? :tinted : :plain`.
2. Make the role line small and muted. Replace `_TITLE_FONT`
   (`font_ubuntu_bold_22`) with a 14 px font, and keep the role color.
3. Keep the avatar. Reduce `_AVATAR_SIZE` from 22 to 16.
4. Raise the gap between turns to 28 in
   `print_document(::ConversationConversationToWidgetComposite, …)`. Keep the
   gap inside a turn at `_GAP`.

**Test:** `test_conversation()` passes, 44 of 44. A render of
`make_conversation_document_example()` (roles `[:user, :assistant, :user]`) draws
two tinted panels with no border and no panel at all for the assistant turn.
The part cards still draw their own fill and border; Stage 3 removes them.

## Stage 3 — the part becomes a flow ✅ DONE

Change `print_document(::ConversationPartToWidget, …)` to return the body, and
not a card. Dispatch the chrome on the content:

- prose, markdown, and any other self-evident content — return the recursed
  content directly.
- code — wrap it in a `WidgetCard` of variant `:muted`, and put the language
  name in a small muted label in the card's title slot. `FORMAT_LABELS` stays
  and feeds that label. A new `CODE_FORMATS` set (`:jl`, `:json`, `:xml`) says
  which formats read as code; every other format is prose to this file.

**Decision: the tag goes in the title slot, not the corner.** The plan said a
corner. A card has no top-right slot, and a right-aligned element inside the
title would have to know the card's width, which the title does not. The tag is
one small muted label with no avatar, which is already far quieter than the bold
22 px heading with an avatar that it replaces.
- an `EvaluatorForm` — a `:muted` card with an `eval` tag, keeping `_eval_body`.

**Decision: no hairline between the form and the result.** The plan asked for
one. A `WidgetSeparator` takes the width it is OFFERED, and no offer reaches it
inside a content-tall card: neither `child_width = Fill` on the layout nor a
`LayoutConstraint` around the rule changed it. It fell back to its own 200 px
default and drew a stub that reads as a mistake. The panel and the gap separate
the two well enough, so the rule is gone.

**Fix found in the render: the thinking tag is a bare word.** It first carried
the glyph `∴`, which drew as a missing-glyph box: the chrome font holds no such
character and the renderer has no fallback. Every tag is now a bare word.
- a `ConversationThinking` — a `:muted` card whose title is the `∴ thinking`
  header, and whose body keeps the existing `_maybe_clip` fold. An accordion was
  the first idea, and it was dropped: `_maybe_clip` is already driven by the
  domain `collapsed` flag that the toggle reader writes, and a header over one
  clipped row IS the disclosure line. Changing the fold mechanism in the same
  commit as the chrome would have mixed two changes.

`FORMAT_GLYPHS` stays: the composer imports it to mark the part it is editing.
`_kind_glyph` in this file loses its only reader and is deleted.

**A part with no card cannot fold.** The part collapse rides on the card header
click today. Only a code part, a thinking part, and an evaluation keep a chrome,
and each of those keeps its own affordance. A prose part can no longer
fold, which is the right trade.

`_mvp_test_collapse_click` in
[`AssistantMvpTest.jl`](../../test/workbench/editor/AssistantMvpTest.jl) clicked
the header of a prose part, so it had to change with the design. It now clicks
the Julia part (`turns[2].parts[3]`), and asserts that no click anywhere yields
a toggle for the prose part (`turns[2].parts[2]`).

### A stale broken marker, promoted ✅

`@test_broken _canvas_maxw(out_default) == _canvas_maxw(out_expanded)` in the
same file passes, and it is promoted to `@test`.

**This stage did not fix it.** A run of the suite at the base commit reports the
same `Unexpected Pass` at `AssistantMvpTest.jl:335`, so the assertion was
already passing before any of this work and the marker was simply stale. The
promotion is right; the credit is not.

### Decision: two quiet variants, not one ✅

The first render of this stage showed a defect the plan did not predict. A part
panel and a turn band are both quiet surfaces, and a part sits INSIDE a turn —
so a code block in a user message drew nothing at all, because both used
`theme.accent`.

Two changes fixed it, both in Stage 1's widget:

1. `WidgetCard` gained a fourth variant, `:muted`, filled from `theme.muted`.
   The part panels use it; the turn band keeps `:tinted`.
2. The tint is no longer the raw accent. It is
   `color_interpolate(theme.accent, theme.card, 0.55)` — the accent pulled most
   of the way to the card surface. The raw accent (indigo-100, `224,231,255`)
   and `theme.muted` (slate-200, `226,232,240`) differ by 15 units of blue and
   nothing else, which is not a difference a person sees.

The rendered result: a band at `237,241,253` holding a panel at `226,232,240`.
The panel is a clear step darker in all three channels, so it reads inside a
band and on the plain background alike.

**Test:** `test_conversation()` passes, 44 of 44. `test_object_to_widget()` and
`test_widget_button_behavior()` pass. A render of the conversation example draws
a band for each user turn, no band for the assistant turn, a muted panel for the
thinking part and for the Julia part, and no panel at all for the two prose
parts. The transcript draws no border anywhere.

## Stage 4 — the composer matches the transcript 🟡 PARTLY DONE

In [`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl):

1. ✅ Delete `_PART_WIDTH`. The draft takes the width it is offered.
2. ✅ The per-part cards follow the Stage 3 rules. The active typein is a bare
   line with a caret and a placeholder.
3. ⬜ Put one surface around the whole draft, with a border and a focus ring.
4. ⬜ Add the `+` affordance and the hint line.

**Decision: a part stays a card, and the card stops drawing.** The plan warned
that the caret walks `children[i].content.elements[s].content{k}`, and that a
part which is not a card drops the `content` step. It does. So the composer
keeps one `WidgetCard` per part and gives it `variant = :plain`, which draws no
panel at all — the same picture, with the path intact and both reference maps
untouched. Code and an evaluation get `:muted` with a tag, exactly as in the
transcript. `content` is the card's own named slot
(`_card_slot_value`), so dropping the title changes no path either.

Items 3 and 4 are **not done**. Both belong to the pane that HOSTS the draft, not
to the draft: `AssistantToWidgetSplitPane` wraps `a.draft` in a
`WidgetScrollPane`, and `AssistantToWidgetCard` wires its selection through
hand-counted container depths (`suffix(2)`, `suffix(3)`). A surface added at
either place shifts those counts, so it is its own change with its own test.

**Also done here:** `_kind_glyph`, `_format_glyph`, `_header` and the whole
`FORMAT_GLYPHS` table lost their last reader and are deleted. The composer's
avatar goes with them; only the role line keeps one.

**Test:** `test_conversation()` passes, 44 of 44. `test_assistant_mvp()` passes,
78 of 78. A render of the composer example draws one line of placeholder text
with a caret, and no box.

## Stage 5 — selection and node copy ✅ DONE

The transcript is read-only, but a person must be able to select a part and copy
it out.

1. ✅ **Name the part.** Both maps are written, at all three levels, each level
   stripping the steps it printed and delegating the rest to the child that
   printed them (School A). A click now yields `turns[i].parts[j]`.
2. ✅ **Deny the mutations.** `ReplaceReferencedValueOperation`,
   `ReplaceStringRangeOperation` and `ReplaceNumberRangeOperation` are declined
   by exact type. Every other operation travels.

### What the probe found ✅

The widget layer was ALREADY handing up a full structured path —
`children[i].content.children[j].content.…` — and the transcript's
`read_intent(::P, iomap, op::Operation) = op` passed it through untranslated. So a
click in a text part put a WIDGET path on a conversation document, naming fields
that do not exist there. That was a live defect, not just a missing feature.

The shape made the maps straightforward: a turn prints as a card in a layout
(`children[i]`), and its parts print inside that card (`content.children[j]`).

**No regression in key routing.** The risk was that a selection inside the
transcript would stop the composer receiving keys. It does not: the panel's
`KeyPress`/`KeyDown` handlers route to `a.draft` unconditionally
([`AssistantTurn.jl:936`](../../source/assistant/AssistantTurn.jl#L936)), and a
probe confirms a `KeyPress` still becomes a `ComposerInputOperation` with the
selection on `conversation.turns[1].parts[1]`.

**Test:** a new [`ConversationTranscriptTest.jl`](../../test/conversation/projection/ConversationTranscriptTest.jl)
with three testsets — every part of the example is reachable by a click and
named exactly, a selection round-trips through both maps, and each of the three
edit operations is declined. `test_conversation()` passes, 63 of 63.
`test_assistant_mvp()` passes, 78 of 78.
3. ✅ **Copy through the clipboard that exists.** It needed **no production
   change at all.** `ClipboardSlice` copies whatever the slice's selection names,
   and after 5a the selection names a part. Wrap a conversation in a
   `ClipboardSlice`, project it with `ClipboardSliceToAnyProjection` over the
   transcript projection, and `Ctrl+C` stores a deep copy of the selected
   `ConversationPart` — the part alone, not the turn and not the conversation.

   A test asserts that composition, because the composition IS the copy story
   and no code in this package takes part in it.

   The OS-clipboard mirror needs a `to_text` converter, which is a choice for
   whoever installs the slice (a conversation has no one text form). Left to the
   caller.



## Stage 6 — show the selection, and hover ⬜ NOT DONE

A click names a part and `Ctrl+C` copies it, but **nothing on screen changes when
a part is selected**. A person who selects a message sees no answer. This stage
closes that, and it is not the polish the plan first called it. Here is what a
probe found and what the work actually costs.

**A sub-document does not see the root selection.** Set the conversation's
selection to `turns[2].parts[2]`, and `getfield(part, :selection)[]` is still
`nothing`. Nothing propagates it. A render with a part selected draws the same
107 elements and the same 12 rectangles as a render with no selection at all.

So the selection has to be carried to the printed widget by the printer, which
is the `set_cell_function!` chain the composer uses on its body
([`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl)) and
`AssistantToWidgetCard` uses on its four containers with hand-counted depths
(`suffix(2)`, `suffix(3)`).

**And a prose part has no widget to mark.** After Stage 3 a prose part prints its
content bare, so there is no surface to ring, tint or outline. Giving it one
again brings back the 32 px of card padding per part that Stage 3 removed.

### What it needs

1. `WidgetCard` gains a `padding` field, where a negative value means "the
   theme's". A `:plain` card with `padding = 0` draws nothing and occupies
   nothing, so a part can be a card again without costing a paragraph of space.
   This breaks the positional call site at
   [`EmbedToSyntax.jl:249`](../../source/fileformat/EmbedToSyntax.jl#L249) a
   second time.
2. A fifth variant, `:selected`, filled from the raw `theme.accent`. Nothing
   uses that token now — the turn band uses the interpolated tint — so it
   collides with nothing.
3. Every part becomes a card again: prose gets `:plain` with `padding = 0`.
4. The `variant` becomes a reactive cell reading the card's own `selection`.
   `_card_build` already reads `w.variant` inside its `build` cell, so a
   reactive variant re-renders on its own.
5. The transcript printer installs the selection down the chain, one
   `set_cell_function!` per container, each with its own prefix already spent.

Steps 1 to 4 are small. Step 5 is the delicate one: it is the same seam Stage 5
changed, and getting a suffix count wrong silently stops a container carrying
the caret.

**The `padding` field of step 1 exists.** The transcript-folds plan added it,
as a number for every side or an `Inset`, so step 1 is done and the rest of
this stage starts at step 2.

**Hover** is a second piece on top, and it needs a `hovered` cell on the card
that does not exist yet. [`WidgetHoverTracking.jl`](../../source/widget/WidgetHoverTracking.jl)
tracks the pointer for widgets that have one.

**Test when it is done:** a render with a part selected differs from one without,
at the part's own rectangle and nowhere else.

## Stage 7 — what the window showed ✅ DONE

A run of the campaign window (`omnet-julia`) found four things the test renders
did not. Three are fixed here; the fourth is not reproducible.

**The role line was too small.** 22 was too big and 14 was too small. It is 18
now — under the 20 px body, so it still reads as metadata, but read. A part's tag
stays at 14, because naming a kind is a smaller thing to say than naming who
spoke, so `_ROLE_FONT` and `_KIND_STYLE` are two constants now and not one.

**`U` and `A` were letters, not icons.** They came from a `WidgetAvatar`, which
draws a disc with initials — and at 16 px the disc was a pale ring behind a 20 px
letter that overflowed it, so what showed was the letter alone. The avatar is
gone: the mark is drawn as text, in the role's own color, beside the role.

The glyph was chosen by rendering candidates at the size they are drawn at, twice
over, because DejaVu fails in two different ways:

| Glyph | What the font does |
| --- | --- |
| `∴` | not in the font — draws as an empty box |
| `👤` `✦` `⬥` | thin OUTLINE — disappears beside a bold word |
| `✨` | ink wider than its advance — eats the gap and sits against the word |
| `☻` `●` `◆` `★` `✱` | solid at 20 px bold |

So: `☻` for the user, `✱` for the model, bold 20, gap 10.

**The band tint fought every other color on the page.** Measured against the pane
background of `241,245,249`: the band was `237,241,253` — 4 units toward BLUE —
and a part panel was `226,232,240`, 15 units toward GREY. Two quiet surfaces that
nest have to be ordered, and a ladder only reads as one if every rung moves the
same way. The band moved sideways, so it read as a cast on the background rather
than as a surface, and beside a panel the two pulled apart.

The tint is neutral now, `color_interpolate(theme.muted, theme.background, 0.5)`.
The ladder is `241,245,249` → band → panel `226,232,240`, all one hue. The role
is said by the colored mark and word, which is where color means something.

**"The initial message looks different in background color" — not reproduced.**
A render of a greeting turn, a user turn and a reply measures the same
`241,245,249` behind the first assistant turn and behind the last. Both are
`:plain`, and the campaign greeting is a plain `ConversationPart(String)` like any
other prose. Open question for the user.

## Where this stands

| Stage | State |
| --- | --- |
| 1 — a variant on `WidgetCard` | ✅ done |
| 2 — the turn becomes a quiet card | ✅ done |
| 3 — the part becomes a flow | ✅ done |
| 4 — the composer matches the transcript | 🟡 the draft and its parts are done; the input frame and the hint line are not |
| 5 — selection and node copy | ✅ done |
| 6 — show the selection, and hover | ⬜ not done |

**What works.** The transcript reads as a document: a faint band for a user turn,
nothing for the model's, a muted panel only around code, a thinking block and an
evaluation, and no border anywhere. A click names the part it landed in, an edit
that reaches the transcript is declined, and `Ctrl+C` on a selected part copies
that part.

**What does not.** A selected part looks exactly like an unselected one
(Stage 6). The composer has no frame saying a person can type in it, and no hint
line (Stage 4, items 3 and 4).

## The wide suites, against the base commit

Both wide suites still report failures. Each was re-run at the base commit
(`ecd6623b`, whose only change is this plan file) in its own worktree, and the
counts say the failures are not this work's.

Run the baseline at the BASE COMMIT, not at `main`. `main` moved on while this
branch was built, so a run there has testsets this branch does not, and the
comparison stops being one.

| Suite | Base commit | This branch |
| --- | --- | --- |
| `test_substrate()` | 55959 pass, 4 fail, 3 error, 1 broken | 56059 pass, 4 fail, 3 error, 1 broken |
| `test_workbench()` | 104 pass, 1 fail, 3 error | 106 pass, 1 fail, 2 error |

- **Substrate:** the same 4 failures and 3 errors, at the same seven sites, one
  occurrence each and byte-identical between the two runs:

  | Site | Count |
  | --- | --- |
  | `test/substrate/projection/SplitPaneDragTest.jl` lines 76, 78, 111, 128, 129 | 5 |
  | `test/kernel/layering/CheckLayering.jl:707` (the `ProjecturedDragging` guard) | 1 |
  | `test/substrate/serialization/MarkerLanguageTest.jl:31` | 1 |

  The 100 extra passes are the cell-count assertions that track a document's
  field count, and `WidgetCard` gained two fields.
- **Workbench:** the same 1 failure, `scrolling the tab strip reveals overflow
  tabs` in `WorkbenchTabClickTest.jl:151`. One fewer error, because the stale
  broken marker above is now a plain passing test. One more test, the prose-part
  assertion this work added.

## How to test the whole thing

Run the narrowest test for the stage, as listed above. After every stage is
done, run `test_conversation()` and `test_example(assistant_example)`, and look
at the window with `run_example(assistant_example)`.
