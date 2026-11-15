# Architecture review: Input — events, gestures, bindings, popups, drag, hover, the frame loop

Commit 3a9b4fae4. Reviewer area key: input-interaction.

## Scope

**Paths.** `source/kernel/{event,device,gesture,binding,editor,playback,clock,fault,performance}`,
`source/platform/{gesturehelp,gesturelog,gesturetracking,dragging,dragtracking,tooltip,fault,focus}`,
the popup and menu files of the widget, shell, pane, explorer and navigator slices, and the screen
slice, because every popup ends there.

**Read in full, about 9 700 source lines:**

- kernel: the binding layer (4 files, 567 lines); the editor layer except `SafeMode.jl`,
  `BackendChoice.jl`, `DocumentEdits.jl` and the second half of `BackgroundCells.jl` (about 2 450
  lines); `intent/Intent.jl`; `gesture/ClickRecognition.jl`; the fault layer except
  `FaultRecord.jl` and the first half of `FaultStore.jl`; `playback/Playback.jl`;
  `feed/FeedInterface.jl`; `projection/ProjectionGestureBindings.jl`.
- platform: the tooltip slice (all 7 files); `widget/ContextMenuWindow.jl`,
  `ContextMenuOperation.jl`, `ShellPlacement.jl`; `screen/WindowManaging.jl`, `WindowLayers.jl`,
  `WindowScene.jl`, `EscapeQuitting.jl`; `gesturetracking/GestureTracking.jl`,
  `PointerSettings.jl`; `dragtracking/DragTracking.jl`; `dragging/Dragging.jl`;
  `gesturehelp/GestureHelpDecorator.jl`, `CommandPaletteDecorator.jl`, `GestureMap.jl`,
  `PartCommands.jl`; `gesturelog/GestureLogRecording.jl`; `focus/FocusCycling.jl`,
  `SelectionWalking.jl`; `shell/FileDialog.jl`; `pane/PaneTabMenu.jl`;
  `explorer/ExplorerRowMenu.jl`; `navigator/NavigatorGestures.jl`; the four feeds of the message
  log, the MCP log, the background work and the frame statistics.

**Sampled:** `widget/WidgetToGraphics.jl` (15 822 lines; about 450 lines read: the readers of the
button, the dialog, the menu, the menu item, the select, the option, the shell and the split
pane), `widget/WidgetDocument.jl`, `widget/WidgetChoiceList.jl`, `screen/ScreenToScreen.jl` (the
readers), `shell/WindowChrome.jl`, `pane/PaneGestures.jl`, `pane/PaneToWidget.jl` (the drag of a
tab), `domain/pivot/PivotTableToWidget.jl` and `domain/graph/GraphLayoutToGraphics.jl` (their
drags), `kernel/projection/ProjectionDefaults.jl` (the default reader), the two overlay files,
the log stores and the log documents. The counts in the tables come from `grep` over
`source/platform`, `source/domain` and `source/adapter`, with comment lines left out.

**Not read:** `gesture/GesturePattern.jl`, the performance layer, the device layer and the event
layer (sealed, and the kernel audit covers them), the backends.

**Documents read:** `concepts.md`, `architecture-decisions.md`, the index and the projection,
operation and editor sections of `architecture-invariants.md`, the package documents of the
gesture layer, the mouse target, the fault layer, dragging, drag tracking, gesture help, gesture
log, gesture tracking, the popup window and the context menu, the seven guides of the area, the
heads of the ten plans named in the task, and the summary of the kernel audit.

## State

The kernel half of this area is sound. One loop runs the frames. One vocabulary of events and
gestures reaches every reader. A recognition is a pure rule, and its state is a document field.
One contract serves the ten feeds. One store and one record function serve every fault. One
protocol serves every drag, and one path chain tells every view which part is under the pointer.

The weakness is one level up, in the platform, and it has two parts.

First, the project has one good answer to "what does a key or a click mean": a table of rules
that is data, so the same table fires a key and lists it. The domains use it. The widget toolkit,
the menus and the wrappers of a window mostly do not. So a command can have three declarations
(a key rule, a menu item, a window command) that a text joins, and the help window, the command
palette and the assistant see only the part that is in a table.

Second, each feature at the level of the screen (the tooltip window, the context menu window,
the drag tracker, the help, the palette, the cycle of Tab, the quit on Escape) is a wrapper
projection that is written by hand: its own IO map type, its own code to take one operation out
of an answer, its own code to join operations, its own test for Escape. Popups show the cost:
four operations open a popup window, and keys, layers and the lift of an edit work only for the
popups that one of the wrappers opened.

## Inventory

### A. The ways that code reacts to a key or a click

`F1` is the help window (`GestureHelpDecoratorProjection`). The palette is the list that
Ctrl+Shift+P opens. `describe_commands(part)` is the verb by which the assistant lists the
commands of a part. All three read the rules by one question, the payload `CollectIntents`,
which only a table answers.

