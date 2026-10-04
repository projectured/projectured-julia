# The default look fits a desktop at 100%

> **Status:** pending, not started. Written on 2026-10-02 at the owner's
> request. The owner decided the goal, the reference, the scope and the font
> model on 2026-10-02, and answered the five questions of section 4 the same
> day. Section 5 logs each decision. No question is open.

## 1. The request

The owner wrote on 2026-10-02:

> in projectured-julia, the text size and spacing size feels large on my current
> screen and I'm not sure we are using sensible defaults
>
> I changed the settings to make it look good: font size to 80%, spacing size to
> 67%
>
> I would like to have sensible defaults which look good on most computers for
> other users

After the first report, the owner answered:

> for 1, we can do the same as VS code around
> for 2, yes, follow them
> for 3, … we should find sensible spacing defaults that works on a desktop
> program. The scales should be kept 100%
>
> all places should use themes for fonts and sizes and have sensible default. I
> don't care about the recorded videos, they don't have to match exactly.
>
> maybe we should also get rid of the color and font constants and use some
> registry which caches the immutable instances and looks them up during
> projection construction based on parameters. what do you think?

The owner answered "yes" to the counter-proposal of section 3.1 and 3.2: a font
is a description, and a registry of font faces finds its file. There is no
cache of instances.

## 2. What exists

### 2.1 The screen and the density

- The screen of the owner is HDMI-1, 1920×1200 on 520×320 mm, about 94 dots per
  inch. `xrdb -query` gives `Xft.dpi: 96`. The GNOME interface font is
  Adwaita Sans 11 pt, which is 14.7 px.
- `_detect_display_density!` in `source/backend/sdl/SdlBackend.jl` reads
  `Xft.dpi / 96` and gives the density 1.0. This is correct, so the density is
  not the cause.
- At the density 1, one logical pixel is 1/96 inch, the reference pixel of CSS.
  A default that looks right on this screen at 100% is a correct default for a
  desktop.

### 2.2 The sizes

- The widgets draw text in Ubuntu 20 px (`WidgetTheme.font`). The syntax, text,
  JSON and most other domain themes use Ubuntu Mono 20 px. The Markdown
  headings are 36, 24, 22 and 18 px.
- The Lisp original used 24 px. Commit `0d86b6712` (2026-06-30) changed every
  24 to 20.
- Other programs at the density 1:

  | Program | Text size |
  | --- | --- |
  | VS Code | 13 px interface, 14 px editor |
  | JetBrains | 13 px |
  | macOS | 13 px |
  | Windows | 12 to 14 px |
  | GNOME on the screen of the owner | 14.7 px |
  | Web body text | 16 px |

- The spacings of `WidgetTheme` follow shadcn/ui, which is made for web pages:
  a control padding of 9/14, a card padding of 16, a badge padding of 3/10,
  gaps from 4 to 12 and a tree indent of 22. The parts of controls are a
  checkbox of 18, a switch of 44×24, a slider of 24 and a scroll bar of 12. The
  radii are 8 and 4.
- The look that the owner chose on this screen is the font scale 0.8, so text of
  16 px, and the spacing scale 0.67. The owner did not save it.

### 2.3 The font model

- A font is `StyleFont(filename, size)` in `source/platform/style/Font.jl`. The
  file is the identity of a face. The family, the weight and the slant are only
  in the name of the file.
- `Font.jl` defines 143 constants, one for each face and size. They cover
  Ubuntu, Ubuntu Mono, DejaVu Sans, DejaVu Sans Mono, Liberation Sans and
  Liberation Serif, each regular, bold and italic. The sizes are 14, 16, 18,
  20, 22, 24, 30, 36, 42 and 48. Two more are Inconsolata 18 and the Lucide
  icon font. No constant has the size 13.
- `font_file` in `TrueType.jl` finds a file by its name in the font search path
  at run time, so a bundle on another machine finds its fonts.
- Twelve files read `font.filename`: `SdlBackend.jl` (the TTF handle cache
  `_font_cache`, keyed by file and device size), `TextMeasure.jl`,
  `TrueType.jl` (the fallback chain), `PdfWriter.jl` (one embedded font for each
  file), `WebBackend.jl`, `VideoBackend.jl`, `AppearanceToWidget.jl` (steps
  through the files), `Appearance.jl` (saves a font as a file and a size),
  `WidgetToGraphics.jl`, `SyntaxToText.jl`, `FileDialog.jl` and
  `MathToGraphics.jl`.
- A theme holds a full font in each text field. `SyntaxTheme` repeats Ubuntu
  Mono 20 in 15 `StyleText` fields and in its `font` field. To change the
  family or the size of code text, a person changes 16 fields.
- `WidgetTheme.font_bold` is a separate file from `WidgetTheme.font`. When a
  person changes `font` to DejaVu Sans, the titles stay in Ubuntu Bold.
- The fallback chain for a missing glyph is one list for every font: DejaVu
  Sans Mono, then Noto Emoji. A bold font tries DejaVu Sans Mono Bold first.
- The memory of the style values, measured on `main` on 2026-10-02:

  | Value | Bytes | Stored inline | Heap memory for a new value |
  | --- | --- | --- | --- |
  | `StyleColor` | 32 | yes, a bits type | 0 bytes |
  | `StyleFont` | 16 | yes | 0 bytes |
  | `StyleText` | 48 | yes | 0 bytes |

  Julia copies an immutable value into the field or the array that holds it, so
  two holders can not share one instance. The file name is the only part of a
  font on the heap, and every copy points to the same `String`. 10,000
  `TextString`s use 3,489,046 bytes, which is 349 bytes each. The font and the
  color are 48 bytes of each, about 14%.

### 2.4 The colors

`Color.jl` defines 1077 color constants with 1076 names, because
`color_pastel_orange` occurs two times. They are curated ramps (slate, zinc,
indigo, solarized, …) and a list of color names. The themes take their defaults
from the ramps.

### 2.5 The theme model

- A domain declares its theme with `@theme struct`. There are 29 themes, all in
  projectured-julia. The type of a field chooses its scale: `StyleFont` and
  `StyleText` take the font scale, `Spacing` the spacing scale, and so on.
- A projection takes its scaled theme with `get_scaled_theme!(appearance, T)`
  while it is built. A constructor takes a theme as a keyword with a default,
  for tests and examples.
- A font in a document is as its author set it, and a scale does not change it
  (`plan/done/zoom-and-theme-controls.md`, section 4.3).
- `scale_length` keeps a length above 0 at 1 or more.

### 2.6 Fixed values outside a theme

An inventory of 2026-10-02 counted the style values that are fixed outside a
`@theme` declaration:

| Repository | Fonts | Colors | `StyleText` | Fixed lengths |
| --- | --- | --- | --- | --- |
| projectured-julia, `source/` | 44 | about 300 | 50 | about 40 constants, about 150 keyword defaults |
| projectured-julia, `example/` | 102 | about 110 | 4 | about 90 |
| omnet-julia | 116 | 156 | 79 | 20 constants, about 200 keyword defaults |
| inet-julia | 6 | 11 | 3 | 1 |

- omnet-julia and inet-julia declare no theme. The NED, INI, test file and
  result views of omnet-julia fix Ubuntu Mono 24, so the font scale does not
  reach them. `NedToSyntax.jl` alone holds 43 fonts and 43 colors. The other
  views of omnet-julia use the themes of projectured-julia.
