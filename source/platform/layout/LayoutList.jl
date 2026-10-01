# Fragment of `LayoutModule`.
#
# The list form of a vertical and of a horizontal layout: `children` is a
# `ListNode`, and the layout draws the children that a viewport shows and no
# others.
#
# **The head is the anchor.** The canvas is walked both ways from its head:
# `prev` up, or to the left, until a child is past the near edge of the
# viewport, and `next` down, or to the right, until one is past the far edge. So
# `children[k]` counts from the head: the head is child 1, and a child reached
# through `prev` has an index of 0 or less. That is the arithmetic that
# `ListNode` answers to `getindex`.
#
# **A child is built when the walk reaches it**, through the recursion. The
# canvas list mirrors the document list node for node, and it keeps each child
# that it built until the head changes.
#
# **What a list needs.** The main axis has no weight, because a weight divides
# an offered extent by a count and a list has none. The cross axis needs an
# extent that no child decides: a `Fixed` policy of the layout, or the extent
# that the parent offers, because a child that is not built can not be measured.
#
# **What the layout reports.** Its extent on the cross axis, and none on the
# main axis: a list has no extent there, so the layout belongs in a
# `WidgetScrollPane`, which stops at the ends of a list that ends.

# What the printer of a list keeps for its readers: the children built so far,
# by their index from the head, and the canvas list that it draws from.
mutable struct LayoutListState
    axis::Symbol                                # :y down a column, :x along a row
    built::Dict{Int,Tuple{Cell,Cell,Any}}       # index from the head => (x, y, child iomap)
    head::Cell                                  # the canvas node of the head, or nothing
end

@iomap struct LayoutListIoMap
    projection::Any
    input::Any
    output::Any
    state::Any
end

const _LinearLayoutToGraphicsCanvas =
    Union{VerticalLayoutToGraphicsCanvas, HorizontalLayoutToGraphicsCanvas}

# ── What a list needs, said before anything is drawn ─────────────────────────

function _check_layout_list(doc, axis::Symbol)
    main_default = getfield(doc, axis === :y ? :child_height : :child_width)[]
    main_default isa SizePolicy && main_default.weight !== nothing && main_default.weight > 0 &&
        error(nameof(typeof(doc)), ": a weight divides an offered extent by a count, and a ",
              "list of children has none; give the children Fixed or Content")
    nothing
end

# The extent of the layout on its cross axis: a `Fixed` policy of the layout, or
# the edge that the parent offers. A child that is not built can not be
# measured, so no child decides it.
function _get_layout_list_cross_extent(doc, ctx, axis::Symbol)
    cross_default = getfield(doc, axis === :y ? :child_width : :child_height)[]
    preferred = cross_default isa SizePolicy ? cross_default.preferred : nothing
    preferred !== nothing && cross_default.weight == 0 && return Cell(Int32(preferred))
    edge = ctx === nothing ? nothing : (axis === :y ? ctx.maximum_width : ctx.maximum_height)
    edge !== nothing && return Cell(@computation Int32(Int(edge[])))
    error(nameof(typeof(doc)), ": a layout of a list needs its ",
          axis === :y ? "width" : "height",
          ": a Fixed ", axis === :y ? "child_width" : "child_height",
          " or an extent that the parent offers")
end

# The range that a child of a list gets on the main axis: its `Fixed` extent
# exactly, and else no offer, because the room of a list is not known.
function _get_layout_list_main_context(cctx, child, doc, axis::Symbol)
    main = axis === :y ? :y : :x
    default = getfield(doc, axis === :y ? :child_height : :child_width)[]
    preferred = layout_preferred(child, main, 0; default)
    preferred > 0 || return withhold_offer(cctx, main)
    axis === :y ? with_exact_size(cctx; height = Cell(Int32(preferred))) :
                  with_exact_size(cctx; width = Cell(Int32(preferred)))
end

# ── The printer ──────────────────────────────────────────────────────────────

# Print a `VerticalLayout` (`axis = :y`) or a `HorizontalLayout` (`axis = :x`)
# whose `children` is a `ListNode`. The canvas has the layout's extent on the
# cross axis and none on the main axis, and its elements are a list that the
# renderer walks from the head and stops in.
function _print_layout_list(p, recursion, doc, ctx, axis::Symbol)
    _check_layout_list(doc, axis)
    cross = _get_layout_list_cross_extent(doc, ctx, axis)
    state = LayoutListState(axis, Dict{Int,Tuple{Cell,Cell,Any}}(), Cell(nothing))
    # A new head in `children` drops every child built and starts again, and a
    # layout whose children are no list draws nothing.
    set_cell_computation!(state.head, () -> begin
        list = doc.children
        empty!(state.built)
        list isa ListNode ?
            _make_layout_list_node(recursion, doc, ctx, state, cross, 1, list, nothing, nothing) :
            nothing
    end)
    elements = Cell(@computation begin
        head = state.head[]
        head === nothing ? CellVector() : head
    end)
    width, height = axis === :y ? (cross, Cell(Int32(0))) : (Cell(Int32(0)), cross)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), width, height, elements,
                            axis === :y ? layout_vertical : layout_horizontal, false,
                            Cell(nothing))
    LayoutListIoMap(p, doc, canvas, state)
