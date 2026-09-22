# Fragment of `ConversationModule`.
#
# EvaluatorForm / EvaluatorToplevel → WidgetDocument projection, for the
# standalone REPL a person opens by typing `repl` into an empty tab:
#
#     EvaluatorToplevelToWidgetComposite → VerticalLayout of the elements
#     EvaluatorFormToVerticalLayout      → VerticalLayout of a `>` row and a `=` row
#
# Neither prints a child. The toplevel's layout holds the forms, and a form's rows
# hold its code and its result, so the layout stage that follows prints each of
# them once, through the recursion. `_follow_selection!` makes a caret set on the
# domain node show up on the widget it produced.
#
# A bare form is EDITED: `EvaluatorFormToVerticalLayout`'s reference maps pass the
# tail of a `form`/`result` reference through unchanged, so a caret inside the
# code reaches it.

struct EvaluatorFormToVerticalLayout      <: Projection end
struct EvaluatorToplevelToWidgetComposite <: Projection end

# `("form", 1)` / `("result", 2)`: which row of a form each field prints as.
const _FORM_ROWS = (("form", 1), ("result", 2))

const _ELEMENT_GAP = 8    # between the forms of a toplevel
const _ROW_GAP     = 4    # between the code of a form and its result
const _PROMPT_GAP  = 8    # between a prompt and what follows it

const _PROMPT_STYLE       = StyleText(font_ubuntu_monospace_regular_20, color_slate_500)
const _PROMPT_ERROR_STYLE = StyleText(font_ubuntu_monospace_regular_20, color_destructive)

# ── print_document: a bare form → a prompt column beside its code and result ──
#
# `>` stands before the code and `=` before the result. Each row is the prompt,
# then the document, so the prompts of every form stand in one column, and a
# second line of code or of a result stays right of it. The prompts are one
# character of one monospace font, so the column has one width.
#
# A fresh form holds an empty result, and it shows no `=` row until it has one.

function print_document(projection::EvaluatorFormToVerticalLayout,
                          recursion, form::EvaluatorForm, ctx)
    code_prompt   = WidgetLabel(Point2D(0, 0), ">"; text_style = _PROMPT_STYLE)
    result_prompt = WidgetLabel(Point2D(0, 0), "="; text_style = _PROMPT_STYLE)
    error_prompt  = WidgetLabel(Point2D(0, 0), "="; text_style = _PROMPT_ERROR_STYLE)
    code_row = _make_prompt_row(() -> Any[code_prompt, form.form])
    result_row = _make_prompt_row(() -> Any[form.is_error === true ? error_prompt : result_prompt,
                                            form.result])
    rows = (code_row, result_row)
    output = VerticalLayout(ComputedCellVector(() -> _has_result(form) ? Any[rows...] : Any[code_row]),
                            Cell(:left), Cell(_ROW_GAP), Cell(nothing), Cell(nothing), Cell(nothing))
    iomap = SimpleIoMap(projection, form, output)
    _follow_selection!(output, form, projection, iomap, Any[])
    for (_, index) in _FORM_ROWS
        _follow_selection!(rows[index], form, projection, iomap,
                           Any[FieldReferenceStep("children"), RangeReferenceStep(index - 1, index)])
    end
    iomap
end

_make_prompt_row(children::Function) =
    HorizontalLayout(ComputedCellVector(children), Cell(:top), Cell(_PROMPT_GAP),
                     Cell(nothing), Cell(nothing), Cell(nothing))

_has_result(form::EvaluatorForm) = !(form.result isa TextBlock && isempty(form.result.elements))

# `form.<rest>` / `result.<rest>` ↔ `children[i].children[2].<rest>` — a full
# passthrough of whatever lies below the row, because a bare form is edited and
# not merely read. A form with no result yet has no row for one.
function map_reference_forward(::EvaluatorFormToVerticalLayout, iomap, reference)
    steps = _steps(reference)
    steps === nothing && return nothing
    isempty(steps) && return EmptyReference()
    for (name, index) in _FORM_ROWS
        _is_field_step(steps[1], name) || continue
        index == 2 && !_has_result(iomap.input) && return nothing
        return _from_steps(Any[FieldReferenceStep("children"), RangeReferenceStep(index - 1, index),
                               FieldReferenceStep("children"), RangeReferenceStep(1, 2)],
                           _from_steps(steps[2:end]))
    end
    nothing
end

# A path into a prompt, or into the rows themselves, names the whole form.
function map_reference_backward(::EvaluatorFormToVerticalLayout, iomap, reference)
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 4 && _is_field_step(steps[1], "children") &&
     steps[2] isa RangeReferenceStep && _is_field_step(steps[3], "children") &&
     steps[4] isa RangeReferenceStep && steps[4].stop == 2) || return EmptyReference()
    for (name, index) in _FORM_ROWS
        steps[2].stop == index &&
            return _from_steps(Any[FieldReferenceStep(name)], _from_steps(steps[5:end]))
    end
    EmptyReference()
end

# ── print_document: the toplevel → a stack of its forms ────────────────────
#
# The layout holds the forms themselves, as `CellVectorToVerticalLayout` holds
# the elements of a bare vector. A form printed here would reach the layout
# stage as graphics, and that stage prints each child again: the renderer has no
# row for graphics, so it would draw the canvas as a tree of its fields.

function print_document(projection::EvaluatorToplevelToWidgetComposite,
                          recursion, t::EvaluatorToplevel, ctx)
    layout = VerticalLayout(ComputedCellVector(() -> Any[element for element in t.elements]),
                            Cell(:left), Cell(_ELEMENT_GAP),
                            Cell(Fill), Cell(Content), Cell(nothing))
    iomap = SimpleIoMap(projection, t, layout)
    _follow_selection!(layout, t, projection, iomap, Any[])
    iomap
end

# `elements[i].<rest>` ↔ `children[i].<rest>`. The rest is a path in the form,
# which the layout stage maps through the form's own row.
function map_reference_forward(::EvaluatorToplevelToWidgetComposite, iomap, reference)
    steps = _steps(reference)
    steps === nothing && return nothing
    isempty(steps) && return EmptyReference()
    found = _indexed(steps, "elements")
    found === nothing && return nothing
    (i, rest) = found
    _from_steps(Any[FieldReferenceStep("children"), RangeReferenceStep(i - 1, i)], _from_steps(rest))
end

function map_reference_backward(::EvaluatorToplevelToWidgetComposite, iomap, reference)
    steps = _steps(reference)
    steps === nothing && return EmptyReference()
    found = _indexed(steps, "children")
    found === nothing && return EmptyReference()
    (i, rest) = found
    _from_steps(Any[FieldReferenceStep("elements"), RangeReferenceStep(i - 1, i)], _from_steps(rest))
end

# ── Natural-projection registration ──────────────────────────────────────────
#
# The row that lets a tab draw an evaluator toplevel or a bare form. Without it
# a person who types `repl` sees field names, because the render-anything
# projection falls through to the reflection tail for a document no row claims.
#
# Each row ends in graphics. A tab reads its content through `print_child`,
# which does not print a layout again until it is graphics, and a layout draws
# only the children whose output is graphics. The rows and the documents in
# them re-enter the renderer through the recursion both stages share.

function __init__()
    register_natural_graphics!(:evaluator, (; measure) -> Pair{Type,Any}[
        EvaluatorToplevel => ChainingProjection(EvaluatorToplevelToWidgetComposite(),
                                                VerticalLayoutToGraphicsCanvas()),
        EvaluatorForm     => ChainingProjection(EvaluatorFormToVerticalLayout(),
                                                VerticalLayoutToGraphicsCanvas()),
    ])
end