- In projectured-julia, most fixed colors are in `WidgetToGraphics.jl` (92),
  `SqlToSyntax.jl` (32), `JuliaToSyntax.jl` (18) and `GraphicsDocument.jl`
  (18).
- Some fonts are fixed in a projection and do not follow the font scale, for
  example `_PROMPT_STYLE` in `EvaluatorToWidget.jl`, the fonts of
  `ConversationToWidget.jl`, `FaultLogOverlay.jl` and `GestureLogOverlay.jl`.
- Some fixed values are not a style. `color_transparent` means "no paint". About
  140 keyword defaults are `= 0`, which means "no fixed size". `indentation` in
  `RstToSyntax.jl` is a depth of recursion.

### 2.7 Related plans

`plan/pending/line-spacing-from-the-theme.md` is not started. No theme sets the
line spacing, so every text has single spacing. VS Code draws its 14 px editor
text on lines 19 px apart.

## 3. The design

### 3.1 A font is a description

A font says its family, its size, its weight and its slant:
`StyleFont("Ubuntu Mono", 14; weight = 700)`. CSS, fontconfig and Qt's `QFont`
use this model.

- The weight is a CSS number from 100 to 900: 400 is regular, 700 is bold. The
  OpenType `usWeightClass` uses the same scale.
- The slant is the `Bool` field `italic`, so a call reads
  `StyleFont("Ubuntu", 13; italic = true)`. An oblique face counts as italic.
- The size stays an `Int` in logical pixels.
- Two equal descriptions are equal values, as two equal fonts are now. There is
  no cache of instances (D5). A cache gives back a copy of the same value, and
  the copy uses the same memory (section 2.3).
- The description stays small (D13). The weight is an `Int16` and the slant is
  one byte. The weight is signed because Julia prints an unsigned integer in
  hexadecimal: a `UInt16` weight of 700 shows as `0x02bc`. With the family `String` and the `Int` size, a font is 24 bytes
  inline, and a new font allocates nothing. A cache could save memory only if a
  field held a small number for the font in place of the value. That saves
  about 40 bytes of the 349 of a `TextString`, about 11%. It costs a global table
  that can change, a lookup at each read, and a font that means nothing
  without the table.
- The exact names of the fields and the functions follow
  `documentation/rule/naming-rules.md` and are fixed at step F2.

### 3.2 The registry of font faces

- The registry is a table from family, weight and slant to the name of a file.
  It holds the bundled faces of `asset/font/`: Ubuntu (light, regular, medium,
  bold, each upright and italic), Ubuntu Condensed, Ubuntu Mono, DejaVu Sans,
  DejaVu Sans Mono, Liberation Sans, Liberation Serif, Liberation Mono,
  Inconsolata, Lucide and Noto Emoji.
- The table is a constant in code. It holds file names, not paths, and
  `font_file` resolves a name at run time, as now.
- The lookup follows the font matching of CSS: the family, then the nearest
  weight, then the slant. An italic that the family does not have falls back to
  upright. A family that the table does not hold falls back to a default family.
- The fallback chain for a missing glyph comes from the registry.
- Only the measure and the backends ask the registry: SDL, PDF, web, video, and
  `MathToGraphics.jl`. A projection never asks it.
- The SDL handle cache and the PDF font embed stay keyed by the file. Two
  descriptions can find one file, for example weight 500 and weight 400 in a
  family with no medium face.

### 3.3 A theme holds base fonts and text roles

The owner chose this model on 2026-10-02 (D8).

- A theme that draws text holds its base fonts: `font` for proportional text
  and `code_font` for monospace text, each with a family and a size.
- A text field holds a role: a color, a weight, a slant, a relative size with
  the default 1.0, and the base font it starts from.
- The scaled theme computes the final `StyleText` of each role from its base
  font, so the printers do not change.
- The Markdown headings become 2.0, 1.5, 1.25 and 1.0 times the body text, as
  in GitHub.
- The appearance tab shows the family and the size of a base font one time for
  each theme.
- `@theme` needs a field that it computes from two fields: the base font and the
  role. Now each scaled field reads only its own base value.

### 3.4 Every style value comes from a theme

Each fixed value of section 2.6 is one of three kinds:

- **A style of a projection.** It becomes a field of the theme of its domain.
  A domain that has no theme gets one. Examples: the prompt of the evaluator,
  the fonts of the conversation, the padding of the window menu, the colors of
  `SqlToSyntax.jl` and `JuliaToSyntax.jl`.
- **The content of a document.** A font, a color or a size that the author of a
  document gives stays in the document: the examples, `WidgetSpinBox(width =
  80)`, a text that a document constructor makes. It is written with a font
  description, at the new sizes (D11).
- **Not a style.** `color_transparent`, a `0` that means "no fixed size", a
  depth of recursion, a protocol constant.

omnet-julia gets themes for its NED, INI, test file, result and workbench
views. inet-julia gets a theme for the packet diagram. They declare `@theme` in
their own repository, and the `Appearance` holds them by type, as any theme.

### 3.5 The guard

A static test in each repository, beside the layering guard and the naming
guard, fails when one of these occurs outside an allowed place:

- a font description, a palette color, `StyleColor(` or `StyleText(`;
- `Inset(`, `Spacing(`, `Radius(`, `LineWidth(`, `ControlSize(` or `IconSize(`
  with a number.

The allowed places are a `@theme` declaration, a preset function of a theme,
the palette, the registry, the examples and the tests. A line in a document
constructor that sets content carries the marker
`# @style: content of the document`, as `# @positional:` marks an exception to
the argument count. `color_transparent` is allowed everywhere. The guard does
not read bare numbers. Step T1 classifies them one time, and a review covers
them after that.

### 3.6 The default values

The reference is VS Code on Linux at the density 1 (D1).

- The interface text is Ubuntu 13 px.
- The code text is 14 px. Ubuntu Mono has glyphs 0.5 em wide and DejaVu Sans
  Mono 0.6 em, so Ubuntu Mono 14 looks smaller than the 14 px of VS Code. Step V1
  shows Ubuntu Mono 14, 15 and 16 and DejaVu Sans Mono 14, and the owner chooses.
- The prose text of Markdown, reStructuredText and books is 14 px.
- The line spacing (D9): code lines 1.35 times the font size, as VS Code on
  Linux (19 px for 14 px), prose 1.5, widgets single.

A first proposal for `WidgetTheme`. Step V1 shows it in images, and the owner
chooses:

| Field | Now | Proposal | Reference |
| --- | --- | --- | --- |
| `font` | Ubuntu 20 | Ubuntu 13 | VS Code interface 13 |
| `font_bold` | Ubuntu Bold 20 | Ubuntu Bold 13 | |
| `font_small` | Ubuntu 18 | Ubuntu 11 | VS Code badge 11 |
| `control_padding` | 9, 9, 14, 14 | 5, 5, 10, 10 | VS Code button 26 px high |
| `container_padding` | 16 | 12 | |
| `compact_padding` | 3, 3, 10, 10 | 2, 2, 6, 6 | VS Code badge 3/6 |
| `item_gap` | 4 | 2 | |
| `title_gap` | 6 | 4 | |
| `label_gap` | 6 | 6 | |
| `section_gap` | 10 | 8 | |
| `bar_gap` | 12 | 8 | VS Code menu bar item 8 |
| `indent` | 22 | 12 | VS Code tree indent 8 |
| `radius` | 8 | 6 | VS Code 2 to 4, GNOME 6 |
| `radius_small` | 4 | 3 | |
| `indicator_size` | 18 | 16 | VS Code checkbox 18, GNOME 14 |
| `indicator_dot` | 5 | 4 | |
| `switch_track` | 44×24 | 36×20 | macOS 38×22 |
| `switch_knob_padding` | 3 | 2 | |
| `slider_height` | 24 | 20 | |
| `slider_knob` | 9 | 7 | |
| `progress_height` | 8 | 4 | |
| `scroll_bar_thickness` | 12 | 10 | VS Code lists 10, editor 14 |
| `tree_chevron_column` | 18 | 16 | VS Code twistie 16 |

