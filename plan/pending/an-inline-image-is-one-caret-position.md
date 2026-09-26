# An inline image is one caret position

> **Status:** in progress in the worktree `projectured-julia-inline-image`, branch
> `inline-image`, from `main` `90748061`. Written 2026-09-26. The owner asked for this
> plan after the text layout examples showed the fault
> ([text-layout-examples.md](../done/text-layout-examples.md), Step 2), and
> answered the seven questions of §5 on 2026-09-26.

An inline image (`TextGraphics`, a span of a `TextBlock`) has no width in the
flat caret stream. So the caret after an image is the caret before it: a
character typed after an image goes before it, Backspace after an image deletes
the character before the image, and no key can put the caret after an image at
the end of a line. This plan gives an image one position in the caret stream, as
a word processor gives a picture set in line with text one character, and makes
every reader of that stream agree.

## 1. The request

"Write the plan for the inline image after." The type-in sweep of
`text_with_image_example` fails 4 assertions on `main`, and the layout examples
`text_baseline` and `text_line_height` fail 2 each, all at the start of the run
after an image. The type-in walk keeps these failures visible on purpose.

## 2. What exists

### 2.1 Two flat spaces count an image differently

- **The caret space** counts an image as 0. `get_flat_length(::TextDocument) = 0`
  ([TextDocument.jl:795](../../source/text/TextDocument.jl#L795)) covers
  `TextGraphics`, and `_push_flat_chars!(chars, ::TextDocument)` pushes nothing
  ("0-width, matches get_flat_length", :410). `get_flat_offsets`,
  `_text_flat_total`, `get_flat_base` and every decorator run
  (`_make_flat_runs` :923-932, "an image, is a run of length zero") follow it.
- **The box space** of `TextToGraphics` counts an image as 1:
  `_box_flat_length(::TextGraphics) = 1`
  ([TextToGraphics.jl:774-776](../../source/text/TextToGraphics.jl#L774-L776)).
  So do `SyntaxToText` (`_span_len(::TextGraphics) = 1`,
  [SyntaxToText.jl:1377-1383](../../source/syntax/SyntaxToText.jl#L1377-L1383)),
  the segment of an image in the coordinate table (range `[0, 1)`), the wrap
  segment of `WordWrapping` (length 1, :191), the `TextGraphics` docstring
  (TextDocument.jl:168-169, "one atomic cursor position") and `text.md:76`
  ("one character wide").
- [text-range-reference-flat-cursor.md](../done/text-range-reference-flat-cursor.md)
  left this skew to "reconcile later" (:438-439), and
  [inline-text-images.md](../done/inline-text-images.md) §2.4-2.5 meant an image
  to have a caret before and a caret after it.

### 2.2 What a person meets today

- **A typed character** at the caret after an image: `_lower_text_range` resolves
  the offset to the end of the text run before the image
  (`_flat_to_span_nearest`, TextDocument.jl:1116-1131), so the character goes
  before the image.
- **Backspace** there deletes the last character before the image; **Delete**
  before an image deletes the first character after it. No key deletes an image.
  A range that covers an image crosses two runs and does nothing (:1154).
- **Left and Right** step over an image with no stop (`_text_char_motion`,
  :606-617). **Ctrl+arrow** reads `"ab"[image]"cd"` as one word `abcd`,
  because the image pushes no character.
- **Ctrl+End** in a block that ends with an image stops before the image. **End**
  on a line that ends with an image, and a click on the right half of an image,
  give `base + 1`: one character into the next run
  ([TextToGraphicsTest.jl:198-225](../../test/substrate/projection/TextToGraphicsTest.jl#L198-L225)
  asserts this).
- **The caret** is never drawn after an image: `_flat_to_span` (:1035-1046)
  answers only text runs, so the branch of `_layout_group` that draws a caret
  before or after an image (TextToGraphics.jl:555-558) is never reached.
- **A selection** does not paint an image: `_hl_piece_blank` treats the empty
  text of an image segment as blank (TextToGraphics.jl:1237-1245).

### 2.3 Faults found beside it

- **A caret-space range is painted with box-space offsets.** `_highlight_char_range`
  (TextToGraphics.jl:1209-1228) passes the offsets of a `TextRangeReferenceStep`
  (caret space) to `_compute_span_rows`, which reads `span_flat_offsets` (box
  space, where a `TextNewline` counts 0 and an image 1). So a selection across a
  `TextNewline` or an image paints one character more per newline, or one less
  per image. The line model test checks only the rows, not their ends.
- **`SyntaxToText` asserts a text run** in `_text_elem_path_to_flat` and
  `_flat_to_span_char` (SyntaxToText.jl:1570-1595), so a walk over the image leaf
  of a Markdown, Book or reStructuredText picture can throw a `TypeError`.
- **`TextToString` has no rule for an image**
  ([TextToString.jl:122-129](../../source/text/TextToString.jl#L122-L129)), so a
  text with an image errors there.
- **`splice_value!` over a `TextBlock`** counts only the characters of text runs
  (TextDocument.jl:317-330), a third metric beside the two spaces.

### 2.4 The operations that exist

- A text edit is `ReplaceTextRangeOperation` over the flat caret space, lowered to
  one `ReplaceStringRangeOperation` on one run (`_lower_text_range`,
  :1133-1161).
- `insert_elements(path, index, items; selection)` and
  `delete_elements(path, index, count)`
  ([Operations.jl:285-314](../../source/kernel/operation/Operations.jl#L285-L314))
  splice a list with a `ReplaceReferencedValueOperation`, and undo inverts them
  ([Inversion.jl:119-130](../../source/kernel/operation/Inversion.jl#L119-L130)).
  So deleting an image, or starting a text run beside one, needs no new
  mechanism.

## 3. The model

### 3.1 The caret stream

- **An image is one position.** `get_flat_length(::TextGraphics) = 1`, and the
  flat characters of a text hold U+FFFC (OBJECT REPLACEMENT CHARACTER) for it
  (question 1). The caret before an image is `base`, the caret after it
  `base + 1`, and the two are different places.
- **Every reader of the stream agrees:** `get_flat_offsets`, `_text_flat_total`,
  `get_flat_base`, `_flat_chars`, the decorator runs, `SelectionInverting`,
  `splice_value!` over a `TextBlock`, and `SyntaxToText`, which counts 1 already.
  The box space of `TextToGraphics` counts an image as 1 already; it differs from
  the caret space only by the soft newlines of word wrapping.

### 3.2 From an offset to a place

- An offset resolves to a text run when one holds it; at the seam of two text
  runs, to the end of the earlier run, as today.
- An offset that no text run holds is beside an image: the caret before the image
  (`char 0`) or after it (`char 1`). This happens at the start or the end of a
  line, and between two images. The caret there is drawn at the left or the
  right edge of the image.
- Because an image is one position, "before the image" and "after the image" are
  different offsets, so a seam of a text run and an image is never ambiguous.

### 3.3 Motion

- **Left and Right** step over an image as over one character.
- **Ctrl+arrow:** an image is a word of its own (question 2).
- **Ctrl+Home and Ctrl+End** go to 0 and to the total, which counts every image.
- **Home, End, Up, Down and a click** land before or after an image: the left half
  is before it, the right half after it.

### 3.4 Edits

- **A typed character** before an image goes to the end of the text run before
  it; after an image, to the start of the text run after it. Where no text run
  touches that side of the image, the character starts a new run there, with
  `insert_elements` (question 3). An image has no font and no colour, so the new
  run takes the style of the nearest text run of its line, the run before the
  image first; on a line with no text run, the style of the block, the font that
  `_block_font` finds and the colour of the run it finds it in. This rule is my
  proposal from the owner's answer, not the owner's decision.
- **Backspace after an image and Delete before it delete the image** (question 4),
  with `delete_elements`, and leave the caret where the image was.
- **A range** that covers text and an image still does nothing: an edit across
  runs is a separate plan. A range that covers only an image deletes it.
- These edits are defined for a `TextBlock` that is the document itself, as in
  `text_with_image_example`. Through `SyntaxToText`, the picture leaf of a
  Markdown, Book or reStructuredText document keeps its own reader: it does not
  throw, it counts its image as 1, and it declines an edit of the image (question 5).

### 3.5 The style beside an image

An image has no font and no colour (the owner, question 3). The line model reads
a font where it meets an image today: the caret beside an image takes the font of
the image span (TextToGraphics.jl:557), and `_element_font(::TextGraphics)`
(:816) lets an image give the prevailing font of a block and the height of a line
with no glyph. With the owner's statement, each of these takes the style of the
nearest text run instead, by the rule of §3.4. `TextGraphics` loses its `font`
and `font_color` fields, and keeps `fill_color`, `line_color` and `padding`, which
a box around a picture can use (question 7).

### 3.6 The string of a text

`TextToString` gives an image U+FFFC, so the string of a text is its flat
characters, and an offset in one is an offset in the other.

### 3.7 The paint of a selection

A `TextRangeReferenceStep` is painted with caret-space offsets, and a
`TextSpanReferenceStep` with box-space offsets, as its producers mean them. An
image inside a selection is painted (question 6).

## 4. What changes for a person

- The caret stops before and after an image, and a typed character appears where
  the caret is.
- Backspace after an image, or Delete before it, removes the image; undo brings it
  back.
- A selection shows exactly the characters and images it holds.
- A text with an image can be turned into a string.

## 5. Questions for the owner

The owner answered questions 1 to 6 on 2026-09-26.

1. **The character of an image in the flat characters and in the string.**
   *Decided:* U+FFFC, the Unicode character for an object in text.
2. **Word motion.** *Decided:* an image is a word of its own; Ctrl+Right stops
   before and after it.
3. **Typing where no text run touches the image.** *Decided:* a new run starts
   there, and "an image does not have font and color". The style of the new run
   comes from the nearest text run (§3.4, my proposal).
4. **Backspace after, Delete before.** *Decided:* they delete the image; undo
   restores it.
5. **Scope through `SyntaxToText`.** *Decided:* the picture leaves of Markdown,
   Book and reStructuredText stop throwing and count the image as 1; an edit of
   the image through its syntax is deferred to a plan of each domain.
6. **The paint of a selection.** *Decided:* fixed in this plan (Step 7).
7. **The style fields of `TextGraphics`.** *Decided:* `font` and `font_color`
   go; `fill_color`, `line_color` and `padding` stay; the readers of §3.5 take
   the style of the nearest text run. The change is part of this plan (Step 5b).

## 6. Steps

Do the work in a git worktree, and commit each step.

- [x] **Step 0. The baseline.** On the base commit, in a fresh process in the
  network namespace: the suites of the text line plan
  (`/var/tmp/text-baseline-base/baseline.jl`), `test_example` of
  `text_with_image`, `text_baseline` and `text_line_height`, and the navigation
  sweep of `text_with_image`
  ([ExampleSweeps.jl:404-408](../../test/projectured/editor/ExampleSweeps.jl#L404-L408)).
  - *Done for the examples* (`/var/tmp/inline-image/base/check.log`). Pass, fail
    and broken counts:

    | Example | `test_example` | navigation, with the markers of the sweep | navigation, no markers |
    | --- | --- | --- | --- |
    | `text_with_image` | 1479 / 4 / 2 | 9 / 0 / 2 | 9 / 2 / 0 |
    | `text_baseline` | 2985 / 2 / 9 | 8 / 3 / 0 | 8 / 3 / 0 |
    | `text_line_height` | 3485 / 2 / 3 | 8 / 3 / 0 | 8 / 3 / 0 |

    The navigation walks of `text_baseline` and `text_line_height` fail on `main`
    too: the right walk and the left walk do not agree (`same_length`, and each
    walk ends where the other starts). No suite runs them: the list `examples` of
    the sweep does not name the layout examples.
  - *Done for the suites* (`/var/tmp/inline-image/base/test-counts.tsv`), pass /
    fail / error / broken: substrate 85078 / 3 / 2 / 1, formula 104 / 12 / 0 / 0,
    sdl 690, write_pdf 43, assistant_mvp 127 / 4, example_conversation_widget
    4694 / 1060 (at `TypeinTest.jl:587`), example_assistant 13310 / 2,
    example_markdown 3911, example_markdown_rendered 3660 / 8 / 0 / 86,
    catalog_markdown 30080, catalog_text 10498 / 0 / 0 / 12. 1091 fail and error
    entries in all, the same set as at `f5955aef`; `sdl` has 4 more passes from
    `ee1e494d`.
- [x] **Step 1. The caret stream counts an image** (§3.1).
  `get_flat_length(::TextGraphics) = 1`, U+FFFC in `_push_flat_chars!`, the
  comments that say zero, and `splice_value!` over a `TextBlock` in the caret
  space. Tests: the offsets, the total, the characters and the base of a block
  with images at the start, in the middle and at the end, and in a `TextLine`.
  - *Done.* The character is the constant `OBJECT_REPLACEMENT_CHARACTER` of
    `TextDocument.jl`. The tests of this plan are in one file,
    [InlineImageCaretTest.jl](../../test/substrate/projection/InlineImageCaretTest.jl)
    (`test_inline_image_caret`, in `test_substrate`).
  - *Decision:* the only producer of an edit that reaches `splice_value!` over a
    `TextBlock` is the leaf of a book paragraph, and that leaf held only the
    characters of the text runs. So the leaf now holds the flat string of the
    text, from a new exported `get_flat_string(::TextBlock)`, and the leaf and
    `splice_value!` count in one space. A paragraph of text runs only renders as
    before. Test: `BookToSyntaxTest`, a paragraph with a `TextNewline`.
  - The text projection tests (`test_text_to_graphics`, `test_word_wrapping`,
    the decorators, `test_syntax_to_text`) pass with no change after this step.
- [x] **Step 2. From an offset to a place** (§3.2). `_flat_to_span` and the
  functions beside it answer the caret before or after an image where no text
  run holds the offset; `get_flat_cursor_coordinate` passes it on, and the caret
  of `_layout_group` is drawn beside the image. Tests: every caret of
  `"ab"[image]"cd"`, `[image]"ab"`, `"ab"[image]` and `[image][image]`, and where
  each is drawn.
  - *Done.* *Decision:* `_flat_to_span` still answers text runs only, because
    the edit code (`evaluate_operation`, `_lower_text_range`) splices the run it
    returns. A new `_find_flat_place` answers the run, else the image beside the
    offset (`_find_flat_image_place`, over `_text_image_paths`); between two
    images, the caret after the earlier one. `get_flat_cursor_coordinate` and
    `_text_flat_span` use it. The caret branch of `_layout_group` needed no
    change.
  - *Fact:* after Steps 1 and 2 the type-in walks of the three examples have no
    failure (`test_example`, pass / fail / broken): `text_with_image`
    1487 / 0 / 0, `text_baseline` 2989 / 0 / 8, `text_line_height`
    3489 / 0 / 2. A typed character after an image now goes into the run after
    it. Fewer rules are broken because Delete at the end of a run before an
    image now declines (the range covers the image) where it deleted the first
    character after the image before; Step 4 makes it delete the image. The
    navigation counts do not change.
- [x] **Step 3. Motion** (§3.3). Left, Right, Ctrl+arrow, Ctrl+Home, Ctrl+End, and
  the geometric Home, End, Up, Down and click. `TextToGraphicsTest.jl:198-225`
  keeps its numbers, and its comment says what they mean. Tests: a walk with
  Right from 0 to the total visits each caret once, and Left walks back.
  - *Done.* Left, Right, Ctrl+Home, Ctrl+End, Home, End, Up, Down and a click
    needed no change after Steps 1 and 2: the geometric keys already took an
    image segment as `0..1`. Word motion has a third class, `_is_image_char`:
    Ctrl+Right skips one image, then the separators, so it stops before and
    after an image that touches a word. The reader guard of the geometric keys
    is `_has_caret_span` (a text run or an image), so a line of images has
    carets.
  - *Fact:* the walks of the navigation sweep stop for two reasons that are not
    images. In `text_with_image` the left walk stops at 152, at a soft wrap:
    Left from the start of a wrapped line maps back to the same input offset
    (the stall of `NAV_LEFT_WALK_STALLS`, owned by
    [left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md)).
    In `text_baseline` the right walk stops at 225, before an empty line of two
    `TextNewline`s: `WordWrapping` maps an offset in a gap back to the nearest
    run (`convert_flat_offset_to_element`), so the caret can not stand on the
    empty line. This plan does not fix either.
- [x] **Step 4. Edits** (§3.4). The reader of the text domain types beside an
  image, starts a new run with `insert_elements`, and deletes an image with
  `delete_elements`, each followed by the caret. The operations go through the
  decorators (`WordWrapping` lowers them against its input) and undo. Tests: each
  edit and its undo, directly and through `WordWrapping` and `TextToGraphics`.
  - *Done.* The gesture table still makes a flat `ReplaceTextRangeOperation`.
    Its lowering decides: `_make_image_edit` (TextDocument.jl), called first by
    `_lower_text_range` and by `evaluate_operation(::ReplaceTextRangeOperation)`,
    answers an element write for an insertion beside an image where no run holds
    the caret (`insert_elements` with the flat caret after it) and for a range of
    only images (`delete_elements`, or a splice to one new run when the range is
    replaced, with the caret after it). Every other edit lowers as before.
  - *Decision:* a range of only images with a replacement puts one new run of the
    replacement in their place, as a word processor replaces a selected picture
    with the typed text. The plan said only "deletes it".
  - *Decision:* a new run copies all five style fields (`font`, `font_color`,
    `fill_color`, `line_color`, `padding`) of the span that `_find_style_span`
    finds, as a character typed into that run would have them. On a line with no
    run, the first run of the block, else its first `TextNewline`, else the
    default `TextString(content)`.
  - *Decision:* a stage that changes the element indices declines an element
    write of its output, and the chain reads the gesture again against its input
    (`ChainingProjection`: "a claim that no step can carry is no claim"). The
    predicate is the new exported `is_text_element_write`. `WordWrapping`,
    `TextFiltering`, `TextFirstLine`, `TextHighlighting` and `SelectionInverting`
    each have a method for it; they passed every operation up unchanged before.
    `TextLineNumbering` declines through the kernel default, because its backward
    map answers `nothing` for a bare `.elements{a:b}`. `SyntaxToText` declines it
    in the gesture readers of a leaf and a compound, and after its own lowering
    (question 5).
  - *Part of Step 5 done here,* because an edit through `WordWrapping` needs it:
    `convert_flat_offset_to_element` answers the image beside an offset (through
    `_find_flat_place`), and `TextHighlighting` and `SelectionInverting` record a
    segment of length 1 for an image, as `WordWrapping` did.
  - *Fact:* the clipboard paste (`make_text_insert_operation`) beside an image
    now starts a new run too.
  - *Fact:* a flat `ReplaceTextRangeOperation` that reaches the editor unlowered
    has no inverse (`make_inverse_operation`), on `main` too. Through
    `TextToGraphics` the edit arrives lowered, and undo works.
  - *Fact:* the type-in walks fail again, 2 / 1 / 1 in the three examples:
    "backspace at the boundary produced CompoundOperation, expected no edit". The
    walk expects no edit where Backspace now deletes the image; Step 8 teaches
    it.
- [ ] **Step 5. The decorators and `SyntaxToText`** (§3.1, question 5). The runs of
  `WordWrapping`, `TextFiltering`, `TextFirstLine`, `TextLineNumbering` and
  `SelectionInverting` hold an image as a run of length 1, and the mapping of a
  caret lands beside it. `_text_elem_path_to_flat` and `_flat_to_span_char` count
  an image as 1. Tests: a caret beside an image through each decorator, and a
  walk over a Markdown picture leaf with a real image file.
- [ ] **Step 5b. The style beside an image** (§3.5, question 7). The caret beside
  an image, the prevailing font of a block and the height of a line with no
  glyph take the style of the nearest text run, by the rule of §3.4.
  `TextGraphics` loses `font` and `font_color`, and every producer stops passing
  them: `BookToSyntax.jl:557, 568`, `MarkdownToSyntax.jl:446`,
  `RstToSyntax.jl:1145`, the examples (`TextDocumentExample.jl:38, 40, 94`,
  `TextLayoutDocumentExample.jl:30, 56`), the tests, and omnet-julia and
  inet-julia if they make one. The walks that skip the style fields of a span
  (`TypeinTest.jl:125-126`, `SelectionEnumeration.jl`) are read again. Tests: the
  caret height beside an image in a line of a small font, a line that holds only
  an image, and a new run typed after an image at the end of a line.
- [ ] **Step 6. The string of a text** (§3.6). `TextToString` gives an image U+FFFC.
  Test: the string of `text_with_image` and its length against the total.
- [ ] **Step 7. The paint of a selection** (§3.7, question 6). A caret-space range
  is painted with caret-space offsets, and an image in a range is painted. Tests:
  a range across a `TextNewline`, across a soft newline and across an image
  paints exactly its characters, checked by the x of each row end.
- [ ] **Step 8. The type-in walk.** At the start of the run after an image, a typed
  character goes into that run, and Backspace yields the deletion of the image;
  Delete at the end of the run before an image yields it too. The walk asserts
  such a deletion without evaluating it, as it asserts a declined edit. The rule
  at `TypeinTest.jl:559-564` that marks Delete at the end of a run as broken is
  read again. The 8 failures of the three examples pass.
- [ ] **Step 9. The suites** of Step 0 against the baseline, in a fresh process;
  a moved count is explained before it is accepted. Images of the three examples
  with a caret after an image go to the owner.
- [ ] **Step 10. The documents.** `text.md` (an image counts one; the list at :28;
  the limits), the comments of `TextToGraphics` about the two spaces, and
  [text-domain-kit.md](text-domain-kit.md) :378-384, which says the two spaces
  differ on images.

## 7. Relations and risks

- [text-domain-kit.md](text-domain-kit.md) (pending) argues to keep the two
  spaces apart (:378-384). They stay apart for soft newlines; they agree on
  images after this plan.
- [left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md)
  (pending) names the walk of `text_with_image` as asymmetric (:160-166). Step 3
  can change it; its counts are compared, not assumed.
- **Counts move.** The type-in, navigation and catalog counts of every example with
  an image move, because each image adds carets. Step 9 explains each move.
- **The rerooting of a list splice** through `WordWrapping` and `TextToGraphics`
  is new for the text domain. Step 4 tests it through the real chain, and undo
  with it.
