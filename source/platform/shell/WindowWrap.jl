# Fragment of `ShellModule` — the fold that stacks a window's wrappers, and the
# two values a binary passes beside it.

"""
    make_window_wrap(; gesture_help = true, command_palette = true,
                     selection = true,
                     clipboard_gestures = CLIPBOARD_GESTURES,
                     history = identity, context_menu = nothing, shell = nothing,
                     measure::TextMeasure = FontFileMeasure(),
                     appearance::Appearance = Appearance()) -> Function

The wrappers a window gets, as the fold `(document, projection) -> (document,
projection)` that a window entry applies before it opens.

- `gesture_help`: F1 opens a window listing the gestures that work where the
  person is. F1 again closes it. The window it opens is drawn by
  [`make_opened_window_projections`](@ref).
- `command_palette`: Ctrl+Shift+P opens a field over the window. Typing narrows
  the commands that work here, Enter runs the selected one, Escape closes it.
- `shell`: the window's chrome. It is `(document) -> (menu_bar, toolbar,
  status_bar, context_menu, size)`, so a host says what its window offers and
  this package names none of it. It is given the window's own document, because
  a status bar says where the person is in it. **The shell is a document**: it wraps the window's own
  document and is drawn by the projection paired with it, so the chrome can be
  selected, referenced and saved like everything else.
- `context_menu`: what the document under the pointer offers on a right press.
  It is the function the probe asks, `(document) -> Document | Nothing`;
  `compute_context_menu` is the one every document answers. A
  `WidgetContextMenu` closer to the pointer answers first, because it is closer.
- `history`: a wrapper for what the window remembers, put **innermost**, around
  the content projection itself. It is a function `projection -> projection`, and
  the default changes nothing. A host that has an undo buffer passes the wrapper
  that draws it. Innermost because such a wrapper is a recursive type dispatch
  over the tree, and anything between it and the tree prints that subtree itself,
  so the recursion never reaches what it dispatches on.
- `selection`: Alt and an arrow walk the objects of the document, and the
  clipboard acts on the object an Alt+click or the walk selected.
  `clipboard_gestures` says which of [`CLIPBOARD_GESTURES`](@ref) are offered; a
  host whose documents must not be cut leaves `:cut` out.

**The gesture log is always recorded**, into the session's own log, and no
keyword turns it off. A person reads it in a tab that View → Gesture log opens,
so the tab must already hold what happened before it existed.

The help, the palette and the recorder wrap the projection and leave the
document as it is. The clipboard wraps the document too, so a verb that walks the window
must look inside it.

The order is the history innermost, the shell over it, the focus cycling over the
shell, the walk and the clipboard over that, the context menu probe over them, the
help over that, the palette over it, and the log's recorder outermost, where it sees
every operation the window makes. The focus cycling is always there, so Tab
starts over at the ends of every window. A window gets its light under the
pointer from the screen, which gives each move to its windows.
"""
function make_window_wrap(; gesture_help::Bool = true, command_palette::Bool = true,
                            selection::Bool = true,
                            clipboard_gestures::Tuple = CLIPBOARD_GESTURES,
                            history = identity,
                            context_menu = nothing, shell = nothing,
                            measure::TextMeasure = FontFileMeasure(),
                            appearance::Appearance = Appearance())
    # One flag for the help window, which the decorator reads each time F1 comes.
    help_state = GestureHelpState()
    # The session's own log, and not one this fold made: a tab that opens a
    # gesture log opens this one.
    log = get_session_gesture_log()
    (document, projection) -> begin
        # The history is innermost, under the clipboard. It is a recursive type
        # dispatch, and what it dispatches on — a buffer around what a tab
        # holds — sits inside the tree. A wrapper between it and the tree prints
        # that subtree itself, and the recursion never reaches the buffer.
        projection = history(projection)
        # The chrome is outside the window's own document and inside everything
        # that acts on a window, so the walk and the clipboard reach into it and
        # a verb that asks for the pane tree looks past it.
        if shell !== nothing
            menu_bar, toolbar, status_bar, context_menu_document, size = shell(document)
            document = make_window_shell_document(document; menu_bar = menu_bar,
                                                  toolbar = toolbar,
                                                  status_bar = status_bar,
                                                  context_menu = context_menu_document,
                                                  size = size)
            projection = make_window_shell_projection(projection; measure = measure,
                                                       appearance = appearance)
        end
        # Tab starts over at the ends of the window, the bands with the panes.
        projection = FocusCyclingProjection(inner = projection)
        if selection
            projection = make_clipboard_projection(SelectionWalkingProjection(inner = projection);
                                                   offered_gestures = clipboard_gestures)
            document = make_clipboard_document(document)
        end
        # Over the walk, because the probe asks the document the walk selects in;
        # under the help and the palette, because a probe must not answer for a
        # window that one of them opened.
        context_menu === nothing ||
            (projection = ContextMenuProbeProjection(inner = projection,
                                                     compute_context_menu = context_menu))
        gesture_help &&
            (projection = GestureHelpDecoratorProjection(inner = projection, state = help_state))
        command_palette &&
            (projection = CommandPaletteDecoratorProjection(inner = projection, measure = measure))
        # The recorder is outermost, where it sees every operation the window
        # makes, and it is always there. A typed run is one entry: a person reads
        # what was typed, not one line for each letter.
        projection = GestureLogRecordingProjection(inner = projection, log = log, fold_typing = true)
        (document, projection)
    end
end

"""
    make_opened_window_projections(; gesture_help = true, content = [],
                                   measure::TextMeasure = FontFileMeasure(),
                                   appearance::Appearance = Appearance()) -> Vector

What draws the content of a window that a wrapper of [`make_window_wrap`](@ref)
opens. It is the value of the `opened_window_projections` setting of the
`window` wrapper of `build_editor`.

**A window whose content type is named by no row draws nothing.** The help
window holds a `GestureMap`, which this function names. A tooltip window holds a
`TooltipContent`, which the natural projection draws, so **a host that shows
tooltips passes the natural rows** as `content`, with the rows that draw its own
documents. They are the rows the window already draws a pane's content with.

The help window holds a `GestureMap`. The palette and the log draw into the
window they wrap and open none.

**A popup holds widgets**: the menu of a menu bar or of a context menu, and the
options of a `WidgetSelect`, in a layout. So the rows end with the rows of
`WidgetToGraphics`, one for each widget and each layout, in the scaled widget
theme of `appearance` and the measure the shell draws its bands with. The rows
of `content` come before them, so a host decides first.
"""
make_opened_window_projections(; gesture_help::Bool = true,
                                 content = Pair{Type,Any}[],
                                 measure::TextMeasure = FontFileMeasure(),
                                 appearance::Appearance = Appearance()) =
    vcat(gesture_help ?
             Pair{Type,Any}[GestureMap => make_gesture_map_projection(measure)] :
             Pair{Type,Any}[],
         Pair{Type,Any}[content...],
         Pair{Type,Any}[WidgetToGraphics(; measure = measure,
                                         theme = get_scaled_theme!(appearance, WidgetTheme)).dispatch...])