The other fields keep their values. The spacings of the other themes, such as
`MarkdownTheme.block_gap` and the chart spacings, are set at step V2 with the
same reference.

## 4. Questions for the owner

Each question had a recommendation. On 2026-10-02 the owner took every
recommendation: "agreed on all". Section 5 logs them as D8 to D12.

1. **Q1. Base fonts and roles, or a full font in each field?** Section 3.3
   describes base fonts and roles. The other choice keeps a full font in each
   field and only replaces the constants. That choice is smaller, but a change of
   the code size stays 16 changes in the syntax theme alone. Recommendation: base
   fonts and roles, Part R.
2. **Q2. Does this plan take in `line-spacing-from-the-theme.md`?** The line
   height is half of what makes code look dense: VS Code draws 14 px text on
   19 px lines, and single spacing draws it on about 15 px lines. The themes of
   this plan are the place for it. Recommendation: yes, as step V2.
3. **Q3. Which families are the defaults?** Recommendation: Ubuntu for the
   interface, as now. It is bundled, so the metrics are the same on each
   machine, and the measure needs a file. The code family follows the images of
   step V1. A system font is not in this plan.
4. **Q4. Fonts in documents.** One choice keeps a font in the content of a
   document, marked for the guard. The other choice lets a text without a font
   take the font of the theme of the projection that prints it, as HTML text
   takes its font from the style sheet. Recommendation: keep the font in the
   content now. The second choice changes the text documents and every reader of
   `TextString.font`, so it needs its own plan.
5. **Q5. Saved appearance files with a font as a file name.** Recommendation:
   drop that form. A key that is not known is ignored and the default applies.
   The owner has no saved file.

## 5. The decision log

- **D1** (2026-10-02). The reference is VS Code: interface text 13 px, editor
  text 14 px. The owner: "we can do the same as VS code around".
- **D2** (2026-10-02). omnet-julia and inet-julia follow in the same work.
- **D3** (2026-10-02). Every scale stays at 100%. The new look is in the base
  values of the themes. The spacings are the defaults of a desktop program.
- **D4** (2026-10-02). Every place takes its fonts and sizes from a theme, with
  a sensible default.
- **D5** (2026-10-02). A font is a description, and a registry of font faces
  finds its file. There is no cache of instances. The colors stay palette data,
  and only a theme default or a preset names a palette color.
- **D6** (2026-10-02). The recorded videos do not need to match.
- **D7** (2026-10-02). The density probe does not change.
- **D8** (2026-10-02, Q1). A theme holds base fonts and text roles (section
  3.3, Part R).
- **D9** (2026-10-02, Q2). This plan takes in
  `plan/pending/line-spacing-from-the-theme.md`. The line spacing is a theme
  value. Step V2 sets it: code 1.35 times the font size, prose 1.5, widgets
  single. Both plans move to `plan/done/` when this plan is done.
- **D10** (2026-10-02, Q3). Ubuntu stays the interface font. The images of step
  V1 choose the code font.
- **D11** (2026-10-02, Q4). A document keeps the fonts that its author gives,
  marked for the guard. A text without a font that takes the font of the theme
  needs its own plan.
- **D12** (2026-10-02, Q5). The saved form of a font as a file name goes. A key
  that is not known is ignored, and the default applies.
- **D13** (2026-10-02). The owner asked if a cache of instances saves memory.
  The measurement of section 2.3 shows that it does not. The weight and the
  slant of a font are small integers, so a font stays at 24 bytes inline or
  less, and a new font allocates nothing.
- **D14** (2026-10-02, V1). The code font is Ubuntu Mono. The owner: "Ubuntu
  Mono".
- **D16** (2026-10-02, V1). The default sizes are the proposal of section 3.6:
  the interface text 13 px, code and documents 14 px, the tool panes 13 px,
  the charts 12 px, and the spacings of the table. The owner: "the proposal".
- **D17** (2026-10-02, T1). The owner accepts the review of step T1: the
  content list, the list of "not a style" with the sizes of outputs and
  windows added, and fewer new themes. A chrome value that a field of
  `WidgetTheme` already says takes that field; a new theme only for a slice
  with several values of its own.
- **D18** (2026-10-02, T2). A widget document that sets no padding takes the
  padding of its kind from `WidgetTheme`, as a browser takes a default style
  for each kind of element. The builders of window chrome, of the assistant
  and of a card leave the padding out. The owner: "yes". This also gives
  padding to the widgets of these kinds that now set none, such as the
  context menus and the menus of the data frame and of the fault log, so they
  change on the screen. The owner accepted that change: "Yes for the menu
  question".
- **D19** (2026-10-02, T2). A small `GraphicsTheme` in the graphics slice holds
  the selection ring and the fault mark of the graphics and layout slices,
  which lie below every other theme; `WidgetTheme` reads the ring from it and
  has no copy of its own. The owner: "yes".
- **D20** (2026-10-02, T2). In this plan, a value that the old look had is no
  reason to keep it. The paddings that builders set go to the default of their
  widget kind, also where that changes other widgets of the kind. The owner:
  "Backward compatibility is not a goal, we should make it correct and
  beautiful first". The image check still finds the changes, to show which ones
  were not intended.
- **D21** (2026-10-03, T2). A builder that makes widgets outside a printer (a
  dialog, a bar of the pager, of a filter or of a column chooser, the value
  list of a data frame) takes the theme from the place that calls it: the
  view, the editor or the page. A button that it makes takes the size of its
  label. The owner: "yes".
- **D22** (2026-10-03, T2). A checkbox and a switch carry a label of their own,
  as in a desktop toolkit, at the gap of the theme from the mark. A builder no
  longer puts a label beside them in a layout. The owner: "yes".
- **D23** (2026-10-03, T2). A column of a grid can fill the width that its
  parent offers and keep the width of its content when no width is offered, so
  the cards of a form fill the pane and do not collapse where nothing is
  offered. The owner: "yes".
- **D24** (2026-10-03, T2). The column chooser of a table shows each column as a
  checkbox with its own label, not as a button with "[x]" or "[ ]". The owner:
  "yes".
- **D25** (2026-10-03, V2). The line spacing keeps the existing spacing types.
  `MultipleSpacing` counts from the natural line height of the font, so its
  factors are chosen to give about 1.35 times the font size for code and 1.5
  times for prose with the default fonts, as D9 asks. The owner: "option 2,
  follows the plan".
- **D26** (2026-10-03, V2). A horizontal layout can align its children on the
  baseline of their first line (`vertical_align = :baseline`), as Qt and CSS
  do, so a label or a prompt beside a text of another line spacing stands on
  the same baseline. The evaluator aligns its prompt rows so. The owner:
  "option 1, agreed with recommendation: baseline alignment".
