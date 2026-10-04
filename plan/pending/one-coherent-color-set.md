# One coherent color set

> **Status:** pending. Part 1, the catalog of every color, is done
> (2026-10-04). Part 2, the design of the new color set, is not started. The
> owner decides its direction after reading the catalog. No code changed.

## 1. The request

The owner wrote on 2026-10-04:

> collect all the colors for all styles in projectured-julia, what are they
> used for, what categories they belong, etc.
>
> the goal is to have a catalog of colors and then create coherent and
> consistent set of colors throughout the domains and all user interface parts.
>
> first, just do the catalog, we will figure out how to recolor them afterwards

## 2. Summary

- A color is a `StyleColor`: red, green, blue and alpha, each from 0 to 1
  ([Color.jl](../../source/platform/style/Color.jl)).
- The palette in `Color.jl` names 1076 colors. The code in `source/` uses 54 of
  them. The 977 names of the Wikipedia list and the 19 pastel colors have no
  use.
- 33 themes are declared with `@theme struct`. 32 of them hold colors: 266
  color fields in total. 176 are text roles (a color and a font change), and 90
  are plain colors. `TooltipTheme` holds no color; the tooltip takes the
  popover colors of `WidgetTheme`.
- The 266 fields hold 57 distinct values, or 42 distinct values if an alpha
  variant counts as its base color.
- Two palettes live side by side. Solarized gives 162 fields: every domain,
  the syntax, the text, the graphics and the charts. The Tailwind ramps slate,
  indigo and red give 52 fields: the widgets, the help, and the plain text of
  the logs and of the conversation. 28 fields are literal numbers, and one is
  a mix of a palette color.
- Three themes have presets: `WidgetTheme` has four (two light, two dark),
  and `FaultTheme` and `GestureLogTheme` have a "Panel" preset for a dark
  panel. No domain theme has a dark preset.
- About 12 places outside the themes fix a color (section 8). The most
  visible is the background of every window, `#fdf6e3`, which is not a theme
  value.
- 11 places derive a color from a theme color: a layer at an alpha, a mix of
  two colors, a fade (section 9).

## 3. How a color reaches the screen

1. The palette in `Color.jl` names the colors as constants, for example
   `color_solarized_blue` or `color_slate_500`.
2. A theme field takes a palette constant or a literal `StyleColor(…)` as its
   default. A field of type `TextRole` holds a color and a font change
   (weight, italic, family, relative size), for example
   `TextRole(color_solarized_blue; weight = 700)`. A field of type
   `StyleColor` holds a color only.
3. A preset is a function that makes the theme with other values. The
   appearance tab offers the presets at the head of the section of the theme,
   and a person can edit each color field there.
4. A projection reads its scaled theme and holds each color in a style field.
   Some projections derive a color from a theme color (section 9).
5. The projection puts the color in a graphics element (`GraphicsText`,
   `GraphicsRect`, …). The SDL, PDF, web and video backends convert it to 8-bit
   RGBA. The console backend writes it as a 24-bit ANSI color, and writes no
   color for `color_default`.
