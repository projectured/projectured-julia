# A projection holds its styles, and a builder fills them

> **Status:** pending, in progress on the branch `projection-styles` (2026-10-04). Written on 2026-10-03 at the owner's request.
> The owner decided the model (section 4) and every point of section 6. The work
> waits: another agent changes the default values of the appearance, so some
> defaults of the styles change. The work starts from the `main` that holds that
> change, and a default that it changed is kept as it is there.

## 1. The request

The owner asked why the projections of the JSON domain store their theme, and
not only their styles. After the answer the owner decided:

> look at how WidgetToGraphics does this, all projections should do it like
> that, store the styles as fields, don't store the themes, use option 1
>
> also, I think the scaled theme should not be known by the projections, they
> should not care about whether it's scaled or not, why would they? it's the
> builders task to make sure it's scaled

Option 1 of the answer: the factory of a domain passes the styles to the
projections that it builds.

## 2. What exists

- **The widget printers** store only their style fields. Each has a second
  constructor, `WidgetLabelToGraphicsCanvas(theme::ScaledWidgetTheme; …)`,
  whose keyword defaults fill the fields with cells over the scaled theme
  (`_themed`, 319 calls). The builder `WidgetToGraphics(; theme)` passes the
  theme, and scales a theme that is not scaled itself. Its offsets that are no
  value of the theme (`_scale_space`, the icon scale) are read in those
  constructors, not while a printer prints.
- **The projections of Part P** (the text, the syntax, the domains and the
  tools) store the theme: 243 fields `theme::Any = nothing` in 29 files. The
  style fields have the default `_get_x_style(theme, :role)`, which is
  `make_style_field(K, scale_theme(theme), T; name)`. `@projection` makes a
  keyword constructor from the fields, and only a field is a keyword, so the
  theme had to be a field for the defaults to read it.
- **Nothing reads that field after the projection is built**, except in four
  places, which choose a style while they print:
  - Markdown, the font of a heading by its level (`_heading_font`);
  - RST, the font of a title by its level (`_title_font`), and the color of a
    role by its name (`_role_color`), which is one of six text styles;
  - SQL, the plain text of the commas and the parentheses that the printer
    builds (`_get_sql_text(p.theme, :plain_text)`, six calls);
  - the settings tab, the caption style (`SettingsToWidget(; theme)`).
- **The projections with a tuple of values** (the chart, the sequence chart,
  the graph and two more; `make_theme_values_field`, 5 files) store the tuple
  and not the theme. They fit the model, except that their constructors scale.
- **`scale_theme` has 100 calls in 55 files**: each factory and each default
  scales a theme that is not scaled, at a scale of 1. Eight callers pass such a
  theme in this repository, and one in omnet (`build_qtenv_widget_theme()`).
- **The builders that hold an `Appearance`** call `get_scaled_theme!` (60
  calls in 28 files): the natural registrations, the wrappers of the tools, the
  application and the shell.
- 15 test files build a single projection with `theme`.

## 3. The words

- **A style**: one value that a projection draws with, a `StyleText`, a color, a
  font or a length, held in a field of the projection, as a value or as a cell
  that reads a theme with no edge.
- **A builder**: the code that makes a projection and fills its styles: a
  factory of a domain (`JsonToSyntax(; theme)`), `WidgetToGraphics`, a natural
  registration, a wrapper of the editor.

## 4. The model (decided)

1. **A projection holds its styles as fields, and no theme.** Its printer reads
   only its fields. Nothing in a projection type or its printer scales a value
   or asks whether a theme is scaled.
2. **The default of a style field is the plain value of its role in the default
   theme** (`get_theme_defaults(JsonTheme).null_text`), so a projection that is
   built with no styles draws as it draws today.
