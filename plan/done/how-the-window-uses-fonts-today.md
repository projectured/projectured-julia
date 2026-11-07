# How the window uses fonts today

> **Kind:** study · **Status:** facts only, no decision · **Date:** 2026-11-05

The owner asked on 2026-11-05 for a study of the fonts in projectured-julia and
omnet-julia: "I feel like the font sizes are too often very similar and we should
also use different fonts and/or font sizes for titles, emphasis and or less
important parts." This file holds the facts that a plan needs. It holds no
decision. The summary with specimens at their true sizes is the artifact
"Editor Type Study".

Three read-only studies made the parts below, with grep and sed and no Julia
run. I checked the main claims against the code. One correction: every role
rounds to a whole pixel (`apply_font_role`, `source/platform/style/FontRole.jl:62-66`),
so the chart title is 14 px and `font_small` is 12 px; the omnet part first gave
the values before rounding.

- Part 1: the platform layer, `source/platform/**`.
- Part 2: the domains, the adapters and the font back end.
- Part 3: omnet-julia.

## Part 1 — Font study, platform layer (`source/platform/**`)

Read-only inventory. Paths are relative to `/home/projectured/workspace/projectured-julia/source/platform/`.

How a size is computed (`style/FontRole.jl:63-67`): `apply_font_role(role, base)` gives `max(1, round(Int, base.size * relative_size))` (Julia `round` on a half goes to even), and the family, weight and slant of the base unless the role sets its own. `Appearance.font_scale` multiplies the base size (`style/Appearance.jl:138`, `scale_length`), so all sizes below are at scale 1.0 ("default"). Sizes are px at default. Weight 400 = regular, 700 = bold. "base" is the `font` field of the theme unless said otherwise.

Fonts that ship (`style/FontFace.jl:25-58`): DejaVu Sans (400, 400i, 700), DejaVu Sans Mono (400, 400i, 700), Liberation Mono/Sans/Serif (400, 700, with italics), Lucide (icons), Noto Emoji, Ubuntu (300, 400, 500, 700, each with italic), Ubuntu Condensed (400), Ubuntu Mono (400, 400i, 700, 700i). Default family constant: DejaVu Sans (`style/FontFace.jl:154`).

Scope notes. 23 `@theme struct` hits: 21 real themes (`style/Theme.jl:287` and `:318` are docstring examples). Themes with text styles: 20. `ColorTheme` (`style/ColorTheme.jl:32`) has no fonts. `TaskTheme` (`task/TaskTheme.jl:12`) has no font field: it holds colors and a button size only; the task pane draws with widget labels. `GraphicsTheme` has a font only for the fault mark. The use site of each theme field was read from docstrings and from the printer that reads the field; where I only know the docstring, the "UI part" says so.

---

### A. Every text style

Abbreviations: U = Ubuntu, UM = Ubuntu Mono, DSM = DejaVu Sans Mono, DS = DejaVu Sans, LS = Liberation Sans, Lu = Lucide. Italic column: n = no, i = italic. Category names are those of the request.

#### A1. Widget theme fonts and the text styles derived from them (the UI chrome)

Defined at `widget/WidgetTheme.jl:97` (`font = StyleFont("Ubuntu", 13)`), `:99` (`font_bold = FontRole(weight = 700)`), `:101` (`font_small = FontRole(relative_size = 0.9)`). The derived styles are `widget/WidgetTheme.jl:260-264`: body = font on `foreground`; title = font_bold on `foreground`; caption = font_small on `muted_foreground`; label = font on `foreground`; link = font on `link`. Also `make_widget_theme(; font = StyleFont("Ubuntu", 13))` at `:242,:248`.

| category | UI part | file:line | family | px | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|
| window chrome / body | base font of every widget | widget/WidgetTheme.jl:97 | U | 13 | 400 | n | foreground | theme `font` |
| title | bold font of a title/header | widget/WidgetTheme.jl:99 | U | 13 | 700 | n | (set by use) | theme `font_bold` |
| secondary | small font of caption/badge | widget/WidgetTheme.jl:101 | U | 12 (13*0.9=11.7) | 400 | n | (set by use) | theme `font_small` |
| body | label (WidgetLabel) | widget/WidgetToGraphics.jl:482 | U | 13 | 400 | n | foreground | `_get_body_text` |
| body | text widget `WidgetText`, label; placeholder | widget/WidgetToGraphics.jl:517,519,521 | U | 13 | 400 | n | foreground / muted_foreground (disabled, placeholder) | `_get_body_text`, inline `StyleText(t.font, t.muted_foreground)` |
| label | checkbox label | widget/WidgetToGraphics.jl:574,576 | U | 13 | 400 | n | foreground / muted_foreground (disabled) | `_get_body_text`, inline |
| window chrome | button label | widget/WidgetToGraphics.jl:619,621 | U | 13 | 400 | n | foreground / muted_foreground (disabled) | `_get_label_text`, inline |
| label | link | widget/WidgetToGraphics.jl:661,662 | U | 13 | 400 | n | link / muted_foreground (disabled) | `_get_link_text`, inline |
| tooltip | widget tooltip label (WidgetTooltip) | widget/WidgetToGraphics.jl:694 | U | 13 | 400 | n | popover_foreground | inline |
| window chrome | menu item label | widget/WidgetToGraphics.jl:767,769 | U | 13 | 400 | n | foreground / muted_foreground (disabled) | `_get_body_text`, inline |
| secondary | menu item key hint (the keys at the right edge) | widget/WidgetToGraphics.jl:774 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| window chrome | menu / menu bar (font only measures the row height; items are menu items) | widget/WidgetToGraphics.jl:721-727 (font `t.font` at :726) | U | 13 | 400 | n | n/a | inline `t -> t.font` |
| window chrome | toolbar item label | widget/WidgetToGraphics.jl:805,807 | U | 13 | 400 | n | foreground / muted_foreground (disabled) | `_get_body_text`, inline |
| window chrome | tab (unselected) | widget/WidgetToGraphics.jl:957 | U | 13 | 400 | n | muted_foreground | inline |
| window chrome | tab (selected) | widget/WidgetToGraphics.jl:958 | U | 13 | 400 | n | foreground | inline |
| title | title pane title (WidgetTitlePane) | widget/WidgetToGraphics.jl:885 | U | 13 | 700 | n | foreground | `_get_title_text` |
| body | title pane body | widget/WidgetToGraphics.jl:886 | U | 13 | 400 | n | card_foreground | inline |
| title | dialog title | widget/WidgetToGraphics.jl:3024 | U | 13 | 700 | n | foreground | `_get_title_text` |
| body | dialog body | widget/WidgetToGraphics.jl:3025 | U | 13 | 400 | n | foreground | `_get_body_text` |
| body | insertion label | widget/WidgetToGraphics.jl:1956 | U | 13 | 400 | n | foreground | `_get_body_text` |
| window chrome / secondary | status bar label | widget/WidgetToGraphics.jl:7729 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| badge/status | icon label | widget/WidgetToGraphics.jl:8121 | U | 13 | 400 | n | foreground | inline |
| badge/status | badge, 9 tones (default, secondary, destructive, outline, success, warning, error, info, accent) | widget/WidgetToGraphics.jl:8189,8194,8199,8204,8207,8210,8213,8216,8219 | U | 12 | 400 | n | primary/secondary/destructive/foreground/success/warning/error/info/accent_foreground | inline `StyleText(t.font_small, ...)` |
| badge/status | numeric count mark on an icon | widget/WidgetDecoration.jl:111 (share 0.6 at :92) | family of the badge label (U) | max(8, round(0.6 * icon box px)) | 400 | n | badge label color | inline `with_font_size` |
| title | card title | widget/WidgetToGraphics.jl:8409 | U | 13 | 700 | n | foreground | `_get_title_text` |
| secondary | card description | widget/WidgetToGraphics.jl:8410 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| body | card body | widget/WidgetToGraphics.jl:8411 | U | 13 | 400 | n | card_foreground | inline |
| secondary | card footer | widget/WidgetToGraphics.jl:8412 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| label | switch label | widget/WidgetToGraphics.jl:8920,8922 | U | 13 | 400 | n | foreground / muted_foreground (disabled) | `_get_body_text`, inline |
| label | radio group label | widget/WidgetToGraphics.jl:9390,9392 | U | 13 | 400 | n | foreground / muted_foreground | `_get_body_text`, inline |
| badge/status | avatar initials | widget/WidgetToGraphics.jl:9558 (size = 0.42 * avatar px, `:9563`, `:9589`) | U | round(0.42 * avatar px), at least 1 | 400 | n | muted_foreground | inline `with_font_size` |
| title | alert title | widget/WidgetToGraphics.jl:9628 | U | 13 | 700 | n | foreground | `_get_title_text` |
| secondary | alert description | widget/WidgetToGraphics.jl:9629 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| error/fault | alert title in destructive variant | widget/WidgetToGraphics.jl:9632 | U | 13 | 700 | n | destructive | inline `StyleText(t.font_bold, t.destructive)` |
| label | toggle label (on / off / disabled) | widget/WidgetToGraphics.jl:10076,10078,10080 | U | 13 | 400 | n | foreground / accent_foreground / muted_foreground | `_get_body_text`, inline |
| label | toggle group item (unselected / selected / disabled) | widget/WidgetToGraphics.jl:10171,10172,10174 | U | 13 | 400 | n | muted_foreground / foreground / muted_foreground | inline, `_get_body_text` |
| label | select (dropdown) label | widget/WidgetToGraphics.jl:10376,10378 | U | 13 | 400 | n | foreground / muted_foreground | `_get_body_text`, inline |
| body | option label | widget/WidgetToGraphics.jl:10510 | U | 13 | 400 | n | foreground | `_get_body_text` |
| value/number | spin box text | widget/WidgetToGraphics.jl:10599,10601 | U | 13 | 400 | n | foreground / muted_foreground | `_get_body_text`, inline |
| tree/list row | list (WidgetList) item | widget/WidgetToGraphics.jl:10907 | U | 13 | 400 | n | foreground | `_get_body_text` |
| body | textarea | widget/WidgetToGraphics.jl:11083,11085 | U | 13 | 400 | n | foreground / muted_foreground | `_get_body_text`, inline |
| title | accordion item title | widget/WidgetToGraphics.jl:11204 (drawn at :11319) | U | 13 | 700 | n | foreground | `_get_title_text` |
| secondary | accordion body | widget/WidgetToGraphics.jl:11205 | U | 12 | 400 | n | muted_foreground | `_get_caption_text` |
| tree/list row | tree row label | widget/WidgetToGraphics.jl:12805 | U | 13 | 400 | n | foreground | `_get_body_text` |
| tree/list row | tree row icon text | widget/WidgetToGraphics.jl:12806 | U | 13 | 400 | n | muted_foreground | inline |
| secondary | tree row detail | widget/WidgetToGraphics.jl:12821 | U | 13 | 400 | n | muted_foreground | inline `StyleText(t.font, t.muted_foreground)` |
| table header, table cell | WidgetTable: no style of its own. `font` at :11608 is `t.font` for measuring; header and cell widgets are the content (usually labels) | widget/WidgetToGraphics.jl:11598-11610; header test `:11652` | U | 13 | 400 | n | foreground | unknown to the table; content decides |
| window chrome | icons (glyphs of Lucide) registered at 20, drawn at the icon box size | widget/WidgetToGraphics.jl:10023, 9906 | Lu | icon box px (`icon_size` 1.0 of the line height) | 400 | n | caller | inline `StyleFont("Lucide", 20)` marked `@style` |

Settings and appearance (platform printers that use the widget fonts):

| category | UI part | file:line | family | px | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|
| secondary | summary/description style of settings cards | settingsmanaging/SettingsToWidget.jl:61 | U | 12 | 400 | n | muted_foreground | inline `StyleText(values.font_small, values.muted_foreground)` |
| section heading | heading of a theme group in the Appearance tab | appearance/AppearanceToWidget.jl:213 | U | 13 | 700 | n | muted_foreground | inline `StyleText(theme.font_bold, theme.muted_foreground)` |
| secondary | caption of a field row in the Appearance tab | appearance/AppearanceToWidget.jl:362 | U | 12 | 400 | n | muted_foreground | inline `StyleText(font_small, muted_foreground)` |

#### A2. Other themes (one table row per font or text field)

