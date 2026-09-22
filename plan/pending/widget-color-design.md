# Widget colors: where each color comes from

**Status (2026-09-22): PROPOSED.** Nothing is implemented. §3 records the
present state, §4 describes the target model, and §5 lists the decisions. Each
decision in §5 carries a recommendation. The owner did not decide them yet.

**Goal:** one rule that gives, for each color that a widget draws, the value
that the renderer uses. The rule covers the three places that can hold a color:
the theme, the widget projection and the widget document. It gives the order in
which they apply, the meaning of `nothing` in each place, and the ways in which
one widget can get colors that differ from the other widgets.

**Repositories:** projectured-julia holds the model, in
`source/widget/WidgetToGraphics.jl` and `source/widget/WidgetDocument.jl`.
Neither file is sealed. omnet-julia holds call sites that set widget colors, and
it builds a `WidgetTheme` with the positional constructor, so a change to the
fields of the theme changes omnet-julia too.

## 1. Summary

**The target rule.**

1. The **theme** holds colors with names that give their meaning. Only a
   projection constructor reads it, once, when the factory builds the
   projections.
2. The **widget projection** holds one style field for each part and state that
   it draws. The factory fills each field from a theme token, and a caller can
   give another value. The projection is the only place that holds the look of
   a widget type.
3. The **widget document** holds no theme and no token name. For its own
   instance it can hold a **tone or variant**, which selects style fields of the
   projection, and an **override**, which is a color for one part.

The renderer resolves the color of one part in this order:

1. the override on the document, if it is not `nothing`;
2. the style field of the projection that the variant and the state of the
   document select.

A style field gets its value from the caller that built the projection, else
from the factory. There is no third step. A printer body holds no color
constant.

| Place | `nothing` means |
| --- | --- |
| theme token | not allowed |
| projection style field | draw nothing for this part |
| document override | no override, so the projection field applies |

**The present state breaks this rule in many places** (§3.8). The three largest:
no code draws the box colors of 19 widgets, seven colors are constants in
printer code, and four different colors mark a selected thing.

## 2. Terms

| Term | Meaning |
| --- | --- |
| **theme** | a `WidgetTheme` value: named colors, fonts and some shared sizes |
| **token** | one field of the theme, for example `primary` or `border` |
| **factory** | `WidgetToGraphics(font; measure, theme)`. It builds one widget projection for each widget type. |
| **widget projection** | a `Widget<X>ToGraphicsCanvas`. It prints one widget type to graphics. |
| **style field** | a field of a widget projection that holds a `StyleColor`, a `StyleStroke` or a `StyleText` |
| **part** | a visible piece of a widget that has a color: the surface, the outline, the text, the focus ring, a chevron |
| **state** | a field of the widget document that the actions of the user change: `enabled`, `hovered`, `pressed`, checked, the selection, the active tab |
| **variant** | a `Symbol` field of the widget document that selects one set of style fields, for example `WidgetCard.variant = :muted` |
| **tone** | a proposed `Symbol` field that gives the meaning of a widget, such as `:destructive` or `:warning` (D5) |
| **override** | a field of the widget document that holds a color for one part of this one widget |
| **upstream projection** | a projection that makes widget documents, for example `ConversationToWidget` |

## 3. The present state

### 3.1 The theme

