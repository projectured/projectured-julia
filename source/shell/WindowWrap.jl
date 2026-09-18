# Fragment of `ShellModule` — the fold that stacks a window's wrappers, and the
# two values a binary passes beside it.

"""
    make_window_wrap(; gesture_help = true, command_palette = true,
                     gesture_log = false, selection = true,
                     clipboard_gestures = CLIPBOARD_GESTURES,
                     measure = measure_truetype_text) -> Function

The wrappers a window gets, as the fold `(document, projection) -> (document,
projection)` that a window entry applies before it opens.

- `gesture_help`: F1 opens a window listing the gestures that work where the
  person is. F1 again closes it. The window it opens is drawn by
  [`make_opened_window_projections`](@ref).
- `command_palette`: Ctrl+Shift+P opens a field over the window. Typing narrows
  the commands that work here, Enter runs the selected one, Escape closes it.
- `gesture_log`: a panel in the top-right corner lists the last gestures and the
  operation each one made. Off by default: it is for a demonstration and for a
  fault report, not for daily work. **The log is recorded either way.** A gesture
  log a person opens in a tab is the session's own, so it must already hold what
  happened before the tab existed; this keyword adds the panel, not the record.
- `history`: a wrapper the host puts between the palette and the recorder, for
  what the window remembers. It is a function `projection -> projection`, and the
  default changes nothing. A host that has an undo buffer passes the wrapper that
  draws it.
- `selection`: Alt and an arrow walk the objects of the document, and the
  clipboard acts on the object an Alt+click or the walk selected.
  `clipboard_gestures` says which of [`CLIPBOARD_GESTURES`](@ref) are offered; a
  host whose documents must not be cut leaves `:cut` out.

The help, the palette and the log wrap the projection and leave the document as
it is. The clipboard wraps the document too, so a verb that walks the window
must look inside it.

The order is the gallery's: the walk and the clipboard inside, the help over
them, the palette over it, the history over that, the log's panel over the
history, and the log's recorder outermost, where it sees every operation the
window makes.
"""
function make_window_wrap(; gesture_help::Bool = true, command_palette::Bool = true,
                            gesture_log::Bool = false, selection::Bool = true,
                            clipboard_gestures::Tuple = CLIPBOARD_GESTURES,
                            history = identity,
                            measure = measure_truetype_text)
    # One flag for the help window, which the decorator reads each time F1 comes.
    help_state = GestureHelpState()
    # The session's own log, and not one this fold made: a tab that opens a
    # gesture log opens this one.
    log = get_session_gesture_log()
    (document, projection) -> begin
        if selection
            projection = make_clipboard_projection(SelectionWalkingProjection(inner = projection);
                                                   offered_gestures = clipboard_gestures)
            document = make_clipboard_document(document)
        end
        gesture_help &&
            (projection = GestureHelpDecoratorProjection(inner = projection, state = help_state))
        command_palette &&
            (projection = CommandPaletteDecoratorProjection(inner = projection, measure = measure))
        projection = history(projection)
        gesture_log &&
            (projection = GestureLogOverlayProjection(inner = projection, log = log))
        # The recorder is outermost, where it sees every operation the window
        # makes, and it is always there.
        projection = GestureLogRecordingProjection(inner = projection, log = log)
        (document, projection)
    end
end

"""
    make_opened_window_projections(; gesture_help = true,
                                   measure = measure_truetype_text) -> Vector

What draws the content of a window that a wrapper of [`make_window_wrap`](@ref)
opens. It is the value of the `opened_window_projections` keyword of
`run_window_editor`.

The help window holds a `GestureMap`. The palette and the log draw into the
window they wrap and open none.
"""
make_opened_window_projections(; gesture_help::Bool = true,
                                 measure = measure_truetype_text) =
    gesture_help ? Pair{Type,Any}[GestureMap => make_gesture_map_projection(measure)] :
                   Pair{Type,Any}[]

"""
    make_popup_screen_wrap() -> Function

The wrap that puts `WidgetPopupResolverProjection` on the window route. It is
the value of the `screen_wrap` keyword of `run_window_editor`.

**A popup is a native window, so it is placed in screen coordinates.** A widget
that offers one answers an `OpenPopupOperation` naming an anchor and an offset
inside the window; the resolver maps that anchor forward through the screen
printer, adds the offset, and answers the `OpenWindowOperation` that the window
manager opens. Mapping through the screen printer is what makes the coordinates
absolute, and it is why this cannot ride in the fold of
[`make_window_wrap`](@ref): the fold wraps the content of a window and never
sees the screen.

A window that goes without it draws every popup-offering widget and opens none
of them.
"""
make_popup_screen_wrap() = inner -> WidgetPopupResolverProjection(inner = inner)
