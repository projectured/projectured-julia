# Settings and Appearance show their groups in the explorer

**Status (2026-11-10): approved for implementation; the code and the tests are
done on the branch, and the check in a window of step 5 waits for the
permission of the owner.** The owner
decided D1, D2 and D3. The assistant proposed D4 to D12, and the owner approved
them with the plan on 2026-11-10.

**Goal:** the explorer shows the groups that the Settings tab and the Appearance
tab show, as nodes under two top-level nodes. A person opens each group alone in
its own tab.

**Repository:** projectured-julia. The plan changes no file under
`source/kernel/`, and [SEALING.md](../../SEALING.md) seals only kernel files.

**Branch:** `explorer-settings-groups`, in the worktree
`../projectured-julia-explorer-settings-groups`.

## 1. The request

> under the explorer settings and appearance item we should have deeper
> structure for the groups, no?

> It's A
>
> Also, the root settings seems unnecessary, make settings and appearance a top
> level node, no?

> Headings as intermediate nodes

## 2. What exists (main `b14502b56`)

### The explorer

The first content of the explorer has a section "Settings" with two nodes, the
`Settings` and the `Appearance` of the editor
([ApplicationExplorer.jl:38](../../source/platform/application/ApplicationExplorer.jl#L38),
[:55](../../source/platform/application/ApplicationExplorer.jl#L55)). Both are
leaves: no method of `get_tree_children_steps` exists for them, and the default
gives `()` ([TreeDefaults.jl:8](../../source/platform/tree/TreeDefaults.jl#L8)).

The tree gets a child by its number: it evaluates each path of
`get_tree_children_steps` to a collection, and reads `collection[i]` and
`length(collection)`
([DocumentTreeToWidgetTree.jl:176-200](../../source/platform/tree/DocumentTreeToWidgetTree.jl#L176-L200)).
Enter and a double click on a node answer `OpenPageOperation` with the
reference of the node
([DocumentTreeToWidgetTree.jl:299](../../source/platform/tree/DocumentTreeToWidgetTree.jl#L299)).

`ExplorerTest.jl:676` checks the names of the top level: `"Files", "Open
files", "Tasks", "Assistants", "Evaluators", "Dashboards", "Editor",
"Settings", "Help"`. A window that loads a saved explorer file shows the tree of
that file.

### The settings

`Settings.groups` is a `Dict{Type,Any}`, one group for each type
([Settings.jl:28](../../source/platform/settings/Settings.jl#L28)).
`get_settings_groups` sorts the values by name at each call. A group is a
`SettingsGroup <: Document`. Six groups exist: assistant index, fault, history,
pointer, render and start.

The Settings tab shows one card for each group, and under the cards the buttons
"Reset all", "Save" and "Load"
([SettingsToWidget.jl:85-150](../../source/platform/settingsmanaging/SettingsToWidget.jl#L85-L150)).
A card disables its controls and shows a note when the editor does not use its
group. The start step finds that and stores the types in
`Settings.unused_types`
([SettingsWrapper.jl:57](../../source/platform/settingsmanaging/SettingsWrapper.jl#L57)).

### The appearance

`Appearance` holds the zoom, six scales and five colour settings as plain
fields, the colour themes of the four variants, the font theme, and the other
themes in `themes::Dict{Type,Any}` with entries `(theme, scaled)`
([Appearance.jl:64-83](../../source/platform/style/Appearance.jl#L64-L83)).
`set_theme!` adds an entry when a projection first asks for a theme type. A
theme is a `Theme <: Document`. About 40 theme types exist.

The Appearance tab shows the buttons "Save" and "Load", the card "Scale", the
card "Colors", and three headings
([AppearanceToWidget.jl:215-230](../../source/platform/appearance/AppearanceToWidget.jl#L215-L230)):

- "Editor": the colour theme of the present mode and contrast, the font theme,
  and six themes that every view draws with;
- "Tools": the other themes of `ProjecturedPlatform`;
- "Documents": the themes of the other packages.

The view makes the headings at each print in `_get_theme_groups`
([AppearanceToWidget.jl:304](../../source/platform/appearance/AppearanceToWidget.jl#L304)).
No document holds them. A theme card folds. `Appearance.open_sections` holds the
names of the open cards.

The appearance wrapper makes each write of a field of a theme of the appearance
a `ReplaceThemeValueOperation`. It finds the theme by its identity, so a write
from any view of the theme is an edit that Ctrl+Z takes back
([AppearanceManagingProjection.jl:109-119](../../source/platform/appearance/AppearanceManagingProjection.jl#L109-L119)).

## 3. The target

```
Explorer
├─ …
├─ Editor
├─ Settings              opens the Settings tab, as now
│  ├─ Assistant index    opens the group alone
│  ├─ Fault
│  ├─ History
│  ├─ Pointer
│  ├─ Render
│  └─ Start
├─ Appearance            opens the Appearance tab, as now
│  ├─ Scale              opens the part alone
│  ├─ Colors
│  ├─ Editor             opens the theme cards of the heading
│  │  ├─ Color (the colour theme of the present mode)
│  │  ├─ Font
│  │  └─ Widget, Text, Syntax, Reference, Graphics, Tooltip
│  ├─ Tools
│  │  └─ one node for each theme
│  └─ Documents
│     └─ one node for each theme
└─ Help
```

## 4. Decisions

**D1 (owner, 2026-11-10).** A node of a group opens the group alone in its own
tab. Rejected: open the parent tab and scroll to the card.

Fact for D1 (2026-11-10): a press, Enter or a double click on a node of the
explorer shows its document as the page of the explorer, whose navigator puts the
page in a pane that scrolls. Ctrl+press opens it in a new tab. A group, a part
and a theme open the same way, so their views need no pane of their own.

**D2 (owner, 2026-11-10).** `Settings` and `Appearance` are top-level nodes of
the explorer. The section "Settings" goes away.

**D3 (owner, 2026-11-10).** The headings "Editor", "Tools" and "Documents" are
intermediate nodes under "Appearance". A heading opens a tab with the theme
cards under it. Rejected: each theme directly under "Appearance".

**D4 (proposed by the assistant, approved with the plan 2026-11-10).** The tree stops at a group. A setting and a
field of a theme are no nodes. Rejected: a node for each setting, because the
page of a group shows them, and about 40 themes with their fields make a long
tree.

**D5 (proposed by the assistant, approved with the plan 2026-11-10).** `Settings.groups` is a `CellVector` in the
order of the names of the groups, in place of the `Dict`. A lookup by type
scans the list. Rejected: a new reference step that reads a `Dict` in the order
of its names, because the paths that exist reach a list.

**D6 (proposed by the assistant, approved with the plan 2026-11-10).** Each group holds whether the editor uses
it. `@settings` adds the field `is_used::Bool = true`, which has no setting
description, so no file holds it. `start_settings!` writes it.
`Settings.unused_types` goes away. Rejected: the view of one group reads the
`Settings`, because a view reads only its document.

**D7 (proposed by the assistant, approved with the plan 2026-11-10).** The zoom and the six scales move into a
document `AppearanceScale` at `Appearance.scale`. The five colour settings move
into a document `AppearanceColors` at `Appearance.colors`. Each reader reads a
field through its part, for example `appearance.scale.font_scale`. Rejected: a
node that names a set of fields of `Appearance`, because a tree node, a page
and a reference reach a document.

**D8 (proposed by the assistant, approved with the plan 2026-11-10).** The three headings are three `ThemeGroup`
documents in `Appearance`: `editor_themes`, `tool_themes` and
`document_themes`. A `ThemeGroup` holds its `title` and `themes`, a
`CellVector` in the order of the tab. `set_theme!` puts a new theme into its
heading by the rule of `_get_theme_groups`, which moves from the view to
`Appearance.jl`. `Appearance.themes` stays the index of the scaled theme by
type. Rejected: the view makes the headings at each print, because the tree and
a page need them as documents.

**D9 (proposed by the assistant, approved with the plan 2026-11-10).** The heading "Editor" has one colour node:
the colour theme of the present mode and contrast, as the tab shows it. The
node changes when the mode, the contrast or the system colours change. Step 4
finds how the list follows them and records it here. Rejected: one node for
each of the four colour variants, because the tab shows one.

**D10 (proposed by the assistant, approved with the plan 2026-11-10).** Each `ThemeGroup` holds the names of its
open cards, in place of `Appearance.open_sections`. The Appearance tab and the
page of a heading fold the same cards. Rejected: the page of a heading keeps
its own fold state, because a person then sees two states of one card.

**D11 (proposed by the assistant, approved with the plan 2026-11-10).** One view for each kind of node:
`SettingsGroupToWidget`, `AppearanceScaleToWidget`, `AppearanceColorsToWidget`,
`ThemeGroupToWidget` and `ThemeToWidget`. A view gives the content of a card:
the summary, the note and the rows. In a tab, the parent view prints each child
through the recursion and puts it in a card with its title and, for a theme,
the fold. The page of one group, part or theme shows the content under the tab
title. Rejected: the tab views also print a part alone, because one view then
prints two kinds of document.

**D11, changed in step 5 (2026-11-10, by the assistant).** The views of the parts
draw the pages. A tab does not put a part into a card for its view to draw: it
builds the same bodies with the same functions (`_make_group_grid` of the
settings; `_make_scale_body`, `_make_colors_body`, `_make_group_body` and
`_make_theme_body` of the appearance), and reads its controls with the same
functions. Reason: Tab moves through the stops of one widget tree. Its walk
(`get_first_focusable_path`) goes through the documents of the widgets, and does
not enter a document that another view draws. With the part in the card, Tab in
the settings tab skipped every control of the groups
(`SettingsTabTest.jl:265`). Rejected: a Tab walk that enters the view of an
embedded document, because that changes Tab in every layout and is no part of
this plan.

**D12 (proposed by the assistant, approved with the plan 2026-11-10).** `get_document_title` gives the label of a
node and the title of its tab: the title of the card for a group and a theme,
the title for a heading, and "Scale" and "Colors" for the two parts. A group
takes the icon of the settings, and a part, a heading and a theme take the icon
of the appearance.

## 5. Steps

Each step updates the design document of each package that it changes, under
[documentation/package/platform/](../../documentation/package/platform/), and
makes one commit.

1. [x] **Top-level nodes (D2).** Done. The test editor of the first content now
   has a `Settings` and an `Appearance`, and the test checks that the two nodes
   are the ones of the editor. `make_editor_explorer_content` puts `Settings`
   and `Appearance` at the top level, after the section "Editor". Change the
   names in `ExplorerTest.jl:676`. Test: `test_explorer()`.
2. [x] **Groups of the settings (D4, D5, D6, D12).** Done. Facts: the layering
   table of the platform (`PLATFORM_SLICE_EDGES` in `PlatformSuite.jl`) gets two
   edges, `settings` → `collection` for the `CellVector`, and `settingsmanaging`
   → `tree` for `get_tree_children_steps`. `find_settings_group(settings, T)` is
   new; it replaces each `get(settings.groups, T, nothing)`. Change `Settings.jl`,
   `SettingsGroup.jl`, `SettingsWrapper.jl` and the reads of `unused_types`.
   Add `get_tree_children_steps(::Settings)`, the title and the icon of a group.
   Add a test: the node "Settings" has six children with the titles of the
   cards. Tests: `test_settings()`, `test_settings_wrapper()`,
   `test_settings_tab()`, `test_explorer()`.
3. [x] **The view of one group (D1, D11).** Done. The tab builds the rows of each
   card with the functions of the view of a group (see D11, changed in step 5). Add `SettingsGroupToWidget` and
   register it beside `SettingsToWidget`. `SettingsToWidget` prints each card
   through it. Add a test: Enter on the node "Pointer" opens a tab "Pointer",
   and a step of a spin box there writes the setting. Tests:
   `test_settings_tab()`, `test_explorer()`.
4. [x] **Parts and headings of the appearance (D7, D8, D9, D10, D12).** Done. Facts and
   choices of the implementation:
   - The tree slice reads a path of children that reaches one document, which no
     collection holds, as one child: that document, with no step of an element.
     The parts of an appearance and the colour node of "Editor" are such
     documents in fields.
   - `system_colors` moves into `AppearanceColors` with the five colour
     settings. The colour node is a computed cell that the keyword default of
     `editor_themes` makes from the fields before it, `colors` and
     `color_themes`; a write replaces `system_colors`, so it must be inside a
     part that stays.
   - `get_theme_place(T) -> (heading, rank)` is a generic of the style slice. Its
     default places a theme of `ProjecturedPlatform` under "Tools" and any other
     under "Documents", at rank 0. The appearance slice places the six themes of
     every view under "Editor" at ranks 1 to 6, and the font theme and the colour
     theme take rank 0. `set_theme!` puts each theme into its heading.
   - `get_document_title(theme)`, the name of the theme type in words, moves from
     the tab into the style slice, so the tab, a tree and a page name a theme
     alike.
   - The layering table gets two edges: `style` → `collection` and `appearance`
     → `tree`.
   - The appearance file keeps its form: the same keys, at the top level.
   - A Sonnet agent changed the 40 test and example files that made an
     `Appearance` with the old keywords or read the moved fields. Downstream, the
     same change waits for the landing: eight tests of `omnet-julia` (the legacy
     theme tests and `ResultChartTest.jl`) and `packetdiagram.jl` of
     `inet-julia` make an `Appearance` with `font_scale`, `spacing_scale`,
     `control_scale` or `color_mode`. Add
   `AppearanceScale`, `AppearanceColors` and `ThemeGroup`, and change each read
   of the twelve fields and of `open_sections`. About 30 test files build an
   `Appearance` with these keywords, and the tests of downstream packages do
   too: the step lists each call and changes it. Add
   `get_tree_children_steps` for `Appearance` and `ThemeGroup`, and the titles
   and the icons. Add a test: the node "Appearance" has the children of §3.
   Tests: `test_appearance_file()`, `test_appearance_wrapper()`,
   `test_appearance_tab()`, `test_explorer()`, and the suite of each package
   whose files the step changes.
5. [ ] **The views of the appearance (D1, D3, D11).** The code and the tests are
   done; the check in a window waits for the permission of the owner, because it
   opens a window and takes the focus. Facts and choices of the implementation:
   - The tab builds the cards of the parts, the headings and the themes with the
     functions of the views of the parts (see D11, changed in step 5); it prints
     no part through a view of a part.
   - The tests: a press on the node "Widget" shows the theme alone, and the › of
     its row "background" writes the next role, which Ctrl+Z takes back; a press
     on "Scale" shows the scale, and its + steps the zoom; a press on "Tools"
     shows a card for each theme of the heading. A press on a node shows its
     page in the explorer, so the tests press; they press no Enter.
   - The suites at `8a8b0d397` pass: `test_appearance_tab()` (159),
     `test_appearance_wrapper()` (55), `test_explorer()` (421), `test_settings()`
     (107), `test_settings_tab()` (60), `test_clipboard()`, and the theme tests of
     the 17 domain packages, with `test_julia_code_pieces()`,
     `test_data_frame_theme()` and `test_data_frame_view()`. With the test of the
     write on the theme page, `test_explorer()` passes 424 at `07ac253c4`.
   - The four views are subtypes of one abstract projection,
     `AppearancePartToWidget`, in `AppearancePartToWidget.jl`, with one IO map,
     `AppearancePartToWidgetIoMap`, and one reader. Each holds the appearance of
     the editor, which the natural renderer gives it, for the widget theme and
     the colours that it draws with.
   - `AdjustZoomOperation` and `AdjustScaleOperation` hold the `AppearanceScale`
     in place of the `Appearance`, so the view of the scale alone steps it.
   - The tab looks as before: the cards keep their summaries as descriptions,
     and a closed theme card makes its controls when it first opens. A page
     shows the summary of its part at its top, in the small font and the muted
     colour.
   - The tests of the tab read the tables of the controls from the IO map of the
     tab and of each view of a part (`_at_tables`).
   - A review found two faults of the new nodes, now fixed. The menu of a row
     counted the children of a node with `length`, which a single document does
     not have (`_find_long_children_steps`). A paste or a cut on the node of a
     group, a part or a theme wrote into the live settings or appearance:
     `Settings` and `Appearance` now refuse a pasted document, as a tool does, and
     a refusal covers each document inside them.
   - [x] Open the explorer in a window, and open one node of each kind with a
     double click. Done 2026-11-10 with the owner's permission: the window of the
     application, with the SDL backend, no settings file and a new appearance.
     The nodes Settings, Appearance and Editor open with their chevrons, and a
     double click on Pointer, Scale, Colors, Widget, Tools and Editor shows the
     page of each. The window showed two faults:
     - The address named the appearance by the place of its node,
       `entries[10]`: an `Appearance` had no title. It now has the title
       "Appearance", and a test checks the address of the page of a theme.
     - The page of one part has no margin, so its summary touches the frame of
       the page. A page of the explorer gets no margin from the navigator, but a
       tab gives its content `slot_padding`; the owner decides who gives it.

## Not in this plan

A page of the explorer has the place of its node as its address, such as
`tool_themes.themes[3]`. When a new theme type takes a place before it in its
heading, the page shows the theme at that place, its neighbour. Each node of a
list in the explorer has this limit, such as a file of the open files.


A node for each setting or field of a theme; a node for each colour variant;
the buttons "Reset all", "Save" and "Load" on the page of one group.
