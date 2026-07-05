"""
    ProjectionConfiguringProjectionModule

A higher-order projection that wraps an inner ("parameter") projection and
extends its output with an editable control bar for the inner projection's
parameters. The printer:

1. runs the inner projection on the input (giving the projected document), and
2. projects the inner projection *object itself* through a `control` projection
   (default `ObjectToWidget`) into a parameter-control widget,

then stacks the two in a `WidgetSplitPane` (control above document by default).

The reader routes backward-flowing changes three ways:

- a `ReplaceReferencedValueOperation` produced by a control is handed to the control
  reader, which redirects it onto the inner projection's parameter cell;
- a show/hide gesture (`Ctrl+F` toggles, `Escape` hides) flips the control
  widget's `visible` cell via `ReplaceReferencedValueOperation(control_widget, "visible", …)`;
- everything else delegates to the inner projection's reader (document edits).

Because the control edits the *same* parameter `Cell`s the inner projection
reads inside its reactive thunks, configuring re-projects the document live.

Reader-routing model mirrors `WindowManagingProjection`: intercept the changes
this projection owns, delegate the rest.
"""
module ProjectionConfiguringProjectionModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward,
                              Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..WidgetModule: WidgetDocument, WidgetSplitPane, WidgetScrollPane
import ..ObjectToWidgetModule: ObjectToWidget
import ..OperationModule: ReplaceReferencedValueOperation, ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference
import ..KeyboardModule: KeyDown, is_ctrl

export ProjectionConfiguringProjection, ProjectionConfiguringProjectionIoMap

# ── IoMap ─────────────────────────────────────────────────────────────────

struct ProjectionConfiguringProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    control_iomap::Any
    control_widget::Any   # the control composite — target of show/hide
end

# ── Projection ────────────────────────────────────────────────────────────

"""
    ProjectionConfiguringProjection(; inner, control=ObjectToWidget(), orientation=:vertical)

`inner` is the projection whose parameters become editable. `control` projects
the inner projection object into a control widget. `orientation` is the split
axis (`:vertical` ⇒ control above document).
"""
struct ProjectionConfiguringProjection <: Projection
    inner::Any
    control::Any
    orientation::Symbol
end

ProjectionConfiguringProjection(; inner, control=ObjectToWidget(), orientation::Symbol=:vertical) =
    ProjectionConfiguringProjection(inner, control, orientation)

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::ProjectionConfiguringProjection, recursion, input, ctx)
    inner_iomap   = print_document(p.inner, recursion, input, ctx)
    # Project the inner projection *object* into a control form.
    control_iomap = print_document(p.control, p.control, p.inner, ctx)
    control_widget = control_iomap.output
    # WidgetSplitPane only renders WidgetDocument slots, so a non-widget
    # projected document (e.g. a TextText) is wrapped in a WidgetScrollPane,
    # which recurses it back through the chain (the assistant-input pattern).
    doc_output = inner_iomap.output
    doc_widget = doc_output isa WidgetDocument ? doc_output : WidgetScrollPane(doc_output)
    output = WidgetSplitPane(p.orientation, Any[control_widget, doc_widget])
    ProjectionConfiguringProjectionIoMap(p, input, output,
        inner_iomap, control_iomap, control_widget)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::ProjectionConfiguringProjection, recursion,
                         change::Intent, iomap::ProjectionConfiguringProjectionIoMap)
    op = change.operation

    # 1. A checkbox click (ReplaceReferencedValueOperation rooted at a control widget) →
    #    redirect onto the inner projection's parameter cell.
    if op isa ReplaceReferencedValueOperation
        redirected = read_intent(p.control, iomap.control_iomap, op)
        redirected !== op && return Intent(change.gesture, redirected)
    end

    # 2. A control-bar text edit. The renderer re-roots it at our output split
    #    pane; if it falls in the control slot (1), strip that step and hand the
    #    output-domain edit to the control reader, which converts it to a
    #    ReplaceReferencedValueOperation on the parameter.
    if op isa ReplaceStringRangeOperation
        rest = _strip_control_slot(op.reference)
        if rest !== nothing
            converted = read_intent(p.control, iomap.control_iomap,
                                        ReplaceStringRangeOperation(rest, op.replacement))
            converted isa ReplaceReferencedValueOperation && return Intent(change.gesture, converted)
        end
    end

    # 3. A click in the control bar (ReplaceSelectionOperation under the control
    #    slot) is consumed — the control caret is derived, so there is no input
    #    selection to set, and it must not fall through to the document.
    if op isa ReplaceSelectionOperation && _strip_control_slot(op.path) !== nothing
        return Intent(change.gesture, nothing)
    end

    # 4. Show/hide the control bar.
    toggle = _toggle_operation(change.gesture, iomap.control_widget)
    toggle !== nothing && return Intent(change.gesture, toggle)

    # 5. Otherwise the change belongs to the projected document.
    read_intent(p.inner, recursion, change, iomap.inner_iomap)
end

# 3-arg compatibility shim (tests / hit-test recursion).
read_intent(p::ProjectionConfiguringProjection,
                iomap::ProjectionConfiguringProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Strip the control split-slot step (`elements[1]`, 0-based start 0) from a
# reference rooted at our output split pane, returning the remainder (rooted at
# the control bar) or `nothing` when the reference is not in the control slot.
function _strip_control_slot(ref)
    # Skip canonical TypeReference checkpoints at each level before reading the
    # `elements[1]` control-slot structure.
    ref = ref
    ref isa ConcreteReferencePath || return nothing
    (ref.head isa FieldReference && ref.head.name == "elements") || return nothing
    t = ref.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference && t.head.start == 0) || return nothing
    t.tail
end

# `Ctrl+F` toggles the control bar; `Escape` hides it when shown. Returns the
# operation to emit, or `nothing` when the gesture is not a show/hide.
function _toggle_operation(gesture, control_widget)
    gesture isa KeyDown || return nothing
    hidden = control_widget.visible == false
    if gesture.key === :f && is_ctrl(gesture)
        return ReplaceReferencedValueOperation(control_widget, "visible", hidden)
    elseif gesture.key === :escape
        return hidden ? nothing : ReplaceReferencedValueOperation(control_widget, "visible", false)
    end
    nothing
end

# ── Reference mapping ─────────────────────────────────────────────────────
# v1: no cursor mapping through the split pane (document editing still works via
# the reader routing above). Mirrors ConversationToWidget's minimal v1 mapping.

map_reference_forward(::ProjectionConfiguringProjection, iomap::ProjectionConfiguringProjectionIoMap, reference) = nothing
map_reference_backward(::ProjectionConfiguringProjection, iomap::ProjectionConfiguringProjectionIoMap, reference) = nothing

end # module