- **D27** (2026-10-04, after the landing). A table gives the text of its cells
  single spacing through the printer context, as CSS passes `line-height` down
  to the cells of a table: the table sets the property `:line_spacing`, and the
  text stage draws at that spacing when its context holds one. So a value in a
  cell and the number of its row stand on one line. The owner: "option A is
  ok".
- **D28** (2026-10-04, T2). A field of Julia code, such as the filter box of a
  data frame, takes the colors of its tokens from the text roles of the
  `JuliaTheme` of its appearance, so the same code looks the same in the field
  and in the code view, and an edit in the appearance tab reaches the field.
  Later the field draws through the Julia domain and does not tokenize the code
  again (section 9). The owner: "yes but eventually it should be using the
  julia domain and should not reimplement".
- **D29** (2026-10-04, T2). The views of the view registry of omnet-julia get the
  appearance of the editor after the first release. The owner: "agreed".
- **D31** (2026-10-04, T2). The panel of the newest gestures over a window is the
  translucent `panel_background` of the gesture log theme, as every overlay of
  the log. The owner: "the overlay I liked it semi transparent".
- **D30** (2026-10-04, T2). The color swatch of the appearance tab is a widget
  of its own kind now, which draws a square of a given size. The owner: "add a
  swatch now".
- **D15** (2026-10-02, T1). The pointer ring and the fault band of the video
  backend, and the glyph cursor of the SDL backend, stay as they are: they mark
  a recording or the system cursor, not the look of the editor.

## 6. Steps

The work is done in a worktree of each repository. Each step is one commit.
Parts F, R and T change no pixel, and section 7.1 checks each of their steps.
Part V changes the look. When a step changes a name that omnet-julia or
inet-julia uses, the same step changes them, so that they always load.

### Part F: the font description and the registry

- [x] **F1.** The registry of the bundled faces and its lookup, with tests. No
  caller yet. *Done:* `FontFace(family, weight::Int16, italic::Bool, file)` and
  the table `_FONT_FACES` of 34 faces in `source/platform/style/FontFace.jl`;
  `find_font_face(family, weight, italic)` and `get_font_face_path(face)`.
  `TrueTypeFont` reads `weight_class` and `is_italic` from the OS/2 table, and
  `test_font_face` checks each face against its file and each file against
  the table. See section 10 for what the step found.
- [x] **F2.** `StyleFont` becomes the description. The twelve readers of
  `font.filename` ask the registry. The 143 constants stay, now defined as
  descriptions, so their callers do not change. `save_appearance!` and
  `load_appearance!` write and read the family, the weight, the slant and the
  size. A test checks that `StyleFont` is stored inline, is 24 bytes or less,
  and that a new font allocates nothing (D13). *Done:*
  `StyleFont(family, size; weight = 400, italic = false)` with the fields
  `family::String`, `size::Int`, `weight::Int16` and `italic::Bool`.
  `compute_font_path(font)` gives the path of the face, or of DejaVu Sans for a
  family with no bundled face; every reader of the file and every font cache
  keys on it. `with_font_size(font, size)` replaces each
  `StyleFont(font.filename, size)`. `get_font_families()` names the families,
  and the appearance tab steps through them until step F4. Each of the 143
  constants finds the file that it named before. The image check of section
  7.1 found 315 of 315 outputs equal (105 examples, a PNG at the density 1 and
  2, and a PDF). omnet-julia changes one test that read `font.filename`.
- [x] **F3.** The fallback chain comes from the registry. *Done:*
  `get_fallback_font_files(font)` and `find_glyph_font_file(font, character)`
  take a font. The fallback families are DejaVu Sans Mono and then Noto Emoji.
  For each, the chain takes the upright face at the weight of the font, then
  the upright regular face. For every bundled face this gives the files that
  the rule on the file name gave, italic text included: its fallback glyphs
  stand upright. The fallback section is in `FontFace.jl`.
- [x] **F4.** The appearance tab chooses a family, a weight, a slant and a size,
  in place of the steps through the files. *Done:* the font control has two
  rows: "‹ family ›", then "− weight +", a checkbox for italic and the spin box
  of the size. The weight steps through the weights of the family, from
  `get_font_weights(family)`, and stops at the lightest and the heaviest. The
  checkbox goes through the `writes` of the tab, as a spin box does. A select
  does not: it answers from its popup window, so it is not used.
- [x] **F5.** Each use of a font constant becomes a description, in all three
  repositories. The 143 constants and their exports go. *Done:* a script
  (`/var/tmp/default-look/convert_font_uses.py`) replaced 721 uses in 198
  files: 156 in projectured-julia, 37 in omnet-julia and 5 in inet-julia. It
  took each description from `Font.jl`, removed the names from the `import`,
  `using` and `export` lists, and added `StyleFont` to an explicit import list
  that needed it. Plan files keep the old names, because they record history.
  Checks in projectured-julia: every changed file parses; `Pkg.precompile` of
  `environment/all` builds every package; each module of a changed file
  resolves `StyleFont` (a precompile does not prove that for a function body);
  the image check finds 315 of 315 outputs equal; `test_printers()` passes.

### Part R: base fonts and text roles

- [x] **R1.** `@theme` computes a role field from the base font and the role.
  Tests with `test_theme`. *Done:* `FontRole(; base, family, weight, italic,
  relative_size)` and `TextRole(color; …)` in `source/platform/style/FontRole.jl`.
  A role takes the family, the weight and the slant of its base where it sets
  none, and the size of its base times `relative_size`; `apply_font_role(role,
  base)` gives the font and `get_role_base(role, theme)` the base. The macro
  passes the theme to `scale_theme_value(value, theme, appearance)`, so the
  scaled value of a role reads its base font and follows a change of it. A role
  field can still hold an absolute `StyleFont` or `StyleText`, which scales as
  before. Save and load write a role as a table with `base` and no `size`, and
  read either form. The appearance tab shows a role as "− weight +", a checkbox
  for italic and its size in percent of its base.
- [x] **R2.** Each of the 29 themes gets its base fonts and its roles. The roles
  give the old sizes, for example a Markdown heading of 36 px is 1.8 times
  20 px. *Done:* a script (`/var/tmp/default-look/convert_theme_roles.py`)
  converted 27 themes; `GraphTheme` has no font, and `Theme.jl` holds only the
  docstring example. Per theme, the family with the most fields gets a base:
  `font`, and `code_font` when a theme has both a proportional and a monospace
  family. A family with one field follows the base of its kind with a family
  override, such as the DejaVu Sans Mono markers of Markdown. An existing plain
  font field of the base family and size is the base: `SyntaxTheme.font`,
  `FormulaTheme.plain_font`, `ChartTheme.axis_font`. 23 base fields are new.
  The scaled value of each of the 366 font and text fields, at the font scale
  1 and 1.5, is the same before and after; the image check finds 315 of 315
  outputs equal; the theme tests of the 19 domains and slices pass.

### Part T: every style value in a theme

