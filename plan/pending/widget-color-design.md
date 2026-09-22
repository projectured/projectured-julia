# Widget colors: where each color comes from

**Status (2026-09-22): DECIDED.** Nothing is implemented. §3 records the
present state, §4 describes the target model, and §5 records the decisions. The
owner decided every decision of §5 on 2026-09-22:

- Every part of the structure of a widget has its own color (§4.4, D3).
- A part becomes transparent with `color_transparent` (§4.3, D3).
- The color overrides of a widget are in one `style` field (D2).
- Every widget that the factory prints on its own has the box insets, with
  three exceptions (D11).
- No new type holds an inset and its color together (D12).
- For D1, D4, D6 to D10 and the decorations of D3, the owner accepted the
  recommendation of this plan.
- The colors of another domain, such as a conversation, belong to the
  projection that makes widgets from it, not to the widget theme (§4.7).
- A widget has no `tone`. A `variant` value exists only where the widget library
  draws the widget differently with no knowledge of a domain (D5).

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
   instance it can hold a **variant**, which selects style fields of the
   projection, and an **override**, which is a color for one part. A domain
   gives its meanings their colors in its own projection (§4.7, D5).

**Every part has a color.** Each part that has a meaning in the structure of a
widget, and a size that a caller can control, has its own color: the margin, the
border, the padding, the content, and the regions of one widget type, such as
the tab strip. A part that the look does not show is transparent, and it costs
no element.

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
| projection style field | not allowed |
| document override | no override, so the projection field applies |

The one way to draw no fill is the global color `color_transparent`, in every
layer. The code that paints a part adds no element for a transparent fill
(§4.3).

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
| **part** | a region of a widget that has a meaning in its structure and its own size: the margin, the border, the padding, the content, or a region of one widget type, such as the tab strip or the knob. Every part has a color (§4.4). |
| **surface** | the padding and the content of a widget together |
| **decoration** | a mark of a state that the printer draws over the parts: the focus ring, the hover and pressed layers, the selection band, the shadow, the scrim |
| **state** | a field of the widget document that the actions of the user change: `enabled`, `hovered`, `pressed`, checked, the selection, the active tab |
| **variant** | a `Symbol` field of the widget document that selects one set of style fields, for example `WidgetCard.variant = :muted` |
| **override** | a field of the widget document that holds a color for one part of this one widget |
| **transparent** | the color with alpha 0, as the planned global `color_transparent`. A part in this color adds no element (§4.3). |
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
  padding. `_push_box_rects!` paints the margin, the border and the padding as
  separate bands with square corners.
- The Lisp original has the same fields on `widget/base`: `margin-color`,
  `border-color` and `padding-color`, and `content-fill-color` on some widgets.
  There `nil` means "draw nothing", and `widget/make-surrounding-graphics`
  paints each part that has a color.