end

# The canvas node of child `k`. `before` is the canvas node of child `k - 1` when
# this child was reached from it, `after` that of child `k + 1` when it was
# reached from there; the head has neither and sits at zero. The neighbours are
# built when first read, and each links back, so a walk forth and back meets the
# same nodes.
function _make_layout_list_node(recursion, doc, ctx, state::LayoutListState, cross::Cell,
                                k::Int, document_node::ListNode, before, after)
    axis = state.axis
    child = document_node.value
    cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [k]))
    cctx = _get_layout_list_main_context(cctx, child, doc, axis)
    cctx = make_cross_axis_context(cctx, child, axis === :y ? :x : :y,
                          getfield(doc, axis === :y ? :child_width : :child_height)[])
    cim = _recurse_child(recursion, child, cctx)
    output = cim.output isa GraphicsDocument ? cim.output : _empty_canvas()
    width = Cell(@computation Int32(_child_w(cim)))
    height = Cell(@computation Int32(_child_h(cim)))
    gap = getfield(doc, :gap)
    align = getfield(doc, axis === :y ? :horizontal_align : :vertical_align)
    # The main axis: from the neighbour it was reached from.
    main = if before !== nothing
        before_canvas = before.value
        axis === :y ?
            Cell(@computation Int32(Int(before_canvas.y) + Int(before_canvas.h) + Int(gap[]))) :
            Cell(@computation Int32(Int(before_canvas.x) + Int(before_canvas.w) + Int(gap[])))
    elseif after !== nothing
        after_canvas = after.value
        axis === :y ?
            Cell(@computation Int32(Int(after_canvas.y) - Int(height[]) - Int(gap[]))) :
            Cell(@computation Int32(Int(after_canvas.x) - Int(width[]) - Int(gap[])))
    else
        Cell(Int32(0))
    end
    # The cross axis: aligned inside the extent of the layout.
    own_cross = axis === :y ? width : height
    cross_position = Cell(@computation Int32(_get_layout_list_align_offset(
        Symbol(align[]), Int(cross[]), Int(own_cross[]))))
    x_cell, y_cell = axis === :y ? (cross_position, main) : (main, cross_position)
    # The wrapper states the extent of the child, so a walk that stops at an
    # edge, and a pane that stops at an end, read it without the child.
    wrapper = GraphicsCanvas(x_cell, y_cell, width, height,
                             CellVector(Cell[Cell(output)]), layout_none, true, Cell(nothing))
    state.built[k] = (x_cell, y_cell, cim)
    node = ListNode(wrapper)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = document_node.next
        following === nothing && return nothing
        next_node = _make_layout_list_node(recursion, doc, ctx, state, cross, k + 1,
                                           following, node, nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = document_node.prev
        preceding === nothing && return nothing
        prev_node = _make_layout_list_node(recursion, doc, ctx, state, cross, k - 1,
                                           preceding, nothing, node)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# Where a child `extent` long sits in a cross extent `total` long.
_get_layout_list_align_offset(align::Symbol, total::Int, extent::Int) =
    align in (:center,) ? max(0, div(total - extent, 2)) :
    align in (:right, :bottom) ? max(0, total - extent) : 0

# ── The children the walk has built ──────────────────────────────────────────

# The entry `(x, y, child iomap)` of child `k`, walked to from the head and built
# on the way, or `nothing` when the list ends before it.
function _find_layout_list_child(state::LayoutListState, k::Int)
    node = state.head[]
    node isa ListNode || return nothing
    for _ in 1:abs(k - 1)
        node = k >= 1 ? node.next : node.prev
        node === nothing && return nothing
    end
    get(state.built, k, nothing)
end

# The index of the child under `(x, y)`, walking from the head toward the point
# along the main axis, or `nothing` when no child is there.
function _find_layout_list_index_at(state::LayoutListState, x::Int, y::Int)
    node = state.head[]
    node isa ListNode || return nothing
    along = state.axis === :y ? y : x
    start(canvas) = Int(state.axis === :y ? canvas.y : canvas.x)
    extent(canvas) = Int(state.axis === :y ? canvas.h : canvas.w)
    k = 1
    if along < start(node.value)
        while along < start(node.value)
            node = node.prev
            node === nothing && return nothing
            k -= 1
        end
    else
        while along >= start(node.value) + extent(node.value)
            node = node.next
            node === nothing && return nothing
            k += 1
        end
    end
    along >= start(node.value) ? k : nothing
end

# ── Reference mapping ────────────────────────────────────────────────────────

# `children[k] + rest`, with `k` counted from the head, or `(nothing, nothing)`.
function _split_layout_list_reference(reference)
    reference isa ConcreteReference || return (nothing, nothing)
    head = reference.head
    (head isa FieldReferenceStep && head.name == "children") || return (nothing, nothing)
    rest = reference.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return (nothing, nothing)
    (rest.head.start + 1, rest.tail)
end

# The output reference of node `k` of a canvas list, counted from its head as the
# document list is, followed by `below`.
_make_list_node_reference(k::Int, below::Reference) =
    ConcreteReference(FieldReferenceStep("elements"),
                      ConcreteReference(RangeReferenceStep(k - 1, k), below))

# `inner` inside the wrapper that holds one drawn child as its one element.
_make_wrapped_reference(inner::Reference) =
    ConcreteReference(FieldReferenceStep("elements"),
                      ConcreteReference(RangeReferenceStep(0, 1), inner))

# `children[k] + rest` maps to the node that draws child `k`: the wrapper of the
# child is node `k` of the canvas list, and it holds the child's output as its one
# element. The empty reference is the layout itself, whose image is its canvas.
function map_reference_forward(::_LinearLayoutToGraphicsCanvas, iomap::LayoutListIoMap, reference)
    strip_reference_types(reference) isa EmptyReference && return EmptyReference()
    k, rest = _split_layout_list_reference(reference)
    k === nothing && return nothing
    entry = _find_layout_list_child(iomap.state, k)
    entry === nothing && return nothing
    cim = entry[3]
    cim.output isa GraphicsDocument || return nothing
    inner = map_reference_forward(cim.projection, cim, rest)
    inner === nothing && return nothing
    _make_list_node_reference(k, _make_wrapped_reference(inner))
end

# A path into the canvas of a list goes through nodes that name no child by a
# fixed index, so it maps to no path into the document.
map_reference_backward(::_LinearLayoutToGraphicsCanvas, ::LayoutListIoMap, reference) = nothing

# ── Reading ──────────────────────────────────────────────────────────────────

# A pointer event goes to the child under the pointer, and a key to the child
# that the selection of the layout names. The answer is rooted at `children[k]`.
function read_intent(::_LinearLayoutToGraphicsCanvas, iomap::LayoutListIoMap, evt)
    state = iomap.state
    k = if hasproperty(evt, :x) && hasproperty(evt, :y)
        _find_layout_list_index_at(state, Int(evt.x), Int(evt.y))
    else
        _find_selected_layout_list_index(iomap.input)
    end
    k === nothing && return read_container_gesture(nothing, evt, iomap.input)
    entry = _find_layout_list_child(state, k)
    entry === nothing && return read_container_gesture(nothing, evt, iomap.input)
    answer = hasproperty(evt, :x) && hasproperty(evt, :y) ?
        _read_layout_list_pointer(entry, evt) :
        read_intent(entry[3].projection, entry[3], evt)
    answer = answer isa Operation ? _reroot_into_child(iomap.input, answer, k) : nothing
    read_container_gesture(answer, evt, iomap.input; steps = _get_layout_child_steps(k))
end

# The pointer event in the frame of the child, read by the child, with a
# position in the answer shifted back into the frame of the layout.
function _read_layout_list_pointer(entry, evt)
    point = _find_child_point(entry, Int(evt.x), Int(evt.y); bounded = true)
    point === nothing && return nothing
    local_event = _translate_layout_list_event(evt, point...)
    local_event === nothing && return nothing
    shift_operation_position(read_child_event(last(entry), local_event),
                             Int(evt.x) - point[1], Int(evt.y) - point[2])
end

_translate_layout_list_event(evt::MouseClick, x, y) =
    MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseScroll, x, y) =
    MouseScroll(evt.dx, evt.dy, x, y, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseMove, x, y) =
    MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseEnter, x, y) =
    MouseEnter(x, y, evt.buttons, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseLeave, x, y) =
    MouseLeave(x, y, evt.buttons, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseDown, x, y) =
    MouseDown(evt.button, x, y, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseUp, x, y) =
    MouseUp(evt.button, x, y, evt.modifiers; time = evt.time)
_translate_layout_list_event(evt::MouseDwell, x, y) =
    shift_event_position(evt, x - evt.x, y - evt.y)
_translate_layout_list_event(evt, x, y) = nothing

# The child that the selection names as `children[k]`, or `nothing`.
function _find_selected_layout_list_index(doc)
    selection = getfield(doc, :selection)[]
    k, _ = _split_layout_list_reference(selection)
    k
end
