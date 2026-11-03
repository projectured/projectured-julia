# Gesture help and command palette

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [screen.md](../screen/screen.md), [gesturelog.md](../gesturelog/gesturelog.md)

The gesturehelp slice of `ProjecturedPlatform` holds two lists that a person opens while working: F1 shows the gestures that work where the selection is, and Ctrl+Shift+P runs a command by its name. Both read the live projection chain, not a table written by hand. This document says how the rows are collected, why the help is a window of its own and the palette is a list in the context menu window, and how the palette matches a query.

## How it works

Both tools have [the shared shape](../gesturelog/gesturelog.md#the-shared-shape): a document, a transparent decorator, and a view of the document. The decorator does not record or catch. It uses one gesture that the inner reader returned no operation for. The palette has no document and no view of its own: it is a list of the widget slice.

### One list of rows

A key press goes to the view under the selection, and each view has its own gestures. So the true list of keys depends on where the selection is. Both decorators call the inner reader with `Intent(CollectIntents())`, the route that a keystroke takes. Every gesture table on that route returns one `Intent` for each rule, with the operation that the rule builds now, inside a `CollectedIntentsOperation`. Every stage on the way back roots these operations, so each one applies at the input of the decorator. [devices-and-backends.md](../../kernel/devices-and-backends.md#asking-what-is-available) describes the collection.

`collect_gesture_rows` makes one `GestureRow` for each intent: the gesture text, the description, the domain and the operation. The order is the order of the chain, the innermost document first, and a pair of domain and description appears once. A row whose `operation` is `nothing` can not run now: its precondition failed, or it needs the key that carries its argument. No other test of applicability exists.

### F1: the gesture map

`GestureHelpDecoratorProjection(; inner, state, id = :gesture_help, …)` passes the output of `inner` through. Its reader calls the inner reader first. When that returns no operation and the gesture matches `HELP_GESTURE`, which is `KeyDownPattern(:f1)`, the decorator collects the rows, makes a `GestureMap`, and returns an `OpenWindowOperation` whose content is the map. `WindowManagingProjection` opens it as a window beside the content; see [screen.md](../screen/screen.md). A second F1 returns `CloseWindowOperation(id)`.

**A command opens a tool with an operation.** `ToggleGestureHelpOperation()` and `ToggleCommandPaletteOperation()` do what F1 and Ctrl+Shift+P do. A command sends one with a route into the content of the decorator, as `read_rooted_operation` sends an operation, and the decorator finds it in the answer of its inner reader. The key and the operation call one function in each decorator. Each operation names no place, so it travels up a chain as it is. The Help menu of the shell sends them; [shell.md](../shell/shell.md#the-menu-bar) says how.

The open flag is in a `GestureHelpState` that the caller makes and shares, because a pipeline can build the decorator again for each dispatch. The screen that opens the window needs a row for `GestureMap`: `make_gesture_map_projection(measure)` chains `GestureMapToSyntax`, `SyntaxToText`, `WordWrapping` and `TextToGraphics`. `GestureMapToSyntax` prints a heading for each domain and one line for each row. A row with no key shows `by name`, and a row that can not run is muted and ends with `(n/a)`.

### Ctrl+Shift+P: the command palette

`CommandPaletteDecoratorProjection(; inner)` passes the output of `inner` through, and it maps references as `inner` does. It holds no state. The inner reader comes first, as in the help. The palette gesture, `COMMAND_PALETTE_GESTURE`, which is `KeyDownPattern(:p; modifiers = [:ctrl, :shift])`, or a `ToggleCommandPaletteOperation` that comes up from the content, then collects the rows and answers

```julia
make_choice_list_operation("Commands", make_command_palette_list(rows);
                           placement = make_shell_top_placement)
```

The operation opens the list in the context menu window ([context-menu.md](../widget/context-menu.md#a-list-that-a-person-types-into)), at the top center of the window, below its menu bar and toolbar. So the editor needs the `context_menu` wrapper, which is on by default. The list takes the keys while it is open: a typed letter narrows it, Up, Down, Page Up and Page Down move the row, Return chooses it and Escape closes it. A key that the list does not answer goes on to the window under it. Ctrl+Shift+P while the list is open opens it again.

`make_command_palette_list(rows)` makes the `WidgetChoiceList`. It has one `WidgetChoice` for each row whose operation is not `nothing`, with the description as the label and the key as the note. A row that can not run does not appear; F1 still lists every command, and marks the ones that can not run. The query matches the text "domain description" with `find_letter_matches`, and the description is the name part. So a match in the description ranks first, and the domain still matches.

To run a row, the choice answers the operation of the row. The context menu window lifts it from the place of the decorator through the readers above it, as a key would. So an undo buffer above the decorator records it as an edit.

### Matching a query

`find_letter_matches(query, texts; name_start)` of the widget slice ranks the rows. The letters of the query must appear in order in the text, in any case, and they need not touch. A match at the start of a word counts most, a match in the description counts more than one in the domain, and a letter right after the one before counts more. A higher score ranks first, then a shorter text, then the order of collection. [context-menu.md](../widget/context-menu.md#a-list-that-a-person-types-into) gives the rules.

### What a domain must do to appear

Nothing but declare its gestures with `@gestures`. The description of a rule is what both lists show, and a rule with no description shows its key alone. A rule with `nothing` in the pattern slot has no key; it appears in the palette by its name.

### The commands of a part for a verb

`describe_commands(part)` and `run_command!(part, words)` (`PartCommands.jl`) list and run the commands of a part for an assistant, and the selection of the person does not move. The part is read again from the root by its reference. Its commands are the rows of its own table, read with `CollectIntents`, and then the commands that each document on the path of the part gives to it, the nearest document first: `collect_part_commands(holder, steps)` answers them for the part at `steps` below `holder`, and the default answers none. A row keeps the place of the document that gave it, and `run_command!` roots its operation there with `read_rooted_operation`, so every reader above that place lifts it and the history records it as an edit. A command whose words a nearer row has is left out. The explorer gives the commands of the menu of a row this way ([explorer.md](../explorer/explorer.md#what-an-assistant-calls)).

### The theme

`GestureHelpTheme` holds the text of the header, a gesture, a description and the muted parts of the gesture map. Each value has the default that the slice draws with no
appearance. `GestureMapToSyntax` holds its styles and no theme. `make_gesture_map_projection` fills them with `get_gesture_help_style`, from a `GestureHelpTheme` scaled or not, or the default values for `nothing`. The wrapper `gesture_help` of `build_editor` gives the window of the gesture map its theme and the syntax and the text themes of the `Appearance` of the `appearance` wrapper, and so does `make_opened_window_projections` of the shell wrapper, so the map scales with the editor. The palette draws with the widget theme, as every list of the widget slice does.

## How it fits

The gesturehelp slice depends on the kernel and on the collection, graphics, projection, screen, style, syntax, text and widget slices. It takes the collection of intents from the gesture bindings of the kernel, the window operations from the screen slice, and the list, its placement and its matching from the widget slice.

A window built with `build_editor` adds both decorators only when `gesture_help` or `command_palette` is given as a wrapper. `command_palette` takes `true` and no measure, and it is around the help; [shell.md](../shell/shell.md#the-wrappers-of-a-window) says why. `make_opened_window_projections` of the shell gives the row for `GestureMap`. The gallery adds them with `gesture_help = true` and `command_palette = true`.

It registers nothing: no natural row and no insertion alias. No tab holds the gesture map.

## Design decisions

- **The lists are projections over the live chain.** A list written by hand goes stale when a projection changes. The rows come from the same gesture tables that fire, so what a list shows is what a key does. See [plan/done/reified-gesture-bindings.md](../../../../plan/done/reified-gesture-bindings.md).
- **Applicability is the built operation.** A row runs when its rule built an operation. No predicate exists that could disagree with the rule.
- **The palette is a list in the context menu window.** A window that the screen holds gets its own keys, its own place and its own close, so the palette needs no panel of its own. An operation that comes from another window applies at the place of that window. The context menu window lifts the operation of a choice from its part, through the readers above it, so the operation of a row applies where the key of the binding would apply. See [plan/done/command-palette.md](../../../../plan/done/command-palette.md).
- **The help map is a snapshot.** The rows are built once, when F1 is pressed. A map that follows the selection was left for later; press F1 twice to see the list of a new place.
- **A query matches letters in order, and the name ranks first.** The letters of `sort` appear in order in `Select the root node`, so a match alone does not rank. A letter at the start of a word and a letter in the description count more, so the right row comes first.
- **The help state is outside the projection.** A pipeline can build the decorator again for each dispatch, and only an object that the caller holds keeps the open flag of the help.

## Usage

```julia
help_state = GestureHelpState()
projection = GestureHelpDecoratorProjection(inner = projection, state = help_state)
projection = CommandPaletteDecoratorProjection(inner = projection)
help_row   = GestureMap => make_gesture_map_projection(FontFileMeasure())   # for the window F1 opens
run_example("json"; gesture_help = true, command_palette = true)
```

- Example: `make_gesture_map_document_example()`, the `GestureMap` of the atomic catalog. The package has no example of its own; the gallery keywords above show both tools.
- Tests: `test_gesture_help()`, `test_gesture_map()`, `test_command_palette()` and `test_command_palette_decorator()` in `test/projectured/projection/`. The package has no test suite of its own.

[keyboard-and-mouse-guide.md](../../../guide/keyboard-and-mouse-guide.md) describes the same tools for a user of the editor.

## Limits

- The help map does not follow the selection while it is open.
