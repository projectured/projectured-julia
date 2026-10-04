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
- [ ] **M2. The text and the syntax.** Their projections lose the field
  `theme`, their factories (`SyntaxToText`, `TextToGraphics`, the insertion
  leaf of a domain) fill the styles.
- [ ] **M3. The ten document domains**, one commit each: JSON, XML, YAML, SQL
  (with its plain text), Julia, Math (`MathConfig`), Formula, Markdown (with its
  heading fonts), RST (with its title fonts and its roles), Book.
- [ ] **M4. The charts, the graph, process, FSM and the database catalog.**
- [ ] **M5. The tools**: the fault log, the gesture log, the message log, the
  frame statistics, undo, the file explorer, the gesture help and the palette,
  help, the inspector, the settings tab.
- [ ] **M6. The widgets.** The second constructors of the widget printers take a
  theme of any kind; the five offsets and the box of a glyph become fields of
  `WidgetTheme` (6.1); the five printers that size an icon beside a text read a
  style for it (6.2).
- [ ] **M7. omnet**: a call scan for the factories whose keyword changed.
- [ ] **M8. The tests**: the 15 files that build a projection with `theme` build
  it through its factory, or pass the style.
- [ ] **M9. The guides**: the style slice, the widget slice, the guide for a new
  domain, the section "The theme" of each domain, and a rule in
  `architecture-rules.md`: a projection holds its styles, a builder fills them,
  and only a builder with an appearance scales.

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
