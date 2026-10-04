# Fragment of `TooltipModule` — the wrapper that keeps the tooltip window.

"""
    TooltipWindowState(; content)

The state of the tooltip window, around `content`. A view state operation writes
each field, so a history does not record it:

- `layers` — the `(title, content)` pairs of the open tooltip, the nearest part
  first;
- `shown` — how many layers the window shows; `0` when no tooltip is open;
- `source` — the path of the part that the tooltip describes, from `content`;
- `window` — the `OpenWindowOperation` that opened the window last, which F2 and
  Shift+F2 open again with other content (`show_window_layers`).
"""
@document struct TooltipWindowState <: Document
    content::Document
    layers::Any = Tuple{String,Document}[]
    shown::Int = 0
    source::Any = nothing
    window::Any = nothing
end

get_wrapped_document(state::TooltipWindowState) = get_wrapped_document(state.content)

"""
    TooltipWindowProjection(; inner, id = :tooltip, theme = nothing, title = "tooltip")

Show the content of a [`TooltipWindowState`](@ref) through `inner`, and keep the
tooltip window: the one place that opens and closes it, because a window belongs
to the screen, and no part can close its own tooltip when the pointer goes to
another part.

**Opening.** The meaning is not here: a part answers a dwell with an
[`OpenTooltipOperation`](@ref) from its own gesture table, and each part around it
adds its layer. This projection takes that operation out of the answer and opens
the window with the nearest layer, at the `offset` of the [`TooltipTheme`](@ref)
from the point where the pointer rested, in screen coordinates. A command that
runs the binding answers with no point, and the window opens below the part, with
the left edges aligned and the `part_gap` between them (`find_part_place`), so it
does not cover the part. The window is printed at the `maximum_size` of the theme
and ends with the extent of what it holds, never smaller than its `minimum_size`.
`theme` is a `TooltipTheme`, scaled or not, or `nothing` for the default theme;
the projection holds the offset, the part gap and the two sizes that it reads from
it, and reads them each time it opens a window.

**Closing.** While a tooltip is open, a move of the pointer off the part closes it
(the point is mapped backward, and the path no longer passes through the part),
and so do Escape, which it takes, a press, a scroll and the leave of a window.
Any other key passes on and leaves it open, so a person can type while it shows.

**More and fewer.** F2 shows the next layer outward, and Shift+F2 one fewer. The
state document declares both keys in its gesture table, so the gesture help lists
them.

Sit it around the screen, inside the gesture tracker. The screen gives the dwell
to the part at its point.
"""
struct TooltipWindowProjection <: Projection
    inner::Projection
    id::Symbol
    title::String
    offset::Any             # from the point of the pointer, a `Point2D` or a cell of one
    part_gap::Any           # between the part and a tooltip below it, a number or a cell
    minimum_size::Any       # of the window, a `Point2D` or a cell of one
    maximum_size::Any       # of the window, a `Point2D` or a cell of one
end

TooltipWindowProjection(; inner::Projection, id::Symbol = :tooltip, theme = nothing,
                          title::AbstractString = "tooltip") =
    TooltipWindowProjection(inner, id, String(title), get_tooltip_style(theme, :offset),
                            get_tooltip_style(theme, :part_gap),
                            get_tooltip_style(theme, :minimum_size),
                            get_tooltip_style(theme, :maximum_size))

