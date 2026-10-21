# A tooltip is a framed note

Status: IN PROGRESS, 2026-10-21, on the branch `tooltip-note`, in the worktree
`projectured-julia-tooltip-note`. Not landed on `main`.

## The ask

The user, 2026-10-21: "do a survey and collect all tooltips in projectured-julia
and omnet-julia, I want to make them rich in text notation with more style,
colors, different fonts, more content, some nice padding and border around them.
let's design a beutiful tooltip and make the tooltip contents much better. maybe
we should use markdown or text directly, I'm not sure which domain fits the
best"

## The problem

The facts at `main` `a1cbc1e5c` of projectured-julia. Find each function by its
name. The full list of the tooltips is in "The survey" at the end.

1. **The window draws no frame.** `TooltipContentToVerticalLayout` puts the
   layers in a `VerticalLayout` with a gap. It adds no padding, no border and no
   surface, so the text touches the edge of the window. `TooltipTheme` holds only
   the place and the size of the window. The graphics slice has no shadow, and
   the SDL backend opens no transparent or shaped window, so a frame must fill a
   rectangle.
2. **A tooltip is one plain string.** In projectured-julia, about 56 sites give a
   static string, 6 an interpolated string, and about 26 compute a string or a
   document. In omnet-julia, 4 sites give a tooltip, all through
   `DocumentDecoration(; tooltip)`. `_as_tooltip_document` makes a string a
   `PrimitiveString`. The Julia domain makes a `TextBlock` of plain lines, and the
   fault slice one `TextString`. No site sets a font or a color.
3. **A key is typed by hand.** 12 strings hold a key as text, for example
   "Go back to the page before (Ctrl+[)." and "Find a command that works here,
   and run it (Ctrl+Shift+P)". A change of a binding does not change the string.
   No helper reads `Action.shortcut` into a tooltip, but
   `describe_gesture_pattern` already gives the text of a key. The menu items
   with a shortcut (Ctrl+T, Ctrl+W, Ctrl+\, Ctrl+,) do not say it in a tooltip.
4. **The words repeat the label or say too little.** 14 toolbar tooltips start
   with the label: "Explorer: the files, the tasks, the assistants and the tools
   of this editor". Some say too little: "Open its page", "Open the file", "How
   this editor works". A `WidgetMenuItem` with no `tooltip` says nothing, because
   only `WidgetToolbarItem` falls back to its label.
5. **The structure is lost on the way.** `format_decoration_words` joins the
   conditions of a row into plain lines and drops the glyph and the color that
   the row shows. The tooltip of a task group is four lines of names and values:
   "3 of 3 finished", "3 TOTAL, 1 PASS", "Started …". A Julia docstring is
   Markdown, and the tooltip shows its source lines. A link shows its URL, and not
   the click that follows it.
6. **omnet-julia has tooltips only on a failure.** The 4 sites speak when a read
   failed or a build failed. The 9 transport buttons of the simulation (Step,
   Step in, Step out, Go on, Run, Fast, Express, Stop, Finish), the speed slider
   and the menu bar of the simulation have no tooltip. The NED tag `tt=` is a
   field of `ModuleAppearance` that nothing reads.

## Which domain

The decision: a note, drawn with the text domain. The user, 2026-10-21, to the
question "Do you agree with the note, or do you prefer Markdown or text spans?":
"yes I agree, let's implement this".

| | Markdown | The text domain directly | A note (recommended) |
| --- | --- | --- | --- |
| Where it lives | `ProjecturedMarkdown`, a domain package above the platform | the text slice of the platform | the tooltip slice, drawn by the natural slice |
| Reaches the platform widgets | no: a platform slice can not depend on a domain package, and about 90 % of the sites are platform widgets | yes | yes |
| A key cap, a name and value grid, a status color | no notation for any of them | yes, by hand at each site | yes, from the theme |
| Follows the theme and the dark mode | yes, through `MarkdownTheme` | no: a span holds a `StyleColor`, not a role | yes |
| What an author writes | markup in a string | spans with fonts and colors | the meaning: title, keys, text, facts, hint |

- **Markdown** fits long prose that is Markdown already, such as a Julia
  docstring, in a package that loads `ProjecturedMarkdown`. A note can hold such
  a page in its `text` field.
- **The text domain** is the material that the drawing uses: a `TextString`
  has a font, a font color, a fill color, a line color and padding, which is all
  that a key cap or a muted line needs. When each of 90 sites picks its own
  fonts and colors, the tooltips do not look the same, and they do not follow the
  theme.
