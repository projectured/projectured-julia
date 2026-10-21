# Fragment of `ScreenModule` — a window that shows the first layers of what a
# wrapper at the screen collected, such as the tooltip window and the context
# menu window, and the two keys that show more and fewer of them.

"""
    show_window_layers(state, count, make_content) -> Operation

The window of `state` again, with the first `count` of its layers, when that is
another count. `state` is the state document of a wrapper that keeps one window,
with the fields `layers`, `shown` (how many layers the window shows, `0` when it
is closed) and `window` (the `OpenWindowOperation` that opened the window last).
`make_content(layers, shown)` is what the window shows. `count` stays between one
and the number of layers, and the window stays where it opened. A view state
operation writes `shown` and `window`, so a history does not record it.
"""
function show_window_layers(state, count::Int, make_content::Function)
    count = clamp(count, 1, length(state.layers))
    count == state.shown && return DoNothingOperation()
    window = state.window
    reopened = OpenWindowOperation(; id = window.id, title = window.title,
                                     x = window.x, y = window.y,
                                     width = window.width, height = window.height,
                                     minimum_size = window.minimum_size,
                                     maximum_size = window.maximum_size,
                                     bg = window.bg, style = window.style,
                                     auto_dismiss = window.auto_dismiss,
                                     modal = window.modal,
                                     content = make_content(state.layers, count))
    CompoundOperation(Any[_write_window_state(state, "shown", count),
                          _write_window_state(state, "window", reopened),
                          reopened])
end

# A write of one field of the state of a wrapper, which a history does not record.
_write_window_state(state, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

"""
    WINDOW_LAYER_MORE_KEY

The key that shows one more layer of a window that shows layers: F2.
[`make_window_layer_bindings`](@ref) binds it, and a window that names it to a
person reads it here, so the name and the binding are the same key.
"""
const WINDOW_LAYER_MORE_KEY = KeyDownPattern(:f2; modifiers = Symbol[])

"""
    WINDOW_LAYER_FEWER_KEY

The key that shows one fewer layer of a window that shows layers: Shift+F2. See
[`WINDOW_LAYER_MORE_KEY`](@ref).
"""
const WINDOW_LAYER_FEWER_KEY = KeyDownPattern(:f2; modifiers = [:shift])

"""
    make_window_layer_bindings(make_content; domain) -> Vector{GestureBinding}

The two keys of a window that shows the first layers of what a wrapper
collected: F2 shows one more layer, outward, and Shift+F2 one fewer
([`show_window_layers`](@ref)). A wrapper declares them in the gesture table of
its state, so the gesture help lists them, and each one applies only while the
window is open. `domain` names the wrapper in the gesture help.
"""
make_window_layer_bindings(make_content::Function; domain::AbstractString) =
    GestureBinding[
        GestureBinding(WINDOW_LAYER_MORE_KEY,
                       (state, gesture) ->
                           show_window_layers(state, state.shown + 1, make_content);
                       applicable = (state, selection) -> state.shown > 0,
                       description = "Show what the next part around says",
                       domain = String(domain)),
        GestureBinding(WINDOW_LAYER_FEWER_KEY,
                       (state, gesture) ->
                           show_window_layers(state, state.shown - 1, make_content);
                       applicable = (state, selection) -> state.shown > 0,
                       description = "Show one part fewer", domain = String(domain)),
    ]