| category | UI part | file:line | family | px | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|
| code/mono | Text document: unstyled text base | text/TextTheme.jl:25 | UM | 14 | 400 | n | (document) | `TextTheme.font` |
| body/content | text placeholder, plain text, bool, number, string, line number | text/TextTheme.jl:43,45,47,51,53,55 | UM | 14 | 400 | n | boolean_literal, number_literal, string_literal, text_faint, text, text_muted | `TextRole` no size change |
| error/fault | fault mark in text | text/TextTheme.jl:63-64 | DSM | 11 (14*0.8=11.2) | 700 | n | error_text | `TextRole(...relative_size = 0.8)` |
| code/mono | Syntax view base (indent, line break) | syntax/SyntaxTheme.jl:62 | UM | 14 | 400 | n | n/a | `SyntaxTheme.font` |
| code/mono | syntax bool, number, string, char, quote, symbol, nothing, reflected bool (8 fields) | syntax/SyntaxTheme.jl:26,28,30,32,34,36,38,40 | UM | 14 | 400 | n | literal roles | TextRole |
| code/mono | field name, separator, object delimiter, typed text | syntax/SyntaxTheme.jl:44,50,64,54 | UM | 14 | 400 | n | field, punctuation, punctuation, text | TextRole |
| secondary | node label, hint | syntax/SyntaxTheme.jl:52,56 | UM | 14 | 400 | n | text_faint | TextRole |
| emphasis | type name; delimiter | syntax/SyntaxTheme.jl:42,48 | UM | 14 | 700 | n | type_name; punctuation | TextRole |
| secondary / emphasis | note text | syntax/SyntaxTheme.jl:46 | UM | 14 | 400 | i | text_muted | TextRole |
| code/mono | folded-node ellipsis | syntax/SyntaxTheme.jl:66 | DSM | 14 | 400 | n | text_muted | TextRole family override |
| error/fault | syntax fault mark | syntax/SyntaxTheme.jl:68-69 | DSM | 11 | 700 | n | error_text | TextRole |
| code/mono | graphics fault mark base | graphics/GraphicsTheme.jl:19 | DSM | 13 | 400 | n | n/a | `GraphicsTheme.font` |
| error/fault | graphics fault mark | graphics/GraphicsTheme.jl:21 | DSM | 13 | 700 | n | error_text | TextRole |
| code/mono | Terminal base | terminal/TerminalTheme.jl:15 | UM | 14 | 400 | n | n/a | `font` |
| code/mono | terminal output; error; status | terminal/TerminalTheme.jl:17,19,23 | UM | 14 | 400 | n | text; error_text; text_muted | TextRole |
| code/mono | terminal input line | terminal/TerminalTheme.jl:21 | UM | 14 | 700 | n | text | TextRole |
| tooltip | Tooltip base | tooltip/TooltipTheme.jl:30 | U | 13 | 400 | n | n/a | `font` |
| secondary | tooltip layer line (the title of a layer, and the keys line) | tooltip/TooltipTheme.jl:38 | U | 12 | 400 | n | text_faint | TextRole relative_size 0.9 |
| tooltip / title | tooltip note title | tooltip/TooltipTheme.jl:40 | U | 13 | 700 | n | text | TextRole |
| tooltip / body | tooltip body; muted | tooltip/TooltipTheme.jl:42,44 | U | 13 | 400 | n | text; text_muted | TextRole |
| value/number, code/mono | tooltip value | tooltip/TooltipTheme.jl:46 | UM | 13 | 400 | n | text | TextRole |
| label (key cap) | tooltip key cap | tooltip/TooltipTheme.jl:48 | UM | 12 | 400 | n | text | TextRole relative_size 0.9 |
| badge/status | tooltip marks: warning, error, success, info, accent, quiet (6) | tooltip/TooltipTheme.jl:54,56,58,60,62,64 | Lu | 13 | 400 | n | warning/error/success/info/accent_text, text_muted | TextRole family Lucide |
| code/mono | Undo base | undo/UndoTheme.jl:24 | DSM | 13 | 400 | n | n/a | `font` |
| tree/list row | undo index; step; ahead; empty | undo/UndoTheme.jl:26,28,30,32 | DSM | 13 | 400 | n | text_muted; text; text_faint; text_faint | TextRole |
| emphasis | undo marker; barrier | undo/UndoTheme.jl:34,36 | DSM | 13 | 700 | n | accent_text; warning_text | TextRole |
| code/mono | Statistics base | statistics/FrameStatisticsTheme.jl:26 | DSM | 13 | 400 | n | n/a | `font` |
| table header | statistics header line | statistics/FrameStatisticsTheme.jl:28 | DSM | 13 | 700 | n | heading | TextRole |
| tree/list row | statistics row; empty; slow | statistics/FrameStatisticsTheme.jl:30,32,34 | DSM | 13 | 400 | n | text; text_faint; warning_text | TextRole |
| code/mono | Faults base | fault/FaultTheme.jl:23 | DSM | 13 | 400 | n | n/a | `font` |
| secondary | fault count; site | fault/FaultTheme.jl:25,27 | DSM | 13 | 400 | n | text_muted | TextRole |
| error/fault | fault origin | fault/FaultTheme.jl:29 | DSM | 13 | 700 | n | error_text | TextRole |
| error/fault | fault message; empty | fault/FaultTheme.jl:31,33 | DSM | 13 | 400 | n | text; text_faint | TextRole |
| error/fault | inverse variant (text on error fill) | fault/FaultTheme.jl:49-51 | DSM | 13 | 400, origin 700 | n | text_on_accent | TextRole |
| code/mono | Log base | log/MessageLogTheme.jl:23 | DSM | 13 | 400 | n | n/a | `font` |
| badge/status | log level: info, error, warning, debug | log/MessageLogTheme.jl:25,27,29,31 | DSM | 13 | 700 | n | info/error/warning_text, text_muted | TextRole |
| body | log message; empty | log/MessageLogTheme.jl:33,35 | DSM | 13 | 400 | n | text; text_faint | TextRole |
| code/mono | Gestures panel base | gesturelog/GestureLogTheme.jl:23 | DSM | 13 | 400 | n | n/a | `font` |
| tree/list row | gesture index; operation; muted; empty | gesturelog/GestureLogTheme.jl:25,29,31,33 | DSM | 13 | 400 | n | text_muted; text; text_faint; text_faint | TextRole |
| emphasis | gesture | gesturelog/GestureLogTheme.jl:27 | DSM | 13 | 700 | n | accent_text | TextRole |
| code/mono | Gesture help base (every text overrides the family) | gesturehelp/GestureHelpTheme.jl:19 | DSM | 14 | 400 | n | n/a | `font` |
| section heading | gesture map header | gesturehelp/GestureHelpTheme.jl:21 | UM | 14 | 700 | n | heading | TextRole family override |
| label | gesture map gesture (key combination) | gesturehelp/GestureHelpTheme.jl:23 | UM | 14 | 700 | n | accent_text | TextRole |
| body | gesture map description; muted | gesturehelp/GestureHelpTheme.jl:25,27 | UM | 14 | 400 | n | text; text_faint | TextRole |
| body | Help base | help/HelpTheme.jl:27 | DS | 13 | 400 | n | n/a | `font` |
| section heading | help heading ("the line that says what a tree or a group holds") | help/HelpTheme.jl:29 | DS | 13 | 400 | n | text_muted | TextRole |
| title | help type name on its page | help/HelpTheme.jl:31 | DS | 15 (13*1.125=14.6) | 700 | n | heading | TextRole |
| secondary | help detail (module, names to type; version, home page) | help/HelpTheme.jl:33 | DS | 13 | 400 | n | text_muted | TextRole |
| body | help description (docstring) | help/HelpTheme.jl:35 | DS | 13 | 400 | n | text | TextRole |
| secondary | help "no docstring" line | help/HelpTheme.jl:37 | DS | 13 | 400 | i | text_faint | TextRole |
| title | about page program name | help/HelpTheme.jl:39 | DS | 20 (13*1.5=19.5, rounds to even) | 700 | n | heading | TextRole |
| code/mono | Inspector body | inspector/InspectorTheme.jl:26 | UM | 14 | 400 | n | n/a | `font` |
| section heading | Inspector header ("Compact", "Human-readable") | inspector/InspectorTheme.jl:28 | LS (Liberation Sans) | 21 (14*1.5) | 700 | n | heading (`:30`) | `FontRole(family="Liberation Sans", weight=700, relative_size=1.5)` |
| code/mono | Reference text base | text/ReferenceTheme.jl:27 | UM | 14 | 400 | n | by role | `font` |
| emphasis | reference aside ("which is") | text/ReferenceTheme.jl:29 | UM | 14 | 400 | i | punctuation | `FontRole(italic = true)` |
| body | McpLog base | mcplog/McpLogTheme.jl:14 | U | 14 | 400 | n | n/a | `font` |
| section heading | MCP log heading | mcplog/McpLogTheme.jl:16 | U | 14 | 700 | n | heading | TextRole |
| body | MCP call name; muted (time, method, duration, arguments) | mcplog/McpLogTheme.jl:18,24 | U | 14 | 400 | n | text; text_muted | TextRole |
| badge/status | MCP answered; fault | mcplog/McpLogTheme.jl:20,22 | U | 14 | 700 | n | success_text; error_text | TextRole |
| body | Conversation base | conversation/ConversationTheme.jl:32 | U | 14 | 400 | n | n/a | `font` |
| code/mono | Conversation code font (code and prompts) | conversation/ConversationTheme.jl:34 | UM | 14 | 400 | n | n/a | `code_font` |
| label | role label (user; assistant; other) | conversation/ConversationTheme.jl:36,38,40 | U | 13 (14*0.9=12.6) | 700 | n | accent_text; teal palette; text_muted | TextRole |
| badge/status | role glyph (3) | conversation/ConversationTheme.jl:42,44,46 | Lu | 14 | 400 | n | as role label | TextRole family Lucide |
| body | message | conversation/ConversationTheme.jl:48 | U | 14 | 400 | n | text | TextRole |
| secondary | kind label (tag of a block) | conversation/ConversationTheme.jl:50 | U | 11 (14*0.8=11.2) | 700 | n | text_muted | TextRole |
| secondary | section text (notes, field descriptions, status, section card header) | conversation/ConversationTheme.jl:52 | U | 11 | 400 | n | text_muted | TextRole |
| error/fault | error text | conversation/ConversationTheme.jl:54 | U | 11 | 700 | n | error_text | TextRole |
| code/mono | prompt; error prompt | conversation/ConversationTheme.jl:56,58 | UM | 14 | 400 | n | text_muted; error_text | `base = :code_font` |
| title | Outline document title | outline/OutlineTheme.jl:27 | U | 24 (14*24/14) | 700 | n | text | TextRole |
| section heading | outline section label (drawn uppercase at outline/OutlineRow.jl:177) | outline/OutlineTheme.jl:29 | U | 11 | 700 | n | text_muted | TextRole |
| tree/list row | outline row text | outline/OutlineTheme.jl:31 | U | 15 | 500 | n | text | TextRole |
| tree/list row | outline settled row (done step) | outline/OutlineTheme.jl:33 | U | 15 | 400 | n | text_muted | TextRole |
| label / value | outline field value; field word | outline/OutlineTheme.jl:35,37 | U | 13 | 400 | n | text; text_muted | TextRole |
| secondary | outline links / header facts | outline/OutlineTheme.jl:39 | U | 12 | 400 | n | text_muted | TextRole |
| secondary | outline row id | outline/OutlineTheme.jl:41 | UM | 12 | 700 | n | text_muted | TextRole |
| secondary | outline time and date | outline/OutlineTheme.jl:43 | UM | 11 | 400 | n | text_muted | TextRole |
| badge/status | outline chip text | outline/OutlineTheme.jl:45 | UM | 12 | 700 | n | text | TextRole |
| secondary | outline placeholder | outline/OutlineTheme.jl:47 | U | 15 | 400 | n | text_faint | TextRole |
| body | Outline base | outline/OutlineTheme.jl:25 | U | 14 | 400 | n | n/a | `font` |
| code/mono | Explorer file base; file | filesystem/FileSystemTheme.jl:24,26 | UM | 14 | 400 | n | text | `font`, TextRole |
| tree/list row | Explorer directory | filesystem/FileSystemTheme.jl:28 | UM | 14 | 700 | n | module_name | TextRole |
| (none) | Task pane | task/TaskTheme.jl:12-28 | n/a | n/a | n/a | n/a | colors only | no font field; labels use the widget body font (`task/TaskGroupToWidget.jl:46`, `WidgetLabel(text; text_style = color)`) |

---

### B. Per category: distinct (family, size, weight, italic) and counts

Counts are of the theme or style fields in section A that carry that value (the widget-part rows count once per use site row; "base" fonts of a theme count as one). Not weighted by how often a UI draws it.

- **window chrome** (menu item, menu, toolbar, tab, button, status bar, icon): U 13/400 x7 rows (button, menu item, menu font, toolbar, tab, tab selected, icon label), U 12/400 x1 (status bar), U 12/400 x1 (menu key hint, secondary).
- **title** (window/pane/card/dialog/alert/accordion title, outline, help): U 13/700 x6 (title pane 885, dialog 3024, card 8409, alert 9628, accordion 11204, tooltip title 40), U 24/700 x1 (outline title), DS 15/700 x1, DS 20/700 x1, U 13/700 alert destructive x1.
- **section heading**: U 13/700 x1 (Appearance heading, `appearance/AppearanceToWidget.jl:213`), U 11/700 x1 (outline section), U 14/700 x1 (MCP heading), UM 14/700 x1 (gesture map header), DSM 13/700 x1 (statistics header), DS 13/400 x1 (help heading), LS 21/700 x1 (inspector header).
- **label** (form label, field name, key): U 13/400 x about 8 (checkbox, switch, radio, toggle, toggle group, select, link, field word), U 13/700 x3 (conversation role labels), UM 14/700 x1 (gesture), UM 12/400 x1 (tooltip key cap), U 13/400 outline field value x1.
- **body/content**: U 13/400 (label, text, textarea, option, dialog body, card body, insertion, tooltip body, muted) about 11; U 14/400 x3 (conversation message, MCP call, MCP muted); DSM 13/400 x3 (log message, statistics row, fault message); DS 13/400 x1 (help description); UM 14/400 (gesture description, muted, text-theme plain, placeholder) x5.
- **code/mono**: UM 14/400 x about 35 fields (text, syntax, terminal, reference, filesystem, conversation code); UM 14/700 x6; UM 14/400 italic x2; DSM 13/400 x23; DSM 13/700 x10; DSM 14/400 x2; DSM 11/700 x2; UM 13/400 x1 (tooltip value).
- **secondary** (caption, hint, placeholder, metadata): U 12/400 x6 (caption style: menu keys, status bar, card description, card footer, alert description, accordion body, tooltip layer, outline links), U 11/700 x2 (kind, outline section counted above), U 11/400 x1 (conversation section), U 13/400 x1+ (tree detail, muted, disabled), U 15/400 x2 (outline quiet, placeholder), UM 12/700 x1 (outline id), UM 11/400 x1 (outline time), DSM 13/400 x several (count, site, empty), DS 13/400 italic x1, DS 13/400 x1 (help detail), U 12 appearance caption x2 (SettingsToWidget:61, AppearanceToWidget:362).
- **emphasis inside content**: bold: UM 14/700 (type name, delimiter), DSM 13/700 (undo marker/barrier, gesture log), italic: UM 14/400i x2 (syntax note, reference aside), DS 13/400i x1.
- **value/number**: U 13/400 (spin box), UM 13/400 x1 (tooltip value), UM 14/400 (number literals).
- **badge/status**: U 12/400 x9 (badge tones), U 13/700 x3 (role label), Lu 13 x6 and Lu 14 x3 (marks and glyphs), UM 12/700 x1 (chip), DSM 13/700 x4 (log level), U 14/700 x2 (MCP answered, fault), computed (avatar, count mark).
- **table header**: DSM 13/700 x1 (statistics header). The generic WidgetTable has no header style of its own.
- **tree/list row**: U 13/400 x2 (list, tree), U 15/500 x1 + U 15/400 x1 (outline), DSM 13/400 x about 10 (undo, statistics, gesture log), UM 14/400 and 700 (explorer).
- **tooltip**: U 13/400 (widget tooltip label, tooltip body, muted), U 13/700 (title), U 12/400 (layer), UM 13/400 (value), UM 12/400 (key).
- **error/fault**: DSM 13/700 x3 (graphics, fault origin, ...), DSM 11/700 x2, U 11/700 x1 (conversation error), U 13/700 x1 (alert destructive), DSM 13/400 x2.

---

### C. Distinct font combinations in the platform layer