- `_push_box!` paints the surface of `WidgetText` over the whole box, the margin
  included
  ([WidgetToGraphics.jl:258-264](../../source/widget/WidgetToGraphics.jl#L258-L264)).
  So the margin of a text box shows the surface color, not the parent.
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

**The transparent color has no name.** The code writes it as
`StyleColor(0.0, 0.0, 0.0, 0.0)` in 12 places. Three of them give it a local
name: `_WT_HIT_COLOR`
([WidgetToGraphics.jl:5847](../../source/widget/WidgetToGraphics.jl#L5847)),
`_transparent`
([TextToGraphics.jl:741](../../source/text/TextToGraphics.jl#L741)) and
`_NO_WASH` ([MathToGraphics.jl:1679](../../source/math/MathToGraphics.jl#L1679)).

**A transparent rect catches the pointer.** A container sends a press to a child
only over an element that the child drew. `hit_element_at` tests the position of
a rect and not its alpha
([GraphicsDocument.jl:676](../../source/graphics/GraphicsDocument.jl#L676)). The
table, the tree, the fold column of the card and `WidgetTableList` push a
transparent rect for this reason
([WidgetToGraphics.jl:4326](../../source/widget/WidgetToGraphics.jl#L4326),
[:6166](../../source/widget/WidgetToGraphics.jl#L6166),
[:6768](../../source/widget/WidgetToGraphics.jl#L6768),
[WidgetTableList.jl:167](../../source/widget/WidgetTableList.jl#L167)).

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

An upstream projection makes widget documents from the documents of another
domain, for example a conversation. The colors of that domain belong to the
upstream projection, as the colors of JSON belong to `JsonToSyntax`. The
projection gives them to the widgets as overrides, and it does not read the
widget theme (§4.7).

`ObjectToWidget` holds its color in a style field, `style::StyleText`. The other
upstream projections of the table hold their colors as module constants, and a
caller can not change them. For example, the projection structs of
`ConversationToWidget` are empty, such as
`struct ConversationPartToWidget <: Projection end`. This is a defect of each of
those slices, and this plan does not fix it. The table lists what they write,
because step 6 moves these call sites to the new override form.

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
8. Some upstream projections hold their colors as module constants, not as
   style fields (§3.6). This defect is outside the widget model, and this plan
   does not fix it.
9. The theme has no token for a shadow, a scrim, a selection band, a hover band
   or a knob.
10. Only `WidgetLabel` can change the text color of one instance.
11. Two style fields and one theme token are never read.
12. The border width has two sources: the `border` inset of the document, which
    `_push_box!` reads for `WidgetText`, and the width of the `StyleStroke` on
    the projection, which the other widgets read.
13. [widget.md](../../documentation/package/widget/widget.md) "Shared visual
    fields" still describes the box colors as boxes that the renderer draws.
14. The transparent color has no name: 12 literals and three local names
    (§3.4).
15. One shell can not change or remove its fill. Every shell that has a size
    on both axes paints `theme.background`
    ([WidgetToGraphics.jl:2152](../../source/widget/WidgetToGraphics.jl#L2152)).
    The page area of `WidgetTabbedPane` is not a part: its printer paints
    only the tab strip and the active tab
    ([:3056](../../source/widget/WidgetToGraphics.jl#L3056),
    [:3061](../../source/widget/WidgetToGraphics.jl#L3061)). So no theme and no
    override can give the page a color.
16. The margin of `WidgetText` shows its surface color, because `_push_box!`
    fills the whole box (§3.3).

## 4. The target model

### 4.1 Three layers

| | Theme | Widget projection | Widget document |
| --- | --- | --- | --- |
| Holds | colors with names that give their meaning | one style field for each part and state that it draws | a variant; an override for one part |
| Scope | every widget that one factory builds | every widget of one type that this projection prints | one widget |
| Set by | the application | the factory, from the theme; or a caller | the author, or an upstream projection |
| Follows a change of theme | it is the theme | yes, when the factory fills it | the variant: yes; the override: no |
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
5. The transparent color is the global `color_transparent` in `Color.jl`, beside
   `color_white`. It replaces the 12 literals and the three local names of §3.4.
6. Every part has a color: a style field on the projection, and an override on
   the document (§4.4). A part that the look does not show has
   `color_transparent`.

### 4.2 The order of resolution

For one part P of a widget w in state S, printed by projection p:

1. If w has an override for P that is not `nothing`, the printer uses it. §4.5
   and D4 give the rule for the states.
2. Else the printer uses the style field of p for P that the variant of
   w and the state S select. A projection that has one field for P in every
   variant uses that field.

The value of a style field comes from the caller that built p, if the caller
gave one. Else it comes from the factory: a token, or a color derived from
tokens. There is no later fallback, and no printer falls back to a constant.

### 4.3 What `nothing` means, and the transparent color

| Place | `nothing` means |
| --- | --- |
| theme token | not allowed. A theme gives every token. |
| projection style field | not allowed. A look that draws no fill for a part gives `color_transparent`. |
| document override | no override. The style field of the projection applies. |
| document variant | not allowed. The field is a `Symbol` with a default. |

So `nothing` has one meaning in the model: this layer sets no value, and the
next layer applies. Only a document override can be `nothing`.

This table matches the document fields that work today: `text_style`,
`content_fill_color` and `ChartStyle`. The box colors are the only document
fields where `nothing` meant "draw nothing", and no code draws them.

**The transparent color is the one way to draw no fill.** It is a color, so it
needs no new kind of value:

- A projection style field gives `color_transparent` for a look that draws no
  fill for a part. `WidgetCard` `:plain` becomes a variant whose surface is
  `color_transparent`.
- An override gives `color_transparent` to remove the fill of one widget, for
  example of one shell.

**The printer adds no element for a transparent fill.** So a transparent part
costs nothing, which is the reason that `WidgetCard` gives for `:plain` today
([WidgetToGraphics.jl:4386](../../source/widget/WidgetToGraphics.jl#L4386)).
Three rules make the skip correct:

1. Only the code that paints a part skips the element: `_push_panel!` and the
   code like it. `GraphicsRect` and the hit test do not change. A hit target
   (§3.4) stays a separate `GraphicsRect` that the printer always pushes. The
   backend can skip the draw of any rect with alpha 0, because the draw does not
   change the hit test.
2. The code skips the element only when the fill is transparent and the part has
   no visible outline. One `GraphicsRect` draws the fill and the outline
   together.
3. The check is exact: the alpha is 0. A color derived from tokens that has a
   very small alpha is still drawn. It is not visible, and it costs one element.

**A transparent surface lets the pointer through.** Where the surface of a
widget is transparent and its content does not cover it, a press on the empty
area does not reach the widget, because the widget drew nothing there. The
press goes to the element below. A widget that must get a press on its empty
area pushes its own hit target.

**A reactive color can change the element list.** When a style field or an
override is a reactive cell, the code that builds the element list reads the
alpha to decide whether to add the element. A change between transparent and a
visible color then builds the list again. A change of `variant` on `WidgetCard`
has the same cost today.

### 4.4 The parts of a widget

**Decided by the owner on 2026-09-22.** Every part that has a meaning in the
structure of a widget, and a size that a caller can control, has its own color.
The rule holds also where the look does not show the part. Its color is then
`color_transparent`, and it costs no element (§4.3). The margin is such a part.
A second reason for the rule: a developer can give each part a color to see the
layout.

**The box parts.** Every widget that the factory prints on its own has the box
insets, except `WidgetHighlight` (D11). The insets and the colors stay separate
fields (D12). Every widget with the box insets has four parts, from the outside
in:

| Part | Size | Default color |
| --- | --- | --- |
| margin | the `margin` inset | `color_transparent` |
| border | the `border` inset (D8) | the outline token of the widget, for example `theme.border` or `theme.input`. `color_transparent` for a widget that shows no outline. |
| padding | the `padding` inset | the surface token of the widget, for example `theme.card` |
| content | the size of the content | the same surface token as the padding |

The padding and the content have the same default color, so the widget shows one
surface. An override on one of them makes the two areas visible.

**The painter of the box.**

- The printer paints the four parts from the outside in, and skips a
  transparent part (§4.3). With the default colors, the border, the padding and
  the content are one `GraphicsRect` with a fill and an outline, as today. So the
  default look costs no more elements than today.
- `_push_box_rects!` is the start of this painter (§3.3). It needs the corner
  radius, the content part and the skip of a transparent part.
- The surface starts at the border. The margin is outside it, so the defect of
  `WidgetText` (defect 16) goes away.
- With a corner radius, the border, the padding and the content are rounded.
- A translucent color on an inner part must not show the color of an outer part
  through it. So where a color is translucent, the painter paints each part as a
  band, not as rects inside each other.

**The parts of one widget type.** A widget type has more parts where its printer
lays out a region with its own size. Some examples:

| Widget | Parts of its own |
| --- | --- |
| `WidgetShell` | none. Its bands are child widgets with their own parts. |
| `WidgetTabbedPane` | tab strip, tab, active tab, page |
| `WidgetTitlePane` | title bar, content |
| `WidgetSplitPane` | splitter |
| `WidgetScrollBar` | track, thumb |
| `WidgetSwitch`, `WidgetSlider`, `WidgetProgress` | track, indicator, knob |
| `WidgetTable` | header row, row, cell |
| `WidgetList`, `WidgetTree` | row |
| `WidgetCard` | header, body, footer |

Step 4 makes the full list, with one row for each widget type.

**Two parts that this plan names.**

- `WidgetShell` keeps `theme.background` as the default color of its surface.
  One shell becomes transparent with the override `color_transparent`.
- `WidgetTabbedPane` gets a page part, the area below the tab strip. Its factory
  value is `color_transparent`, which keeps the present look. A theme factory or
  an override can give it a color.

**Text and marks.** The text of a part, and a mark in it such as a chevron or a
check, have their own color: the color of a `StyleText` or a `StyleStroke`.

**Decorations are not parts.** The focus ring, the hover and the pressed layers,
the selection band, the shadow and the scrim show a state, not a part of the
structure. They have style fields on the projection, and a document can not
override them (D3).

**Debugging a whole window.** To color one part in every widget of a window, a
developer gives the style field of that part a color at the factory, for example
a red margin for every widget type. No document changes.

### 4.5 States

States select style fields, as they do today. Where two states meet, the order
is: disabled, pressed, checked or selected, hovered, normal. §3.5 shows that the
code follows this order today. The model writes it down once.

Two rules are new:

1. Every interactive widget has a disabled look (defect 5).
2. One token marks a selection and one token marks a hover, in every widget
   (defect 4).

An override and a state combine as D4 (c) says. The printer draws the hovered
and the pressed state as a translucent layer over the surface. So a button with
a red surface override still shows a hover. The disabled state keeps its own
style fields and ignores the override.

### 4.6 How one widget gets different colors

From the widest scope to the narrowest:

| Scope | Mechanism | Follows a change of theme | Today |
| --- | --- | --- | --- |
| every widget of an application | give a theme to the factory | it is the theme | works, for example the Qtenv window |
| the widgets in one part of the tree | a second factory with another theme, joined with a `NestingProjection` or given to one pane | yes, its own theme | works only where the tree already changes projection |
| every widget of one type | a caller gives a projection its own style fields, or a person edits them with `ProjectionConfiguringProjection` | yes, when the caller derives them from the theme | works, but a projection built by hand loses the theme (defect 6) |
| one widget | a variant on the document | yes | three widgets have a variant |
| one part of one widget | an override on the document | no | works in two fields |

No widget document selects a theme for its children (D10).

### 4.7 Colors from an upstream projection

The colors of another domain belong to the projection that makes widgets from
it. `ConversationToWidget` owns the colors of a conversation, and `LogView` owns
the colors of the severities of a log, as `JsonToSyntax` owns the colors of
JSON. Such a projection holds its colors in its own style fields, and it gives
them to the widgets as overrides. It does not read the widget theme (D6).

An application that wants another look gives another style to each of these
projections, and another theme to the widget factory. This is the rule of §3.1
for every projection: another look is another factory.

So the widget theme holds only the colors of the widgets themselves. A domain
can come with its own theme, in the same way as the widget theme: that theme
gives the default style fields of the projections of the domain. Where the
domain needs a color on a widget, its projection overrides the default of the
widget. A widget document carries no meaning of a domain (D5).

### 4.8 Out of scope

- The color that the backend clears the window to. A `WidgetShell` that fills
  the window covers it.
- The fault log and the gesture log overlays.
- The colors of the other domains: text, syntax, charts. They have their own
  style fields. §3.7 lists their `nothing` rules only for comparison.
- Fonts and sizes. The same three layers hold them, but this plan covers colors.

## 5. Decisions

Each decision gives the options, the outcome and the reasons. The owner decided
all of them on 2026-09-22. D5 was opened again and decided a second time on the
same day. Where a decision says "the owner accepted the recommendation", the
outcome is the recommendation of this plan.

### D1. The names of the style fields

- **(a)** Keep the names, and fix only the collisions of §3.2.
- **(b)** Use one scheme in every projection: `<part>_<state>_<kind>`. The kind
  is `color` for a `StyleColor`, `stroke` for a `StyleStroke` and `text` for a
  `StyleText`. The normal state has no state word. The part words are the box
  parts `margin`, `border`, `padding` and `content`; the parts of one widget
  type, such as `tab_strip`, `page`, `splitter`, `track`, `thumb`, `knob`,
  `indicator` and `row`; the marks `label`, `chevron` and `check`; and the
  decorations `focus_ring` and `shadow`. The state words are `hovered`,
  `pressed`, `checked`, `selected` and `disabled`. `WidgetButton` then has
  `margin_color`, `border_color`, `padding_color`, `content_color`,
  `padding_disabled_color`, `content_disabled_color`, `label_text`,
  `label_disabled_text`, `shadow_color` and `focus_ring_stroke`. With D4 (c),
  the hovered and the pressed state need no fields of their own.
- **(c)** A compound type for each state, with a fill, an outline and a text,
  and one field for each state: `normal`, `hovered`, `pressed`, `disabled`.

**Decision: (b).** The owner accepted the
recommendation on 2026-09-22. One part then has one name in every widget. So an
override (D2) can have the same name as the style field that it replaces, and a
test can check that every interactive widget has its `_disabled_` fields. (c) is
shorter, but most states change only one of the three aspects.

The box parts keep the names that the document uses today: `margin_color`,
`border_color` and `padding_color`. `content_color` replaces
`content_fill_color`. The kind word keeps a fill and a text apart:
`content_color` is the fill of the content, and `label_text` is its text.

**What moved this recommendation:** the owner's rule of §4.4. The first version
of this plan had the parts `surface` and `outline`. The four box parts replace
them, because each has its own size. The border is then a band with the width of
the `border` inset, and its color is a fill, not a stroke.

### D2. The form of the override on the document

- **(a)** Flat fields on each widget, for example `margin_color`,
  `border_color`, `padding_color`, `content_color` and `text_color`, each
  `nothing` by default.
- **(b)** One field `style` on each widget. It holds `nothing` or a
  `WidgetStyle` document whose fields are `nothing` by default, in the form of
  `ChartStyle`.

**Decision: (b).** Decided by the owner on 2026-09-22, together with D12. The
reasons follow. Every part has a color (§4.4), so (a) gives each widget
at least four color fields, one for each box part, and more for its own parts
and its text. (b) costs one cell per widget. `ChartStyle` and
`SequenceChartStyle` already use this form. Another part that an override can
cover is one field in one struct, not a field in 43 structs. A person can edit a
`WidgetStyle` in the editor like any other document, and many widgets can share
one `WidgetStyle`. The cost: a call site writes
`style = WidgetStyle(padding_color = …)`.

One detail of (b) is the parts of one widget type. The owner accepted the
recommendation on 2026-09-22: the `style` field takes either a `WidgetStyle` or
the style of the widget type. A
`WidgetStyle` has the box parts and the text, and every widget takes it. The
style of a widget type, for example `WidgetTabbedPaneStyle`, has the same fields
and the parts of that type. So one `WidgetStyle` can color the margins of widgets
of many types.

### D3. The parts that an override covers, and how it removes a fill

**The parts.** Decided by the owner on 2026-09-22: an override can cover every
part of §4.4, the margin included, and the text and the marks in a part. The
first version of this plan recommended only the surface, the outline and the
text. The owner rejected that: every part that has a meaning in the structure
and a size can have a color, also for debugging.

**The decorations.**

- **(a)** A document can not override a decoration. The theme and the projection
  give its color.
- **(b)** A document can override a decoration, as it can override a part.

**Decision: (a).** The owner accepted the
recommendation on 2026-09-22. A decoration shows a state, and one state must look the
same in every widget: a focused widget shows the same ring everywhere.

**How an override removes a fill.** Decided by the owner on 2026-09-22.

- **(a)** The override gives `color_transparent`, and the printer adds no
  element for a transparent fill (§4.3).
- **(b)** A separate marker value, not `nothing` and not a color, that means
  "draw no fill".
- **(c)** A `:plain` variant on each surface widget, as on `WidgetCard`.

**Decision: (a).** The transparent color is a value that `StyleColor` already
has, so the override needs no third kind of value. The only cost of (a) was the
element for an alpha-0 fill, and the printer can skip that element. With (a),
`nothing` keeps one meaning in every layer, and no projection field is
`nothing`. (c) needs a new field on each widget that must become transparent.
The transparent color is a global constant, `color_transparent`.

### D4. An override and the states

- **(a)** The override replaces the part in every state. A hovered or pressed
  widget shows no change.
- **(b)** The override replaces the normal state only. The other states use the
  style fields, so a red button turns to the hover color of the theme.
- **(c)** The printer draws the hovered and the pressed state as a translucent
  layer over the resolved surface, in a color from the theme. Two tokens hold
  these layers. The disabled state keeps its own style fields and ignores the
  override.

**Decision: (c).** The owner accepted the
recommendation on 2026-09-22. It is the only option where an override and a hover
both show. It also replaces the hover and pressed fields of each widget, and the
constant `_WT_HOVER_COLOR`, with two tokens. The cost: the hover look of the
button, the menu item, the list, the table and the tree changes, and the images
of the examples change with it.

### D5. The meaning of a widget

**History.** The owner first accepted (b) on 2026-09-22, and opened the
question again on the same day, for two reasons:

- The first reason for (b) was that `LogView` and `ConversationToWidget` could
  mark an error or a warning with a tone. That reason is gone: these projections
  own their colors (§4.7). The `warning` and `success` tokens came from the log
  view too.
- The owner doubts that any finite list of meanings in the widget library is
  enough.

The `variant` fields of today answer two questions: how loud a surface is
(`WidgetCard`), and what a widget means (`:destructive` on `WidgetAlert`).

- **(a)** No `tone`. Keep one `variant` per widget. A `variant` value exists
  only where the widget library draws the widget differently with no knowledge
  of a domain.
- **(b)** Add one field `tone` to the widgets that can carry a meaning: the
  label, the badge, the alert, the card and the button. It has one set of
  values in every widget: `:neutral`, `:primary`, `:destructive`, `:warning`,
  `:success`. Each value selects a token pair of the theme, for example
  `destructive` and `destructive_foreground`. `variant` then answers only how
  loud a surface is. The theme gets the tokens `warning`,
  `warning_foreground`, `success` and `success_foreground`.

- **(c)** An open `tone`: any `Symbol`. The theme maps each tone to its colors,
  and an application adds its own entries.

**Decision: (a).** Decided by the owner on 2026-09-22. The reasons:

- A meaning belongs to a domain: the severities of a log, the states of a diff,
  the roles of a conversation. No finite list in the widget library can hold
  the meanings of every domain. A short list puts different meanings into one
  group, and the difference is lost.
- A domain can come with its own theme, in the same way as the widget theme.
  That theme gives the defaults of the projections of the domain, and those
  projections override the defaults of a widget where the domain needs it
  (§4.7). The override of D2 takes any color on any part, so a domain needs
  nothing more from the widget library.
- A `variant` is a look that the widget library itself defines, so a closed list
  is correct there. `:tinted` on `WidgetCard`, `:outline` on `WidgetBadge` and
  `:destructive` on `WidgetAlert` are such looks. A domain selects one where it
  fits.
- (c) is open, but the widget theme then holds names from domains, and a tone
  with no entry falls back to the default with no error. It also does the job
  of the theme of the domain.

The theme gets no `warning` and no `success` token.

### D6. How an upstream projection gets a color of the theme

- **(a)** The upstream projection never gets the widget theme. It holds the
  colors of its domain in its own style fields (§4.7), and it can select a
  variant of a widget.
- **(b)** The upstream projection also takes the theme as a constructor argument
  and writes resolved colors into the document.

**Decision: (a) for widget documents.** The owner accepted the
recommendation on 2026-09-22. With (b) the theme is in two
places, and another theme needs a new upstream projection too. (b) stays correct
for a projection that draws graphics itself, such as
`build_module_appearance_graphics`. There the caller must give the theme, and
`nothing` must not select black on white.

The first wording of (a) said "only through a tone or a variant". It changed on
2026-09-22, when §4.7 gave the colors of a domain to the projection of that
domain. The decision itself did not change: the upstream projection never gets
the widget theme.

### D7. A caller that builds one projection

- **(a)** Each widget projection gets a constructor that takes the theme, for
  example `WidgetScrollPaneToGraphicsCanvas(theme; measure, font, chrome = false)`.
  The factory calls these constructors.
- **(b)** The factory takes changes for one widget type:
  `WidgetToGraphics(font; theme, changes = …)`.
- **(c)** The caller builds the factory and sets the cell of one style field.

**Decision: (a).** The owner accepted the
recommendation on 2026-09-22. It removes the literal defaults (defect 6). It also
puts the mapping from token to style field beside each struct, with keyword
arguments. Today that mapping is a positional table of about 40 calls, where two
swapped arguments of the same type give no error.

### D8. The width of the border

- **(a)** The `border` inset of the document gives the width, and the projection
  gives only the color.
- **(b)** The `StyleStroke` of the projection gives the width and the color. The
  `border` inset of the document only reserves space.

**Decision: (a).** The owner accepted the
recommendation on 2026-09-22. The border is a part whose size a caller controls
(§4.4), and the `border` inset is that size. With (b) the border has two sizes:
the inset reserves space, and the stroke draws a line of another width.

**What moved this recommendation:** the owner's rule of §4.4. The first version
of this plan gave no recommendation.

The cost of (a): a widget that shows a 1-pixel outline today draws it inside its
box, and its `border` inset is 0. With (a) its `border` inset becomes 1, and its
box grows by 1 pixel on each side. The theme token `inset` can give this default,
so the token gets a job, and step 3 keeps it. The images of the examples change.

### D9. The selection ring of the layouts

Layouts are not widgets and get no theme. They draw `SELECTION_RING_COLOR`.

- **(a)** The widget factory also builds the layout projections from the theme.
  The factory already registers `GridLayout`
  ([WidgetToGraphics.jl:7017](../../source/widget/WidgetToGraphics.jl#L7017)).
  Each layout projection gets a style field for its ring.
- **(b)** Keep the constant for the layouts, and make it the default of a theme
  token that every whole-selection ring uses.

**Decision: (a).** The owner accepted the
recommendation on 2026-09-22. A ring around a selected object then has one color in a
widget and in a layout, and the theme sets it.

### D10. A theme for a part of the tree

- **(a)** No document selects a theme. A part of the tree gets another theme only
  where the application joins a second factory (§4.6).
- **(b)** A widget, for example `WidgetShell`, holds the name of a theme, and the
  factory resolves it.

**Decision: (a),** until a real case needs (b). The owner accepted the
recommendation on 2026-09-22. With (b) a document holds a theme name, and the
printer context must carry the themes.

### D11. The box parts on every widget

19 widgets have the `margin`, `border` and `padding` insets. `WidgetCard` has
only `padding`. 23 widgets have none, for example `WidgetBadge`, `WidgetSwitch`
and `WidgetTable`. A widget with no insets has no box parts, so a caller can not
color its margin.

- **(a)** Every widget gets the three insets, and so the four box parts.
- **(b)** Only the widgets of today have box parts.

**Decision: (a), wherever it makes sense.** Decided by the owner on 2026-09-22.
The rule: every widget that the factory prints on its own gets the `margin`,
`border` and `padding` insets. Three widgets are exceptions:

- `WidgetTabPage` and `WidgetAccordionItem` have no projection of their own.
  The tabbed pane and the accordion draw them as their own parts: the tab and
  the page, and the item.
- `WidgetHighlight` marks an area that its caller sizes, for example a drop
  target. A margin would move the mark away from that area.

So 20 widget types get three inset fields, and `WidgetCard` gets `margin` and
`border`. Their printers and readers must respect the insets. Then the rule of
§4.4 holds for every widget that has a box, and a developer can color the margin
of any of them to see the layout.

### D12. A type for an inset and its color

`StyleText` holds a font and a color together, and `StyleStroke` holds a color
and a width.

- **(a)** No new type. The document keeps `margin::Inset`, `border::Inset` and
  `padding::Inset`. The colors of these parts are overrides in the `style` field
  (D2).
- **(b)** A new type, for example `StyleBand(inset, color)`, and one field for
  each box part: `margin::StyleBand`. The color is `nothing` to use the color of
  the projection.

**Decision: (a).** Decided by the owner on 2026-09-22. The reasons:

- An inset and a color belong to different layers. The inset is a layout
  value: the layout, the printer geometry and the readers read it, and the
  document holds it. The color is a paint value: only the painter reads it, its
  default comes from the projection, and the document can override it. The two
  values of `StyleText` are both paint values, and one printer reads them
  together.
- Only the margin, the border and the padding have an inset. The content and the
  parts of one widget type have no inset, so with (b) the parts have two shapes.
- With (b) the box colors are in the bands and the other colors are in the
  style, so the overrides of a widget are in two places. A style that many
  widgets share then shares a size too.

(b) is the better choice where the colors are flat fields on the document
(D2 (a)), because there it replaces a pair of fields with one field. With (b)
the color needs its own cell in the type, so that a change of the color does
not lay the widget out again.

## 6. Steps

The owner decided §5 on 2026-09-22. Each step is one commit, and the
targeted tests run after each step.

- [x] 1. Record the decisions of §5 in this plan. Done on 2026-09-22.
- [x] 2. Add `color_transparent` to `Color.jl`. Replace the 12 literals and the
      three local names of §3.4 with it. This step changes no image, so it can
      land before the other decisions. Done: the graphics, text, widget, math,
      chart and sequence chart suites pass.
- [ ] 3. Theme: add the tokens that the decisions need, for example the shadow,
      the scrim, the selection band, the hover and pressed layers and the knob.
      No token for a meaning of a domain (D5). Keep `inset` as the default box
      insets (D8). Change
      `build_qtenv_widget_theme` in omnet-julia, which calls the positional
      constructor.
- [ ] 4. Projections: give each widget projection a constructor that takes the
      theme (D7), with the names of D1. Move the constants of §3.4 into style
      fields. Remove the two style fields that are never read. Make
      `_push_panel!` skip a transparent fill that has no outline (§4.3), and
      give `WidgetCard` `:plain` a transparent surface. Write the full list of
      the parts of each widget type (§4.4), and give each part a style field.
      Paint the four box parts with one painter, made from `_push_box_rects!`,
      with the corner radius and the skip of a transparent part. Add the page
      part of `WidgetTabbedPane`.
- [ ] 5. States: give every interactive widget a disabled look, and use one
      selection token and one hover token everywhere (D4).
- [ ] 6. Documents: move `margin_color`, `border_color`, `padding_color`,
      `content_fill_color` and `title_fill_color` into the override of D2, with
      one color for every part (§4.4). No part loses its color. The insets stay
      separate fields (D12). Give the box insets to the 20 widget types and to
      `WidgetCard` (D11). Add no `tone` (D5). Change the 26 call
      sites in both repositories to the new override form. This is a
      mechanical change: the colors of an upstream projection stay its own
      (§4.7). For each of the 16 call sites that have no effect today, check
      whether the color is still wanted. For example, `AssistantToWidget` asks
      for white panes but shows `theme.background`.
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
- **A test of the parts.** A widget example gives each part a different color.
  The rendered image shows each color at the size of its part: the margin band
  as wide as the `margin` inset, the border band as wide as the `border` inset,
  and so on. The margin of `WidgetText` shows the parent, not the surface
  (defect 16).
- **A test of the transparent fill.** A shell and a tabbed pane with the
  override `color_transparent` add no fill element. The same widgets with a
  visible color add one. A transparent fill with a visible outline keeps its
  element.
- **A test of the hit targets.** A press over an empty area of the table, of the
  tree and of the fold column of the card still reaches the widget after the
  change of step 4.
- The widget tests under `test/substrate/projection/`. A change to the number of
  fields of a widget document changes the pass counts, because the tests check
  each cell.
- The images of the examples change where D4 changes the hover look. Make new
  reference images and compare them by eye.

## 8. Implementation

### 8.1 The order of the commits

The steps of §6 are ordered by concern. The implementation goes in commits that
each leave the tree consistent and the tests at their baseline:

1. Step 2: `color_transparent`.
2. The shared code: the new theme tokens and a keyword constructor for
   `WidgetTheme`, the style documents of D2, and the helpers of §8.4. No widget
   uses them yet.
3. One commit for each group of widgets. A commit converts the projections of
   its group (§8.3 names, the constructor of D7, the constants of §3.4 as style
   fields, the default insets), their printers and readers (the box parts, the
   overrides, the layers of D4, the disabled look), their documents (the `style`
   field, the insets of D11) and the call sites.
   - leaf controls: label, insertion, text, button, checkbox, tooltip;
   - menus and bars: context menu, menu, menu item, dialog, composite,
     toolbar, status bar;
   - panes: shell, title pane, split pane, tabbed pane, scroll pane, transform
     pane, scroll bar;
   - surfaces: badge, separator, card, alert, avatar, skeleton, highlight;
   - value controls: switch, progress, slider, radio group, toggle, toggle
     group;
   - lists: select, option, spin box, list, textarea, accordion, table, tree.
4. The layouts (step 7), and the removal of the old helpers and fields.
5. omnet-julia, in a branch of its own (§8.6).
6. The documentation, the tests of §7, and the move of this plan to `done`.

The baseline of each suite comes from a separate worktree at the base commit
`91cb3348`, `projectured-julia-widget-color-base`, so that no change of the
branch can reach it.

### 8.2 Decisions made in the implementation

- **The document insets default to `nothing`.** `nothing` takes the default
  inset of the projection, by the rule of §4.3 for an override. The projection
  names its default insets as the document does: `margin`, `border` and
  `padding`. So a caller who writes `padding = Inset(…)` overrides the padding of
  the look, and a caller who writes nothing gets it.
- **The default border is `Inset(theme.border_width)`** for a widget that shows
  an outline (D8). The token `border_width` gives it, so the token `inset` has
  no job and goes after all. D8 said that `inset` can give the default.
- **A cell padding, a row padding or an item padding is not the box padding.**
  The table, the list and the accordion name it `cell_padding`, `row_padding` and
  `item_padding`.
- **The scroll pane loses `chrome`.** `content_color = color_transparent` does
  the same.
- **An override replaces the style field of the same name** in every state
  except the disabled state (D4 (c)). A style document holds one field for each
  color of its projection: the box parts, the parts of the type and their
  states, and the variants. It holds no field for the disabled state and none
  for a decoration. For a `_text` or a `_stroke` field, the override holds the
  color and is named `<field>_color`, for example `label_text_color`. The font
  and the width stay those of the projection.
- **`WidgetStyle`** has the fields that every widget has: `margin_color`,
  `border_color`, `padding_color`, `content_color` and `label_text_color`. A
  widget type with more parts has a style of its own, for example
  `WidgetTabbedPaneStyle`, with the same five fields and the fields of its type.
  All fields are `nothing` by default.
- **`text_style` of `WidgetLabel` stays.** It holds a font and a color, which a
  style can not. The order for the label text: `text_style`, then
  `label_text_color` of the style, then `label_text` of the projection.
- **The new theme tokens**, with their values in every preset: `shadow` is
  black at 8%, `scrim` is black at 40%, `selection` is `SELECTION_RING_COLOR`,
  `knob` is `color_white`, `hover_layer` is `primary` at 12% and
  `pressed_layer` is `primary` at 20%. The selection band of a row is
  `selection` at 25%. The placeholder of an image that is not decoded yet takes
  `muted`. `WidgetTheme` gets a keyword constructor, so a caller names each
  token.
- **"On" is a checked state.** A switch or a toggle that is on uses the
  `checked` state word.

### 8.3 The names of the style fields

The grammar of D1, with a variant word in front where a projection has
variants: `[<variant>_]<part>[_<state>]_<kind>`. The kind is `color`, `stroke`
or `text`. An inset field has no kind word, as on the document.

Every widget with the box insets has `margin`, `border`, `padding`,
`margin_color`, `border_color`, `padding_color` and `content_color`. The table
gives each widget its defaults and its other fields. A box color that the table
does not name is `color_transparent`, and an inset that it does not name is
`inset_default`. `border` below means `Inset(theme.border_width)`, `pad` means
`Inset(pad_y, pad_y, pad_x, pad_x)`, and `(t, w)` is `StyleStroke(theme.t, w)`.

| Widget | Defaults of the box | Other style fields |
| --- | --- | --- |
| `WidgetInsertion` | | `label_text` ← `body_text` |
| `WidgetLabel` | | `label_text` ← `body_text`; `placeholder_color` ← `muted` |
| `WidgetText` | border `input`; surface `background` | `label_text`; `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_disabled_text`; `focus_ring_stroke` ← (`ring`, 2); `selection_ring_stroke` ← (`selection`, 2); `corner_radius` |
| `WidgetCheckbox` | | `indicator_color` ← `background`; `indicator_checked_color` ← `primary`; `indicator_disabled_color` ← `muted`; `indicator_stroke` ← (`input`, `stroke`); `indicator_disabled_stroke` ← (`muted_foreground`, `stroke`); `check_stroke` ← (`primary_foreground`, `stroke`); `check_disabled_stroke` ← (`muted_foreground`, `stroke`); `focus_ring_stroke`; `indicator_size`; `corner_radius` |
| `WidgetButton` | border `border`; padding `pad`; surface `background` | `label_text` ← `label_text`; `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_disabled_text`; `layer_hovered_color` ← `hover_layer`; `layer_pressed_color` ← `pressed_layer`; `shadow_color` ← `shadow`; `shadow_offset`; `placeholder_color` ← `muted`; `focus_ring_stroke`; `corner_radius` |
| `WidgetTooltip` | border `border`; padding `pad`; surface `popover` | `label_text` ← (`font`, `popover_foreground`); `corner_radius` |
| `WidgetContextMenu`, `WidgetMenu`, `WidgetToolbar` | | none |
| `WidgetDialog` | border `border`; padding `pad`; surface `card` | `title_text`; `body_text`; `scrim_color` ← `scrim`; `gap`; `corner_radius` |
| `WidgetMenuItem` | | `label_text`; `label_disabled_text`; `layer_hovered_color` |
| `WidgetComposite` | | `selection_ring_stroke` |
| `WidgetShell` | surface `background` | `band_gap` |
| `WidgetTitlePane` | | `title_bar_color`; `title_text` ← (`font_bold`, `foreground`); `body_text` ← (`font`, `card_foreground`); `title_gap` |
| `WidgetSplitPane` | | `splitter_stroke` ← (`border`, `border_width`) |
| `WidgetTabbedPane` | | `tab_strip_color` ← `muted`; `tab_color`; `tab_selected_color` ← `background`; `tab_text` ← (`font`, `muted_foreground`); `tab_selected_text` ← (`font`, `foreground`); `page_color`; `selection_ring_stroke`; `tab_padding`; `corner_radius` |
| `WidgetScrollPane`, `WidgetTransformPane` | content `background` | none |
| `WidgetStatusBar` | surface `muted` | `label_text` ← `caption_text`; `item_gap` |
| `WidgetScrollBar` | | `track_color` ← `muted`; `thumb_color` ← `border`; `minimum_thumb_length` |
| `WidgetBadge` | border `border`; padding `Inset(3, 3, 10, 10)`; surface `primary` | `label_text` ← (`font_small`, `primary_foreground`); for each of the variants `secondary`, `destructive` and `outline`: `<variant>_padding_color`, `<variant>_content_color`, `<variant>_border_color`, `<variant>_label_text` |
| `WidgetSeparator` | | `divider_stroke` ← (`border`, `border_width`) |
| `WidgetCard` | border `border`; surface `card` | `title_text`; `description_text`; `body_text`; `footer_text`; `header_color`; `body_color`; `footer_color`; for each of the variants `tinted`, `muted` and `plain`: `<variant>_border_color`, `<variant>_padding_color`, `<variant>_content_color`; `chevron_stroke`; `selection_ring_stroke`; the sizes of today |
| `WidgetSwitch` | | `track_color` ← `track_off`; `track_checked_color` ← `primary`; `track_disabled_color` ← `muted`; `knob_color` ← `knob`; `knob_stroke` ← (`border`, `border_width`); `focus_ring_stroke`; the sizes of today |
| `WidgetProgress` | | `track_color` ← `muted`; `indicator_color` ← `primary`; `bar_height` |
| `WidgetSlider` | | `track_color` ← `muted`; `indicator_color` ← `primary`; `knob_color` ← `knob`; `knob_stroke` ← (`primary`, `stroke`); `track_disabled_color`, `indicator_disabled_color`, `knob_disabled_color` ← `muted`; `focus_ring_stroke`; the sizes of today |
| `WidgetRadioGroup` | | `label_text`; `label_disabled_text`; `indicator_color` ← `background`; `indicator_stroke` ← (`input`, `stroke`); `indicator_selected_stroke` ← (`primary`, `stroke`); `indicator_disabled_stroke`; `dot_color` ← `primary`; `dot_disabled_color` ← `muted_foreground`; `focus_ring_stroke`; the sizes of today |
| `WidgetAvatar` | content `muted` | `label_text` ← (`font`, `muted_foreground`) |
| `WidgetAlert` | border `border`; padding 14; surface `background` | `title_text` ← (`font_bold`, `foreground`); `description_text`; `destructive_border_color` ← `destructive`; `destructive_title_text` ← (`font_bold`, `destructive`); `title_gap`; `corner_radius` |
| `WidgetHighlight` | no box (D11) | `content_color` ← `primary` at 25%; `border_stroke` ← (`primary`, 2); `corner_radius` |
| `WidgetSkeleton` | content `muted` | `corner_radius` |
| `WidgetToggle` | border `border`; padding `pad`; surface `background` | `border_checked_color`; `padding_checked_color`, `content_checked_color` ← `accent`; `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_text` ← (`font`, `foreground`); `label_checked_text` ← (`font`, `accent_foreground`); `label_disabled_text`; `focus_ring_stroke`; `corner_radius` |
| `WidgetToggleGroup` | padding 2; surface `muted` | `padding_disabled_color`, `content_disabled_color` ← `muted`; `segment_color`; `segment_selected_color` ← `background`; `segment_disabled_color` ← `muted`; `label_text` ← (`font`, `muted_foreground`); `label_selected_text` ← (`font`, `foreground`); `label_disabled_text`; `segment_padding` ← `pad`; `focus_ring_stroke`; `corner_radius` |
| `WidgetSelect` | border `input`; padding `pad`; surface `background` | `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_text`; `label_disabled_text`; `chevron_stroke` ← (`muted_foreground`, `stroke`); `focus_ring_stroke`; `gap`; `chevron_size`; `corner_radius` |
| `WidgetOption` | padding `pad`; surface `background` | `label_text`; `layer_hovered_color` |
| `WidgetSpinBox` | border `input`; padding `pad`; surface `background` | `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_text`; `label_disabled_text`; `stepper_color` ← `foreground`; `stepper_disabled_color` ← `muted_foreground`; `divider_stroke` ← (`input`, `border_width`); `focus_ring_stroke`; `corner_radius` |
| `WidgetList` | border `border`; surface `background` | `label_text`; `row_selected_color` ← `selection` at 25%; `layer_hovered_color`; `row_padding` ← `pad`; `corner_radius` |
| `WidgetTextarea` | border `input`; padding `pad`; surface `background` | `padding_disabled_color`, `content_disabled_color` ← `muted`; `label_text`; `label_disabled_text`; `focus_ring_stroke`; `corner_radius` |
| `WidgetAccordion` | | `title_text`; `body_text`; `divider_stroke` ← (`border`, `border_width`); `chevron_stroke`; `item_padding`; the sizes of today |
| `WidgetTable` | | `divider_stroke` ← (`border`, `border_width`); `header_row_color` ← `muted`; `row_selected_color`; `layer_hovered_color`; `cell_padding` ← `pad` |
| `WidgetTree` | | `label_text`; `icon_text` ← (`font`, `muted_foreground`); `chevron_stroke`; `row_selected_color`; `layer_hovered_color`; the sizes of today |

`label_disabled_text` is the font of `label_text` in `muted_foreground`.
`focus_ring_stroke` is (`ring`, 2) and `selection_ring_stroke` is
(`selection`, 2) wherever the table names them.

### 8.4 The shared helpers

- `_get_part_color(w, name, default)`, `_get_part_text(w, name, default)` and
  `_get_part_stroke(w, name, default)` read the override of one part from the
  `style` field of `w`, and return `default` when there is none.
- `_get_box_insets(p, w)` resolves the three insets of `w` against the defaults
  of `p`. `_content_offset` and `_inset_total` take `p` as well.
- `_push_box_parts!` paints the four box parts from the outside in, and skips a
  transparent part (§4.3). With a uniform border and the same color for the
  padding and the content, it pushes one `GraphicsRect`.
- `_push_panel!` skips a transparent fill that has no outline.
- `_push_state_layer!` paints the layer of the hovered or the pressed state
  (D4 (c)).

### 8.5 Progress

- [x] Step 2: `color_transparent`, `is_color_transparent`, and the 12 literals.
- [x] The shared code: the theme tokens `shadow`, `scrim`, `selection`, `knob`,
      `hover_layer` and `pressed_layer`, a keyword constructor for
      `WidgetTheme`, no `inset` token, `WidgetStyle`, the helpers of §8.4, and
      the color and width of `make_selection_ring` as keywords. `test_substrate()`
      is at its baseline: 63119 pass, and the 3 failures and 2 errors of
      `SplitPaneDragTest` that clean main has too.
- [x] Group 1, the leaf controls: label, insertion, text, button, checkbox and
      tooltip, and `WidgetCheckboxStyle`. `test_substrate()` keeps the 3
      failures and 2 errors of the baseline and has 65506 passes, and the
      twenty domain suites match their baseline exactly; the walker counts one pass for each cell,
      and the projections have more cells. Found on the way:
      - An image that is not decoded yet needs a color, so the label and the
        button get `placeholder_color` ← `muted`.
      - A padding that the document gives now wins over the padding of the
        projection, where the tooltip took the larger of the two. The tooltip
        example gave `padding = Inset(4, 4, 4, 4)`, which never showed; it
        goes, with the black `border_color` of four widget examples, which never
        drew either.
      - The layout example gives its buttons and tags a blue border. It never
        drew; as `style = WidgetStyle(border_color = …)` it draws now, with the
        padding of the tags, which the label ignored before.

### 8.6 omnet-julia

omnet-julia reaches projectured-julia through the main checkout, so it can not
see this branch (see the note on cross-repository worktrees). Its changes go in
a branch of its own, `widget-color-design`, in a sibling worktree, and a
throwaway environment in the scratchpad tests it against this branch. The
branch lands after the projectured-julia branch.

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
| `WidgetShell` | `background_color` ← `background`. The shell paints it only when it has a size on both axes. |
| `WidgetTitlePane` | `title_text` ← (`font_bold`, `foreground`); `content_text` ← (`font`, `card_foreground`) |
| `WidgetSplitPane` | `splitter` ← (`border`, `border_width`) |
| `WidgetTabbedPane` | `track_color` ← `muted`; `active_color` ← `background`; `active_foreground` ← `foreground`; `inactive_foreground` ← `muted_foreground`. The page area has no fill. The whole-selection ring is a constant. |
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
