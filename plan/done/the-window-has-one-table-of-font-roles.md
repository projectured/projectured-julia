# The window has one table of font roles

> **Status:** done on 2026-11-07. Written on 2026-11-05 at the owner's request.
> The owner decided every point of section 2. Steps 1 to 7 are in
> projectured-julia and step 8 is in omnet-julia; the record of the compiled
> calls of step 6 is deferred to after the plan.
> The facts are in [how-the-window-uses-fonts-today.md](how-the-window-uses-fonts-today.md).
> The page with the 19 parts of the window before and after is the artifact
> "Editor Type Study", https://claude.ai/artifact/T8tYi1TEgC5T249MrJJRuk.

## 1. The request

The owner asked on 2026-11-05:

> I feel like the font sizes are too often very similar and we should also use
> different fonts and/or font sizes for titles, emphasis and or less important
> parts. [...] Let's plan something useful to make the UI visually more
> appealing and easier to decode.

The study found the cause. Nearly nine of ten text fields of the themes are 13 or
14 px. A title, a label and the text under it differ only by weight or color.
The themes use six families and ten sizes, and no rule says which text gets
which. Each theme writes its own base font and its own ratios, so the values
drift apart, and a ratio rounds twice.

## 2. The decisions

Each decision has the answer of the owner, on 2026-11-05.

**D1. A person must see six differences at a glance.** The owner agreed with the
list:

1. the window frame against the content;
2. a title against what it heads;
3. a label against its value;
4. main text against quiet text;
5. code against normal text;
6. emphasis inside text.

**D2. The roles.** After the owner saw the 19 examples, the owner said that the
changes "mostly look good" and picked the four open values in the bar of the
page: widget and tool text 13 px, title weight medium, label medium, and section
heading 12 bold. The roles:

| Role | Size | Weight | Family | Color in the usual case | For |
|---|---|---|---|---|---|
| `page_title` | 20 | 500 | sans | text | help page, about page, outline title |
| `title` | 16 | 500 | sans | text | pane, card, dialog |
| `text` | 13 | 400 | sans | text | the frame, controls, rows, table cells, tool panels |
| `label` | 13 | 500 | sans | text | form label, field name, setting name |
| `strong_text` | 13 | 700 | sans | text or tone | a head inside a row: accordion item, alert title, tooltip title, turn label |
| `section` | 12 | 700 | sans | muted | a group heading inside a pane |
| `column` | 12 | 500 | sans | muted | a table header, an axis title |
| `quiet` | 12 | 400 | sans | muted | caption, description, hint, footer, status bar, time, count |
| `badge` | 12 | 500 | sans | tone | badge, chip, log level, key cap |
| `document_text` | 14 | 400 | sans | text | prose in a document, a message, a help text |
| `heading_1` … `heading_6` | 24, 20, 16, 14, 14, 14 | 700 | sans | heading; 5 and 6 muted | document headings |
| `code` | 13 | 400 | mono | syntax | code in a tool panel |
| `document_code` | 14 | 400 | mono | syntax | code in a document and in every code view |

The sizes are 12, 13, 14, 16, 20 and 24: six sizes in place of ten. The weights
are 400, 500 and 700. The families are Ubuntu (sans) and Ubuntu Mono (mono).
DejaVu Sans Mono and Noto Emoji stay as the fallback for missing glyphs, and
Lucide stays for icons. A code view keeps one size and one family. A placeholder
inside a field keeps the size of the field text.

**D3. Where the values live: one table, as for the colors (option A).** The
appearance holds one font theme. A font field of any theme names a role of that
table, as a color field names a role of the color theme with `ColorRole`. The
owner rejected option B, new numbers in each theme, because nothing in the code
would keep the themes on the rule.

**D4. The exceptions.** The owner asked whether a font field can hold a specific
font, as a color field can hold a fixed color. The answer, which the owner
accepted:

- a field that names a role can set its own weight and its own slant on top of
  the role, as `TextRole(:keyword; weight = 700)` does today;
- a field that needs another size or another family holds an exact `StyleFont`,
  which no role setting changes. Examples: the icons in Lucide, and the markers
  of Markdown and RST in DejaVu Sans Mono, which need its glyphs for arrows and
  rules;
- a role never changes its size. If it can, the steps become ad hoc again.

## 3. The design

### What a theme field holds

```julia
# now: a role follows a field of its own theme, by a ratio
font::StyleFont = StyleFont("DejaVu Sans Mono", 13)                    # MessageLogTheme
section_text::ThemeText = TextRole(:text_muted; relative_size = 0.8)  # ConversationTheme: 14 × 0.8 → 11

# after: a role names a role of the font theme of the appearance
font::ThemeFont = FontRole(:text)
section_text::ThemeText = TextRole(:text_muted; font_role = :quiet)
keyword_text::ThemeText = TextRole(:keyword; font_role = :document_code, weight = 700)
marker_text::ThemeText = StyleText(StyleFont("DejaVu Sans Mono", 14), ColorRole(:markup))  # the exception
```

- `FontRole(role; weight = nothing, italic = nothing)` names a field of the
  `FontTheme`. It has no `base`, no `family` and no `relative_size` any more.
- `TextRole(color; font_role = :text, weight = nothing, italic = nothing)` is a
  font role and a color, as it is now.