- [x] **T1.** Classify each fixed value of section 2.6 as a style, content or
  not a style. Record the lists in section 10. The owner reviews the lists of
  content and of "not a style". *In progress (2026-10-02):* an agent wrote the
  lists `/var/tmp/default-look/t1-projectured.md` (320 style, 155 content
  entries for 521 values, 433 not a style), `t1-omnet.md` (507, 56, 95) and
  `t1-inet.md` (6, 23, 14). Corrections before the review: the size of an
  output or a window (`write_image`, the PDF, the video, the recording, the
  default `Display`, `EditorDisplay`, the file dialog) is not a style. The
  agent proposed 17 new themes in projectured-julia and 24 in omnet-julia;
  a value of window chrome that one field of `WidgetTheme` already says, such
  as the padding of a pane or the gap of a tooltip, takes that field instead.
  *Done (2026-10-04):* the owner accepted the lists ("fine").
- [x] **T2.** projectured-julia: each style value moves into a theme. A domain
  with no theme gets one. Batches, each checked by the image check and the
  suites of the slices it touches. *Done (2026-10-04):* the owner closed the
  step. Later decisions answer its open questions: the documents of the chrome
  builders (D18, D21, D23), the ring and the fault mark (D19), the colors of
  the code pieces (D28), the spacing of a cell (D27), the swatch (D30) and the
  panel of the gesture log (D31). Left as they are: the defaults of two
  geometry helpers of the charts, which their callers pass.
  - Domain syntax (`cd52731ea`): `SqlTheme.punctuation_text`, the brackets of
    a Julia operation take `JuliaTheme.punctuation_text`.
    `TextString(content, font)` is a separator that draws no ink.
  - Overlays: `FaultTheme` and `GestureLogTheme` get `panel_background`,
    `panel_margin`, `panel_padding`, `panel_radius` and a preset "Panel" with
    the light text; `FAULT_LOG_BACKGROUND` and `GESTURE_LOG_BACKGROUND` go.
  - Text and syntax: `SyntaxTheme.object_delimiter_text` and `fault_text`;
    `TextTheme.plain_text`, `line_number_text`, `match_highlight`,
    `inverted_background`, `inverted_foreground` and `fault_text`;
    `UNSTYLED_TEXT_FONT` is the one font of a text that names none (content,
    D11). `NaturalToGraphics(; font = nothing)` follows the text theme, as its
    docstring says. `PALETTE_PADDING` goes: `GestureHelpTheme.palette_padding`
    holds it.
  - Agents did three batches, which I reviewed: `DataFrameTheme` (7 fields;
    the scroll bar beside the table reads `WidgetTheme.scroll_bar_thickness`),
    `ConversationTheme` (25 fields, reached from the appearance in
    `ConversationRows.jl`), and 29 new fields of `ChartTheme` and
    `SequenceChartTheme` (radii, line widths, dashes, opacities). Left: the
    default color cycle of a chart series, a default of the chart document;
    the defaults of two geometry helpers that their callers pass.
  - Check of these batches: the images are 315 of 315 equal; the suites of
    the platform, the data frames, the charts, the sequence charts, the
    command palette and the gesture log pass, and `test_printers()`. Two tests
    needed a change: the appearance tab now shows three preset choices.
  - Not a style, left: the widths of the columns of the logs, which count
    characters; the window size of the gesture help; the parameters of the
    Adaptagrams and Fruchterman–Reingold layouts.
  - Open questions for the owner: the documents that the chrome builders make
    (window chrome, assistant, object card, pane border); the selection ring
    and the fault mark of the graphics and layout slices, below every theme;
    the colors of `compute_code_pieces`. The owner did not understand the
    question about the colors of `compute_code_pieces` (2026-10-02). It stayed
    open until D28. *Done (2026-10-04):* `compute_code_pieces(language, text,
    appearance)` takes the appearance of the field, which the printer of
    `WidgetText` holds; the Julia method reads the text role of each token
    from the `JuliaTheme` of that appearance, unscaled because a color does
    not scale, or from the default theme. `JuliaTheme` gets `comment_text`.
    `true`, `false` and `nothing` take `keyword_text`, as the theme says, and
    `missing` is a name, which keeps the color of the field. A symbol is
    magenta, as in the code view. The style guard exempts no file now. The
    Julia piece test, the text field test and `test_dataframes` pass.
  - Open, found in the rebase onto main (2026-10-04): the panel of the newest
    gestures. `GestureLogTheme.panel_background` is a translucent black, and
    the panel that the `gesture_log` wrapper puts over a window is an opaque
    gray (`_GESTURE_LOG_PANEL_BACKGROUND`), so that the text under the panel
    does not show through. The line carries a marker until the owner chooses
    one color for the theme. *Done (2026-10-04, D31):* the overlay stays
    translucent; the wrapper takes `panel_background` of the theme, and a
    `background` in its options still replaces it.
  - Open, found after the landing (2026-10-04): a value in a cell of a data
    frame stands about 3 px below the number of its row, and 7 checks of
    `test_dataframes` fail (`DataFrameViewTest.jl` lines 134, 141, 176 and
    177, `DataFrameFilterTest.jl` line 83). A cell holds the primitive
    document of its value, which the text stage of the natural view draws at
    the code line spacing of the text theme (1.35); the row number is a widget
    label at single spacing. A probe with single spacing in the text theme
    puts both at the same height. D27 decides how the table gives its cells
    single spacing. *Done:* `WidgetTableToGraphicsCanvas` puts
    `:line_spacing => SingleSpacing()` in the context of its parts, and
    `TextToGraphics` prints with a copy of itself at that spacing
    (`_with_line_spacing`, which keeps the theme cells). `test_dataframes`
    passes, 555 of 555, and the table tests of the platform pass.
  - The graphics theme (D19): `GraphicsTheme` in the graphics slice holds
    `font`, `fault_text`, `selection_ring` and `selection_ring_width`.
    `SELECTION_RING_COLOR` and `WidgetTheme.selection_ring` go.
    `make_selection_ring_stroke(theme)` gives the stroke of the ring: a theme
    cell for a scaled theme, the plain default stroke for `nothing`.
    `LayoutToGraphics(; theme)` takes the theme in place of the keyword
    `selection_ring_stroke`. The widgets read the graphics theme of the
    appearance of their own theme (`_get_graphics_theme`), for the ring and
    for the band of a selected row. `NaturalToGraphics` and the tabs wrapper
    pass the scaled theme of their appearance; the appearance tab shows it in
    the group "Editor". `FaultToGraphics` takes its defaults from the theme,
    as `FaultToText` and `FaultToSyntax` do. omnet-julia: the qtenv widget
    theme names no ring, and the select-and-paste test reads the default.
    The radius of the ring is the field `selection_ring_radius` (3), and the
    gap of a collection is `collection_gap` (8); the guard of T5 found both.
    Check: the images are 315 of 315 equal. The platform suite passes after
    one change of `PLATFORM_SLICE_EDGES`: the appearance slice may use the
    graphics slice, because its tab names `GraphicsTheme`. The conversation
    transcript test passes. In omnet-julia the ring test of
    `test_select_and_paste` passes; 9 other assertions of it fail, because
    the window content is now a `SettingsDocument`, which the test does not
    expect yet. D19 does not touch that.
  - The padding of a kind (D18), the window chrome: `WidgetTheme` gets
    `menu_item_padding` (4, 4, 12, 12), `menu_name_padding` (4, 4, 6, 6),
    `menu_bar_padding` (2), `toolbar_padding` (4), `toolbar_item_padding` (4)
    and `status_bar_padding` (4, 4, 8, 8), the values that the window chrome
    set. The printers of these kinds take them as defaults, and the window
    chrome sets no padding. A menu item that opens a menu is the name of a menu
    on a bar, the variant `submenu`; any other item is a command. No menu
    opens a menu from inside a dropdown, so the rule reads only the item.
    Check: 4 examples change (`widget`, `widget_menu`, `widget_shell`,
    `widget_toolbar`), the other 101 are equal. Three tests pressed fixed
    points on menus with no padding; they now press the middle of each row.
  - The rest of D18, by D20: `WidgetTheme.tabbed_pane_padding` (8) is the
    default space around the strip and the page of a tabbed pane; the pane
    tree sets no border (the 8 was a `border` with no color). The assistant
    and the appearance tab set no padding on their scroll panes, whose kind
    has none, so in a pane they sit 8 from the edge as every tab does. The two
    omnet forms set no border and no padding on their text boxes, which take
    the look of every text box. Check: 6 examples change (the 4 above,
    `assistant`, `widget_tabbed_pane`), the other 99 are equal; the window
    with the pane tree draws as before. The platform suite and the omnet form
    tests pass.
  - Seen in the images, for step V2: the tab strip is a pill inside the band
    of the pane, where a desktop tool puts the strip at the edge of the pane.
  - The ring, the ellipsis and the assistant: `GraphicsTheme` gets
    `selection_ring_radius` (3). A layout and a widget container hold all the
    values of the graphics theme (`graphics_style`, from
    `make_theme_values_field`), and `make_selection_ring(bounds, style)` takes
    the color, the width and the radius from them; `make_selection_ring_stroke`
    goes. `SyntaxTheme.ellipsis_text` is the style of the ellipsis of a folded
    node, which the compound projection holds as `ellipsis_style`; the glyph is
    one constant that the printer and the offset count share.
    `ConversationTheme` gets `card_gap` (6) and `composer_min_height` (200),
    which the two assistant views take. Check: the images are equal to the
    batch before; the platform suite, the assistant tests and the omnet
    precompile pass. A run of the platform suite in `unshare -rn` fails one file
    system test, because the process is root there and reads a folder of mode
    000; outside the namespace it passes.
  - Open: the color swatch of the appearance tab is a label with fixed
    paddings, because no widget kind draws a square of a given size.
    *Done (2026-10-04, D30):* `WidgetSwatch(color; size = nothing)` is a
    widget kind that takes no input. Its color fills a square inside a border
    of the theme, with `radius_small`. Its side is `size`, or the new
    `WidgetTheme.swatch_size` (16, the size of a checkbox). The appearance tab
    shows it beside the text of a color. The catalog has an example and an
    atom of it. Check: the new `test_widget_swatch` and the appearance tab
    test pass. `test_example(widget_swatch_example)` fails one navigation
    check, "a state exists", which the skeleton example fails the same way,
    because a widget with no input has no state to reach.
  - D22, a label of its own: `WidgetCheckbox` and `WidgetSwitch` have a field
    `label`, drawn after the mark at `label_gap`, and a press on it flips the
    value. The value list of a data frame, the two options of the evaluator
    and the italic boxes of the appearance tab use it; the options stand
    `ConversationTheme.option_gap` (12) apart. A form keeps its labels in a
    column of their own, so its boxes carry none.
  - D21, the theme of the caller: the value list takes the widget and data
    frame themes of the editor's appearance (`find_editor_appearance`), for
    the gap of its rows and `DataFrameTheme.value_list_size` and
    `value_list_window_size`. The pager, filter and column chooser bars and the
    input dialog take `theme` (a scaled widget theme or `nothing`) for their
    `item_gap`; their buttons, and those of the message box and of the file
    dialog, are as large as their labels. omnet-julia calls the bars with no
    theme yet, which step T3 changes with the themes of its page views.
  - Check: the images change only in the `widget` example (the labelled
    checkbox and switch); the platform, data frame, evaluator and application
    tests pass, and omnet-julia precompiles.
  - Seen, for the owner: the column chooser shows its state as "[x]" and
    "[ ]" text on buttons, where a labelled checkbox is the widget for it.
  - The forms: `WidgetTheme` gets `form_column_gap` (12) and `form_row_gap`
    (8). The object form (`ObjectToWidget`) and the settings tab take them;
    they had 12 and 6, and 12 and 12. The settings tab puts `section_gap`
    between its cards and `label_gap` between its buttons. The object form and
    a field of an object (`ObjectFieldToWidget`) take a `theme` and write
    their labels and values in the widget body text, the interface font, as a
    desktop form does; the examples that pass their own style keep it. A card
    of the object form sets no width (it had 480).
  - Open: a card in a form now takes the width of its content, so two cards in
    one form can differ in width. A control column with the policy `Fill`
    makes them fill the pane, but with no width offered it collapses to
    nothing (measured: a form 114 pixels wide), and a form is printed with no
    width in the image examples and inside a card of a page. The correct fix is
    a column policy that fills an offered width and keeps the content width
    when no width is offered.
  - Check: 4 examples change (`object_to_widget`, `nested_object_to_widget`,
    `chart_inspector`, `sequencechart_inspector`); the platform and chart
    suites pass, and omnet-julia precompiles. The platform suite counts 16
    fewer tests than the run before, most likely the example walker on the
    changed object examples; I did not prove it.
  - The windows and the collection: `TooltipTheme` (new, in the tooltip
    slice) holds `offset`, `part_gap`, `minimum_size` and `maximum_size` of the
    tooltip window; `WidgetTheme.context_menu_maximum_size` and `item_gap` give
    the context menu window its size and its gap below a part. The two
    wrappers read `parts.arguments[:appearance]`. `GraphicsTheme.collection_gap`
    (8) is the gap of `CellVectorToVerticalLayout`. Two new edges of the slice
    table: tooltip uses style, appearance uses tooltip. Check: the images are
    equal; the platform suite, the tooltip window test and the application
    test pass, and omnet-julia precompiles.
  - D23, a filling column with no offer: the grid gives a weighted column or
    row (`Fill`, `Relative`) on an axis that it was offered no extent on the
    extent of its cells (`_gl_unoffered_policy`), as a stack already does for
    a weighted child; no new policy. The object form gives its control column
    `Fill`, so its cards fill a pane and keep their width where nothing is
    offered (a test form: 448 pixels wide with no offer, where it collapsed
    to 114).
  - D24: the column chooser is a row of labelled checkboxes; a press runs
    `choose` through the gestures of the box. New test `test_column_chooser`.
  - Check: the images are equal (the image check offers each example a
    width); the platform, data frame, chart and sequence chart suites and the
    application test pass, and omnet-julia precompiles. The example walker has
    80 fewer tests, measured per example against the commit before:
    `object_field_form` 1968 to 1918 and `widget` 10212 to 10182. Both hold a
    `FormLayout` with a `Fill` field column, which the walker prints with no
    offer: the column collapsed to 0 and the grid wrapped each field in a
    clipping viewport, 10 checks each (5 and 3 fields). Now the fields keep
    their width and need no wrapper.
