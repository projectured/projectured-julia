# Fragment of `ShellModule` — the fold that stacks a window's wrappers, and the
# two values a binary passes beside it.

"""
    make_window_wrap(; gesture_help = true, command_palette = true,
                     selection = true,
                     clipboard_gestures = CLIPBOARD_GESTURES,
                     history = identity, tooltip = nothing, pointer = nothing,
                     tooltip_feed = nothing, context_menu = nothing, shell = nothing,
                     measure = measure_truetype_text) -> Function

The wrappers a window gets, as the fold `(document, projection) -> (document,
projection)` that a window entry applies before it opens.

- `gesture_help`: F1 opens a window listing the gestures that work where the
  person is. F1 again closes it. The window it opens is drawn by
  [`make_opened_window_projections`](@ref).
- `command_palette`: Ctrl+Shift+P opens a field over the window. Typing narrows
  the commands that work here, Enter runs the selected one, Escape closes it.
- `tooltip`: what the document under the pointer says about itself, shown in a
  window of its own beside the pointer (`PAR-MANY-WINDOWS`). It is the function
  the probe asks, `(document) -> Document | Nothing`; `compute_tooltip` is the
  one every document answers. `nothing` leaves the wrapper out. It needs
  `pointer`, because a window is placed in screen coordinates and only a backend
  knows where the pointer is, and `tooltip_feed`, a `TooltipFeed` from
  `make_tooltip_feed`. A tooltip opens once the pointer has rested, and a resting
  pointer sends nothing, so the time comes from the loop: the entry hands the same
  feed to `run_window_editor(feeds = …)`, and the feed wakes the loop when the
  rest is long enough.
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

The order is the history innermost, the shell over it, the hover tracker over the
shell, the walk and the clipboard over that, the tooltip probe over them, the help
over that, the palette over it, and the log's recorder outermost, where it sees
every operation the window makes. The hover tracker is always there: a window
that shows a button must light it.
"""
function make_window_wrap(; gesture_help::Bool = true, command_palette::Bool = true,
                            selection::Bool = true,
                            clipboard_gestures::Tuple = CLIPBOARD_GESTURES,
                            history = identity,
                            tooltip = nothing, pointer = nothing, tooltip_feed = nothing,
                            context_menu = nothing, shell = nothing,
                            measure = measure_truetype_text)
    tooltip === nothing || pointer !== nothing ||
        error("make_window_wrap: a tooltip is placed beside the pointer, so it needs `pointer`")
    tooltip === nothing || tooltip_feed !== nothing ||
        error("make_window_wrap: a tooltip opens when the pointer has rested, so it needs `tooltip_feed`")
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
            projection = make_window_shell_projection(projection; measure = measure)
        end
        # The hover tracker sees the whole window, the bands with the panes: only
        # something that sees all of it can tell that the pointer left a button in
        # the toolbar for a row in a pane.
        projection = WidgetHoverTrackingProjection(inner = projection)
        if selection
            projection = make_clipboard_projection(SelectionWalkingProjection(inner = projection);
                                                   offered_gestures = clipboard_gestures)
            document = make_clipboard_document(document)
        end
        # Over the walk, because the probe asks the document the walk selects in;
        # under the help and the palette, because a probe must not answer for a
        # window that one of them opened.
        tooltip === nothing ||
            (projection = TooltipProbeProjection(inner = projection,
                                                 compute_tooltip = tooltip,
                                                 pointer = pointer,
                                                 feed = tooltip_feed))
        context_menu === nothing ||
            (projection = ContextMenuProbeProjection(inner = projection,
                                                     compute_context_menu = context_menu))
        gesture_help &&
            (projection = GestureHelpDecoratorProjection(inner = projection, state = help_state))
        command_palette &&
            (projection = CommandPaletteDecoratorProjection(inner = projection, measure = measure))
        # The recorder is outermost, where it sees every operation the window
        # makes, and it is always there.
        projection = GestureLogRecordingProjection(inner = projection, log = log)
        (document, projection)
    end
end

"""
    make_opened_window_projections(; gesture_help = true, content = [],
                                   measure = measure_truetype_text) -> Vector

What draws the content of a window that a wrapper of [`make_window_wrap`](@ref)
opens. It is the value of the `opened_window_projections` keyword of
`run_window_editor`.

**A window whose content type is named by no row draws nothing.** The help
window holds a `GestureMap`, which this function names. A tooltip holds whatever
the document under the pointer answered — a string, a block of prose, a document
of any domain the host has — so **a host that turns the tooltip on passes the
rows that draw its own documents** as `content`. They are the rows the window
already draws a pane's content with.

The help window holds a `GestureMap`. The palette and the log draw into the
window they wrap and open none.

**A popup holds widgets**: the menu of a menu bar or of a context menu, and the
options of a `WidgetSelect`, in a layout. So the rows end with the rows of
`WidgetToGraphics`, one for each widget and each layout, in the font and the
measure the shell draws its bands with. The rows of `content` come before them,
so a host decides first.
"""
make_opened_window_projections(; gesture_help::Bool = true,
                                 content = Pair{Type,Any}[],
                                 measure = measure_truetype_text) =
    vcat(gesture_help ?
             Pair{Type,Any}[GestureMap => make_gesture_map_projection(measure)] :
             Pair{Type,Any}[],
         Pair{Type,Any}[content...],
         Pair{Type,Any}[WidgetToGraphics(font_ubuntu_regular_20; measure = measure).dispatch...])
