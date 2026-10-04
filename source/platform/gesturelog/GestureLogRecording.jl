# Fragment of `GestureLogModule`.
#
# A transparent decorator that records what the reader chain below it decides.
#
# **Printer** — transparent: it projects the wrapped `inner` and returns its output
# unchanged, so the display is exactly the display without the decorator.
#
# **Reader** — it calls the inner reader, records the pair (gesture, operation) in
# the [`GestureLog`](GestureLogDocument.jl) when the filter accepts the pair, and returns
# the inner result without a change. The decorator never makes an operation of its
# own and never consumes a gesture.
#
# Put it at the **root** of the composed projection. The root is the seam where
# every operation passes, so a content operation, a window operation and an
# operation of a nested application all reach the log. The editor makes the
# readability-zoom operation after the pipeline declines the gesture, so that one
# operation stays outside the log.
#
# The filter is a plain field of a plain struct, not a reactive field. A
# `Function` in a reactive field becomes a thunk and the reader calls it with no
# arguments.
"""
    GestureLogRecordingProjection(; inner, log, filter = default_gesture_log_filter,
                                    fold_typing = false)

Decorator over `inner` that records every operation the inner reader makes.
`filter(gesture, operation)` decides what the log keeps; the default drops the
selection operations. Each entry writes its references from the document this
projection reads, by the titles of the documents on them. `fold_typing` folds a
run of typed characters into one entry (see `record_gesture!`). A click, a turn
of the wheel, or a key that types no character ends the run, also when the
filter keeps no entry of it, so the text typed after it is an entry of its own.
"""
struct GestureLogRecordingProjection <: Projection
    inner::Any
    log::GestureLog
    filter::Any
    fold_typing::Bool
end

GestureLogRecordingProjection(; inner, log::GestureLog,
                                filter = default_gesture_log_filter, fold_typing::Bool = false) =
    GestureLogRecordingProjection(inner, log, filter, fold_typing)

# Transparent: `output` forwards the inner output through a cell so the IoMap
# keeps its identity while the inner projection re-derives.
@iomap struct GestureLogRecordingIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (transparent) ──────────────────────────────────────────────────

function print_document(p::GestureLogRecordingProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    GestureLogRecordingIoMap(p, input, Cell(@computation inner_iomap.output), inner_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::GestureLogRecordingProjection, recursion, change::Intent,
                     iomap::GestureLogRecordingIoMap)
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    operation = child isa Intent ? child.operation : child
    if operation isa Operation && p.filter(change.gesture, operation)
        # Code that acts with no gesture says in the description what it did.
        record_gesture!(p.log, change.gesture === nothing ? change.description : change.gesture,
                        operation; root = iomap.input, fold_typing = p.fold_typing)
    elseif p.fold_typing && !isempty(p.log.typing) && _ends_typing_run(change.gesture)
        # A click that only selects, or F3 that only scrolls, is no entry, but the
        # person stopped typing: the next typed character starts an entry of its own.
        p.log.typing = ""
    end
    child
end

# The keys that type no character. The press of any other key comes with the
# character that it types.
const _NON_TYPING_KEYS = Set{Symbol}([:left, :right, :up, :down, :home, :end, :page_up, :page_down,
                                      :return, :tab, :escape, :insert, :backspace, :delete,
                                      :f1, :f2, :f3, :f4, :f5, :f6, :f7, :f8, :f9, :f10, :f11, :f12])

# Is `gesture` an act of the person that types no character: a press of a mouse
# button, a turn of the wheel, a key with Ctrl, Alt or Meta held, or a key that
# types nothing? A move or a dwell of the pointer, a key up and a timer are none.
function _ends_typing_run(gesture)
    event = gesture isa WindowInput ? gesture.event : gesture
    event isa Union{MouseClick, MouseDown, MouseScroll} && return true
    event isa KeyDown || return false
    modifiers = event.modifiers
    modifiers.ctrl || modifiers.alt || modifiers.meta || event.key in _NON_TYPING_KEYS
end

read_intent(p::GestureLogRecordingProjection, iomap::GestureLogRecordingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping (transparent — the output is the inner output) ───────

map_reference_forward(p::GestureLogRecordingProjection,
                      iomap::GestureLogRecordingIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::GestureLogRecordingProjection,
                       iomap::GestureLogRecordingIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

# ── The gesture log of a window, as a wrapper of `build_editor` ──────────────

"""
    gesture_log = true | (; overlay, anchor, lines, measure, operation_width)

The wrapper of `build_editor` that records each operation of a window in the
gesture log of the session ([`get_session_gesture_log`](@ref)), with the key or
the click that made it. It records no move of the selection, and a run of typed
characters is one entry. View → Gesture log and the toolbar of the `shell`
wrapper open the log. It is off by default. It acts outermost in the content of
the window, so it sees every operation that the window makes.

`overlay = true` also draws the newest gestures as a panel over the content, in
the corner that `anchor` names (`:bottom_right` by default), so a person who
watches the window sees each gesture and what it did, as a video shows them. The
panel holds the last `lines` entries (8 by default) in a log of its own,
`measure` measures its text (`FontFileMeasure()` by default),
`operation_width` limits the operation of a line (60 characters by default), and
`background` is its color, by default the translucent `panel_background` of the
gesture log theme. The panel takes the "Panel" preset of the gesture log theme,
scaled with the `Appearance` of the build when the editor has one, so its colours
follow the colour settings of the appearance.
"""
function wrap_editor!(::Val{:gesture_log}, layer::Symbol, argument, parts::EditorParts)
    options = argument === true ? (;) : argument
    inner = get(options, :overlay, false) === true ?
            _make_gesture_log_panel(parts.projection, options,
                                    get(parts.arguments, :appearance, nothing)) : parts.projection
    parts.projection = GestureLogRecordingProjection(inner = inner,
                                                     log = get_session_gesture_log(),
                                                     fold_typing = true)
    parts
end

# The panel of the newest gestures over `projection`. It has a short log of its
# own, so it stays as tall as its lines, and it records into that log as the
# wrapper records into the log of the session. With an `appearance`, the panel
# theme is scaled with it, so its colours follow the colour settings.
function _make_gesture_log_panel(projection, options, appearance)
    log = GestureLog(; capacity = get(options, :lines, 8))
    theme = appearance isa Appearance ? make_scaled_theme(make_gesture_log_panel_theme(), appearance) :
                                        make_gesture_log_panel_theme()
    content = make_gesture_log_content_projection(; measure = get(options, :measure, FontFileMeasure()),
                                                    operation_width = get(options, :operation_width, 60),
                                                    theme)
    # A background that the options name replaces the one of the theme.
    background = haskey(options, :background) ? (; background = options[:background]) : (;)
    GestureLogRecordingProjection(inner = GestureLogOverlayProjection(; inner = projection, log = log,
                                                                      content = content,
                                                                      anchor = get(options, :anchor, :bottom_right),
                                                                      theme, background...),
                                  log = log, fold_typing = true)
end

get_wrapper_layers(::Val{:gesture_log}) = (:container => 90,)