- **A note** is a small document with fields. An author writes what a part is.
  One projection draws each note with spans of the text domain and colors of the
  theme, so every tooltip looks the same and follows the dark mode.

## The proposal

### The frame, around every tooltip

`TooltipContentToVerticalLayout` draws the column in a frame. The frame applies
to any content: a note, a string, a table, a widget.

- The surface is `popover`, the line is `border_strong`, 1 pixel wide, and the
  corners are square, because the window is a rectangle on every backend.
- The padding is 8 pixels above and below, and 12 pixels at the sides.
- When more than one layer shows, each outer layer starts with a hairline and
  the title of its part, in small capitals, in `text_faint`.
- When the parts around have more to say, the last line says
  "F2 · 2 more", in `text_faint`. Now a person must read the guide to find F2.
- `TooltipTheme` gets `padding` and `border_width`. The maximum size stays
  560 × 400.

### The note

```julia
TooltipNote(; title = nothing, keys = GesturePattern[], text = nothing,
              facts = Pair[], hint = nothing, tone = :plain)
```

- `title`: the name of the part, as the person sees it.
- `keys`: the keys that do the same, drawn as key caps after the title.
- `text`: what the part does, or what it shows. A string or any document.
- `facts`: name and value pairs, such as a path, a count, a time or a size with
  its unit. A `DocumentCondition` is a fact too, drawn with its glyph and color.
- `hint`: another gesture on the part, or why a command is off.
- `tone`: `:plain`, `:warning` or `:error`. A warning or an error puts its
  glyph, in its status color, before the title.

The drawing, with roles of `ColorTheme`:

```
┌───────────────────────────────────────────────┐
│ Command palette             [Ctrl][Shift][P]  │  title: Ubuntu 500, 14, text
│ Find a command that works here, and run it.   │  text: Ubuntu 400, 13, text
│ ───────────────────────────────────────────── │  hairline: border
│ Finished   3 of 3                             │  name: text_muted
│ Elapsed    12 s                               │  value: Ubuntu Mono, text
│ ───────────────────────────────────────────── │
│ ⓘ Ctrl+click opens it in a new tab.           │  hint: Ubuntu 12, text_muted
└───────────────────────────────────────────────┘
```

A key cap is a `TextString` in Ubuntu Mono 12 with the fill `surface_sunken`,
the line `border` and a padding of 1 × 5 pixels. The keys come from the pattern,
not from the text that `describe_gesture_pattern` gives, so the cap of "+" is
right.

### The words

Each tooltip follows these rules. They go to
[writing-rules.md](../../documentation/rule/writing-rules.md).

1. The title is the name of the part. It is not a sentence.
2. The keys come from the binding. A string never holds a key.
3. The text says what happens, or what the part shows. It does not repeat the
   title. It is one sentence of no more than 20 words.
4. The facts give what the part does not show: the full path, the count, the
   time, the unit.
5. The hint gives a second gesture, or the reason a command is off and what
   turns it on.
6. A button with only an icon has a tooltip. A label that says all of it has
   none.

### Before and after

