# The window has one table of font roles

> **Status:** pending. Written on 2026-11-05 at the owner's request. The owner
> decided every point of section 2. No implementation is asked yet.
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
- [ ] **Step 4. The tool panels.** The themes of the tooltip, help, message log,
  faults, statistics, undo, gesture log, gesture map, inspector, outline,
  conversation, MCP log, explorer, terminal, reference, text, syntax, graphics,
  settings and task panes name roles. DejaVu Sans, DejaVu Sans Mono and Liberation
  Sans leave the themes. Prose, names and values that are not code leave the mono
  font: log messages, file names, key names, help text. `UNSTYLED_TEXT_FONT`
  (`text/TextDocument.jl:118`): first find how an unstyled text reaches the
  printer. If the printer can draw it with the `document_code` role of its theme,
  it does. If the font is a value in the document, it stays, and the plan records
  why. Tests: the suite of each panel that the step changes.
- [ ] **Step 5. The domains and adapters.** The 16 domain themes with fonts name
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
- [ ] **Step 6. Real screens.** Draw the parts of the 19 examples of the page in
  the editor, on `main` and on the branch, with `write_image` and no window on
  the desktop, and put them side by side on the page. The owner looks at them
  before the branch goes further. Then compare every suite that steps 1 to 5
  touched with the baseline of `main`. Record the precompile calls again
  (`record_package_calls!`) for each package whose load warns that recorded calls
  no longer resolve, and check that the load of the branch gives no such warning.
- [ ] **Step 7. The documentation.** Write `documentation/rule/type-rules.md`:
  the six differences, the roles, the exceptions, and how a new widget, panel or
  domain gets its fonts. Change `documentation/package/platform/style/style.md`
  (fonts, roles and the font theme), `appearance/appearance.md` (the font theme in
  the appearance and in the tab), `widget.md` (the roles of each part) and
  `new-domain-guide.md` (a domain theme names roles).
- [ ] **Step 8. omnet-julia.** After the owner approves the landing of steps 1 to
  7 on `main` of projectured-julia: the NED, INI, test file and result themes name
  roles; the result card title takes `title`; the Qtenv preset
  (`WorkbenchRender.jl:107, 160`) names roles and keeps no literal font; campaign
  form values leave the code font. The execution status icon keeps its exact
  Lucide font. Tests: the presentation suite of omnet-julia, and
  `Pkg.precompile` of the omnet environment, because a change of a platform
  method breaks its precompile.

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

## 6. Not in this plan

Letter spacing, small capitals, a switch for tabular figures and a line height
for each font in the renderer; the light face of Ubuntu.