- `ThemeFont = Union{StyleFont, FontRole}` and `ThemeText = Union{StyleText, TextRole}`
  keep their meaning: an exact value or a role.

### The font theme

`FontTheme` is a `@theme struct` of the style slice, next to `ColorTheme`. It
holds two families, `sans_family = "Ubuntu"` and `mono_family = "Ubuntu Mono"`,
and one field for each role of D2. A role field holds a size, a weight, a slant
and the family that it uses, `:sans` or `:mono`. A change of a family moves every
role that uses it, as `color_accent` moves every color on the accent ramp. The
`Appearance` holds one `font_theme`. A font does not change with the color mode,
so there is one font theme, not one for each variant.

### How a role becomes a font

The scaled theme resolves a `FontRole` in one place: it takes the size, the
weight, the slant and the family from the font theme of the appearance, puts the
weight and the slant of the field on top, and then multiplies the size by the
font scale and rounds it once. A role follows a change of the font theme, as a
`ColorRole` follows a change of the color theme. An exact `StyleFont` takes only
the font scale, as now.

### Save and load

`appearance.toml` gets a table for the font theme, as it has one for each color
theme. A field that names a role is saved as the role and its weight and slant.
A font entry in the old form, with `base` and `relative_size`, does not load, and
the field keeps its default. This machine has no saved appearance file on
2026-11-05, so nothing is lost here.

## 4. The steps

Each step is one commit, or a few, on a branch in a worktree. Each step runs the
narrowest suites that cover it, and compares the counts with a baseline of clean
`main`. A test that asserts a font, a size or a position that this plan changes
gets the new value; the commit names each one.

- [x] **Step 1. The font theme and the font role.** Done on 2026-11-05, `aa348c026`;
  see section 5 for what the work found. In `source/platform/style/`:
  add `FontTheme` with the roles of D2; change `FontRole` and `TextRole` to name
  a role of the font theme; resolve and scale a role with one rounding; add
  `font_theme` to `Appearance`; save and load it. The old form of `FontRole` and
  `TextRole`, with `base` and `relative_size`, keeps working next to the new form
  until the end of step 5, so that each step builds and passes its tests. Tests: `ThemeTest.jl`, `ColorThemeTest.jl` as a
  model for a new `FontThemeTest.jl`, `test_font_face`, the save and load test of
  the appearance.
- [x] **Step 2. The appearance tab.** Done on 2026-11-05, `e708fd341` and `45cab5799`. A "Fonts" section with one row for each
  role: the family, the size, the weight and the slant. A field of a theme shows
  whether it names a role or holds an exact font, as a color field shows a role
  or a fixed color. Test: `AppearanceTabTest.jl`.
- [x] **Step 3. The widgets.** (Done: b91624435, 2eda752d3; facts in section 5.)
  `WidgetTheme`: `font` becomes `FontRole(:text)`;
  `font_bold` and `font_small` give way to the roles that each part takes. The
  parts and their roles, as on the page: a card, dialog and title pane title
  `title`; an accordion item, alert and tooltip title `strong_text`; a caption,
  description, footer, status bar and menu key hint `quiet`; a badge `badge`; a
  form label and a setting name `label`; the selected tab `text` at weight 500; a
  group heading of a settings page `section`. A table gets a style for its
  header row, `column`, which it does not have now. Tests: the widget suite of
  the platform, and `test_dataframes()`, because a change of the widget layout
  broke data frame edits before.
- [x] **Step 4. The tool panels.** (Done: 294834aeb, b3a7d3fef, 05cd9cf19,
  6ffa040ba, 03a01bd03; facts in section 5.) The themes of the tooltip, help, message log,
  faults, statistics, undo, gesture log, gesture map, inspector, outline,
  conversation, MCP log, explorer, terminal, reference, text, syntax, graphics,
  settings and task panes name roles. DejaVu Sans, DejaVu Sans Mono and Liberation
  Sans leave the themes. Prose, names and values that are not code leave the mono
  font: log messages, file names, key names, help text. `UNSTYLED_TEXT_FONT`
  (`text/TextDocument.jl:118`): first find how an unstyled text reaches the
  printer. If the printer can draw it with the `document_code` role of its theme,
  it does. If the font is a value in the document, it stays, and the plan records
  why. Tests: the suite of each panel that the step changes.
- [x] **Step 5. The domains and adapters.** (Done: 45a91bb99, ce6265373,
  065dfd6f1, eb851e0b0; facts in section 5.) The 16 domain themes with fonts name
  roles. Markdown, RST and Book headings take `heading_1` to `heading_6`; captions
  and other quiet text take `quiet`; code domains take `document_code`, with
  weight 700 where they are bold now; chart and sequence chart titles take
  `document_text` at weight 500 in the text color, axis titles `column`, ticks
  `quiet`. The math typesetter keeps its script sizes, 0.7 and 0.5 of the font of
  its role, because they are a rule of the typesetting. The markers in DejaVu Sans
  Mono become exact fonts (D4). The header labels of the pivot tables
  (`domain/pivot/PivotTableToWidget.jl`, `PivotPartTableToWidget.jl`) take the
  `column_font` and the muted color of the widget theme, as the data frame does.
  When no theme uses the old form any more, remove
  it: the `base`, `family` and `relative_size` of `FontRole`, `get_role_base` and
  the ratio of `apply_font_role`. Tests: `test_markdown()`, `test_rst()`,
  `test_book()`, `test_chart()`, `test_sequencechart()`, `test_math()` and one
  code domain, `test_json()`.