# The two numbers of a point of a theme.
_get_pair(point::Point2D) = (Int(point.x[]), Int(point.y[]))

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct TooltipWindowIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::TooltipWindowIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::TooltipWindowProjection, recursion, input::TooltipWindowState, ctx)
    child = make_reconciled_child_iomap_cell(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    TooltipWindowIoMap(p, input, Cell(@computation child[].output), child)
end

# ── The keys of an open tooltip ───────────────────────────────────────────

# F2 shows one more layer and Shift+F2 one fewer, while a tooltip is open.
get_document_gesture_bindings_own(::Type{TooltipWindowState}) =
    make_window_layer_bindings(_make_tooltip_content; domain = "tooltip")

_make_tooltip_content(layers, shown::Int) =
    TooltipContent(; layers = layers, shown = shown)

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::TooltipWindowProjection, recursion, change::Intent,
                     iomap::TooltipWindowIoMap)
    change.route === nothing || return _read_routed(p, recursion, change, iomap)
    input = change.gesture
    state = iomap.input
    event = input isa WindowInput ? input.event : nothing
    if state.shown > 0 && event !== nothing
        own = read_bound_gesture(state, event, nothing)
        own === nothing || return Intent(input, own)
        _is_plain_escape(event) && return Intent(input, _close_tooltip(p, state))
    end
    content = _read_content(p, recursion, change, iomap)
    tooltip, rest = _take_tooltip(content)
    own = if tooltip !== nothing
        _open_tooltip(p, iomap, tooltip)
    elseif state.shown > 0 && event !== nothing && _closes_tooltip(p, iomap, input)
        _close_tooltip(p, state)
    end
    Intent(input, _join_operations(rest, own))
end

