# Examples of how text layout works

> **Status:** in progress, in the worktree `projectured-julia-text-layout-examples`
> on the branch `text-layout-examples`, from `48ecec12`. Written 2026-09-26. The
> owner asked: "Create examples in projectured which shows how text layout
> works".

## 1. The request

The text line model landed on 2026-09-26
([a-line-of-text-sits-on-one-baseline.md](../done/a-line-of-text-sits-on-one-baseline.md)).
A reader of the code or a user of the editor can not see its rules without a
document that shows each one. The examples show them, and the text of each
example says what to look at.

## 2. The examples

All are `TextBlock` documents in `example/substrate/TextLayoutExample.jl`, laid
out by `WordWrapping` (at most 700 pixels) and `TextToGraphics`, and registered
in `example/substrate/SubstrateExamples.jl`.

| Example | What it shows |
| --- | --- |
| `text_baseline` | runs of several fonts and sizes, a fallback arrow, an emoji and an inline icon on one baseline |
| `text_line_height` | each line as high as its fonts ask; a code line with no line gap; an image on the baseline |
| `text_kerning` | kerned pairs in a large bold font, a monospace line with no kerning, the caret in a pair |
| `text_selection` | a text of mixed sizes to select across lines and to click between lines |
| `text_spacing_single` | single spacing, the natural distance of the fonts |
| `text_spacing_one_and_a_half` | 1.5 times the natural distance |
| `text_spacing_double` | 2 times the natural distance |
| `text_spacing_exactly` | exactly 20 pixels, less than the 23 of the fonts, so descenders touch the next line |
| `text_spacing_at_least` | at least 30 pixels |

Two vectors group them: `text_layout_examples` holds the first four, and
`text_spacing_examples` the five spacings, so that `run_example` opens a group
side by side.

## 3. Steps

- [x] **Step 1.** The documents, the projection and the registration.
- [x] **Step 2.** `test_example` passes for each example.
  *Result:* six examples pass fully. `text_baseline` fails 18 type-in
  assertions, `text_line_height` 6 and `text_selection` 8, all at
  `TypeinTest.jl:555`, and all at offset 0 of a span that follows another text
  span on the same line. There the flat caret is the end of the previous span: an
  insert goes into the previous span, and a Backspace deletes its last
  character, as a word processor does at the seam of two style runs. The
  type-in test expects each span start to be a place of its own. The owner
  chose on 2026-09-26 that the test treats the start of a run that directly
  follows another text run as the caret at the end of that run, and tests it
  once (`_walk_span_strings!` in `TypeinTest.jl`).
  *Done.* The seams of two text runs pass. Four failures remain, two in
  `text_baseline` and two in `text_line_height`, at the start of the run after
  an inline image: an image has no width in the flat caret stream, so the caret
  after an image is the caret before it, and a typed character goes before the
  image. `text_with_image_example` fails the same 4 assertions on `main`. It is a
  fault of the caret model, not of the examples, and the test keeps it visible.
  The suites of Step 0 fail as `main` does (1068 type-in failures of the
  conversation widget, at the same assertion, whose line moved to 587). The
  substrate count rises by 3593: the printer walks of the nine examples, which
  `test_substrate_examples` walks (543, 573, 385, 444, 324, 324, 324, 352, 324).
- [x] **Step 3.** Images of each example at ratio 1 and 2 go to the owner.
  *Done:* `/var/tmp/text-layout-examples/images2/`. The exact spacing is 20
  pixels: at 16 the heading and the first sentence could not be read.
- [x] **Step 4.** `text.md` names the examples.
