# Architecture review: the application — panes, files, persistence, undo, settings, explorer, navigator

Commit 3a9b4fae4. Reviewer area key: application-shell.

## Scope

Paths: `source/platform/{pane,application,shell,filesystem,filechange,fileformat,serialization,versioning,undo,help,settings,settingsmanaging,display,explorer,navigator,essentials}` (about 24 600 lines in 118 files), and the file documents of the domains, `source/domain/*/*File.jl` (798 lines).

Read in full, or nearly in full (about 5 500 lines of code):

- `application/Application.jl`, `application/ApplicationExplorer.jl`
- `fileformat/DocumentFile.jl`
- `filesystem/FileSystemDocument.jl` lines 1 to 420 (the file row, the open of a file)
- `undo/UndoBufferToAny.jl`, `versioning/VersioningToAny.jl`, `settingsmanaging/SettingsManagingProjection.jl`
- `settings/Settings.jl`, `settings/SettingsFile.jl`, most of `settings/SettingsGroup.jl`
- `pane/PaneTabsWrapper.jl`, `pane/PaneFile.jl`, `pane/UserInterfaceFile.jl`, `shell/WindowShellWrapper.jl`, `shell/WindowChrome.jl` lines 326 to 470
- `explorer/Dashboard.jl` lines 176 to 283, `explorer/ExplorerContentFile.jl` lines 60 to 114, `navigator/NavigatorDocument.jl` lines 120 to 165, `navigator/NavigatorPageOpen.jl` lines 1 to 80
- outside the area, because the area rests on them: `kernel/editor/EditorBuild.jl`, `kernel/operation/Rerooting.jl`, `platform/natural/NaturalNotation.jl` lines 1 to 140, `platform/domain/DocumentView.jl`, `platform/screen/DocumentShow.jl`, the save and load part of `platform/style/Appearance.jl`
- `domain/json/JsonFile.jl`, `domain/yaml/YamlFile.jl`

Read as documents (about 1 900 lines): `concepts.md`, `architecture-decisions.md`, and the package documents of application, pane, shell, fileformat, serialization, undo, versioning, filechange, explorer and navigator. I read the index of `architecture-invariants.md` and the sections PAR-PER-EDITOR-STATE, PAR-NO-EDITOR-IN-DOCUMENT, PAR-PERSISTENCE-BY-VALUE, PAR-INVERTIBLE-OPERATIONS and PAR-HIGHER-ORDER-IS-DOMAIN-FREE.

Sampled with `grep` and by the package documents only: `pane/PaneProgram.jl`, `pane/PaneSurgery.jl`, `pane/PaneToWidget.jl`, `serialization/FileCut.jl`, `FileSplice.jl`, `FileProject.jl`, `PredFile.jl`, the views of the explorer and the navigator, `filechange/FileChangeStore.jl`, `undo/UndoDocument.jl`, `display/EditorDisplay.jl`, the settings views. Not read: `help/`, `essentials/`, `application/ApplicationWorkload.jl`.

Plans read (head, and the step that touches a candidate): `a-tab-shows-the-file-that-a-program-rewrites`, `a-history-records-every-edit-of-its-document`, `pending-edits-and-file-changes`, `packages-compose-by-seams`, `object-versioning`, `catalog-all-documents`, `assistant-api-consolidation`, `workbench-feature-projections`, `live-example-construction`, `filesystem-file-content-projection` (tentative), and `plan/done/editor-settings.md`.

## State

The model of this area is sound in its main lines. A history, a file, a navigator, a tab and a card are plain documents, so they nest and each one saves as the print of the tree. The edits of the panes are generic operations. One file document for each path of an editor exists since the last landings. A wrapper of `build_editor` is one seam of the kernel, and 26 wrappers use it. Outside state enters by a background cell: a file reads its text when a view draws it.

The main weakness is that the general mechanisms stop one step short, and each holder then writes the last step by hand. A view of a document is a general idea (`make_document_view`), but a navigator, a card and a file row each write the slot that keeps the view, and a tab has none. A layer around a document is a general idea (`get_edited_field`), but six functions walk the layers of a tab, each with its own rule. A transparent wrapper projection has one shape, and each wrapper writes that shape again. The text format of a domain is one fact, and a domain says it to two registries and three tables.

The second weakness is at the edge of the session. Two mechanisms keep a window for the next start, and they treat the files of the window in two ways. A file document is made by three functions, of which one reads the disk on the editor task. The application lists the tools of the window by hand in three places, beside a trait that lists them.

Undo and versioning are two models on purpose, and the documents say why. The gaps of the undo are the subject of a pending plan.

## Inventory

### I1. The ways to open something