3. **A builder fills the styles** (option 1). The factory of a domain maps each
   role of its theme to the field of a projection:

   ```julia
   function JsonToSyntax(; theme = nothing, syntax_theme = nothing)
       style(name) = make_style_field(JsonTheme, theme, StyleText; name)
       RecursiveProjection(TypeDispatchingProjection(
           JsonNull => JsonNullToSyntaxLeaf(; style = style(:null_text)),
           …))
   end
   ```

4. **A projection and a factory take any theme, or `nothing`, and never ask
   whether it is scaled.** A builder that supports the scales passes
   `get_scaled_theme!(appearance, T)`; a builder of an interface with no scales
   passes a theme as it is, such as a preset. `scale_theme` goes, and no
   constructor names a scaled theme type (6.1, 6.3).
5. **A style chosen while printing is a field too.** Markdown holds the four
   fonts of its headings, RST the four fonts of its titles and the styles that
   its roles take, SQL its plain text, and the settings tab its caption style.

## 5. Steps

All the work is in a worktree, and each step is a commit. The platform is one
package, so the steps of its slices run one after another.

- [x] **M1. The style slice.** Done, except that `scale_theme` stays until the
  last caller goes (M9); finding 1. A read of a field of a theme gives the plain
  value, and an accessor gives the kind (6.3); the appearance tab, the file and
  the scaled theme use it. `@theme` writes `get_<name>_style` (6.6), and the 29
  helpers by hand go. `make_theme_cell`, `make_style_field` and
  `make_theme_values_field` take any theme or `nothing`, and `scale_theme`
  goes. The guide of the style slice says the model.
- [x] **M2. The text and the syntax.** Done; finding 2. Their projections lose the field
  `theme`, their factories (`SyntaxToText`, `TextToGraphics`, the insertion
  leaf of a domain) fill the styles.
- [x] **M3. The ten document domains**, one commit each: JSON, XML, YAML, SQL
  (with its plain text), Julia, Math (`MathConfig`), Formula, Markdown (with its
  heading fonts), RST (with its title fonts and its roles), Book.
  - [x] JSON, the model (`ea994afb4`). [x] XML (`55ec211b2`). The local function
    of a factory that gives a style is `get_style(name)`, a name with a verb;
    the factory of YAML has a keyword `style` already (`6d20f49d6`).
  - [x] YAML (`12841097d`, `53ea2cc4b`).
  - [x] SQL, with its plain text (`fef2db90f`).
  - [x] Julia (`804761740`). [x] Math, with `MathConfig` (`f5f31898e`).
  - A check reads a factory and the style fields of each projection it builds,
    and prints each projection that misses a style:
    `python3 /var/tmp/projection-styles/check_factory.py <file> <get_x_style> <factory>`.
    JSON, XML, YAML, SQL, Julia and Math give `bad 0`.
  - [x] Formula (`76a7f4c47`, `03030616d`: a helper by hand that read one field
    goes). [x] Markdown (`27f803964`, `1d3d5669a`), finding 8. [x] RST
    (`ff1cc507d`, `6fe919b09`), finding 8. [x] Book (`a11a09069`). Every
    factory gives `bad 0`, except extra keywords that are no styles.
- [x] **M4. The charts, the graph, process, FSM and the database catalog.**
  Chart, sequence chart and graph (`f21842adf`): their printers hold the values
  of the theme in one field already, so only `scale_theme` goes, and the plan of
  a chart names those values `theme_values` beside the `ChartStyle` of the
  chart (6.7). Process (`39a332180`), DB catalog (`54f8db940`), FSM
  (`69ce8fd81`): FSM gains `FsmToSyntaxLabel`, the table of the labels of its
  diagram, in the form of `ProcessToSyntaxLabel`, for omnet (finding 6).