- [x] **Step 6. Real screens.** Draw the parts of the 19 examples of the page in
  the editor, on `main` and on the branch, with `write_image` and no window on
  the desktop, and put them side by side on the page. The owner looks at them
  before the branch goes further. Then compare every suite that steps 1 to 5
  touched with the baseline of `main`. Record the precompile calls again
  (`record_package_calls!`) for each package whose load warns that recorded calls
  no longer resolve, and check that the load of the branch gives no such warning.
  (Done on 2026-11-07, `1cbfd8252`, except the record of the compiled calls,
  which the owner deferred to after the plan; facts in section 5.)
- [x] **Step 7. The documentation.** Write `documentation/rule/type-rules.md`:
  the six differences, the roles, the exceptions, and how a new widget, panel or
  domain gets its fonts. Change `documentation/package/platform/style/style.md`
  (fonts, roles and the font theme), `appearance/appearance.md` (the font theme in
  the appearance and in the tab), `widget.md` (the roles of each part) and
  `new-domain-guide.md` (a domain theme names roles).
  (Done on 2026-11-06, `3bd645e14`; facts in section 5.)
- [ ] **Step 8. omnet-julia.** After the owner approves the landing of steps 1 to
  7 on `main` of projectured-julia: the NED, INI, test file and result themes name
  roles; the result card title takes `title`; the Qtenv preset
  (`WorkbenchRender.jl:107, 160`) names roles and keeps no literal font; campaign
  form values leave the code font. The execution status icon keeps its exact
  Lucide font. Tests: the presentation suite of omnet-julia, and
  `Pkg.precompile` of the omnet environment, because a change of a platform
  method breaks its precompile.
  (Done on 2026-11-06 on the omnet-julia branch `font-roles`, `1c76decd1` and
  `b8878b93a`, not landed; facts in section 5.)

## 5. Facts and decisions found in the work

- **2026-11-05, before step 1.** The themes call the old form of `FontRole` and
  `TextRole` in about 278 places. If step 1 replaced the form, no step from 1 to
  5 would build. So the new form `FontRole(:quiet)` comes next to the old one,
  a theme changes all its fields in one step, and step 5 removes the old form.
- **2026-11-05.** The owner accepted the names `FontTheme`, `FontRole(:quiet)`
  and the keyword `font_role`. A field of the font theme holds a `FontStep`: a
  family kind, `:sans` or `:mono`, a size, a weight and a slant. The two family
  fields of the font theme give the family of each kind, as `color_accent`
  gives the hue of the accent ramp.
- **2026-11-05, step 1.** `@theme` refers to `Appearance` and to
  `scale_theme_value` when it expands, so `FontTheme.jl` comes after
  `Appearance.jl` in the include order, as `ColorTheme.jl` does. So the field of
  the appearance is `font_theme::Theme = FontTheme()`, and `get_font_theme`
  asserts `::FontTheme`. `FontStep` is in `FontRole.jl`, before `Appearance.jl`,
  because the decoders of the appearance file need it. `appearance.toml` writes
  only the fields of the font theme that differ from the default, under
  `[FontTheme]`, as for the colour themes.
- **2026-11-05, step 1.** A change of a step or of a family of the font theme
  reaches every scaled theme: `resolve_font_role` reads `appearance.font_theme`
  in the computed cell of the scaled theme, as a colour role reads the colour
  theme. `test_font_theme()` checks it for a step and for `sans_family`.
- **2026-11-05, step 1, counts.** On the branch, with `environment/all`:
  `test_font_theme` 70 pass, `test_theme` 86, `test_font_face` 139,
  `test_appearance_file` 22, `test_appearance_tab` 138, `test_color_theme` 1431.
  On `main` the same counts, except `test_font_theme`, which `main` does not
  have, and `test_color_theme`, whose run on `main` did not get memory. No Fail,
  no Error and no Broken.
- **2026-11-05, step 2.** The font card stands second in "Editor", after the
  colour card, with the title "Font". The family stepper is a method of
  `_make_field_control` for a `String` value that acts only on `sans_family` and
  `mono_family` of the font theme; every other text field shows its text, as
  before. A role with a role name has its own control, `_make_font_theme_role_control`,
  with no size. Counts on the branch: `test_appearance_tab` 138 before, 156 after;
  `test_appearance_file` 22; `test_font_theme` 70.
- **2026-11-06, step 3.** The widget theme has `font = FontRole(:text)` and one
  field for each role that a part takes: `label_font`, `title_font`,
  `strong_font`, `quiet_font`, `badge_font`, `column_font`, `section_font` and
  `selected_tab_font = FontRole(:text; weight = 500)`. `font_bold` and
  `font_small` are gone. The tooltip title is in the tooltip theme, so step 4
  gives it `strong_text`.
- **2026-11-06, step 3.** `WidgetTable` takes the header widgets that its caller
  builds, so the table needs no style of its own for the header row. The maker of
  a header label gives it `column_font` and the muted color: the data frame view
  (`header_font`, `header_color`) and the roster. The pivot tables follow in step 5.