Counted over the theme fields (including each theme's base `font`) and the widget derived styles of section A, with each Julia field counted once. 28 distinct (family, px, weight, italic) values.

| # | family | px | weight | italic | number of fields |
|---|---|---|---|---|---|
| 1 | Ubuntu | 13 | 400 | n | 6 + widget derived (label, body, tab ...) |
| 2 | Ubuntu | 13 | 700 | n | 5 + widget `_get_title_text` (6 titles) |
| 3 | Ubuntu | 12 | 400 | n | 3 + widget caption (7 uses) + badge (9 tones) |
| 4 | Ubuntu | 14 | 400 | n | 6 |
| 5 | Ubuntu | 14 | 700 | n | 3 |
| 6 | Ubuntu | 11 | 700 | n | 3 |
| 7 | Ubuntu | 11 | 400 | n | 1 |
| 8 | Ubuntu | 24 | 700 | n | 1 |
| 9 | Ubuntu | 15 | 500 | n | 1 |
| 10 | Ubuntu | 15 | 400 | n | 2 |
| 11 | Ubuntu Mono | 14 | 400 | n | 35 |
| 12 | Ubuntu Mono | 14 | 700 | n | 6 |
| 13 | Ubuntu Mono | 14 | 400 | i | 2 |
| 14 | Ubuntu Mono | 13 | 400 | n | 1 |
| 15 | Ubuntu Mono | 12 | 400 | n | 1 |
| 16 | Ubuntu Mono | 12 | 700 | n | 2 |
| 17 | Ubuntu Mono | 11 | 400 | n | 1 |
| 18 | DejaVu Sans Mono | 13 | 400 | n | 23 |
| 19 | DejaVu Sans Mono | 13 | 700 | n | 10 |
| 20 | DejaVu Sans Mono | 14 | 400 | n | 2 |
| 21 | DejaVu Sans Mono | 11 | 700 | n | 2 |
| 22 | DejaVu Sans | 13 | 400 | n | 4 |
| 23 | DejaVu Sans | 13 | 400 | i | 1 |
| 24 | DejaVu Sans | 15 | 700 | n | 1 |
| 25 | DejaVu Sans | 20 | 700 | n | 1 |
| 26 | Liberation Sans | 21 | 700 | n | 1 |
| 27 | Lucide | 13 | 400 | n | 6 (tooltip marks) |
| 28 | Lucide | 14 | 400 | n | 3 (conversation glyphs) |

Plus computed sizes: icon glyphs (box size, `widget/WidgetToGraphics.jl:9906`), avatar initials (0.42 of the avatar, `:9589`), count mark (0.6 of the icon, min 8, `widget/WidgetDecoration.jl:111`).

Totals: 8 distinct pixel sizes for text (11, 12, 13, 14, 15, 20, 21, 24; and 8 when Lucide at 13 and 14 is included, with the computed ones left out), 3 weights (400, 500, 700), 6 families (Ubuntu, Ubuntu Mono, DejaVu Sans Mono, DejaVu Sans, Liberation Sans, Lucide), 2 slants (n, i).

---

### D. A title or heading and the text under it have the same size

1. Widget title vs body, all of one size: `font_bold` is `FontRole(weight = 700)` with no `relative_size` (`widget/WidgetTheme.jl:99`), so a title is 13 px bold, exactly the 13 px of the body (`:97`). Users: title pane (`widget/WidgetToGraphics.jl:885`, body 886), dialog (`:3024`, `:3025`), card (`:8409`, `:8411`), alert (`:9628`), accordion (`:11204`). Only the weight differs. The sub-text of card, alert and accordion is 12 px (`font_small`), 1 px smaller.
2. Section heading in the Appearance tab: `StyleText(theme.font_bold, theme.muted_foreground)` (`appearance/AppearanceToWidget.jl:213`) is 13 px bold, against 13 px body fields; only the weight and color differ.
3. Tab, menu item, button, toolbar, tab bar: all `font` 13 px; selected tab differs from a tab only by color (`widget/WidgetToGraphics.jl:957-958`).
4. Tooltip note title: 13 px bold (`tooltip/TooltipTheme.jl:40`) over a 13 px body (`:42`) and a 13 px muted line (`:44`).
5. MCP log: heading 14 px bold (`mcplog/McpLogTheme.jl:16`) over 14 px call text (`:18`) and 14 px muted text (`:24`).
6. Statistics panel: header 13 px bold (`statistics/FrameStatisticsTheme.jl:28`), rows 13 px (`:30`).
7. Gesture map: header 14 px bold (`gesturehelp/GestureHelpTheme.jl:21`) over 14 px descriptions (`:25`).
8. Help: the heading line (`help/HelpTheme.jl:29`) is 13 px regular muted, the same size as the description (`:35`) and the detail (`:33`). Only color differs. Page names are bigger (15, 20).
9. Conversation: the role label is 13 px bold (`conversation/ConversationTheme.jl:36-40`) against a 14 px message (`:48`): the label is smaller than the text it heads; the kind, section and error labels are 11 px (`:50-54`).
10. Explorer: directory is 14 px bold (`filesystem/FileSystemTheme.jl:28`), file 14 px (`:26`).
11. Undo marker, gesture log gesture, log level, fault origin: bold 13 px next to 13 px rows.
12. Syntax: type name and delimiter 14 px bold next to 14 px values (`syntax/SyntaxTheme.jl:42,48`).
13. Inspector: the header is 21 px (`inspector/InspectorTheme.jl:28`) over a 14 px body: a real gap (ratio 1.5). The Outline has the widest scale: 24 / 15 / 13 / 12 / 11 (`outline/OutlineTheme.jl:27-47`), and Help 20 / 15 / 13.

Only Help (`:31,:39`), Inspector (`:28`) and Outline (`:27`) give a title or heading a bigger size than the text.

---

### E. Fonts that bypass the theme

Literal families or sizes outside a `@theme struct`:

| file:line | value | what it draws |
|---|---|---|
| text/TextDocument.jl:118 | `UNSTYLED_TEXT_FONT = StyleFont("Ubuntu Mono", 14)` marked `@style: content of the document` | every unstyled text string, text block, syntax leaf (also used at syntax/SyntaxDocument.jl:398,492, text/MarkedTextToText.jl:100, conversation/Evaluator.jl:284) |
| widget/WidgetToGraphics.jl:10023 | `StyleFont("Lucide", 20)`, marked `@style` | registers each icon glyph; the drawn size is the icon box |
| widget/WidgetDecoration.jl:92,111 | share 0.6, minimum 8 px | numeric count mark on an icon |
| widget/WidgetToGraphics.jl:9563,9589 | share 0.42, minimum 1 px | avatar initials |
| widget/WidgetToGraphics.jl:9906 | `with_font_size(font, size)` | icon glyph at the box size |
| syntax/SyntaxToText.jl:985,1081 | `with_font_size(style.font, size)` | folded-node ellipsis, size passed by caller |
| style/StyleText.jl:28, style/TextMeasure.jl:215, graphics/GraphicsDocument.jl:89,638 | `StyleFont("DejaVu Sans", 14)`, `StyleFont("Ubuntu Mono", 20)` | docstring and test or demo values (GraphicsDocument.jl:89 and :638 are docstring examples) |
| style/Appearance.jl:442,451,466 | `StyleFont(_DEFAULT_FONT_FAMILY, 1)` | placeholder while decoding a saved appearance (size 1 is replaced) |
| style/FontFace.jl:154,188 | default family DejaVu Sans; fallback families "DejaVu Sans Mono", "Noto Emoji" | glyph lookup |
| appearance/AppearanceToWidget.jl:118-149, 519 | `StyleFont(...)` / `with_font_size` for the font editor (families, weight steps, size spin box min 6, max 96) | the editing controls of fonts |

Inline `StyleText(t.font, color)` built in the widget printers (`widget/WidgetToGraphics.jl`: 519, 521, 576, 621, 662, 694, 769, 807, 886, 922, 957, 958, 8121, 8189-8219, 8411, 9392, 9558, 9632, 10078, 10080, 10171, 10174, 10378, 10601, 11085, 12806, 12821) take their font from the widget theme but choose the color inline; they cannot be changed by one role. `_get_*_text` helpers (`widget/WidgetTheme.jl:260-264`) are not part of the theme.

Printers with a text style that does not come from a font role: `natural/NaturalProjection.jl:155` (`StyleText(font, ...plain_text.color)`, a caller-given font), `syntax/ObjectToSyntax.jl:368` (font or the theme one), `text/PrimitiveToText.jl:164`, `text/MarkedTextToText.jl:203`, `widget/WidgetToGraphics.jl:1793-1794,2025,2200,2256-2257` (a label `text_style` that is a color alone, or a font alone).

---

### F. Surprising things

1. **Help and "ordinary" panels use mono fonts for prose or labels.** Terminal, Explorer file names, the gesture map descriptions (`gesturehelp/GestureHelpTheme.jl:25`), and the Inspector body are mono; of these only the gesture map descriptions and the outline time/id/chip are prose-like or metadata text. Tooltip `value_text` and `key_text` are mono (`tooltip/TooltipTheme.jl:46,48`), and Log, Faults, Statistics, Undo, Gestures panels are all DejaVu Sans Mono 13 (including prose messages and the table header of Statistics).
2. **Two body sizes (13 and 14), by panel.** The body base size is 13 in WidgetTheme, Tooltip, Help, Log, Faults, Statistics, Undo, Gesture log, Graphics, and 14 in Text, Syntax, Terminal, Inspector, Explorer, Conversation, MCP log, Outline, Gesture help, Reference. The same kind of text (a panel row) is 13 or 14 depending on the panel.
3. **Mixed sans families.** Ubuntu (widgets, conversation, outline, MCP log), DejaVu Sans (Help), Liberation Sans (Inspector header only, `inspector/InspectorTheme.jl:28`), DejaVu Sans Mono for logs and Ubuntu Mono for code. Liberation Sans is used by one field and by no theme as a base. The `GestureHelpTheme.font` base is DejaVu Sans Mono 14 while every text in that theme overrides the family to Ubuntu Mono (`gesturehelp/GestureHelpTheme.jl:19-27`), so the base family is never the one drawn.
4. **A size that shows only after rounding.** 14*0.9 = 12.6 draws as 13 (role labels, `conversation/ConversationTheme.jl:36-40`), so the role label (13) is smaller than the message (14) by 1 px only; 13*1.125 = 14.625 becomes 15; 13*1.5 = 19.5 becomes 20 (round half to even); 14*0.8 = 11.2 becomes 11; 13*0.9 = 11.7 becomes 12. A change of the base size moves these steps unevenly.
5. **Weight 500 used once.** `OutlineTheme.text` is `weight = 500` (`outline/OutlineTheme.jl:31`); Ubuntu Medium (500) exists on disk (`style/FontFace.jl:50`). No other style uses a weight other than 400 and 700.
6. **Light weight and condensed fonts ship but are never used.** Ubuntu Light 300 (`style/FontFace.jl:46-47`) and Ubuntu Condensed (`:54`), Liberation Mono and Liberation Serif (`:32-43`): no theme names them. Ubuntu Mono 700 italic and Liberation Sans italic exist but no theme asks for them either. Bold Ubuntu Mono is used; bold italic is not used anywhere.
7. **Italic is used by three fields only**, all muted notes: `syntax/SyntaxTheme.jl:46` (note), `help/HelpTheme.jl:37` (muted), `text/ReferenceTheme.jl:29` (aside). DejaVu Sans and Ubuntu and Ubuntu Mono italics exist on disk. The Appearance tab lets a person set italic and weight per role (`appearance/AppearanceToWidget.jl:484-489`).
8. **Text color alone is used to mark state in the chrome:** disabled and placeholder text use `muted_foreground` at the same size and weight; selected tab uses `foreground` against `muted_foreground`; both at 13 regular (`widget/WidgetToGraphics.jl:957-958`).
9. **Menu bar, table header, table cell, form label, list, tree and tab have no role of their own.** They draw with `font` (13 regular). A table header cannot be bolder than a cell except by the content's own `text_style`. A "hint" has no widget style except `font_small` caption (12) and `placeholder_text` (`:521`) which is the body size in muted color.
10. **Statistics panel: `FrameStatisticsToWidget.jl:475` measures columns with `header_text.font` and `row_text.font`.** The header is bold; the row is regular, same size.
11. **Uppercase.** The outline section label is 11 px bold and uppercased (`outline/OutlineRow.jl:177`), the only text with a case transform.
12. **Not found / unknown.** The `WidgetLabel` default font when no theme is passed is unknown to me (not read); the pixel size of an icon glyph is the icon box (theme `icon_size`, 1.0 of the line height), so I give no number; uses of `font`, `font_bold`, `font_small` in code outside `source/platform` were not searched.

## Part 2 — Font study: domains, adapters and font back end

Read-only inventory. Pixel sizes are the effective logical size at default (font scale 1.0, zoom 1.0): base size times `relative_size`, rounded to a whole pixel (`apply_font_role`, source/platform/style/FontRole.jl:62-66). Weight 400 is the default of a base font. "-" means the field is a base font, not a role. Counts and categories are mine; the category of a field is a judgement from its docstring.

### A. Every text style in domains and adapters

One row per `StyleFont`, `FontRole` or `TextRole` field of every `@theme struct` (19 themes, of which 16 hold font fields: 161 fields (20 base fonts, 141 roles)). Column `source` is the field name and its theme; the rows with a color role of `-` are base fonts or font roles with no color. `UI part` is the docstring of the field in short. Files are under `source/`.

| category | domain | UI part | file:line | family | size px | weight | italic | color role | source (theme.field [base, relative_size]) |
|---|---|---|---|---|---|---|---|---|---|
| base font (not drawn by itself) | Book | The font that the texts of this theme follow: its family, its weight and its size. | domain/book/BookTheme.jl:24 | Ubuntu | 14 | 400 | no | - | BookTheme.font |
| base font (not drawn by itself) | Book | The font that the code of this theme follows: its family, its weight and its size. | domain/book/BookTheme.jl:26 | Ubuntu Mono | 14 | 400 | no | - | BookTheme.code_font |
| title | Book | The title of a book. | domain/book/BookTheme.jl:28 | Ubuntu | 25 | 700 | no | heading | BookTheme.title_text [font, x1.8] |
| secondary | Book | The \"Written by \" that introduces the author. | domain/book/BookTheme.jl:30 | Ubuntu | 14 | 400 | yes | text_muted | BookTheme.author_prefix_text [font, x1] |
| body/content | Book | The author of a book. | domain/book/BookTheme.jl:32 | Ubuntu | 14 | 400 | yes | text | BookTheme.author_text [font, x1] |
| section heading | Book | The title of a chapter. | domain/book/BookTheme.jl:34 | Ubuntu | 17 | 700 | no | heading | BookTheme.chapter_title_text [font, x1.2] |
| section heading | Book | The numbering of a chapter. | domain/book/BookTheme.jl:36 | Ubuntu | 17 | 700 | no | text_muted | BookTheme.numbering_text [font, x1.2] |
| body/content | Book | A paragraph, and the blank line between the elements of a book or a chapter. | domain/book/BookTheme.jl:38 | Ubuntu Mono | 14 | 400 | no | text | BookTheme.paragraph_text [code_font, x1] |
| secondary | Book | The insertion leaf, and a picture with no path yet. | domain/book/BookTheme.jl:40 | Ubuntu Mono | 14 | 400 | no | text_faint | BookTheme.placeholder_text [code_font, x1] |
| punctuation/marker | Book | The bullet of a list item. | domain/book/BookTheme.jl:42 | Ubuntu Mono | 14 | 400 | no | markup | BookTheme.bullet_text [code_font, x1] |
| secondary | Book | The caption of a picture. | domain/book/BookTheme.jl:44 | Ubuntu Mono | 14 | 400 | no | text_muted | BookTheme.picture_text [code_font, x1] |
| title | Chart | The font of the chart's own title. | domain/chart/ChartTheme.jl:55 | Ubuntu | 14 | 700 | no | - | ChartTheme.title_font [axis_font, x16/14] |
| label | Chart | The font of an axis title, a tick label and a strip's segment name. | domain/chart/ChartTheme.jl:57 | Ubuntu | 12 | 400 | no | - | ChartTheme.axis_font |
| label | Chart | The font of a legend item's label. | domain/chart/ChartTheme.jl:59 | Ubuntu | 12 | 400 | no | - | ChartTheme.legend_font [axis_font, x1] |
| base font (not drawn by itself) | DbCatalog | The font that the texts of this theme follow: its family, its weight and its size. | domain/dbcatalog/DbCatalogTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | - | DbCatalogTheme.font |
| label | DbCatalog | A column, with its type. | domain/dbcatalog/DbCatalogTheme.jl:27 | Ubuntu Mono | 14 | 400 | no | field | DbCatalogTheme.column_text [font, x1] |
| label | DbCatalog | The name of a table. | domain/dbcatalog/DbCatalogTheme.jl:29 | Ubuntu Mono | 14 | 700 | no | type_name | DbCatalogTheme.table_text [font, x1] |
| label | DbCatalog | The name of a schema. | domain/dbcatalog/DbCatalogTheme.jl:31 | Ubuntu Mono | 14 | 700 | no | module_name | DbCatalogTheme.schema_text [font, x1] |
| label | DbCatalog | The name of a database and of an RDBMS. | domain/dbcatalog/DbCatalogTheme.jl:33 | Ubuntu Mono | 14 | 700 | no | module_name | DbCatalogTheme.database_text [font, x1] |
| secondary | DbCatalog | The keyword that opens a group of children, such as \"Columns\", \"Tables\", \"Schemas\" o | domain/dbcatalog/DbCatalogTheme.jl:35 | Ubuntu Mono | 14 | 400 | no | text_muted | DbCatalogTheme.keyword_text [font, x1] |
| secondary | Formula | The \"insert formula\" placeholder. | domain/formula/FormulaTheme.jl:26 | Ubuntu Mono | 14 | 400 | no | text_faint | FormulaTheme.insertion_text [plain_font, x1] |
| label | Formula | A reference to another formula, by its current name. | domain/formula/FormulaTheme.jl:28 | Ubuntu Mono | 14 | 700 | no | link | FormulaTheme.reference_text [plain_font, x1] |
| label | Formula | The name of a formula. | domain/formula/FormulaTheme.jl:30 | Ubuntu Mono | 14 | 700 | no | variable | FormulaTheme.name_text [plain_font, x1] |
| code/mono | Formula | The = and the ⇒ of a formula's line. | domain/formula/FormulaTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | operator | FormulaTheme.operator_text [plain_font, x1] |
| value/literal | Formula | The value of a formula. | domain/formula/FormulaTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | constant | FormulaTheme.result_text [plain_font, x1] |
| base font (not drawn by itself) | Formula | The font the lines of an environment separate on. | domain/formula/FormulaTheme.jl:36 | Ubuntu Mono | 14 | 400 | no | - | FormulaTheme.plain_font |
| base font (not drawn by itself) | Fsm | The font that the texts of this theme follow: its family, its weight and its size. | domain/fsm/FsmTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | - | FsmTheme.font |
| code/mono | Fsm | The keywords: component, variable, timer, event, machine, state, initial, on, when, stay,  | domain/fsm/FsmTheme.jl:27 | Ubuntu Mono | 14 | 700 | no | keyword | FsmTheme.keyword_text [font, x1] |
| label | Fsm | The name of a variable, at its declaration. | domain/fsm/FsmTheme.jl:29 | Ubuntu Mono | 14 | 700 | no | variable | FsmTheme.variable_name_text [font, x1] |
| label | Fsm | The name of an event and of a timer, at its declaration. | domain/fsm/FsmTheme.jl:31 | Ubuntu Mono | 14 | 700 | no | event | FsmTheme.event_name_text [font, x1] |
| label | Fsm | The name of a state, at its declaration. | domain/fsm/FsmTheme.jl:33 | Ubuntu Mono | 14 | 700 | no | enum_member | FsmTheme.state_name_text [font, x1] |
| label | Fsm | The name of a machine and of a component, at its declaration. | domain/fsm/FsmTheme.jl:35 | Ubuntu Mono | 14 | 700 | no | type_name | FsmTheme.machine_name_text [font, x1] |
| label | Fsm | A trigger, read from its event or its timer, also in the label of a transition in a diagra | domain/fsm/FsmTheme.jl:37 | Ubuntu Mono | 14 | 400 | no | event | FsmTheme.event_reference_text [font, x1] |
| label | Fsm | A target and an initial, read from the state. | domain/fsm/FsmTheme.jl:39 | Ubuntu Mono | 14 | 400 | no | enum_member | FsmTheme.state_reference_text [font, x1] |
| punctuation/marker | Fsm | The punctuation around a part, and the chrome of a transition label in a diagram. | domain/fsm/FsmTheme.jl:41 | Ubuntu Mono | 14 | 400 | no | punctuation | FsmTheme.chrome_text [font, x1] |
| label | Fsm | The name of a state in a diagram. | domain/fsm/FsmTheme.jl:43 | Ubuntu Mono | 14 | 700 | no | enum_member | FsmTheme.state_label_text [font, x1] |
| code/mono | Fsm | The keyword of a transition label in a diagram. | domain/fsm/FsmTheme.jl:45 | Ubuntu Mono | 14 | 400 | no | keyword | FsmTheme.trigger_text [font, x1] |
| base font (not drawn by itself) | Json | The font that the texts of this theme follow: its family, its weight and its size. | domain/json/JsonTheme.jl:23 | Ubuntu Mono | 14 | 400 | no | - | JsonTheme.font |
| value/literal | Json | A null value. | domain/json/JsonTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | null_literal | JsonTheme.null_text [font, x1] |
| value/literal | Json | A boolean value. | domain/json/JsonTheme.jl:27 | Ubuntu Mono | 14 | 400 | no | boolean_literal | JsonTheme.bool_text [font, x1] |
| value/literal | Json | A number value. | domain/json/JsonTheme.jl:29 | Ubuntu Mono | 14 | 400 | no | number_literal | JsonTheme.number_text [font, x1] |
| value/literal | Json | A string value. | domain/json/JsonTheme.jl:31 | Ubuntu Mono | 14 | 400 | no | string_literal | JsonTheme.string_text [font, x1] |
| punctuation/marker | Json | The quotes around a string. | domain/json/JsonTheme.jl:33 | Ubuntu Mono | 14 | 400 | no | punctuation | JsonTheme.quote_text [font, x1] |
| label | Json | The key of an object member, with its quotes. | domain/json/JsonTheme.jl:35 | Ubuntu Mono | 14 | 400 | no | field | JsonTheme.key_text [font, x1] |
| punctuation/marker | Json | The brackets of an array and the braces of an object. | domain/json/JsonTheme.jl:37 | Ubuntu Mono | 14 | 700 | no | punctuation | JsonTheme.delimiter_text [font, x1] |
| punctuation/marker | Json | A comma, and the colon of a member. | domain/json/JsonTheme.jl:39 | Ubuntu Mono | 14 | 400 | no | punctuation | JsonTheme.separator_text [font, x1] |
| base font (not drawn by itself) | Julia | The font that the texts of this theme follow: its family, its weight and its size. | domain/julia/JuliaTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | - | JuliaTheme.font |
| code/mono | Julia | A variable, a name whose kind the place does not give, and the label of an object that sta | domain/julia/JuliaTheme.jl:27 | Ubuntu Mono | 14 | 400 | no | variable | JuliaTheme.identifier_text [font, x1] |
| value/literal | Julia | A string, a chunk of an interpolated string, the quotes of a string interpolation, and a d | domain/julia/JuliaTheme.jl:29 | Ubuntu Mono | 14 | 400 | no | string_literal | JuliaTheme.string_text [font, x1] |
| value/literal | Julia | A character. | domain/julia/JuliaTheme.jl:31 | Ubuntu Mono | 14 | 400 | no | character_literal | JuliaTheme.char_text [font, x1] |
| value/literal | Julia | An integer and a float. | domain/julia/JuliaTheme.jl:33 | Ubuntu Mono | 14 | 400 | no | number_literal | JuliaTheme.number_text [font, x1] |
| value/literal | Julia | true and false. | domain/julia/JuliaTheme.jl:35 | Ubuntu Mono | 14 | 400 | no | boolean_literal | JuliaTheme.bool_text [font, x1] |
| value/literal | Julia | nothing. | domain/julia/JuliaTheme.jl:37 | Ubuntu Mono | 14 | 400 | no | null_literal | JuliaTheme.nothing_text [font, x1] |
| punctuation/marker | Julia | A quote, a delimiter, a separator, a brace and a fence. | domain/julia/JuliaTheme.jl:39 | Ubuntu Mono | 14 | 400 | no | punctuation | JuliaTheme.punctuation_text [font, x1] |
| secondary | Julia | A comment. | domain/julia/JuliaTheme.jl:41 | Ubuntu Mono | 14 | 400 | no | comment | JuliaTheme.comment_text [font, x1] |
| code/mono | Julia | A keyword. | domain/julia/JuliaTheme.jl:43 | Ubuntu Mono | 14 | 700 | no | keyword | JuliaTheme.keyword_text [font, x1] |
| value/literal | Julia | A symbol, such as :name. | domain/julia/JuliaTheme.jl:45 | Ubuntu Mono | 14 | 400 | no | symbol_literal | JuliaTheme.symbol_text [font, x1] |
| code/mono | Julia | An operator, the dot of a field access, a range, ::, =, ?:, <:, ->, and the dollar sign of | domain/julia/JuliaTheme.jl:47 | Ubuntu Mono | 14 | 400 | no | operator | JuliaTheme.operator_text [font, x1] |
| code/mono | Julia | The called function. | domain/julia/JuliaTheme.jl:49 | Ubuntu Mono | 14 | 400 | no | function_name | JuliaTheme.callee_text [font, x1] |
| code/mono | Julia | The name of a function, at its definition. | domain/julia/JuliaTheme.jl:51 | Ubuntu Mono | 14 | 700 | no | function_name | JuliaTheme.function_definition_text [font, x1] |
| code/mono | Julia | The name of a macro. | domain/julia/JuliaTheme.jl:53 | Ubuntu Mono | 14 | 400 | no | macro_name | JuliaTheme.macro_text [font, x1] |
| code/mono | Julia | A type after ::, after <:, and before {. | domain/julia/JuliaTheme.jl:55 | Ubuntu Mono | 14 | 400 | no | type_name | JuliaTheme.type_text [font, x1] |
| code/mono | Julia | The name of a struct and of an abstract type, at its definition. | domain/julia/JuliaTheme.jl:57 | Ubuntu Mono | 14 | 700 | no | type_name | JuliaTheme.type_definition_text [font, x1] |
| label | Julia | A field after a dot. | domain/julia/JuliaTheme.jl:59 | Ubuntu Mono | 14 | 400 | no | field | JuliaTheme.field_text [font, x1] |
| code/mono | Julia | The name of a module. | domain/julia/JuliaTheme.jl:61 | Ubuntu Mono | 14 | 700 | no | module_name | JuliaTheme.module_text [font, x1] |
| body/content | Julia | The path of a using, and the typed text of the insertion. | domain/julia/JuliaTheme.jl:63 | Ubuntu Mono | 14 | 400 | no | text | JuliaTheme.plain_text [font, x1] |
| secondary | Julia | The completion that the insertion offers. | domain/julia/JuliaTheme.jl:65 | Ubuntu Mono | 14 | 400 | no | text_faint | JuliaTheme.hint_text [font, x1] |
| base font (not drawn by itself) | Markdown | The font that the texts of this theme follow: its family, its weight and its size. | domain/markdown/MarkdownTheme.jl:28 | Ubuntu | 14 | 400 | no | - | MarkdownTheme.font |
| base font (not drawn by itself) | Markdown | The font that the code of this theme follows: its family, its weight and its size. | domain/markdown/MarkdownTheme.jl:30 | Ubuntu Mono | 14 | 400 | no | - | MarkdownTheme.code_font |
| punctuation/marker | Markdown | A marker: an insertion placeholder, a tick, a break, an emphasis mark, a quote mark, a bul | domain/markdown/MarkdownTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | markup | MarkdownTheme.marker_text [code_font, x1] |
| code/mono | Markdown | The text of the source form, and the root. | domain/markdown/MarkdownTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | text | MarkdownTheme.source_text [code_font, x1] |
| value/literal | Markdown | A code span and a code block, in the source form. | domain/markdown/MarkdownTheme.jl:36 | Ubuntu Mono | 14 | 400 | no | string_literal | MarkdownTheme.code_text [code_font, x1] |
| code/mono | Markdown | The language of a code block, and the value of an inline code span in the rendered form. | domain/markdown/MarkdownTheme.jl:38 | Ubuntu Mono | 14 | 400 | no | keyword | MarkdownTheme.language_text [code_font, x1] |
| punctuation/marker | Markdown | The # marker of a heading, in the source form. | domain/markdown/MarkdownTheme.jl:40 | Ubuntu Mono | 14 | 700 | no | markup | MarkdownTheme.heading_marker_text [code_font, x1] |
| code/mono | Markdown | The url of a link or an image. | domain/markdown/MarkdownTheme.jl:42 | Ubuntu Mono | 14 | 400 | no | link | MarkdownTheme.url_text [code_font, x1] |
| value/literal | Markdown | The alt text of an image. | domain/markdown/MarkdownTheme.jl:44 | Ubuntu Mono | 14 | 400 | no | string_literal | MarkdownTheme.alt_text [code_font, x1] |
| body/content | Markdown | The plain prose of the rendered form. | domain/markdown/MarkdownTheme.jl:46 | Ubuntu | 14 | 400 | no | text | MarkdownTheme.body_text [font, x1] |
| emphasis in content | Markdown | The font a bold run takes in the rendered form. | domain/markdown/MarkdownTheme.jl:48 | Ubuntu | 14 | 700 | no | - | MarkdownTheme.bold_font [font, x1] |
| emphasis in content | Markdown | The font an italic run takes in the rendered form. | domain/markdown/MarkdownTheme.jl:50 | Ubuntu | 14 | 400 | yes | - | MarkdownTheme.italic_font [font, x1] |
| title | Markdown | The font of a level 1 heading in the rendered form. | domain/markdown/MarkdownTheme.jl:52 | Ubuntu | 25 | 700 | no | - | MarkdownTheme.heading_1_font [font, x1.8] |
| section heading | Markdown | The font of a level 2 heading in the rendered form. | domain/markdown/MarkdownTheme.jl:54 | Ubuntu | 17 | 700 | no | - | MarkdownTheme.heading_2_font [font, x1.2] |
| section heading | Markdown | The font of a level 3 heading in the rendered form. | domain/markdown/MarkdownTheme.jl:56 | Ubuntu | 15 | 700 | no | - | MarkdownTheme.heading_3_font [font, x1.1] |
| section heading | Markdown | The font of a heading past the third level, in the rendered form. | domain/markdown/MarkdownTheme.jl:58 | Ubuntu | 13 | 700 | no | - | MarkdownTheme.heading_font [font, x0.9] |
| secondary | Markdown | The caption under a rendered image. | domain/markdown/MarkdownTheme.jl:64 | Ubuntu | 14 | 400 | yes | text_muted | MarkdownTheme.caption_text [font, x1] |
| punctuation/marker | Markdown | A marker of the rendered form: a thematic break rule, a quote bar, a code fence's language | domain/markdown/MarkdownTheme.jl:66 | DejaVu Sans Mono | 14 | 400 | no | markup | MarkdownTheme.rendered_marker_text [code_font, x1] |
| base font (not drawn by itself) | Math | The font that the code of this theme follows: its family, its weight and its size. | domain/math/MathTheme.jl:24 | Ubuntu Mono | 14 | 400 | no | - | MathTheme.code_font |
| code/mono | Math | A variable. | domain/math/MathTheme.jl:26 | Ubuntu Mono | 14 | 400 | no | variable | MathTheme.variable_text [code_font, x1] |
| code/mono | Math | An operator, and the / of a fraction. | domain/math/MathTheme.jl:28 | Ubuntu Mono | 14 | 400 | no | operator | MathTheme.operator_text [code_font, x1] |
| punctuation/marker | Math | A parenthesis, a brace, a bracket and the insertion leaf. | domain/math/MathTheme.jl:30 | Ubuntu Mono | 14 | 400 | no | punctuation | MathTheme.chrome_text [code_font, x1] |
| value/literal | Math | A symbol. | domain/math/MathTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | constant | MathTheme.symbol_text [code_font, x1] |
| code/mono | Math | The name of a function, a radical, a big operator, a differential, a derivative, an accent | domain/math/MathTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | function_name | MathTheme.name_text [code_font, x1] |
| body/content | Math | A run of plain text. | domain/math/MathTheme.jl:36 | Ubuntu Mono | 14 | 400 | no | text | MathTheme.word_text [code_font, x1] |
| code/mono | Math | The = of an assignment. | domain/math/MathTheme.jl:38 | Ubuntu Mono | 14 | 400 | no | operator | MathTheme.equals_text [code_font, x1] |
| base font (not drawn by itself) | Math | The upright face: a number, an operator, a function name, a symbol. | domain/math/MathTheme.jl:40 | DejaVu Sans | 14 | 400 | no | - | MathTheme.font |
| emphasis in content | Math | The oblique face: a variable. | domain/math/MathTheme.jl:42 | DejaVu Sans | 14 | 400 | yes | - | MathTheme.slanted_font [font, x1] |
| base font (not drawn by itself) | Process | The font that the texts of this theme follow: its family, its weight and its size. | domain/process/ProcessTheme.jl:26 | Ubuntu Mono | 14 | 400 | no | - | ProcessTheme.font |
| code/mono | Process | process, step, if, else, while, for, in, break, continue and return, and the keyword of a  | domain/process/ProcessTheme.jl:28 | Ubuntu Mono | 14 | 700 | no | keyword | ProcessTheme.keyword_text [font, x1] |
| label | Process | The name of a process. | domain/process/ProcessTheme.jl:30 | Ubuntu Mono | 14 | 700 | no | function_name | ProcessTheme.name_text [font, x1] |
| body/content | Process | The description of a step, and the text of a step label in a diagram. | domain/process/ProcessTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | text | ProcessTheme.action_text [font, x1] |
| punctuation/marker | Process | The punctuation around a part, an unrefined <condition>, <variable> or <iterable> marker,  | domain/process/ProcessTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | punctuation | ProcessTheme.chrome_text [font, x1] |
| error/fault | Process | The keyword of the node where a debug session stops. | domain/process/ProcessTheme.jl:36 | Ubuntu Mono | 14 | 700 | no | warning_text | ProcessTheme.current_text [font, x1] |
| error/fault | Process | The keyword of a node that holds a breakpoint. | domain/process/ProcessTheme.jl:38 | Ubuntu Mono | 14 | 700 | no | error_text | ProcessTheme.breakpoint_text [font, x1] |
| code/mono | Process | The label of the start or the stop terminal in a diagram. | domain/process/ProcessTheme.jl:40 | Ubuntu Mono | 14 | 700 | no | keyword | ProcessTheme.terminal_text [font, x1] |
| base font (not drawn by itself) | Research | The font that the texts of this theme follow: its family, its weight and its size. | domain/research/ResearchTheme.jl:18 | Ubuntu | 14 | 400 | no | - | ResearchTheme.font |
| section heading | Research | The id of an item, and the title of a section of the outline. | domain/research/ResearchTheme.jl:20 | Ubuntu | 14 | 700 | no | heading | ResearchTheme.heading_text [font, x1] |
| secondary | Research | The name of a link, the name of a field, and the time of an item. | domain/research/ResearchTheme.jl:22 | Ubuntu | 14 | 400 | no | text_muted | ResearchTheme.muted_text [font, x1] |
| label | Research | The author of an item that the assistant made. | domain/research/ResearchTheme.jl:24 | Ubuntu | 14 | 700 | no | info_text | ResearchTheme.assistant_text [font, x1] |
| body/content | Research | The author of an item that the person made. | domain/research/ResearchTheme.jl:26 | Ubuntu | 14 | 700 | no | text | ResearchTheme.person_text [font, x1] |
| base font (not drawn by itself) | Rst | The font that the texts of this theme follow: its family, its weight and its size. | domain/rst/RstTheme.jl:28 | Ubuntu | 14 | 400 | no | - | RstTheme.font |
| base font (not drawn by itself) | Rst | The font that the code of this theme follows: its family, its weight and its size. | domain/rst/RstTheme.jl:30 | Ubuntu Mono | 14 | 400 | no | - | RstTheme.code_font |
| punctuation/marker | Rst | A marker: an insertion placeholder, a tick, an emphasis or strong mark, a bullet, a transi | domain/rst/RstTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | markup | RstTheme.marker_text [code_font, x1] |
| code/mono | Rst | The text, the root, a value and an argument, in the source form. | domain/rst/RstTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | text | RstTheme.source_text [code_font, x1] |
| code/mono | Rst | A literal, a literal block, and a code block's code. | domain/rst/RstTheme.jl:36 | Ubuntu Mono | 14 | 400 | no | string_literal | RstTheme.literal_text [code_font, x1] |
| code/mono | Rst | A role name, a target, a path, and a role definition. | domain/rst/RstTheme.jl:38 | Ubuntu Mono | 14 | 400 | no | link | RstTheme.target_text [code_font, x1] |
| code/mono | Rst | A role's value and a math block. | domain/rst/RstTheme.jl:40 | Ubuntu Mono | 14 | 400 | no | string_literal | RstTheme.value_text [code_font, x1] |
| code/mono | Rst | A reference, a footnote label, a toctree entry, and a section's adornment. | domain/rst/RstTheme.jl:42 | Ubuntu Mono | 14 | 400 | no | link | RstTheme.reference_text [code_font, x1] |
| label | Rst | The name of a field of a field list. | domain/rst/RstTheme.jl:44 | Ubuntu Mono | 14 | 400 | no | field | RstTheme.field_text [code_font, x1] |
| label | Rst | The name of an option of a directive. | domain/rst/RstTheme.jl:46 | Ubuntu Mono | 14 | 400 | no | parameter | RstTheme.option_text [code_font, x1] |
| code/mono | Rst | A substitution reference and the name of a substitution definition. | domain/rst/RstTheme.jl:48 | Ubuntu Mono | 14 | 400 | no | constant | RstTheme.substitution_text [code_font, x1] |
| code/mono | Rst | The name of a directive and the language of a code block. | domain/rst/RstTheme.jl:50 | Ubuntu Mono | 14 | 400 | no | keyword | RstTheme.directive_text [code_font, x1] |
| code/mono | Rst | The .. kind:: marker of an admonition. | domain/rst/RstTheme.jl:52 | Ubuntu Mono | 14 | 700 | no | keyword | RstTheme.admonition_text [code_font, x1] |
| section heading | Rst | The title of a section, in the source form. | domain/rst/RstTheme.jl:54 | Ubuntu Mono | 14 | 700 | no | heading | RstTheme.title_text [code_font, x1] |
| body/content | Rst | The plain prose of the rendered form. | domain/rst/RstTheme.jl:56 | Ubuntu | 14 | 400 | no | text | RstTheme.body_text [font, x1] |
| emphasis in content | Rst | The font a bold run takes in the rendered form. | domain/rst/RstTheme.jl:58 | Ubuntu | 14 | 700 | no | - | RstTheme.bold_font [font, x1] |
| emphasis in content | Rst | The font an italic run takes in the rendered form. | domain/rst/RstTheme.jl:60 | Ubuntu | 14 | 400 | yes | - | RstTheme.italic_font [font, x1] |
| title | Rst | The font of a level 1 section title in the rendered form. | domain/rst/RstTheme.jl:62 | Ubuntu | 25 | 700 | no | - | RstTheme.title_1_font [font, x1.8] |
| section heading | Rst | The font of a level 2 section title in the rendered form. | domain/rst/RstTheme.jl:64 | Ubuntu | 17 | 700 | no | - | RstTheme.title_2_font [font, x1.2] |
| section heading | Rst | The font of a level 3 section title in the rendered form. | domain/rst/RstTheme.jl:66 | Ubuntu | 15 | 700 | no | - | RstTheme.title_3_font [font, x1.1] |
| section heading | Rst | The font of a section title past the third level, in the rendered form. | domain/rst/RstTheme.jl:68 | Ubuntu | 13 | 700 | no | - | RstTheme.title_font [font, x0.9] |
| secondary | Rst | The caption under a rendered figure. | domain/rst/RstTheme.jl:72 | Ubuntu | 14 | 400 | yes | text_muted | RstTheme.caption_text [font, x1] |
| punctuation/marker | Rst | A marker of the rendered form: a transition rule, and the arrow of a literal include. | domain/rst/RstTheme.jl:74 | DejaVu Sans Mono | 14 | 400 | no | markup | RstTheme.rendered_marker_text [code_font, x1] |
| title | SequenceChart | The font of the chart's title. | domain/sequencechart/SequenceChartTheme.jl:57 | Ubuntu | 14 | 700 | no | - | SequenceChartTheme.title_font [axis_font, x16/14] |
| label | SequenceChart | The font of a tick, a lane name, a readout and the empty-chart placeholder. | domain/sequencechart/SequenceChartTheme.jl:59 | Ubuntu | 12 | 400 | no | - | SequenceChartTheme.axis_font |
| label | SequenceChart | The font of the label of an event, an arrow or a band. | domain/sequencechart/SequenceChartTheme.jl:61 | Ubuntu | 12 | 400 | no | - | SequenceChartTheme.label_font [axis_font, x1] |
| base font (not drawn by itself) | Sql | The font that the texts of this theme follow: its family, its weight and its size. | domain/sql/SqlTheme.jl:24 | Ubuntu Mono | 14 | 400 | no | - | SqlTheme.font |
| code/mono | Sql | A reserved word, such as SELECT, FROM, WHERE or AND. | domain/sql/SqlTheme.jl:26 | Ubuntu Mono | 14 | 700 | no | keyword | SqlTheme.keyword_text [font, x1] |
| body/content | Sql | A raw expression, and any other text that is not a keyword, a name or a value. | domain/sql/SqlTheme.jl:28 | Ubuntu Mono | 14 | 400 | no | text | SqlTheme.plain_text [font, x1] |
| label | Sql | A column, and the qualifier before it. | domain/sql/SqlTheme.jl:30 | Ubuntu Mono | 14 | 400 | no | field | SqlTheme.column_text [font, x1] |
| label | Sql | An alias of a column or of a table. | domain/sql/SqlTheme.jl:32 | Ubuntu Mono | 14 | 400 | no | variable | SqlTheme.alias_text [font, x1] |
| code/mono | Sql | A data type. | domain/sql/SqlTheme.jl:34 | Ubuntu Mono | 14 | 400 | no | type_name | SqlTheme.type_text [font, x1] |
| value/literal | Sql | A boolean value: TRUE and FALSE. | domain/sql/SqlTheme.jl:36 | Ubuntu Mono | 14 | 400 | no | boolean_literal | SqlTheme.bool_text [font, x1] |
| value/literal | Sql | A number value. | domain/sql/SqlTheme.jl:38 | Ubuntu Mono | 14 | 400 | no | number_literal | SqlTheme.number_text [font, x1] |
| value/literal | Sql | A string value, with its quotes. | domain/sql/SqlTheme.jl:40 | Ubuntu Mono | 14 | 400 | no | string_literal | SqlTheme.string_text [font, x1] |
| label | Sql | A table, with its schema and its alias. | domain/sql/SqlTheme.jl:42 | Ubuntu Mono | 14 | 400 | no | type_name | SqlTheme.table_text [font, x1] |
| label | Sql | The name of a schema. | domain/sql/SqlTheme.jl:44 | Ubuntu Mono | 14 | 400 | no | module_name | SqlTheme.schema_text [font, x1] |
| punctuation/marker | Sql | The brackets, the commas, the spaces and the semicolons between the parts of a statement. | domain/sql/SqlTheme.jl:46 | Ubuntu Mono | 14 | 700 | no | punctuation | SqlTheme.punctuation_text [font, x1] |
| base font (not drawn by itself) | Xml | The font that the texts of this theme follow: its family, its weight and its size. | domain/xml/XmlTheme.jl:23 | Ubuntu Mono | 14 | 400 | no | - | XmlTheme.font |
| body/content | Xml | The text of a text node. | domain/xml/XmlTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | text | XmlTheme.content_text [font, x1] |
| label | Xml | The name of an element's opening and closing tag. | domain/xml/XmlTheme.jl:27 | Ubuntu Mono | 14 | 700 | no | tag | XmlTheme.tag_text [font, x1] |
| punctuation/marker | Xml | The angle brackets of a tag. | domain/xml/XmlTheme.jl:29 | Ubuntu Mono | 14 | 400 | no | punctuation | XmlTheme.delimiter_text [font, x1] |
| label | Xml | The name of an attribute. | domain/xml/XmlTheme.jl:31 | Ubuntu Mono | 14 | 400 | no | field | XmlTheme.attribute_name_text [font, x1] |
| punctuation/marker | Xml | The quotes around an attribute value. | domain/xml/XmlTheme.jl:33 | Ubuntu Mono | 14 | 400 | no | punctuation | XmlTheme.quote_text [font, x1] |
| value/literal | Xml | The value of an attribute. | domain/xml/XmlTheme.jl:35 | Ubuntu Mono | 14 | 400 | no | string_literal | XmlTheme.attribute_value_text [font, x1] |
| base font (not drawn by itself) | Yaml | The font that the texts of this theme follow: its family, its weight and its size. | domain/yaml/YamlTheme.jl:23 | Ubuntu Mono | 14 | 400 | no | - | YamlTheme.font |
| value/literal | Yaml | A null value. | domain/yaml/YamlTheme.jl:25 | Ubuntu Mono | 14 | 400 | no | null_literal | YamlTheme.null_text [font, x1] |
| value/literal | Yaml | A boolean value. | domain/yaml/YamlTheme.jl:27 | Ubuntu Mono | 14 | 400 | no | boolean_literal | YamlTheme.bool_text [font, x1] |
| value/literal | Yaml | A number value. | domain/yaml/YamlTheme.jl:29 | Ubuntu Mono | 14 | 400 | no | number_literal | YamlTheme.number_text [font, x1] |
| value/literal | Yaml | A string value. | domain/yaml/YamlTheme.jl:31 | Ubuntu Mono | 14 | 400 | no | string_literal | YamlTheme.string_text [font, x1] |
| label | Yaml | The key of a mapping entry. | domain/yaml/YamlTheme.jl:33 | Ubuntu Mono | 14 | 400 | no | field | YamlTheme.key_text [font, x1] |
| punctuation/marker | Yaml | The brackets of a flow sequence, the braces of a flow mapping, and the -  marker of a bloc | domain/yaml/YamlTheme.jl:35 | Ubuntu Mono | 14 | 700 | no | punctuation | YamlTheme.delimiter_text [font, x1] |
| punctuation/marker | Yaml | A comma, and the colon of a mapping entry. | domain/yaml/YamlTheme.jl:37 | Ubuntu Mono | 14 | 400 | no | punctuation | YamlTheme.separator_text [font, x1] |

### B. Per category: distinct (family, size, weight, italic) and the number of fields that use each

A place is one theme field. Base fonts are listed under their own category so they are not counted as drawn text. A text role in several themes counts once per theme.

#### base font (not drawn by itself) (18 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 13 | Book.code_font, DbCatalog.font, Formula.plain_font, Fsm.font, Json.font, Julia.font ... |
| Ubuntu | 14 | 400 | upright | 4 | Book.font, Markdown.font, Research.font, Rst.font |
| DejaVu Sans | 14 | 400 | upright | 1 | Math.font |

#### body/content (10 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 6 | Book.paragraph_text, Julia.plain_text, Math.word_text, Process.action_text, Sql.plain_text, Xml.content_text |
| Ubuntu | 14 | 400 | upright | 2 | Markdown.body_text, Rst.body_text |
| Ubuntu | 14 | 400 | italic | 1 | Book.author_text |
| Ubuntu | 14 | 700 | upright | 1 | Research.person_text |

#### code/mono (31 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 22 | Formula.operator_text, Fsm.trigger_text, Julia.identifier_text, Julia.operator_text, Julia.callee_text, Julia.macro_text ... |
| Ubuntu Mono | 14 | 700 | upright | 9 | Fsm.keyword_text, Julia.keyword_text, Julia.function_definition_text, Julia.type_definition_text, Julia.module_text, Process.keyword_text ... |

#### emphasis in content (5 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu | 14 | 400 | italic | 2 | Markdown.italic_font, Rst.italic_font |
| Ubuntu | 14 | 700 | upright | 2 | Markdown.bold_font, Rst.bold_font |
| DejaVu Sans | 14 | 400 | italic | 1 | Math.slanted_font |

#### error/fault (2 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 700 | upright | 2 | Process.current_text, Process.breakpoint_text |

#### label (30 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 13 | DbCatalog.column_text, Fsm.event_reference_text, Fsm.state_reference_text, Json.key_text, Julia.field_text, Rst.field_text ... |
| Ubuntu Mono | 14 | 700 | upright | 12 | DbCatalog.table_text, DbCatalog.schema_text, DbCatalog.database_text, Formula.reference_text, Formula.name_text, Fsm.variable_name_text ... |
| Ubuntu | 12 | 400 | upright | 4 | Chart.axis_font, Chart.legend_font, SequenceChart.axis_font, SequenceChart.label_font |
| Ubuntu | 14 | 700 | upright | 1 | Research.assistant_text |

#### punctuation/marker (18 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 12 | Book.bullet_text, Fsm.chrome_text, Json.quote_text, Json.separator_text, Julia.punctuation_text, Markdown.marker_text ... |
| Ubuntu Mono | 14 | 700 | upright | 4 | Json.delimiter_text, Markdown.heading_marker_text, Sql.punctuation_text, Yaml.delimiter_text |
| DejaVu Sans Mono | 14 | 400 | upright | 2 | Markdown.rendered_marker_text, Rst.rendered_marker_text |

#### secondary (10 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 6 | Book.placeholder_text, Book.picture_text, DbCatalog.keyword_text, Formula.insertion_text, Julia.comment_text, Julia.hint_text |
| Ubuntu | 14 | 400 | italic | 3 | Book.author_prefix_text, Markdown.caption_text, Rst.caption_text |
| Ubuntu | 14 | 400 | upright | 1 | Research.muted_text |

#### section heading (10 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu | 17 | 700 | upright | 4 | Book.chapter_title_text, Book.numbering_text, Markdown.heading_2_font, Rst.title_2_font |
| Ubuntu | 13 | 700 | upright | 2 | Markdown.heading_font, Rst.title_font |
| Ubuntu | 15 | 700 | upright | 2 | Markdown.heading_3_font, Rst.title_3_font |
| Ubuntu | 14 | 700 | upright | 1 | Research.heading_text |
| Ubuntu Mono | 14 | 700 | upright | 1 | Rst.title_text |

#### title (5 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu | 25 | 700 | upright | 3 | Book.title_text, Markdown.heading_1_font, Rst.title_1_font |
| Ubuntu | 14 | 700 | upright | 2 | Chart.title_font, SequenceChart.title_font |

#### value/literal (22 fields)

| family | size px | weight | style | places | fields (up to 6) |
|---|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 22 | Formula.result_text, Json.null_text, Json.bool_text, Json.number_text, Json.string_text, Julia.string_text ... |

#### All drawn text roles together (base fonts excluded)

| family | size px | weight | style | places |
|---|---|---|---|---|
| Ubuntu Mono | 14 | 400 | upright | 81 |
| Ubuntu Mono | 14 | 700 | upright | 28 |
| Ubuntu | 14 | 700 | upright | 7 |
| Ubuntu | 14 | 400 | italic | 6 |
| Ubuntu | 17 | 700 | upright | 4 |
| Ubuntu | 14 | 400 | upright | 3 |
| Ubuntu | 25 | 700 | upright | 3 |
| DejaVu Sans Mono | 14 | 400 | upright | 2 |
| Ubuntu | 12 | 400 | upright | 2 |
| Ubuntu | 13 | 700 | upright | 2 |
| Ubuntu | 15 | 700 | upright | 2 |
| DejaVu Sans | 14 | 400 | italic | 1 |

### C. Per domain: sizes in use

| theme | base font(s) | distinct sizes of drawn roles | verdict |
|---|---|---|---|
| BookTheme | Ubuntu 14; Ubuntu Mono 14 | 14, 17, 25 | several sizes |
| ChartTheme | Ubuntu 12 | 12, 14 | several sizes |
| DbCatalogTheme | Ubuntu Mono 14 | 14 | one size |
| FormulaTheme | Ubuntu Mono 14 | 14 | one size |
| FsmTheme | Ubuntu Mono 14 | 14 | one size |
| JsonTheme | Ubuntu Mono 14 | 14 | one size |
| JuliaTheme | Ubuntu Mono 14 | 14 | one size |
| MarkdownTheme | Ubuntu 14; Ubuntu Mono 14 | 13, 14, 15, 17, 25 | several sizes |
| MathTheme | DejaVu Sans 14; Ubuntu Mono 14 | 14 | one size |
| ProcessTheme | Ubuntu Mono 14 | 14 | one size |
| ResearchTheme | Ubuntu 14 | 14 | one size |
| RstTheme | Ubuntu 14; Ubuntu Mono 14 | 13, 14, 15, 17, 25 | several sizes |
| SequenceChartTheme | Ubuntu 12 | 12, 14 | several sizes |
| SqlTheme | Ubuntu Mono 14 | 14 | one size |
| XmlTheme | Ubuntu Mono 14 | 14 | one size |
| YamlTheme | Ubuntu Mono 14 | 14 | one size |
#### C, reading of the table

- Eleven themes print every role at one size, 14 px: Json, Yaml, Xml, Sql, Julia, Fsm, Process, DbCatalog, Formula, Research and Math (Math sets its own sizes in code, see below). In these themes the only differences between roles are color role and weight (400 or 700). No italic except Math's variable face.
- Five themes use other sizes: Markdown, Rst and Book (the rendered or titled forms: 25, 17, 15, 13 around a 14 base), and Chart and SequenceChart (12 base, title 14).
- Math: the theme has one size, 14 (`MathTheme` `code_font` Ubuntu Mono 14 and `font` DejaVu Sans 14). The typesetter `MathToGraphics.jl` makes smaller sizes in code: `_script_factor` is 0.7 for script and 0.5 for scriptscript (MathToGraphics.jl:202-203), and the size is `max(6, round(Int, c.font.size * factor))` (MathToGraphics.jl:223), so 14, 10, 7 at default. `_scaled` calls `with_font_size` (MathToGraphics.jl:213-214).
- The heading sizes of Markdown and Rst are 1.8, 1.2, 1.1 and 0.9 times 14, that is 25, 17 (16.8), 15 (15.4) and 13 (12.6). Level 4 to 6 headings are one pixel SMALLER than the 14 px body, and differ from it only by weight 700. Level 2 to 3 headings are 17 and 15 px: the gap between an h3 (15) and the body (14) is one pixel.
- Chart and SequenceChart: the title is `FontRole(base = :axis_font, weight = 700, relative_size = 16/14)` over an axis font of 12 px, which gives round(13.71) = 14 px bold; axis titles, tick labels, legend, event labels and the empty placeholder are 12 px regular. So the title is 2 px and one weight above its axis text. The chart colors every text (title, axis, ticks, legend) with the one role `text_color = :text_muted` (ChartTheme.jl:35-36, SequenceChartTheme.jl text_color), so title and tick labels differ only by 2 px and weight 700.
- Book: title 25 bold (heading role), chapter title 17 bold (heading), numbering 17 bold (muted), author 14 italic Ubuntu, paragraphs and placeholders and bullets and picture text 14 Ubuntu Mono (`base = :code_font`). So book body text is monospace.
- The data frame adapter, workflow, graph: no font field at all (see D).

### D. Fonts that bypass the theme

Literal families or sizes outside a `@theme struct` field in domains and adapters (searched: `StyleFont(`, `make_style_font`, `with_font_size`, `StyleText(`, `GraphicsText(`, `font =`, `font_size`):

1. `source/domain/book/BookModule.jl:33-34`: `StyleFont("Ubuntu Mono", 20)` with `color_default` inside `make_workload_file`, the file text of a precompile/window workload (`a.pred`). Not drawn as a theme text; it is the content of a sample file. Size 20 is the only literal size in these folders.
2. `source/domain/math/MathToGraphics.jl:203, 213-214, 223`: script sizes 0.7 and 0.5 times the theme font, minimum 6 px, via `with_font_size`. This is a size outside the theme (a TeX rule) and not scaled by the appearance except through the base font.
3. `source/domain/markdown/MarkdownTheme.jl:66` and `source/domain/rst/RstTheme.jl:74`: `rendered_marker_text = TextRole(:markup; base = :code_font, family = "DejaVu Sans Mono")`. A literal family inside a theme field, inside a role: the marker of the rendered form (thematic break rule, quote bar, code fence language, list marker, include arrow) draws in DejaVu Sans Mono 14 instead of Ubuntu Mono, so the glyphs (arrows, rules) come from a font that carries them.
4. `StyleText(...)` made in code, from theme fonts (not literal): `markdown/MarkdownToSyntax.jl:374-385` (bold, italic, link, heading), `rst/RstToSyntax.jl:930-932, 1033` and `rst/RstToLayout.jl:96` (bold, italic, title). They take the font of a theme field (`p.bold_font`, `_get_heading_font`, `_get_title_font`) and a color, so they follow the theme. `ambient.font` is used for the link text (MarkdownToSyntax.jl:378): link text has the size, weight and style of the text that surrounds it.
5. `domain/formula/FormulaToSyntax.jl:469` passes `get_style(:plain_font)`, a theme font.
6. Chart and sequence chart `GraphicsText(...)` calls (`chart/ChartPlotToGraphics.jl:551-801, 1298-1397, 1529`; `sequencechart/SequenceChartPlotToGraphics.jl:379-939`) all take their font from the theme values (`axis_font`, `title_font`, `legend_font`/`plan.font`, `label_font`). No literal size or family. A chart's own `ChartStyle` can override: `chart/ChartDocument.jl:52-54` has `title_font`, `axis_font`, `legend_font` of type `Any`, default `nothing` = take the theme.
7. No font in: `graph/GraphTheme.jl` (a node label is the content of the node, drawn by the child projection or widget; an edge label has only a `label_fill` rectangle and `label_padding`), `workflow/WorkflowTheme.jl` (gap only; "The outline of a workflow and its journal take the sizes and the type of the OutlineTheme", OutlineTheme.jl:25 = Ubuntu 14), `adapter/dataframes/DataFrameTheme.jl` (widths only; the header of a column draws with the widget theme, `WidgetTheme.font` Ubuntu 13, platform part; `DataFrameViewToWidget.jl:374` uses `theme.font` to compute row height from "M"). `dbcatalog` and `sql` etc. have a font and no literal.
8. Adapters `acp, adaptagrams, anthropic, languageserver, mcp, odbc, ollama, openrouter, tulip`: no `@theme struct`, no `StyleFont`, no `FontRole`, no `TextRole` (grep over `source/adapter`).
9. A style in the document data: the Text/Syntax documents of the platform carry `StyleFont` per `TextString` (platform part, not mine). The domain projections to syntax set fonts only through their themes, as listed in A.

### E. The font back end

#### E1. Files and the lookup

Files: `asset/font/` (`ls`). Registry: `source/platform/style/FontFace.jl`.

- `_FONT_FACES` (FontFace.jl:27-62) lists each face as (family, weight, italic, file). The lookup is by family name (case-insensitive, `_is_same_family` FontFace.jl:120-127), then the CSS matching rule.
- `find_font_face` calls `_find_font_face_index` (FontFace.jl:87-98): rank = (slant mismatch, weight group, weight distance); the smallest wins. The slant mismatch is first: a face of the asked slant always wins over a face of the other slant. So italic never fakes a slant: if the family has no italic face, upright is drawn (doc at FontFace.jl:69-71). No synthetic bold either.
- `_rank_font_weight` (FontFace.jl:104-116): wanted 400..500: exact, then nearest heavier up to 500, then nearest lighter, then heavier above 500; wanted < 400: nearest lighter, then nearest heavier; wanted > 500: nearest heavier, then nearest lighter.
- `compute_font_path(font)` (FontFace.jl:172-176): index by family, weight, italic; if the family has no face (index 0), it retries with `_DEFAULT_FONT_FAMILY = "DejaVu Sans"` (FontFace.jl:154) at the same weight and italic. All of the SDL, PDF, web, measure and caches key on this path. The SDL back end opens the file with `font_file(path)` (SdlBackend.jl:~972-984, `_get_font`).
- Glyph fallback per character: `find_glyph_font_file` (FontFace.jl:227-236): the font's own file, then DejaVu Sans Mono at the same weight, DejaVu Sans Mono regular, Noto Emoji at the same weight, Noto Emoji regular (`_FALLBACK_FONT_FAMILIES`, FontFace.jl:188; `get_fallback_font_files`). A code point above U+FFFF goes to Noto Emoji first.

#### E2. Faces really on disk, per family (all are in `_FONT_FACES`, and every named file exists in `asset/font/`)

| family | weights on disk | italic faces | files |
|---|---|---|---|
| Ubuntu | 300, 400, 500, 700 | yes for all four (300, 400, 500, 700) | Ubuntu-L, -LI, -R, -RI, -M, -MI, -B, -BI |
| Ubuntu Condensed | 400 only | no | Ubuntu-C |
| Ubuntu Mono | 400, 700 | yes for both | UbuntuMono-R, -RI, -B, -BI (so "Ubuntu Mono" has all four files) |
| DejaVu Sans | 400, 700 | 400 only (Oblique); no bold oblique | DejaVuSans, -Oblique, -Bold |
| DejaVu Sans Mono | 400, 700 | 400 only (Oblique); no bold oblique | DejaVuSansMono, -Oblique, -Bold |
| Liberation Sans, Serif, Mono | 400, 700 | yes for both | Regular, Italic, Bold, BoldItalic of each |
| Inconsolata | 500 only | no | Inconsolata.otf (CFF outlines) |
| Lucide | 400 | no | lucide.ttf (icons) |
| Noto Emoji | 400 | no | NotoEmoji-Regular.ttf |

Results of the rule for the weights that the code asks for, by reading the rank function (not by running it):
- Ubuntu 400 gives Ubuntu-R; 500 gives Ubuntu-M; 300 gives Ubuntu-L; 700 gives Ubuntu-B; italic gives the real Ubuntu-RI/-MI/-LI/-BI. 600 gives 700 (nearest heavier above 500); 800 and 900 give 700; 100 and 200 give 300; 350 gives 300.
- Ubuntu Mono: 500 gives 400 (candidate 400 is lighter, group 1, wins over 700 group 2); 300 gives 400; 600 and above give 700. Italic bold gives UbuntuMono-BI.
- DejaVu Sans and DejaVu Sans Mono with italic and weight 700: the slant wins, so the regular Oblique is drawn, NOT bold (no bold oblique file). That is `slanted_font` of Math (italic, weight 400): DejaVuSans-Oblique, fine.
- Weight 500 and 300 are reachable only for Ubuntu, and no domain theme asks for them: every weight in domains and adapters is 400 or 700 (table A). They could be set by a person in `appearance.toml` (Appearance.jl:383-385 writes family, size, weight, italic of a font).

#### E3. Families that the domains and adapters name, and the families with no file

Named in domains and adapters: Ubuntu (Markdown, Rst, Book, Research, Chart, SequenceChart), Ubuntu Mono (everything else), DejaVu Sans (Math `font`), DejaVu Sans Mono (the two `rendered_marker_text`). All four have a file. No family named in these folders lacks a file, so the fallback to DejaVu Sans never triggers for them. (The fallback exists: a name with no face draws in DejaVu Sans, FontFace.jl:154 and compute_font_path.) Files on disk that no domain uses: Ubuntu Condensed, Inconsolata, Liberation Serif, Liberation Mono, Ubuntu-L/-M (no weight 300 or 500 role). Liberation Sans is used by the platform inspector header (`platform/inspector/InspectorTheme.jl:28`).

The PDF writer embeds only TrueType outlines (`PdfWriter.jl:110-112`, `_is_embeddable_font` needs a `glyf` table), so Inconsolata.otf (CFF) is not embeddable in a PDF.

#### E4. Sizes: logical, device, scale, zoom, rounding

- `StyleFont.size` is an `Int` of logical pixels (Font.jl:31-37). There are no fractional sizes in a font.
- `font_logical_size(font) = max(1, round(Int, font.size))` (Font.jl:68). Used by the measure (TextMeasure.jl:102, 129, 160), the line box (TrueType.jl:394, 449), the PDF writer (PdfWriter.jl:448) and the web back end (`"sz"`, WebBackend.jl:243).
- `font_device_size(font, ratio) = max(1, round(Int, font.size * ratio))` (Font.jl:77). The SDL back end rasterizes at this size (SdlBackend.jl:974, 1074, 1123, 1155; `TTF_OpenFont(path, size)` at SdlBackend.jl:982 in `_get_font`). The `ratio` is the device pixel ratio times the zoom of the window (SdlBackend.jl:~4336 `off.sc * off.zoom` for the offscreen form; a window frame uses its drawn zoom). So the zoom multiplies the device size, and the layout stays in logical pixels.
- Font scale (Appearance `font_scale`, Appearance.jl:64) applies in `scale_theme_value(font::StyleFont, appearance)` (Appearance.jl:137-138): `scale_length(font.size, font_scale)`, which is `max(1, round(Int, size * factor))` for an Integer (Theme.jl:96-97). It is applied to the theme font when the scaled theme is built.
- A `FontRole` or `TextRole` is resolved in two steps with two roundings: `apply_font_role` gives `round(base.size * relative_size)` on the UNSCALED base (FontRole.jl:62-66), and then the font scale rounds again (Appearance.jl:165-166). Example at default: 14 x 0.9 = 12.6 rounds to 13 (not 12; the 13 x 0.9 = 11.7 to 12 case is the widget theme, platform part). With a scale of 1.1: body 14 becomes 15, level 4 heading 13 becomes 14.
- Everything is rounded to whole pixels at every step, so small ratios collapse: 14 x 1.1 = 15.4 gives 15 (h3), 14 x 1.2 = 16.8 gives 17 (h2): those two roles are only 2 px apart, and h3 is 1 px above the body.
- Light hinting is on: `TTF_SetFontHinting(f, LIGHT_SUBPIXEL)` (SdlBackend.jl:988-996), so glyphs fit the pixel rows; the advance is the one the layout measures.

#### E5. Letter spacing, small caps, tabular numbers, line height per font

- Letter spacing (tracking): not supported. No `letter_spacing`, `tracking` or similar field in `StyleFont` (Font.jl:31-37 has only family, size, weight, italic) nor in `FontRole` (FontRole.jl:25: base, family, weight, italic, relative_size). The grep for `letter.?spacing|tracking|small.?caps|tabular` over `source/backend` and `source/platform/style` gave no hit.
- Small caps: not supported (no field, no OpenType feature handling; `TrueType.jl` reads cmap, hmtx, kern, and `glyf`, no GSUB/GPOS).
- Tabular numbers: not supported as a feature. DejaVu Sans, Ubuntu and the mono faces have digits of equal width by design, but no feature switch exists.
- Kerning: yes, read from the `kern` table (`get_kerning`, TrueType.jl:252-257; used by TextMeasure.jl:146-147 and PdfWriter.jl:155-156). Ligatures: none; the web back end explicitly draws each character at its measured pen position so a browser's own kerning and ligatures never move a glyph (WebBackend.jl:~230-236).
- Line height per font: not a setting. The line box comes from the font's metrics: ascent and descent by FreeType's rule, rounded up (`font_ascent`, `font_descent`, `font_line_height` = ascent + descent, TrueType.jl:~400-420), plus the font's own `line_gap` (`compute_line_box`, TextMeasure.jl). A different line height needs a different font file or a layout gap (spacing); no `line_height` factor exists on a font or role. Tests use `FixedMeasure` with custom metrics (TextMeasure.jl:~205-215).
- Underline/strikethrough: not looked for, not in scope.

### F. Other things that stand out

1. Size contrast is small everywhere except the very top: text roles are 12, 13, 14, 15, 17 and 25 px, but 128 of the 141 drawn text roles are exactly 14 px (the rest: 17 x4, 25 x3, 12 x2, 15 x2, 13 x2). The only larger roles are h1/title (25) and h2 and chapter/numbering (17). Ranking: 25 / 17 / 15 / 14 / 13 / 12.
2. The "less important" text is not smaller: caption (`caption_text`, Markdown and Rst), author prefix, placeholders, hints, comments, the DbCatalog group keyword, the research `muted_text`, the formula insertion text all draw at the base size 14 and differ only in color role (`text_muted` or `text_faint`) and, for captions and "Written by", italic. Only the charts have a smaller text (12), and there everything, title included, takes the muted color.
3. Level 4 to 6 headings are smaller (13) than the body (14), and the weights are the only mark of a heading there.
4. Emphasis in content is weight 700 or italic at the SAME size, by design (`bold_font`, `italic_font`). In the code domains keywords, definitions and delimiters are bold 700 at the same size (julia `keyword_text`, `function_definition_text`, `type_definition_text`, `module_text`; json/yaml/sql `delimiter_text` or `punctuation_text` is bold, while `separator_text` and `quote_text` are regular), so emphasis, delimiter and name roles all share one size and are told apart by color and weight.
5. Weights in use are only 400 and 700. Ubuntu-L (300) and Ubuntu-M (500) exist but nothing asks for them; a "medium" step for labels or a "light" step for secondary text would need no new file.
6. Mixed families inside one view: Markdown, Rst and Book mix Ubuntu (body, headings) and Ubuntu Mono (markers, code, and for Book all paragraph text); Math mixes DejaVu Sans (upright, variable) and Ubuntu Mono (code_font roles).
7. A `TextRole` with `relative_size` is possible (Book title) but the three role kinds differ: Book sets size in a TextRole; Markdown and Rst set sizes in FontRoles that the syntax converters wrap in a `StyleText` with the heading color (`heading_color`).
8. Markdown `heading_marker_text` (the `#` signs, source form) is Ubuntu Mono 14 bold: in the source form the sizes do not change by level.
9. Domain fields sum: 19 themes (18 in `source/domain`, 1 in `source/adapter`: DataFrameTheme, with no font); 161 text or font fields: 20 base fonts and 141 roles; 16 of the 19 themes have such fields (Workflow, Graph and DataFrame have none). The 20 base fonts: Ubuntu Mono 14 x13, Ubuntu 14 x4 (Markdown, Rst, Book, Research), Ubuntu 12 x2 (Chart, SequenceChart), DejaVu Sans 14 x1 (Math).
10. Sealed files: not touched; nothing in the repository was changed, only this file and two scratch files (`gen.py`, `rows.json`, `partAB.md`) in the scratchpad.

## Part 3 — Font study: omnet-julia (read-only inventory)

Root of paths: /home/projectured/workspace/omnet-julia. "P:" = projectured-julia path. Method: grep/sed only, no Julia run. Sizes are the unscaled default; every `@theme` value is multiplied by the appearance font scale when read through `get_scaled_theme!` (scale itself not studied here: unknown).

Key fact: omnet-julia defines NO font hierarchy of its own. It has 4 `@theme` structs with fonts (Ned, Ini, TestFile, Result), one const (`QTENV_FONT`), one WidgetTheme variant (qtenv), and otherwise reuses projectured defaults (WidgetTheme.font Ubuntu 13, TextTheme.font Ubuntu Mono 14, ChartTheme.axis_font Ubuntu 12). `SimulationTheme` (source/legacy/simulator/presentation/SimulationTheme.jl:40) has NO font or text field (only spacings and sizes).

Effective-size notes for projectured defaults (read from P:):
- WidgetTheme: font = Ubuntu 13 (P:source/platform/widget/WidgetTheme.jl:97); font_bold = FontRole(weight=700) = Ubuntu 13 bold (:99); font_small = FontRole(relative_size=0.9) = round(11.7) = 12 px, Ubuntu regular (:101). Caption text = font_small + muted_foreground (:262); title text = font_bold + foreground (:261); body and label = font + foreground (:260, :263).
- TextTheme.font = Ubuntu Mono 14 (P:source/platform/text/TextTheme.jl:25).
- ChartTheme: axis_font = Ubuntu 12 (P:source/domain/chart/ChartTheme.jl:57); title_font = FontRole(base=:axis_font, weight=700, relative_size=16/14) = round(12*16/14) = 14 px bold (:55); `apply_font_role` rounds to a whole pixel (P:source/platform/style/FontRole.jl:62-66). SequenceChartTheme.axis_font = Ubuntu 12 (P:source/domain/sequencechart/SequenceChartTheme.jl:59).

### A. Table of every text style

Format: category | view | UI part | file:line | family | size px | weight | italic | color role | source

#### A1. `@theme struct` fields (the only themes with font/text fields in omnet-julia)

NedTheme (source/legacy/ned/NedTheme.jl:27), view: NED source (syntax). All italic = no (no field sets italic anywhere in omnet-julia).

| category | view | UI part | file:line | family | size | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|---|
| code/mono | NED | base font of all NED text | NedTheme.jl:29 `font` | Ubuntu Mono | 14 | 400 | no | n/a (font only) | theme field `font` |
| code/mono | NED | placeholder | NedTheme.jl:31 `placeholder_text` | Ubuntu Mono (base :font) | 14 | 400 | no | solarized_gray | theme |
| code/mono | NED | keyword | NedTheme.jl:33 `keyword_text` | Ubuntu Mono | 14 | 700 | no | solarized_magenta | theme |
| code/mono | NED | type name | NedTheme.jl:35 `type_text` | Ubuntu Mono | 14 | 400 | no | solarized_magenta | theme |
| code/mono | NED | plain text | NedTheme.jl:37 `plain_text` | Ubuntu Mono | 14 | 400 | no | :text | theme |
| code/mono | NED | property | NedTheme.jl:39 `property_text` | Ubuntu Mono | 14 | 400 | no | solarized_green | theme |
| code/mono | NED | string | NedTheme.jl:41 `string_text` | Ubuntu Mono | 14 | 400 | no | solarized_blue | theme |
| code/mono | NED | punctuation | NedTheme.jl:43 `punctuation_text` | Ubuntu Mono | 14 | 400 | no | :punctuation | theme |
| section heading | NED | section header (`types:`, `submodules:`, ...) | NedTheme.jl:45 `section_text` | Ubuntu Mono | 14 | 700 | no | solarized_violet | theme |

IniTheme (source/legacy/ini/IniTheme.jl:27), view: INI source.

| category | view | UI part | file:line | family | size | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|---|
| code/mono | INI | base font | IniTheme.jl:29 `font` | Ubuntu Mono | 14 | 400 | no | n/a | theme |
| secondary | INI | insertion placeholder | IniTheme.jl:31 `insertion_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| secondary | INI | comment | IniTheme.jl:33 `comment_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| code/mono | INI | keyword (`include`, ...) | IniTheme.jl:35 `keyword_text` | Ubuntu Mono | 14 | 700 | no | solarized_magenta | theme |
| code/mono | INI | path | IniTheme.jl:37 `path_text` | Ubuntu Mono | 14 | 400 | no | solarized_green | theme |
| label (key) | INI | config key | IniTheme.jl:39 `config_key_text` | Ubuntu Mono | 14 | 400 | no | solarized_blue | theme |
| label (parameter name) | INI | parameter name | IniTheme.jl:41 `parameter_name_text` | Ubuntu Mono | 14 | 400 | no | solarized_green | theme |
| code/mono | INI | `=` | IniTheme.jl:43 `assignment_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| value/number | INI | value | IniTheme.jl:45 `value_text` | Ubuntu Mono | 14 | 400 | no | solarized_cyan | theme |
| section heading | INI | `[Config X]` heading | IniTheme.jl:47 `section_heading_text` | Ubuntu Mono | 14 | 700 | no | solarized_yellow | theme |

TestFileTheme (source/legacy/testfile/TestFileTheme.jl:30), view: .test file source.

| category | view | UI part | file:line | family | size | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|---|
| code/mono | test file | base font | TestFileTheme.jl:32 `font` | Ubuntu Mono | 14 | 400 | no | n/a | theme |
| secondary | test file | insertion placeholder | :34 `insertion_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| code/mono | test file | keyword | :36 `keyword_text` | Ubuntu Mono | 14 | 700 | no | solarized_magenta | theme |
| error/fault | test file | negative keyword (`%not-contains`) | :38 `negative_keyword_text` | Ubuntu Mono | 14 | 700 | no | solarized_red | theme |
| secondary | test file | description | :40 `description_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| label | test file | file name | :42 `filename_text` | Ubuntu Mono | 14 | 400 | no | solarized_green | theme |
| label | test file | target | :44 `target_text` | Ubuntu Mono | 14 | 400 | no | solarized_cyan | theme |
| body/content | test file | expectation body | :46 `body_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| value/number | test file | argument | :48 `argument_text` | Ubuntu Mono | 14 | 400 | no | solarized_cyan | theme |
| secondary | test file | comment | :50 `comment_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| code/mono | test file | code | :52 `code_text` | Ubuntu Mono | 14 | 400 | no | :text | theme |

ResultTheme (source/legacy/result/presentation/ResultTheme.jl:38), view: legacy simulation results (cards, tables, syntax).

| category | view | UI part | file:line | family | size | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|---|
| title | results | base of card titles | ResultTheme.jl:40 `font` | Ubuntu (proportional) | 14 | 400 | no | n/a | theme |
| code/mono | results | base of rows, scalars, headings | ResultTheme.jl:42 `code_font` | Ubuntu Mono | 14 | 400 | no | n/a | theme |
| title | results | result card title | :44 `title_text` | Ubuntu (base :font) | 14 | 400 | no | :text | theme |
| section heading | results | config line | :46 `config_text` | Ubuntu Mono | 14 | 700 | no | solarized_yellow | theme |
| secondary | results | detail | :48 `detail_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| badge/status | results | status | :50 `status_text` | Ubuntu Mono | 14 | 400 | no | solarized_cyan | theme |
| label | results | scalar name | :52 `scalar_name_text` | Ubuntu Mono | 14 | 400 | no | solarized_cyan | theme |
| value/number | results | scalar value | :54 `scalar_value_text` | Ubuntu Mono | 14 | 400 | no | solarized_green | theme |
| secondary | results | scalar unit | :56 `scalar_unit_text` | Ubuntu Mono | 14 | 400 | no | solarized_gray | theme |
| section heading | results | module heading | :58 `module_heading_text` | Ubuntu Mono | 14 | 700 | no | solarized_blue | theme |
| section heading | results | run heading | :60 `run_heading_text` | Ubuntu Mono | 14 | 700 | no | solarized_magenta | theme |

SimulationTheme (source/legacy/simulator/presentation/SimulationTheme.jl:40): fields are `button_size`, `stack_gap`, `inline_gap`, `field_width`, `count_width`, `field_border`, `field_padding`, `label_gap`, `grid_vertical_gap`, `flag_gap`, `action_row_gap`. No font or text field. (Other @theme in omnet: task theme `get_task_style` at LegacySimulationRunnerToWidget.jl:49, :633 `:warning_color`; its definition was not opened: font fields unknown, only the color is read here.)

#### A2. Fonts that omnet-julia makes outside a theme struct

| category | view | UI part | file:line | family | size | weight | italic | color role | source |
|---|---|---|---|---|---|---|---|---|---|
| window chrome / body | workbench (Qtenv window) | body font of whole Qtenv-shaped window | source/presentation/workbench/WorkbenchRender.jl:107 `QTENV_FONT` | Ubuntu | 13 | 400 | no | n/a | inline literal const |
| title / emphasis | workbench (Qtenv) | `font_bold` of qtenv WidgetTheme: titles, headers | WorkbenchRender.jl:160 | Ubuntu | 13 | 700 | no | foreground | inline literal `StyleFont("Ubuntu", 13; weight = 700)` (projectured makes it by FontRole(weight=700)) |
| secondary | workbench (Qtenv) | `font_small` of qtenv WidgetTheme: captions, badges | WorkbenchRender.jl:160 | Ubuntu | 11 | 400 | no | muted_foreground (disabled_text 160/160/160 light, 127 dark; :152) | inline literal `StyleFont("Ubuntu", 11)` (projectured has relative_size = 0.9) |
| window chrome | workbench (Qtenv) | menu/tab/toolbar/status | WorkbenchRender.jl:125-160 | Ubuntu | 13 | 400 | no | foreground | QTENV_FONT via `font` |
| badge/status (icon) | execution status | status icon, an icon-font glyph | source/presentation/execution/ExecutionStatusView.jl:132 | Lucide (icon font) | WidgetTheme.font.size = 13 | 400 | no | takes color of text beside it (no explicit) | inline `StyleFont("Lucide", get_theme_defaults(WidgetTheme).font.size)`; marked `# @style` |
| secondary/value | execution status | status strip text ("running, t=..., events") | ExecutionStatusView.jl:134 `WidgetLabel("")` | Ubuntu (WidgetTheme.font) | 13 | 400 | no | foreground (default label) | default widget label (not set here) |
| secondary | workbench document | placeholder hints "(select a simulation type above)", "(no source location found ...)", source preview | source/presentation/projection/OmnetWorkbenchToWidget.jl:64 `_get_subtle_style`, used :187, :195, :212, :216 | Ubuntu Mono (TextTheme.font) | 14 | 400 | no | WidgetTheme.muted_foreground | inline `StyleText(TextTheme.font, WidgetTheme.muted_foreground)`; mixes a TextTheme font with a WidgetTheme color |
| graphic label | topology | module name under node | source/presentation/module/ModuleAppearanceToGraphics.jl:140-141 (`label_text`), drawn :299-300 | `font` param: default `TextTheme.font` (SimulationTopologyToWidget.jl:150) = Ubuntu Mono; Qtenv: QTENV_FONT = Ubuntu | 14 (default) / 13 (Qtenv) | 400 | no | WidgetTheme.foreground, or `appearance.label_color` (:300) | inline `StyleText(font, defaults.foreground)` |
| graphic label | topology | edge/graph node labels, other graph text | SimulationTopologyToWidget.jl:150-161 (`WidgetToGraphics(font)`) | same `font` | 14 / 13 | 400 | no | WidgetTheme | param default TextTheme.font |
| graphic label | Hanoi demo board | stick label, "moves: N" | source/presentation/module/HanoiToGraphics.jl:67 `label_font` default (use :101, :108, :120) | Ubuntu (WidgetTheme.font) | 13 | 400 | no | `label_color` (default of file, line not shown; WidgetTheme-based) | reuse of WidgetTheme.font |
| graphic label | timeline | event mark "|" glyph (TIMELINE_MARK, :60) | source/presentation/execution/TimelineView.jl:192, drawn :214 | Ubuntu Mono (TextTheme.font) | 14 | 400 | no | `color` param | param default `get_theme_defaults(TextTheme).font`; Qtenv path passes `font` (WorkbenchRender.jl:359) so 13 |
| title | vector plot | chart title | source/presentation/result/VectorPlot.jl:65, drawn :198 | Ubuntu | 14 (round of 12 x 16/14) | 700 | no | ChartTheme.text_color (:69) | reuse ChartTheme.title_font (unscaled default; scaled only if caller passes) |
| label | vector plot | x/y tick labels, axis title | VectorPlot.jl:64, drawn :208, :213, :218 | Ubuntu | 12 | 400 | no | ChartTheme.text_color | reuse ChartTheme.axis_font |
| title / value (chart) | workbench result chart | whole chart through scaled ChartTheme | WorkbenchRender.jl:258, NaturalRows.jl:59,62 | Ubuntu | 12 axis, 14 bold title | | no | ChartTheme | reuse |
| graphic label | sequence chart | axis / module names | source/legacy/result/presentation/ResultGraphics.jl:154; CaptureToWidget.jl:241 | Ubuntu | 12 (P:SequenceChartTheme.axis_font) | 400 | no | SequenceChartTheme | reuse, values not read here (only axis_font read) |
| body/content | log | log lines | source/presentation/capture/LogView.jl:204 | Ubuntu (WidgetTheme.font) | 13 | 400 | no | severity color via `get_severity_color` (text_style = a color, no size) | default WidgetLabel |
| error/fault | runner | "missing needs" warning label | source/legacy/simulator/presentation/LegacySimulationRunnerToWidget.jl:633 | Ubuntu (WidgetTheme.font) | 13 | 400 | no | task style `:warning_color` | default WidgetLabel + color |
| secondary | configuration form | "(declared default)", "per site: ..." values | source/presentation/parameter/ConfigurationFormToWidget.jl:123, 127, 128 | Ubuntu (default label) | 13 | 400 | no | WidgetTheme.muted_foreground | color only; same size as the name next to it |
| error/fault | configuration form | note | ConfigurationFormToWidget.jl:198-203 | Ubuntu | 13 | 400 | no | WidgetTheme.destructive | color only |
| secondary | navigator demo | catalog list rows | package/OmnetPresentationExample/src/OmnetPresentationExample.jl:345 | Ubuntu | 12 (0.9 x 13, rounded); 11 in Qtenv | 400 | no | WidgetTheme.muted_foreground | reuse of `theme.font_small` (the only reuse of font_small in omnet) |
| tree/list row | result files, INI entries | row text via WidgetLabel/WidgetTable | LegacyResultFileToWidget.jl (25 widget constructors), LegacyIniFileEntryToWidget.jl (16) | Ubuntu | 13 | 400 | no | default | default widget text; no style argument found in omnet for these (grep of `text_style` shows only LogView, Runner:633, ExecutionStatus:132, ConfigurationForm:198-203) |
| table header | tables | WidgetTable column headers | LegacyIniFileEntryToWidget.jl:188, 333; LegacySimulationRunnerToWidget.jl:507; LegacySimulationResultToWidget.jl:77; CaptureToWidget.jl:157 | Ubuntu | 13 | projectured table header style (P:, not read here: unknown) | no | default | omnet sets no font |
| title | cards | `WidgetCard(title = ...)` (inspector :207, log "Log" LogView.jl:~210, others) | many files (counts: see F) | Ubuntu | 13 | 700 (font_bold) | no | foreground | projectured title text = font_bold |
| badge/status | batch, execution dashboard, INI entry | `WidgetBadge` | SimulationBatchToWidget.jl:96; SimulationToWidget.jl:206, 387; SequentialEngineDashboard.jl:102; LegacyIniFileEntryToWidget.jl:84 | Ubuntu | 12 (font_small, projectured caption/badge) / 11 Qtenv | 400 | no | badge variant | projectured widget, no omnet font |
| window chrome | campaign window | NaturalToGraphics font | source/ide/CampaignWindow.jl:70, 96 | Ubuntu (WidgetTheme.font) | 13 | 400 | no | n/a | reuse WidgetTheme.font; text theme scaled at :36 of the block (TextTheme scaled) |
| title (window) | campaign window | window title "Campaign" | CampaignWindow.jl:293 | OS window decoration | unknown (not drawn by this repo) | | | | n/a |
| body/content | inspector | reflected tree | SimulationInspectorToWidget.jl:79 | Ubuntu Mono (TextTheme.font) | 14 | 400 | no | default | reuse |
| code/mono | workbench embed | scaled TextTheme | source/legacy/simulator/presentation/SimulationToWidget.jl:105 | Ubuntu Mono | 14 | 400 | no | | reuse `get_scaled_theme!(TextTheme)` |

Uses in omnet that bypass the themes: `TelemetryView.jl:18` comment says sparkline blocks need the "DejaVu chrome font" in SDL. It is a comment only; no font is named in code there (unknown whether a code path sets it). FaultTheme (P) has DejaVu Sans Mono 13, not used in omnet code found.

### B. Per category: distinct (family, size, weight, italic) and number of places

Counted from A (a "place" = one theme field or one code site). Italic is "no" everywhere in omnet.

| category | distinct values (count of places) |
|---|---|
| window chrome | Ubuntu 13/400 (Qtenv, campaign window) 2 |
| title | Ubuntu 14/400 (ResultTheme font, title_text) 2; Ubuntu 13/700 (card title via font_bold, Qtenv literal) 2; Ubuntu 14/700 (chart title) 1 |
| section heading | Ubuntu Mono 14/700: Ned section_text 1, Ini section_heading_text 1, Result config_text, module_heading_text, run_heading_text 3 = 5 places (all same size as code, only bold+color) |
| label | Ubuntu Mono 14/400: Ini config_key, parameter_name; TestFile filename, target; Result scalar_name = 5; Ubuntu 12/400 axis ticks and titles 1 (+ sequence chart) ; Ubuntu 13 default labels many |
| body/content | Ubuntu Mono 14/400: TestFile body_text, workbench inspector 2; Ubuntu 13/400: log, forms |
| code/mono | Ubuntu Mono 14/400: Ned 7 fields + font, Ini 4 + font, TestFile 2 + font, Result code_font; Ubuntu Mono 14/700 keywords: Ned 1, Ini 1, TestFile 1 |
| secondary | Ubuntu Mono 14/400 gray: Ini 2, TestFile 4, Result 2, subtle style 1 (same size as code); Ubuntu 12 or 11 (font_small): navigator 1, badges, captions; Ubuntu 13 with muted color: form values 3 |
| emphasis | only weight 700 on 14 mono (keywords) 3; Ubuntu 13/700 (font_bold) |
| value/number | Ubuntu Mono 14/400: Ini value, TestFile argument, Result scalar value = 3 |
| badge/status | Ubuntu 12/400 (WidgetBadge, projectured); Lucide 13 icon 1; Ubuntu Mono 14 result status 1 |
| table header | projectured header style, size unknown here; 5 table sites |
| tree/list row | Ubuntu 13 default (many); navigator Ubuntu 12 1 |
| graphic label | Ubuntu Mono 14 (topology default, timeline) 2; Ubuntu 13 (Qtenv topology, Hanoi) 2; Ubuntu 12 axis 1 |
| error/fault | Ubuntu Mono 14/700 red (TestFile negative keyword) 1; Ubuntu 13 colored (warning, note) 2 |

Distinct values in all of omnet-julia (unscaled): families 4 (Ubuntu, Ubuntu Mono, Lucide icon, DejaVu mention only in comment); sizes 4 effective (11, 12, 13, 14); weights 2 (400, 700); italic: none.

### C. Per view: any size other than the base?

| view | sizes present | answer |
|---|---|---|
| topology (SimulationTopologyToWidget.jl) | one: font param, 14 (default Mono) or 13 (Qtenv) | single size; module labels use one StyleText (ModuleAppearanceToGraphics.jl:140), no caption/title |
| timeline (TimelineView.jl) | one: 14 mono (13 in Qtenv), only mark glyph | single size |
| vector plot (VectorPlot.jl) | 12 ticks and 14 bold title (2 px) | two sizes, the only omnet view with a title scale |
| execution status (ExecutionStatusView.jl) | 13 icon and 13 text | single size |
| workbench / Qtenv (WorkbenchRender.jl) | 13 body, 13 bold, 11 small | has a smaller size (11) via font_small; title and body same 13 |
| campaign window (CampaignWindow.jl) | WidgetTheme.font 13 for all, text theme scaled | single size (no font set here; sizes inside nested widgets from projectured: unknown) |
| inspector (SimulationInspectorToWidget.jl) | TextTheme.font 14 for tree; card title 13 bold from projectured | two sizes by accident (13 widget, 14 mono) |
| NED | 14 Mono only | single size (bold keywords, section) |
| INI | 14 Mono only | single size |
| results (ResultTheme) | 14 Ubuntu title, 14 Mono rest | single size 14 (family and weight differ) |
| test file | 14 Mono only | single size |

### D. Fonts that bypass the theme, and copies of projectured values

1. WorkbenchRender.jl:107 `QTENV_FONT = StyleFont("Ubuntu", 13)` — copies the projectured `WidgetTheme.font` default (P:WidgetTheme.jl:97) as a literal.
2. WorkbenchRender.jl:160 `font_bold = StyleFont("Ubuntu", 13; weight = 700)` — copies in a literal what P: expresses as `FontRole(weight = 700)` (P:WidgetTheme.jl:99): the bold size is not derived from `font`, so a change to `font` leaves bold at 13.
3. WorkbenchRender.jl:160 `font_small = StyleFont("Ubuntu", 11)` — literal 11, where P: derives 0.9 x font (12 after rounding). Not equal to projectured (11 vs 12). Does not follow `font` argument either (the `font` parameter of `build_qtenv_widget_theme` changes `font` only).
4. ExecutionStatusView.jl:132 `StyleFont("Lucide", WidgetTheme.font.size)` — literal family; size follows WidgetTheme default at build time (unscaled default read by `get_theme_defaults`, not the scaled theme).
5. ResultTheme.jl:40, 42 and NedTheme.jl:29, IniTheme.jl:29, TestFileTheme.jl:32: `StyleFont("Ubuntu", 14)` and `StyleFont("Ubuntu Mono", 14)` repeated 5 times; each repeats `TextTheme.font` (Ubuntu Mono 14, P:TextTheme.jl:25) as a literal instead of reusing it. ResultTheme.font = Ubuntu 14 differs from WidgetTheme.font Ubuntu 13 (a 14 where the widgets have 13).
6. OmnetWorkbenchToWidget.jl:64 mixes TextTheme.font with WidgetTheme.muted_foreground in an inline StyleText.
7. `get_theme_defaults(...)` is used directly (unscaled) in HanoiToGraphics.jl:65-67, TimelineView.jl:192, VectorPlot.jl:64-70, SimulationTopologyToWidget.jl:150, SimulationInspectorToWidget.jl:79, CampaignWindow.jl:70, 96, WorkbenchRender.jl:304, 325, 411, ConfigurationFormToWidget.jl:123-128, 203. A default read bypasses the appearance scale unless the caller passes a scaled font (workbench passes `font`, others use default).
8. Reuse as designed: OmnetPresentationExample.jl:345 `theme.font_small` (reuses field); CampaignWindow.jl:70/96 `WidgetTheme.font`.

### E. Title or heading with the same size as the text under it (only weight and/or color differ)

- NED: section_text (14 bold violet) vs plain/keyword text (14): NedTheme.jl:45 vs :37.
- INI: section_heading_text (14 bold yellow) vs value/key (14): IniTheme.jl:47 vs :39-45.
- Results: module_heading_text, run_heading_text, config_text (14 mono bold + color) vs scalar rows (14 mono): ResultTheme.jl:46, 58, 60 vs :52-56. Result card title: title_text (Ubuntu 14 regular, weight 400!) vs rows (Ubuntu Mono 14): ResultTheme.jl:44 vs :48; the title is not even bold, only a different family.
- Test file: keyword (14 bold) vs body (14): TestFileTheme.jl:36 vs :46.
- Qtenv workbench: title font_bold 13/700 vs body 13/400 (WorkbenchRender.jl:160).
- Cards in default WidgetTheme: title = font_bold 13 vs body 13 (P: WidgetTheme.jl:99, :97).
- Execution status: icon 13 vs text 13 (ExecutionStatusView.jl:132, 134).
- Vector plot: title 14 bold vs ticks 12: a 2 px difference (VectorPlot.jl:198 vs :208).
- Secondary text vs primary: Ini/TestFile/Result comments, details, units (gray) have the same 14 as the code; only color differs. Muted subtle style (OmnetWorkbenchToWidget.jl:64) same 14 as other text. Configuration-form default values (ConfigurationFormToWidget.jl:123-128) muted but the same 13.
- Qtenv small 11 vs body 13 is the only secondary size step in omnet (a 1.18 ratio), plus projectured 0.9.

### F. Anything else surprising

- No `italic` anywhere; no `relative_size`, no `FontRole(` and no `with_font_size(` or `make_style_font(` in omnet-julia source (grep: zero matches in source/ and package/ non-test). All sizes come from literals or projectured themes.
- Only two weights in use, 400 and 700. No size step for headings in any code-like view: all text in NED/INI/test file/results is one size (14), emphasis only by bold and solarized color.
- The legacy themes use Solarized colors named per role (`color_solarized_*`) rather than semantic color roles (only :text and :punctuation are roles).
- Two defaults for "base size": 13 (widgets, Ubuntu) and 14 (text/syntax/results, Ubuntu Mono and Ubuntu in ResultTheme). A card title (13 bold) next to result text (14) puts the body larger than the title in the result views: ResultTheme title_text 14 regular vs module headings 14 bold mono.
- Qtenv: the repo comment says monospace at 14 in the rest of the package and Qt chrome at 13 (WorkbenchRender.jl:99-105). The log and message table "stay monospace" per that comment; the code that does it was not found (unknown: not located).
- The vector plot title is round(12 x 16/14) = 14: `apply_font_role` rounds every role to a whole pixel (P:source/platform/style/FontRole.jl:62-66).
- ExecutionStatusView.jl:132: icon size read from unscaled default, so it can drift from a scaled label.
- TelemetryView.jl:18 documents a DejaVu need for sparkline glyphs; TimelineView.jl:56 and ModuleViews.jl:80 and VectorPlot.jl:193 choose ASCII glyphs because of missing glyphs (tofu) in the font: the glyph set limits typographic choices.
- Counts of widget constructors (WidgetLabel/Card/Button/Tab/Badge/...) per file: highest SimulationWorkflowToWidget.jl 45, LegacyResultFileToWidget.jl 25, SimulationEmbedToWidget.jl 19, LegacySimulationRunnerToWidget.jl 19. Almost none passes a text style, so these inherit projectured defaults; their real sizes are decided in projectured-julia.
- Not examined: `source/build/*`, tests, `package/*Test`; test-only measures (OmnetLegacyResultTest.jl:598).
- Unknown: the font fields of the task theme (get_task_style) and the table header style (projectured); the appearance font scale; the places where the Qtenv font_small is actually drawn (captions and badges are projectured widgets).
