"""
    ScreenToScreenModule

The screen-domain projection. `ScreenToScreen` owns *all* structural knowledge
of the screen domain — `ScreenDocument` and `WindowDocument` — so that the
domain-independent `CopyingProjection` need not. It:

- copies the `ScreenDocument` shell, recursing each window through itself;
- copies a `WindowDocument`'s metadata verbatim and recurses its `content`
  through the outer pipeline (`recursion`), seeding the window's
  `width`/`height` as the available layout extent so layout-aware content
  sizes itself to the window;
- on the reader side, routes an `EventEnvelope` to the matching window by
  `window_id`, hands the inner event to that window's `content` reader, and
  prepends the `windows[i].content` steps to the operation that comes back.

`ScreenToScreen` is normally the `inner` of a `WindowManagerProjection`, which
layers window-management *operations* (open/close/resize) on top. The two are
separate concerns: structural projection here, operation interception there.
"""
module ScreenToScreenModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change, as_change
import ..ReactiveModule: Cell
import ..ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope
import ..CollectionModule: CellVector
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference, ElementReference, PointReference, head, tail
import ..PrinterContextModule: PrinterContext, child_context, with_available_size
import ..IoMapApiModule: IoMap
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValue, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation

export ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap

struct ScreenToScreen <: Projection end

# ── IoMaps ──────────────────────────────────────────────────────────────────

struct ScreenToScreenIoMap <: IoMap
    projection::ScreenToScreen
    input::Any              # ScreenDocument
    output::Any             # ScreenDocument
    window_iomaps::Cell     # Vector of ScreenWindowIoMap, one per window
end

struct ScreenWindowIoMap <: IoMap
    projection::ScreenToScreen
    input::Any              # WindowDocument
    output::Any             # WindowDocument
    content_iomap::Any      # iomap of the recursively-projected content
end

# ── Printer ─────────────────────────────────────────────────────────────────

function projection_print(p::ScreenToScreen, recursion, input::ScreenDocument, ctx)
    iomap_cell = Cell(nothing)
    window_iomaps = Cell(() -> [
        projection_print(p, recursion, input.windows[i],
                         child_context(ctx, FieldReference("windows"), ElementReference(i)))
        for i in 1:length(input.windows)
    ])
    out_windows = Cell(() -> CellVector(Cell[Cell(im.output) for im in window_iomaps[]]))
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, input.selection)
    end)
    output = ScreenDocument(out_windows, sel)
    iomap = ScreenToScreenIoMap(p, input, output, window_iomaps)
    iomap_cell[] = iomap
    iomap
end

function projection_print(p::ScreenToScreen, recursion, input::WindowDocument, ctx)
    # Seed the window's pixel size as the available layout extent for its
    # content, so split/tabbed/scroll panes size to the window.
    content_ctx = with_available_size(child_context(ctx, FieldReference("content"));
                                      width=getfield(input, :width),
                                      height=getfield(input, :height))
    content_iomap = projection_printer_recurse(recursion, input.content, content_ctx)
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, input.selection)
    end)
    # Metadata cells are shared verbatim (as CopyingProjection does for
    # non-document fields); only content and selection are produced fresh.
    output = WindowDocument(getfield(input, :id), getfield(input, :title),
                            getfield(input, :x), getfield(input, :y),
                            getfield(input, :width), getfield(input, :height),
                            getfield(input, :bg), getfield(input, :style),
                            getfield(input, :auto_dismiss), getfield(input, :modal),
                            Cell(content_iomap.output), sel)
    iomap = ScreenWindowIoMap(p, input, output, content_iomap)
    iomap_cell[] = iomap
    iomap
end

# ── Reference mapping (order- and structure-preserving) ───────────────────────

_wval(v) = Int(v isa Cell ? v[] : v)

# Screen level: peel `windows` + `[i]`, delegate the tail to window `i`'s iomap.
# A coordinate image (`PointReference`) from the window — already in screen space
# (the window shifted it by its origin) — passes straight up; a structural path is
# re-rooted at `windows[i]` (coordinates accumulate, paths stay paths).
function _map_screen(fn, iomap::ScreenToScreenIoMap, reference)
    reference isa ConcreteReferencePath || return reference
    h = head(reference)
    (h isa FieldReference && h.name == "windows") || return reference
    rest1 = tail(reference)
    rest1 isa ConcreteReferencePath || return reference
    elem = head(rest1)
    elem isa RangeReference || return reference
    i = elem.stop                       # ElementReference(i) == RangeReference(i-1, i)
    ims = iomap.window_iomaps[]
    (i < 1 || i > length(ims)) && return nothing
    wim = ims[i]
    mapped = fn(wim.projection, wim, tail(rest1))
    mapped === nothing && return nothing
    mapped isa PointReference && return mapped
    ConcreteReferencePath(FieldReference("windows"), ConcreteReferencePath(elem, mapped))