- **2026-11-06, step 3.** No widget draws a form label. The `label` role goes to
  the name of a setting (`SettingsToWidget`, field `name_text`) and to the name of
  a row of the appearance tab: a scale, a colour setting, a field of a theme
  (`_make_name_label`).
- **2026-11-06, step 3.** The strip measures every tab name in one font, but the
  selected tab draws its name at weight 500, which is wider. So a tab takes the
  width of its name in the wider of the two fonts: the medium name ends before its
  badges and its close button, and no tab moves when the selection does.
  `test_widget_tab_strip` checks it with the real faces.
- **2026-11-06, step 3, counts.** `test_dataframes` 608 before and after. The
  platform suite in one call passes the 9.3G cap, so it ran as its 242 parts in one
  process: no count moved, except `test_platform_examples` (203654 → 203763) and
  `test_widget_tab_strip` (29 → 33). The failures in `test_conversation` (75 fail,
  51 error), `test_pane_surgery`, `test_platform_layering`,
  `test_platform_slice_edges`, `test_work_plan` and `test_mcp_log_pane` are the
  same on `main` 4c8d27962. One assertion group of `AppearanceTabTest.jl` (lines
  196 to 208) reads the role of the `font` field now, not its size and family.
- **2026-11-06, found in step 3.** The load of the branch warns that recorded
  precompile calls no longer resolve: 1406 of 12310 in `ProjecturedPlatform`, 69
  in `ProjecturedChart`, 73 in `ProjecturedDataFrames`, 3 in
  `ProjecturedLanguageServer`. `main` gives no such warning. The calls name types
  and fields that the branch changes. Step 6 records them again, after the last
  theme change.
- **2026-11-06, open, found in step 3.** About 100 examples and tests build a
  widget projection with an exact font, mostly `WidgetToGraphics(StyleFont("Ubuntu", 20))`
  or `StyleFont("Ubuntu Mono", 20)`. That font now sets only the `font` field,
  so such a projection draws a control at 20 px, a card title at 16, the selected
  tab at 13 and a badge at 12. The owner decides what a passed font means.
- **2026-11-06, step 4.** The form of the exception of D4 in section 3,
  `StyleText(StyleFont(…), ColorRole(…))`, does not build: a `StyleText` holds a
  fixed colour. So a `TextRole` holds a `ThemeFont`, a font role or an exact font,
  as it holds a colour role or a fixed colour: `TextRole(:warning_text; font = StyleFont("Lucide", 13))`.
  The scaled theme scales the exact font once. The appearance file saves it with
  its colour role and loads it back; the appearance tab shows the controls of an
  exact font for it. The exact fonts of step 4: the marks of the tooltip (Lucide
  13), the role icons of the conversation (Lucide 14), and the type name of a help
  page (Ubuntu Mono 20 bold, because Ubuntu Mono has no medium face).
- **2026-11-06, step 4.** No code read the base `font` of 15 tool themes once
  their texts named roles, so it left the tooltip, undo, statistics, fault, log,
  gesture log, gesture map, help, MCP log, conversation, outline, explorer,
  terminal, text and graphics themes. The inspector (`code`), reference and
  syntax (`document_code`) themes keep it, and the conversation keeps
  `code_font` (`code`), because printers read them. No caller set a removed field.
- **2026-11-06, step 4.** Each colour stays as it was, except the headers of the
  statistics, of the gesture map and of the MCP log, which take `text_muted` as
  the roles `column` and `section` say. The outline row is 13 regular, and a
  section label of the outline keeps the case it was written in. The help theme
  has no field for the field names of a type, so nothing takes `code` there.
- **2026-11-06, step 4.** `UNSTYLED_TEXT_FONT` stays. A `TextString` made with no
  font stores that font in the document, and the printer draws each span with the
  font that the span holds. To draw it with a role, a font would have to reach the
  printer by a new channel, which this plan does not make.
- **2026-11-06, step 4.** More builders take an exact font, which the open
  question above also covers: `ReferenceInspectorToText(font)` (1 caller),
  `ReferenceToText(font)` (3), `ReferenceToHumanReadableText(font)` (2),
  `SelectionInspectorToText(font)` (0), `SyntaxCompoundToText(decoration_font)` (2),
  `ConversationComposerToWidget(code_font)` (4).
- **2026-11-06, step 4, counts.** Before → after on the branch: `test_font_theme`
  70 → 84, `test_appearance_tab` 156 → 159, `test_help` 97 → 96 (three
  assertions became two). The same counts: `test_theme` 86, `test_appearance_file`
  22, `test_settings` 107, `test_tool_themes` 113, `test_outline` 26,
  `test_help_themes` 81, `test_text_and_syntax_themes` 21, `test_tooltip` 57,
  `test_tooltip_note` 44, `test_undo` 130, `test_fault` 118, `test_filesystem` 142,
  `test_explorer` 313, `test_terminal` 53, `test_text_folding` 20,
  `test_text_gutter` 47, `test_builder_appearance` 7; `test_conversation` and
  `test_mcp_log_pane` keep the failures of `main`. Changed assertions:
  `ToolThemeTest.jl` compares each field with the size of the default theme, not
  with one base size; `AppearanceTabTest.jl` 273 to 330 checks the role controls
  and a text role with an exact font; `OutlineTest.jl` 14 and 15;
  `ConversationThemeTest.jl` (kind 13/500, section 12, error 12/700, prompt and
  `code_font` 13 mono); `HelpTreeTest.jl` 81 and `HelpPageTest.jl` 112 read
  `heading_text`. In the review: `test_json` 245 on `main` and on the branch,
  because a code domain draws through the text and syntax themes;
  `test_platform_examples` 203763 → 203772 with no failure.