| Function | Key that finds an open tab | What it opens | Focus | Place |
| --- | --- | --- | --- | --- |
| `open_pane!(document; title, group, target, side)`, the verb that places a document in a new tab | none: always a new tab | the document as given | no | [PaneProgram.jl:300](../../../source/platform/pane/PaneProgram.jl#L300) |
| `show_document!(document; title)`, the verb of the screen slice | identity of the document in a layer of a tab (`find_pane_tab_layer`) | `open_pane!`, then `show_pane!` | no | [PaneTabsWrapper.jl:84](../../../source/platform/pane/PaneTabsWrapper.jl#L84) |
| `_reach_tool!(editor, type, make)`, the action of a toolbar button | type of the content (`_find_tool_tab`) | `make(editor)` | yes | [WindowChrome.jl:413](../../../source/platform/shell/WindowChrome.jl#L413) |
| evaluation of `OpenFileOperation`, the request of a link, a dialog or the Files pane | path, then the open file document, then `_is_document_in_tab` | `make_file_view(file)` or `file_wrap(file)` | yes | [FileSystemDocument.jl:224](../../../source/platform/filesystem/FileSystemDocument.jl#L224) |
| `open_file!(path)`, the verb of the assistant | the same, by `_find_open_file_tab` | the same | no | [FileSystemDocument.jl:322](../../../source/platform/filesystem/FileSystemDocument.jl#L322) |
| `open_file_document!(path)`, the editor's one document of a path, with no tab | the open file list | an unread file document | – | [FileSystemDocument.jl:265](../../../source/platform/filesystem/FileSystemDocument.jl#L265) |
| evaluation of `OpenPageOperation`, the request of a link to a part | none | `Navigator(content, address)` | yes | [NavigatorPageOpen.jl:63](../../../source/platform/navigator/NavigatorPageOpen.jl#L63) |
| `open_page!(part)`, the verb of the assistant | none | `Navigator(content, address)` | no | [NavigatorPageOpen.jl:106](../../../source/platform/navigator/NavigatorPageOpen.jl#L106) |
| `make_file_tab_content(path, wrap)`, the files of the command line | none: before the editor exists | a new file document, read at once | – | [Application.jl:121](../../../source/platform/application/Application.jl#L121) |
| `acquire_document!(editor, ::FileSystemFile)`, a file row of a folder | the open file list | `_read_opened_file`, read at once | – | [FileSystemDocument.jl:66](../../../source/platform/filesystem/FileSystemDocument.jl#L66) |
| `display_in_editor(value)`, the Julia display | an `IdDict` from a shown value to its document; the tab is then found by `show_document!` ([EditorDisplay.jl:216](../../../source/platform/display/EditorDisplay.jl#L216)) (corrected by the check) | a tab or a window | – | [EditorDisplay.jl:53](../../../source/platform/display/EditorDisplay.jl#L53) |

### I2. The walkers through the layers of a tab

| Function | Follows | Stops after | Place |
| --- | --- | --- | --- |
| `find_pane_tab_layer(tab, matches)` | `get_edited_field`, else `get_wrapped_document` | 16 | [PaneDocument.jl:390](../../../source/platform/pane/PaneDocument.jl#L390) |
| `_get_tab_document(tab)` | `get_edited_field`, stops at a file | 8 | [PaneGestures.jl:152](../../../source/platform/pane/PaneGestures.jl#L152) |
| `_find_tab_file(content)` | `get_edited_field` | 8 | [PaneFile.jl:41](../../../source/platform/pane/PaneFile.jl#L41) |
| `_is_document_in_tab(tab, file)` | `get_edited_field` | 16 | [FileSystemDocument.jl:284](../../../source/platform/filesystem/FileSystemDocument.jl#L284) |
| `_find_shown_file(document)` | `get_edited_field` | 16 | [DocumentFile.jl:755](../../../source/platform/fileformat/DocumentFile.jl#L755) |
| `_find_tool_tab(tree, type)` | `get_wrapped_document`, then the content of a navigator | 1 | [WindowChrome.jl:431](../../../source/platform/shell/WindowChrome.jl#L431) |
| `get_edited_document(document)`, of the kernel, which answers the last layer (added by the check) | `get_edited_field` | 16 | [ReferencedDocument.jl:448](../../../source/kernel/reference/ReferencedDocument.jl#L448) |

### I3. The containers of documents, and the view that each keeps

`make_document_view(document)` makes the view document of a document: the state of one place that shows it, such as a scroll position. Its default answers the document itself. `FileView` is the view of a file: the file, a scroll pane, and above it the band that says "changed on disk".

| Container | Where it keeps the view | Who makes the view | Makes a new one when another holder holds it | Holds the view | Drops it in a duplicate | Place |
| --- | --- | --- | --- | --- | --- | --- |
| `PaneTab` | `content` is the view itself | the opener, by hand, for a file only | no | the tab acquires its content | by `make_document_duplicate` of the content | [FileSystemDocument.jl:277](../../../source/platform/filesystem/FileSystemDocument.jl#L277) |
| `Navigator` | `page_view`, a `NavigatorViewSlot` | its acquire and each visit | yes | yes | yes, by hand | [NavigatorDocument.jl:128](../../../source/platform/navigator/NavigatorDocument.jl#L128) |
| `DashboardCard` | `content_view`, a `NavigatorViewSlot` | the acquire of the dashboard, and `_add_card_holds` | yes | yes | – | [Dashboard.jl:211](../../../source/platform/explorer/Dashboard.jl#L211) |
| `FileSystemFile` (a row of a folder) | `document_view`, a plain field | its acquire | yes | yes | – | [FileSystemDocument.jl:66](../../../source/platform/filesystem/FileSystemDocument.jl#L66) |
| `ExplorerSection` | none: it links documents | – | – | – | – | – |
| window (`WindowDocument`) | none | – | – | – | – | – |

### I4. What writes state to disk

| Mechanism | Format | What it writes | Who calls it |
| --- | --- | --- | --- |
| `save_document` / `load_document` | binary, `.pdoc` | one document, cell values | `write_document_file`, `SaveDocumentOperation` |
| `save_file_text!` / `save_file!` / `load_file` (file types) | the text of the format | one file document, with `file("…")` for a held file | `SaveFileOperation`, `write_document_file` |
| `save_project!` / `load_project` | the same, many files | a graph, cut at the files | `save_user_interface` |
| `PredFile`, `.pred` | a constructor call as text | any document | the two rows below |
| `export_document` / `import_document` | natural text | one document | `write_document_file`, two operations |
| `save_user_interface` / `load_user_interface` | `.pred` and a project | the whole document of the editor, and every file it reaches | nothing in `source/` |
| `save_explorer_content!` / `load_explorer_content` | `.pred`, saved alone | the root section of the explorer | `run_application`, by hand |
| `write_settings_file!` / `read_settings_file!` | TOML | the settings groups | Save and Load of the settings tab, the start |
| `save_appearance!` / `load_appearance!` | TOML, own encoder | scales, colours, themes | the appearance tab, the start |
| `write_conversation` | (not read) | a conversation | (other area) |

So there is one generic serializer of documents as text (`.pred`), one binary one, and one text form per format. Settings and appearance do not use them, by a recorded choice (finding AS-8).

### I5. The wrappers of `build_editor`

26 wrappers, each a keyword. `:container`: `tabs` 0, `undo` 5, `shell` 10, `focus_cycling` 20, `clipboard` 30, `gesture_help` 40, `command_palette` 50, `gesture_log` 90. `:window`: `tooltip` -20, `context_menu` -10, `window` 0. `:screen`: `settings` -10, `appearance` 0, `message_log`, `file_change`, `mcp_log` 10, `frame_statistics`, `background_work`, `task`, `agent_event`, `system_process`, `language_server` 20, `fault_log` 30, `assistant_list` 40, `quit_on_escape` 100. `:document`: none.

A wrapper does one or more of five things: it wraps the root document and the projection; it adds a feed; it adds a start or a stop step; it adds rows for windows that open later; it gives a wrapper to the window wrapper. The order matters only inside `:container`, and [shell.md](../../../documentation/package/platform/shell/shell.md) gives the reason of each number. The wrappers compose their projection in three ways (finding AS-3).

### I6. Where the state of one editor lives

| Home | Found by | Examples |
| --- | --- | --- |
| a wrapper document around the root | a walk down `content`, at most 8 steps ([SettingsDocument.jl:43](../../../source/platform/settingsmanaging/SettingsDocument.jl#L43)) | `Settings`, `Appearance` |
| a session document of the editor, by type | `get_session_document!(make, editor, T)` | about 18 kinds: open files, explorer content, logs, lists |
| the store of a feed | `find_file_change_store(editor)` | the watched files |
| a process-global constant | its name | the stores of the task feed, the message log and the MCP log; the display editor |

## Findings

### AS-1 A place shows a document through a view: three hand-written slots, and a tab has none

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism for every part) and 8 (reuse an existing view).
- **Today:** Three containers keep a view of what they show, and each writes the same code. `_make_page_view_slot` of the navigator ([NavigatorVisits.jl:263](../../../source/platform/navigator/NavigatorVisits.jl#L263)) and `_make_card_view_slot` of the dashboard ([Dashboard.jl:201](../../../source/platform/explorer/Dashboard.jl#L201)) have the same body. `get_navigator_page_view` ([NavigatorVisits.jl:41](../../../source/platform/navigator/NavigatorVisits.jl#L41)) and `_get_card_view` ([Dashboard.jl:192](../../../source/platform/explorer/Dashboard.jl#L192)) answer "the view while it still shows this document, else the document". The three acquires make a new view "when another holder holds it" in three wordings ([NavigatorDocument.jl:128](../../../source/platform/navigator/NavigatorDocument.jl#L128), [Dashboard.jl:211](../../../source/platform/explorer/Dashboard.jl#L211), [FileSystemDocument.jl:66](../../../source/platform/filesystem/FileSystemDocument.jl#L66)). A tab has no slot. The pane slice never calls `make_document_view`. The opener of a file makes the view by hand: `make_file_view` in `_make_opened_tab_content` ([FileSystemDocument.jl:277](../../../source/platform/filesystem/FileSystemDocument.jl#L277)), in `open_file!` (line 327) and in `make_file_tab_content` ([DocumentFile.jl:242](../../../source/platform/fileformat/DocumentFile.jl#L242)).
- **Example:**
  ```julia
  # today: a tab gets the view from its opener, a card makes it itself
  open_pane!(make_file_view(open_file_document!("notes.md")))           # tab: scroll and band
  open_pane!(open_file_document!("notes.md"))                           # tab: the bare file, no scroll, no band
  insert_elements!(dashboard.cards, 1, [DashboardCard("Notes", file)])  # card: makes its FileView itself

  # proposal: every holder has the same slot, filled by one function
  @document struct PaneTab; title; content; content_view::ViewSlot = ViewSlot(); end
  acquire_view_slot!(editor, holder, slot, document)   # make when missing or held elsewhere, then hold
  get_shown_document(slot, document)                   # the view while it shows `document`, else `document`
  open_pane!(open_file_document!("notes.md"))          # the tab shows the file as a card does
  ```
- **Problem:** The same document looks different by the place that shows it and by the function that opened it. A domain that gives its document a view (a method of `make_document_view`) gets it on a navigator page and in a card, and not in a tab that `open_pane!` or `show_document!` opens. The next container, and the next kind of view, must copy about 40 lines and the rule for a duplicate. The dashboard also needs `_add_card_holds` (27 lines, 55 with its two helpers; corrected by the check), which four places call: the answer to Insert, the answer to a paste, the reader of the explorer and the reader of the page, because an edit of the list changes what the dashboard holds.
- **Proposal:** One slot type in the domain slice, beside `make_document_view`: the type `NavigatorViewSlot` moved and named for what it is. With it, three functions: make the view of a document when the slot has none of that document or another holder holds it; answer what the slot shows; drop the slot in a duplicate. `PaneTab` gets the slot. `Navigator`, `DashboardCard` and `FileSystemFile` use the same three functions. The openers pass the document.
- **What goes away:** `_make_page_view_slot`, `_is_page_view_slot`, `_make_card_view_slot`, `_get_card_view`, `_get_file_document_view`, the three hand-written acquire bodies, the calls of `make_file_view` in the openers, and `make_file_tab_content`. About 120 lines, and one rule in place of four.
- **What stays:** Each place keeps its own scroll position. A file in a tab, a card and a page is one file document with a view in each. A visit of a navigator keeps its view for Back. A save writes no view.
- **Risk and open questions:** The selection path of a tab is `tabs[i].content.…` today, with the view as the content; with a slot the path goes through the document, as it does in a card. The maps of `PaneToWidget` must then prefix the field of the view, as the dashboard page does. The rule of the hold of a document is a topic that the owner deferred (the note "document lifecycle plan deferred"); this finding changes where the view is made, and not who holds what.
- **Related plans:** `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md` (in progress; its steps 1a and 1b made the three slots, one at a time).
- **Check:** confirmed. Value stays high. I opened the two slot makers, the three "what does it show" functions, the three acquires, the acquire of a tab ([PaneSurgery.jl:561](../../../source/platform/pane/PaneSurgery.jl#L561)), `DocumentView.jl` and `FileView.jl`. Each statement holds. A `grep` finds no call of `make_document_view` in `source/platform/pane/`, and two methods of it in `source/` (`Url` and `FileDocument`), so a `Url` in a tab of `open_pane!` shows with no `UrlView` too. The plan itself says that the helpers of the card "repeat the shape of the private helpers of `NavigatorVisits.jl`, which another module cannot call", so the copy has no reason but the module boundary. Four notes for the owner:
  - A third repeated part, which the report names only as a risk: each holder projection maps a path through the field of the view by hand, with the same rule (the field of the view goes in front on the way forward and comes off on the way back, except for a part that the view introduced): [NavigatorToWidget.jl:538](../../../source/platform/navigator/NavigatorToWidget.jl#L538) and line 590, [DashboardToWidget.jl:274](../../../source/platform/explorer/DashboardToWidget.jl#L274) to 292, [FileSystemFileToWidget.jl:33](../../../source/platform/filesystem/FileSystemFileToWidget.jl#L33) and line 50. The shared slot needs these two maps as shared functions too, or the tab becomes a fourth copy.
  - `acquire_view_slot!` makes the view and holds it in the acquire. What a holder holds is open question 10 of the plan above, which the owner deferred to a plan of its own. So this change belongs in that plan or after it, and not before it. `_add_card_holds` stays: it is about the hold, not about the view.
  - The proposal does not go against the rule that a tab page gets no scroll of its own: the scroll comes from the view of the file, as in a card, and a document with no view shows as itself.
  - No feature is lost. What changes: the path of a file in a tab is `content.…` and no longer `content.file.…`, and a save of the tabs writes the file and needs no `find_held_file` of the view.

### AS-2 The text format of a domain is declared to two registries and three tables

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (a missing case gets its row in the generic mechanism); 5 (domains are independent: the platform names no domain).
- **Today:** A domain says "JSON text is `.json`, read by `parse_json`" twice. The natural slice keeps `type => (format, extension)` and `format => parser` ([NaturalNotation.jl:59](../../../source/platform/natural/NaturalNotation.jl#L59), [:74](../../../source/platform/natural/NaturalNotation.jl#L74)). The serialization slice keeps `extension => file type` ([FileProject.jl:268](../../../source/platform/serialization/FileProject.jl#L268)), and the file type answers `get_file_domain`, `parse_file_content` and `emit_text` ([JsonFile.jl:21](../../../source/domain/json/JsonFile.jl#L21)). 6 of the 8 file types of the domains write the same line, `emit_text(f) = print_natural_text(get_file_content(f))`, and `JuliaFile` and `MathFile` add a line break to it (corrected by the check; the report said all 8). 12 file types in `source/` repeat the three fields `filename`, `content`, `disk` (corrected by the check; the report said 13), and one of them, `SourceFile`, has a fourth field. Each registry has its own answer to "which extension writes this document": `get_natural_extension` ([NaturalNotation.jl:205](../../../source/platform/natural/NaturalNotation.jl#L205)) and `find_file_extension` ([FileProject.jl:297](../../../source/platform/serialization/FileProject.jl#L297)). Three more tables hang on the extension: the seed of a new file, `make_document_seed(::Val{:json})` ([DocumentFile.jl:38](../../../source/platform/fileformat/DocumentFile.jl#L38)); the icon, a fixed chain of `if` in the platform that names `.jl`, `.json`, `.ned` and `.ini` ([DocumentFile.jl:440](../../../source/platform/fileformat/DocumentFile.jl#L440)); and the second name of a format, `register_natural_parser!(:yml, parse_yaml)`. `read_document_file` asks the natural registry first and the file types second ([DocumentFile.jl:99](../../../source/platform/fileformat/DocumentFile.jl#L99)), and a save goes through the file type ([DocumentFile.jl:319](../../../source/platform/fileformat/DocumentFile.jl#L319)).
- **Example:**
  ```julia
  # today, in the JSON domain and in the platform
  register_natural_domain!(JsonDocument; rung = :syntax, make = …, format = :json, extension = ".json", parse = parse_json)
  register_file_document_type!(".json", JsonFile)
  @document struct JsonFile <: FileDocument; filename::String; content::Document = JsonNothing(); disk::FileDiskState = FileDiskState(); end
  get_file_domain(::Type{<:JsonFile}) = JsonDocument
  parse_file_content(::Type{<:JsonFile}, text) = parse_json(text)
  emit_text(f::JsonFile) = print_natural_text(get_file_content(f))
  make_document_seed(::Val{:json}) = JsonInsertion()
  # and in fileformat/DocumentFile.jl:  extension == ".json" ? :braces : …

  # proposal: the file type is the one row of a format
  @file_document JsonFile JsonDocument                     # the struct with its three fields
  register_file_format!(JsonFile; extensions = (".json",), parse = parse_json,
                        seed = JsonInsertion, icon = :braces)
  make_reference_leaf(::JsonFile, marker) = JsonString(make_marker_text(marker))   # what only JSON knows
  ```
- **Problem:** The read of a file and its save go through two tables that a domain must keep equal. A format with a file type and no natural parser reads by one path, and one with both reads by the other. The icon of a new format needs an edit of the platform, and the platform names formats of a product that it does not know (`.ned`, `.ini`). Only 4 of the 9 natural formats have a seed, which [fileformat.md](../../../documentation/package/platform/fileformat/fileformat.md) lists as a limit: the table is easy to forget.
- **Proposal:** The file type is the one description of a text format: its extensions, its domain, its parser, its seed and its icon, declared in one call. The natural slice asks it for the parser and the extension of a format, so `parse_natural_text(:json, …)` and `print_natural_text` stay. The default `emit_text` is the natural print of the content. `get_file_icon` and `make_document_seed` read the row.
- **What goes away:** `_FORMATS` and `_PARSERS` of the natural slice as stores of their own (or the reverse: the file types read them), one of `get_natural_extension` and `find_file_extension`, `make_document_seed(::Val)` with its methods, the `if` chain of `get_file_icon`, the branch `_is_natural_path` of `read_document_file`, and about 6 lines in each of 8 file types.
- **What stays:** Every format, every extension, the marker language, the `.pred` inline text of a format, the natural text that the assistant reads and writes, and a file type with no parser (`TextFile`, `ImageFile`).
- **Risk and open questions:** The natural slice is below the serialization slice or beside it; the direction of the dependency must be chosen. `register_natural_parser!` is keyed by the format "so the package that owns a grammar can fill this seam without owning the projection": a format whose parser and file type live in two packages needs the two-step form to stay possible.
- **Related plans:** none found (`grep` of `plan/pending` and `plan/tentative` for the names of both registries). The check found one: `plan/pending/packages-compose-by-seams.md`, decisions C1 and C7 (see the check below).
- **Check:** confirmed-with-corrections. Value high → medium. The facts hold, with two counts corrected in the text above (6 of 8 `emit_text` lines are equal; 12 file types, not 13). I opened both registries, `JsonFile.jl`, the `__init__` of the JSON domain, the seeds, the icon chain and the reads. A read goes to the natural parser (`read_document_file` → `import_document`), a save goes to the file type (`emit_text`), and `read_file_content_again` ([DocumentFile.jl:655](../../../source/platform/fileformat/DocumentFile.jl#L655)) chooses one of the two by whether the type is the type of the extension. No design document gives a reason for the two tables. Three corrections of the proposal:
  - `register_file_format!(JsonFile; …)` is a registry call in an `__init__`. Decision C1 of the owner in `plan/pending/packages-compose-by-seams.md` (2026-09-30) is "seams only": no registry table and no `__init__` registration; the package that owns a type adds a method. C7 of the same plan says that the natural tables stay for now and that a later plan moves the natural register functions to seams. So the one row of a format must be methods on the file type, which has three already (`get_file_domain`, `parse_file_content`, `emit_text`), with the extensions, the seed and the icon as three more; and the change belongs in the plan that C7 announces, which is not written yet.
  - `@file_document` can not make `SourceFile`, which has a fourth field, and D11 of the tab plan settled the three fields in each type. Drop the macro; the default `emit_text` alone removes the repeated line.
  - To keep: `register_natural_expression!` (a format as code), the answer from a type to its format for an insertion that a person types into, and a parser that another package gives for a format.
  The value is lower because the direction (seams) is decided already, and the gain for the next domain is about ten lines, one read path, and no edit of the platform for an icon.

### AS-3 Each window wrapper writes the same transparent projection by hand, in two styles

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 2 (a general step works for every domain); the settled decision that only the projections of the algebra hold a projection in a field.
- **Today:** A wrapper document holds one `content` and draws nothing. Its projection prints the content as its own output, takes the step `content` off a path on the way forward and puts it back on the way back, and its reader gives the gesture to the content, reroots the answer, merges a collection of intents, follows a route, and reads its own keys first or last. I compared four of them line by line: `UndoBufferToAnyProjection` ([UndoBufferToAny.jl:53](../../../source/platform/undo/UndoBufferToAny.jl#L53) to 141), `SettingsManagingProjection` ([SettingsManagingProjection.jl:36](../../../source/platform/settingsmanaging/SettingsManagingProjection.jl#L36) to 122), `VersioningToAnyProjection` ([VersioningToAny.jl:73](../../../source/platform/versioning/VersioningToAny.jl#L73) to 232) and, by `grep` of the same calls, `AppearanceManagingProjection`, `FileToContent` and the two clipboard projections. Each declares its own `_CONTENT_STEPS` and its own `_collected_intents`. They differ in one hook: what to do with the answer (`_record_operation`, `wrap_setting_writes`). There are two styles. The first finds the child projection by the recursion and joins the table by type dispatch, as the `undo` wrapper does ([UndoBufferToAny.jl:241](../../../source/platform/undo/UndoBufferToAny.jl#L241)). The second holds the child projection in a field `inner`: 15 projections outside `source/platform/projection/higherorder/` do so (settings, appearance, gesture help, command palette, focus cycling, selection walking, the recorder and the overlay of the gesture log, the overlay of the fault log, quit on Escape, tooltip window, context menu window, gesture tracking, drag tracking, window managing; corrected by the check, the report said 12), and `FileToContent` holds one in `content` ([FileToContent.jl:25](../../../source/platform/fileformat/FileToContent.jl#L25)). Versioning also has its own rerooter, `_prefix_op`, with a closed list of seven operation types (corrected by the check; the report said six) and "else unchanged" ([VersioningToAny.jl:240](../../../source/platform/versioning/VersioningToAny.jl#L240)), beside the generic `reroot_operation` of the kernel ([Rerooting.jl:32](../../../source/kernel/operation/Rerooting.jl#L32)).
- **Example:**
  ```julia
  # today: about 70 lines in each wrapper slice
  struct SettingsManagingProjection <: Projection; inner::Projection; end
  print_document(p::SettingsManagingProjection, recursion, input, ctx) = …   # print content, forward its output
  map_reference_forward(p::SettingsManagingProjection, iomap, reference) = … # peel `content`
  map_reference_backward(p::SettingsManagingProjection, iomap, reference) = …# prepend `content`
  read_intent(p::SettingsManagingProjection, recursion, change, iomap) = …   # delegate, reroot, merge, own keys

  # proposal: one projection of the algebra, and a hook per wrapper
  ContentDelegatingProjection(inner; field = :content, own_keys = :last,
                              answer = (iomap, gesture, operation) -> wrap_setting_writes(iomap.input.settings, operation))
  ```
- **Problem:** A change of the reader contract (a new kind of intent, a route, a collection) must be made in every copy, and a copy that misses it fails only in the window that stacks it. The comment in `ScreenToScreen.jl` says of its own `_prefix_op` that "an unhandled type would fall through unchanged and apply its child-relative path against the screen root"; versioning has that fall-through. A new wrapper costs 70 lines before its first feature. The `inner` field is a second way to compose projections beside the algebra.
- **Proposal:** One higher-order projection in the algebra folder that delegates to the document in one field: print, the two maps, the collection, the route and the rerooting, with the generic `reroot_operation`. A wrapper gives the field, the order of its own keys, and one function over the answer. The versioning projection gives a computed path of three steps in place of one field.
- **What goes away:** The printer, the two maps and most of the reader in about 12 wrapper projections (roughly 60 to 80 lines each), the local `_CONTENT_STEPS` and `_collected_intents` helpers, `_prefix_op` and `_prepend` of versioning, and the projection fields outside the algebra.
- **What stays:** Each wrapper keeps its document, its keys, its order (undo reads its keys last, versioning first, as [undo.md](../../../documentation/package/platform/undo/undo.md) explains) and its effect on the answer.
- **Risk and open questions:** I read four of the copies in full and matched the rest by `grep`. The window-layer wrappers (tooltip, context menu, the two trackers) do more than delegate, so they may use only part of the shared projection. The owner should say whether the 12 `inner` fields count as "the algebra" today; I found no written exception.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (the wrapper seam is done; it does not speak of the projections). Other areas: clipboard, gesturehelp, focus, tooltip, screen, appearance.
- **Check:** confirmed-with-corrections. Value stays high, effort large. I read the undo, settings, versioning and file projections in full and the head of the appearance one, and counted the rest with `grep`. Two counts are corrected in the text above (15 `inner` fields, seven operation types). `_CONTENT_STEPS` is declared in 4 slices and the helper for a collection in 6. No plan covers it; the versioning plan left "a shared `prefix_operation`" as an open question "if a third elimination projection appears". Corrections and notes:
  - The 15 are not one shape. Shape A is a wrapper document whose `content` step comes off and goes back: undo, settings, appearance, file, clipboard, the tooltip window, the context menu window, gesture tracking, drag tracking, and versioning with three steps. Shape B is a reader around the same input, with no step: quit on Escape, focus cycling, selection walking, gesture help, command palette, the two of the gesture log, the fault log overlay, window managing. One projection with one field fits shape A only. Shape B needs a second, smaller one, or stays.
  - Evidence of drift, which makes the finding stronger: the reader of versioning has no branch for an intent with a route (`grep` of `follow_intent_route` and `change.route` gives 0 in `VersioningToAny.jl`, and 1 to 3 in each of the ten other files of shape A, the two clipboard projections among them). The `_prefix_op` of versioning ends in "else unchanged", and the one of `ScreenToScreen.jl` ends in `reroot_operation`. Undo gives the child a context with the step `content` ([UndoBufferToAny.jl:59](../../../source/platform/undo/UndoBufferToAny.jl#L59)); the settings, appearance, tooltip, context menu and two tracking projections pass the context unchanged. The shared projection must choose one of each, so the change needs the tests of each wrapper.
  - The owner decided on 2026-10-08 that only a projection of the algebra holds a projection in a field; I found it written in no rule document. The proposal goes with that decision. But its example takes `inner` as an argument: the shared projection should get the child from the recursion and the dispatch, as undo does. `plan/done/editor-settings.md` (3.8) chose the `inner` form for the settings and the appearance wrapper on purpose ("it holds only its inner projection"), so the owner must say that the decision covers these wrappers.
  - `FileToContent` keeps its repeat card, its `path_files` property and its `content` and `accepts` override, so only its reader and its maps can be shared. No feature is lost when each wrapper keeps its hook and the order of its keys.

### AS-4 The editor's file document is made in three ways, with two wrap parameters

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 9 (outside state enters by an acquire on a task); 1 (who needs a value computes it).
- **Today:** `make_unread_file` makes a file document that holds the seed and reads its text on a task when a view draws it ([DocumentFile.jl:207](../../../source/platform/fileformat/DocumentFile.jl#L207)); `open_file_document!` uses it. `make_file_tab` reads and parses the file at once ([DocumentFile.jl:169](../../../source/platform/fileformat/DocumentFile.jl#L169)); the open of a tab uses it through `_make_opened_file` ([FileSystemDocument.jl:245](../../../source/platform/filesystem/FileSystemDocument.jl#L245)), on the editor task, inside the evaluation of `OpenFileOperation`, and so does a file row of a folder (line 106). `make_file_tab_content` makes the files of the command line before the editor exists ([Application.jl:121](../../../source/platform/application/Application.jl#L121)). The history of a file comes from a function that each maker must pass: `make_history_wrap(settings)` in the application (line 120) and `_make_editor_history_wrap(editor)` in the file-system slice (line 256). `OpenFileOperation` carries `wrap` and `file_wrap`; no caller in `source/` passes `wrap`, and `file_wrap = Navigator` has three callers. The layer `:document` of the wrappers ("acts on each document", [EditorBuild.jl:57](../../../source/kernel/editor/EditorBuild.jl#L57)) has no member, so the one thing that is put around each document is passed by hand. A read of a file then passes four functions, which call one another (corrected by the check; the report said four entries): the task `_read_file_text_answer` (line 810) calls `read_file_content_again` (line 655), which calls `read_document_file` for the type of the extension and `_read_own_file` (line 664) for another type.
- **Example:**
  ```julia
  # today
  tabs = [make_file_tab_content(path, make_history_wrap(settings)) for path in paths]        # at the start
  make_file_tab(op.path, document -> history(op.wrap(splice_held_files!(document, …))))      # the open of a tab
  file = make_unread_file(path, _make_editor_history_wrap(editor)); add_open_file!(editor, file)  # a card, a load

  # proposal: one maker, and the tab is one more holder
  file = open_file_document!(path; editor)          # always unread; a view reads it on a task
  open_pane!(file)                                  # with AS-1, the tab makes its view
  run_application("a.json")                         # posts OpenFileOperation("a.json") once the editor exists
  ```
- **Problem:** A large file opened by a click blocks the loop while it parses, and the same file opened as a card does not. The files of the command line are not in the open file list until their tab is acquired, and they get their history from another call than every later file. A host that builds its own window must know which maker to call; the docstring of `make_file_tab` has to warn that its answer is "a new document, which no other place shares".
- **Proposal:** The editor makes its file document in one function, unread, with the history inside it. A tab, a card, a file row and a link all ask that function. The read is always the background cell. `make_file_tab` stays only as the plain reader for code with no editor, or goes into `read_document_file`.
- **What goes away:** `make_file_tab_content`, `_make_opened_file`, `_read_opened_file`, the `wrap` field of `OpenFileOperation`, the `wrap` argument of the makers, one of the two history functions, and the unused `:document` layer if nothing else takes it.
- **What stays:** One file document for each path. A file with edits keeps them over a change on disk. A file that does not exist opens as its seed. `file_wrap = Navigator` for a link stays as it is, or becomes a plain `open_pane!(Navigator(file))`.
- **Risk and open questions:** A new tab shows the row "reading" for a frame or two before its text, and the first focus can not go into a content that is not read yet. A file that is its own content (`is_own_content`) can not be made unread today (`make_unread_file` throws), so that case needs its own answer. Step 6 of the plan below chose to keep both makers; I did not find the reason written.
- **Related plans:** `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md` (in progress; step 6 is done and keeps `make_file_tab` for the open of a tab). `plan/pending/a-history-records-every-edit-of-its-document.md` (design to decide: where a history lives).
- **Check:** weakened. Value medium → low. The facts hold: three makers, two history calls, a parse on the editor task, and no caller of `wrap` of `OpenFileOperation` in `source/` or in omnet-julia. One statement is corrected above (the four reads are one chain). The proposal "always unread" loses three things that work today:
  - `open_file!(path)` answers a tab whose document is read, so the assistant and a test read and edit it in the same code unit. An unread file reads only when a view draws it, and `open_file!` does not show its tab (to show is a separate step, by the owner), so a file that is opened and not shown would stay the seed.
  - A tab that a person opens takes the caret in the content (`_make_new_tab_cursor`, [PaneSurgery.jl:579](../../../source/platform/pane/PaneSurgery.jl#L579)); an unread content has no place for it. The report names this one.
  - A link to a section of a file finds no section before the read. This is open question 13 of the plan above: the owner chose option B for now (the file opens at its top) and option C later, "in a plan of its own": the navigator keeps the name and finds it after the read.
  So one maker needs a mechanism for what waits for the read, and the owner put that mechanism in a later plan. The reason of the eager read is written, partly: the comment at [FileSystemDocument.jl:62](../../../source/platform/filesystem/FileSystemDocument.jl#L62) says that the read "runs in the evaluation of the operation that acquires, where a read of the disk is in its place". The part that holds now and is small: remove the `wrap` field of `OpenFileOperation`, and open the files of the command line through the maker of the editor, so `make_file_tab_content` and the second history call go away. The `:document` layer is not unused by design: see the check of AS-9.

### AS-5 "Find the tab that shows it, else open it" is written three times for four openers, with seven walkers (counts corrected by the check; the report said five times and six walkers)

- **Kind:** several-ways · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 7 (one mechanism); 6 (decide locally: the pane tree knows what its tabs show).
- **Today:** Tables I1 and I2. Four openers each find an open tab and then open, show or focus: `show_document!`, `_reach_tool!`, the evaluation of `OpenFileOperation`, and `open_file!`; the last two share `_is_document_in_tab`, so the search is written three times. The display is no fifth one: it calls `show_document!` (corrected by the check; the report said five). Six functions walk from the content of a tab through its layers, with a stop at 8 or at 16, and with two rules for what a layer is: `get_edited_field` alone, or `get_edited_field` and then `get_wrapped_document`. `_find_tool_tab` knows the navigator by name. The pane slice has the general walker, `find_pane_tab_layer` ([PaneDocument.jl:390](../../../source/platform/pane/PaneDocument.jl#L390)), and three of the other five are in the pane slice itself or in a slice that depends on it.
- **Example:**
  ```julia
  # today
  _is_document_in_tab(tab, file)                                   # filesystem, 16 layers, edited field only
  _get_tool_document(get_wrapped_document(tab.content)) isa type   # shell, wrapper then navigator
  find_pane_tab_layer(tab, layer -> layer === document)            # pane, both rules

  # proposal: one finder and one "reach" builder in the pane slice
  find_pane_showing(matches; editor)                       # the tab whose layers match, as a part, or nothing
  make_reach_pane_operation(matches; make, focus, group)   # that tab, else a new tab of make()
  ```
- **Problem:** A new layer type (a view, a history, a zoom pane) is seen by some finders and not by others. A file inside a navigator inside a history is found by `find_pane_tab_layer` and, at a depth past 8, not by `get_pane_file_group`. A tool in a tab that a view wraps would open twice. Each new "open X" verb writes the same ten lines again.
- **Proposal:** `find_pane_tab_layer` is the one walker. One finder answers the tab that shows a match, and one builder answers "reach or open". Place, show and focus stay three steps, as the owner decided: the builder takes `focus`, and the verbs call `show_pane!` after it.
- **What goes away:** `_is_document_in_tab`, `_find_open_file_tab`, `_focus_open_file!`, `_find_tool_tab`, `_get_tool_document`, `_find_tab_file`, `_get_tab_document`, `_find_shown_file`, and the search inside `show_document!`: about 90 lines in four slices.
- **What stays:** A press on a tool reaches its tab and opens no second one. A file that is open keeps its tab. `open_pane!` always opens a new tab.
- **Risk and open questions:** `_get_tab_document` stops at the file on purpose ("the document of a file is the document, and not the data in it"); the one walker needs that as a predicate, not as a second walker.
- **Related plans:** `plan/pending/assistant-api-consolidation.md` (pending; it is about the verbs that the assistant sees, and not about these finders).
- **Check:** confirmed-with-corrections. Value stays medium, effort small. I opened the six walkers and the openers; the line numbers and the limits (16, 8, 8, 16, 16, 1) hold. Corrections:
  - The display is no opener of its own: `_show_in_session!` calls `show_document!` ([EditorDisplay.jl:216](../../../source/platform/display/EditorDisplay.jl#L216), line 221), and its `IdDict` goes from a value to its document. So there are four openers and three searches, not five (corrected in the text and in table I1).
  - There is a seventh walker, in the kernel: `get_edited_document` ([ReferencedDocument.jl:448](../../../source/kernel/reference/ReferencedDocument.jl#L448)) follows `get_edited_field` to the last layer, with a limit of 16 (added to table I2). `_find_shown_file` is in the fileformat slice, which does not use the pane slice, so it can not call `find_pane_tab_layer`. The one walker therefore belongs beside `get_edited_document`: "the first layer that matches" on the same chain. `find_pane_tab_layer` is then that walk from `tab.content`.
  - The limit of 8 against 16 is no real case: a tab has three or four layers. The real difference is the rule: four walkers follow `get_edited_field` only, one follows `get_wrapped_document` too, and one knows `Navigator` by name.
  To keep: `_find_tool_tab` looks in the focused group first, and `_get_tab_document` stops at a file. Place, show and focus stay three steps, as the proposal says.

### AS-6 Two mechanisms keep a window for the next start, and they treat its files in two ways

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 6 (state belongs to an editor); the settled decision that a saved file is the print of the tree.
- **Today:** `save_user_interface(path)` writes the whole document of the editor as a `.pred` file in a project, and with it writes every file document that the window reaches ([UserInterfaceFile.jl:33](../../../source/platform/pane/UserInterfaceFile.jl#L33) to 43). `load_user_interface` reads every file at once with `load_project(…; follow = true)` and takes no editor, so its files are not the editor's documents of their paths and have no history (line 60). Nothing in `source/` calls either. `save_explorer_content!` writes the root section of the explorer alone, with `file("…")` for a held file, and writes nothing of that file ([ExplorerContentFile.jl:65](../../../source/platform/explorer/ExplorerContentFile.jl#L65)); `load_explorer_content` gives each such name the editor's document with `open_file_document!` (line 108). `run_application` wires the second by hand: a posted `RestoreExplorerContentOperation` before the loop and a save after it ([Application.jl:618](../../../source/platform/application/Application.jl#L618), [:625](../../../source/platform/application/Application.jl#L625)). So a new start gives back the explorer, and not the tabs, the splits or a navigator address, though each of them saves itself correctly as a part of the document.
- **Example:**
  ```julia
  # today, in run_application only
  post_operation!(editor, RestoreExplorerContentOperation(get_explorer_content_file(root); folder = root))
  result = run_editor!(editor; …)
  save_explorer_content!(get_session_explorer_content(; editor), file; folder = root, editor)

  # proposal: a wrapper, for every host
  build_editor(document, projection; session_file = (; folder = root), …)
  # start step: load the kept document, splice each file("…") with open_file_document!
  # stop step:  save the root document alone, each held file as file("…")
  ```
- **Problem:** A host that builds its window with `build_editor` gets neither. The older function has the side effect that a save of the layout writes the unsaved edits of every open file. Its load makes a second document of a path, which the file work of the last weeks removed everywhere else.
- **Proposal:** One mechanism: the save of a document alone with held files as names (what the explorer content does), and the load that splices the editor's file documents. It is a wrapper of `build_editor` with a start and a stop step, so the application and every host get it by a keyword. It keeps the root document, of which the explorer content is one part, or only the explorer content where the host asks for that.
- **What goes away:** The project save inside `save_user_interface` and the eager load of `load_user_interface`; `RestoreExplorerContentOperation` and the two hand-written lines of `run_application`.
- **What stays:** The content of the explorer comes back at a start. `save_user_interface` stays as a verb for a named path. The bands of the shell are still not saved.
- **Risk and open questions:** Whether the tabs should come back at a start is a product choice of the owner; this finding only says that the two functions should share one way to write and read held files. The explorer content is a session document that outlives a closed Explorer tab, so "save the root" alone does not cover it.
- **Related plans:** `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md` (step 6 names "a load of a saved file" as a holder of the one file document; `load_user_interface` is not on its list).
- **Check:** weakened. Value medium → low. The facts hold. I opened both pairs of functions, `run_application` and `UserInterfaceFileTest.jl`. But the difference is smaller than the title says, and the proposal does more than it must:
  - Only one mechanism is connected to a start. Nothing in `source/` and nothing in omnet-julia calls `save_user_interface` or `load_user_interface`; two tests do. `plan/done/a-file-saved-alone-names-the-files-that-it-holds.md` recorded this, and said of the same rule for the project save of `save_user_interface`: "That change belongs to its own plan." No such plan exists.
  - The wrapper that keeps the root document and gives back the tabs at a start is a new feature and a product choice, as the report says itself. New features are not the goal of this review.
  - The proposal removes a behaviour that the docstring of `save_user_interface` states: the save writes each open file too. With "held files as names" the edits that no save wrote are not on disk when the window is read again.
  What holds, and is small: `load_user_interface` gives a file tab a bare file document (the test asserts `json_back isa JsonFile`): no view, no history, and a second document of its path. It should take the editor and splice with `open_file_document!`, as `load_explorer_content` does. The owner said in C16 of `plan/pending/packages-compose-by-seams.md` that a person "should absolutely be able to save the complete state of the UI", so the pair should be repaired and not removed.

### AS-7 The tools of a window are listed by hand in three places, beside the trait that lists them

- **Kind:** special-case · **Value:** medium · **Effort:** small · **Confidence:** medium
- **Principle:** 7 (a missing case gets its row); 10 (a surface by reflection, not by a second list).
- **Today:** `make_editor_explorer_content` names the message log, the gesture log, the fault log, the MCP log, the open files, the tasks, the assistants, the frame statistics, the frame times, the background work, the selection inspector, the process tree, the settings, the appearance and three help documents, and then adds "each kind that a loaded package marks" with the trait `is_session_explorer_entry_type` ([ApplicationExplorer.jl:35](../../../source/platform/application/ApplicationExplorer.jl#L35) to 58, [:63](../../../source/platform/application/ApplicationExplorer.jl#L63)). `make_window_toolbar` names 13 tools again, each with a label, a type and an icon ([WindowChrome.jl:231](../../../source/platform/shell/WindowChrome.jl#L231) to 284). `RECORDED_TOOLS` maps four wrapper keywords to five of them (line 266; `frame_statistics` gives two buttons; corrected by the check), and the `shell` wrapper tests each keyword in `parts.arguments` ([WindowShellWrapper.jl:51](../../../source/platform/shell/WindowShellWrapper.jl#L51)). The View menu names three ([WindowChrome.jl:80](../../../source/platform/shell/WindowChrome.jl#L80) to 98; link corrected by the check). There are also 13 getters of one line each, `get_session_x(; editor) = editor isa Editor ? get_session_document!(X, editor, X) : X()`.
- **Example:**
  ```julia
  # today: a new log needs an edit in the application, in the shell and in RECORDED_TOOLS
  logs = Any[get_session_message_log(; editor), get_session_gesture_log(; editor), get_session_fault_log(; editor)]
  make_window_tool_command("Message log", MessageLog; icon = :scroll_text, …)

  # proposal: the slice that owns the tool says so, once
  get_window_tool(::Type{MessageLog}) = (; section = :editor, wrapper = :message_log)   # label and icon come from
  # get_document_title and get_document_decoration; the explorer and the toolbar read the method table
  ```
- **Problem:** The application "names no domain", but it names every tool slice, and the shell does too. A package that brings a tool gets into the explorer by the trait and not onto the toolbar. The three lists can drift: the MCP log is in the explorer by a flag and on the toolbar by a host option.
- **Proposal:** A session document that is a tool of the window says it with one method: its section, and the wrapper that fills it or `nothing`. The explorer content and the toolbar read the method table, as the explorer already does for the kinds of the trait. The three tools that need the setup of the window (assistant, explorer, files) stay options of the `shell` wrapper.
- **What goes away:** The hand-written lists in `make_editor_explorer_content` and `_make_recorded_tool_commands`, `RECORDED_TOOLS`, and most of the dependencies of the application slice on the tool slices.
- **What stays:** A press reaches a tool and opens no second one. A button shows only when its wrapper fills its tool. The order of the toolbar, by a rank in the method.
- **Risk and open questions:** [shell.md](../../../documentation/package/platform/shell/shell.md) records the decision "The shell names the tools" and rejects "a button that each tool slice registers in its `__init__`", because a slice does not have the setup of the window. A trait method is not that rejected form, and it keeps the three setup tools in the shell, but the owner must say whether the decision still stands for the other ten.
- **Related plans:** `plan/done/the-toolbar-opens-the-tools.md` (done; holds the decision). Other areas: log, fault, statistics, gesturelog, assistant.
- **Check:** against-owner-decision. Value medium → low. The facts hold, with two corrections in the text above (five buttons from `RECORDED_TOOLS`; the View menu is in `WindowChrome.jl`). The decision is R3 of `plan/done/the-toolbar-opens-the-tools.md`, "The shell names the tools, and the host gives the assistant and the folder (decided by the owner)", of 2026-09-22, which [shell.md](../../../documentation/package/platform/shell/shell.md) repeats. R2 of the same plan rejected a button that each tool slice gives, with two reasons: the setup of the window, and "the order of the buttons is one choice for the whole toolbar. A slice can not know either one." The proposal keeps the three setup tools in the shell, which answers the first reason. Its "rank in the method" is the second reason again: each slice would say its place in the toolbar. Two notes for the owner:
  - C1 of `plan/pending/packages-compose-by-seams.md` (2026-09-30, eight days later) prefers a method of a seam to a table, and the explorer has such a seam (`is_session_explorer_entry_type`, with one method in `source/`, for `WorkflowList`). So the owner could decide R3 again for the ten tools with no setup; the report can not.
  - One part does not touch R3: `make_editor_explorer_content` of the application slice, which omnet-julia calls too, names the logs and the statistics a second time. It could read the table of the shell.

### AS-8 Settings and appearance are two stores of one shape, with two TOML encoders

- **Kind:** several-ways · **Value:** low · **Effort:** medium · **Confidence:** low
- **Principle:** 7 (one mechanism); the question of the owner "one store or more".
- **Today:** `Settings` holds groups found by type; a group is declared with `@settings`, which gives each value a label, a type, a default and its allowed values ([SettingsGroup.jl:169](../../../source/platform/settings/SettingsGroup.jl#L169)). The file is written from the descriptions in 15 lines ([SettingsFile.jl:29](../../../source/platform/settings/SettingsFile.jl#L29)). `Appearance` holds themes found by type, and two documents, `AppearanceScale` (seven factors) and `AppearanceColors` (five choices), which have the shape of a settings group and are written and read by hand, name by name ([Appearance.jl:352](../../../source/platform/style/Appearance.jl#L352), [:406](../../../source/platform/style/Appearance.jl#L406)). Each store has its own wrapper, its own managing projection, its own tab, and its own way to be found from the root (`find_editor_settings`, `find_editor_appearance`). They share `get_configuration_folder`.
- **Example:**
  ```julia
  # today
  data = Dict(String(f) => Float64(getproperty(appearance.scale, f)) for f in _APPEARANCE_FACTORS)   # by hand
  # proposal
  @settings struct ScaleSettings
      "Zoom: the size of the whole interface."
      zoom::Float64 = 1.0 in 0.25:0.05:4.0
  end
  ```
- **Problem:** A value of the scale has no declared range, no label for a generic view and no environment variable, which a setting gets from its declaration. Two wrappers and two managing projections do the same job (see AS-3).
- **Proposal:** The scale and the colour choices become settings groups. The themes stay in `Appearance`, because a theme value is a colour, a font or an inset and scales. One file helper reads and writes a TOML table from a described group.
- **What goes away:** The hand-written save and load of the twelve values, and possibly one of the two wrappers.
- **What stays:** The two tabs, the two files if the owner wants them, every theme.
- **Risk and open questions:** `plan/done/editor-settings.md` chose two tabs (D8) and TOML (D5), and said "the appearance plan owns it; this plan does not change it". Its section 4.9 planned one shared helper for the two files, which I did not find in the code. I did not read the appearance views, so the confidence is low.
- **Related plans:** `plan/done/editor-settings.md`, `plan/done/zoom-and-theme-controls.md` (both done). Other area: appearance and style.
- **Check:** confirmed. Value stays low. I opened `save_appearance!`, `load_appearance!`, the settings file and `AppearanceScale`. The seven factors and the five colour settings are written and read name by name ([Appearance.jl:325](../../../source/platform/style/Appearance.jl#L325), line 439), and a settings file is written from the descriptions of its groups. `AppearanceScale` is a `@document` of cells, the shape of a settings group. The style slice uses the settings slice already ([StyleModule.jl:17](../../../source/platform/style/StyleModule.jl#L17)), so a group inside `Appearance` needs no new dependency. Section 4.9 of `plan/done/editor-settings.md` planned one helper for the two files ("the folder, the read of a TOML table into a document, and the write"); only the folder is shared. The sentence "the appearance plan owns it" of that plan sets a scope and rejects nothing. To keep: a change of a scale still ends in a new print of the view (the appearance wrapper adds `InvalidateProjectionOperation`), the themes stay in `Appearance`, and the two tabs stay (D8). I did not read the appearance views either, so the effect on them is not checked.

### AS-9 Two small redundant parts

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 11 (design as from scratch).
- **Today:** (a) `make_application_content_projections` holds a row for `WorkspaceExplorer` and one for `WorkspaceDocument` ([Application.jl:195](../../../source/platform/application/Application.jl#L195), [:205](../../../source/platform/application/Application.jl#L205)) that are, word for word, the rows that the file-system slice registers with the natural renderer ([FileSystemToSyntax.jl:245](../../../source/platform/filesystem/FileSystemToSyntax.jl#L245), [:254](../../../source/platform/filesystem/FileSystemToSyntax.jl#L254)). The comment gives as the reason that the application "gives every file it opens a history"; the rows pass no history, and the history now comes from the evaluation of the open. (b) The layer `:document` of `EDITOR_WRAPPER_LAYERS` has no wrapper in `source/`; only four probes of a test use it ([BuildEditorTest.jl:53](../../../test/kernel/editor/BuildEditorTest.jl#L53) to 57; corrected by the check, the report said three).
- **Example:**
  ```julia
  # today, in Application.jl, a copy of the registered row
  WorkspaceDocument => ChainingProjection(RecursiveProjection(WorkspaceToFileSystem()), …)
  # proposal: delete both rows; the natural renderer has them
  ```
- **Problem:** A change of the registered row does not reach the application window.
- **Proposal:** Delete the two rows. Keep the `:document` layer only if AS-4 or the plan of the history gives it a member.
- **What goes away:** About 25 lines; perhaps one layer name.
- **What stays:** The Files pane draws as it does.
- **Risk and open questions:** A row in `extra` wins over a registered row, so the order of dispatch must be checked for `WorkspaceExplorer`, which must come before `WorkspaceDocument`; the registered rows have that order too.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (its table planned five `:document` wrappers; none exists now).
- **Check:** confirmed-with-corrections. Value stays low. Part (a) holds: the two rows of [Application.jl:195](../../../source/platform/application/Application.jl#L195) and line 205 are the registered rows word for word, they stand "in front of the defaults of `NaturalToGraphics`", and they pass no history. Delete them. Part (b) does not hold as "redundant": step 8 of `plan/pending/packages-compose-by-seams.md` (the gallery, open) gives the `:document` layer its members, and its point S1, option (a), applies that layer to each later document that `show_document!` shows. So the empty layer waits for a step of a pending plan: covered by that plan, and the layer stays. The count of the probes is corrected above (four).

## Covered by plans

- A history records only the edits that pass its own reader; an edit on a navigator page or in a duplicate tab is not recorded: `plan/pending/a-history-records-every-edit-of-its-document.md` (design to decide).
- One file document for each path, shared by a tab, a card, the explorer and a load: `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md`, step 6 (done on main).
- Pending edits of a file document, shown until Save: `plan/pending/pending-edits-and-file-changes.md` (deferred by the owner).
- A history view of the versions of an object: `plan/pending/object-versioning.md`, step 5 (open).
- The process-global stores of the message log and of the task feed: named in `plan/pending/kernel-audit/21-feed.md`.
- The four copies of the walk through fields, cells, vectors and tuples in `FileCut.jl` and `FileSplice.jl`: [serialization.md](../../../documentation/package/platform/serialization/serialization.md) names it; no plan found, and it is file-level, so I did not make it a finding.

## Examined and sound

- Undo and versioning as two models: an `UndoBuffer` is a log of inverse operations, a `VersionedObject` holds versions as values in the tree. [versioning.md](../../../documentation/package/platform/versioning/versioning.md) and the object-versioning plan give the reason, and both are wrapper documents of the same form.
- The reader order of the two (undo reads its keys last, versioning first): on purpose, so the innermost history takes Ctrl+Z; stated at the head of `UndoBufferToAny.jl`.
- Focus as the selection of the pane tree, with no focus field: one source of truth; the surgery returns generic operations, so a pane tree nests.
- The wrapper seam of `build_editor`: one mechanism, a keyword per wrapper, the method table as the list, and numbered layers. The order inside `:container` has a written reason for each number.
- Session documents by type on the editor (`get_session_document!`): the general home of the state of a session. `Settings` and `Appearance` sit in wrapper documents around the root instead, because their managing projections must be on the path of the reader; that reason holds.
- The file against the disk: one `FileDiskState` in each file document, a watcher that reads no text, a background cell that a view demands, and the hash of the text as the test. It follows principle 9 fully, except the eager maker of AS-4.
- `OpenFileOperation` and `OpenPageOperation` declared in the widget slice and evaluated in the file-system and navigator slices: the slices below can answer them without a dependency upward.
- An explorer section links documents and wraps none, so a document shows the same in the explorer and in a tab (owner, 2026-10-17).
- The `.pred` format as the one generic text form of a document, with a marker interpreter that calls no `eval`.
- The binary `.pdoc` snapshot beside the text forms: a different job (exact, one version), and small (128 lines).
- The process-global `_SESSION` of the display slice: it is the one editor of the Julia display of a process, by its meaning.

## Check of the report

A second agent checked each finding against the code at commit 3a9b4fae4, the design documents and the plans. It read the code and ran nothing. A wrong fact, count or link is corrected where it stands, with the words "corrected by the check". Each finding has a list item **Check** with what was opened and what was found.

| Id | Verdict | Value after the check | In one sentence |
| --- | --- | --- | --- |
| AS-1 | confirmed | high | The facts hold; the map of a path through the field of a view is a third repeated part; the change belongs with the deferred plan of what a holder holds (open question 10 of the tab plan). |
| AS-2 | confirmed-with-corrections | medium (was high) | The two tables are real; the one row of a format must be methods on the file type and no registry call (C1 of `packages-compose-by-seams.md`), in the later plan that C7 announces; no `@file_document` macro. |
| AS-3 | confirmed-with-corrections | high | 15 `inner` fields, not 12, in two shapes; the reader of versioning has no branch for a routed intent; the shared projection takes its child from the recursion, not as an argument. |
| AS-4 | weakened | low (was medium) | Three makers are real, but "always unread" loses the read document after `open_file!`, the caret of a new tab and a link to a section; the mechanism for what waits for a read is in a later plan by the owner (open question 13). |
| AS-5 | confirmed-with-corrections | medium | Four openers and three searches, not five; a seventh walker is in the kernel (`get_edited_document`), so the one walker belongs beside it and not in the pane slice. |
| AS-6 | weakened | low (was medium) | Only the explorer content is connected to a start; the wrapper that gives back the tabs is a new feature; what holds is the repair of `load_user_interface`, which gives a tab a bare file with no history. |
| AS-7 | against-owner-decision | low (was medium) | R3 of `plan/done/the-toolbar-opens-the-tools.md`: the shell names the tools, and a slice can not know the order of the buttons. |
| AS-8 | confirmed | low | The facts hold; the style slice uses the settings slice already; the shared file helper of section 4.9 of the settings plan was not made. |
| AS-9 | confirmed-with-corrections | low | Part (a) holds: delete the two copied rows. Part (b) is covered by step 8 of `packages-compose-by-seams.md`, which gives the `:document` layer its members. |

What the check saw and the report does not have as a finding:

- Two traits name a layer around a document: `get_wrapped_document` and `get_edited_field` ([DocumentDefaults.jl:172](../../../source/kernel/document/DocumentDefaults.jl#L172), line 175). The settings, appearance, shell and tooltip wrappers answer only the first; a file view, a navigator and a scroll pane answer only the second; a history and a clipboard slice answer both. So `find_pane_tab_layer` tries both, and the other walkers of AS-5 see one kind of layer only.
- The reader of `VersioningToAnyProjection` ([VersioningToAny.jl:204](../../../source/platform/versioning/VersioningToAny.jl#L204)) has no branch for an intent with a route, which every other content wrapper has. It belongs to AS-3, and it is a gap of today, not only a risk of drift. The check read the code and did not run it.
- The rule of a path through the field of a view is written three times in the holder projections (see the check of AS-1).