- `WidgetTheme`
  ([WidgetToGraphics.jl:60](../../source/widget/WidgetToGraphics.jl#L60)) holds
  20 colors, three fonts, some spacing values, one `inset` and four text
  styles. It is a plain struct, not a document.
- The palette follows shadcn/ui. Each surface token has a text token beside it:
  `card` and `card_foreground`, `primary` and `primary_foreground`. The token
  `background` is the color of the page. `card` is a raised surface, `muted` a
  quiet surface, `accent` a hover surface, `border` a line, `input` the outline
  of an input box, and `ring` a focus ring.
- Four presets exist
  ([WidgetToGraphics.jl:143-220](../../source/widget/WidgetToGraphics.jl#L143-L220)).
  The default is `make_slate_light_theme`. No code in either repository uses a
  dark preset. omnet-julia builds its own theme, `build_qtenv_widget_theme`,
  with the positional constructor
  ([WorkbenchRender.jl:127](../../../omnet-julia/source/presentation/workbench/WorkbenchRender.jl#L127)).
- Only the factory reads the theme. `PrinterContext` names a theme as an example
  of a property
  ([PrinterContext.jl:20](../../source/kernel/projection/PrinterContext.jl#L20)),
  but no code puts one there. So a printer can not read the theme, and a parent
  widget can not give a theme to its children.
- No code changes the theme of an open window. Another theme needs another
  factory.
- The token `inset` is never read.

The design comes from the "hybrid" model in
[widget-fixed-sizes-positions-report.md](../done/widget-fixed-sizes-positions-report.md)
§8.1. The theme is a small shared core, each projection owns its style fields,
and "different styles are different factory constructors".
[layout-rules.md](../../documentation/rule/layout-rules.md) §1 states the same
for sizes: the factory chooses a style parameter, and a caller can replace it.

### 3.2 The factory and the style fields

- The factory
  ([WidgetToGraphics.jl:6983-7119](../../source/widget/WidgetToGraphics.jl#L6983-L7119))
  calls about 40 projection constructors with positional arguments. Each
  argument is a token, a stroke made of a token and a width, a color derived
  from tokens, or a literal. For example, `WidgetText` gets `theme.body_text`,
  `theme.background`, `theme.input`, `theme.radius` and `theme.ring`.
- `@projection` puts each style field in a cell. So
  `ProjectionConfiguringProjection` can show the fields of a projection in a
  form, and a person can change them while the editor runs.
- A caller that builds one projection by hand gets the struct defaults, not the
  theme. `WidgetScrollPaneToGraphicsCanvas` has
  `background_color = color_white`
  ([WidgetToGraphics.jl:426](../../source/widget/WidgetToGraphics.jl#L426)).
  Four call sites build this projection by hand with `chrome = false`.
- Two factory arguments are literals, not tokens: the knob of `WidgetSwitch` and
  the knob of `WidgetSlider` are `color_white` in every theme
  ([WidgetToGraphics.jl:7056](../../source/widget/WidgetToGraphics.jl#L7056),
  [:7061](../../source/widget/WidgetToGraphics.jl#L7061)).
- Two factory arguments are derived from tokens: the `tint_color` of
  `WidgetCard` is `color_interpolate(theme.muted, theme.background, 0.5)`, and
  the `fill_color` of `WidgetHighlight` is `_with_alpha(theme.primary, 0.25)`.
- Two style fields are never read: `cell_text` and `header_text` of
  `WidgetTableToGraphicsCanvas`
  ([WidgetToGraphics.jl:5832-5833](../../source/widget/WidgetToGraphics.jl#L5832-L5833)).

The names of the style fields follow no common scheme. One name means different
parts in different widgets:

| Name | In one widget | In another widget |
| --- | --- | --- |
| `active_color` | the surface of a pressed button | the fill of the active tab |
| `selected_color` | the band of the selected row of a list | the dot of a selected radio button |
| `fill_color` | the filled part of a progress bar | the whole block of a skeleton |
| `background_color` | the surface of a button, from `theme.background` | the surface of a status bar, from `theme.muted` |
| `border_color` | the box border on the document, which is not drawn | the outline of the `WidgetText` projection, from `theme.input` |

One part has many names. The surface fill alone is `background_color`,
`surface_color`, `card_color`, `default_fill`, `released_fill`, `button_fill`
and `track_color`, depending on the widget.

Appendix A lists every style field of every widget projection and the token that
fills it.

### 3.3 Color fields on the widget document

| Field | Widgets | Drawn | `nothing` means |
| --- | --- | --- | --- |
| `margin_color`, `border_color`, `padding_color` | 19 of 43 | no | — |
| `content_fill_color` | `WidgetScrollPane`, `WidgetTransformPane` | yes, [:3614](../../source/widget/WidgetToGraphics.jl#L3614) and [:3866](../../source/widget/WidgetToGraphics.jl#L3866) | the `background_color` of the projection |
| `content_fill_color` | `WidgetText`, `WidgetShell`, `WidgetTitlePane` | no | — |
| `title_fill_color` | `WidgetTitlePane` | no | — |
| `text_style` | `WidgetLabel` only | yes, [:921-923](../../source/widget/WidgetToGraphics.jl#L921-L923) | the `text` of the projection |
| `variant` | `WidgetCard`, `WidgetBadge`, `WidgetAlert` | yes | not allowed: a `Symbol` with a default |

- The only code that draws the three box colors is `_push_box_rects!`
  ([WidgetToGraphics.jl:507](../../source/widget/WidgetToGraphics.jl#L507)).
  Commit `641b2e60` of 2026-06-13, the shadcn restyle, removed its eight
  callers. The widgets still reserve the space of the margin, the border and the
  padding.
- `text_style` takes three forms: `nothing`, a `StyleText` with font and color,
  or a bare `StyleColor`. The bare color keeps the font of the theme
  ([WidgetDocument.jl:40-48](../../source/widget/WidgetDocument.jl#L40-L48)).
- The values of `variant` are `:card`, `:tinted`, `:muted` and `:plain` on
  `WidgetCard`; `:default`, `:secondary`, `:destructive` and `:outline` on
  `WidgetBadge`; `:default` and `:destructive` on `WidgetAlert`. A variant
  selects style fields of the projection, so it follows the theme. `:plain` draws
  no surface.
- 24 widgets have no color field on the document.

### 3.4 Colors that no layer controls

These colors are constants in printer code. No theme, factory or caller can
change them.

| Color | Where | Used by |
| --- | --- | --- |
| button shadow, black at 8% | [WidgetToGraphics.jl:1289](../../source/widget/WidgetToGraphics.jl#L1289) | `WidgetButton` |
| dialog scrim, black at 40% | [:1604](../../source/widget/WidgetToGraphics.jl#L1604) | `WidgetDialog` |
| image placeholder, black at 8% | [:646](../../source/widget/WidgetToGraphics.jl#L646) | `WidgetLabel`, `WidgetButton` |
| `_WT_HL_COLOR`, selection band, blue at 25% | [:5840](../../source/widget/WidgetToGraphics.jl#L5840) | `WidgetTable`, `WidgetTree`, [WidgetTableList.jl:123](../../source/widget/WidgetTableList.jl#L123) |
| `_WT_HOVER_COLOR`, hover band, blue at 13% | [:5843](../../source/widget/WidgetToGraphics.jl#L5843) | `WidgetTable`, `WidgetTree`, `WidgetList` |
| `SELECTION_RING_COLOR`, ring around a whole selected object, fixed blue | [SelectionRing.jl:9](../../source/graphics/SelectionRing.jl#L9) | `WidgetText` ([:1066](../../source/widget/WidgetToGraphics.jl#L1066)), `WidgetComposite`, `WidgetTabbedPane`, `WidgetCard`, every layout |
| knob, `color_white` | the factory | `WidgetSwitch`, `WidgetSlider` |

Two more colors are outside the widget model:

- The backend clears the window to a fixed color, and the theme can not change
  it ([QtenvWindow.jl:30-44](../../../omnet-julia/source/qtenv/QtenvWindow.jl#L30-L44)).
- The fault log and the gesture log overlays have a `background` field with a
  fixed default. They are decorators, not widgets, and they keep one color in
  every theme on purpose.

### 3.5 States

Each printer selects the color for a state in its own code. Where two states
meet, the order is the same in every widget: disabled, then pressed, then
checked or selected, then hovered, then normal.

| Widget | Order in the code |
| --- | --- |
| `WidgetButton` ([:1277-1282](../../source/widget/WidgetToGraphics.jl#L1277-L1282)) | disabled, pressed, hovered, normal |
| `WidgetToggle`, `WidgetSwitch` | disabled, on, off |
| `WidgetCheckbox`, `WidgetRadioGroup`, `WidgetToggleGroup` | disabled, checked or selected, normal |
| `WidgetMenuItem` | a disabled item has no hover surface; else hovered, normal |
| `WidgetList` | selected, hovered, normal. A disabled list only loses the hover. |
| `WidgetTable`, `WidgetTree` | the selection band covers the hover band. No disabled color. |
| `WidgetSelect`, `WidgetSpinBox`, `WidgetTextarea`, `WidgetSlider` | disabled, normal |
| `WidgetText`, `WidgetOption` | no state color. A disabled text box looks like an enabled one. |

Two sets of colors mark a hovered thing: `theme.accent` for the button and the
menu item, and the constant `_WT_HOVER_COLOR` for the list, the table and the
tree.

Four colors mark a selected thing:

1. the focus ring, `theme.ring`;
2. the ring around a whole selected object, the constant `SELECTION_RING_COLOR`;
3. the selected row of a list, `theme.accent`;
4. the selected row of a table or a tree, the constant `_WT_HL_COLOR`.

### 3.6 Colors that upstream projections write

An upstream projection makes widget documents. It has no theme, because the
theme exists only in `WidgetToGraphics`, which runs after it. So each upstream
projection that needs a color writes a constant.

| Projection | Color | Effect |
| --- | --- | --- |
| [ConversationToWidget.jl:63-75](../../source/conversation/ConversationToWidget.jl#L63-L75) | role colors indigo, cyan and slate; `_ERROR_STYLE` in `color_destructive` | drawn, the same in every theme |
| [AssistantToWidget.jl:60-65](../../source/assistant/AssistantToWidget.jl#L60-L65) | `padding_color = _WHITE` on four scroll panes | not drawn. The panes show `theme.background`. |
| `ObjectToWidget.jl:70`, `ObjectFieldToWidget.jl:82` | text in `color_default`, which is black | drawn, black in every theme |
| omnet [LogView.jl:181-185](../../../omnet-julia/source/presentation/capture/LogView.jl#L181-L185) | a severity color as a bare `StyleColor` in `text_style` | drawn, the same in every theme |
| omnet `ConfigurationFormToWidget.jl:138`, `SimulationWorkflowToWidget.jl:338`, `:540`, `:605` | `border_color` on `WidgetText` | not drawn |
| omnet `ConfigurationFormToWidget.jl:161` | a red `text_style` on a note | drawn |
| the examples | `border_color`, eight times | not drawn |
| the examples | `content_fill_color` on a scroll pane, four times | drawn |

In total, code gives a color keyword to a widget 26 times, and 16 of these have
no effect.

omnet-julia also gives the theme to projections that are not widget
projections. `build_module_appearance_graphics(theme = nothing)` uses black on
white when it gets no theme
([ModuleAppearanceToGraphics.jl:135-139](../../../omnet-julia/source/presentation/module/ModuleAppearanceToGraphics.jl#L135-L139)),
and `SimulationTopologyToWidget` calls it with no theme.

### 3.7 What `nothing` means today

| Place | `nothing` means |
| --- | --- |
| `text_style` of `WidgetLabel`, `content_fill_color` of a scroll pane | the style field of the projection |
| the three box colors, in `_push_box_rects!` that no code calls | draw nothing |
| the `border` argument of `_push_panel!`, from the card, the badge and the toggle | draw no outline |
| `border_color` of `GraphicsRect` | transparent ([GraphicsDocument.jl:105](../../source/graphics/GraphicsDocument.jl#L105)) |
| `fill_color` of `TextString` | no fill ([TextDocument.jl:117](../../source/text/TextDocument.jl#L117)) |
| the fields of `ChartStyle`, `color` of `SequenceChartAxis` | "the projection's theme default, resolved at print time" ([ChartDocument.jl:42-44](../../source/chart/ChartDocument.jl#L42-L44)) |
| the `theme` argument in omnet-julia | the default theme of the factory ([WorkbenchRender.jl:402-404](../../../omnet-julia/source/presentation/workbench/WorkbenchRender.jl#L402-L404)), or black on white in `build_module_appearance_graphics` |
| a style field of a widget projection | not used: every style field has a value |

On a widget document, `nothing` means "the projection field" in the fields that
are drawn, and "draw nothing" in the fields that are not drawn.

### 3.8 The defects

1. No code draws `margin_color`, `border_color` and `padding_color` on 19
   widgets, and 16 call sites set them.
2. `content_fill_color` works on two of five widgets. `title_fill_color` never
   works.
3. Seven colors are constants in printer code (§3.4).
4. Four colors mark a selected thing, and two sets of colors mark a hovered
   thing (§3.5).
5. `WidgetText`, `WidgetOption`, `WidgetList`, `WidgetTable` and `WidgetTree`
   have no disabled look.
6. A projection that a caller builds by hand gets `color_white`, not a color of
   the theme.
7. One name of a style field means different parts, and one part has many names
   (§3.2).
8. An upstream projection can not get a color of the theme, so it writes a
   constant (§3.6).
9. The theme has no token for a warning, a success, a shadow, a scrim, a
   selection band, a hover band or a knob.
10. Only `WidgetLabel` can change the text color of one instance.
11. Two style fields and one theme token are never read.
12. The border width has two sources: the `border` inset of the document, which
    `_push_box!` reads for `WidgetText`, and the width of the `StyleStroke` on
    the projection, which the other widgets read.
13. [widget.md](../../documentation/package/widget/widget.md) "Shared visual
    fields" still describes the box colors as boxes that the renderer draws.

## 4. The target model

### 4.1 Three layers

| | Theme | Widget projection | Widget document |
| --- | --- | --- | --- |
| Holds | colors with names that give their meaning | one style field for each part and state that it draws | a tone or a variant; an override for one part |
| Scope | every widget that one factory builds | every widget of one type that this projection prints | one widget |
| Set by | the application | the factory, from the theme; or a caller | the author, or an upstream projection |
| Follows a change of theme | it is the theme | yes, when the factory fills it | the tone and the variant: yes; the override: no |
| Reads | nothing | the theme, in its constructor only | nothing |

The rules of the model:

1. Only a projection constructor reads the theme. A printer body reads style
   fields and the document.
2. Every color that a printer draws comes from a style field or from an override
   on the document. The constants of §3.4 become style fields, and the factory
   fills them from tokens.
3. A color style field has no literal default in its struct. It gets its value
   from the theme or from the caller (D7).
4. A widget document holds no theme and no token name.

### 4.2 The order of resolution

For one part P of a widget w in state S, printed by projection p:

1. If w has an override for P that is not `nothing`, the printer uses it. §4.5
   and D4 give the rule for the states.
2. Else the printer uses the style field of p for P that the variant or tone of
   w and the state S select. A projection that has one field for P in every
   variant uses that field.

The value of a style field comes from the caller that built p, if the caller
gave one. Else it comes from the factory: a token, or a color derived from
tokens. There is no later fallback, and no printer falls back to a constant.

### 4.3 What `nothing` means

| Place | `nothing` means |
| --- | --- |
| theme token | not allowed. A theme gives every token. |
| projection style field | this look draws nothing for this part: no shadow, no outline, no fill. The printer adds no element. |
| document override | no override. The style field of the projection applies. |
| document variant or tone | not allowed. The field is a `Symbol` with a default. |

A color with alpha 0 is not `nothing`. The printer draws it, and it costs one
element. To draw no surface on one widget, the document selects a variant whose
style field is `nothing`, as `WidgetCard` does with `:plain`. An override can not
remove a part. D3 asks whether it must.

This table matches the document fields that work today: `text_style`,
`content_fill_color` and `ChartStyle`. The box colors are the only document
fields where `nothing` meant "draw nothing", and no code draws them.

### 4.4 The box model

- **The margin has no color.** The surface of the parent shows through it.
  `margin_color` goes.
- **The border is the outline of the surface.** Its color is the color of the
  outline part: the override, else the style field. D8 asks where its width
  comes from.
- **The padding is part of the surface.** The fill of the surface covers the
  padding and the content. `padding_color` and `content_fill_color` become one
  override for the surface part.
- A widget with two surfaces names each part. `WidgetTitlePane` has a title
  surface and a content surface.

### 4.5 States

States select style fields, as they do today. Where two states meet, the order
is: disabled, pressed, checked or selected, hovered, normal. §3.5 shows that the
code follows this order today. The model writes it down once.

Two rules are new:

1. Every interactive widget has a disabled look (defect 5).
2. One token marks a selection and one token marks a hover, in every widget
   (defect 4).

D4 decides how an override and a state combine. Example: a button has a red
surface override. The question is what the button shows when the pointer is on
it.

### 4.6 How one widget gets different colors

From the widest scope to the narrowest:

| Scope | Mechanism | Follows a change of theme | Today |
| --- | --- | --- | --- |
| every widget of an application | give a theme to the factory | it is the theme | works, for example the Qtenv window |
| the widgets in one part of the tree | a second factory with another theme, joined with a `NestingProjection` or given to one pane | yes, its own theme | works only where the tree already changes projection |
| every widget of one type | a caller gives a projection its own style fields, or a person edits them with `ProjectionConfiguringProjection` | yes, when the caller derives them from the theme | works, but a projection built by hand loses the theme (defect 6) |
| one widget | a tone or a variant on the document | yes | three widgets have a variant |
| one part of one widget | an override on the document | no | works in two fields |

No widget document selects a theme for its children. D10 asks whether one must.

### 4.7 Colors from an upstream projection

An upstream projection gives the meaning of a widget, not its color. For
example, `LogView` gives a warning line the tone `:warning`, and the widget
projection draws the line in the warning color of the theme. When the theme
changes, the log colors change with it. An override is for a color that has no
meaning in the theme, for example a color that the user selected. D5 and D6 are
the decisions.

### 4.8 Out of scope

- The color that the backend clears the window to. A `WidgetShell` that fills
  the window covers it.
- The fault log and the gesture log overlays.
- The colors of the other domains: text, syntax, charts. They have their own
  style fields. §3.7 lists their `nothing` rules only for comparison.
- Fonts and sizes. The same three layers hold them, but this plan covers colors.

## 5. Decisions

Each decision gives the options and a recommendation. The recommendations are
mine. None of them is decided.

### D1. The names of the style fields

- **(a)** Keep the names, and fix only the collisions of §3.2.
- **(b)** Use one scheme in every projection: `<part>_<state>_<kind>`. The kind
  is `color` for a `StyleColor`, `stroke` for a `StyleStroke` and `text` for a
  `StyleText`. The normal state has no state word. Parts: `surface`, `outline`,
  `label`, `focus_ring`, `shadow`, `divider`, `chevron`, `track`, `thumb`,
  `knob`, `indicator`, `row`. States: `hovered`, `pressed`, `checked`,
  `selected`, `disabled`. `WidgetButton` then has `surface_color`,
  `surface_hovered_color`, `surface_pressed_color`, `surface_disabled_color`,
  `outline_stroke`, `label_text`, `label_disabled_text`, `shadow_color` and
  `focus_ring_stroke`.
- **(c)** A compound type for each state, with a fill, an outline and a text,
  and one field for each state: `normal`, `hovered`, `pressed`, `disabled`.

**Recommendation: (b).** One part then has one name in every widget. So an
override (D2) can have the same name as the style field that it replaces, and a
test can check that every interactive widget has its `_disabled_` fields. (c) is
shorter, but most states change only one of the three aspects.

### D2. The form of the override on the document

- **(a)** Flat fields on each widget, for example `surface_color`,
  `outline_color` and `text_color`, each `nothing` by default.
- **(b)** One field `style` on each widget. It holds `nothing` or a
  `WidgetStyle` document whose fields are `nothing` by default, in the form of
  `ChartStyle`.

**Recommendation: (b).** It costs one cell per widget instead of three to six.
`ChartStyle` and `SequenceChartStyle` already use this form. Another part that
an override can cover is one field in one struct, not a field in 43 structs. A
person can edit a `WidgetStyle` in the editor like any other document, and many
widgets can share one `WidgetStyle`. The cost: a call site writes
`style = WidgetStyle(surface_color = …)`.

### D3. The parts that an override covers

- **(a)** The surface, the outline and the text, on every widget.
- **(b)** Every part that the widget draws.

**Recommendation: (a).** The call sites of §3.6 set only these three parts.
Another part can come when a caller needs it. An override can not remove a part;
a variant does that, as `:plain` does on `WidgetCard`.

### D4. An override and the states

- **(a)** The override replaces the part in every state. A hovered or pressed
  widget shows no change.
- **(b)** The override replaces the normal state only. The other states use the
  style fields, so a red button turns to the hover color of the theme.
- **(c)** The printer draws the hovered and the pressed state as a translucent
  layer over the resolved surface, in a color from the theme. Two tokens hold
  these layers. The disabled state keeps its own style fields and ignores the
  override.

**Recommendation: (c).** It is the only option where an override and a hover
both show. It also replaces the hover and pressed fields of each widget, and the
constant `_WT_HOVER_COLOR`, with two tokens. The cost: the hover look of the
button, the menu item, the list, the table and the tree changes, and the images
of the examples change with it.

### D5. A tone for the meaning of a widget

The `variant` fields of today answer two questions: how loud a surface is
(`WidgetCard`), and what a widget means (`:destructive` on `WidgetAlert`).

- **(a)** Keep one `variant` per widget, and add values where a caller needs
  them.
- **(b)** Add one field `tone` to the widgets that can carry a meaning: the
  label, the badge, the alert, the card and the button. It has one set of
  values in every widget: `:neutral`, `:primary`, `:destructive`, `:warning`,
  `:success`. Each value selects a token pair of the theme, for example
  `destructive` and `destructive_foreground`. `variant` then answers only how
  loud a surface is. The theme gets the tokens `warning`,
  `warning_foreground`, `success` and `success_foreground`.

**Recommendation: (b).** `LogView` and `ConversationToWidget` can then mark an
error or a warning, and the colors follow the theme. One question stays open:
the role colors of the conversation (user, assistant) are categories, not
meanings. Either the theme gets a list of category colors, like the color cycle
of a chart, or they stay overrides.

### D6. How an upstream projection gets a color of the theme

- **(a)** Only through a tone or a variant (D5). The upstream projection never
  gets the theme.
- **(b)** The upstream projection also takes the theme as a constructor argument
  and writes resolved colors into the document.

**Recommendation: (a) for widget documents.** With (b) the theme is in two
places, and another theme needs a new upstream projection too. (b) stays correct
for a projection that draws graphics itself, such as
`build_module_appearance_graphics`. There the caller must give the theme, and
`nothing` must not select black on white.

### D7. A caller that builds one projection

- **(a)** Each widget projection gets a constructor that takes the theme, for
  example `WidgetScrollPaneToGraphicsCanvas(theme; measure, font, chrome = false)`.
  The factory calls these constructors.
- **(b)** The factory takes changes for one widget type:
  `WidgetToGraphics(font; theme, changes = …)`.
- **(c)** The caller builds the factory and sets the cell of one style field.

**Recommendation: (a).** It removes the literal defaults (defect 6). It also
puts the mapping from token to style field beside each struct, with keyword
arguments. Today that mapping is a positional table of about 40 calls, where two
swapped arguments of the same type give no error.

### D8. The width of the border

- **(a)** The `border` inset of the document gives the width, and the projection
  gives only the color.
- **(b)** The `StyleStroke` of the projection gives the width and the color. The
  `border` inset of the document only reserves space.

**No recommendation yet.** This is a layout question more than a color question.
It needs its own check of which widgets read which source.

### D9. The selection ring of the layouts

Layouts are not widgets and get no theme. They draw `SELECTION_RING_COLOR`.

- **(a)** The widget factory also builds the layout projections from the theme.
  The factory already registers `GridLayout`
  ([WidgetToGraphics.jl:7017](../../source/widget/WidgetToGraphics.jl#L7017)).
  Each layout projection gets a style field for its ring.
- **(b)** Keep the constant for the layouts, and make it the default of a theme
  token that every whole-selection ring uses.

**Recommendation: (a).** A ring around a selected object then has one color in a
widget and in a layout, and the theme sets it.

### D10. A theme for a part of the tree

- **(a)** No document selects a theme. A part of the tree gets another theme only
  where the application joins a second factory (§4.6).
- **(b)** A widget, for example `WidgetShell`, holds the name of a theme, and the
  factory resolves it.

**Recommendation: (a),** until a real case needs (b). With (b) a document holds a
theme name, and the printer context must carry the themes.

## 6. Steps

The steps start after the owner decides §5. Each step is one commit, and the
targeted tests run after each step.

- [ ] 1. Record the decisions of §5 in this plan.
- [ ] 2. Theme: add the tokens that the decisions need, for example the shadow,
      the scrim, the selection band, the hover and pressed layers, the knob,
      `warning` and `success`. Remove `inset`. Change
      `build_qtenv_widget_theme` in omnet-julia, which calls the positional
      constructor.
- [ ] 3. Projections: give each widget projection a constructor that takes the
      theme (D7), with the names of D1. Move the constants of §3.4 into style
      fields. Remove the two style fields that are never read.
- [ ] 4. States: give every interactive widget a disabled look, and use one
      selection token and one hover token everywhere (D4).
- [ ] 5. Documents: replace `margin_color`, `border_color`, `padding_color`,
      `content_fill_color` and `title_fill_color` with the override of D2. Add
      `tone` (D5). Change the 26 call sites in both repositories. For each of the
      16 call sites that have no effect today, check whether the color is still
      wanted. For example, `AssistantToWidget` asks for white panes but shows
      `theme.background`.
- [ ] 6. Upstream projections: `ConversationToWidget`, `LogView`,
      `ObjectToWidget` and `ConfigurationFormToWidget` use tones or overrides.
- [ ] 7. Layouts: the selection ring takes its color from the theme (D9).
- [ ] 8. Documentation: write the "Theme" and "Shared visual fields" sections
      of [widget.md](../../documentation/package/widget/widget.md) from §4.

## 7. Verification

- **A test with a probe theme.** Each token of the probe theme is a color that no
  constant in the code uses. The test prints every widget example with this
  theme and collects the color of every element. Each color must be a token, a
  color derived from tokens, or an override that the example sets. A constant in
  a printer fails the test. This test keeps defect 3 from coming back.
- **A test of the order of §4.2** on one widget: an override, a variant, the
  default, and each state.
- The widget tests under `test/substrate/projection/`. A change to the number of
  fields of a widget document changes the pass counts, because the tests check
  each cell.
- The images of the examples change where D4 changes the hover look. Make new
  reference images and compare them by eye.

## Appendix A. The style fields of each widget projection

Each entry is `field ← source`. `(t, w)` is `StyleStroke(theme.t, theme.w)`, and
`(f, t)` is `StyleText(theme.f, theme.t)`. A bare name is a theme token.

| Widget | Style fields |
| --- | --- |
| `WidgetInsertion` | `text` ← `body_text` |
| `WidgetLabel` | `text` ← `body_text` |
| `WidgetText` | `text` ← `body_text`; `background_color` ← `background`; `border_color` ← `input`; `ring_color` ← `ring`. The whole-selection ring is the constant `SELECTION_RING_COLOR`. |
| `WidgetCheckbox` | `checked_color` ← `primary`; `check` ← (`primary_foreground`, `stroke`); `background_color` ← `background`; `outline` ← (`input`, `stroke`); `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetButton` | `label` ← `label_text`; `background_color` ← `background`; `hover_color` ← `accent`; `active_color` ← `muted`; `border` ← (`border`, `border_width`); `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring`. The shadow is a constant. |
| `WidgetTooltip` | `text` ← (`font`, `popover_foreground`); `surface_color` ← `popover`; `border` ← (`border`, `border_width`) |
| `WidgetContextMenu`, `WidgetMenu`, `WidgetToolbar` | no color |
| `WidgetComposite` | no style field. The whole-selection ring is the constant `SELECTION_RING_COLOR`. |
| `WidgetDialog` | `title` ← `title_text`; `body` ← `body_text`; `card_color` ← `card`; `border` ← (`border`, `border_width`). The scrim is a constant. |
| `WidgetMenuItem` | `text` ← `body_text`; `disabled_foreground` ← `muted_foreground`; `hover_color` ← `accent` |
| `WidgetShell` | `background_color` ← `background` |
| `WidgetTitlePane` | `title_text` ← (`font_bold`, `foreground`); `content_text` ← (`font`, `card_foreground`) |
| `WidgetSplitPane` | `splitter` ← (`border`, `border_width`) |
| `WidgetTabbedPane` | `track_color` ← `muted`; `active_color` ← `background`; `active_foreground` ← `foreground`; `inactive_foreground` ← `muted_foreground`. The whole-selection ring is a constant. |
| `WidgetScrollPane` | `background_color` ← `background`, struct default `color_white` |
| `WidgetTransformPane` | `background_color` ← `background` |
| `WidgetStatusBar` | `text` ← `caption_text`; `background_color` ← `muted` |
| `WidgetScrollBar` | `track_color` ← `muted`; `thumb_color` ← `border` |
| `WidgetBadge` | `default_fill` ← `primary`; `default_foreground` ← `primary_foreground`; `secondary_fill` ← `secondary`; `secondary_foreground` ← `secondary_foreground`; `destructive_fill` ← `destructive`; `destructive_foreground` ← `destructive_foreground`; `outline_fill` ← `background`; `outline_foreground` ← `foreground`; `outline_border` ← `border` |
| `WidgetSeparator` | `stroke` ← (`border`, `border_width`) |
| `WidgetCard` | `title_text` ← (`font_bold`, `foreground`); `description_text` ← (`font_small`, `muted_foreground`); `content_text` ← (`font`, `card_foreground`); `footer_text` ← (`font_small`, `muted_foreground`); `surface_color` ← `card`; `tint_color` ← `color_interpolate(muted, background, 0.5)`; `muted_color` ← `muted`; `border` ← (`border`, `border_width`); `chevron` ← (`muted_foreground`, `stroke`). The whole-selection ring is a constant. |
| `WidgetSwitch` | `knob_color` ← `color_white`; `knob_border` ← (`border`, `border_width`); `on_color` ← `primary`; `off_color` ← `track_off`; `disabled_color` ← `muted`; `ring_color` ← `ring` |
| `WidgetProgress` | `track_color` ← `muted`; `fill_color` ← `primary` |
| `WidgetSlider` | `knob_color` ← `color_white`; `knob_border` ← (`primary`, `stroke`); `track_color` ← `muted`; `fill_color` ← `primary`; `disabled_color` ← `muted`; `ring_color` ← `ring` |
| `WidgetRadioGroup` | `label_text` ← (`font`, `foreground`); `button_fill` ← `background`; `selected_ring` ← (`primary`, `stroke`); `unselected_ring` ← (`input`, `stroke`); `selected_color` ← `primary`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetAvatar` | `initials` ← (`font`, `muted_foreground`); `background_color` ← `muted` |
| `WidgetAlert` | `description_text` ← (`font_small`, `muted_foreground`); `background_color` ← `background`; `default_title_color` ← `foreground`; `default_border_color` ← `border`; `destructive_color` ← `destructive` |
| `WidgetSkeleton` | `fill_color` ← `muted` |
| `WidgetHighlight` | `fill_color` ← `primary` at 25%; `border_color` ← `primary` |
| `WidgetToggle` | `border` ← (`border`, `border_width`); `pressed_fill` ← `accent`; `pressed_foreground` ← `accent_foreground`; `released_fill` ← `background`; `released_foreground` ← `foreground`; `disabled_fill` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetToggleGroup` | `track_color` ← `muted`; `selected_fill` ← `background`; `selected_foreground` ← `foreground`; `unselected_foreground` ← `muted_foreground`; `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetSelect` | `text` ← `body_text`; `background_color` ← `background`; `border` ← (`input`, `border_width`); `chevron` ← (`muted_foreground`, `stroke`); `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetOption` | `text` ← `body_text`; `background_color` ← `background` |
| `WidgetSpinBox` | `text` ← `body_text`; `background_color` ← `background`; `border` ← (`input`, `border_width`); `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `stepper_color` ← `foreground`; `ring_color` ← `ring` |
| `WidgetList` | `text` ← `body_text`; `background_color` ← `background`; `border` ← (`border`, `border_width`); `selected_color` ← `accent`; `selected_foreground` ← `accent_foreground`. The hover band is the constant `_WT_HOVER_COLOR`. |
| `WidgetTextarea` | `text` ← `body_text`; `background_color` ← `background`; `border` ← (`input`, `border_width`); `disabled_color` ← `muted`; `disabled_foreground` ← `muted_foreground`; `ring_color` ← `ring` |
| `WidgetAccordion` | `title_text` ← (`font_bold`, `foreground`); `body_text` ← (`font_small`, `muted_foreground`); `rule` ← (`border`, `border_width`); `chevron` ← (`muted_foreground`, `stroke`) |
| `WidgetTable` | `cell_text` and `header_text`, never read; `rule` ← (`border`, `border_width`); `header_fill` ← `muted`. The selection and hover bands are constants. |
| `WidgetTree` | `label_text` ← (`font`, `foreground`); `icon_text` ← (`font`, `muted_foreground`); `chevron` ← (`muted_foreground`, `stroke`). The selection and hover bands are constants. |
