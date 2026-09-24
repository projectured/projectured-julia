# Fragment of `ConversationModule`.
#
# EvaluatorForm / EvaluatorToplevel → WidgetDocument projection, for the
# standalone REPL a person opens by typing `repl` into an empty tab:
#
#     EvaluatorToplevelToWidgetComposite → a GridLayout of one column: the row of
#                                          options, then a WidgetScrollPane over a
#                                          VerticalLayout of the elements, which
#                                          follows the end
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
#
# The rows fill the width of the form, and in a row the prompt keeps the width of
# its one character while the document fills the rest. So a document that breaks
# its lines, as prose does, breaks them at the edge of the pane that shows it.

function print_document(projection::EvaluatorFormToVerticalLayout,
                          recursion, form::EvaluatorForm, ctx)
    code_prompt   = _make_prompt(">", _PROMPT_STYLE)
    result_prompt = _make_prompt("=", _PROMPT_STYLE)
    error_prompt  = _make_prompt("=", _PROMPT_ERROR_STYLE)
    code_row = _make_prompt_row(() -> Any[code_prompt, form.form])
    result_row = _make_prompt_row(() -> Any[form.is_error === true ? error_prompt : result_prompt,
                                            form.result])
    rows = (code_row, result_row)
    output = VerticalLayout(CellVector(Computed(() -> _has_result(form) ? Any[rows...] : Any[code_row])),
                            Cell(:left), Cell(_ROW_GAP), Cell(Fill), Cell(nothing), Cell(nothing))
    iomap = SimpleIoMap(projection, form, output)
    _follow_selection!(output, form, projection, iomap, Any[])
    for (_, index) in _FORM_ROWS
        _follow_selection!(rows[index], form, projection, iomap,
                           Any[FieldReferenceStep("children"), RangeReferenceStep(index - 1, index)])
    end
    iomap
end

_is_plain_left_press(event) =
    event isa MousePress && event.button === :left && event.modifiers == ModifierKeys()

_make_prompt(text, style) =
    LayoutConstraint(WidgetLabel(Point2D(0, 0), text; text_style = style); width = Content)

_make_prompt_row(children::Function) =
    HorizontalLayout(CellVector(Computed(children)), Cell(:top), Cell(_PROMPT_GAP),
                     Cell(Fill), Cell(nothing), Cell(nothing))

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

# A plain left press on a form that nothing in it answers, on its prompt or on
# the empty space after its code, puts the caret at the end of the code, so a
# click on a form is the way back to typing in it. A form whose code is a
# document selects the code whole instead.
function read_intent(::EvaluatorFormToVerticalLayout, iomap, event::MousePress)
    _is_plain_left_press(event) || return nothing
    code = iomap.input.form
    _is_text_form(code) ||
        return ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("form"), EmptyReference()))
    ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("form"),
                                                _valpath(length(_get_form_source_text(code)))))
end

# ── print_document: the toplevel → its options over a scroll pane of its forms ──
#
# The layout holds the forms themselves, as `CellVectorToVerticalLayout` holds
# the elements of a bare vector. A form printed here would reach the layout
# stage as graphics, and that stage prints each child again: the renderer has no
# row for graphics, so it would draw the canvas as a tree of its fields.
#
# The scroll pane takes the height the row of options leaves, so in a tab the
# forms scroll inside the page and the options stay in place. It follows the end
# through the toplevel's own `follow_end` cell: a scroll away from the end
# writes it, and an evaluation writes it back, so the fresh form is in view where
# the next key goes.
#
# A grid of one column holds the two, because each of its rows takes a size
# policy of its own: the options their content, the pane the rest.
#
#     children[1]                      the row of options
#     children[2]                      the scroll pane
#     children[2].content.children[i]  form i

const _FORMS_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2),
                      FieldReferenceStep("content"))