- **2026-11-06, step 5.** Code text that is bold keeps weight 700 over
  `document_code`. The rendered markers of Markdown and RST are
  `TextRole(:markup; font = StyleFont("DejaVu Sans Mono", 14))`. The base fonts
  that no code read left the themes of json, julia, sql, xml, yaml, fsm, process,
  dbcatalog, markdown, rst, book and the `code_font` of math. Formula keeps
  `plain_font` (`document_code`), research keeps `font` (`text`), and math keeps
  `font` (`document_text`) and `slanted_font` (`document_text`, italic).
- **2026-11-06, step 5.** The math typesetter needs no change for its script
  sizes: `compute_math_metrics` (`domain/math/MathToGraphics.jl`) multiplies the
  size of the resolved font by 0.7 and 0.5, so they follow the role.
- **2026-11-06, step 5.** The chart had one `axis_font` for the axis titles, the
  ticks, the segment names, the readout and the placeholder. The axis title now
  has `axis_title_font` (`column`), and the rest keeps `axis_font` (`quiet`). The
  chart had one `text_color` for every text, so the title and the legend label
  got fields of their own, `title_color` and `legend_color` (text colour), and the
  sequence chart a `title_color`. The `title_color` of a chart's own style still
  colours every text of that chart. `test_chart` checks the font and the colour of
  the title and of an axis title.
- **2026-11-06, step 5.** Markdown and RST had one font for every heading past
  the third level. Each level from 1 to 6 now has its field and its role, and
  levels 5 and 6 draw in `minor_heading_color` and `minor_title_color` (muted), as
  D2 says.
- **2026-11-06, step 5.** The pivot tables take `header_font` and `header_color`
  from `column_font` and the muted colour, as the data frame does: the column and
  row labels, the measure header, `all`, the row numbers of a group, and the
  header of a part table. The names of the dimensions in the corner stay plain
  text.
- **2026-11-06, step 5.** The old form is gone: the `base`, `family` and
  `relative_size` of `FontRole` and `TextRole`, `get_role_base`,
  `apply_font_role`, their save and load, and their controls in the appearance
  tab. A saved entry with `base` or `relative_size` does not load, and the field
  keeps its default. omnet-julia still uses the old form, so it does not build
  against the branch until step 8.
- **2026-11-06, step 5.** More builders and documents take an exact font, which
  the open question above also covers: `MathToGraphics(; font, slanted)`,
  `MathConfig(; font, slanted)`, `FormulaEnvironmentToSyntaxNode(; font)`, and
  the fonts of `ChartStyle`, which a chart document holds as its own style.
- **2026-11-06, step 5, counts.** The same before and after: markdown 274, rst
  115, book 33, chart 429 (432 with the new title check), sequencechart 326, math
  215, json 245, julia 774 with 1 fail, sql 671, xml 86, yaml 64 with 2 broken,
  fsm 273, process 316, formula 309, dbcatalog 74, research 386, pivot 334 with 1
  fail and 1 error, dataframes 608, `test_appearance_file` 22,
  `test_appearance_tab` 159, `test_tool_themes` 113, `test_color_theme` 1431,
  `test_platform_examples` 203772. The failures of julia (`TooltipWindowTest:179`)
  and pivot (`PivotZoneEditTest:84`, `PivotModuleTest:21`) are on the tip before
  the step. `test_font_theme` 84 → 74 and `test_theme` 86 → 85: the tests of the
  old form left. Changed assertions: `MathToGraphicsTest.jl` 9 to 12 read the
  faces of the default theme; `PivotGroupViewTest.jl` 18, 40 and
  `PivotTotalsTest.jl` 34, 35 pass the projection to the helpers; `ThemeTest.jl`
  and `FontThemeTest.jl` test the new form only.
- **2026-11-06, step 6, the screens.** One script draws 17 parts on `main` and
  on the branch with the default appearance, through the application window and
  `write_window_picture`, and names no font
  (`scratchpad/screens/draw.jl` of the session). The page has them side by side,
  version 4. The parts of omnet-julia wait for step 8.
- **2026-11-06, step 6, faults that the screens showed.** The message log lined
  up its messages with spaces, which needs a monospaced level: the level is in
  `code` at 700, not `badge` (3bd5c31c6); the text of the editor has no column
  of a fixed width. The frame statistics drew its section titles in the style of
  its table headers: it has `section_text` (`section`) and `count_text`
  (`quiet`) (34cf3ce1d). The gesture map never drew a key in its own style: a
  row is two leaves now, the key in `label` and the accent colour (d770d5d59).
- **2026-11-06, open, found in step 6.** A card prints a title that is a
  document as a child, so a `WidgetLabel` title draws in its own style, 13
  regular, and only a string title takes `title`. Ten cards have a label title
  (appearance tab, settings tab, task, assistant work, embed card, find bar,
  object view); most are built as documents, with no theme at hand. The printer
  context carries no text style to a child. The owner decides.