- [x] **T3.** omnet-julia: the themes of the NED, INI, test file, result and
  workbench views, and the values move into them. *In progress:* omnet-julia
  `7df48184` adds `NedTheme`, `IniTheme`, `TestFileTheme`, `ResultTheme` and
  `SimulationTheme` for the legacy views; the NED, INI and result domains take
  them from the appearance. The theme modules need `using ..CellModule`,
  `..DocumentModule` and `..ReferenceModule`, because `@theme` declares a
  document. Images of 8 legacy examples at the density 1 and 2: 14 of 16 equal
  to the base; the simulation cards differ (section 10, step T3). The legacy
  tests pass, except two failures that the base has too. The presentation
  views (workbench, module, page, execution, parameter, capture, telemetry and
  the result charts), after V2 by the owner's choice: the pilot is the
  workflow (omnet-julia `1cc1cc42`): `SimulationWorkflowToWidget` takes a
  `theme`, and every card builder a keyword `style` with the values of the
  widget theme; the gaps map by meaning (`label_gap`, `form_row_gap`,
  `item_gap`, `section_gap`) and a button sets no height. The other views follow
  the same pattern, by a helper agent whose work I reviewed (omnet-julia
  `62e74da0`, 38 files). Facts: the legacy themes (NED, INI, test file,
  result, simulation) live in packages that `OmnetPresentation` does not
  depend on, so its views take `WidgetTheme`, `TextTheme`, `ChartTheme` and
  `MessageLogTheme`. The page passes its theme to its panes by the printer
  context property `:widget_theme`, the idiom of `:md_style`; the views of the
  view registry (`register_view_projection!`) have no appearance in reach and
  take the default values. `make_simulation_control_button` sets no height.
  The log view first took `ring` for a warning; `MessageLogTheme` got a role
  for each kind of level (projectured `6d5a5be05`), which the editor's log
  uses too. A fault from step R2: the demo navigator read `font_small` of an
  unscaled theme, a role; it takes the scaled theme of its window. Check: the
  presentation tests of omnet fail exactly as on the base of the branch (the
  same functions, messages and counts; the failures come from
  `Projectured` not defined, a timer, a stale test of a model, an allocation
  bound and the warm dashboards); the projectured images are equal, and the
  platform suite passes. `OmnetCampaignUiTest` is not in the scratch
  environment, so the campaign window is checked by its precompile only.
