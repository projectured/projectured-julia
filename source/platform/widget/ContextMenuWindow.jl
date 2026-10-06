# Fragment of `WidgetModule` — the wrapper at the screen that keeps the context
# menu window.

# What the context menu window shows: the first `shown` of `layers`, the
# `(title, menu)` pairs of an `OpenContextMenuOperation`, the nearest part first.
# One layer is the menu of its part as it is. More layers are one `WidgetMenu`
# with the items of each layer in their order: a separator stands between two
# layers, and each layer starts with a mark that names its part, a disabled item
# with the title.
function _make_context_menu_content(layers, shown::Int)
    shown == 1 && return last(first(layers))
    elements = Any[]
    for index in 1:shown
        title, menu = layers[index]
        index > 1 && push!(elements, WidgetSeparator())
        push!(elements, WidgetMenuItem(title; enabled = false))
        menu isa WidgetMenu ? append!(elements, collect(menu.elements)) :
                              push!(elements, menu)
    end
    WidgetMenu(elements)
end

"""
    ContextMenuWindowState(; content)

The state of the context menu window, around `content`. A view state operation
writes each field, so a history does not record it:

- `layers` — the `(title, menu)` pairs of the open menu, the nearest part first;
- `shown` — how many layers the window shows; `0` when no menu is open;
- `source` — the path of the part that the menu belongs to, from the state,
  through `content`;
- `window` — the `OpenWindowOperation` that opened the window last, which F2 and
  Shift+F2 open again with other content (`show_window_layers`).
"""
@document struct ContextMenuWindowState <: Document
    content::Document
    layers::Any = Tuple{String,Document}[]
    shown::Int = 0
    source::Any = nothing
    window::Any = nothing
end

get_wrapped_document(state::ContextMenuWindowState) = get_wrapped_document(state.content)

"""
    ContextMenuWindowProjection(; inner, id = :widget_popup, theme = nothing)

Show the content of a [`ContextMenuWindowState`](@ref) through `inner`, and keep
the context menu window: the one place that opens it, because a window belongs
to the screen.

**Opening.** The meaning is not here: a part answers a right click with an
[`OpenContextMenuOperation`](@ref) from its own gesture table
([`make_context_menu_binding`](@ref)), and each part around it adds its menu.
This projection takes that operation out of the answer and opens a popup window
with the nearest menu at the point of the click, in screen coordinates. A
command that runs the binding answers with no point, and the window opens below
the part, with the left edges aligned (`find_part_place`), so it does not cover
the part, `item_gap` below it. The window takes the extent of the menu, up to
the `context_menu_maximum_size` of the widget theme. `theme` is a `WidgetTheme`,
scaled or not, or `nothing` for the default theme; the projection holds the
maximum size and the item gap that it reads from it, and reads them each time it
opens a window.

**Closing.** The window is a popup that dismisses itself, with the id of the
popups of the widgets, `:widget_popup`. So the window manager closes it on a
press in another window, on Escape and on the loss of the focus, and a choice of
an item closes it, because an item closes `:widget_popup`. This projection
forgets its layers when the window is gone.

**More and fewer.** F2 shows the menu of the next part outward, and Shift+F2 one
fewer. While more than one menu shows, each starts with a mark that names its
part, and a separator stands between two of them. The state document declares
both keys in its gesture table, so the gesture help lists them.

**Keys.** The window is a popup, so the window under it keeps the focus. While
the window is open, a key of that window goes first to the content of the
menu, after F2 and Shift+F2: a menu that answers a key, such as a list that a
person types into, takes it, and a key that the menu does not answer goes on.

Sit it around the screen, inside the gesture tracker, as the tooltip window
sits. The screen gives the right click to the part at its point.
"""
struct ContextMenuWindowProjection <: Projection
    inner::Projection
    id::Symbol
    maximum_size::Any       # the largest size of a menu, a `Point2D` or a cell of one
    item_gap::Any           # between the part and a menu below it, a number or a cell
end

ContextMenuWindowProjection(; inner::Projection, id::Symbol = :widget_popup,
                              theme = nothing) =
    ContextMenuWindowProjection(inner, id, get_widget_style(theme, :context_menu_maximum_size),
                                get_widget_style(theme, :item_gap))

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct ContextMenuWindowIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

ProjectionModule.get_child_iomaps(iomap::ContextMenuWindowIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::ContextMenuWindowProjection, recursion,
                        input::ContextMenuWindowState, ctx)
    child = make_reconciled_child_iomap_cell(() -> input.content,
                                  content -> print_document(p.inner, recursion, content,
                                                            ctx))
    ContextMenuWindowIoMap(p, input, Cell(@computation child[].output), child)
end

# ── The keys of an open menu ──────────────────────────────────────────────