end

# Window level: peel `content`, delegate the tail to the content iomap. A
# coordinate image (`PointReference`, the forward image of a positioned widget in
# the content's frame) is shifted by this window's screen origin so the popup
# resolver lands in screen space; a structural path is re-rooted at `content`.
function _map_window(fn, iomap::ScreenWindowIoMap, reference)
    reference isa ConcreteReferencePath || return reference
    h = head(reference)
    (h isa FieldReference && h.name == "content") || return reference  # metadata: identity
    cim = iomap.content_iomap
    mapped = fn(cim.projection, cim, tail(reference))
    mapped === nothing && return nothing
    if mapped isa PointReference
        return PointReference(_wval(getfield(iomap.input, :x)) + Int(mapped.x[]),
                              _wval(getfield(iomap.input, :y)) + Int(mapped.y[]))
    end
    ConcreteReferencePath(FieldReference("content"), mapped)
end

map_reference_forward(::ScreenToScreen, iomap::ScreenToScreenIoMap, reference) =
    _map_screen(map_reference_forward, iomap, reference)
map_reference_backward(::ScreenToScreen, iomap::ScreenToScreenIoMap, reference) =
    _map_screen(map_reference_backward, iomap, reference)
map_reference_forward(::ScreenToScreen, iomap::ScreenWindowIoMap, reference) =
    _map_window(map_reference_forward, iomap, reference)
map_reference_backward(::ScreenToScreen, iomap::ScreenWindowIoMap, reference) =
    _map_window(map_reference_backward, iomap, reference)

# ── Reader ────────────────────────────────────────────────────────────────────
# Route an EventEnvelope to the matching window's content, then prepend the
# steps that lead from the screen root to that content so the operation's path
# is rooted at the ScreenDocument.

function projection_read(p::ScreenToScreen, recursion, change::Change, iomap::ScreenToScreenIoMap)
    env = change.gesture
    if env isa EventEnvelope
        ims = iomap.window_iomaps[]
        for (i, wim) in enumerate(ims)
            win_in = wim.input
            win_in isa WindowDocument || continue
            win_in.id === env.window_id || continue
            inner = projection_read(wim.projection, recursion, change, wim)
            op = _prefix_op(inner.operation, (FieldReference("windows"), ElementReference(i)))
            return Change(change.gesture, op)
        end
        return Change(change.gesture, nothing)
    end
    # Non-envelope change (operation threaded up, or coordless gesture):
    # fall back to the generic per-reference mapping (selection/edit retarget).
    payload = change.operation === nothing ? change.gesture : change.operation
    return Change(change.gesture, projection_read(p, iomap, payload))
end

function projection_read(p::ScreenToScreen, recursion, change::Change, iomap::ScreenWindowIoMap)
    env = change.gesture
    if env isa EventEnvelope
        cim = iomap.content_iomap
        inner = projection_read(cim.projection, recursion, Change(env.event, nothing), cim)
        op = _prefix_op(inner.operation, (FieldReference("content"),))
        return Change(change.gesture, op)
    end
    payload = change.operation === nothing ? change.gesture : change.operation
    return Change(change.gesture, projection_read(p, iomap, payload))
end

# Prepend `steps` to the reference path inside `op` (if it carries one), rooting a
# child's operation at the ScreenDocument. Every path-carrying operation type must
# be handled here; an unhandled type would fall through unchanged and apply its
# child-relative path against the screen root (e.g. ReplaceDocumentOperation's
# `.slice` from the clipboard projection).
function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa StringReplaceRangeOperation
        return StringReplaceRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa NumberReplaceRangeOperation
        return NumberReplaceRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(_prepend(steps, op.path))
    elseif op isa ReplaceReferencedValue
        return op.document === nothing ?
            ReplaceReferencedValue(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        return CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
    else
        return op
    end
end

function _prepend(steps::Tuple, path::ReferencePath)
    result = path
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

end # module