- **2026-11-06, decided by the owner, step 6.** "The title could be a String, a
  PrimitiveString or a WidgetLabel, the two former can get the style from the
  WidgetCardToGraphicsCanvas projection, the title could still be selected." The
  design that follows from it:
  - a `String` title draws in the title style of the card, as before; a
    collapsible card folds with it too, and an Alt+press on it selects the field
    `title` of the card as a part, as a table selects a header;
  - a `PrimitiveString` title is a document: the card prints it through the
    dispatch and offers its title style in the printer context, with the
    property `:text_style`, as a text view offers `:line_spacing`; the printer of
    a `PrimitiveString` draws with that style when the context holds one. A caret,
    an edit and an Alt+press work through its own printer;
  - a `WidgetLabel` title keeps its own style;
  - the ten cards take a `String`, or a `PrimitiveString` where the title is
    live.
- **2026-11-06, step 6, card titles** (049dd1815, 40d8549ce). The card has an
  IO map of its own, `WidgetCardToGraphicsCanvasIoMap`: the fields of
  `WidgetChildrenIoMap` and `header = (height, title_box)`. The reader needs the
  height of the header and the box of a `String` title, and only the print knows
  them. The fold box takes the height of the header for every title. An
  Alt+press in the box of a `String` title answers the selection of `title`, and
  the band behind the text is a cell that reads
  `is_whole_selected_field(w.selection, "title")`, as the band of a `:row` card
  does. A `PrimitiveString` title prints with `:text_style` in its own context
  only. Nine cards take a `String`; no card title is live. The heading of a task
  group keeps its `WidgetLabel`, because the heading is a row of a label, a badge
  and a state, and `:text_style` reaches only a title that is the
  `PrimitiveString` itself.
- **2026-11-06, open, found in step 6.** Inside a container, an Alt+press on a
  `String` title selects the card as a whole. `read_child_event` calls
  `convert_to_whole_selection`, which keeps a path only when it names a
  document, and the field `title` names a `String`. The press selects the title
  where the card answers directly, and a `PrimitiveString` title everywhere. The
  owner decides.
- **2026-11-06, decided by the owner, step 6.** "The principle behind the alt
  click is that it should be possible to select any part of the editor's
  document, so yes." A whole selection names a part as a whole: a document, or
  a value that a field or one element of a collection holds. A caret and a
  range of text still name a place inside a value, and a container makes them
  the child as a whole. `is_whole_selection` and `convert_to_whole_selection`
  follow the one rule, so a plain header of a table in a layout is selected too.
  The Alt+arrow walk keeps its objects, which are documents.
- **2026-11-06, step 6, the whole part rule.** `_is_whole_part` in
  `WholeSelection.jl` holds the rule: the value is a `Document`, or the last
  step is a field, or a range of width one in an `AbstractVector`, a `Tuple` or
  a `CollectionDocument`. No collection document holds the letters of a text,
  so a range of a text is never an element. The pane had a copy of the old rule
  in `_select_page_content` and calls `is_whole_selection` now. From a selected
  value, Alt+Down keeps the selection and Alt+Left and Alt+Right answer nothing,
  because a value holds no objects. The picture of a selected value is the
  picture of the part above it that has a canvas. Three tests expected the old
  rule and follow the new one: an Alt+click on the `String` title of a card
  selects the title, the whole card takes an Alt+click on its padding, and an
  Alt+click on a row of the Files pane selects the file of the row, while an
  Alt+click below the rows selects the pane.
- **2026-11-06, step 6, the whole part rule, counts.** After the change:
  `test_widget_selection` 107 (95 before, with new tests), `test_widget_card_fold`
  72, `test_application` 401 pass, 1 fail, 2 broken; the fail is
  `ApplicationTest.jl:1002` ("36k / 1M"), which main fixed in 6981aab8e after the
  branch began. `test_history_sweep` 167 pass, 1 fail at `HistorySweepTest.jl:111`
  (the palette gesture leaves one undo step), the same at 042c42fd0 before the
  change. `test_pivot_zone_edits` 31 pass, 1 error, the known "Rows" fault. All
  pass: `test_selection_walking` 36, `test_widget_table_part_selection` 69,
  `test_widget_forms` 97, `test_widget_table_header_levels` 40,
  `test_widget_table_list_column_share` 6, `test_widget_table_list` 256,
  `test_layout_list` 101, `test_pane_construct` 62, `test_pane_gestures` 117,
  `test_pane_reader` 89, `test_widget_toolbar` 83, `test_fault_catching` 53,
  `test_widget_table_cell_order` 48, `test_appearance_wrapper` 55,
  `test_find_bar_view_to_widget` 50, `test_appearance_tab` 159,
  `test_settings_tab` 55, `test_pivot_table_projection` 42,
  `test_workflow_to_widget` 72, `test_sequencechart_selection` 49,
  `test_sequencechart_projection` 120, `test_research_to_widget` 121,
  `test_data_frame_paths` 19, `test_data_frame_cells` 173, `test_part_picture` 13,
  `test_table_navigation` 67, `test_evaluator_toplevel` 250,
  `test_conversation_transcript` 143.
