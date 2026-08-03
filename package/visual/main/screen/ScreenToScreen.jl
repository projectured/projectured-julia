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
- on the reader side, routes an `WindowInput` to the matching window by
  `window_id`, hands the inner event to that window's `content` reader, and
  prepends the `windows[i].content` steps to the operation that comes back.

`ScreenToScreen` is normally the `inner` of a `WindowManagingProjection`, which
layers window-management *operations* (open/close/resize) on top. The two are
separate concerns: structural projection here, operation interception there.
"""
module ScreenToScreenModule

import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..CellModule: Cell, ComputedCell
import ..ScreenDocumentModule: ScreenDocument, WindowDocument
import ..EventModule: WindowInput
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, RangeReferenceStep, ElementReferenceStep, head, tail
import ..PointReferenceStepModule: PointReferenceStep
import ..PrinterContextModule: PrinterContext, make_child_context, with_available_size
import ..IoMapModule: IoMap, reconcile_child_iomaps, reconcile_child_iomap, var"@iomap"
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation, CompoundOperation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation

export ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap

struct ScreenToScreen <: Projection end

# ── IoMaps ──────────────────────────────────────────────────────────────────

@iomap struct ScreenToScreenIoMap
    projection::ScreenToScreen
    input::Any              # ScreenDocument
    output::Any             # ScreenDocument
    window_iomaps::Cell     # Vector of ScreenWindowIoMap, one per window
end

@iomap struct ScreenWindowIoMap
    projection::ScreenToScreen
    input::Any              # WindowDocument
    output::Any             # WindowDocument
    content_iomap::Any      # iomap of the recursively-projected content
end

# ── Printer ─────────────────────────────────────────────────────────────────

function print_document(p::ScreenToScreen, recursion, input::ScreenDocument, ctx)
    iomap_cell = Cell(nothing)
    # Reconcile windows by identity so opening/closing a sibling reuses the
    # surviving windows' iomaps (AR-STABLE-IOMAP-IDENTITY).
    window_iomaps = reconcile_child_iomaps(
        () -> input.windows,
        (i, x) -> print_document(p, recursion, x,
            make_child_context(ctx, FieldReferenceStep("windows"), ElementReferenceStep(i))))
    out_windows = ComputedCell(() -> CellVector(Cell[Cell(im.output) for im in window_iomaps[]]))
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, input.selection)
    end)
    output = ScreenDocument(out_windows, sel)
    iomap = ScreenToScreenIoMap(p, input, output, window_iomaps)
    iomap_cell[] = iomap
    iomap
end

function print_document(p::ScreenToScreen, recursion, input::WindowDocument, ctx)
    # Seed the window's pixel size as the available layout extent for its
    # content, so split/tabbed/scroll panes size to the window.
    content_ctx = with_available_size(make_child_context(ctx, FieldReferenceStep("content"));
                                      width=getfield(input, :width),
                                      height=getfield(input, :height))
    # Reconcile the content by identity so replacing a same-id window's content
    # (a hover probe following the cursor, a re-opened tooltip) re-projects it
    # reactively; a same object mutated in place reuses the iomap and re-derives
    # through its own cells. This is what lets the window manager mutate only the
    # input screen and rely on this stage to mirror the output (AR-STABLE-IOMAP-IDENTITY).
    content_iomap = reconcile_child_iomap(() -> input.content,
                                          c -> print_child(recursion, c, content_ctx))
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, input.selection)
    end)
    # Metadata cells are shared verbatim (non-document fields), so a metadata edit on
    # the input window is reflected here through the shared cell; only content and
    # selection are produced fresh.
    output = WindowDocument(getfield(input, :id), getfield(input, :title),
                            getfield(input, :x), getfield(input, :y),
                            getfield(input, :width), getfield(input, :height),
                            getfield(input, :bg), getfield(input, :style),
                            getfield(input, :auto_dismiss), getfield(input, :modal),
                            ComputedCell(() -> content_iomap[].output), sel)
    iomap = ScreenWindowIoMap(p, input, output, content_iomap)
    iomap_cell[] = iomap
    iomap
end

# ── Reference mapping (order- and structure-preserving) ───────────────────────

_wval(v) = Int(v isa Cell ? v[] : v)

# Screen level: peel `windows` + `[i]`, delegate the tail to window `i`'s iomap.
# A coordinate image (`PointReferenceStep`) from the window — already in screen space
# (the window shifted it by its origin) — passes straight up; a structural path is
# re-rooted at `windows[i]` (coordinates accumulate, paths stay paths).
function _map_screen(fn, iomap::ScreenToScreenIoMap, reference)
    reference isa ConcreteReference || return reference
    h = head(reference)
    (h isa FieldReferenceStep && h.name == "windows") || return reference
    rest1 = tail(reference)
    rest1 isa ConcreteReference || return reference
    elem = head(rest1)
    elem isa RangeReferenceStep || return reference
    i = elem.stop                       # ElementReferenceStep(i) == RangeReferenceStep(i-1, i)
    ims = iomap.window_iomaps
    (i < 1 || i > length(ims)) && return nothing
    wim = ims[i]
    mapped = fn(wim.projection, wim, tail(rest1))
    mapped === nothing && return nothing
    mapped isa PointReferenceStep && return mapped
    ConcreteReference(FieldReferenceStep("windows"), ConcreteReference(elem, mapped))
end

# Window level: peel `content`, delegate the tail to the content iomap. A
# coordinate image (`PointReferenceStep`, the forward image of a positioned widget in
# the content's frame) is shifted by this window's screen origin so the popup
# resolver lands in screen space; a structural path is re-rooted at `content`.
function _map_window(fn, iomap::ScreenWindowIoMap, reference)
    reference isa ConcreteReference || return reference
    h = head(reference)
    (h isa FieldReferenceStep && h.name == "content") || return reference  # metadata: identity
    cim = iomap.content_iomap
    mapped = fn(cim.projection, cim, tail(reference))
    mapped === nothing && return nothing
    if mapped isa PointReferenceStep
        return PointReferenceStep(_wval(getfield(iomap.input, :x)) + Int(mapped.x[]),
                              _wval(getfield(iomap.input, :y)) + Int(mapped.y[]))
    end
    ConcreteReference(FieldReferenceStep("content"), mapped)
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
# Route an WindowInput to the matching window's content, then prepend the
# steps that lead from the screen root to that content so the operation's path
# is rooted at the ScreenDocument.

function read_intent(p::ScreenToScreen, recursion, change::Intent, iomap::ScreenToScreenIoMap)
    window_input = change.gesture
    if window_input isa WindowInput
        ims = iomap.window_iomaps
        for (i, wim) in enumerate(ims)
            win_in = wim.input
            win_in isa WindowDocument || continue
            win_in.id === window_input.window_id || continue
            inner = read_intent(wim.projection, recursion, change, wim)
            op = _prefix_op(inner.operation, (FieldReferenceStep("windows"), ElementReferenceStep(i)))
            return Intent(change.gesture, op)
        end
        return Intent(change.gesture, nothing)
    end
    # Non-window-input change (operation threaded up, or coordless gesture):
    # fall back to the generic per-reference mapping (selection/edit retarget).
    payload = change.operation === nothing ? change.gesture : change.operation
    return Intent(change.gesture, read_intent(p, iomap, payload))
end

function read_intent(p::ScreenToScreen, recursion, change::Intent, iomap::ScreenWindowIoMap)
    window_input = change.gesture
    if window_input isa WindowInput
        cim = iomap.content_iomap
        inner = read_intent(cim.projection, recursion, Intent(window_input.event, nothing), cim)
        op = _prefix_op(inner.operation, (FieldReferenceStep("content"),))
        return Intent(change.gesture, op)
    end
    payload = change.operation === nothing ? change.gesture : change.operation
    return Intent(change.gesture, read_intent(p, iomap, payload))
end

# Prepend `steps` to the reference path inside `op` (if it carries one), rooting a
# child's operation at the ScreenDocument. Every path-carrying operation type must
# be handled here; an unhandled type would fall through unchanged and apply its
# child-relative path against the screen root (e.g. ReplaceDocumentOperation's
# `.slice` from the clipboard projection).
function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceStringRangeOperation
        return ReplaceStringRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        return ReplaceNumberRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(_prepend(steps, op.path))
    elseif op isa ReplaceReferencedValueOperation
        return op.document === nothing ?
            ReplaceReferencedValueOperation(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        return CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
    else
        return op
    end
end

function _prepend(steps::Tuple, path::Reference)
    result = path
    for step in reverse(steps)
        result = ConcreteReference(step, result)
    end
    result
end

end # module
