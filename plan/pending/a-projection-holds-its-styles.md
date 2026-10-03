# A projection holds its styles, and a builder fills them

> **Status:** pending, not started. Written on 2026-10-03 at the owner's request.
> The owner decided the model (section 4); section 6 lists the points that are
> open.

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

4. **Only a builder that holds the `Appearance` scales**: it passes
   `get_scaled_theme!(appearance, T)`. A factory takes a scaled theme or
   `nothing`, and passes it on; it does not scale. A caller with a theme that is
   not scaled and no appearance, such as a preset in a test or the Qtenv look of
   omnet, scales it with `make_scaled_theme(theme)`. `scale_theme` goes.
5. **A style chosen while printing is a field too.** Markdown holds the four
   fonts of its headings, RST the four fonts of its titles and the styles that
   its roles take, SQL its plain text, and the settings tab its caption style.

## 5. Steps

All the work is in a worktree, and each step is a commit. The platform is one
package, so the steps of its slices run one after another.

- [ ] **M1. The style slice.** `make_style_field` and `make_theme_values_field`
  take a scaled theme or `nothing`, and `scale_theme` goes. The guide of the
  style slice says the model.
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
- [ ] **M6. The widgets.** `WidgetToGraphics(; theme)` takes a scaled theme, and
  its default is the scaled default theme; the callers with a preset scale it.
  The second constructors of the widget printers stay (6.1).
- [ ] **M7. omnet**: the Qtenv look scales its preset; a call scan for the
  factories whose keyword changed.
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

## 6. Open points

1. **The second constructors of the widget printers.** They take the scaled
   widget theme and fill the fields, so they are code of the builder that stands
   next to its projection; the projection type and its printer never see the
   theme. My recommendation: keep them, and say so in the guide. The other way
   moves 319 calls of `_themed` into `WidgetToGraphics`, for no gain that I can
   see.
2. **A theme that is not scaled, passed to a factory.** My recommendation: a
   `MethodError`, because the factory takes a scaled theme or `nothing`; the
   other way scales it silently at 1, which is what `scale_theme` does today.
3. **Where the default of a style field comes from.** My recommendation: the
   default theme of its role (4.2), so the projection names its theme type for
   its defaults only. The other way gives no default, and every builder must
   pass every style.
4. **Mechanical edits by sub-agents.** M3 to M5 are about 240 fields of the same
   form. My recommendation: a Sonnet sub-agent writes one package at a time from
   the JSON commit as the model, and I review each before the next.

## 7. Risks

- About 240 projections and their factories change. A field that a factory
  forgets keeps its default and does not follow the theme; the theme test of
  each domain draws at a font scale of 1.5 and compares every font size, which
  finds it.
- A factory that two builders share changes for both; the call scan of M7
  finds the callers in omnet.

## 8. Findings during the work

None yet.