- [x] **T4.** inet-julia: the theme of the packet diagram. *Done:* inet-julia
  `887a204`: `PacketDiagramTheme` with the font and four colors;
  `GUTTER_WIDTH` counts characters and stays. The packet diagram tests pass.
- [x] **T5.** The guard of section 3.5 in each repository. *Done:*
  projectured-julia `f10303c93` (`test/suite/style.jl`, `test_style()`),
  omnet-julia `c33270de` (`test/style.jl`) and inet-julia `ee71036`
  (`test/suite/style.jl`). Each guard passes, and each runs on its own with no
  environment. The values that the guard found in omnet-julia now come from a
  theme or carry a marker; section 10 lists them. The omnet build passes, and
  the tests of the changed views pass, except two checks of
  `test_result_chart` that fail the same way on the base of the branch.

### Part V: the new defaults

- [x] **V1.** Images of a fixed set of views at the density 1 and 2: the IDE
  window with the explorer, a JSON document, Julia code, a Markdown document,
  the settings tab, the appearance tab and a chart, and the omnet workbench with
  a NED file. Each view in three looks: now, the look of the owner (0.8 and
  0.67), and the proposal of section 3.6 with the candidates for the code font.
  The images go on one page, and the owner chooses. *In progress (2026-10-02):*
  the page https://claude.ai/artifact/XEAB4xRHmdT1XLYEMDfVVq shows the JSON,
  Julia and Markdown views of the application window
  (`make_application_window`, 1440×900) and the appearance tab, at the density
  1, in four looks: now, the look of the owner, and the proposal with Ubuntu
  Mono 14 or DejaVu Sans Mono 14 as the code font. The proposal sets the base
  fonts through an `Appearance`, so it needs no change of code. Not yet shown:
  the line spacing of D9, which needs step V2, the density 2, and the omnet
  workbench. The script is `/var/tmp/default-look/v1/looks.jl`. *Done:* the
  owner chose the values from this page, and step V2 put them in.
- [x] **V2.** The chosen values go into every theme, with the line spacing of
  section 3.6. *Done (2026-10-03), before T3 by the owner's choice:*
  - Fonts: the rule of step V1 sets 41 base fonts in 35 theme files of the
    three repos: `WidgetTheme` 13, the chart axis fonts 12, a base font of 16
    or less (the tool panes) 13, every other one 14 (code, documents, the
    inspector, the conversation, the gesture help, the omnet legacy views 24
    to 14, the packet diagram). The presets of `WidgetTheme` default to Ubuntu
    13. `UNSTYLED_TEXT_FONT` is Ubuntu Mono 14. Roles follow their base.
  - `WidgetTheme`: the spacing table of section 3.6. The fields added after
    the table (the menus, the bars, the tabbed pane, the forms, the context
    menu) keep their values, which fit a line of 13 px.
  - The other themes: their spacings (2 to 16 px), radii, line widths and
    control sizes were reviewed and kept; the chart tick spacings (70, 100)
    set the density of the ticks and are no gaps.
  - The line spacing (D9, D25): `TextTheme.code_line_spacing` is
    `MultipleSpacing(1.35)` and `prose_line_spacing` is `MultipleSpacing(1.3)`.
    Measured natural heights: Ubuntu Mono 14 is 14.0 (ascent 11.62, descent
    2.38, no gap), so code lines are 1.35 × 14 = 19 px; Ubuntu 14 is 16.09, so
    prose lines are 1.3 × 16.09 = 21 px, 1.5 × 14. The code chain of the
    syntax fabric and the Julia domain pass the code spacing; the prose chain
    (Markdown headings, paragraphs, quotes and lists) and the text documents
    of the natural view pass the prose spacing; the widgets, the overlays and
    the inspector keep single spacing. `TextToGraphics` takes a spacing or a
    theme cell. The appearance file saves a spacing as a table of one key
    (`single`, `multiple`, `exact`, `at_least`), and the appearance tab shows a
    multiple as a spin box in percent.
  - The baseline alignment (D26), the design: `find_first_baseline(iomap)` in
    the graphics slice answers the baseline of the first line of text that an
    output draws, in pixels from its top, or `nothing`. A wrapper answers what
    it wraps: a chain its last stage, a barrier its content
    (`get_content_iomap`). A `ChildrenIoMap`, the IoMap of every layout,
    answers its first child that has one, offset by the place of that child.
    The text projection keeps the baseline of its first line in its IoMap; a
    label computes its own from its content box and the line box of its
    text. `HorizontalLayout` takes `vertical_align = :baseline`: the row
    baseline is the lowest baseline of its children, each child stands so its
    baseline meets it, and a child with no baseline stands on its bottom edge,
    as in CSS. The evaluator puts its prompt rows on the baseline.
- [x] **V3.** The tests that check a pixel size follow, for example the line box
  of 23 px for Ubuntu 20. The count of broken tests does not change.
  *Done (2026-10-03).* The line spacing changed one more test, the prompt of the
  evaluator, which the baseline alignment of D26 fixes (`find_first_baseline`,
  new test `test_baseline_alignment`). It also showed a fault of the scroll
  pane: the room of the wheel came from the drawn elements, measured with the
  default measure, while the pane drew with the declared extent, so the first
  turn off the end jumped 28 px for 24. The room now takes the extent that the
  pane draws with. For the fonts and the widget spacing: a helper agent updated 37 files of the platform and domain suites
  (`ec62ae78b`) and 6 files of the integration suite (`043e13c86`), and the 4
  legacy theme tests of omnet-julia (`1e89d27d`); I reviewed the changes. Three
  of its changes weakened a check, and I changed the fixture instead: a table
  of 20 rows so the wheel moves, a settings window 300 high so the tab
  scrolls, the caret test on `UNSTYLED_TEXT_FONT`. A finding in the source:
  the warm-up of a build pressed a fixed point, which with the old sizes hit
  the new-tab button of the navigator, and its Ctrl+T never worked, because
  the warm-up did not apply what a command posts. The warm-up now presses the
  row of `b.md` by its drawn name and drains the inbox after each operation
  (`7b6e9486a`). Check: the platform and the 19 domain suites pass; the
  integration suite fails only where main fails (catalog coverage, table cell
  editing, the history sweep of the two inspectors) and in the web and MCP
  tests, which need a loopback network that `unshare -rn` has not, and pass
  outside it; 5 `@test_broken` round trips pass, where main has 3.