- **2026-11-06, step 6, card titles, counts.** Before → after:
  `test_widget_card_fold` 46 → 68, `test_platform_examples` 203796 → 203700, all
  pass in both; the 96 that went are not checked one by one. The same before
  and after: `test_widget_selection` 95, `test_find_bar_view_to_widget` 50,
  `test_object_to_widget` 60, `test_appearance_tab` 159, `test_settings` 107,
  `test_settings_tab` 55, `test_widget_forms` 97, `test_task_views` 82,
  `test_task_group_table` 65, `test_task_pages` 48, `test_dataframes` 608,
  `test_conversation` 552/75/51 (the known failures). Two assertions changed:
  `ObjectToWidgetTest.jl` reads the title as the `String` "WindowSettings", and
  `AppearanceTabTest.jl` reads the IO map of the card as
  `WidgetCardToGraphicsCanvasIoMap`.

- **2026-11-06, the landing.** The owner said "land it" before steps 6 to 8
  were all done. The branch was rebased onto `main` `e30b59b5e` with no
  conflict and landed by fast-forward. The 28 commits of `main` add no use of a
  removed name: their new code calls only `WidgetLabel("Wakes left:")` and
  `WidgetLabel(""; max_lines = 1)`. The package `Project.toml` files of
  omnet-julia point to the main checkout of projectured-julia, and omnet-julia
  calls `TextRole(...; base = :code_font)` in its result theme, so omnet-julia
  does not load against `main` until step 8 lands. The lists of compiled calls
  on `main` hold the calls of the old font code until `record_package_calls!`
  of step 6 runs. The next release of `ProjecturedPlatform` takes a minor step,
  because `apply_font_role` and `get_role_base` are no longer exported; the
  generator of step B7 finds a removed name by itself.

- **2026-11-06, step 8.** The omnet-julia branch `font-roles` (worktree
  `omnet-julia-font-roles`, from omnet main `f2b9b2f7d`) makes omnet-julia load
  against `main` again:
  - The NED, INI, test file and result themes name `font_role = :document_code`
    on each text. The NED, INI and test file themes keep their `font` field as
    `FontRole(:document_code)`, because their projections read it for the line
    breaks and the spaces between the parts. The `font` field of `ResultTheme`
    is gone, because only the title text used it as a base; the card title is
    `TextRole(:text; font_role = :title)`, and its `code_font` is
    `FontRole(:document_code)` for the line breaks of a task list.
  - The Qtenv preset keeps no literal font: `QTENV_FONT` and the `font` keyword
    of `build_qtenv_widget_theme` are gone, the theme sets no font field, and
    the Qtenv window passes `get_theme_defaults(WidgetTheme).font`, the 13 px
    text role. Its 11 px small font is now the 12 px quiet role.
  - Seven builders read `get_theme_defaults(TextTheme).font`, which is gone;
    they read `plain_text.font`, the same Ubuntu Mono 14. The example reads
    `quiet_font` for `font_small`.
  - The module builder read `theme.font` of a widget theme that is not scaled,
    which is now a `FontRole`; it reads `get_theme_values(theme)`, so a role
    comes resolved.
  - The campaign form names no font in omnet-julia, so it did not change. The
    icon of the execution status keeps its exact Lucide font.
- **2026-11-06, step 8, tests.** `Pkg.precompile` of the omnet environment
  prints no undeclared binding and no method overwriting. It warns that the
  recorded call lists are old: OmnetIde 552 of 5098, OmnetIdeBuild 240 of 1277,
  OmnetLegacyFormat 408 of 3921, OmnetLegacyResultPresentation 391 of 2639, and
  the projectured lists of Chart, DBCatalog, FSM, Workflow and Research. They
  are recorded again after the landing. The baseline is omnet `f2b9b2f7d` with
  projectured `e30b59b5e`, in a folder that holds both checkouts:
  `test_qtenv` 38/38 on both sides; `OmnetPresentationTest.test_all` 1663 pass,
  9 fail, 9 errors, 1 broken on both sides, at the same lines;
  `OmnetLegacyTest.test_all` 2650/25/64/1 against 2638/25/64/3, with the same
  failing lines. The ten tests more come from two `@test_skip` that need
  `inet-cpp` and `opp_repl` beside the repository, which the baseline folder
  did not hold. Both runs skipped `test_parallel_sim_dashboard_panel`, which
  hangs on main with two threads.
- **2026-11-06, decided by the owner.** The open question of step 3, what an
  exact font passed to `WidgetToGraphics(StyleFont(...))` means: "remove,
  agreed", option 1. The argument goes, an example draws at the sizes of the
  editor, and an example that needs large text sets the font scale of its
  appearance. The fonts of the widgets come only from the widget theme. The
  design that follows from it:
  - `WidgetToGraphics(font; ...)` goes, and `make_widget_theme(; font)` with it,
    because it was the default of that argument and gives the same exact font.
    A caller takes `WidgetTheme()`, or the scaled theme of its appearance.
  - The map of a study draws its widgets with the widget theme that it gets, not
    with the `font` of `ResearchTheme`. That field goes, with the `theme` keyword
    of `make_research_map_projection`.
  - The builders of step 4 and step 5 that take an exact font are not in this
    decision; each needs a design of its own.
  - The owner deferred the record of the compiled calls of step 6 to after the
    plan.