6. The background of a window is a separate value: `bg::NTuple{4,UInt8}` of
   the window document, with the default `DEFAULT_BG` in
   [ScreenDocument.jl:27](../../source/platform/screen/ScreenDocument.jl#L27).
   It is not a `StyleColor` and not a theme value.

The style guard [test/suite/style.jl](../../test/suite/style.jl) fails on a
palette name or a `StyleColor(0.…` outside a theme, a preset, `Color.jl`, a
docstring or a comment. A line can keep a value on purpose with a
`# @style: <reason>` marker. The guard reads `StyleColor` only, so it does not
see the byte tuples of the window background.

## 4. The roles

Each theme color field has one role and one sub-role. The roles come from what
the docstring of the field says that it draws. Appendix A.1 gives the role of
each field.

| Role | Sub-roles | Fields | Distinct values | What it is |
| --- | --- | --- | --- | --- |
| `surface` | window, raised, quiet, plot | 14 | 9 | The fill of an area: a window, a card, a menu, a disabled control, the plot area of a chart. |
| `overlay` | shadow, scrim, panel | 4 | 4 | A translucent layer over other content: a shadow, the scrim behind a dialog, the panel of a log over a window. |
| `line` | border, axis, grid, edge | 11 | 8 | A border, an axis, a grid line, the edge of a graph. |
| `text` | body, muted, hint, completion, heading, on accent | 81 | 21 | Text that is not a token of a language: prose, labels, captions, placeholders, headings. |
| `accent` | fill, tint, text, focus ring, role | 14 | 9 | The color of identity and of the main action: the primary button, the focus ring, the marker line of a log, the role of a turn. |
| `selection` | ring, band, fill, hover, caret, pointer, match, item | 18 | 15 | What shows the selection, the pointer, the caret and a search match. |
| `status` | error, warning, success, info | 22 | 6 | A state: an error, a warning, a valid or found value, a log level. |
| `token` | 19 classes (keyword, name, string, number, …) | 97 | 8 | A part of a language or a format: JSON, Julia, SQL, Markdown, the reflected display of an object. |
| `data` | mark, readout, wash | 5 | 5 | A mark of a chart that is not a series: an arrow, an event, a crosshair. |

The sub-roles of `token`: boolean, callee, delimiter, identifier, key / field,
keyword, markup marker, name, null, number, operator, quote, reference,
separator, string, symbol, type. Appendix A.3 lists, for each sub-role, the
values and the themes that use them.

## 5. The palette

`Color.jl` holds the palette in sections. The table gives, for each section,
the count of names and the count that `source/` uses.

| Section | Names | Used in `source/` | Where it is used |
| --- | --- | --- | --- |
| Default | 1 | 1 | `color_default` (`#000000`): the text of a span that names no color. |
| Pure | 9 | 5 | `color_black`, `color_white`, `color_red` (as a base for a mix), `color_yellow` (the search match), `color_transparent` (no paint). |
| Gray | 17 | 2 | `color_gray159` and `color_gray223`: the data frame sort glyph and the "Panel" presets. |
| Solarized | 18 | 15 | The 8 accents, 5 of the 8 base tones, `color_solarized_gray` and `color_completion_hint`. Every domain theme. |
| Pastel pairs | 19 | 0 | — |
| Zinc ramp (Tailwind) | 11 | 11 | Only the two zinc presets of `WidgetTheme`. |
| Slate ramp (Tailwind) | 11 | 11 | `WidgetTheme`, the slate presets, and the text of the platform logs and panels. |
| Indigo ramp (Tailwind) | 11 + 2 | 9 | The widget accent, the user role of the conversation. The section also holds `color_destructive` (`#ef4444`, Tailwind red-500) and `color_destructive_fg` (`#fafafa`). |
| Named (Wikipedia) | 977 | 0 | — |

The Solarized colors that the code uses:

| Name | Value | Solarized name | Theme fields |
| --- | --- | --- | --- |
| `color_solarized_blue` | `#268bd2` | blue | 27 |
| `color_solarized_gray` | `#808080` | — (a neutral gray, not a Solarized tone) | 29 |
| `color_solarized_green` | `#859900` | green | 22 |
| `color_solarized_magenta` | `#d33682` | magenta | 17 |
| `color_solarized_cyan` | `#2aa198` | cyan | 16 |
| `color_solarized_red` | `#dc322f` | red | 13 |
| `color_solarized_yellow` | `#b58900` | yellow | 12 |
| `color_solarized_violet` | `#6c71c4` | violet | 7 |
| `color_solarized_orange` | `#cb4b16` | orange | 5 |
| `color_solarized_content_darker` | `#586e75` | base01 | 4, and 1 as a literal |
| `color_completion_hint` | `#85990080` | green at 50% | 4 |
| `color_solarized_background_lighter` | `#fdf6e3` | base3 | 3, and the window background |
| `color_solarized_content_dark` | `#657b83` | base00 | 2 |
| `color_solarized_background_dark` | `#073642` | base02 | 1 |
| `color_solarized_content_lighter` | `#93a1a1` | base1 | 1 |

Not used from Solarized: base03 `#002b36`, base2 `#eee8d5` and base0
`#839496`.

## 6. The themes

| Theme | Slice | Colors | Text roles | Plain colors | Families | Presets |
| --- | --- | --- | --- | --- | --- | --- |
| [`WidgetTheme`](../../source/platform/widget/WidgetTheme.jl) | platform | 23 | 0 | 23 | slate 14, indigo 4, red 2, literal 2, pure 1 | 4: Slate light (default), Slate dark, Light, Dark |
| [`GraphicsTheme`](../../source/platform/graphics/GraphicsTheme.jl) | platform | 2 | 1 | 1 | Solarized 1, literal 1 |  |
| [`TextTheme`](../../source/platform/text/TextTheme.jl) | platform | 15 | 7 | 8 | Solarized 8, literal 4, pure 2, default 1 |  |
| [`SyntaxTheme`](../../source/platform/syntax/SyntaxTheme.jl) | platform | 21 | 18 | 3 | Solarized 19, default 2 |  |
| [`ReferenceTheme`](../../source/platform/text/ReferenceTheme.jl) | platform | 6 | 0 | 6 | Solarized 6 |  |
| [`ConversationTheme`](../../source/platform/conversation/ConversationTheme.jl) | platform | 16 | 11 | 5 | Solarized 6, slate 5, indigo 2, red 2, default 1 |  |
| [`GestureHelpTheme`](../../source/platform/gesturehelp/GestureHelpTheme.jl) | platform | 11 | 9 | 2 | Solarized 9, default 2 |  |
| [`GestureLogTheme`](../../source/platform/gesturelog/GestureLogTheme.jl) | platform | 6 | 5 | 1 | slate 4, Solarized 1, literal 1 | 2: Light (default), Panel |
| [`UndoTheme`](../../source/platform/undo/UndoTheme.jl) | platform | 6 | 6 | 0 | slate 4, Solarized 2 |  |
| [`MessageLogTheme`](../../source/platform/log/MessageLogTheme.jl) | platform | 6 | 6 | 0 | Solarized 3, slate 3 |  |
| [`FaultTheme`](../../source/platform/fault/FaultTheme.jl) | platform | 6 | 5 | 1 | slate 4, Solarized 1, literal 1 | 2: Light (default), Panel |
| [`FrameStatisticsTheme`](../../source/platform/statistics/FrameStatisticsTheme.jl) | platform | 3 | 3 | 0 | slate 2, Solarized 1 |  |
| [`HelpTheme`](../../source/platform/help/HelpTheme.jl) | platform | 6 | 6 | 0 | slate 6 |  |
| [`InspectorTheme`](../../source/platform/inspector/InspectorTheme.jl) | platform | 1 | 0 | 1 | Solarized 1 |  |
| [`FileSystemTheme`](../../source/platform/filesystem/FileSystemTheme.jl) | platform | 2 | 2 | 0 | Solarized 2 |  |
| [`DataFrameTheme`](../../source/adapter/dataframes/DataFrameTheme.jl) | adapter | 2 | 0 | 2 | literal 1, gray 1 |  |
| [`JsonTheme`](../../source/domain/json/JsonTheme.jl) | domain | 8 | 8 | 0 | Solarized 8 |  |
| [`YamlTheme`](../../source/domain/yaml/YamlTheme.jl) | domain | 7 | 7 | 0 | Solarized 7 |  |
| [`XmlTheme`](../../source/domain/xml/XmlTheme.jl) | domain | 6 | 6 | 0 | Solarized 5, pure 1 |  |
| [`SqlTheme`](../../source/domain/sql/SqlTheme.jl) | domain | 4 | 4 | 0 | Solarized 2, default 2 |  |
| [`DbCatalogTheme`](../../source/domain/dbcatalog/DbCatalogTheme.jl) | domain | 5 | 5 | 0 | Solarized 4, default 1 |  |
| [`JuliaTheme`](../../source/domain/julia/JuliaTheme.jl) | domain | 12 | 10 | 2 | Solarized 11, default 1 |  |
| [`MathTheme`](../../source/domain/math/MathTheme.jl) | domain | 10 | 7 | 3 | Solarized 7, default 2, literal 1 |  |
| [`FormulaTheme`](../../source/domain/formula/FormulaTheme.jl) | domain | 5 | 5 | 0 | Solarized 5 |  |
| [`FsmTheme`](../../source/domain/fsm/FsmTheme.jl) | domain | 6 | 6 | 0 | Solarized 6 |  |
| [`ProcessTheme`](../../source/domain/process/ProcessTheme.jl) | domain | 7 | 7 | 0 | Solarized 7 |  |
| [`GraphTheme`](../../source/domain/graph/GraphTheme.jl) | domain | 4 | 0 | 4 | Solarized 3, pure 1 |  |
| [`ChartTheme`](../../source/domain/chart/ChartTheme.jl) | domain | 13 | 0 | 13 | literal 10, Solarized 3 |  |
| [`SequenceChartTheme`](../../source/domain/sequencechart/SequenceChartTheme.jl) | domain | 12 | 0 | 12 | literal 8, Solarized 4 |  |
| [`MarkdownTheme`](../../source/domain/markdown/MarkdownTheme.jl) | domain | 12 | 10 | 2 | Solarized 10, pure 2 |  |
| [`RstTheme`](../../source/domain/rst/RstTheme.jl) | domain | 14 | 13 | 1 | Solarized 12, pure 2 |  |
| [`BookTheme`](../../source/domain/book/BookTheme.jl) | domain | 9 | 9 | 0 | Solarized 8, pure 1 |  |
| [`TooltipTheme`](../../source/platform/tooltip/TooltipTheme.jl) | platform | 0 | 0 | 0 | — | |

## 7. The presets

### 7.1 `WidgetTheme`

The default is "Slate light". A preset changes the 20 palette fields below.
The fields `destructive` (`#ef4444`), `destructive_foreground` (`#fafafa`),
`shadow` (black at 8%), `scrim` (black at 40%) and `knob` (`#ffffff`) are the
same in all four.

| Field | Slate light | Slate dark | Light (zinc) | Dark (zinc) |
| --- | --- | --- | --- | --- |
| `background` | slate_100 `#f1f5f9` | slate_950 `#020617` | white `#ffffff` | zinc_950 `#09090b` |
| `foreground` | slate_950 `#020617` | slate_50 `#f8fafc` | zinc_950 `#09090b` | zinc_50 `#fafafa` |
| `card` | slate_50 `#f8fafc` | slate_900 `#0f172a` | white `#ffffff` | zinc_900 `#18181b` |
| `card_foreground` | slate_950 `#020617` | slate_50 `#f8fafc` | zinc_950 `#09090b` | zinc_50 `#fafafa` |
| `popover` | slate_50 `#f8fafc` | slate_900 `#0f172a` | white `#ffffff` | zinc_900 `#18181b` |
| `popover_foreground` | slate_950 `#020617` | slate_50 `#f8fafc` | zinc_950 `#09090b` | zinc_50 `#fafafa` |
| `muted` | slate_200 `#e2e8f0` | slate_800 `#1e293b` | zinc_100 `#f4f4f5` | zinc_800 `#27272a` |
| `muted_foreground` | slate_500 `#64748b` | slate_400 `#94a3b8` | zinc_500 `#71717a` | zinc_400 `#a1a1aa` |
| `primary` | indigo_600 `#4f46e5` | indigo_500 `#6366f1` | zinc_900 `#18181b` | zinc_50 `#fafafa` |
| `primary_foreground` | slate_50 `#f8fafc` | slate_50 `#f8fafc` | zinc_50 `#fafafa` | zinc_900 `#18181b` |
| `secondary` | slate_200 `#e2e8f0` | slate_800 `#1e293b` | zinc_100 `#f4f4f5` | zinc_800 `#27272a` |
| `secondary_foreground` | slate_900 `#0f172a` | slate_50 `#f8fafc` | zinc_900 `#18181b` | zinc_50 `#fafafa` |
| `accent` | indigo_100 `#e0e7ff` | indigo_950 `#1e1b4b` | zinc_100 `#f4f4f5` | zinc_800 `#27272a` |
| `accent_foreground` | indigo_700 `#4338ca` | indigo_200 `#c7d2fe` | zinc_900 `#18181b` | zinc_50 `#fafafa` |
| `border` | slate_300 `#cbd5e1` | slate_800 `#1e293b` | zinc_200 `#e4e4e7` | zinc_800 `#27272a` |
| `input` | slate_300 `#cbd5e1` | slate_800 `#1e293b` | zinc_200 `#e4e4e7` | zinc_800 `#27272a` |
| `ring` | indigo_500 `#6366f1` | indigo_400 `#818cf8` | zinc_400 `#a1a1aa` | zinc_600 `#52525b` |
| `track_off` | slate_300 `#cbd5e1` | slate_700 `#334155` | zinc_300 `#d4d4d8` | zinc_700 `#3f3f46` |

The widgets that use each palette field, from the style fields of the widget
projections in
[WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl):

| Field | Widgets |
| --- | --- |
| `background` | Alert, Badge, Button, Card, Checkbox, List, Option, RadioGroup, ScrollPane, Select, Shell, SpinBox, TabbedPane, Text, Textarea, Toggle, ToggleGroup, TransformPane |
| `foreground` | the body, title and label text of every widget; Badge, SpinBox, TabbedPane |
| `card` / `card_foreground` | Card, Dialog / Card, TitlePane |
| `popover` / `popover_foreground` | Menu, Tooltip / Tooltip |
| `muted` | Avatar, Button (disabled), Card (`:muted`), Checkbox, Label, Progress, ScrollBar, Select, Skeleton, Slider, SpinBox, StatusBar, Switch, TabbedPane, Table, Text, Textarea, Toggle, ToggleGroup |
| `muted_foreground` | the caption text of every widget; Accordion, Avatar, Button, Card, Checkbox, MenuItem, RadioGroup, Select, SpinBox, Switch, TabbedPane, Text, Textarea, Toggle, ToggleGroup, ToolbarItem, Tree; the appearance and settings tabs |
| `primary` | Badge, Checkbox, Highlight, Progress, RadioGroup, Slider, Switch; the hover and pressed layers of every widget |
| `primary_foreground` | Badge, Checkbox |
| `secondary` / `secondary_foreground` | Badge |
| `accent` / `accent_foreground` | Toggle |
| `destructive` | Alert, Badge, Table |
| `destructive_foreground` | Badge |
| `border` | Accordion, Alert, Badge, Button, Card, Dialog, List, Menu, ScrollBar, Separator, SplitPane, Switch, Table, Toggle, ToggleGroup, Tooltip; the color control of the appearance tab |
| `input` | Checkbox, RadioGroup, Select, SpinBox, Text, Textarea |
| `ring` | Button, Checkbox, RadioGroup, Select, Slider, SpinBox, Switch, Table, Text, Textarea, Toggle, ToggleGroup |
| `track_off` | Switch |
| `shadow` | Button |
| `scrim` | Dialog |
| `knob` | Slider, Switch |

### 7.2 `FaultTheme` and `GestureLogTheme`

Each has the presets "Light" (the default) and "Panel". "Panel" gives light
text for the dark panel over a window. The panel background does not change.

| Field | Light | Panel |
| --- | --- | --- |
| `FaultTheme.count_text` | slate_500 `#64748b` | gray159 `#9f9f9f` |
| `FaultTheme.site_text` | slate_500 `#64748b` | solarized_gray `#808080` |
| `FaultTheme.message_text` | slate_700 `#334155` | gray223 `#dfdfdf` |
| `FaultTheme.empty_text` | slate_500 `#64748b` | solarized_gray `#808080` |
| `GestureLogTheme.index_text` | slate_500 `#64748b` | gray159 `#9f9f9f` |
| `GestureLogTheme.operation_text` | slate_700 `#334155` | gray223 `#dfdfdf` |
| `GestureLogTheme.muted_text` | slate_500 `#64748b` | solarized_gray `#808080` |
| `GestureLogTheme.empty_text` | slate_500 `#64748b` | solarized_gray `#808080` |

## 8. Colors outside the themes

These colors are fixed in the code. Most carry a `# @style:` marker with a
reason; the guard does not read the byte tuples and the web assets.

| What it draws | Value | Place | Why it is not a theme value |
| --- | --- | --- | --- |
| The background of every window | `#fdf6e3` (Solarized base3), a byte tuple | `DEFAULT_BG` in [ScreenDocument.jl:27](../../source/platform/screen/ScreenDocument.jl#L27); the same value is written 13 more times in `ScreenDocument.jl`, `PdfWriter.jl`, `VideoRecording.jl` and `SdlBackend.jl` | No reason is written. No caller sets another background. |
| The panel of the newest gestures over a window | `#424547` (0.26, 0.27, 0.28), opaque | `_GESTURE_LOG_PANEL_BACKGROUND` in [GestureLogRecording.jl:143](../../source/platform/gesturelog/GestureLogRecording.jl#L143) | Waits for the owner: the theme panel is black at 72%, and this panel must be opaque. |
| The series of a chart that names no color | blue, red, green, orange, violet, cyan, magenta, yellow (Solarized), in this order; blue when the cycle is empty | `default_color_cycle` in [PlotStyle.jl:21](../../source/platform/plot/PlotStyle.jl#L21) | Content of the document: the chart and the sequence chart documents hold the cycle. |
| Julia code in a code field (the expression bar of a data frame) | comment `#808080`, string, character and number `#859900`, operator `#2aa198`, symbol `#6c71c4`, keyword `#d33682`, `true` `false` `nothing` `missing` `#859900` | `_get_julia_code_color` in [JuliaCodePieces.jl:20](../../source/domain/julia/JuliaCodePieces.jl#L20) | The whole file is exempt from the guard: the colors wait for the owner. They do not follow `JuliaTheme`. |
| The placeholder of an empty hinted text | `#808080` (solarized gray) | `make_hinted_text` in [TextDocument.jl:172](../../source/platform/text/TextDocument.jl#L172) | Content of the document. |
| The default color of a graphics element | `GraphicsText` and `GraphicsRect` white `#ffffff`; `GraphicsLine`, `GraphicsCircle`, `GraphicsPolyline`, `GraphicsPolygon`, `GraphicsSpline` black `#000000` | keyword defaults in [GraphicsDocument.jl](../../source/platform/graphics/GraphicsDocument.jl) | Content of the document. |
| The tint of a cached image, when the paint flashes for debugging | six pale colors at 16%: red, green, blue, yellow, magenta, cyan | `_checker_colors` in [GraphicsCaching.jl:54](../../source/platform/graphics/GraphicsCaching.jl#L54) | A view for debugging. |
| The outline of the dirty rectangles, for debugging | `#ff0000` | `_outline_dirty_rects!` in [SdlBackend.jl:2857](../../source/backend/sdl/SdlBackend.jl#L2857) | A view for debugging; raw SDL bytes. |
| The pointer in a recorded video | glyph black with a white outline; arrow white with a black border; crossed circle black and white | `_make_pointer_shape_graphics` in [VideoBackend.jl:392](../../source/backend/video/VideoBackend.jl#L392) | A mark of the recording. |
| The ring of a press in a recorded video | `#cb4b16` (solarized orange), fades after the release | [VideoBackend.jl:443](../../source/backend/video/VideoBackend.jl#L443) | A mark of the recording. |
| The band of a paint fault in a recorded video | band `#dc322f` (solarized red), text white | [VideoBackend.jl:573](../../source/backend/video/VideoBackend.jl#L573) | A mark of the recording. |
| The web page around the canvas | page `#000`, text `#ddd`; the overlay before the first paint `#1b1b1b`, text `#999`; a popup page `#000` | [index.html:8](../../asset/web/index.html#L8), [client.js:284](../../asset/web/client.js#L284) | CSS of the web client. |

The examples hold about 110 color references. 87 of them are
`color_default`; the others are Solarized colors and a few literals for the
content of an example document. They are content, not style.

## 9. Derived colors

| What it draws | Formula | Value with the default themes | Place |
| --- | --- | --- | --- |
| The hover layer of a widget | `primary` at 12% | `#4f46e51f` | `_get_hover_layer`, [WidgetTheme.jl:242](../../source/platform/widget/WidgetTheme.jl#L242) |
| The pressed layer of a widget | `primary` at 20% | `#4f46e533` | `_get_pressed_layer`, [WidgetTheme.jl:243](../../source/platform/widget/WidgetTheme.jl#L243) |
| The band of a selected row of a widget | `GraphicsTheme.selection_ring` at 25% | `#2563eb40` | `_make_selected_row_color`, [WidgetTheme.jl:253](../../source/platform/widget/WidgetTheme.jl#L253) |
| The fill and the ring of `WidgetHighlight` | `primary` at 25%; ring `primary` | `#4f46e540`; `#4f46e5` | [WidgetToGraphics.jl:7428](../../source/platform/widget/WidgetToGraphics.jl#L7428) |
| The fill of a `:tinted` card | half `muted`, half `background` | `#eaeef4` | [WidgetToGraphics.jl:6356](../../source/platform/widget/WidgetToGraphics.jl#L6356) |
| A delimiter near the part under the pointer | `lit_delimiter` mixed into the delimiter color over 4 levels | `#cb4b16` to `#808080` | `_compute_delimiter_color`, [SyntaxToText.jl:812](../../source/platform/syntax/SyntaxToText.jl#L812) |
| A field of a data frame that does not parse | `color_red` lightened by 75% | `#ffbfbf` | `DataFrameTheme.invalid_query`, [DataFrameTheme.jl:36](../../source/adapter/dataframes/DataFrameTheme.jl#L36) |
| A series of a chart while another one is selected | the series color times a veil alpha | — | [ChartPlotToGraphics.jl:40](../../source/domain/chart/ChartPlotToGraphics.jl#L40) |
| The shade under a series, and a series outside the range | the series color times an alpha of the theme | — | [ChartPlotToGraphics.jl:796](../../source/domain/chart/ChartPlotToGraphics.jl#L796), [:947](../../source/domain/chart/ChartPlotToGraphics.jl#L947) |
| An overlay of a sequence chart | the color at an overlay alpha | — | [SequenceChartPlotToGraphics.jl:566](../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L566) |
| The ring of a released press in a video | the ring color, alpha from 1 to 0 | — | [VideoBackend.jl:451](../../source/backend/video/VideoBackend.jl#L451) |

`color_lighten_selection` and `color_darken_selection` in `Color.jl` are
exported, but no code calls them.

## 10. Findings

These are facts that the design of Part 2 must answer. They are not
decisions.

1. **Two palettes.** Solarized gives 162 of the 266 fields, the Tailwind ramps
   give 52. Six themes mix both: `UndoTheme`, `MessageLogTheme`,
   `GestureLogTheme`, `FaultTheme`, `FrameStatisticsTheme` and
   `ConversationTheme`. In these, the plain text is slate and the accent text
   is Solarized cyan.
2. **The window is cream, the widgets are cool gray.** Every window clears to
   `#fdf6e3`. The widget surface is `#f1f5f9`, the card `#f8fafc`. The chart,
   the sequence chart and the command palette also draw on `#fdf6e3`; the plot
   area of a chart, the body of a sequence chart and a graph node are white.
   The window background is not a theme value, so no preset changes it.
3. **Five near-black text colors.** `#000000` (19 fields: `color_default` 12,
   `color_black` 7), `#020617` (widget text), `#0f172a` (help names),
   `#334155` (log messages), `#586e75` (chart text, line numbers).
4. **Seven muted text colors.** `#64748b` (slate_500, 16 fields), `#808080`
   (solarized gray: 7 muted, 5 hint, 9 delimiter, 4 marker, 3 separator
   fields), `#9f9f9f`, `#94a3b8`, `#475569`, `#586e75` and the dormant caret
   `#8c8c8c`. `color_solarized_gray` is not a Solarized tone.
5. **Many colors for selection and hover.** The selection ring `#2563eb`; a
   selected row `#2563eb` at 25%; the widget highlight indigo at 25%; the hover
   and pressed layers indigo at 12% and 20%; the text band `#88bbee` at 25%;
   the chart selection `#88bbee` at 38%, its hover at 16%, its zoom band at
   19%; the chart and sequence chart edge `#268bd2` at 90%, the sequence chart
   hover at 45%; the math wash `#2663ad` at 22%; the search match pure yellow
   `#ffff00`; the graph highlight `#b58900`; the delimiter under the pointer
   `#cb4b16`; the chosen row of the command palette `#859900`.
   `#2563eb`, `#88bbee` and `#2663ad` are not in the palette.
6. **Two error reds, and red that is not an error.** Solarized red `#dc322f`
   marks 11 error fields; Tailwind red-500 `#ef4444` marks 3 (the widget
   `destructive` and two error fields of the conversation). Red also names a
   directory (`FileSystemTheme.directory_text`), a database
   (`DbCatalogTheme.database_text`), the crosshair of a chart, and the second
   series of a chart.
7. **One meaning, many colors** (appendix A.3):
   - a boolean is cyan (syntax, text), yellow (JSON, YAML, a reflected
     object), magenta (the Julia keyword color) or green (Julia code pieces);
   - a number is magenta, but green in Julia and in Julia code pieces;
   - a keyword is magenta (Julia, process, RST directive), blue (SQL, FSM,
     XML tag) or black (database catalog);
   - the name of a declared thing is green (SQL table, FSM, process,
     catalog table), blue (Julia module, formula, catalog schema, file), red
     (catalog database, directory) or magenta (catalog column);
   - a key or a field is blue (JSON, YAML), green (syntax field, XML
     attribute) or cyan (reference);
   - a symbol is blue (syntax), magenta (Julia) or violet (math, code pieces);
   - an operator is cyan (Julia, math), gray (formula) or yellow (math `=`);
   - a type is blue (syntax) or orange (reference);
   - a delimiter is gray, but black and bold in SQL.
8. **One color, many meanings.** Solarized blue holds 27 fields in 12
   sub-roles: heading, keyword, name, key, link, symbol, type, callee,
   variable, a border, an arrow, the query line. Green holds strings, names,
   success, a chosen row and a gesture that can fire. Cyan holds booleans,
   operators, attribute values, the log level "info", the assistant and the
   accent text of three logs.
9. **Three accents.** The widgets use indigo (`#4f46e5`, ring `#6366f1`). The
   logs use Solarized cyan for their accent text. The command palette uses
   Solarized blue for its query and border and green for the chosen row. The
   conversation uses indigo for the user and cyan for the assistant.
10. **Docstrings that say more than the code does.** `WidgetTheme.shadow` says
    "under a card and a popup"; only the button draws it. `accent` says "a
    hovered or a selected item in a list or a menu"; only the toggle uses it,
    and lists and menus use the hover layer. `secondary` says "a secondary
    button"; only the badge uses it.
11. **Dark mode reaches the widgets only.** `WidgetTheme` has two dark
    presets. No domain theme, and not `TextTheme`, `SyntaxTheme`,
    `GraphicsTheme` or the window background, has a dark variant. 19 fields
    are `#000000`, most of them text.
12. **Numbers outside the palette.** 28 theme fields are literal numbers,
    most of them in `ChartTheme` (10) and `SequenceChartTheme` (8). Many are a
    palette color at an alpha, written as numbers.

## 11. What a recolor touches

- The palette: [Color.jl](../../source/platform/style/Color.jl).
- 32 theme files, and the presets of three of them.
- The fixed colors of section 8, of which the window background has 14
  copies.
- The derived colors of section 9.
- Tests: 37 files under `test/` name a color, with 208 references in total.
  A test that asserts a color value changes with the recolor.
- omnet-julia and inet-julia: they read the themes of projectured-julia, and
  they fix colors of their own (about 156 and 11 in the inventory of
  2026-10-02, section 2.6 of
  [default-look-fits-a-desktop.md](default-look-fits-a-desktop.md)). This
  catalog does not list them.
- Open questions for the owner that touch a color already: the panel of the
  newest gestures, and the colors of `compute_code_pieces` (both in section 6,
  Part T of [default-look-fits-a-desktop.md](default-look-fits-a-desktop.md)).

## 12. Part 2: the design

Not started. The owner decides the direction after reading the catalog.

## Appendix A. The tables

The tables come from the source as it stands on 2026-10-04 (main at
`759a7ce2a`). A script read each `@theme struct` block, took the default of
each field whose type is `StyleColor` or `TextRole`, and resolved the palette
name to its value from `Color.jl`. The roles were set by hand from the
docstrings.

### A.1 Every color field of every theme

The columns: the field, its value, the palette name (or `literal` for a value
that is written as numbers), the role from section 4, the font changes of a
text role, and the docstring of the field, which says what it draws.

#### `WidgetTheme` — 23 colors

[WidgetTheme.jl](../../source/platform/widget/WidgetTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `background` | `#f1f5f9` | slate_100 | surface / window |  | The surface behind the widgets of a window. |
| `foreground` | `#020617` | slate_950 | text / body |  | The text and the marks on the background. |
| `card` | `#f8fafc` | slate_50 | surface / raised |  | The surface of a card, an alert and a panel. |
| `card_foreground` | `#020617` | slate_950 | text / body |  | The text on a card. |
| `popover` | `#f8fafc` | slate_50 | surface / raised |  | The surface of a menu, a popup and a tooltip. |
| `popover_foreground` | `#020617` | slate_950 | text / body |  | The text on a menu, a popup and a tooltip. |
| `muted` | `#e2e8f0` | slate_200 | surface / quiet |  | A quiet surface: a disabled control, a skeleton, a track. |
| `muted_foreground` | `#64748b` | slate_500 | text / muted |  | Quiet text: a caption, a hint, a placeholder. |
| `primary` | `#4f46e5` | indigo_600 | accent / fill |  | The color of the main action: a default button, a checked box, a selected item. |
| `primary_foreground` | `#f8fafc` | slate_50 | text / on accent |  | The text on the primary color. |
| `secondary` | `#e2e8f0` | slate_200 | surface / quiet |  | The surface of a secondary button. |
| `secondary_foreground` | `#0f172a` | slate_900 | text / body |  | The text on a secondary button. |
| `accent` | `#e0e7ff` | indigo_100 | accent / tint |  | The surface of a hovered or a selected item in a list or a menu. |
| `accent_foreground` | `#4338ca` | indigo_700 | accent / text |  | The text on the accent color. |
| `destructive` | `#ef4444` | destructive | status / error |  | The color of an action that deletes or an error. |
| `destructive_foreground` | `#fafafa` | destructive_fg | text / on accent |  | The text on the destructive color. |
| `border` | `#cbd5e1` | slate_300 | line / border |  | The border of a card, a pane and a separator. |
| `input` | `#cbd5e1` | slate_300 | line / border |  | The border of a control that takes text or a value. |
| `ring` | `#6366f1` | indigo_500 | accent / focus ring |  | The focus ring of a control. |
| `track_off` | `#cbd5e1` | slate_300 | surface / quiet |  | The track of a switch that is off. |
| `shadow` | `#00000014` | black @ 8% | overlay / shadow |  | The shadow under a card and a popup. |
| `scrim` | `#00000066` | black @ 40% | overlay / scrim |  | The layer that covers the window behind a dialog. |
| `knob` | `#ffffff` | white | surface / raised |  | The knob of a switch and of a slider. |

#### `GraphicsTheme` — 2 colors

[GraphicsTheme.jl](../../source/platform/graphics/GraphicsTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `fault_text` (text) | `#dc322f` | solarized_red | status / error | weight=700 | The mark of a fault that a projection of the graphics domain raised. |
| `selection_ring` | `#2563eb` | literal | selection / ring |  | The ring around an object that is selected as a whole. |

#### `TextTheme` — 15 colors

[TextTheme.jl](../../source/platform/text/TextTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `caret` | `#000000` | black | selection / caret |  | The caret of the text that holds the keyboard. |
| `dormant_caret` | `#8c8c8c` | literal | selection / caret |  | The caret of a text that keeps its place while another holds the keyboard. |
| `highlight` | `#88bbee40` | literal @ 25% | selection / band |  | The band under the selected text, while its text holds the keyboard. |
| `dormant_highlight` | `#88888828` | literal @ 16% | selection / band |  | The band under the selected text, while another text holds the keyboard. |
| `bool_text` (text) | `#2aa198` | solarized_cyan | token / boolean |  | A boolean that a primitive projection prints as text. |
| `number_text` (text) | `#d33682` | solarized_magenta | token / number |  | A number that a primitive projection prints as text. |
| `string_text` (text) | `#859900` | solarized_green | token / string |  | A string that a primitive projection prints as text. |
| `wrong_color` | `#dc322f` | solarized_red | status / error |  | The text of a type-in that is no value yet, such as `1e` on the way to a number. |
| `placeholder_text` (text) | `#85990080` | completion_hint | text / hint |  | What an empty type-in shows, such as `missing` in a cell of a data frame. |
| `plain_text` (text) | `#000000` | default | text / body |  | A text that no other field styles, such as the name of an empty document. |
| `line_number_text` (text) | `#586e75` | solarized_content_darker (literal) | text / muted |  | The number before each line of a text with line numbers. |
| `match_highlight` | `#ffff00` | yellow | selection / match |  | The surface behind each match of a search in a text. |
| `inverted_background` | `#073642` | solarized_background_dark | selection / caret |  | The surface of the character under a block caret, which shows inverted. |
| `inverted_foreground` | `#93a1a1` | solarized_content_lighter | selection / caret |  | The character under a block caret, which shows inverted. |
| `fault_text` (text) | `#dc322f` | solarized_red | status / error | family=DejaVu Sans Mono, weight=700, relative_size=0.8 | The mark of a part whose projection failed, in place of that part. |

#### `SyntaxTheme` — 21 colors

[SyntaxTheme.jl](../../source/platform/syntax/SyntaxTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `bool_text` (text) | `#2aa198` | solarized_cyan | token / boolean |  | A boolean value. |
| `number_text` (text) | `#d33682` | solarized_magenta | token / number |  | A number value. |
| `string_text` (text) | `#859900` | solarized_green | token / string |  | A string value. |
| `quote_text` (text) | `#b58900` | solarized_yellow | token / quote |  | The quotes around a string or a character. |
| `symbol_text` (text) | `#268bd2` | solarized_blue | token / symbol |  | A symbol, in the reflected display of an object. |
| `nothing_text` (text) | `#d33682` | solarized_magenta | token / null |  | The value `nothing`, in the reflected display of an object. |
| `reflected_bool_text` (text) | `#b58900` | solarized_yellow | token / boolean |  | A boolean value, in the reflected display of an object. |
| `type_name_text` (text) | `#268bd2` | solarized_blue | token / type | weight=700 | The name of the type of an object. |
| `field_name_text` (text) | `#859900` | solarized_green | token / key / field |  | The name of a field. |
| `note_text` (text) | `#808080` | solarized_gray | text / muted | italic=true | The muted italic text of an undefined field, of a cycle and of an empty placeholder. |
| `delimiter_text` (text) | `#808080` | solarized_gray | token / delimiter | weight=700 | A bracket. |
| `separator_text` (text) | `#808080` | solarized_gray | token / separator |  | A comma. |
| `label_text` (text) | `#808080` | solarized_gray | text / hint |  | The prefix and the suffix, and the placeholder of an empty buffer, of the insertion. |
| `typed_text` (text) | `#000000` | default | text / body |  | The typed text of the insertion while it names nothing yet. |
| `hint_text` (text) | `#85990080` | completion_hint | text / completion |  | The continuation that a completion offers. |
| `wrong_color` | `#dc322f` | solarized_red | status / error |  | The color of the typed text of the insertion while it names nothing. |
| `found_color` | `#859900` | solarized_green | status / success |  | The color of the typed text of the insertion while it names one thing. |
| `lit_delimiter` | `#cb4b16` | solarized_orange | selection / pointer |  | The color of the delimiters around the part under the pointer. |
| `object_delimiter_text` (text) | `#000000` | default | token / delimiter |  | A bracket and a space of a reflected object, in the font of its field names. |
| `ellipsis_text` (text) | `#808080` | solarized_gray | text / muted | family=DejaVu Sans Mono | The ellipsis that stands in for the children of a folded node, in the size of the text around it. |
| `fault_text` (text) | `#dc322f` | solarized_red | status / error | family=DejaVu Sans Mono, weight=700, relative_size=0.8 | The mark of a part whose projection failed, in place of that part. |

#### `ReferenceTheme` — 6 colors

[ReferenceTheme.jl](../../source/platform/text/ReferenceTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `punctuation_color` | `#808080` | solarized_gray | token / delimiter |  | A delimiter, a comma or a colon, and the plain words of a phrase, such as \"the \" or \"of \". |
| `name_color` | `#2aa198` | solarized_cyan | token / key / field |  | The name of a field or of a step. |
| `index_color` | `#d33682` | solarized_magenta | token / number |  | An element index, a position, a range bound, or a point coordinate. |
| `type_color` | `#cb4b16` | solarized_orange | token / type |  | The type that a step descends from, or the parent type of a step, when it is known. |
| `projection_color` | `#b58900` | solarized_yellow | token / name |  | The name of a projection. |
| `unknown_color` | `#dc322f` | solarized_red | status / error |  | A step of a kind neither form describes, and a type that is not found. |

#### `ConversationTheme` — 16 colors

[ConversationTheme.jl](../../source/platform/conversation/ConversationTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `user_role_text` (text) | `#4f46e5` | indigo_600 | accent / role | weight=700, relative_size=0.9 | The label beside a turn whose role is the user. |
| `assistant_role_text` (text) | `#2aa198` | solarized_cyan | accent / role | weight=700, relative_size=0.9 | The label beside a turn whose role is the assistant. |
| `other_role_text` (text) | `#475569` | slate_600 | accent / role | weight=700, relative_size=0.9 | The label beside a turn whose role is neither the user nor the assistant. |
| `user_role_icon` (text) | `#4f46e5` | indigo_600 | accent / role | family=Lucide | The glyph beside a turn whose role is the user. |
| `assistant_role_icon` (text) | `#2aa198` | solarized_cyan | accent / role | family=Lucide | The glyph beside a turn whose role is the assistant. |
| `other_role_icon` (text) | `#475569` | slate_600 | accent / role | family=Lucide | The glyph beside a turn whose role is neither the user nor the assistant. |
| `kind_text` (text) | `#475569` | slate_600 | text / muted | weight=700, relative_size=0.8 | The tag that names a part's kind: a code's language, \"thinking\", or the name of a tool. |
| `section_text` (text) | `#64748b` | slate_500 | text / muted | relative_size=0.8 | The title of a section of an evaluation: its code or its result. |
| `error_text` (text) | `#ef4444` | destructive | status / error | weight=700, relative_size=0.8 | The title of a section of an evaluation whose result is an error. |
| `prompt_text` (text) | `#64748b` | slate_500 | text / muted | base=:code_font | The `>`/`=` prompt before the code or the result of a form. |
| `error_prompt_text` (text) | `#ef4444` | destructive | status / error | base=:code_font | The `=` prompt before the result of a form whose evaluation failed. |
| `plain_color` | `#000000` | default | text / body |  | The typed text of an editable part of the composer. |
| `placeholder_color` | `#808080` | solarized_gray | text / hint |  | The placeholder of an empty part, and the static words of a kind chooser. |
| `valid_color` | `#859900` | solarized_green | status / success |  | The value of a kind chooser that names a known kind. |
| `invalid_color` | `#dc322f` | solarized_red | status / error |  | The value of a kind chooser that names no kind. |
| `completion_hint_color` | `#85990080` | completion_hint | text / completion |  | The hint that completes the value of a kind chooser. |

#### `GestureHelpTheme` — 11 colors

[GestureHelpTheme.jl](../../source/platform/gesturehelp/GestureHelpTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `map_header_text` (text) | `#268bd2` | solarized_blue | text / heading | family=Ubuntu Mono, weight=700 | The heading of a domain's group of rows in the gesture map. |
| `map_gesture_text` (text) | `#859900` | solarized_green | accent / text | family=Ubuntu Mono, weight=700 | A gesture that can fire. |
| `map_description_text` (text) | `#000000` | default | text / body | family=Ubuntu Mono | What a gesture does. |
| `map_muted_text` (text) | `#808080` | solarized_gray | text / muted | family=Ubuntu Mono | A row that cannot fire for the current selection. |
| `palette_query_text` (text) | `#268bd2` | solarized_blue | accent / text | weight=700 | The line the person types into. |
| `palette_header_text` (text) | `#6c71c4` | solarized_violet | text / heading | weight=700 | The heading of a domain's group of rows in the palette. |
| `palette_selected_text` (text) | `#859900` | solarized_green | selection / item | weight=700 | The chosen row. |
| `palette_command_text` (text) | `#000000` | default | text / body |  | A row that can run. |
| `palette_muted_text` (text) | `#808080` | solarized_gray | text / muted |  | A row that cannot run right now. |
| `palette_background` | `#fdf6e3` | solarized_background_lighter | surface / raised |  | The fill of the panel the palette draws itself on. |
| `palette_border` | `#268bd2` | solarized_blue | line / border |  | The border of the panel the palette draws itself on. |

#### `GestureLogTheme` — 6 colors

[GestureLogTheme.jl](../../source/platform/gesturelog/GestureLogTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `index_text` (text) | `#64748b` | slate_500 | text / muted |  | The number of the entry. |
| `gesture_text` (text) | `#2aa198` | solarized_cyan | accent / text | weight=700 | The gesture that the entry records. |
| `operation_text` (text) | `#334155` | slate_700 | text / body |  | The operation the gesture makes. |
| `muted_text` (text) | `#64748b` | slate_500 | text / muted |  | A line that records a selection, which is context and not a change. |
| `empty_text` (text) | `#64748b` | slate_500 | text / muted |  | The line the log shows while it holds no gesture. |
| `panel_background` | `#000000b8` | black @ 72% | overlay / panel |  | The surface of the panel that shows the log over the content of a window: dark and translucent, so the content stays readable and the light text of the log reads over any content. |

#### `UndoTheme` — 6 colors

[UndoTheme.jl](../../source/platform/undo/UndoTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `index_text` (text) | `#64748b` | slate_500 | text / muted |  | The label and the number of a step. |
| `step_text` (text) | `#334155` | slate_700 | text / body |  | A step that can be taken back. |
| `ahead_text` (text) | `#64748b` | slate_500 | text / muted |  | A step that can be put back. |
| `empty_text` (text) | `#64748b` | slate_500 | text / muted |  | The line the history shows while it holds no step. |
| `marker_text` (text) | `#2aa198` | solarized_cyan | accent / text | weight=700 | The line for where the document stands now. |
| `barrier_text` (text) | `#cb4b16` | solarized_orange | status / warning | weight=700 | A step the history stops at, because it can not be undone. |

#### `MessageLogTheme` — 6 colors

[MessageLogTheme.jl](../../source/platform/log/MessageLogTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `level_text` (text) | `#2aa198` | solarized_cyan | status / info | weight=700 | The level of a message of information, such as `Info`. |
| `error_level_text` (text) | `#dc322f` | solarized_red | status / error | weight=700 | The level of an error, such as `Error`. |
| `warning_level_text` (text) | `#b58900` | solarized_yellow | status / warning | weight=700 | The level of a warning, such as `Warn`. |
| `debug_level_text` (text) | `#64748b` | slate_500 | text / muted | weight=700 | The level of a message for debugging, such as `Debug`. |
| `message_text` (text) | `#334155` | slate_700 | text / body |  | The text of the message. |
| `empty_text` (text) | `#64748b` | slate_500 | text / muted |  | The line the log shows while it holds no message. |

#### `FaultTheme` — 6 colors

[FaultTheme.jl](../../source/platform/fault/FaultTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `count_text` (text) | `#64748b` | slate_500 | text / muted |  | The count of the occurrences of a fault. |
| `site_text` (text) | `#64748b` | slate_500 | text / muted |  | The barrier that catches a fault, such as `print`, `device` or `tool`. |
| `origin_text` (text) | `#dc322f` | solarized_red | status / error | weight=700 | The name of the type or the function whose code fails. |
| `message_text` (text) | `#334155` | slate_700 | text / body |  | The message of the first occurrence of a fault. |
| `empty_text` (text) | `#64748b` | slate_500 | text / muted |  | The line the log shows while it holds no fault. |
| `panel_background` | `#2e0505cc` | literal @ 80% | overlay / panel |  | The surface of the panel that shows the log over the content of a window: dark and translucent, with a red cast, so the content stays readable and the panel says that it is not chrome. |

#### `FrameStatisticsTheme` — 3 colors

[FrameStatisticsTheme.jl](../../source/platform/statistics/FrameStatisticsTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `header_text` (text) | `#2aa198` | solarized_cyan | text / heading | weight=700 | The head line and the column header. |
| `row_text` (text) | `#334155` | slate_700 | text / body |  | One measurement. |
| `empty_text` (text) | `#64748b` | slate_500 | text / muted |  | The line the table shows while it holds no frame. |

#### `HelpTheme` — 6 colors

[HelpTheme.jl](../../source/platform/help/HelpTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `heading_text` (text) | `#475569` | slate_600 | text / heading |  | The line that says what a list holds. |
| `name_text` (text) | `#0f172a` | slate_900 | text / heading | weight=700, relative_size=1.125 | The name of a type, in a list. |
| `detail_text` (text) | `#64748b` | slate_500 | text / muted |  | The package and the typed names of a type, in a list; the version, the Julia version and the home page, on the about page. |
| `description_text` (text) | `#334155` | slate_700 | text / body |  | The first paragraph of a type's docstring, in a list; the sentence of the about page. |
| `muted_text` (text) | `#94a3b8` | slate_400 | text / muted | italic=true | The line a list shows for a type with no docstring. |
| `title_text` (text) | `#0f172a` | slate_900 | text / heading | weight=700, relative_size=1.5 | The name of the program, on the about page. |

#### `InspectorTheme` — 1 colors

[InspectorTheme.jl](../../source/platform/inspector/InspectorTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `header_color` | `#268bd2` | solarized_blue | text / heading |  | The \"Compact\" and \"Human-readable\" section headers. |

#### `FileSystemTheme` — 2 colors

[FileSystemTheme.jl](../../source/platform/filesystem/FileSystemTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `file_text` (text) | `#268bd2` | solarized_blue | token / name |  | The basename of a file. |
| `directory_text` (text) | `#dc322f` | solarized_red | token / name | weight=700 | The name of a directory. |

#### `DataFrameTheme` — 2 colors

[DataFrameTheme.jl](../../source/adapter/dataframes/DataFrameTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `invalid_query` | `#ffbfbf` | red lightened 0.75 | status / error |  | A field of the filter row or of the expression bar whose text does not parse. |
| `unsorted_glyph` | `#9f9f9f` | gray159 | text / muted |  | The glyph of the header of a column that does not sort. |

#### `JsonTheme` — 8 colors

[JsonTheme.jl](../../source/domain/json/JsonTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `null_text` (text) | `#d33682` | solarized_magenta | token / null |  | A null value. |
| `bool_text` (text) | `#b58900` | solarized_yellow | token / boolean |  | A boolean value. |
| `number_text` (text) | `#d33682` | solarized_magenta | token / number |  | A number value. |
| `string_text` (text) | `#859900` | solarized_green | token / string |  | A string value. |
| `quote_text` (text) | `#b58900` | solarized_yellow | token / quote |  | The quotes around a string. |
| `key_text` (text) | `#268bd2` | solarized_blue | token / key / field |  | The key of an object member, with its quotes. |
| `delimiter_text` (text) | `#808080` | solarized_gray | token / delimiter | weight=700 | The brackets of an array and the braces of an object. |
| `separator_text` (text) | `#808080` | solarized_gray | token / separator |  | A comma, and the colon of a member. |

#### `YamlTheme` — 7 colors

[YamlTheme.jl](../../source/domain/yaml/YamlTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `null_text` (text) | `#d33682` | solarized_magenta | token / null |  | A null value. |
| `bool_text` (text) | `#b58900` | solarized_yellow | token / boolean |  | A boolean value. |
| `number_text` (text) | `#d33682` | solarized_magenta | token / number |  | A number value. |
| `string_text` (text) | `#859900` | solarized_green | token / string |  | A string value. |
| `key_text` (text) | `#268bd2` | solarized_blue | token / key / field |  | The key of a mapping entry. |
| `delimiter_text` (text) | `#808080` | solarized_gray | token / delimiter | weight=700 | The brackets of a flow sequence, the braces of a flow mapping, and the `- ` marker of a block sequence. |
| `separator_text` (text) | `#808080` | solarized_gray | token / separator |  | A comma, and the colon of a mapping entry. |

#### `XmlTheme` — 6 colors

[XmlTheme.jl](../../source/domain/xml/XmlTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `content_text` (text) | `#000000` | black | text / body |  | The text of a text node. |
| `tag_text` (text) | `#268bd2` | solarized_blue | token / keyword | weight=700 | The name of an element's opening and closing tag. |
| `delimiter_text` (text) | `#808080` | solarized_gray | token / delimiter |  | The angle brackets of a tag. |
| `attribute_name_text` (text) | `#859900` | solarized_green | token / key / field |  | The name of an attribute. |
| `quote_text` (text) | `#b58900` | solarized_yellow | token / quote |  | The quotes around an attribute value. |
| `attribute_value_text` (text) | `#2aa198` | solarized_cyan | token / string |  | The value of an attribute. |

#### `SqlTheme` — 4 colors

[SqlTheme.jl](../../source/domain/sql/SqlTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `keyword_text` (text) | `#268bd2` | solarized_blue | token / keyword | weight=700 | A reserved word, such as `SELECT`, `FROM`, `WHERE` or `AND`. |
| `plain_text` (text) | `#000000` | default | text / body |  | A column, a value, a raw expression, a data type, or any other identifier that is not a keyword or a table name. |
| `name_text` (text) | `#859900` | solarized_green | token / name |  | A table name. |
| `punctuation_text` (text) | `#000000` | default | token / delimiter | weight=700 | The brackets, the commas, the spaces and the semicolons between the parts of a statement. |

#### `DbCatalogTheme` — 5 colors

[DbCatalogTheme.jl](../../source/domain/dbcatalog/DbCatalogTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `column_text` (text) | `#d33682` | solarized_magenta | token / name |  | A column, with its type. |
| `table_text` (text) | `#859900` | solarized_green | token / name | weight=700 | The name of a table. |
| `schema_text` (text) | `#268bd2` | solarized_blue | token / name | weight=700 | The name of a schema. |
| `database_text` (text) | `#dc322f` | solarized_red | token / name | weight=700 | The name of a database and of an RDBMS. |
| `keyword_text` (text) | `#000000` | default | token / keyword |  | The keyword that opens a group of children, such as \"Columns\", \"Tables\", \"Schemas\" or \"Databases\". |

#### `JuliaTheme` — 12 colors

[JuliaTheme.jl](../../source/domain/julia/JuliaTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `identifier_text` (text) | `#6c71c4` | solarized_violet | token / identifier |  | A variable, and the label of an object that stands in the code, such as a widget pasted into a form. |
| `literal_text` (text) | `#859900` | solarized_green | token / string |  | A number, a string, a character, a chunk of an interpolated string, the quotes of a string interpolation, and a docstring. |
| `punctuation_text` (text) | `#808080` | solarized_gray | token / delimiter |  | A quote, a delimiter, a separator, a brace and a fence. |
| `keyword_text` (text) | `#d33682` | solarized_magenta | token / keyword | weight=700 | A keyword, `true`, `false` and `nothing`. |
| `symbol_text` (text) | `#d33682` | solarized_magenta | token / symbol |  | A symbol, `<:`, `->`, and the dollar sign of a string interpolation. |
| `operator_text` (text) | `#2aa198` | solarized_cyan | token / operator |  | An operator, the dot of a field access, a range, `::`, `=` and `?:`. |
| `callee_text` (text) | `#268bd2` | solarized_blue | token / callee |  | The called function, and the name of a macro. |
| `name_text` (text) | `#268bd2` | solarized_blue | token / name | weight=700 | The name of a module. |
| `plain_text` (text) | `#000000` | default | text / body |  | The path of a `using`, and the typed text of the insertion. |
| `hint_text` (text) | `#85990080` | completion_hint | text / completion |  | The completion that the insertion offers. |
| `wrong_color` | `#dc322f` | solarized_red | status / error |  | The color of the typed text of the insertion while it names nothing. |
| `found_color` | `#859900` | solarized_green | status / success |  | The color of the typed text of the insertion while it names one thing. |

#### `MathTheme` — 10 colors

[MathTheme.jl](../../source/domain/math/MathTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `variable_text` (text) | `#268bd2` | solarized_blue | token / identifier | base=:code_font | A variable. |
| `operator_text` (text) | `#2aa198` | solarized_cyan | token / operator | base=:code_font | An operator, and the `/` of a fraction. |
| `chrome_text` (text) | `#808080` | solarized_gray | token / delimiter | base=:code_font | A parenthesis, a brace, a bracket and the insertion leaf. |
| `symbol_text` (text) | `#6c71c4` | solarized_violet | token / symbol | base=:code_font | A symbol. |
| `name_text` (text) | `#859900` | solarized_green | token / callee | base=:code_font | The name of a function, a radical, a big operator, a differential, a derivative, an accent, a matrix or a case list. |
| `word_text` (text) | `#000000` | default | text / body | base=:code_font | A run of plain text. |
| `equals_text` (text) | `#b58900` | solarized_yellow | token / operator | base=:code_font | The `=` of an assignment. |
| `ink` | `#000000` | default | text / body |  | The color of every part. |
| `hint` | `#808080` | solarized_gray | text / hint |  | The color of an empty slot. |
| `selection_wash` | `#2663ad38` | literal @ 22% | selection / fill |  | The color that washes a selected box. |

#### `FormulaTheme` — 5 colors

[FormulaTheme.jl](../../source/domain/formula/FormulaTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `insertion_text` (text) | `#808080` | solarized_gray | text / hint | base=:plain_font | The \"insert formula\" placeholder. |
| `reference_text` (text) | `#6c71c4` | solarized_violet | token / reference | base=:plain_font, weight=700 | A reference to another formula, by its current name. |
| `name_text` (text) | `#268bd2` | solarized_blue | token / name | base=:plain_font, weight=700 | The name of a formula. |
| `operator_text` (text) | `#808080` | solarized_gray | token / operator | base=:plain_font | The `=` and the `⇒` of a formula's line. |
| `result_text` (text) | `#859900` | solarized_green | token / string | base=:plain_font | The value of a formula. |

#### `FsmTheme` — 6 colors

[FsmTheme.jl](../../source/domain/fsm/FsmTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `keyword_text` (text) | `#268bd2` | solarized_blue | token / keyword | weight=700 | The keywords: `component`, `variable`, `timer`, `event`, `machine`, `state`, `initial`, `on`, `when`, `stay`, `ignore`, `entry` and `ignoring unhandled`. |
| `name_text` (text) | `#859900` | solarized_green | token / name |  | The name of a component, a variable, a timer, an event, a machine or a state. |
| `reference_text` (text) | `#6c71c4` | solarized_violet | token / reference |  | A trigger, a target and an `initial`, read from the referenced part, and the reference of a transition label in a diagram. |
| `chrome_text` (text) | `#808080` | solarized_gray | token / delimiter |  | The punctuation around a part, and the chrome of a transition label in a diagram. |
| `state_label_text` (text) | `#859900` | solarized_green | token / name | weight=700 | The name of a state in a diagram. |
| `trigger_text` (text) | `#268bd2` | solarized_blue | token / keyword |  | The keyword of a transition label in a diagram. |

#### `ProcessTheme` — 7 colors

[ProcessTheme.jl](../../source/domain/process/ProcessTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `keyword_text` (text) | `#d33682` | solarized_magenta | token / keyword | weight=700 | `process`, `step`, `if`, `else`, `while`, `for`, `in`, `break`, `continue` and `return`, and the keyword of a diagram label. |
| `name_text` (text) | `#859900` | solarized_green | token / name |  | The name of a process, and a `for`'s variable. |
| `action_text` (text) | `#2aa198` | solarized_cyan | token / string |  | The description of a step, and the text of a step label in a diagram. |
| `chrome_text` (text) | `#808080` | solarized_gray | token / delimiter |  | The punctuation around a part, an unrefined `<condition>`, `<variable>` or `<iterable>` marker, the chrome of a diagram label, and an edge label. |
| `current_text` (text) | `#cb4b16` | solarized_orange | status / warning | weight=700 | The keyword of the node where a debug session stops. |
| `breakpoint_text` (text) | `#dc322f` | solarized_red | status / error | weight=700 | The keyword of a node that holds a breakpoint. |
| `terminal_text` (text) | `#859900` | solarized_green | token / keyword | weight=700 | The label of the start or the stop terminal in a diagram. |

#### `GraphTheme` — 4 colors

[GraphTheme.jl](../../source/domain/graph/GraphTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `node_fill` | `#ffffff` | white | surface / plot |  | The fill of the box of a node, under its content. |
| `node_border` | `#586e75` | solarized_content_darker | line / border |  | The border of the box of a node. |
| `edge` | `#586e75` | solarized_content_darker | line / edge |  | The line of an edge and its arrowhead. |
| `highlight` | `#b58900` | solarized_yellow | selection / pointer |  | The ring around a highlighted node, and the line over a highlighted edge. |

#### `ChartTheme` — 13 colors

[ChartTheme.jl](../../source/domain/chart/ChartTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `background` | `#fdf6e3` | solarized_background_lighter | surface / window |  | The canvas behind the whole chart. |
| `plot_background` | `#ffffff` | white (literal) | surface / plot |  | The plot rectangle, under the series. |
| `axis` | `#657b83` | solarized_content_dark | line / axis |  | The two axis lines, the tick marks and the border of the grid frame. |
| `grid` | `#0000001a` | black @ 10% | line / grid |  | A gridline. |
| `text_color` | `#586e75` | solarized_content_darker | text / body |  | The title, the axis titles, the tick labels and the legend's \"and N more\" line. |
| `selected_fill` | `#88bbee60` | literal @ 38% | selection / fill |  | The fill of a selected part. |
| `selected_edge` | `#268bd2e6` | solarized_blue @ 90% | selection / ring |  | The outline of a selected part. |
| `hover_fill` | `#88bbee28` | literal @ 16% | selection / hover |  | The fill of a hovered legend item. |
| `strip_swatch` | `#8080808c` | literal @ 55% | data / mark |  | The legend swatch of a strip series, neutral because the band draws in many colors. |
| `strip_edge` | `#0000001a` | black @ 10% | line / grid |  | The border between adjacent strip segments. |
| `strip_contrast_text` | `#ffffff` | white (literal) | text / on accent |  | The label of a strip segment whose own color is too dark for the normal text color. |
| `crosshair` | `#dc322fb2` | solarized_red @ 70% | data / readout |  | The readout lines of the pointer. |
| `band_fill` | `#88bbee30` | literal @ 19% | selection / band |  | The rubber band of a zoom drag. |

#### `SequenceChartTheme` — 12 colors

[SequenceChartTheme.jl](../../source/domain/sequencechart/SequenceChartTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `background` | `#fdf6e3` | solarized_background_lighter | surface / window |  | The whole canvas, behind the body. |
| `body_background` | `#ffffff` | white (literal) | surface / plot |  | The body, where the lanes and their events draw. |
| `axis` | `#657b83` | solarized_content_dark | line / axis |  | A lane's line, when the lane names no color of its own. |
| `text_color` | `#586e75` | solarized_content_darker | text / body |  | A tick, a lane name, a title, a readout, and a label. |
| `gutter` | `#fffff0` | literal | surface / quiet |  | The time-scale strip, when the chart names no color of its own. |
| `gutter_border` | `#00000040` | black @ 25% | line / border |  | The border of the gutter strip. |
| `hairline` | `#00000024` | black @ 14% | line / grid |  | The dotted line a tick draws down through the body. |
| `zero_time` | `#0000000e` | black @ 6% | data / wash |  | The wash over a stretch where the clock stands still. |
| `arrow` | `#268bd2` | solarized_blue | data / mark |  | An arrow, when its kind names no color of its own. |
| `event` | `#d33682` | solarized_magenta (literal) | data / mark |  | An occurrence, when its kind names no color of its own. |
| `selected` | `#268bd2e6` | solarized_blue @ 90% | selection / ring |  | The ring, the highlight and the cursor line of a selection. |
| `hover` | `#268bd273` | solarized_blue @ 45% | selection / hover |  | The ring and the highlight of what the pointer is over. |

#### `MarkdownTheme` — 12 colors

[MarkdownTheme.jl](../../source/domain/markdown/MarkdownTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `marker_text` (text) | `#808080` | solarized_gray | token / markup marker | base=:code_font | A marker: an insertion placeholder, a tick, a break, an emphasis mark, a quote mark, a bullet, a pipe, a bracket, a fence. |
| `source_text` (text) | `#000000` | black | text / body | base=:code_font | The text of the source form, and the root. |
| `code_text` (text) | `#859900` | solarized_green | token / string | base=:code_font | A code span and a code block, in the source form. |
| `language_text` (text) | `#d33682` | solarized_magenta | token / keyword | base=:code_font | The language of a code block, and the value of an inline code span in the rendered form. |
| `heading_marker_text` (text) | `#268bd2` | solarized_blue | text / heading | base=:code_font, weight=700 | The `#` marker of a heading, in the source form. |
| `url_text` (text) | `#6c71c4` | solarized_violet | token / reference | base=:code_font | The url of a link or an image. |
| `alt_text` (text) | `#2aa198` | solarized_cyan | token / string | base=:code_font | The alt text of an image. |
| `body_text` (text) | `#000000` | black | text / body |  | The plain prose of the rendered form. |
| `heading_color` | `#268bd2` | solarized_blue | text / heading |  | The color of a heading in the rendered form. |
| `link_color` | `#268bd2` | solarized_blue | token / reference |  | The color of a link in the rendered form. |
| `caption_text` (text) | `#808080` | solarized_gray | text / muted | italic=true | The caption under a rendered image. |
| `rendered_marker_text` (text) | `#808080` | solarized_gray | token / markup marker | base=:code_font, family=DejaVu Sans Mono | A marker of the rendered form: a thematic break rule, a quote bar, a code fence's language, a list marker. |

#### `RstTheme` — 14 colors

[RstTheme.jl](../../source/domain/rst/RstTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `marker_text` (text) | `#808080` | solarized_gray | token / markup marker | base=:code_font | A marker: an insertion placeholder, a tick, an emphasis or strong mark, a bullet, a transition, a comment, a directive's chrome, or any other marker. |
| `source_text` (text) | `#000000` | black | text / body | base=:code_font | The text, the root, a value and an argument, in the source form. |
| `literal_text` (text) | `#859900` | solarized_green | token / string | base=:code_font | A literal, a literal block, and a code block's code. |
| `target_text` (text) | `#6c71c4` | solarized_violet | token / reference | base=:code_font | A role name, a target, a path, and a role definition. |
| `value_text` (text) | `#2aa198` | solarized_cyan | token / string | base=:code_font | A role's value and a math block. |
| `reference_text` (text) | `#268bd2` | solarized_blue | token / reference | base=:code_font | A reference, a footnote label, a field name, a toctree entry, and a section's adornment. |
| `substitution_text` (text) | `#cb4b16` | solarized_orange | token / reference | base=:code_font | A substitution reference and the name of a substitution definition. |
| `directive_text` (text) | `#d33682` | solarized_magenta | token / keyword | base=:code_font | The name of a directive and the language of a code block. |
| `admonition_text` (text) | `#b58900` | solarized_yellow | token / keyword | base=:code_font, weight=700 | The `.. kind::` marker of an admonition. |
| `title_text` (text) | `#268bd2` | solarized_blue | text / heading | base=:code_font, weight=700 | The title of a section, in the source form. |
| `body_text` (text) | `#000000` | black | text / body |  | The plain prose of the rendered form. |
| `title_color` | `#268bd2` | solarized_blue | text / heading |  | The color of a section title in the rendered form. |
| `caption_text` (text) | `#808080` | solarized_gray | text / muted | italic=true | The caption under a rendered figure. |
| `rendered_marker_text` (text) | `#808080` | solarized_gray | token / markup marker | base=:code_font, family=DejaVu Sans Mono | A marker of the rendered form: a transition rule, and the arrow of a literal include. |

#### `BookTheme` — 9 colors

[BookTheme.jl](../../source/domain/book/BookTheme.jl)

| Field | Value | Name | Role | Font change | What it draws |
| --- | --- | --- | --- | --- | --- |
| `title_text` (text) | `#268bd2` | solarized_blue | text / heading | weight=700, relative_size=1.8 | The title of a book. |
| `author_prefix_text` (text) | `#808080` | solarized_gray | text / muted | italic=true | The \"Written by \" that introduces the author. |
| `author_text` (text) | `#2aa198` | solarized_cyan | token / name | italic=true | The author of a book. |
| `chapter_title_text` (text) | `#268bd2` | solarized_blue | text / heading | weight=700, relative_size=1.2 | The title of a chapter. |
| `numbering_text` (text) | `#d33682` | solarized_magenta | text / heading | weight=700, relative_size=1.2 | The numbering of a chapter. |
| `paragraph_text` (text) | `#000000` | black | text / body | base=:code_font | A paragraph, and the blank line between the elements of a book or a chapter. |
| `placeholder_text` (text) | `#808080` | solarized_gray | text / hint | base=:code_font | The insertion leaf, and a picture with no path yet. |
| `bullet_text` (text) | `#b58900` | solarized_yellow | token / markup marker | base=:code_font | The bullet of a list item. |
| `picture_text` (text) | `#d33682` | solarized_magenta | text / muted | base=:code_font | The caption of a picture. |

### A.2 The distinct values

Each value that a theme field holds, with the fields that hold it. A value
with an alpha below 100% is a separate value.

| Value | Name | Family | Fields | Roles | Fields that hold it |
| --- | --- | --- | --- | --- | --- |
| `#808080` | solarized_gray | Solarized | 29 | token/delimiter ×9, text/muted ×7, text/hint ×5, token/markup marker ×4, token/separator ×3, token/operator | GestureHelp.map_muted_text, GestureHelp.palette_muted_text, Syntax.note_text, Syntax.delimiter_text, Syntax.separator_text, Syntax.label_text, Syntax.ellipsis_text, Conversation.placeholder_color, Reference.punctuation_color, Json.delimiter_text, Json.separator_text, Markdown.marker_text, Markdown.caption_text, Markdown.rendered_marker_text, Julia.punctuation_text, Fsm.chrome_text, Process.chrome_text, Formula.insertion_text, Formula.operator_text, Xml.delimiter_text, Math.chrome_text, Math.hint, Book.author_prefix_text, Book.placeholder_text, Yaml.delimiter_text, Yaml.separator_text, Rst.marker_text, Rst.caption_text, Rst.rendered_marker_text |
| `#268bd2` | solarized_blue | Solarized | 27 | text/heading ×8, token/name ×4, token/keyword ×4, token/key / field ×2, token/reference ×2, accent/text, line/border, token/symbol, token/type, token/callee, data/mark, token/identifier | Inspector.header_color, GestureHelp.map_header_text, GestureHelp.palette_query_text, GestureHelp.palette_border, Syntax.symbol_text, Syntax.type_name_text, FileSystem.file_text, Json.key_text, Markdown.heading_marker_text, Markdown.heading_color, Markdown.link_color, Julia.callee_text, Julia.name_text, Fsm.keyword_text, Fsm.trigger_text, Formula.name_text, SequenceChart.arrow, Xml.tag_text, DbCatalog.schema_text, Math.variable_text, Book.title_text, Book.chapter_title_text, Sql.keyword_text, Yaml.key_text, Rst.reference_text, Rst.title_text, Rst.title_color |
| `#859900` | solarized_green | Solarized | 22 | token/string ×8, token/name ×5, status/success ×3, token/key / field ×2, accent/text, selection/item, token/keyword, token/callee | GestureHelp.map_gesture_text, GestureHelp.palette_selected_text, Syntax.string_text, Syntax.field_name_text, Syntax.found_color, Conversation.valid_color, Text.string_text, Json.string_text, Markdown.code_text, Julia.literal_text, Julia.found_color, Fsm.name_text, Fsm.state_label_text, Process.name_text, Process.terminal_text, Formula.result_text, Xml.attribute_name_text, DbCatalog.table_text, Math.name_text, Sql.name_text, Yaml.string_text, Rst.literal_text |
| `#000000` | black / default | Default / Pure | 19 | text/body ×15, token/delimiter ×2, selection/caret, token/keyword | GestureHelp.map_description_text, GestureHelp.palette_command_text, Syntax.typed_text, Syntax.object_delimiter_text, Conversation.plain_color, Text.caret, Text.plain_text, Markdown.source_text, Markdown.body_text, Julia.plain_text, Xml.content_text, DbCatalog.keyword_text, Math.word_text, Math.ink, Book.paragraph_text, Sql.plain_text, Sql.punctuation_text, Rst.source_text, Rst.body_text |
| `#d33682` | solarized_magenta / solarized_magenta (literal) | Solarized / literal | 17 | token/number ×5, token/keyword ×4, token/null ×3, token/symbol, data/mark, token/name, text/heading, text/muted | Syntax.number_text, Syntax.nothing_text, Reference.index_color, Text.number_text, Json.null_text, Json.number_text, Markdown.language_text, Julia.keyword_text, Julia.symbol_text, Process.keyword_text, SequenceChart.event, DbCatalog.column_text, Book.numbering_text, Book.picture_text, Yaml.null_text, Yaml.number_text, Rst.directive_text |
| `#64748b` | slate_500 | Slate | 16 | text/muted ×16 | Undo.index_text, Undo.ahead_text, Undo.empty_text, MessageLog.debug_level_text, MessageLog.empty_text, GestureLog.index_text, GestureLog.muted_text, GestureLog.empty_text, FrameStatistics.empty_text, Help.detail_text, Fault.count_text, Fault.site_text, Fault.empty_text, Widget.muted_foreground, Conversation.section_text, Conversation.prompt_text |
| `#2aa198` | solarized_cyan | Solarized | 16 | token/string ×4, accent/text ×2, token/boolean ×2, accent/role ×2, token/operator ×2, status/info, text/heading, token/key / field, token/name | Undo.marker_text, MessageLog.level_text, GestureLog.gesture_text, Syntax.bool_text, FrameStatistics.header_text, Conversation.assistant_role_text, Conversation.assistant_role_icon, Reference.name_color, Text.bool_text, Markdown.alt_text, Julia.operator_text, Process.action_text, Xml.attribute_value_text, Math.operator_text, Book.author_text, Rst.value_text |
| `#dc322f` | solarized_red | Solarized | 13 | status/error ×11, token/name ×2 | Graphics.fault_text, MessageLog.error_level_text, Syntax.wrong_color, Syntax.fault_text, FileSystem.directory_text, Fault.origin_text, Conversation.invalid_color, Reference.unknown_color, Text.wrong_color, Text.fault_text, Julia.wrong_color, Process.breakpoint_text, DbCatalog.database_text |
| `#b58900` | solarized_yellow | Solarized | 12 | token/quote ×3, token/boolean ×3, status/warning, token/name, selection/pointer, token/operator, token/markup marker, token/keyword | MessageLog.warning_level_text, Syntax.quote_text, Syntax.reflected_bool_text, Reference.projection_color, Json.bool_text, Json.quote_text, Graph.highlight, Xml.quote_text, Math.equals_text, Book.bullet_text, Yaml.bool_text, Rst.admonition_text |
| `#6c71c4` | solarized_violet | Solarized | 7 | token/reference ×4, text/heading, token/identifier, token/symbol | GestureHelp.palette_header_text, Markdown.url_text, Julia.identifier_text, Fsm.reference_text, Formula.reference_text, Math.symbol_text, Rst.target_text |
| `#334155` | slate_700 | Slate | 6 | text/body ×6 | Undo.step_text, MessageLog.message_text, GestureLog.operation_text, FrameStatistics.row_text, Help.description_text, Fault.message_text |
| `#cb4b16` | solarized_orange | Solarized | 5 | status/warning ×2, selection/pointer, token/type, token/reference | Undo.barrier_text, Syntax.lit_delimiter, Reference.type_color, Process.current_text, Rst.substitution_text |
| `#ffffff` | white / white (literal) | Pure / literal | 5 | surface/plot ×3, surface/raised, text/on accent | Widget.knob, Graph.node_fill, Chart.plot_background, Chart.strip_contrast_text, SequenceChart.body_background |
| `#586e75` | solarized_content_darker / solarized_content_darker (literal) | Solarized / literal | 5 | text/body ×2, text/muted, line/border, line/edge | Text.line_number_text, Graph.node_border, Graph.edge, Chart.text_color, SequenceChart.text_color |
| `#85990080` | completion_hint | Solarized | 4 | text/completion ×3, text/hint | Syntax.hint_text, Conversation.completion_hint_color, Text.placeholder_text, Julia.hint_text |
| `#475569` | slate_600 | Slate | 4 | accent/role ×2, text/heading, text/muted | Help.heading_text, Conversation.other_role_text, Conversation.other_role_icon, Conversation.kind_text |
| `#fdf6e3` | solarized_background_lighter | Solarized | 3 | surface/window ×2, surface/raised | GestureHelp.palette_background, Chart.background, SequenceChart.background |
| `#0f172a` | slate_900 | Slate | 3 | text/heading ×2, text/body | Help.name_text, Help.title_text, Widget.secondary_foreground |
| `#020617` | slate_950 | Slate | 3 | text/body ×3 | Widget.foreground, Widget.card_foreground, Widget.popover_foreground |
| `#f8fafc` | slate_50 | Slate | 3 | surface/raised ×2, text/on accent | Widget.card, Widget.popover, Widget.primary_foreground |
| `#4f46e5` | indigo_600 | Indigo | 3 | accent/role ×2, accent/fill | Widget.primary, Conversation.user_role_text, Conversation.user_role_icon |
| `#ef4444` | destructive | Tailwind red | 3 | status/error ×3 | Widget.destructive, Conversation.error_text, Conversation.error_prompt_text |
| `#cbd5e1` | slate_300 | Slate | 3 | line/border ×2, surface/quiet | Widget.border, Widget.input, Widget.track_off |
| `#e2e8f0` | slate_200 | Slate | 2 | surface/quiet ×2 | Widget.muted, Widget.secondary |
| `#657b83` | solarized_content_dark | Solarized | 2 | line/axis ×2 | Chart.axis, SequenceChart.axis |
| `#0000001a` | black @ 10% | literal | 2 | line/grid ×2 | Chart.grid, Chart.strip_edge |
| `#268bd2e6` | solarized_blue @ 90% | literal | 2 | selection/ring ×2 | Chart.selected_edge, SequenceChart.selected |
| `#ffbfbf` | red lightened 0.75 | literal | 1 | status/error | DataFrame.invalid_query |
| `#9f9f9f` | gray159 | Gray | 1 | text/muted | DataFrame.unsorted_glyph |
| `#2563eb` | literal | literal | 1 | selection/ring | Graphics.selection_ring |
| `#000000b8` | black @ 72% | literal | 1 | overlay/panel | GestureLog.panel_background |
| `#94a3b8` | slate_400 | Slate | 1 | text/muted | Help.muted_text |
| `#2e0505cc` | literal @ 80% | literal | 1 | overlay/panel | Fault.panel_background |
| `#f1f5f9` | slate_100 | Slate | 1 | surface/window | Widget.background |
| `#e0e7ff` | indigo_100 | Indigo | 1 | accent/tint | Widget.accent |
| `#4338ca` | indigo_700 | Indigo | 1 | accent/text | Widget.accent_foreground |
| `#fafafa` | destructive_fg | Tailwind red | 1 | text/on accent | Widget.destructive_foreground |
| `#6366f1` | indigo_500 | Indigo | 1 | accent/focus ring | Widget.ring |
| `#00000014` | black @ 8% | literal | 1 | overlay/shadow | Widget.shadow |
| `#00000066` | black @ 40% | literal | 1 | overlay/scrim | Widget.scrim |
| `#8c8c8c` | literal | literal | 1 | selection/caret | Text.dormant_caret |
| `#88bbee40` | literal @ 25% | literal | 1 | selection/band | Text.highlight |
| `#88888828` | literal @ 16% | literal | 1 | selection/band | Text.dormant_highlight |
| `#ffff00` | yellow | Pure | 1 | selection/match | Text.match_highlight |
| `#073642` | solarized_background_dark | Solarized | 1 | selection/caret | Text.inverted_background |
| `#93a1a1` | solarized_content_lighter | Solarized | 1 | selection/caret | Text.inverted_foreground |
| `#88bbee60` | literal @ 38% | literal | 1 | selection/fill | Chart.selected_fill |
| `#88bbee28` | literal @ 16% | literal | 1 | selection/hover | Chart.hover_fill |
| `#8080808c` | literal @ 55% | literal | 1 | data/mark | Chart.strip_swatch |
| `#dc322fb2` | solarized_red @ 70% | literal | 1 | data/readout | Chart.crosshair |
| `#88bbee30` | literal @ 19% | literal | 1 | selection/band | Chart.band_fill |
| `#fffff0` | literal | literal | 1 | surface/quiet | SequenceChart.gutter |
| `#00000040` | black @ 25% | literal | 1 | line/border | SequenceChart.gutter_border |
| `#00000024` | black @ 14% | literal | 1 | line/grid | SequenceChart.hairline |
| `#0000000e` | black @ 6% | literal | 1 | data/wash | SequenceChart.zero_time |
| `#268bd273` | solarized_blue @ 45% | literal | 1 | selection/hover | SequenceChart.hover |
| `#2663ad38` | literal @ 22% | literal | 1 | selection/fill | Math.selection_wash |

### A.3 One meaning, by theme

For each sub-role of the roles `token`, `text`, `selection` and `status`: the
values that hold it, and the themes that use each value.

#### Role `token`

| Sub-role | Value | Name | Fields |
| --- | --- | --- | --- |
| boolean | `#b58900` | solarized_yellow | Syntax.reflected_bool_text, Json.bool_text, Yaml.bool_text |
|  | `#2aa198` | solarized_cyan | Syntax.bool_text, Text.bool_text |
| callee | `#268bd2` | solarized_blue | Julia.callee_text |
|  | `#859900` | solarized_green | Math.name_text |
| delimiter | `#808080` | solarized_gray | Syntax.delimiter_text, Reference.punctuation_color, Json.delimiter_text, Julia.punctuation_text, Fsm.chrome_text, Process.chrome_text, Xml.delimiter_text, Math.chrome_text, Yaml.delimiter_text |
|  | `#000000` | default | Syntax.object_delimiter_text, Sql.punctuation_text |
| identifier | `#6c71c4` | solarized_violet | Julia.identifier_text |
|  | `#268bd2` | solarized_blue | Math.variable_text |
| key / field | `#859900` | solarized_green | Syntax.field_name_text, Xml.attribute_name_text |
|  | `#268bd2` | solarized_blue | Json.key_text, Yaml.key_text |
|  | `#2aa198` | solarized_cyan | Reference.name_color |
| keyword | `#d33682` | solarized_magenta | Markdown.language_text, Julia.keyword_text, Process.keyword_text, Rst.directive_text |
|  | `#268bd2` | solarized_blue | Fsm.keyword_text, Fsm.trigger_text, Xml.tag_text, Sql.keyword_text |
|  | `#859900` | solarized_green | Process.terminal_text |
|  | `#000000` | default | DbCatalog.keyword_text |
|  | `#b58900` | solarized_yellow | Rst.admonition_text |
| markup marker | `#808080` | solarized_gray | Markdown.marker_text, Markdown.rendered_marker_text, Rst.marker_text, Rst.rendered_marker_text |
|  | `#b58900` | solarized_yellow | Book.bullet_text |
| name | `#859900` | solarized_green | Fsm.name_text, Fsm.state_label_text, Process.name_text, DbCatalog.table_text, Sql.name_text |
|  | `#268bd2` | solarized_blue | FileSystem.file_text, Julia.name_text, Formula.name_text, DbCatalog.schema_text |
|  | `#dc322f` | solarized_red | FileSystem.directory_text, DbCatalog.database_text |
|  | `#b58900` | solarized_yellow | Reference.projection_color |
|  | `#d33682` | solarized_magenta | DbCatalog.column_text |
|  | `#2aa198` | solarized_cyan | Book.author_text |
| null | `#d33682` | solarized_magenta | Syntax.nothing_text, Json.null_text, Yaml.null_text |
| number | `#d33682` | solarized_magenta | Syntax.number_text, Reference.index_color, Text.number_text, Json.number_text, Yaml.number_text |
| operator | `#2aa198` | solarized_cyan | Julia.operator_text, Math.operator_text |
|  | `#808080` | solarized_gray | Formula.operator_text |
|  | `#b58900` | solarized_yellow | Math.equals_text |
| quote | `#b58900` | solarized_yellow | Syntax.quote_text, Json.quote_text, Xml.quote_text |
| reference | `#6c71c4` | solarized_violet | Markdown.url_text, Fsm.reference_text, Formula.reference_text, Rst.target_text |
|  | `#268bd2` | solarized_blue | Markdown.link_color, Rst.reference_text |
|  | `#cb4b16` | solarized_orange | Rst.substitution_text |
| separator | `#808080` | solarized_gray | Syntax.separator_text, Json.separator_text, Yaml.separator_text |
| string | `#859900` | solarized_green | Syntax.string_text, Text.string_text, Json.string_text, Markdown.code_text, Julia.literal_text, Formula.result_text, Yaml.string_text, Rst.literal_text |
|  | `#2aa198` | solarized_cyan | Markdown.alt_text, Process.action_text, Xml.attribute_value_text, Rst.value_text |
| symbol | `#268bd2` | solarized_blue | Syntax.symbol_text |
|  | `#d33682` | solarized_magenta | Julia.symbol_text |
|  | `#6c71c4` | solarized_violet | Math.symbol_text |
| type | `#268bd2` | solarized_blue | Syntax.type_name_text |
|  | `#cb4b16` | solarized_orange | Reference.type_color |

#### Role `text`

| Sub-role | Value | Name | Fields |
| --- | --- | --- | --- |
| body | `#000000` | default | GestureHelp.map_description_text, GestureHelp.palette_command_text, Syntax.typed_text, Conversation.plain_color, Text.plain_text, Markdown.source_text, Markdown.body_text, Julia.plain_text, Xml.content_text, Math.word_text, Math.ink, Book.paragraph_text, Sql.plain_text, Rst.source_text, Rst.body_text |
|  | `#334155` | slate_700 | Undo.step_text, MessageLog.message_text, GestureLog.operation_text, FrameStatistics.row_text, Help.description_text, Fault.message_text |
|  | `#020617` | slate_950 | Widget.foreground, Widget.card_foreground, Widget.popover_foreground |
|  | `#586e75` | solarized_content_darker | Chart.text_color, SequenceChart.text_color |
|  | `#0f172a` | slate_900 | Widget.secondary_foreground |
| completion | `#85990080` | completion_hint | Syntax.hint_text, Conversation.completion_hint_color, Julia.hint_text |
| heading | `#268bd2` | solarized_blue | Inspector.header_color, GestureHelp.map_header_text, Markdown.heading_marker_text, Markdown.heading_color, Book.title_text, Book.chapter_title_text, Rst.title_text, Rst.title_color |
|  | `#0f172a` | slate_900 | Help.name_text, Help.title_text |
|  | `#6c71c4` | solarized_violet | GestureHelp.palette_header_text |
|  | `#2aa198` | solarized_cyan | FrameStatistics.header_text |
|  | `#475569` | slate_600 | Help.heading_text |
|  | `#d33682` | solarized_magenta | Book.numbering_text |
| hint | `#808080` | solarized_gray | Syntax.label_text, Conversation.placeholder_color, Formula.insertion_text, Math.hint, Book.placeholder_text |
|  | `#85990080` | completion_hint | Text.placeholder_text |
| muted | `#64748b` | slate_500 | Undo.index_text, Undo.ahead_text, Undo.empty_text, MessageLog.debug_level_text, MessageLog.empty_text, GestureLog.index_text, GestureLog.muted_text, GestureLog.empty_text, FrameStatistics.empty_text, Help.detail_text, Fault.count_text, Fault.site_text, Fault.empty_text, Widget.muted_foreground, Conversation.section_text, Conversation.prompt_text |
|  | `#808080` | solarized_gray | GestureHelp.map_muted_text, GestureHelp.palette_muted_text, Syntax.note_text, Syntax.ellipsis_text, Markdown.caption_text, Book.author_prefix_text, Rst.caption_text |
|  | `#9f9f9f` | gray159 | DataFrame.unsorted_glyph |
|  | `#94a3b8` | slate_400 | Help.muted_text |
|  | `#475569` | slate_600 | Conversation.kind_text |
|  | `#586e75` | solarized_content_darker (literal) | Text.line_number_text |
|  | `#d33682` | solarized_magenta | Book.picture_text |
| on accent | `#f8fafc` | slate_50 | Widget.primary_foreground |
|  | `#fafafa` | destructive_fg | Widget.destructive_foreground |
|  | `#ffffff` | white (literal) | Chart.strip_contrast_text |

#### Role `selection`

| Sub-role | Value | Name | Fields |
| --- | --- | --- | --- |
| band | `#88bbee40` | literal @ 25% | Text.highlight |
|  | `#88888828` | literal @ 16% | Text.dormant_highlight |
|  | `#88bbee30` | literal @ 19% | Chart.band_fill |
| caret | `#000000` | black | Text.caret |
|  | `#8c8c8c` | literal | Text.dormant_caret |
|  | `#073642` | solarized_background_dark | Text.inverted_background |
|  | `#93a1a1` | solarized_content_lighter | Text.inverted_foreground |
| fill | `#88bbee60` | literal @ 38% | Chart.selected_fill |
|  | `#2663ad38` | literal @ 22% | Math.selection_wash |
| hover | `#88bbee28` | literal @ 16% | Chart.hover_fill |
|  | `#268bd273` | solarized_blue @ 45% | SequenceChart.hover |
| item | `#859900` | solarized_green | GestureHelp.palette_selected_text |
| match | `#ffff00` | yellow | Text.match_highlight |
| pointer | `#cb4b16` | solarized_orange | Syntax.lit_delimiter |
|  | `#b58900` | solarized_yellow | Graph.highlight |
| ring | `#268bd2e6` | solarized_blue @ 90% | Chart.selected_edge, SequenceChart.selected |
|  | `#2563eb` | literal | Graphics.selection_ring |

#### Role `status`

| Sub-role | Value | Name | Fields |
| --- | --- | --- | --- |
| error | `#dc322f` | solarized_red | Graphics.fault_text, MessageLog.error_level_text, Syntax.wrong_color, Syntax.fault_text, Fault.origin_text, Conversation.invalid_color, Reference.unknown_color, Text.wrong_color, Text.fault_text, Julia.wrong_color, Process.breakpoint_text |
|  | `#ef4444` | destructive | Widget.destructive, Conversation.error_text, Conversation.error_prompt_text |
|  | `#ffbfbf` | red lightened 0.75 | DataFrame.invalid_query |
| info | `#2aa198` | solarized_cyan | MessageLog.level_text |
| success | `#859900` | solarized_green | Syntax.found_color, Conversation.valid_color, Julia.found_color |
| warning | `#cb4b16` | solarized_orange | Undo.barrier_text, Process.current_text |
|  | `#b58900` | solarized_yellow | MessageLog.warning_level_text |