# F2 shows one more menu and Shift+F2 one fewer, while the menu window is open.
get_document_gesture_bindings_own(::Type{ContextMenuWindowState}) =
    make_window_layer_bindings(_make_context_menu_content; domain = "context menu")

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::ContextMenuWindowProjection, recursion, change::Intent,
                     iomap::ContextMenuWindowIoMap)
    change.route === nothing || return _read_routed_menu(p, recursion, change, iomap)
    input = change.gesture
    state = iomap.input
    event = input isa WindowInput ? input.event : nothing
    if event !== nothing && _is_menu_window_open(state)
        own = read_bound_gesture(state, event, nothing)
        own === nothing || return Intent(input, own)
        key = _read_menu_key(p, recursion, iomap, input)
        key === nothing ||
            return Intent(input, _join_menu_operations(key, _is_menu_window_open(state) ? nothing :
                                                            _forget_context_menu(state)))
    end
    menu, rest = _take_context_menu(_read_menu_content(p, recursion, change, iomap))
    rest = _lift_menu_part_edits(p, recursion, iomap, rest)
    own = if menu !== nothing
        _open_menu_window(p, iomap, menu)
    elseif event !== nothing && state.shown > 0 && !_is_menu_window_open(state)
        _forget_context_menu(state)
    end
    Intent(input, _join_menu_operations(rest, own))
end

read_intent(p::ContextMenuWindowProjection, iomap::ContextMenuWindowIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# A key of the window under the open menu, read by the content of the menu window
# first: the window under it keeps the focus, so the menu gets no key of its own.
# The answer of the menu, with each edit of the part that it made lifted, or
# `nothing` when the menu does not answer the key, which then goes on. A key that
# closes the window, such as Escape or Return on a row, makes the state forget it.
function _read_menu_key(p::ContextMenuWindowProjection, recursion, iomap::ContextMenuWindowIoMap,
                        input::WindowInput)
    event = input.event
    menu = iomap.input.window.id
    (event isa Union{KeyDown, KeyPress} && input.window_id !== menu) || return nothing
    answer = _read_menu_content(p, recursion, Intent(WindowInput(menu, event)), iomap)
    answer isa Operation || return nothing
    _lift_menu_part_edits(p, recursion, iomap, answer)
end

# A change with a route, such as a command that runs a binding on a part with no
# pointer: a menu in the answer opens the window, as the answer to a click does.
function _read_routed_menu(p::ContextMenuWindowProjection, recursion, change::Intent,
                           iomap::ContextMenuWindowIoMap)
    answer = read_routed_child(recursion, change, iomap)
    answer isa Intent || return answer
    menu, rest = _take_context_menu(answer.operation)
    menu === nothing && return answer
    Intent(answer.gesture, _join_menu_operations(rest, _open_menu_window(p, iomap, menu)),
           answer.description, answer.domain, answer.route)
end

# `operation` with each edit of a part that an item of the menu made lifted from
# that part (`_lift_menu_part_edit`); an edit that no place lifts is dropped.
_lift_menu_part_edits(p::ContextMenuWindowProjection, recursion, iomap::ContextMenuWindowIoMap, operation) =
    operation
_lift_menu_part_edits(p::ContextMenuWindowProjection, recursion, iomap::ContextMenuWindowIoMap,
                      operation::EditMenuPartOperation) =
    _lift_menu_part_edit(p, recursion, iomap, operation)
function _lift_menu_part_edits(p::ContextMenuWindowProjection, recursion, iomap::ContextMenuWindowIoMap,
                               operation::CompoundOperation)
    members = Any[_lift_menu_part_edits(p, recursion, iomap, member) for member in operation.operations]
    CompoundOperation(Any[member for member in members if member !== nothing])
end

# The edit of the part that the menu belongs to, lifted from the part through the
# readers of the content, as an operation from the state: from the part outward,
# the first place from which the readers carry it, as `find_rooted_operation`
# looks, with the operation rerooted by the steps from that place to the part.
# `nothing` when no place does, or no menu has a part.
function _lift_menu_part_edit(p::ContextMenuWindowProjection, recursion, iomap::ContextMenuWindowIoMap,
                              edit::EditMenuPartOperation)
    source = iomap.input.source
    source isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(source))
    (isempty(steps) || steps[1] != FieldReferenceStep("content")) && return nothing
    steps = steps[2:end]
    for depth in length(steps):-1:1
        place = extend_reference(EmptyReference(), steps[1:depth]...)
        operation = reroot_operation(edit.operation, Tuple(steps[(depth + 1):end]))
        answer = read_intent(p.inner, recursion, Intent(nothing, operation, edit.description, "", place),
                             iomap.child_iomap)
        lifted = answer isa Intent ? answer.operation : answer
        lifted isa Operation && return reroot_operation(lifted, (FieldReferenceStep("content"),))
    end
    nothing
end