- [x] **M5. The tools**: the fault log, the gesture log, the message log, the
  frame statistics, undo, the file explorer, the gesture help and the palette,
  help, the inspector, the settings tab; finding 7. Also the tooltip window, the
  layouts, the conversation and the assistant, and the data frames.
  - [x] settings (`1bbd6bf6b`), message log, the model (`6d5fffc24`), undo
    (`3596d9c71`), statistics (`396e6d1aa`), gesture log (`c265e5005`), fault
    log (`8e8f03925`), help (`be10fe33e`), gesture help (`9e79bc97d`), file
    system (`3e0627ca5`), tooltip and layout (`1e28c7b0d`), conversation and
    assistant (`862e77d9e`), data frames (`e79e8681d`).
- [x] **M6. The widgets** (`abc11f068`); finding 4. The second constructors of the widget printers take a
  theme of any kind; the five offsets and the box of a glyph become fields of
  `WidgetTheme` (6.1); the five printers that size an icon beside a text read a
  style for it (6.2).
- [ ] **M7. omnet**: a call scan for the factories whose keyword changed.
  Done as a scan (finding 6); the change in omnet waits for the owner.
- [x] **M8. The tests**: the 15 files that build a projection with `theme` build
  it through its factory, or pass the style. Each step changed the theme test
  of its package, and added a check that the projection has no field `theme`
  and that a theme that is not scaled draws at no scale.
- [ ] **M9. The guides**: the style slice, the widget slice, the guide for a new
  domain, the section "The theme" of each domain, and a rule in
  `architecture-rules.md`: a projection holds its styles, a builder fills them,
  and only a builder with an appearance scales.
  - [x] The guides (`2a3080d65`, `c46c10dcc`) and the docstrings of every theme.
  - [ ] `scale_theme` goes: it waits for omnet (finding 6). No caller in this
    repository is left.

Checks after each step: the theme test and the suite of the package that
changed. At the end: the suites of every domain, the tool and the guard tests,
the images of all examples equal to those of `main` byte for byte, the omnet
suites that build a themed view, and the images of both tabs.

## 6. The owner's answers, and what they bring