| # | Way | Count | Where | F1 and palette list it | `describe_commands` lists it |
| --- | --- | ---: | --- | --- | --- |
| 1 | `@gestures T begin … end`, the table of a document type | 44 | 30 folders; widget slice: 1 (`FindBarView`) | yes | yes |
| 2 | A table written without the macro, `get_document_gesture_bindings_own(::Type{T}) = GestureBinding[…]` | 21 | [WidgetDocument.jl:4173](../../../source/platform/widget/WidgetDocument.jl#L4173), [TooltipWindow.jl:105](../../../source/platform/tooltip/TooltipWindow.jl#L105) | yes | yes |
| 3 | A table of one instance, the field `gestures` of 9 widget types | 9 types | [WidgetDocument.jl:627](../../../source/platform/widget/WidgetDocument.jl#L627) | yes | yes |
| 4 | A table of a projection, `get_projection_gesture_bindings` | 10 | undo, clipboard, versioning, focusing, insertion | yes | no |
| 5 | `@gesture_case`, a compiled match in a reader | 25 | [WidgetToGraphics.jl:3092](../../../source/platform/widget/WidgetToGraphics.jl#L3092) (20 of the 25 are in this file) | no | no |
| 6 | A test by hand in a reader: `evt.key === :down`, `event.char == '\t'` | 84 lines with a key test in 18 files, 25 with a character test | [WidgetToGraphics.jl:4200](../../../source/platform/widget/WidgetToGraphics.jl#L4200), [WidgetTableParts.jl:1875](../../../source/platform/widget/WidgetTableParts.jl#L1875) | no | no |
| 7 | A pattern constant that a wrapper tests | 2 | [GestureHelpDecorator.jl:30](../../../source/platform/gesturehelp/GestureHelpDecorator.jl#L30), [CommandPaletteDecorator.jl:27](../../../source/platform/gesturehelp/CommandPaletteDecorator.jl#L27) | no | no |
| 8 | `Action.shortcut`, a key on a command of the menu bar | 8 in the window chrome | [WidgetToGraphics.jl:4767](../../../source/platform/widget/WidgetToGraphics.jl#L4767) | no | no |
| 9 | The loop itself: the quit of a window, Escape in the safe mode | 2 | [ReadEvaluatePrint.jl:40](../../../source/kernel/editor/ReadEvaluatePrint.jl#L40) | no | no |
| 10 | A held frame of the backend: Escape, the stop control, a close | 1 | [HeldFrames.jl:162](../../../source/kernel/editor/HeldFrames.jl#L162) | no | no |

The gesture log (`GestureLogRecordingProjection`) records each operation that passes its reader,
whatever way made it. It sits outermost inside the content of a window
([GestureLogRecording.jl:168](../../../source/platform/gesturelog/GestureLogRecording.jl#L168)). So it
sees ways 1 to 8 inside a window. It does not see what a reader outside it answers: the window
manager, the tooltip window, the context menu window, the drag tracker, the appearance keys and
the quit on Escape. Of way 8 it records only that an action ran.

### B. The readers that a key passes, from the outside in (a window made by `build_editor`)

| Reader | What it does with a key | How it tests |
| --- | --- | --- |
| `EscapeQuittingProjection` (optional) | Escape that nothing took quits | by hand, [EscapeQuitting.jl:45](../../../source/platform/screen/EscapeQuitting.jl#L45) |
| `AppearanceManagingProjection`, `SettingsManagingProjection` | zoom keys, setting writes | table of their document |
| `GestureTrackingProjection` | runs the recognitions | no meaning |
| `DragTrackingProjection` | Escape cancels the drag | by hand, [DragTracking.jl:108](../../../source/platform/dragtracking/DragTracking.jl#L108) |
| `ContextMenuWindowProjection` | F2, Shift+F2; gives a key to the open menu | table, then by hand |
| `TooltipWindowProjection` | F2, Shift+F2; Escape closes | table, then by hand, [TooltipWindow.jl:149](../../../source/platform/tooltip/TooltipWindow.jl#L149) |
| `WindowManagingProjection` | Escape closes each popup | by hand, [WindowManaging.jl:388](../../../source/platform/screen/WindowManaging.jl#L388) |
| `GestureLogRecordingProjection` | records | — |
| `CommandPaletteDecoratorProjection`, `GestureHelpDecoratorProjection` | Ctrl+Shift+P, F1 | pattern constant |
| the clipboard projection | copy, cut, paste | table of the projection |
| `SelectionWalkingProjection` | Alt and an arrow | by hand, [SelectionWalking.jl:64](../../../source/platform/focus/SelectionWalking.jl#L64) |
| `FocusCyclingProjection` | Tab at the ends | by hand, [FocusCycling.jl:42](../../../source/platform/focus/FocusCycling.jl#L42) |
| the reader of `WidgetShell` | fires `Action.shortcut`, then gives the key to each band and the content | walk of the menu bar at each key |
| the undo buffer, the pane tree, the content | Ctrl+Z, the tab keys, the domain | tables |

Escape alone is tested by hand in ten places (corrected by the check; the report said seven):
the four wrappers above (`EscapeQuittingProjection`, `DragTrackingProjection`,
`TooltipWindowProjection`, `WindowManagingProjection`), the reader of a dialog
([WidgetToGraphics.jl:3678](../../../source/platform/widget/WidgetToGraphics.jl#L3678)), the open cell of
a table ([WidgetToGraphics.jl:14245](../../../source/platform/widget/WidgetToGraphics.jl#L14245)), the
explorer ([ExplorerToWidget.jl:298](../../../source/platform/explorer/ExplorerToWidget.jl#L298)), the
navigator ([NavigatorToWidget.jl:332](../../../source/platform/navigator/NavigatorToWidget.jl#L332)), the
turn of the assistant ([AssistantTurn.jl:1390](../../../source/platform/assistant/AssistantTurn.jl#L1390))
and the loop ([ReadEvaluatePrint.jl:122](../../../source/kernel/editor/ReadEvaluatePrint.jl#L122)). The
test `_is_bare_escape` itself is written twice, and a third time as `_is_plain_escape`.

### C. Popup windows

| Popup | The operation that asks for it | What turns it into `OpenWindowOperation` | Keys reach its content | Shows more layers (F2) | An item's edit is lifted through the readers | How it knows that it is open |
| --- | --- | --- | --- | --- | --- | --- |
| Menu of the menu bar, a submenu | `OpenPopupOperation`, [WidgetToGraphics.jl:3897](../../../source/platform/widget/WidgetToGraphics.jl#L3897) | `ScreenToScreen`, [ScreenToScreen.jl:462](../../../source/platform/screen/ScreenToScreen.jl#L462) | no | no | no | not kept |
| List of a `WidgetSelect` | `OpenPopupOperation`, [WidgetToGraphics.jl:11758](../../../source/platform/widget/WidgetToGraphics.jl#L11758) | the same | no | no | no: each option holds a final operation | not kept |
| Context menu, menu of a "⋯" button | `OpenContextMenuOperation`, [ContextMenuOperation.jl:30](../../../source/platform/widget/ContextMenuOperation.jl#L30) | `ContextMenuWindowProjection`, [ContextMenuWindow.jl:282](../../../source/platform/widget/ContextMenuWindow.jl#L282) | yes, [ContextMenuWindow.jl:168](../../../source/platform/widget/ContextMenuWindow.jl#L168) | yes | yes | field `shown`, checked against the screen, [ContextMenuWindow.jl:239](../../../source/platform/widget/ContextMenuWindow.jl#L239) |
| Command palette, "Go to file", the kinds of an insertion | `make_choice_list_operation`, then the row above | the same | yes, with a typed text | yes | yes | the same |
| Tooltip | `OpenTooltipOperation`, [TooltipOperation.jl:24](../../../source/platform/tooltip/TooltipOperation.jl#L24) | `TooltipWindowProjection`, [TooltipWindow.jl:189](../../../source/platform/tooltip/TooltipWindow.jl#L189) | F2 and Escape only | yes | — | field `shown` |
| Tooltip of a `TooltipSource` (examples only) | `OpenWindowOperation` from `TooltipDecoratorProjection` | — | no | no | — | a `Dict` on the projection, written in the reader, [TooltipDecorator.jl:113](../../../source/platform/tooltip/TooltipDecorator.jl#L113) |
| Dialog of a button | `OpenWindowOperation(modal = true)`, [WidgetToGraphics.jl:3119](../../../source/platform/widget/WidgetToGraphics.jl#L3119) | — | own window | no | no | not kept |
| File dialog, "Filter by values" (2 copies) | `evaluate_operation(editor, OpenWindowOperation(…))` from a verb, [FileDialog.jl:93](../../../source/platform/shell/FileDialog.jl#L93) | — | own window | no | no: the button holds a closure | not kept |
| Help window (F1) | `OpenWindowOperation`, [GestureHelpDecorator.jl:149](../../../source/platform/gesturehelp/GestureHelpDecorator.jl#L149) | — | own window | no | — | a flag on the projection, written in the reader, [GestureHelpDecorator.jl:148](../../../source/platform/gesturehelp/GestureHelpDecorator.jl#L148) |

Closing has three homes: `auto_dismiss` in `WindowManagingProjection`
([WindowManaging.jl:96](../../../source/platform/screen/WindowManaging.jl#L96)), the rule of the tooltip
([TooltipWindow.jl:234](../../../source/platform/tooltip/TooltipWindow.jl#L234)), and the reader of the
dialog. `OpenWindowOperation` is applied in two places: in the reader of
`WindowManagingProjection`, which writes the screen document
([WindowManaging.jl:238](../../../source/platform/screen/WindowManaging.jl#L238)), and in
`evaluate_operation` ([WindowManaging.jl:355](../../../source/platform/screen/WindowManaging.jl#L355)).
The find bar is no popup: it is a widget in the page with a table of its own.

### D. Drags

Every drag uses one protocol: the part answers `StartDragOperation`, `DragTrackingProjection`
keeps the path of the part, and the part gets `DragMove`, `DragEnd` and `DragCancel` by that
path. 14 places start a drag, and all 14 use it.

| Drag | Starts | The small move before the start | State field |
| --- | --- | --- | --- |
| slider, scroll bar thumb, split divider, column edge, text range (2 readers), chart, sequence chart | at the press | — | a view-state field of the part |
| tab of a pane | after a move | `hypot ≥ 5`, [PaneToWidget.jl:868](../../../source/platform/pane/PaneToWidget.jl#L868) | `drag`, with `origin` and `started` |
| list element (`DraggingProjection`, used by examples only) | after a move | `hypot ≥ state.threshold` (5), [Dragging.jl:166](../../../source/platform/dragging/Dragging.jl#L166) | `press`, with `x`, `y`, `started` |
| item of a pivot zone | after a move | `hypot ≥ 5`, [PivotTableToWidget.jl:495](../../../source/domain/pivot/PivotTableToWidget.jl#L495) | `drag`, with `x`, `y`, `started` |
| vertex of a graph | after a move | each axis `≥ 5`, [GraphLayoutToGraphics.jl:1070](../../../source/domain/graph/GraphLayoutToGraphics.jl#L1070) | `drag`, with `origin`, `started` |
| (a click, for comparison) | — | each axis `< click_max_displacement`, a setting, [ClickRecognition.jl:113](../../../source/kernel/gesture/ClickRecognition.jl#L113) | state of the recognition |

### E. Hover

One mechanism: the field `mouse_target` of each document holds the rest of the path to the part
under the pointer, as `selection` does. Widgets, rows, brackets, drop targets and row menus read
it (46 call sites of `get_mouse_target` outside the kernel). Two parts use their own means:

- the divider of a split pane keeps `splitter_under_pointer`, written by its own operation type
  ([WidgetToGraphics.jl:5719](../../../source/platform/widget/WidgetToGraphics.jl#L5719)), because a
  divider is no document and no step names it;
- the tooltip window maps the point backward once more to know whether the pointer left the part
  ([TooltipWindow.jl:265](../../../source/platform/tooltip/TooltipWindow.jl#L265)), though the answer to
  the same move already holds that path.

### F. Loops and stores

| Loop | Runs | State |
| --- | --- | --- |
| `_run_editor_loop!`, [EditorLoop.jl:238](../../../source/kernel/editor/EditorLoop.jl#L238) | wait, clock, feeds, report, read and evaluate up to 32 times, print | the one loop |
| held frames, [HeldFrames.jl:162](../../../source/kernel/editor/HeldFrames.jl#L162) | the backend keeps the window alive while a code unit owns the documents | by design (PAR-LOOP-RUNS-NO-USER-CODE) |
| `play_live!`, [Playback.jl:85](../../../source/kernel/playback/Playback.jl#L85) | a second loop with no feeds, no barriers, no clock | kernel audit L23-1 |

| Store | Holds | Read by | Shape |
| --- | --- | --- | --- |
| `Editor.inbox`, `owner_posts` | operations from other tasks | `InboxFeed` | two channels |
| `Editor.timers` | name → time | the read stage | `Dict` |
| `FaultStore` | records by key, with a count | `drain_faults!`, which pushes to targets | keyed, 64 keys |
| `FrameMeasurementStore` | the numbers of the last frames | `FrameStatisticsFeed`, by a frame count | ring |
| `BackgroundWorkStore` | records of works | `BackgroundWorkFeed`, by a change count | vector, 100 |
| `MessageLogStore` | lines | `MessageLogFeed`, by a cursor | numbered, lock, wakes, 1000 |
| `McpLogStore` | calls | `McpLogFeed`, by a cursor | the same fields as the row above |
| `Editor.session_documents` | one document for each type | the views | `IdDict` |

### G. Fault barriers

| Work | Catch | Answer |
| --- | --- | --- |
| a stage of the frame, a feed drain, a deadline | `run_fault_barrier!` through `_run_barrier` (14 call sites, all in the editor layer) | a fixed fallback |
| an operation | `_evaluate_operation_guarded!` | the inverse, a new print, a repair of the selection |
| a part of a print | `FaultCatchingProjection`, then `record_fault!` | a mark in the output, a retry after the next operation |
| one element of a paint | `record_paint_fault!` | the element is skipped |
| a tool call, a turn, an MCP call | a catch in place, then `record_fault!` (12 call sites) | the text of the error |
| the work of a background cell | the exception is the value of the cell | the read throws into the barrier of the part |

One store, one record function, one policy. See "Examined and sound".

## Findings

### II-1 A command is declared up to three times, and a text joins the copies

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 3 (one way to edit; a person, the assistant and a test make the same
  operations), 7 (generic before special), 10 (the surface of the assistant comes by reflection).
- **Today:** A rule of a table is a function of the document and the event
  ([Gestures.jl:119](../../../source/kernel/binding/Gestures.jl#L119)), and its precondition is a function
  of the document and its selection
  ([GestureBinding.jl:118](../../../source/kernel/binding/GestureBinding.jl#L118)). So a rule gets no
  place: a key rule reads the selection of its document in its body, and a rule for a pointer
  gesture reads the mouse target by hand
  ([ExplorerRowMenu.jl:15](../../../source/platform/explorer/ExplorerRowMenu.jl#L15)). A context menu acts
  on the part under the pointer and must not move the selection. So each slice that has a menu
  writes its commands a second time, for a place that it passes by hand:
  - The pane tree declares "Close the focused tab" with Ctrl+W in its table
    ([PaneGestures.jl:176](../../../source/platform/pane/PaneGestures.jl#L176)). The menu of a tab builds
    the same operation again and finds the key by the text of the description,
    `find_bound_keys(PaneTree, "Close the focused tab")`
    ([PaneTabMenu.jl:114](../../../source/platform/pane/PaneTabMenu.jl#L114),
    [PaneTabMenu.jl:88](../../../source/platform/pane/PaneTabMenu.jl#L88)). 6 of the 9 items of that menu
    mirror a rule of the table in this way.
  - The explorer declares "Remove from explorer", "Rename", "Move the entry earlier", "Move the
    entry later" and "New section" in its table
    ([ExplorerEntryEdits.jl:195](../../../source/platform/explorer/ExplorerEntryEdits.jl#L195)), and again
    in `_collect_row_commands`, which takes the steps of a row
    ([ExplorerRowMenu.jl:40](../../../source/platform/explorer/ExplorerRowMenu.jl#L40)).
  - The window chrome declares a third copy as an `Action`: a label, a key (`shortcut`) and a
    callback that takes the editor. "New tab" (Ctrl+T), "Close tab" (Ctrl+W), "Split vertically",
    "Split horizontally" and "Appearance" (Ctrl+,) exist both there
    ([WindowChrome.jl:44](../../../source/platform/shell/WindowChrome.jl#L44)) and in a table. Each
    callback searches the pane tree, builds the operation, lifts it and posts it
    ([WindowChrome.jl:386](../../../source/platform/shell/WindowChrome.jl#L386)). The reader of the shell
    walks the menu bar at each key and fires the action before the content reads the key
    ([WidgetToGraphics.jl:4766](../../../source/platform/widget/WidgetToGraphics.jl#L4766)).
  - For the assistant, a third seam exists: `collect_part_commands(holder, steps)` gives the
    commands of a part that is not the selection. Its default answers none
    ([PartCommands.jl:25](../../../source/platform/gesturehelp/PartCommands.jl#L25)), and only the explorer
    has a method.
  - `find_bound_keys` has 9 call sites outside its file. An `Action` is built directly in about
    20 places, about half of them with a callback, and `make_window_command` makes 15 more
    items, each with a callback (counted again by the check; the report said 24 and 18).
- **Example:**

  ```julia
  # Today: three declarations of one command.
  @gestures PaneTree begin                                         # the key
      KeyDown(:w; ctrl) => "Close the focused tab" => _close_tab(doc)
  end
  item("Close", make_pane_close_tab_operation(tree, group, index),  # the tab menu
       "Close the focused tab")       # the key is found by this text
  make_window_command("Close tab", _close_tab!;                     # the File menu
                      shortcut = Shortcut(:w; ctrl = true))

  # Proposed: one rule that takes the place it acts at.
  @gestures PaneTree begin
      KeyDown(:w; ctrl) => "Close the tab" => make_pane_close_tab_operation(doc, place)
      nothing => "Close the other tabs" => make_pane_close_other_tabs_operation(doc, place)
  end
  make_command_menu(tree, tab_place; commands = ["Duplicate the tab", "Close the tab", …])
  WidgetMenuItem(; command = "Close the tab")    # label, key and enabled state come from the row
  ```

- **Problem:** The three copies do not combine. A change of a description makes
  `find_bound_keys` answer no key, with no error. Ctrl+, has three meanings in three systems: the
  shell action "Appearance", the rule "Show the appearance"
  ([AppearanceDocument.jl:56](../../../source/platform/appearance/AppearanceDocument.jl#L56)) and "Focus
  out" of the focusing projection
  ([Focusing.jl:70](../../../source/platform/projection/generic/Focusing.jl#L70)); no listing shows the
  clash. Ctrl+O, Ctrl+P and Ctrl+Q exist only as actions, so F1 does not list them. In a window
  with the chrome, Ctrl+T, Ctrl+W and Ctrl+\ run the callback of the shell and not the rule of
  the pane tree that F1 lists, because the shell reads the key first. A callback that applies
  its operation itself is no operation of the reader chain, so no history records it
  (context-menu.md says so); the callbacks `_open_tab!`, `_close_tab!` and `_split!` do lift
  their operation with `read_rooted_operation`, so this holds for the other callbacks only
  (corrected by the check). The gesture log records only that an action ran. The shell document
  names the result as a limit: "The menu bar has no Save, Reload or clipboard items. The keys
  work, but no verb reaches the owner of each command through the editor yet"
  ([shell.md:163](../../../documentation/package/platform/shell/shell.md#L163)). The next slice with a row
  menu must write its commands twice and add a method of `collect_part_commands`.
- **Proposal:** The table of a document type is the one declaration of a command. A rule gets
  the place that it acts at, a path in its document: the selection for a key, the part under the
  pointer for a pointer gesture and for a menu, the given part for `run_command!`. A menu is a
  list of command names, and one helper builds it from the rows at a place: the label is the
  description, the key is the pattern of the same row, and an item is grey when the rule builds no
  operation. An item of the menu bar names a command too; the shell asks the content with
  `CollectIntents`, as the palette does, and runs the row. A command of the whole window, such
  as "Open file…", is a row of the table of `WidgetShell`.
- **What goes away:** the second and third declaration of each command (the bodies of
  `_make_tab_menu` and `_collect_row_commands`, the callbacks `_open_tab!`, `_close_tab!` and
  `_split!`, about 150 lines); `Action.shortcut`, `Shortcut`, `_collect_command_actions!`,
  `_shell_shortcut_actions` and `matches_action_shortcut` (about 45 lines); the seam
  `collect_part_commands` and its one method; the lookup of a key by a text.
- **What stays:** every key, every menu, the palette and `run_command!`. A right click still
  moves no selection, because the place is the mouse target. `Action` with a callback stays for a
  button that the assistant or a host makes from a closure.
- **Risk and open questions:** The `@gestures` body binds `doc` today, and many rules call
  helpers that read `get_selection(doc)`. A rule can keep that default, so only the rules that a
  menu uses need the place. `applicable` changes its second argument from the selection to the
  place. The binding layer is not sealed. The owner should confirm that a command of the window
  is a row of the shell.
- **Related plans:** `plan/done/reified-gesture-bindings.md` (done; the table),
  `plan/done/a-tab-has-a-menu-and-shows-its-x-under-the-pointer.md` (done; the tab menu),
  `plan/done/the-assistant-works-in-the-explorer.md` (done; `collect_part_commands`),
  `plan/pending/key-chords-from-bindings.md` (deferred; needs the same single table).
- **Check:** confirmed-with-corrections. Opened every cited file. The three declarations are
  real: the table of the pane tree, `_make_tab_menu` (9 items, 6 of them joined to a rule by the
  text of its description) and `make_window_command` with `Shortcut`; the explorer names five
  commands in its table and again in `_collect_row_commands`; Ctrl+, has three meanings; Ctrl+O,
  Ctrl+P and Ctrl+Q are in no table. No plan covers it, and no document gives a reason for the
  copies (shell.md:83 calls the menu "a second way to one implementation", which is the
  operation maker, not the declaration). Corrected: 8 shortcuts, not 9; the count of `Action`;
  the sentence on the history; the quote of shell.md. The proposal must answer four things
  before it keeps every feature. (1) `_collect_row_commands` has the keyword `selects`: the
  same command moves the selection and the page for a person and not for the assistant, and
  "Rename" and "Add…" exist only for the person. One row with a place does not say who runs it.
  (2) The owner accepted `collect_part_commands` as a generic mechanism on 2026-10-21 (decision
  1 of the-assistant-works-in-the-explorer.md); the proposal removes it, so the owner must take
  that back. (3) "The label is the description" loses the short labels ("Close" for "Close the
  focused tab"), the label that follows the state ("Maximize group" or "Restore layout") and
  the tooltip text of each item of the row menu; a row needs a label and a note of its own.
  (4) A command of the menu bar works today wherever the selection is, because the callback
  searches the pane tree; a row that `CollectIntents` finds along the path of the selection is
  found only while the selection passes the pane tree, so not with the caret in a band of the
  shell. The menus whose items come from data (the pivot, the data frame) are no commands and
  stay as they are, so the gain is the two command menus, the menu bar and the nine key
  lookups by text. Value stays high.

### II-2 Most keys of the widgets and of the wrappers are outside the table that F1, the palette and the assistant read

- **Kind:** partial-feature · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 7 (a missing case gets its row in the generic mechanism), 10, and
  PAR-GEOMETRY-FREE-IN-DOCUMENT (a gesture that reads only the structure and the selection
  belongs to the document, not to the projection).
- **Today:** The kernel gives a document type a table of rules, and its default reader sends a
  key to that table ([ProjectionDefaults.jl:145](../../../source/kernel/projection/ProjectionDefaults.jl#L145)).
  44 `@gestures` tables exist, and one of them is in the widget slice. The widget readers give
  their keys a meaning by hand: the keys of a menu
  ([WidgetToGraphics.jl:4193](../../../source/platform/widget/WidgetToGraphics.jl#L4193)), the arrows, Space
  and F2 of a table ([WidgetTableParts.jl:1860](../../../source/platform/widget/WidgetTableParts.jl#L1860)),
  the keys of a tree ([WidgetToGraphics.jl:15557](../../../source/platform/widget/WidgetToGraphics.jl#L15557)),
  Return and Space of a button in a `@gesture_case`
  ([WidgetToGraphics.jl:3092](../../../source/platform/widget/WidgetToGraphics.jl#L3092)). Outside the
  kernel there are 25 `@gesture_case` blocks, 84 lines that test `.key` and 25 that test `.char`.
  The wrappers of table B test Tab, Alt and an arrow, Escape, F1 and Ctrl+Shift+P by hand. None of
  these readers answers `CollectIntents`.
- **Example:**

  ```julia
  # Today, in the reader of the menu (WidgetToGraphics.jl:4200):
  evt.key === :return && return … _make_menu_item_choice(…)
  next = evt.key === :down ? … : evt.key === :up ? … : evt.key === :home ? 1 : …

  # Proposed, in the table of the widget:
  @gestures WidgetMenu begin
      KeyDown(:down)  => "Light the next item"   => light_menu_item(doc, +1)
      KeyDown(:up)    => "Light the item before" => light_menu_item(doc, -1)
      KeyPress('\n')  => "Choose the lit item"   => choose_menu_item(doc)
  end
  ```

- **Problem:** The guides promise what the code does not hold: "F1 is the true list"
  ([keyboard-and-mouse-guide.md:9](../../../documentation/guide/keyboard-and-mouse-guide.md#L9)) and
  "every key and every click that works where you are is on that list"
  ([gestures-guide.md:36](../../../documentation/guide/gestures-guide.md#L36)). The arrows, Space and F2
  of a `WidgetTable` are in no table, so no listing can show them. `describe_commands` of a
  widget lists its tooltip and its menu and none of its keys, so the assistant can not choose the
  lit item of a menu or move in a table by a command. Rules written by hand drift: the menu reads Return as
  `KeyDown(:return)`, the choice list reads it as `KeyPress('\n')`
  ([WidgetChoiceList.jl:276](../../../source/platform/widget/WidgetChoiceList.jl#L276)), and the gesture
  document says that a rule names `KeyPress('\n')`, never the key down
  ([gesture.md:43](../../../documentation/package/kernel/gesture.md#L43)). The plan for key chords asks
  how the editor finds the bindings of its projection; rules outside a table have no answer.
- **Proposal:** One rule for every reader: a reader finds the part (a hit test, a route by the
  selection), and a table gives the meaning. Each widget type declares its keys and its presses
  with `@gestures`, and its reader calls `read_bound_gesture`, which 13 widget readers already
  call for the table of an instance. The keys of the wrappers become rows too (II-4).
  `@gesture_case` stays only where a reader routes by the type of an event and gives no meaning.
- **What goes away:** the key tests by hand (about 110 lines with a test, and the functions
  around them), the pattern constants of the help and the palette, and the difference between a
  key that F1 knows and a key that it does not.
- **What stays:** every key and every press of every widget. A rule that needs geometry, such
  as Page Down by the rows that show, reads it from fields of the widget document (`top`,
  `shown_rows`), as the choice list does now.
- **Risk and open questions:** `WidgetToGraphics.jl` has 15 822 lines and 59 `read_intent`
  methods (69 in the whole widget slice; corrected by the check), so the
  work is large; it can go one widget type at a time, and each step makes F1 more complete. Each
  key lookup builds the tables of the supertype chain again (kernel audit L15-3), so more rows
  need that fix first. A press on a control and a press that selects (Alt+click) are told apart
  in `read_child_event`; the rows must keep that order.
- **Related plans:** `plan/done/reified-gesture-bindings.md` (done; it says that no editing
  reader with a compiled match is left, which is no longer true),
  `plan/pending/key-chords-from-bindings.md` (deferred),
  `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred; it
  moves Tab and the arrows, and would meet the same readers). Other area: the widget toolkit.
- **Check:** confirmed-with-corrections. Counted again: 44 `@gestures` tables (one in the widget
  slice), 21 tables by hand, 25 `@gesture_case` blocks (20 in `WidgetToGraphics.jl`), 84 lines
  with a `.key` test in 18 files (62 of them in the widget slice) and 25 with a `.char` test;
  all as the report says. The readers cited do give the meaning by hand, and
  `read_bound_gesture` answers `CollectIntents` only from the table. No rule and no plan gives
  the widgets an exception: reified-gesture-bindings.md moved the editing readers of the
  documents and left the widget readers. The menu reads `evt.key === :return`, against
  gesture.md:43 and the owner's rule that Return is read as `KeyPress('\n')`. One correction to
  the proposal: a rule of `@gestures` is a function of the document and the event, and the keys
  of a tree and of a table read the IO map, not fields of the document: the rows that are laid
  out (`iomap.geometry`, `_wtree_key_navigate`), whether row k - 1 of a lazy list exists
  (`find_grid_list_row(st.cells_pane.content_iomap, …)`) and the IO map of the cell that Return
  enters. To put these in the document would move a fact of the reader out of the IO map,
  against the settled decision. So the rule is: a key that reads only the document and its
  selection goes to the table of the document (the menu, the button, the checkbox, the radio
  group; this is PAR-GEOMETRY-FREE-IN-DOCUMENT), and a key that reads the IO map goes to the
  table of the projection, `get_projection_gesture_bindings(p, iomap)`, which exists, fires
  through `read_projection_gesture` and answers `CollectIntents`. `describe_commands` reads
  only the table of the document today, so it needs the rows of the projection too. Nothing is
  lost: the table of an instance is still read first. Value stays high; the effort stays large.

### II-3 A popup window opens in four ways, and each way has its own part of the features

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 7 (one mechanism for every part), PAR-MANY-WINDOWS, PAR-READER-IS-PURE.
- **Today:** Table C. Four operations ask for a popup: `OpenPopupOperation` (a box in the frame
  of the reader), `OpenContextMenuOperation` and `OpenTooltipOperation` (a point and the path of
  the part), and `OpenWindowOperation` given directly. Three pieces of code turn the first three
  into `OpenWindowOperation`. The context menu window gives the keys of the window under it to
  its menu, but only when its own state says that it opened the window
  ([ContextMenuWindow.jl:142](../../../source/platform/widget/ContextMenuWindow.jl#L142),
  [ContextMenuWindow.jl:239](../../../source/platform/widget/ContextMenuWindow.jl#L239)). A menu of the
  menu bar and the list of a select are the same `WidgetMenu` in a window of the same id, but
  they come by `OpenPopupOperation`, so Up, Down and Return do not reach them; the reader of a
  select takes a left click and nothing else
  ([WidgetToGraphics.jl:11739](../../../source/platform/widget/WidgetToGraphics.jl#L11739)). The tooltip
  window and the context menu window keep the same four fields (`layers`, `shown`, `source`,
  `window`) and the same steps, in 346 and 410 lines; they share only the helper for F2
  (`WindowLayers.jl`) and the placement helpers of the screen slice. "Is my
  window open" is kept in four ways (the last column of table C), while the screen document
  already holds the window. The reader of `WindowManagingProjection` writes the screen document
  itself when a window opens or closes
  ([WindowManaging.jl:238](../../../source/platform/screen/WindowManaging.jl#L238),
  [WindowManaging.jl:321](../../../source/platform/screen/WindowManaging.jl#L321)), and
  `evaluate_operation` does the same for an operation that comes from outside the screen.
  Three dialogs that code opens set the action of the last button by hand, with a closure that
  holds the editor ([FileDialog.jl:86](../../../source/platform/shell/FileDialog.jl#L86),
  [RosterToGraphics.jl:319](../../../source/platform/roster/RosterToGraphics.jl#L319),
  [DataFrameValueList.jl:32](../../../source/adapter/dataframes/DataFrameValueList.jl#L32)).
- **Example:**

  ```julia
  # Today: the shape depends on who opens the popup.
  ReplaceViewStateOperation(OpenPopupOperation(; id = :widget_popup,          # select, submenu
      anchor_size = (width, height), gap, auto_dismiss = true, content = WidgetMenu(items)))
  make_context_menu_operation(document, menu, gesture)                        # right click, "⋯"
  make_tooltip_operation(document, note, gesture)                             # dwell
  evaluate_operation(editor, OpenWindowOperation(id = :file_dialog, …))       # a verb

  # Proposed: one request, with what differs as data.
  OpenPartWindowOperation(content; anchor = :part,            # or the point of the gesture
                          dismiss = :press_elsewhere,         # or :pointer_leaves_part, :choice
                          takes_keys = true, layers = …)
  ```

- **Problem:** A feature of one way is missing in the others. Keys work in a context menu and
  not in a menu of the menu bar. The edit of an item of a context menu goes through the readers
  around its part, so a history records it; the pick of an option of a select can not, and its
  comment says why: "The pick runs in the window of the popup, which has no way back to the
  select" ([WidgetToGraphics.jl:11755](../../../source/platform/widget/WidgetToGraphics.jl#L11755)). A
  command can open a context menu or a tooltip with no pointer; it can not open a select. The
  flag of the help window is written in a reader and does not follow a close by the frame of the
  window. A new kind of popup must choose one of the four ways and inherits its gaps.
- **Proposal:** A window that belongs to a part is one concept. `WindowDocument` already holds
  `style`, `auto_dismiss`, `modal`, `placement` and `selection_before`. Give it the rest: the path
  of its part, its layers, and its rule to close. One operation asks for it; it carries the
  content and an anchor (a box or a point in the frame of the reader, moved on the way up as
  now). One place makes the window and `evaluate_operation` applies it, so "open" is "the screen
  holds the window". The window manager is the one reader that closes by the rule, gives the keys
  of the window under a popup to the popup, shows more layers, and lifts the edit of an item from
  the part. The tooltip slice and the context menu keep their bindings, their content and their
  themes.
- **What goes away:** three of the four operations; `TooltipWindowProjection` and
  `ContextMenuWindowProjection` with their state documents (about 750 lines, less what moves into
  the window manager); the conversion in `ScreenToScreen`; `GestureHelpState`; the writes in the
  reader of the window manager; the three hand-wired confirm buttons, when a dialog answers its
  choice as an operation.
- **What stays:** every popup of table C, its place, its close rule and F2. A popup stays a
  window of its own.
- **Risk and open questions:** (1) `plan/done/every-popup-window-is-placed-by-a-function.md`
  (D5) kept `OpenPopupOperation` free of a reference on purpose: the default reader drops an
  operation whose reference maps to a part that a view made
  ([ProjectionDefaults.jl:225](../../../source/kernel/projection/ProjectionDefaults.jl#L225)), and a view
  can make a `WidgetSelect`. The one operation must travel like a path operation, which keeps
  such a step, or carry the box and do without the path there. This needs a check before any
  step. (2) context-menu.md records a decision: "The context menu has a wrapper of its own. A
  tooltip and a menu are alike, but they close in other ways." The proposal turns the close rule
  into data, which goes against that text; the owner decides. (3) The screen slice must not
  depend on the widget slice: the window manager gives a key to the content of the popup and
  knows no menu. (4) The tooltip closes when the pointer leaves the part; the manager can read
  the path from the answer to the move, which is an operation, not the state of another
  projection.
- **Related plans:** `plan/done/every-popup-window-is-placed-by-a-function.md` (done),
  `plan/done/a-press-on-a-menu-name-opens-its-menu.md` (done),
  `plan/pending/a-tooltip-opens-beside-the-pointer-at-any-density.md` (on main, waits for the
  owner's check), `plan/pending/tooltip.md` (stale, see II-7). Other areas: the widget toolkit,
  the screen slice.
- **Check:** weakened. The facts of table C hold; I opened each cited line. The gaps are real:
  a key reaches the content of a popup only when `ContextMenuWindowProjection` opened it
  (`_is_menu_window_open` compares the content of the window), so Up, Down and Return do not
  work in a menu of the menu bar or in the list of a select (widget.md:181 gives "none" as the
  keys of a select); the pick of a select is not lifted; `GestureHelpState.open` and the `Dict`
  of the tooltip decorator are written in a reader; the reader of `WindowManagingProjection`
  changes the screen document itself (`push!` and `deleteat!` on `windows`), against
  PAR-READER-IS-PURE, while `evaluate_operation` has the same code; three dialogs replace the
  action of their last button with a closure that holds the editor. But the "four ways" are a
  recorded design, not an accident. popup-window.md has the section "Three ways to open one"
  and four design decisions: `OpenPopupOperation` carries a box in the frame of its reader, and
  the tooltip window and the context menu window are wrappers at the screen. D5 of
  every-popup-window-is-placed-by-a-function.md tried a reference on `OpenPopupOperation` and
  took it back, because the default reader drops an operation whose reference maps to a part
  that a view made. context-menu.md:94 records that the context menu has a wrapper of its own.
  So the unifying idea of the proposal, "a window that belongs to a part, with the path of its
  part", does not hold for a select or a submenu in a part that a view made: such a popup has
  no path, and the lift of an edit and the layers of F2 both need the path. The proposal would
  also put the dwell rule of a tooltip and the keys of a menu into the window manager of the
  screen slice. What survives is smaller and needs none of the three removals: (a) the window
  manager, which already closes every `auto_dismiss` popup and holds the modal rule, gives a key
  of the window under an open popup to the content of the popup first, for every popup; (b)
  "open" is read from the screen document, as `_is_menu_window_open` already does, so the flag
  and the `Dict` go; (c) the reader of the window manager answers the window operations and
  only `evaluate_operation` applies them; (d) a dialog answers its choice as an operation.
  Value after the check: medium.

### II-4 A wrapper around the content is written by hand each time, and three wrappers exist for one key each

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 2 (a general step knows no domain), 7, and the settled decision that only the
  projections of the algebra hold another projection as a field.
- **Today:** 15 projections outside `source/platform/projection/higherorder/` hold a field
  `inner` with the projection that they wrap: the readers of table B, the two log overlays, and
  the settings and appearance projections. Each one repeats the same parts: an IO map type with
  the four fields `projection`, `input`, `output` and the child; a printer that gives the output
  of the child on; the bridge `read_intent(p, iomap, payload) = read_intent(p, nothing,
  Intent(payload), iomap).operation` (29 copies in the repository); and two reference maps that
  add or drop the step `content`. The wrappers with a state document also repeat:
  `_read_content` (4 copies, one of them named `_read_menu_content`,
  [TooltipWindow.jl:153](../../../source/platform/tooltip/TooltipWindow.jl#L153),
  [DragTracking.jl:88](../../../source/platform/dragtracking/DragTracking.jl#L88)), `_write_state` (4
  copies, one of them named `_write_menu_state`), and a function that joins operations (6
  copies with the same body under 4 names, and 3 more that differ a little; corrected by the
  check,
  [GestureTracking.jl:106](../../../source/platform/gesturetracking/GestureTracking.jl#L106),
  [ContextMenuWindow.jl:254](../../../source/platform/widget/ContextMenuWindow.jl#L254),
  [WindowManaging.jl:195](../../../source/platform/screen/WindowManaging.jl#L195),
  [PivotTableToWidget.jl:541](../../../source/domain/pivot/PivotTableToWidget.jl#L541)). Five wrappers
  take one kind of operation out of the answer of their content, each with its own walk:
  `_take_tooltip` looks into a compound and into `ReplaceViewStateOperation`
  ([TooltipWindow.jl:171](../../../source/platform/tooltip/TooltipWindow.jl#L171)); `_take_context_menu`
  into a compound and any wrapping operation
  ([ContextMenuWindow.jl:260](../../../source/platform/widget/ContextMenuWindow.jl#L260));
  `_split_drag_start` into a compound only
  ([DragTracking.jl:133](../../../source/platform/dragtracking/DragTracking.jl#L133)); `_apply_window_ops`
  into one level of a compound
  ([WindowManaging.jl:174](../../../source/platform/screen/WindowManaging.jl#L174)); `_take_pointer_shape`
  like the tooltip. Three projection types exist to answer one key that nothing inside took:
  `FocusCyclingProjection` (Tab), `SelectionWalkingProjection` (Alt and an arrow) and
  `EscapeQuittingProjection` (Escape), each with about 45 lines of wrapper code around its
  one test. A second style exists beside this
  one: the clipboard and the undo buffer hold no projection; the algebra chooses them by the type
  of their state document, and their keys are a table
  ([ClipboardWrapper.jl:44](../../../source/platform/clipboard/ClipboardWrapper.jl#L44)).
- **Example:**

  ```julia
  # Today (FocusCycling.jl): a projection type, an IO map type, a printer, a reader,
  # a bridge and two reference maps, for this one test:
  (event isa KeyPress && event.char == '\t') || return answer

  # Proposed: the keys are rows, and one projection of the algebra fires them
  # when nothing inside answered.
  const FOCUS_CYCLING_BINDINGS = GestureBinding[
      GestureBinding(KeyPressPattern('\t'; modifiers = Symbol[]),
                     (document, _) -> select_first_stop(document);
                     description = "Go to the first stop", domain = "focus"), …]
  parts.projection = FallbackBindingsProjection(parts.projection, FOCUS_CYCLING_BINDINGS)
  ```

- **Problem:** A new feature at the screen costs about 70 lines before its first line of
  meaning. The copies differ in small ways that nobody chose: which wrapping operations a walk
  enters, whether the child is reconciled when the content is replaced, whether a route passes.
  The keys of these wrappers are not in a table (II-2). The projection field outside the algebra
  is a second way to compose, which the settled decision wants in one place.
- **Proposal:** Three small pieces. (1) One projection of the algebra for "a state document
  around a content": it prints the content, maps references through the step `content`, passes a
  route, and calls one function of a plain behavior value with the state, the change and a
  function that reads the content. The tooltip window, the context menu window, the drag tracker
  and the gesture tracker become behaviors. (2) One projection of the algebra that fires a list
  of bindings when its content answered nothing, through the existing
  `read_projection_gesture`, and that answers `CollectIntents`. The three one-key wrappers become
  lists of rows, and the help and the palette keep only their collection step. (3) One function
  beside `reroot_operation` that takes the operations of one type out of an answer and gives
  back the rest, with one walk of compounds and wrapping operations, and one public function
  that joins operations (the editor layer has a private one,
  [DocumentEdits.jl:118](../../../source/kernel/editor/DocumentEdits.jl#L118)).
- **What goes away:** 15 IO map types and their printers, bridges and reference maps (about 500
  lines), 3 projection types, 5 walks, 6 join functions, 4 `_write_state`, 4 `_read_content`.
- **What stays:** each wrapper as a keyword of `build_editor`, in its layer and its order.
- **Risk and open questions:** The gesture tracker reads timers and runs recognitions; it may
  stay a projection of its own inside the algebra. The owner should say whether a wrapper of this
  kind counts as a projection of the algebra, or whether the decision already forbids its field.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (in progress; it made the
  keywords, and does not touch the wrappers themselves),
  `plan/pending/unify-projection-api-parameter-names.md` (pending; the reader signatures). Other
  area: the projection algebra.
- **Check:** confirmed-with-corrections. Counted again: 15 projections outside `higherorder/`
  hold `inner`; 29 copies of the bridge; `_join_operations` has the same three lines in
  `DragTracking.jl`, `GestureTracking.jl`, `TooltipWindow.jl`, `ContextMenuWindow.jl`,
  `Dragging.jl` and `PivotTableToWidget.jl`; the five walks do enter different wrapping
  operations; `FocusCycling.jl`, `SelectionWalking.jl` and `EscapeQuitting.jl` are one test each
  inside the same 35 lines. No plan covers it: packages-compose-by-seams.md made the keywords
  and leaves the wrappers. Corrections. (1) The owner's rule that only the algebra holds a
  projection is in no rule document, and higher-order-projections.md:7 counts
  `WindowManagingProjection`, `TooltipDecoratorProjection` and `DraggingProjection` as
  higher-order projections "beside the domain each one touches". So whether the 15 break the
  rule is a question for the owner, as the report asks; it is not a fact. (2) Piece 1 of the
  proposal adds a new mechanism, a behavior value that gets a function that reads the content.
  The finding itself names the way that exists and needs no field: the clipboard, the undo
  buffer and `DraggingProjection` are chosen by the type of their state document in a
  `TypeDispatchingProjection` and print the content through the recursion. The tooltip window,
  the context menu window, the drag tracker and the gesture tracker all have a state document
  with a field `content`, so they can go the same way, with one shared IO map type and the
  shared helpers; this is the proposal to give the owner. (3) "15 IO map types go away" is too
  many: the two overlays and the window manager do work of their own in the printer or the
  reader. Pieces 2 and 3 hold as written: the three wrappers of one key read only the document
  and the event, so each is a row, and then F1 lists Tab, Alt and an arrow, and Escape; decision
  N1 of tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md ("a projection step of
  its own") still holds, because the list of rows is a step of its own. No feature is lost.
  Value stays medium.

### II-5 The small move that turns a press into a drag is written four times

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 7, and PAR-NO-GLOBAL-ROUTING, which already gives the drag tracker the one
  fixed route of a drag.
- **Today:** A part whose click has a meaning starts its drag after a small move. Four parts do
  this, each with its own state `(origin, started = false)`, its own branch for a release before
  the start, and its own limit (table D): three use the distance `hypot ≥ 5`, the graph uses
  "each axis ≥ 5", and one of the four limits is a field of a document
  ([DraggingDocument.jl:16](../../../source/platform/dragging/DraggingDocument.jl#L16)). The click
  recognition holds the other side of the same line: a release is a click while each axis moved
  less than `click_max_displacement`, which is a setting of the person
  ([PointerSettings.jl:21](../../../source/platform/gesturetracking/PointerSettings.jl#L21)). The four
  drags do not read the setting. The comment of the graph says that "a drag starts where a click
  stops" ([GraphLayoutToGraphics.jl:1017](../../../source/domain/graph/GraphLayoutToGraphics.jl#L1017)),
  which holds only for the default value and only for the graph.
- **Example:**

  ```julia
  # Today (PaneToWidget.jl): the part keeps the press and tests the move.
  _drag_write(tree, (group, index, origin = (x, y), started = false, …))      # at the press
  hypot(gesture.x - ox, gesture.y - oy) >= _TAB_DRAG_START || return nothing  # at each move
  StartDragOperation(EmptyReference(), (group = state.group, index = state.index))

  # Proposed: the part asks at the press, and the tracker waits for the move.
  StartDragOperation(EmptyReference(), (group = group, index = index); after_move = true)
  ```

- **Problem:** With the click distance set to 10, a press that moves 7 pixels is a drag for a
  tab and still a click for the recognition. The next part that drags after a move, such as a
  file from the explorer, must copy the state and the test again.
- **Proposal:** `StartDragOperation` says whether the drag starts at once or after the move.
  `DragTrackingProjection` keeps the point of the press and sends nothing until the pointer
  leaves the click window; it reads the same limit cell as `ClickRecognition`, and
  `make_tracking_screen` builds both. A release inside the window sends no part of a drag, so the
  click comes as now. The first `DragMove` tells the part that its drag is on.
- **What goes away:** the field `started`, the test and the release branch in four readers
  (about 90 lines), three constants and the field `threshold`.
- **What stays:** every drag of table D, with a click on a tab, a list element, a badge and a
  vertex.
- **Risk and open questions:** No new gesture type is needed, but the protocol of a drag
  changes, and PAR-NO-NEW-SYNTHETIC-EVENT asks for the owner's word near it. The graph needs the
  point of the press for its offset; it can keep it at the press as now. Two smaller facts sit
  beside this finding: `find_drop_zone` is a generic of the kernel with two methods whose
  `point` has two meanings, and each has one caller that knows its own type
  ([Operations.jl:285](../../../source/kernel/operation/Operations.jl#L285)); and `DraggingProjection`,
  the general reorder of a list, is used by examples only, while the pivot reorders its items
  with code of its own.
- **Related plans:** `plan/done/events-gestures-and-the-pointer.md` (done; the drag protocol,
  D20), `plan/done/a-document-knows-the-part-under-the-pointer.md` (done; Q13 points 7 and 8,
  added by the check).
- **Check:** confirmed-with-corrections; the value goes down to low. The four copies are real
  (`started = false` is written in exactly four files), three test `hypot ≥ 5` and the graph
  tests each axis, and none reads `click_max_displacement`. With the default limit a move of
  (4, 4) is already both: `hypot` is 5.7, so the tab drags, and each axis is under 5, so the
  release is a click. Two things the report did not say. (1) The owner agreed to the present
  split on 2026-10-01 (Q13 of a-document-knows-the-part-under-the-pointer.md): point 8, "The
  part decides when its drag starts", and point 7, "the wrapper holds no state of the drag
  itself". The proposal keeps the choice with the part (the flag) and moves the measure and the
  point of the press into the wrapper, so it narrows both points and needs the owner's word. It
  adds no event type, so PAR-NO-NEW-SYNTHETIC-EVENT is not touched. (2) The saving is smaller
  than "about 90 lines". `DragMove` carries no payload and a part can not read the state of the
  wrapper, so each part still writes what was pressed (the tab, the item, the vertex and its
  origin) at the press and still clears it when the release is a click, unless the wrapper
  sends `DragCancel` for a release inside the click window. What goes is the test, the three
  constants, the field `threshold` and the flag `started`: about 40 lines in three live readers
  and in `DraggingProjection`, which only examples use. No feature is lost. The gain is that
  one limit, the setting of the person, says where a click ends and a drag starts.

### II-6 A log of the session is built by hand for each log

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7, 8 (reuse an existing view: a list of items with fields goes to the roster).
- **Today:** gesturelog.md names "the shared shape" of three packages; the code shares none of
  it. `MessageLogStore` and `McpLogStore` have the same six fields and the same five functions,
  in 127 and 122 lines ([MessageLogStore.jl:19](../../../source/platform/log/MessageLogStore.jl#L19),
  [McpLogStore.jl:18](../../../source/platform/mcplog/McpLogStore.jl#L18)). Their two feeds are the same
  cursor loop. `BackgroundWorkFeed` and `FrameStatisticsFeed` are the same "due, watched, at
  most once in an interval" rule
  ([BackgroundWorkFeed.jl:34](../../../source/platform/backgroundwork/BackgroundWorkFeed.jl#L34),
  [FrameStatisticsFeed.jl:56](../../../source/platform/statistics/FrameStatisticsFeed.jl#L56)). Four log
  documents (`MessageLog`, `McpLog`, `GestureLog`, `FaultLog`) each hold `entries`, `capacity`
  and a count, and each trims in its own loop
  ([MessageLogDocument.jl:72](../../../source/platform/log/MessageLogDocument.jl#L72),
  [GestureLogDocument.jl:93](../../../source/platform/gesturelog/GestureLogDocument.jl#L93)).
  `GestureLogOverlayProjection` and `FaultLogOverlayProjection` are one projection written
  twice, function for function, with a prefix in the names (`_panel_x` and `_fault_panel_x`,
  `_is_right` and `_is_fault_right`), in 201 and 246 lines.
- **Example:**

  ```julia
  # Today: a new log needs its own store, feed, document with a trim loop, and panel.
  mutable struct McpLogStore; calls; first_index; lock; capacity; dropped; wakes; end
  mutable struct McpLogFeed <: Feed; store; log; next; end

  # Proposed: the log names its record type and how a record becomes a row.
  # The store belongs to the editor, not to the process (corrected by the check: the report
  # wrote a `const`, which the owner's decision on global state forbids).
  calls = RecordStore{McpCall}(; capacity = 1000)
  push!(parts.feeds, RecordFeed(calls, get_session_mcp_log; make_entry = McpCallEntry))
  ```

- **Problem:** A fix in one copy does not reach the others (the kernel audit lists faults of the
  shared wake and of the process-wide stores, L21-1). The next log copies about 400 lines.
- **Proposal:** One bounded store of numbered records with a lock and the wakes of its readers.
  One feed that copies new records from a cursor, with an optional interval and the "only while a
  view reads it" test. One kit for the log document: entries, capacity, count and the trim. One
  overlay projection that draws any document in a corner of a window; the pending plan for a
  generic overlay widget covers the same need.
- **What goes away:** one of the two stores, two of the four feeds, three of the four trim
  loops, one of the two overlays: about 500 lines.
- **What stays:** the five logs, their tabs, their panels and their capacities. The fault store
  stays as it is: it is keyed, it is the lowest layer, and it must report with no feed.
- **Risk and open questions:** The owner decided that a session document belongs to the editor;
  the producer stores of the message log and the MCP log are still process-wide, and the kernel
  audit plans that (L21-1). A generic store makes that plan one change in place of two. Whether
  the views of the logs should be the roster is a question for the reviewer of that area.
- **Related plans:** `plan/pending/kernel-audit/21-feed.md` (L21-1),
  `plan/pending/configuration-overlay-widget.md` (not started; part A is the generic overlay).
  Other areas: the log, MCP log, background work and statistics slices.
- **Check:** confirmed-with-corrections. Compared the files: `MessageLogStore` and
  `McpLogStore` have the same six fields and the same functions, and differ in the record type
  and in the count of missed lines that only the message log answers; the two overlays have
  the same functions one for one; the four documents trim with the same loop;
  `BackgroundWorkFeed` and `FrameStatisticsFeed` hold the same rule. No shared helper exists,
  and no plan joins them: L21-1 moves the stores to the editor, and
  configuration-overlay-widget.md is about a widget inside the content, not about a panel in a
  corner of a window, so it covers the need only in part. Corrections. (1) The example made the
  store a process constant; the owner decided that no store is global, so the example now makes
  it for the editor. (2) The four feeds are two kinds: two copy new records from a cursor, and
  two write a whole document again when a count changed, a view reads it and the interval is
  over. So two generic feeds stay, not one. (3) The kit of the log document joins four caps
  that exist; it is no answer to the open question of the memory of every list, and must not
  be read as one. Nothing is lost if the generic store keeps the count of missed records. The
  figure of 500 lines is plausible (one store 120, one overlay 200, two feeds 100, three
  loops). Value stays medium.

### II-7 Two older tooltip mechanisms are left beside the one that the editor uses

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 11 (the model as written today), PAR-MANY-WINDOWS, PAR-READER-IS-PURE.
- **Today:** The module text says it: "Two ways to show a tooltip window"
  ([TooltipModule.jl:4](../../../source/platform/tooltip/TooltipModule.jl#L4)). The editor uses the
  binding of a part and `TooltipWindowProjection`. The older way is the document `TooltipSource`
  ([TooltipDocument.jl:4](../../../source/platform/tooltip/TooltipDocument.jl#L4)) and
  `TooltipDecoratorProjection`, which keeps its state in a `Dict` on the projection, reads the
  wall clock in its reader and writes the `Dict` there
  ([TooltipDecorator.jl:80](../../../source/platform/tooltip/TooltipDecorator.jl#L80)). Only two example
  files use it (`example/projectured/Gallery.jl`, `example/platform/WidgetDocumentExample.jl`),
  and one test file (`test/platform/projection/TooltipProjectionTest.jl`; added by the check).
  A third one is `WidgetTooltip`, a tooltip drawn inside the window, which
  `WidgetShell` holds in its field `overlay`
  ([WidgetDocument.jl:1311](../../../source/platform/widget/WidgetDocument.jl#L1311)); one example sets
  it, the widget example shows it alone, and four layout test files build it (added by the
  check).
- **Example:**

  ```julia
  # Today, in the gallery:
  TooltipSource(child = doc, content = content, style = :tooltip, id = id)
  TooltipDecoratorProjection(; trigger = (source, event) -> …, position = …)

  # Proposed: the part says what it is, as every other part does.
  get_document_gesture_bindings_own(::Type{GalleryExample}) =
      GestureBinding[make_tooltip_binding(example -> example.note)]
  ```

- **Problem:** A reader of the tooltip slice meets three models, and two of them break rules
  that the third keeps. `plan/pending/tooltip.md` still lists remaining work for the oldest one.
- **Proposal:** Move the two examples to `make_tooltip_binding`, remove `TooltipSource`,
  `TooltipDecoratorProjection` and the field `overlay` with `WidgetTooltip`, and close the plan.
- **What goes away:** `TooltipDocument.jl`, `TooltipDecorator.jl` (about 160 lines), the widget
  `WidgetTooltip` and its printer.
- **What stays:** the tooltip of every part. One behavior needs a decision: the gallery opens
  its tooltip while the selection is inside an example, by a `trigger` function; a binding opens
  it on a dwell or by a command.
- **Risk and open questions:** Whether the tooltip that follows the selection is a feature to
  keep. If it is, it is a rule to close and to open of the one window (II-3), not a second
  mechanism.
- **Related plans:** `plan/pending/tooltip.md` (stale since the binding model landed),
  `plan/pending/workbench-feature-projections.md` (not started; it names `TooltipSource`).
- **Check:** confirmed-with-corrections. `TooltipDecoratorProjection` does read `time()` and
  write `p.state` in its reader, and nothing in `source/`, in omnet-julia or in inet-julia uses
  it or `TooltipSource`; two example files and one test file do. tooltip.md:89 gives the
  older way a purpose, "a tooltip with its own trigger", so it is a kept variant with a stated
  use, and the removal loses that use: the gallery opens the tooltip while the selection is
  inside an example. The report names this and leaves it to the owner, which is right.
  `WidgetTooltip` is more than the report says: the widget example shows it as a widget of its
  own, and `LayoutRulesTest.jl`, `SizeRangeChildRuleTest.jl`, `SlotSpaceTest.jl` and
  `SizeRangeStackTest.jl` build it. Its removal takes a widget type out of the toolkit, and
  the owner must agree to that; widget.md:403 ("An overlay layer inside the window was
  rejected") supports it. `plan/pending/tooltip.md` is stale as said: it names
  `TooltipProbeProjection`, which is gone. Value stays low.

## Covered by plans

- `play_live!` runs a second frame loop, and a timeline has three entry forms: kernel audit,
  `plan/pending/kernel-audit/23-playback.md` (L23-1, L23-4).
- The log and statistics feeds default to process-wide stores: kernel audit L21-1.
- A history records only what passes its reader: `plan/pending/a-history-records-every-edit-of-its-document.md`.
- No key chord is bound, and where the chord table comes from: `plan/pending/key-chords-from-bindings.md` (deferred).
- Tab and the arrows between parts: `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred).
- A click and an Alt+click reach the innermost part: `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress, step 5).
- A view that draws graphics names no part under a point: `plan/pending/a-view-names-the-domain-part-under-a-point.md` (pending).
- A graph that a view makes gets no part under the pointer: `plan/pending/a-graph-lights-the-part-under-the-pointer.md` (deferred).
- The place of a tooltip at a display density above 1: `plan/pending/a-tooltip-opens-beside-the-pointer-at-any-density.md`.
- The length of a frame and its guards: `plan/pending/guards-keep-the-frame-short-at-any-size.md`.
- A fault that is easy to see: `plan/pending/a-fault-is-easy-to-see-and-stays-small.md`.
- The event layer: `plan/pending/event-layer-reaudit.md`. The loop hard-codes the zoom keys: kernel audit L22-23.
- Each key lookup builds the tables again; a table on a type with parameters is not found: kernel audit L15-3, L15-1.

## Examined and sound

- **One drag protocol.** All 14 drags answer `StartDragOperation` and read `DragMove`, `DragEnd`
  and `DragCancel`. The raw events still go by position, so the light follows the pointer.
- **One hover mechanism.** The `mouse_target` chain has the shape of the selection, and a
  projection that keeps the structure needs no code for it. The two exceptions of table E are
  local.
- **Recognitions are pure rules.** Their state is a field of the tracker document, a deadline is
  a timer of the editor, and a time comes as an input, so a replay gives the same gestures.
- **The outward read of a dwell and a right click** is one kernel rule, `read_gesture_outward`,
  and a collecting operation joins the layers.
- **The pointer shape has two sources for a reason.** A part prints its shape at rest; a drag
  asks the screen to keep a shape, because the shape must hold off the part.
- **One frame loop, and held frames.** A held frame reads no cell and runs in the backend on
  purpose (PAR-LOOP-RUNS-NO-USER-CODE).
- **One feed contract** of three functions serves ten feeds, and the inbox is the first feed.
- **One fault model.** One store for each editor, one `record_fault!`, one policy, and
  `is_fault_exception` at each catch. `run_fault_barrier!` serves a fixed fallback, and a catch in
  place serves an answer that depends on the fault. The fault store is not a feed because it is
  the lowest layer and must report when nothing else works.
- **The gesture recorder is a reader decorator that writes its log.** The design record rejects
  a recorder in the loop and a log operation (`plan/done/gesture-log-overlay.md`).
- **The wrappers of `build_editor` are keywords with seams.** The owner decided "seams only" in
  `plan/pending/packages-compose-by-seams.md`.
- **The split pane has four operation types of its own.** The pane tree translates them into
  its weights, so they must be typed.
- **`Action` with a callback** is the way for a button that the assistant makes from a closure;
  II-1 removes only its second job as a key binding.
- **The right click moves no selection, and the context menu acts on the part under the
  pointer.** II-1 keeps this and gives it a general form.

## Check of the report

Checked at commit 3a9b4fae4, read only. Each file and line that a finding cites was opened, and
each count of a finding was made again with `grep`. The lines of the inventory tables that no
finding uses (tables E, F and G) were checked by sample only. No Julia ran, so a statement about
what a key does in a running window rests on the reading of the code.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| II-1 | confirmed-with-corrections | high |
| II-2 | confirmed-with-corrections | high |
| II-3 | weakened | medium |
| II-4 | confirmed-with-corrections | medium |
| II-5 | confirmed-with-corrections | low |
| II-6 | confirmed-with-corrections | medium |
| II-7 | confirmed-with-corrections | low |

What the check changed in the text: the count of shortcuts in the window chrome (8), the count
of the hand tests of Escape (10), the counts of `Action` and of the readers, the sentence on
the history in II-1, the quote of shell.md, the names and the count of the copied helpers in
II-4, the example of II-6, and the users of the older tooltip code in II-7.

What the owner must decide before a step: II-1 takes back `collect_part_commands`, which the
owner accepted on 2026-10-21; II-3 goes against three recorded decisions on popups in its full
form, and only its smaller form is safe; II-4 asks whether a wrapper counts as a projection of
the algebra; II-5 narrows points 7 and 8 of Q13, which the owner agreed to on 2026-10-01; II-7
removes a widget type and a tooltip that follows the selection.