| Part | Now | Proposed |
| --- | --- | --- |
| Back, in the navigator | "Go back to the page before (Ctrl+[)." | title Back, keys Ctrl [, text "Go to the page before." |
| Explorer, in the toolbar | "Explorer: the files, the tasks, the assistants and the tools of this editor" | title Explorer, text "The files, the tasks, the assistants and the tools of this editor." |
| New tab, in the menu | nothing | title New tab, keys Ctrl T, text "Open an empty tab." |
| A Markdown link | the URL | title Link, fact Target, hint "Click follows it. Ctrl+click opens it in a new tab." |
| A task group tab | four plain lines | title, a condition row, facts Finished, Passed, Started, Elapsed, Left |
| A fault mark | the whole message | tone error, title, the first line, facts Where and Count, hint "A right click offers Try again", only when the fault has a retry |
| Step in, in omnet-julia | nothing | title Step in, text "Stop at the next place where the model says that its state is whole." |

## Steps

The steps are fixed. Each step is one commit.

1. [x] **The frame.** `TooltipContentToVerticalLayout` draws the frame, the
   layer titles and the F2 line. `TooltipTheme` gets `padding` and
   `border_width`. Test: `test_tooltip_window()`.

   Done. As built:
   - The frame is a `WidgetComposite` with a border, padding and a
     `WidgetStyle` of the theme colors. The projection answers a
     `VerticalLayout` of one block, the frame, so its exported name and its
     output type stay, and `ProjecturedPlatform` takes no minor step.
   - `TooltipTheme` got `font`, `surface`, `line`, `line_width` (not
     `border_width`, after `WidgetTheme`), `padding`, `gap` and `layer_text`.
     The natural projection takes the scaled `TooltipTheme` of the appearance.
   - Between two layers stands no line. A `WidgetSeparator` draws a rule of
     its own length, 200 pixels by default, so in an SDL picture it stopped
     short of a wider layer. The title of each layer marks where it starts,
     with the gap of the column above it.
   - A layer title is the title in `text_faint`, 0.9 of the size. It is not
     in capitals: a text has no letter spacing, and a type name such as
     `JuliaDocstring` in capitals is hard to read.
   - The keys of the last line come from `WINDOW_LAYER_MORE_KEY` and
     `WINDOW_LAYER_FEWER_KEY`, two constants of the screen slice that
     `make_window_layer_bindings` binds: "F2 shows 1 more", "Shift+F2 shows
     one fewer", or both.
   - Test: `test_tooltip_window()` 51 of 51, `test_platform_layering()` 7 of 7.
2. [x] **The note.** `TooltipNote` in the tooltip slice, and its projection in
   the natural slice. An example in `example/platform/`. Test: a new
   `test_tooltip_note()`, and `test_example` of the example.

   Done. As built:
   - `TooltipNoteToVerticalLayout` draws a column: the head (the mark, the
     title and the key caps), the text, the facts, the hint, with a
     `WidgetSeparator` between the parts. (Step 5 replaced the separators with
     `section_gap`, for the reason in step 1.) A string text and a string hint are
     a `TextBlock`, so they break at the edge of the window. A fact value
     that is a document stands as it is.
   - The key caps stand after the title with `head_gap`, not at the right
     edge: the window fits what it prints, and a `Fill` would make each
     tooltip as wide as the largest window.
   - A key is a `GesturePattern` or a string such as `"Ctrl+click"`. Two keys
     have an "or" between them. A key text splits at each plus, and a plus at
     the end is the key of the plus.
   - The mark of a tone is the warning glyph of the icon font
     (`find_icon_character(:warning)`) in a label, in the theme texts
     `warning_mark` and `error_mark`. A `WidgetIcon` draws only inside a widget
     that holds it; alone, the natural projection reflects it as a struct.
   - `TooltipTheme` got `title_text`, `body_text`, `muted_text`, `value_text`,
     `key_text`, `key_fill`, `key_line`, `key_padding`, `key_gap`, `head_gap`,
     `fact_gap`, `fact_row_gap`, `warning_mark` and `error_mark`.
   - The line of the layer keys moved to the tooltip slice as
     `describe_layer_keys(shown, count)`: the table of the slice edges does not
     let the natural slice use the screen slice, and the tooltip slice may.
   - The example is the atom `make_tooltip_note_document_example`, so the
     catalog covers `TooltipNote`.
   - Test: `test_tooltip_note()` 22 of 22, `test_tooltip_window()` 51 of 51,
     `test_platform_layering()` 7 of 7, `test_platform_slice_edges()` passes.
3. [x] **A widget answers a note.** `_find_widget_tooltip` makes a note: the
   label is the title, `action.shortcut` gives the keys, the string is the text.
   A `WidgetMenuItem` does the same. Test: `test_widget_tooltip()`.

   Done. As built:
   - A string tooltip of any widget is the text of a `TooltipNote`; an empty
     string says nothing; any other document, a note too, says itself.
   - A control of an action (`WidgetToolbarItem`, `WidgetMenuItem`,
     `WidgetButton`) answers `_make_action_note`: the label is the title, the
     `shortcut` is the key cap, the tooltip is the text.
   - A menu item, and a button with a label, show their label, so with no
     tooltip they say nothing more (rule 6). A toolbar item, and a button with
     an empty label, show only a picture, so they say their label and their
     key with no tooltip. So the plan's "a menu item does the same" holds for
     a menu item with a tooltip; one with none stays quiet.
   - Three readers of the widget slice answer a note too: the edge of a table
     column ("Drag to set the width."), a table cell whose edit failed (its
     reason, tone `:error`), and a row of a tree (its decoration words).
   - Test: `test_widget_tooltip()` 29, `test_widget_toolbar()` 83,
     `test_widget_tab_label()` 24, `test_widget_table_list()` 253,
     `test_widget_table_list_header_floor()` 5, `test_widget_tree()` 103,
     `test_tooltip_window()` 51, `test_tooltip_note()` 22: all pass.
4. [x] **The words of the platform.** The window chrome (22), the navigator (9),
   the assistant and the conversation (14), the explorer, the terminal, the
   settings, the work plan and the workflow domain (8) follow the rules. The 12
   keys leave the strings. Test: the suite of each slice that asserts a text.

   Done. As built:
   - The texts of the window tools lose the "Label:" start, and each text is a
     sentence. The title of a tool button is its label.
   - A key comes from where it is bound: `HELP_GESTURE` and
     `COMMAND_PALETTE_GESTURE` for Gestures and Command palette, and
     `find_bound_keys(type, description)`, a function of the tooltip slice, for
     a key in a `@gestures` table: the navigator (Back, Forward, Parent, the
     path), the explorer (Add an entry) and the data frame view (Refresh).
     `find_bound_keys` keeps only key patterns, because the navigator binds
     the back button of the mouse to "Go back" too.
   - The kernel names the punctuation keys by their signs in
     `_get_key_label` (`GesturePattern.jl`, not sealed): `[`, `]`, `\`, `,`,
     `/`, `*`, `=`, `-`, not "Left_bracket". The gesture help and the command
     palette show the same signs.
   - "Ctrl+C" of the Stop button of the terminal is the signal that the button
     sends, not a key of the editor, so the text says it in words.
   - New tab, Close tab and the two splits keep no tooltip: the label says it
     (rule 6), and the menu shows the key beside the label.
   - A workflow button shows a glyph or a short word, so the name of its
     command is the title of its note.
   - The data frame refresh glyph has the label "Refresh" and a note with F5
     from the view; the sort glyph says the column as the title, and its hint
     says the gesture of its binding ("Shift+Left click adds it ...").
   - A crumb of the navigator address says its path as a fact.
   - A text that is also the description of a gesture binding (the find bar,
     the settings) keeps the form of a description.
   - The navigator and the explorer slices use the tooltip slice now: two
     edges in `PLATFORM_SLICE_EDGES`.
   - Test: `test_gesture_module()` 64, `test_platform_layering()`,
     `test_platform_slice_edges()`, `test_navigator_to_widget()` 68,
     `test_navigator_gestures()` 26, `test_explorer()` 240,
     `test_widget_tooltip()` 29, `test_tooltip_window()` 51,
     `test_tooltip_note()` 25, `test_workflow()` 199, `test_data_frame_sort()`
     17, `test_data_frame_refresh()` 16, `test_data_frame_filter()` 106,
     `test_data_frame_cells()` 173: all pass.
5. [x] **Structured answers.** A decoration answers a note with a condition row
   for each condition. A task group answers facts. A fault answers the tone
   `:error`. A Markdown link and an RST reference answer a fact and a hint. A
   Julia function answers its signature in Ubuntu Mono with the colors of the
   syntax roles. Test: `test_julia_tooltip()`, `test_tooltip_window()`, the
   decoration and task tests.

   Done. As built:
   - A fact of a note can be a `DocumentCondition`: the natural projection
     draws the glyph of its look (a dot for a look with none) in the color of
     its role, its words, and its count. `TooltipTheme` got `success_mark`,
     `info_mark`, `accent_mark` and `quiet_mark` beside the two of step 2.
   - `collect_decoration_conditions(decoration)` (domain slice) gives the
     conditions that have words, in their order; `format_decoration_words`
     uses it too.
   - `make_decoration_note(decoration)` (widget slice) answers the conditions as
     facts, then the tooltip of the decoration: a string as the text, or a
     note whose pieces follow the conditions. A tree row and a pane tab
     (`make_pane_tab_title`) say it.
   - A task group puts a note in its decoration: its title, what it does as
     the text, and the facts Identifier, Finished, Running, At a time, Result,
     Started, Elapsed and Left. The task slice uses the tooltip slice now.
   - A fault answers `make_fault_report_note`: the origin as the title, the
     tone `:error`, the message, "Caught in" as a fact, and the hint "A right
     click offers Try again." when a barrier made the report.
   - A Markdown link and an RST reference answer their target as a fact, with
     no hint: the click that follows a link differs between the source and the
     rendered view, so one hint would be wrong in one of them.
   - A Julia function answers its name and its signature as a fact, which the
     value text draws in Ubuntu Mono; a docstring adds its prose as the text.
     The colors of the syntax roles are not in the note: a fact is one text.
   - A `WidgetSeparator` draws 200 pixels by default, so in a wide note a line
     stopped short. The parts of a note stand apart by `section_gap` (10)
     instead, and the title and the text by `gap` (6).
   - Test: `test_tooltip_note()` 29, `test_document_decoration()` 54,
     `test_widget_tree()` 103, `test_fault_catching()` 53,
     `test_julia_tooltip()` 13, `test_tooltip_window()` 51,
     `test_markdown_link_target()` 11, `test_rst_link_target()` 9,
     `test_explorer()` 240, `test_task_group()` 76, `test_task_views()` 70,
     `test_pane_rename()` 38, `test_platform_layering()`,
     `test_platform_slice_edges()`: all pass.
6. [ ] **omnet-julia.** The transport buttons, the speed slider and the menu bar
   of the simulation answer a note. The decoration notes come from step 5. Test:
   the test of the simulation embed toolbar.
7. [ ] **The documentation.** [tooltip.md](../../documentation/package/platform/tooltip/tooltip.md),
   [tooltip-guide.md](../../documentation/guide/tooltip-guide.md) and the rules
   of the words.

## Not in this plan

- The NED tag `tt=`. No reader parses it, and `ModuleAppearanceToGraphics` draws
  no tooltip.
- A tooltip on a module, a gate or a connection of the simulation canvas.
- A shadow and round corners. Both need a transparent window.
- A markup inside a string, such as `` `code` `` or `**bold**`.

## The survey

### projectured-julia

| Slice | Sites | What they say |
| --- | --- | --- |
| `platform/shell` (`WindowChrome.jl`), `platform/mcplog` | 22 | menu commands and icon tools; 14 repeat the label; 2 hold a key |
| `platform/navigator` | 9 | Back, Forward, Parent, Edit the path (keys by hand), Open in a tab, the view switch, the crumbs (the path), the tab (the address) |
| `platform/assistant`, `platform/conversation` | 14 | Stop, Camera, Work, Sign out, the commands, the usage ("36k of the 1M tokens … 0.46 USD"), the sign-in methods, the choices |
| `platform/task` | 5 | the table (the press gestures), the progress ring (the position), the tab and row of a group (four lines), the reason of a task |
| `platform/widget` | 7 | the generic binding, the toolbar fallback, the reason of a failed cell, the column edge ("Drag to set the width"), the fault alert, the find bar placement |
| `platform/settingsmanaging` | 4 | Reset all, Save, Load, Reset of one setting |
| `platform/explorer`, `filesystem`, `pane`, `tree`, `domain` | 6 | Add an entry (Insert), Keep the rows of some kinds, the error of a folder, the decoration words of a row and a tab |
| `platform/terminal`, `workplan`, `fault` | 4 | Stop (Ctrl+C), the step of a plan, the file of a plan, the fault mark |
| `domain/workflow` | 8 | Fold, Unfold, Step the state, Add a step, Add a decision, Add an option, Add a comment, Add a card, Remove |
| `domain/julia` | 2 | the signature of a function, the signature and the docstring |
| `domain/markdown`, `domain/rst` | 2 | the target of a link, the target of a reference |
| `adapter/dataframes` | 4 | the parse error of a filter field, a cell of a type with no key, Refresh (F5, in the label), Sort (Shift adds it) |
| `example/` | 6 | demos of `WidgetTooltip`, `TooltipSource` and `TooltipContent` |

The keys typed by hand: Ctrl+[, Ctrl+], Ctrl+Up, Ctrl+L, Insert, F1,
Ctrl+Shift+P, Ctrl+C, F5, and the words "Ctrl+press", "Shift+press" and "Shift
adds it". `WidgetIcon` and `WidgetIconMark` have no `tooltip` field.

### omnet-julia

| File | Part | Text |
| --- | --- | --- |
| `source/legacy/result/presentation/LegacyResultFile.jl:542` | a result folder whose read failed | `sprint(showerror, failure)` |
| `source/legacy/simulator/presentation/LegacyIniFileEntry.jl:563` | an INI file that the discovery could not read | the error of the discovery |
| `source/legacy/simulator/presentation/LegacyIniFileEntry.jl:150` | a run row | the tooltip of the last task of the run |
| `source/legacy/simulator/presentation/LegacySimulationProjectPage.jl:211` | the project row | "The discovery could not read 2 INI files. The last build failed." |
| `source/simulator/module/ModuleAppearance.jl:83` | the `tt=` field | declared, never read |

No `make_tooltip_binding`, no `TooltipSource` and no `tooltip =` on a widget in
omnet-julia. The IDE window has the tooltip window of the platform, so the
platform tooltips show there.