read_intent(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# A change with a route, such as a command that runs a binding on a part with no
# pointer: a tooltip in the answer opens the window, as the answer to a dwell does.
function _read_routed(p::TooltipWindowProjection, recursion, change::Intent,
                      iomap::TooltipWindowIoMap)
    answer = read_routed_child(recursion, change, iomap)
    answer isa Intent || return answer
    tooltip, rest = _take_tooltip(answer.operation)
    tooltip === nothing && return answer
    Intent(answer.gesture, _join_operations(rest, _open_tooltip(p, iomap, tooltip)),
           answer.description, answer.domain, answer.route)
end

_is_plain_escape(event) =
    event isa KeyDown && event.key === :escape && event.modifiers == ModifierKeys()

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::TooltipWindowProjection, recursion, change::Intent,
                       iomap::TooltipWindowIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

# A write of one field of the state, which a history does not record.
_write_state(state::TooltipWindowState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# The tooltip in `answer`, and what is left of `answer` without it.
_take_tooltip(answer::OpenTooltipOperation) = (answer, nothing)
_take_tooltip(answer::ReplaceViewStateOperation) =
    get_wrapped_operation(answer) isa OpenTooltipOperation ? (get_wrapped_operation(answer), nothing) :
                                                             (nothing, answer)
function _take_tooltip(answer::CompoundOperation)
    tooltip, rest = nothing, Any[]
    for operation in answer.operations
        found, left = _take_tooltip(operation)
        tooltip === nothing && found !== nothing && (tooltip = found)
        left === nothing || push!(rest, left)
    end
    tooltip, (isempty(rest) ? nothing : length(rest) == 1 ? rest[1] : CompoundOperation(rest))
end
_take_tooltip(answer) = (nothing, answer)

# Open the window of `tooltip`, and keep what it shows. It stands `offset` from
# the point where the pointer rested; with no point, below the part with the left
# edges aligned and `part_gap` between them; with neither, at the corner.
function _open_tooltip(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, tooltip::OpenTooltipOperation)
    state = iomap.input
    offset = _get_pair(unwrap_cell(p.offset))
    minimum_size = _get_pair(unwrap_cell(p.minimum_size))
    maximum_size = _get_pair(unwrap_cell(p.maximum_size))
    x, y = if tooltip.point !== nothing
        (tooltip.point[1] + offset[1], tooltip.point[2] + offset[2])
    else
        below = find_part_place(p, iomap, tooltip.source)
        below === nothing ? offset : (below[1], below[2] + Int(unwrap_cell(p.part_gap)))
    end
    window = OpenWindowOperation(; id = p.id, title = p.title, x = x, y = y,
                                   width = maximum_size[1], height = maximum_size[2],
                                   minimum_size, maximum_size,
                                   style = :tooltip,
                                   content = _make_tooltip_content(tooltip.layers, 1))
    CompoundOperation(Any[_write_state(state, "layers", tooltip.layers),
                          _write_state(state, "shown", 1),
                          _write_state(state, "source", strip_reference_types(tooltip.source)),
                          _write_state(state, "window", window),
                          window])
end

function _close_tooltip(p::TooltipWindowProjection, state::TooltipWindowState)
    CompoundOperation(Any[_write_state(state, "layers", Tuple{String,Document}[]),
                          _write_state(state, "shown", 0),
                          _write_state(state, "source", nothing),
                          _write_state(state, "window", nothing),
                          CloseWindowOperation(p.id)])
end

# Whether `input` closes the open tooltip: a press, a scroll, the leave of a
# window, and a move whose point is off the part the tooltip describes.
function _closes_tooltip(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, input::WindowInput)
    event = input.event
    event isa Union{MouseDown,MouseClick,MouseScroll,WindowLeave} && return true
    event isa MouseMove || return false
    path = _find_path_at(p, iomap, input.window_id, event.x, event.y)
    source = iomap.input.source
    path === nothing || source === nothing ||
        !(path == source || is_reference_prefix(source, path))
end

# The path, from the state, of the part at `(x, y)` of the window `window`, or
# `nothing`, as the source of a tooltip is. The screen is the document that the
# content wraps.
function _find_path_at(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, window, x::Int, y::Int)
    screen = get_wrapped_document(iomap.input)
    hasproperty(screen, :windows) || return nothing
    for (index, candidate) in enumerate(screen.windows)
        candidate.id === window || continue
        point = extend_reference(EmptyReference(), FieldReferenceStep("windows"),
                                 ElementReferenceStep(index), FieldReferenceStep("content"),
                                 PointReferenceStep(x, y))
        answer = map_reference_backward(p, iomap, point)
        return answer === nothing ? nothing : strip_reference_types(answer)
    end
    nothing
end

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::TooltipWindowProjection, iomap::TooltipWindowIoMap, reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end

# ── The wrapper ───────────────────────────────────────────────────────────

"""
    make_tooltip_window_document(document) -> TooltipWindowState

Wrap `document` in the state of the tooltip window. The selection of `document`
becomes the selection of the wrapper, through its `content` field.
"""
function make_tooltip_window_document(document)
    state = TooltipWindowState(; content = document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(state,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    state
end

"""
    make_tooltip_window_projection(projection; keywords...) -> TooltipWindowProjection

The projection half of the same wrapper: `projection` shows the content. The
keywords are those of [`TooltipWindowProjection`](@ref).
"""
make_tooltip_window_projection(projection; keywords...) =
    TooltipWindowProjection(; inner = projection, keywords...)

"""
    wrap_tooltip_window(document, projection; theme = nothing) -> (document, projection)

Both halves at once, the shape that `make_tracking_screen` takes in its list of
`inner_wrappers`. `theme` is the `TooltipTheme` of the window, scaled or not.
"""
wrap_tooltip_window(document, projection; theme = nothing) =
    (make_tooltip_window_document(document), make_tooltip_window_projection(projection; theme))

"""
    tooltip = true

The wrapper of `build_editor` that keeps the tooltip window of the screen. It
gives [`wrap_tooltip_window`](@ref) to the wrapper of the window, which puts it
around the screen, inside the trackers, with the `TooltipTheme` of the appearance
of the editor. It is on by default, and `tooltip = false` leaves an editor with
no tooltip window.
"""
function wrap_editor!(::Val{:tooltip}, layer::Symbol, argument, parts::EditorParts)
    appearance = get(parts.arguments, :appearance, nothing)
    theme = appearance === nothing ? nothing : get_scaled_theme!(appearance, TooltipTheme)
    push!(parts.window_wrappers, (document, projection) -> wrap_tooltip_window(document, projection; theme))
    parts
end

get_wrapper_layers(::Val{:tooltip}) = (:window => -20,)
is_wrapper_default(::Val{:tooltip}) = true