- [x] **V4.** The owner looks at the live editor at 100% on the screen of
  section 2.1. *Done (2026-10-04):* "looks good".

### Part G: the guides

- [x] **G1.** The documents of the style and widget slices in
  `documentation/package/`, the new-domain guide (a domain declares a theme and
  writes no font or color in a projection), and the guard in the testing guide.
  *Done:* ten documents. The widget, layout, graphics, appearance, text and
  style documents describe the new fields and rules. The testing guide has a
  section on the static guards and the style guard. The tutorial of the
  new-domain guide gives the domain a theme from its first projection. The
  worked examples in `macros.md` and `rst.md` follow the code. An example that
  passes an explicit font to an API stays as it is. The documentation guard
  passes.

## 7. Checks

### 7.1 No pixel changes in Parts F, R and T

Write an image of each example offscreen, at the scale 1 and 2, on `main` and on
the branch. Hash the files and compare the two lists. A difference is a fault of
the step. The same check runs for omnet-julia and inet-julia against their
`main`.

### 7.2 Tests

Each step runs the narrowest tests that cover it: `test_theme`,
`test_font_metrics`, `test_font_fallback`, `test_appearance_file`,
`test_appearance_tab`, the widget tests, and the layering guard of each package
that a step touches. Step F5 and Part V also run `test_printers()`. omnet-julia
runs `Pkg.precompile` and the tests of each package that a step touches.

## 8. Risks

- Step F2 changes a type that every package uses. The three repositories land
  together, and every package precompiles again.
- A branch from before this work conflicts in each theme file and in each file
  that names a font constant.
- The measure caches by font. A wrong key gives wrong widths and no error.
  Section 7.1 finds it.
- Ubuntu Mono 14 can look smaller than the 14 px of VS Code. Step V1 decides.
- `FixedMeasure` tables in the tests are keyed by font constants. Step F5 changes
  them.

## 9. Not in this plan

- System fonts in the registry: fontconfig, DirectWrite, Core Text.
- A text size that follows the settings of the desktop.
- A dark theme that follows the operating system.
- A text without a font that takes the font of the theme (D11).
- A field of Julia code that draws through the Julia domain, in place of the
  tokens of `compute_code_pieces` (D28).
- The appearance of the editor for the views of the view registry of
  omnet-julia (D29).

## 10. Findings during the work

### Step F1

- `Inconsolata.otf` is weight 500, not 400. A font that asks for Inconsolata at
  400 gets it by the CSS rule, so the constant `font_inconsolata_regular_18`
  keeps its file.
- `lucide.ttf` names its family `lucide` in lower case. The table names it
  `Lucide`, and a family matches with no regard to case, as in CSS.
- `Ubuntu-C.ttf` declares the family `Ubuntu Condensed`, so it is a family of
  its own.
- The DejaVu oblique faces set the ITALIC bit of `fsSelection`, not the OBLIQUE
  bit.
- A local that holds a face or `nothing` boxes the face at each assignment: the
  first lookup allocated 96 bytes. The lookup keeps the index of the best face.
  Its result is still `FontFace` or `nothing`, so a caller that keeps the whole
  face boxes it (32 bytes). A caller that reads a field allocates nothing. So
  step F2 keys its caches by `face.file` and reads the path only when a cache
  misses: `font_file` calls `isfile`, a system call.

### Step F2

- A `@document` struct gets only a positional constructor that takes every
  field, unless a field has a default. So `StyleFont` has one outer
  constructor with the keywords `weight` and `italic`, which converts the
  weight to `Int16`.
- `_rank_font_weight` returned `Int16` in some branches and `Int` in others
  when the weight was an `Int16`, so the rank was a union and the lookup
  allocated 384 bytes. It now takes two `Int`.
- An `Int16` weight prints as a number. A `UInt16` prints in hexadecimal.
- The image check is `/var/tmp/default-look/image_check.jl`, outside the
  repository: `write_example_image` at the density 1 and 2, and
  `write_example_pdf`, for each of the 105 examples of `ProjecturedExample`. The
  PDF files are the same byte for byte from one run to the next, so a hash
  compares them too.

### Step F5

- The recorded precompile statements of `ProjecturedREPL`
  (`asset/precompile/PrecompileStatements.jl`) skip 7,272 of 10,857
  statements. Only 287 statements name `StyleFont`, so at least 6,985 were
  stale before this work. The recording needs a new run, best after Part V.
  The owner chose not to record them again in this plan (2026-10-04).

### Step T2, the graphics theme

- `NaturalToGraphics` puts the rows of `LayoutToGraphics()` before the rows of
  the widgets, and the first row that matches wins. So in the natural view
  every layout drew its ring with the constant, and the ring of the widget
  theme reached only the layouts of a bare `WidgetToGraphics`. Now both read
  the one graphics theme of the appearance.

### Step T3

- A caller that builds a widget theme with a base font other than the
  default, such as `WidgetToGraphics(StyleFont("Ubuntu", 24))`, now gets
  `font_small` and `font_bold` that follow that base: 22 px and Ubuntu Bold
  24, where they were Ubuntu 18 and Ubuntu Bold 20. This is the role model of
  D8. It shows in the simulation cards of omnet-julia, whose fixture passes
  Ubuntu 24; the projectured-julia examples pass no such font.

### Step T5

- The guard reads the values inside a call, not the name of the call. A
  `StyleColor(` with a number fails, and a `StyleColor(` of a variable is a
  conversion and passes. A `StyleText(` fails only when a font description, a
  number color or a palette color is in it, so the guard does not list
  `StyleText(` by name, as section 3.5 did.
- A marker on a line of its own covers the lines below it, up to the next
  blank line. A table of colors that a document names, such as the colors that
  a model of omnet-julia writes by name, needs one marker and not one for each
  line.
- omnet-julia and inet-julia have no palette file. Their guard reads the names
  of the palette colors from the `import` and `using` statements of each file.
- One file of projectured-julia is exempt by name:
  `source/domain/julia/JuliaCodePieces.jl`, whose colors of the pieces of code
  wait for a decision of the owner.
- The guard found these values in omnet-julia, which now come from a theme:
  - the colors of the states of a result set chart and of the vector plot take
    the color cycle of the plot domain, `default_color_cycle()`;
  - the vector plot takes the axis font and the title font of `ChartTheme`, so
    it draws in Ubuntu and not in DejaVu Sans Mono;
  - the held disk of the Hanoi example takes the `ring` color of the widget
    theme;
  - the icon of the status line takes the size of the text of the widget theme,
    13 px, where it was 20 px. The theme has no size for an icon in a line of
    text.
