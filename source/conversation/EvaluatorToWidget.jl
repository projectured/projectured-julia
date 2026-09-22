# Fragment of `ConversationModule`.
#
# EvaluatorForm / EvaluatorToplevel → WidgetDocument projection, for the
# standalone REPL a person opens by typing `repl` into an empty tab:
#
#     EvaluatorToplevelToWidgetComposite → VerticalLayout of the elements' outputs
#     EvaluatorFormToWidgetCard          → the same code/result section pair the
#                                          composer draws for a draft in
#                                          progress (`_eval_sections`), with no
#                                          part-level panel around it — a bare
#                                          form has no turn or part to sit in.
#
# Both mirror `ConversationToWidget.jl`'s printers exactly: child iomaps kept in
# a `ComputedCell`, a `VerticalLayout` stacking their outputs, a `ChildrenIoMap`,
# and `_follow_selection!` so a caret set on the domain node shows up on the
# widget it produced.
#
# Unlike the read-only transcript, a bare form is EDITED: `EvaluatorFormToWidgetCard`'s
# reference maps pass the tail of a `form`/`result` reference through unchanged,
# rather than stopping at the whole section the way `ConversationPartToWidget`
# does — a caret inside the section's own document has to reach it.

struct EvaluatorFormToWidgetCard          <: Projection end
struct EvaluatorToplevelToWidgetComposite <: Projection end

# `("form", 1)` / `("result", 2)`: which child of the `_eval_sections` layout
# each field prints as.
const _FORM_SECTIONS = (("form", 1), ("result", 2))

const _ELEMENT_GAP = 8    # between the forms of a toplevel

# ── print_document: a bare form → its code/result section pair ─────────────

function print_document(projection::EvaluatorFormToWidgetCard,
                          recursion, form::EvaluatorForm, ctx)
    output = _eval_sections(form, nothing)
    iomap = SimpleIoMap(projection, form, output)
    _follow_selection!(output, form, projection, iomap, Any[])
    for (_, index) in _FORM_SECTIONS
        section = output.children[index]
        _follow_selection!(section, form, projection, iomap,
                           Any[FieldReferenceStep("children"), RangeReferenceStep(index - 1, index)])
    end
    iomap
end

# `form.<rest>` / `result.<rest>` ↔ `children[i].content.<rest>` — a full
# passthrough of whatever lies below the section, because a bare form is edited
# and not merely read.
function map_reference_forward(::EvaluatorFormToWidgetCard, iomap, reference)
    steps = _steps(reference)
    steps === nothing && return nothing
    isempty(steps) && return EmptyReference()
    for (name, index) in _FORM_SECTIONS
        _is_field_step(steps[1], name) &&
            return _from_steps(Any[FieldReferenceStep("children"), RangeReferenceStep(index - 1, index),
                                   FieldReferenceStep("content")], _from_steps(steps[2:end]))
    end
    nothing
end

function map_reference_backward(::EvaluatorFormToWidgetCard, iomap, reference)
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 3 && _is_field_step(steps[1], "children") &&
     steps[2] isa RangeReferenceStep && _is_field_step(steps[3], "content")) || return EmptyReference()
    for (name, index) in _FORM_SECTIONS
        steps[2].stop == index &&
            return _from_steps(Any[FieldReferenceStep(name)], _from_steps(steps[4:end]))
    end
    EmptyReference()
end

# ── print_document: the toplevel → a stack of its elements' outputs ────────

function print_document(projection::EvaluatorToplevelToWidgetComposite,
                          recursion, t::EvaluatorToplevel, ctx)
    rec, ref = recursion, ctx.reference
    ioms = ComputedCell(() -> Any[
        print_document(rec, rec, t.elements[i], make_child_context(ctx, ref))
        for i in eachindex(t.elements)
    ])
    layout = VerticalLayout(ComputedCellVector(() -> Any[im.output for im in ioms[]]),
                            Cell(:left), Cell(_ELEMENT_GAP),
                            Cell(Fill), Cell(Content), Cell(nothing))
    iomap = ChildrenIoMap(projection, t, layout, ioms)
    _follow_selection!(layout, t, projection, iomap, Any[])
    iomap
end

# `elements[i].<rest>` ↔ `children[i].<rest>`, exactly the conversation's own
# `turns` ↔ `children` map.
map_reference_backward(::EvaluatorToplevelToWidgetComposite, iomap, reference) =
    _backward_level(iomap, reference, "children", "elements", 0)
map_reference_forward(::EvaluatorToplevelToWidgetComposite, iomap, reference) =
    _forward_level(iomap, reference, "elements", Any[], "children")

# ── Natural-projection registration ──────────────────────────────────────────
#
# The row that lets a tab draw an evaluator toplevel or a bare form. Without it
# a person who types `repl` sees field names, because the render-anything
# projection falls through to the reflection tail for a document no row claims.
#
# Each row ends in graphics. A tab reads its content through `print_child`,
# which does not print a layout again until it is graphics, and a layout draws
# only the children whose output is graphics. The cards and the documents in
# them re-enter the renderer through the recursion both stages share.

function __init__()
    register_natural_graphics!(:evaluator, (; measure) -> Pair{Type,Any}[
        EvaluatorToplevel => ChainingProjection(EvaluatorToplevelToWidgetComposite(),
                                                VerticalLayoutToGraphicsCanvas()),
        EvaluatorForm     => ChainingProjection(EvaluatorFormToWidgetCard(),
                                                VerticalLayoutToGraphicsCanvas()),
    ])
end