- **2026-11-06, the decision on a passed font, done** (`4b912c2aa`, omnet-julia
  `c57282965`). `WidgetToGraphics(; measure, theme, graphics_theme, text_theme)`
  is the only form, and `make_widget_theme` is no longer exported.
  - In projectured-julia, 107 calls in 17 examples and 54 tests drop the font,
    and 10 calls of `make_widget_theme` take `WidgetTheme()`. No expected size
    or position changed, because most tests measure with a fixed measure that
    gives every font the same size.
  - One test needs a large and a plain widget projection side by side:
    `LayoutCloseoutTest.jl:224` makes the large one with
    `make_scaled_theme(WidgetTheme(), Appearance(font_scale = 2.0))`.
  - The `font` keyword that nothing read is gone from `make_find_bar_projection`,
    `make_shell_projection` and seven omnet-julia demo builders.
  - omnet-julia: `reflection_render_projection` and `pane_render_projection`
    take no font. The scroll pane of the workbench keeps its font, because it
    measures the scroll step with it, and the module builder keeps its font,
    because `build_module_appearance_graphics` draws with it.
  - `ResearchTheme` keeps five fields that no code reads. The owner can remove
    them in a later change.
  - omnet-julia `main` does not load against projectured-julia `main` without
    `c57282965`, so the two branches land together.
  - omnet-julia `c57282965` against projectured-julia `3bd645e14`:
    `Pkg.precompile` prints no undeclared binding and no method overwriting;
    `test_qtenv` 38/38; `OmnetLegacyTest.test_all` 2650/25/64/1 and
    `OmnetPresentationTest.test_all` 1663/9/9/1, at the same failing lines as
    step 8 and as its baseline.
- **2026-11-06, step 7.** `type-rules.md` holds the six differences, the roles,
  the rule of one size in a code view and of a placeholder at the size of its
  field, the weight and the slant over a role, the exceptions, and the steps for
  a new widget, panel or domain. Its section 4 lists the builders that still
  take an exact font as they are now. `resolve_font_role` loses a check that can
  never be true, because a role with no base field does not exist any more.
  `test_documentation()` passes. The style guard `test_style()` fails at
  `BookModule.jl:34`, a `StyleFont("Ubuntu Mono", 20)` in `make_workload_file`,
  and `main` has the same line and the same failure.
- **2026-11-07, step 6, the suites.** The baseline is `e30b59b5e`, the parent of
  the first commit of this plan. Every commit between it and `3bd645e14` belongs
  to this plan, except `7afb5e0ce` and `bb664a6ef`, which change only the plan
  file of another plan. `test_platform`, the 21 domain and adapter suites, and
  `test_printers`, `test_domain_examples` and `test_projections` ran on both
  sides. `test_process` runs in a process of its own, because it can hang at
  `ProcessDebugTest.jl:185` under load, a race on `main`.
  - Four tests failed only on the branch, and each one read a form that this
    plan changed. `1cbfd8252` fixes them:
    - `MarkdownEmbedCardTest.jl:45` and `RstEmbedCardTest.jl:29` read
      `card.title.content`, and the title of a card is a `String` since
      `f1cf896c9`;
    - `WorkflowJournalToWidgetTest.jl:33` expected "9 OCT", and a section label
      of an outline keeps the case it was written in since `fb79e616f`;
    - `TooltipWindowTest.jl:210` rested 10 px into a label in a scrolled pane.
      The test measures with a `FixedMeasure`, but the hit test takes the box of
      a text with no background from the bounds of the canvas, which measure
      with the real font. The point was inside the Ubuntu 20 text of the old
      example font and is above the 13 px text, so the dwell rests in the middle
      of the line.
    The first three also fail on `main`, because their causes landed with
    `0fd0b6351`.
  - The other failures are on both sides, at the same places: `test_platform`
    3, `test_graph` 4 and 2 errors, `test_julia` 1 (`TooltipWindowTest.jl:179`),
    `test_pivot` 1 and 1 error.
  - The counts that differ, and why:

    | Suite | Base → branch | Why |
    | --- | --- | --- |
    | `test_platform` | 219626 → 219836 | new tests: font theme 74, card titles and the whole part rule 38, appearance tab 21, tab strip 4; the cell walk of the platform examples 75; `Theme` and `test_help` lose 1 each |
    | `test_chart` | 429 → 432 | three new tests in `ChartProjectionTest.jl` |
    | `test_projections` | 784 → 787 | three new tests in `GestureMapTest.jl` |
    | `test_printers` | 1048292 → 1036186 | the cell walk, below |
    | `test_domain_examples` | 1122674 → 1110196 | the cell walk, below |

    The two sweeps count one test for each cell that the walk of the IO map
    forces. 64 examples that draw with `NaturalToGraphics` lose about 358
    cells, and the assistant examples, with two natural tables, about 650.
    The research slice registers a row for `ResearchMap` in that table, and
    the row made its own widget printers from the font of `ResearchTheme`. Now
    it takes the scaled widget theme of the appearance, so its printers read
    the same cells as the other widget printers, and the walk counts each cell
    once: each field of each widget printer holds 2 cells on the base and 1 on
    the branch. Each plain widget example gains 1 cell, the title text of an
    alert. The card examples gain cells and `nested_object_to_widget` loses
    63, because a `String` title draws in a card IO map with a header in place
    of a `WidgetLabel`. `widget_table_frozen` draws 6 texts less, probably
    because its rows at 13 px are lower and the scroll of 60 px moves one more
    row out of the view.

## 6. Not in this plan

Letter spacing, small capitals, a switch for tabular figures and a line height
for each font in the renderer; the light face of Ubuntu.