# The answer of the content to `change`, as an operation from the state.
function _read_menu_content(p::ContextMenuWindowProjection, recursion, change::Intent,
                            iomap::ContextMenuWindowIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

# Whether the screen that the state wraps holds the window that the state opened,
# with what the state put in it: a popup of another widget has the same id.
function _is_menu_window_open(state::ContextMenuWindowState)
    state.shown > 0 || return false
    opened = state.window
    screen = get_wrapped_document(state)
    hasproperty(screen, :windows) || return false
    any(window -> window isa WindowDocument && window.id === opened.id &&
                  window.content === opened.content,
        screen.windows)
end

# A write of one field of the state, which a history does not record.
_write_menu_state(state::ContextMenuWindowState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_menu_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# The menu in `answer`, and what is left of `answer` without it.
_take_context_menu(answer::OpenContextMenuOperation) = (answer, nothing)
_take_context_menu(answer::ReplaceViewStateOperation) =
    get_wrapped_operation(answer) isa OpenContextMenuOperation ?
        (get_wrapped_operation(answer), nothing) : (nothing, answer)
function _take_context_menu(answer::CompoundOperation)
    menu, rest = nothing, Any[]
    for operation in answer.operations
        found, left = _take_context_menu(operation)
        menu === nothing && found !== nothing && (menu = found)
        left === nothing || push!(rest, left)
    end
    menu, _join_menu_operations(rest...)
end
_take_context_menu(answer) = (nothing, answer)

# Open the window of `menu`, and keep what it shows. It stands at the point of
# the click; with no point, below the part with the left edges aligned and
# `item_gap` between them; with neither, at the corner of the screen.
function _open_menu_window(p::ContextMenuWindowProjection, iomap::ContextMenuWindowIoMap,
                           menu::OpenContextMenuOperation)
    state = iomap.input
    size = unwrap_cell(p.maximum_size)
    maximum_size = (Int(size.x[]), Int(size.y[]))
    x, y = if menu.point !== nothing
        menu.point
    else
        below = find_part_place(p, iomap, menu.source)
        below === nothing ? (0, 0) : (below[1], below[2] + unwrap_cell(p.item_gap))
    end
    window = OpenWindowOperation(; id = p.id, title = "context menu", x = x, y = y,
                                   width = maximum_size[1], height = maximum_size[2],
                                   maximum_size, style = :popup,
                                   auto_dismiss = true,
                                   content = _make_context_menu_content(menu.layers, 1))
    CompoundOperation(Any[_write_menu_state(state, "layers", menu.layers),
                          _write_menu_state(state, "shown", 1),
                          _write_menu_state(state, "source",
                                            strip_reference_types(menu.source)),
                          _write_menu_state(state, "window", window),
                          window])
end

# The window is gone, so the state forgets what it showed.
_forget_context_menu(state::ContextMenuWindowState) =
    CompoundOperation(Any[_write_menu_state(state, "layers", Tuple{String,Document}[]),
                          _write_menu_state(state, "shown", 0),
                          _write_menu_state(state, "source", nothing),
                          _write_menu_state(state, "window", nothing)])

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::ContextMenuWindowProjection,
                               iomap::ContextMenuWindowIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::ContextMenuWindowProjection,
                                iomap::ContextMenuWindowIoMap, reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end

# ── The wrapper ───────────────────────────────────────────────────────────

"""
    make_context_menu_window_document(document) -> ContextMenuWindowState

Wrap `document` in the state of the context menu window. The selection of
`document` becomes the selection of the wrapper, through its `content` field.
"""
function make_context_menu_window_document(document)
    state = ContextMenuWindowState(; content = document)
    inner = get_selection(document)
    inner === nothing && return state
    content = ConcreteReference(FieldReferenceStep("content"), EmptyReference())
    replace_selection!(state, concat_references(content, strip_reference_types(inner)))
    state
end

"""
    make_context_menu_window_projection(projection; keywords...)
        -> ContextMenuWindowProjection

The projection half of the same wrapper: `projection` shows the content. The
keywords are those of [`ContextMenuWindowProjection`](@ref).
"""
make_context_menu_window_projection(projection; keywords...) =
    ContextMenuWindowProjection(; inner = projection, keywords...)

"""
    wrap_context_menu_window(document, projection; theme = nothing) -> (document, projection)

Both halves at once, the shape that `make_tracking_screen` takes in its list of
`inner_wrappers`. `theme` is the scaled `WidgetTheme` of the window.

Use it to open the menu of the part under the pointer on a right click, in a
window of its own, in every window of the screen.

# Example

    wrappers = [wrap_tooltip_window, wrap_context_menu_window]
    build_editor(document, projection; backend, window = (; inner_wrappers = wrappers))

See also `wrap_tooltip_window`, the wrapper of the tooltip window.
"""
wrap_context_menu_window(document, projection; theme = nothing) =
    (make_context_menu_window_document(document),
     make_context_menu_window_projection(projection; theme))

"""
    context_menu = true

The wrapper of `build_editor` that keeps the context menu window of the screen.
It gives [`wrap_context_menu_window`](@ref) to the wrapper of the window, which
puts it around the screen, inside the trackers and outside the tooltip window,
with the `WidgetTheme` of the appearance of the editor. It is on by default, and `context_menu = false` leaves an editor with no context
menu window.
"""
function wrap_editor!(::Val{:context_menu}, layer::Symbol, argument, parts::EditorParts)
    appearance = get(parts.arguments, :appearance, nothing)
    theme = appearance === nothing ? nothing : get_scaled_theme!(appearance, WidgetTheme)
    push!(parts.window_wrappers,
          (document, projection) -> wrap_context_menu_window(document, projection; theme))
    parts
end

get_wrapper_layers(::Val{:context_menu}) = (:window => -10,)
is_wrapper_default(::Val{:context_menu}) = true