1. **The second constructors of the widget printers do not know the scaled
   widget theme** (the owner: "projection constructors don't need to know about
   scaled widget themes, no?"). They take a theme of any kind; `_themed`, the
   derived text styles and the hover and pressed layers take one too. Five small
   offsets that the constructors scale with the spacing scale (`_scale_space`:
   the offset of a shadow, 2; the nudge of a chevron, 1; the padding of a menu
   item, 2; the inset of a glyph, 3; the gap of a body, 2) and one box of 8 times
   the icon scale become fields of `WidgetTheme`, of the kinds `Spacing` and
   `IconSize`; the appearance tab shows six more fields. The owner agreed.
2. **The icon scale is no style parameter** (the owner: "icon_scale is not a
   style parameter, we can introduce new style parameters if needed or use
   existing ones"). Five printers multiply the height of a line of text by the
   icon scale of the appearance, which they read through the scaled theme, to
   size an icon beside the text: a button, a menu item, a toolbar command, a tab
   and a title. That reading goes. Each printer holds a style instead, which the
   theme scales:
   - **A.** One field of `WidgetTheme`, `icon_size::IconSize = IconSize(1.0)`:
     the size of an icon beside a text, in lines of that text. The kind
     `IconSize` already exists, and the icon scale scales a length of that kind,
     so the scaled theme gives the icon scale times 1.0. A printer computes the
     box as the height of the line times `icon_size`, as it does now with the
     scale. The look does not change: an icon follows the font scale through
     the height of its line, and the icon scale through the field. A theme that
     is not scaled gives 1.0: an icon as tall as its line.
   - **B.** A size in pixels, `icon_box::IconSize = IconSize(23)`, the height of a
     line of the default font. Then an icon follows the icon scale and not the
     font scale: at a font scale of 1.5 its text grows and the icon does not.
   - The owner chose A. It keeps the look and the meaning of the two scales, and
     needs no new kind of style.
3. **A read of a field of a theme gives the plain value**, and the kind of a
   length stays in the document; the appearance tab, the file and the scaled
   theme read the kind with an accessor of the style slice (the owner: "yes").
   This is a change of the style slice that every theme uses.
4. **The default of a style field is the plain value of its role in the default
   theme**, `get_theme_defaults(K)` (the owner: "from the default theme, yes").
5. **A Sonnet sub-agent edits one package at a time**, from the JSON commit as the
   model, and I review each package before the next (the owner: "yes").
6. **`@theme` writes the function that gives a style** (the owner: "The @theme
   JsonTheme macro call should write a function get_json_theme, no? would
   simplify getting the style"). Each theme file has a helper by hand today,
   29 of them, such as `_get_json_style(theme, name) = make_style_field(JsonTheme,
   scale_theme(theme), StyleText; name)`. `@theme struct JsonTheme` writes
   `get_json_style(theme, name)`: the style field of the role `name`, a cell that
   reads `theme` with no edge, or the plain default value when `theme` is
   `nothing`. The macro takes the type of the value from the default of the
   field, so a call names no type. A factory then reads
   `JsonNullToSyntaxLeaf(; style = get_json_style(theme, :null_text))`. The
   name is the name of the type, without `Theme`, in snake case, between `get_`
   and `_style`: `get_widget_style`, `get_db_catalog_style`,
   `get_sequence_chart_style`. No name of the 29 is taken. The owner proposed
   `get_json_theme`, and agreed to `get_json_style`, because the function
   answers a style and not a theme.
7. **A small inconsistency in the use of styles is fixed where it is found**
   (the owner), and recorded in section 8. Known now: the settings tab holds
   the widget theme for one caption style; the chart printer names its tuple of
   values `theme`; the FSM labels of omnet take no Julia theme.

## 7. Risks

- About 240 projections and their factories change. A field that a factory
  forgets keeps its default and does not follow the theme; the theme test of
  each domain draws at a font scale of 1.5 and compares every font size, which
  finds it.
- A factory that two builders share changes for both; the call scan of M7
  finds the callers in omnet.

## 8. Findings during the work

1. **A theme reads its fields as it stores them, and the style slice gives the
   values** (M1, 2026-10-04). Since the plan of the default look (Part R), a text
   field of a theme holds a `TextRole` or a `FontRole`, which the scaled theme
   turns into the `StyleText` or the `StyleFont` over a base font of the theme.
   The appearance tab, the file and the presets read the role and the kind of a
   length as they are stored, so a read of a field must not change (6.3 said it
   would). Instead `get_theme_value(theme, name)` gives the value that a
   projection draws with: of a scaled theme its scaled value, of a theme its value
   at no scale, a length as its number and a role as what it gives.
   `get_theme_values(theme)` gives them by name, and `make_theme_cell`,
   `make_style_field` and `make_theme_values_field` read through it, so they take
   any theme. `make_style_field(K, theme; name)` takes the type of the value from
   its default, and `@theme` writes `get_<name>_style(theme, field)` with it and
   exports it. The goal of 6.3 holds: a builder gives a theme scaled or not, and
   nothing checks.
2. **Two forms of a builder, one rule** (M2, 2026-10-04). The projections of the
   text and the syntax already hold only their styles, as the widget printers
   do: an outer constructor with the keyword `theme` fills them, such as
   `PrimitiveNumberToSyntaxLeaf(; theme, style = get_syntax_style(theme,
   :number_text))`. Such a constructor is a builder that stands beside its
   projection, as 6.1 says of the widgets, so they keep it; only `scale_theme`
   and the helpers by hand go (`get_text_style` and `get_syntax_style` from the
   macro). A projection that stored the theme in a field (Part P) has a keyword
   constructor that `@projection` writes from its defaults, and a second keyword
   constructor would overwrite it, so it takes option 1: its fields default to
   the default theme, and the builder passes the styles. The reference printers
   took option 1, and the inspector, which stored a `ReferenceTheme` and built
   them while it printed, holds the values of that theme
   (`reference_style`); `make_reference_inspector_projection(; theme,
   reference_theme)` builds it, for the natural registration and for
   `SelectionInspectorToText`. The rule for both forms: a projection holds styles
   and no theme, and nothing in it scales. The tests of the text, the syntax, the
   themes, the inspector and of JSON and SQL give 1600 pass.
3. **The images do not change after M1, M2 and JSON** (2026-10-04). Each of the
   105 examples renders to an image equal byte for byte to the image of `main`
   (`bccfd39d6`), for the branch at the JSON commit. The branch is rebased on
   `main` at `759a7ce2a` after YAML, with no conflict.
4. **The widgets take the graphics theme from their builder** (M6, 2026-10-04).
   The ring around a part selected as a whole and the band of a selected row are
   values of `GraphicsTheme`. The printers read them from the appearance of the
   scaled widget theme, so they knew of the scale. `WidgetToGraphics` and the
   seven second constructors that draw them take the keyword `graphics_theme`
   instead, and each of the ten builders with an appearance gives
   `get_scaled_theme!(appearance, GraphicsTheme)`. So the settings and the shell
   slices use the graphics slice directly: two new rows in
   `PLATFORM_SLICE_EDGES`, an edge that they had through the widget slice. The
   context menu window holds its largest size and its item gap, and no theme. The
   theme gains seven fields: five offsets of the kind `Spacing`
   (`shadow_offset`, `chevron_nudge`, `toggle_group_padding`,
   `stepper_glyph_inset`, `accordion_body_gap`), `icon_size` and
   `stepper_glyph_minimum`. The data frame theme test fails at `bccfd39d6`
   (`_make_query_field` takes five arguments, the find field gave three); `main`
   repairs it in `db864f69d`, which the rebase brings.
5. **SQL has thirty projections over six style roles, so the factory builds each
   role group once** (M3, 2026-10-04). `SqlToSyntax` makes six named tuples —
   one `style` field for `:plain_text` (six leaves) and one for `:name_text`
   (two leaves); `keyword` alone for two nodes; `keyword` and `punctuation` for
   eight nodes; `keyword`, `punctuation` and `plain` for five nodes that build a
   delimiter or a comma list (`SqlSelectClause`, `SqlFromClause`,
   `SqlInsertStatement`, `SqlUpdateStatement`, `SqlCreateTableStatement`); and
   `keyword`, `name`, `punctuation` and `plain` for the two from-item/select-item
   nodes — and splats the matching tuple into each constructor, as `53ea2cc4b`
   does for the YAML mapping. The five nodes of the third group read
   `_get_sql_text(p.theme, :plain_text)` while printing a parenthesis or a
   comma; each gains a `plain::StyleText` field instead, and the printer reads
   `p.plain`. `SqlBooleanBinaryToSyntaxNode` is a plain `<: Projection` struct
   with no `theme` field and an outer constructor that takes `theme`; it keeps
   that form (finding 2), only `_get_sql_style` becomes `get_sql_style`.
   `_get_sql_font` drops `scale_theme` the same way `make_style_field` did
   (finding 1): `nothing` gives the default font, anything else goes through
   `make_theme_cell`. No caller outside `source/domain/sql/` passes `theme` to a
   SQL projection constructor, and neither omnet-julia nor inet-julia reference
   a SQL projection or `SqlTheme` at all.
6. **omnet holds themes of its own in the old form** (M7 scan, 2026-10-04, omnet
   `f72ccd5c`). Fourteen files under `source/legacy/` (ini, ned, result,
   simulator, testfile) declare their own themes and projections with a field
   `theme`, 40 of them, and helpers by hand that call `scale_theme`, 13 calls.
   They work while `scale_theme` exists, so M9 can remove it only after omnet
   follows the same rule; that is a change in a second repository, and it waits
   for the owner. Three calls reach the projections of this branch:
   `WorkbenchRender.jl` builds `FsmStateToSyntaxLabel(theme = fsm)` and
   `FsmTransitionToSyntaxLabel(theme = fsm)`, which the FSM step breaks unless it
   gives omnet a builder for the labels; and `build_widget_graphics` in
   `SimulationToWidget.jl` passes a scaled widget theme to `WidgetToGraphics`
   with no `graphics_theme`, so at a scale other than 1 the ring of a selected
   part draws at no scale. omnet calls `ConversationToWidget()` and
   `WidgetToGraphics(font; measure, theme)` in other places, which still work.
7. **A tool with no factory gets a builder** (M5, 2026-10-04). A tool
   projection of the form of Part P is built by its registration, and often by
   an overlay or a test too. Its `@projection` keyword constructor takes the
   styles, so a builder `make_<tool>_projection(; theme)` reads them from a
   theme, as `make_reference_inspector_projection` does: `make_message_log_projection`,
   `make_undo_projection`, `make_frame_statistics_projection`,
   `make_gesture_log_projection` (with `operation_width`, which is no style),
   `make_fault_log_projection`, `make_help_list_projection`,
   `make_about_page_projection`, `make_gesture_map_syntax_projection`,
   `make_command_palette_syntax_projection`, `make_conversation_composer_projection`,
   `make_evaluator_form_projection` and `make_evaluator_toplevel_projection`.
   Where a factory exists (`FileSystemToSyntax`, `ConversationToWidget`,
   `make_data_frame_view_projection`), it fills the styles and no name is added.
   The gesture help had factories of a whole chain, so the two syntax builders
   are their first stage. The panels of the gesture log and the fault log read
   their margin, padding, radius and background with `get_theme_value`. The
   settings tab, the tooltip window and the context menu window hold the values
   they read as fields. The value list of a data frame, a builder of widgets in
   an operation, takes either theme or `nothing`. The suites of the tools, the
   help, the conversation, the tooltips, the settings, the widgets and the data
   frames give 1124 pass and 1 fail; the fail
   (`DataFrameFilterTest.jl:83`, a row number 2 px above its cells) fails on
   `main` at `759a7ce2a` in the same way.
8. **A heading and a title choose a font by level from fields** (M3,
   2026-10-04). A Markdown heading and an RST section title held the theme only
   to choose one of four fonts by the level while they print. Each holds the four
   fonts as fields named as the fields of the theme (`heading_1_font` …
   `heading_font`, `title_1_font` … `title_font`), and `_get_heading_font` or
   `_get_title_font` chooses one. The role chip of RST chose one of six colors by
   the name of a role in the same way; it holds the six styles. The chart, the
   sequence chart and the graph hold all the values of their theme as one
   `NamedTuple` field already, which `make_theme_values_field` fills from a theme
   scaled or not.
9. **The checks at the end** (2026-10-04, branch `177407250`, `main` `759a7ce2a`).
   - The images of the 105 examples equal those of `main` byte for byte, in two
     passes: each example with its own projection, and each document through
     `NaturalToGraphics` with an `Appearance` at the scales 1.5, 1.5, 1.5, 1.5,
     2.0 and 2.0, where 97 images differ from those at scale 1. The one error of
     the second pass (the assistant gives a widget, not graphics) is the same on
     `main`.
   - The guards and every domain suite (`test_tree` … `test_dataframes`): 4383
     pass on the branch, 4350 on `main`, and the same 34 failures on both, in
     the export and the argument guards and in the row numbers of a data frame.
     Two more failures of the export guard came from the help slice, whose
     exports did not follow its fragments; `177407250` repairs them.
   - `test_platform`: 90983 pass, 8 broken, and the one failure of `main`
     (`FileSystemDocumentTest.jl:42`).
   - `test_integration`: 1201817 pass, 1578 broken, and 2 errors, which are
     `@test_broken` assertions of `ClickRoundtripTest.jl:323` that pass.
   - A fresh precompile prints a warning of a stack overflow on `main` too.
   - `test_all` as one process does not fit in 8 GB, because its precompile
     runs many packages at a time; its groups run in three processes instead.