function print_document(projection::EvaluatorToplevelToWidgetComposite,
                          recursion, t::EvaluatorToplevel, ctx)
    layout = VerticalLayout(CellVector(Computed(() -> Any[element for element in t.elements])),
                            Cell(:left), Cell(_ELEMENT_GAP),
                            Cell(Fill), Cell(Content), Cell(nothing))
    # The pane paints no background, so the forms stand on the page of the tab.
    pane = WidgetScrollPane(layout; follow_end = getfield(t, :follow_end),
                            style = WidgetStyle(content_color = color_transparent))
    output = GridLayout(Any[_make_option_row(t), pane], 1; vertical_gap = _ROW_GAP,
                        column_policy = Fill, row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(projection, t, output)
    for (widget, depth) in ((output, 0), (pane, 2), (layout, 3))
        _follow_selection!(widget, t, projection, iomap, Any[_FORMS_STEPS[1:depth]...])
    end
    iomap
end

# The two options of the toplevel, each a check box before its name. A press on
# a box, or Space or Enter on a box that has the selection, answers
# `ToggleEvaluatorOptionOperation`, which the per-instance bindings of the box
# give ahead of its own toggle.
function _make_option_row(t::EvaluatorToplevel)
    HorizontalLayout(Any[_make_option_checkbox(t, :parse_evaluated_forms),
                         WidgetLabel(Point2D(0, 0), "Parse evaluated forms"; text_style = _PROMPT_STYLE),
                         _make_option_checkbox(t, :type_structured_forms),
                         WidgetLabel(Point2D(0, 0), "Structured forms"; text_style = _PROMPT_STYLE)];
                     vertical_align = :center, gap = _PROMPT_GAP)
end

function _make_option_checkbox(t::EvaluatorToplevel, option::Symbol)
    toggle = (document, event) -> ToggleEvaluatorOptionOperation(t, option)
    bind(pattern) = GestureBinding(pattern, toggle; description = "Turn the option on or off",
                                   domain = "evaluator")
    gestures = GestureBinding[bind(MousePressPattern(:left; modifiers = Symbol[])),
                              bind(KeyDownPattern(:space; modifiers = Symbol[])),
                              bind(KeyDownPattern(:return; modifiers = Symbol[]))]
    box = WidgetCheckbox(Point2D(0, 0), getproperty(t, option) === true; gestures)
    set_cell_function!(box, () -> getproperty(t, option) === true)
end

# A key that a layer inside the toplevel already answered, as the hole of a
# structured form answers Enter, is offered to the table of the toplevel as a
# claimed key, so only an `override` rule can take it over. The reader that
# `@projection_template` emits does the same for a template node.
#
# A plain left press that nothing inside answered, on the empty space of the
# toplevel, puts the caret at the end of the bottom form, where the next key
# goes, as a click on the empty space of a terminal goes to its prompt.
#
# Anything else goes to the generic bridge.
function read_intent(projection::EvaluatorToplevelToWidgetComposite, recursion,
                     change::Intent, iomap)
    if change.operation !== nothing && change.gesture isa Union{KeyPress, KeyDown}
        own = read_gesture(iomap.input, change.gesture; claimed = change.operation)
        own === nothing || return Intent(change.gesture, own)
    end
    if change.operation === nothing && _is_plain_left_press(change.gesture)
        t = iomap.input
        return Intent(change.gesture,
                      ReplaceSelectionOperation(_make_form_end_reference(t, length(t.elements))))
    end
    invoke(read_intent, Tuple{Projection, Any, Intent, Any}, projection, recursion, change, iomap)
end

# `elements[i].<rest>` ↔ `children[2].content.children[i].<rest>`. The rest
# is a path in the form, which the layout stage maps through the form's own row.
# A path into the row of options names nothing, so a press on an option leaves
# the caret in the code where it is; any other path outside the forms names the
# whole toplevel.
function map_reference_forward(::EvaluatorToplevelToWidgetComposite, iomap, reference)
    steps = _steps(reference)
    steps === nothing && return nothing
    isempty(steps) && return EmptyReference()
    found = _indexed(steps, "elements")
    found === nothing && return nothing
    (i, rest) = found
    _from_steps(Any[_FORMS_STEPS..., FieldReferenceStep("children"), RangeReferenceStep(i - 1, i)],
                _from_steps(rest))
end

function map_reference_backward(::EvaluatorToplevelToWidgetComposite, iomap, reference)
    steps = _steps(reference)
    _is_options_path(steps) && return nothing
    n = length(_FORMS_STEPS)
    (steps !== nothing && length(steps) > n && all(k -> steps[k] == _FORMS_STEPS[k], 1:n)) ||
        return EmptyReference()
    found = _indexed(steps[(n + 1):end], "children")
    found === nothing && return EmptyReference()
    (i, rest) = found
    _from_steps(Any[FieldReferenceStep("elements"), RangeReferenceStep(i - 1, i)], _from_steps(rest))
end

_is_options_path(steps) =
    steps !== nothing && length(steps) >= 2 && _is_field_step(steps[1], "children") &&
    steps[2] == RangeReferenceStep(0, 1)

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
                                                GridLayoutToGraphicsCanvas()),
        EvaluatorForm     => ChainingProjection(EvaluatorFormToVerticalLayout(),
                                                VerticalLayoutToGraphicsCanvas()),
    ])
end
