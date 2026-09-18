# Fragment of `ConversationModule` — the evaluator document types: the abstract
# `EvaluatorDocument` and the form that carries a source, its result and the
# tool call that produced it.

abstract type EvaluatorDocument <: Document end

# ── EvaluatorForm ────────────────────────────────────────────────────────────

"""
    EvaluatorForm(form; source, result, is_error, tool_use_id, tool_name, input,
                  form_collapsed, result_collapsed)

A code form paired with its evaluation result. `form` is the code document
(a `JuliaDocument`); `result` is the result document (`TextBlock` for now).

`source` is the text the call was made with, **kept as it arrived**. The form is
the *projection* of that text, and a projection is not reversible in general: a
snippet that does not parse is held as a `PrimitiveString`, whose stringification
is its constructor repr, and a snippet that does parse becomes an AST whose
printing is the printer's idea of the code rather than the caller's. Either way a
caller that needs the original — a conversation replayed into a model's history —
must not re-derive it from the document. It reads `source`.

Empty `source` means the caller kept none, and a reader falls back to the form.

`input` is the tool's whole input, kept as it arrived. It is what names a
resource read (`uri`) or a search (`query`) in a transcript, and what a
conversation replays to the model. An empty input means the caller kept none,
and a reader treats the form as an evaluation whose input is the code.

`form_collapsed` and `result_collapsed` are view state, the same as a part's
`collapsed`: each says whether that section of the form is folded. A result that
is an error starts folded, and everything else starts open.
"""
@document struct EvaluatorForm <: EvaluatorDocument
    form::Document
    result::Document
    is_error::Bool
    tool_use_id::String
    tool_name::String
    source::String
    input::Dict{String,Any}
    form_collapsed::Bool
    result_collapsed::Bool
end

EvaluatorForm(form::Document;
              result::Document = TextBlock(),
              is_error::Bool = false,
              tool_use_id::AbstractString = "",
              tool_name::AbstractString = "execute_julia_code",
              source::AbstractString = "",
              input::AbstractDict = Dict{String,Any}(),
              form_collapsed::Bool = false,
              result_collapsed::Bool = is_error) =
    EvaluatorForm(Cell(form), Cell(result), Cell(is_error),
                  Cell(String(tool_use_id)), Cell(String(tool_name)),
                  Cell(String(source)), Cell(Dict{String,Any}(input)),
                  Cell(form_collapsed), Cell(result_collapsed), Cell(nothing))

"""
    get_evaluation_kind_label(name::AbstractString) -> "eval" | "resource" | "tool"

Classify a tool-call form's header label by the tool that produced it:
`execute_julia_code` is an evaluation, `list_resources` / `read_resource`
are resource reads, everything else is a generic tool call.
"""
function get_evaluation_kind_label(name::AbstractString)
    name == "execute_julia_code" && return "eval"
    (name == "list_resources" || name == "read_resource") && return "resource"
    return "tool"
end
get_evaluation_kind_label(f::EvaluatorForm) = get_evaluation_kind_label(f.tool_name)

"""
    get_evaluation_title(form::EvaluatorForm) -> String

The header of a form in a transcript. An evaluation is `eval`. A resource read
names its resource, `resource · <uri>`. A resource listing is `resources`. Any
other tool names itself, `tool · <name>`, followed by its first string argument
in quotes, cut at 60 characters, so a search says what it searched for.
"""
function get_evaluation_title(f::EvaluatorForm)
    name = f.tool_name
    name == "execute_julia_code" && return "eval"
    name == "list_resources"     && return "resources"
    input = f.input
    if name == "read_resource"
        uri = get(input, "uri", "")
        return uri isa AbstractString && !isempty(uri) ? "resource · " * uri : "resource"
    end
    argument = _first_string_argument(input)
    argument === nothing ? "tool · " * name :
                           "tool · " * name * " " * _quoted_cut(argument, 60)
end

# The argument a call is best known by: the query or the name it was made with,
# else the first string argument in key order, else nothing.
function _first_string_argument(input::AbstractDict)
    for key in ("query", "uri", "name")
        value = get(input, key, nothing)
        value isa AbstractString && !isempty(value) && return value
    end
    for key in sort!(collect(keys(input)))
        value = input[key]
        value isa AbstractString && !isempty(value) && return value
    end
    nothing
end

_quoted_cut(s::AbstractString, n::Int) =
    "\"" * (length(s) > n ? first(s, n - 1) * "…" : String(s)) * "\""

"""
    get_evaluation_section_labels(form::EvaluatorForm) -> (String, String)

The titles of a form's two sections. An evaluation shows `code` over `result`;
any other tool shows `arguments` over `result`. A result that is an error is
titled `error`.
"""
get_evaluation_section_labels(f::EvaluatorForm) =
    (f.tool_name == "execute_julia_code" ? "code" : "arguments",
     f.is_error === true ? "error" : "result")

"""
    make_evaluator_arguments_text(input) -> TextBlock

The form of a tool call that is not an evaluation: one `key: value` line per
argument, in key order.
"""
make_evaluator_arguments_text(input::AbstractDict) =
    TextBlock(TextString(join(["$(key): $(value)" for (key, value) in sort(collect(input); by = first)], "\n")))

# Convenience: build a result document from a plain output string.
make_evaluator_result_text(s::AbstractString) = TextBlock(TextString(String(s)))

# ── ToggleEvaluatorSectionOperation ─────────────────────────────────────────

"""
    ToggleEvaluatorSectionOperation(form, section)

Fold or unfold one section of an `EvaluatorForm`: `section` is `:form` or
`:result`. The kernel's `ToggleCollapseOperation` flips the one `collapsed` flag
of a node and can not name a section, so a form's two folds are this
operation's.
"""
struct ToggleEvaluatorSectionOperation <: Operation
    form::EvaluatorForm
    section::Symbol
end

function evaluate_operation(editor, op::ToggleEvaluatorSectionOperation)
    ef = op.form
    if op.section === :form
        ef.form_collapsed = !(ef.form_collapsed === true)
    elseif op.section === :result
        ef.result_collapsed = !(ef.result_collapsed === true)
    else
        error("ToggleEvaluatorSectionOperation: unknown section $(op.section)")
    end
    nothing
end

# ── EvaluatorToplevel ────────────────────────────────────────────────────────

"""
    EvaluatorToplevel(elements = [])

An ordered sequence of `EvaluatorForm`s.
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector = CellVector()
end
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(nothing))

set_cell_function!(t::EvaluatorToplevel, f::Function) =
    (set_cell_function!(getfield(t.elements, :elements), () -> Cell[Cell(x) for x in f()]); t)

# A person points at the part that holds an evaluation, or at the evaluation's
# form or result, never at the evaluation between them: the Alt + arrow walk
# passes through it.
is_selection_walk_stop(::EvaluatorForm) = false

get_document_title(::EvaluatorToplevel) = "Evaluator"
get_insertion_aliases(::Type{EvaluatorToplevel}) = ["repl", "evaluator"]

# A fresh loop: one empty form, caret at the start of its (empty) source, ready
# to type into at once.
@insertion EvaluatorToplevel =
    @with_selection EvaluatorToplevel([EvaluatorForm(PrimitiveString(""))]) elements[1].form.value{0}

# ── EvaluateSelectedFormOperation ────────────────────────────────────────────

"""
    EvaluateSelectedFormOperation(toplevel)

ALT+ENTER on an [`EvaluatorToplevel`](@ref): evaluate the [`EvaluatorForm`](@ref)
the caret sits in, the same evaluation [`ComposerEvaluateOperation`](@ref) runs
for the composer's draft, and open a fresh empty form after it so a person can
keep typing at once.

Declines — leaves the toplevel untouched — when the caret names no element, or
that element's source is blank. Both are checked here, at evaluation time, not
at read time: the gesture always fires and lets the operation decide, exactly
as the composer's own evaluate does.
"""
struct EvaluateSelectedFormOperation <: Operation
    toplevel::EvaluatorToplevel
end

# The 1-based index of the `elements[i]` the caret sits in, or `nothing` when
# the toplevel's selection does not reach into an element at all.
function _find_selected_form_index(t::EvaluatorToplevel)
    path = t.selection
    path isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) >= 2 && steps[1] isa FieldReferenceStep && steps[1].name == "elements" &&
     steps[2] isa RangeReferenceStep) || return nothing
    i = steps[2].stop
    (1 <= i <= length(t.elements)) || return nothing
    i
end

# The source text a form carries: what was typed, while it is still the plain
# `PrimitiveString` an untouched form starts as; the printer's rendering of it
# otherwise — a form already committed to a parsed document, evaluated again.
_get_form_source_text(form::PrimitiveString) = something(form.value, "")
_get_form_source_text(form::Document) = print_natural_text(form)

function evaluate_operation(editor, op::EvaluateSelectedFormOperation)
    t = op.toplevel
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    element = t.elements[i]
    text = _get_form_source_text(element.form)
    isempty(strip(text)) && return nothing
    set = editor.tools
    output = try
        execute_julia_code(set, editor, text)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_err = occursin("ERROR", output) || occursin("Error", output)
    # A `Document` return value is kept as the result so it renders live;
    # otherwise the printed output, exactly as the composer's own evaluate does.
    val = get_last_evaluated_value(set)
    result = val isa Document ? val : make_evaluator_result_text(rstrip(output))
    element.result = result
    element.is_error = is_err
    push!(t.elements, EvaluatorForm(PrimitiveString("")))
    n = length(t.elements)
    set_selection!(t, ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(n - 1, n),
            ConcreteReference(FieldReferenceStep("form"), _valpath(0)))))
    nothing
end

@gestures EvaluatorToplevel begin
    KeyDown(:enter; alt) => "Evaluate" => EvaluateSelectedFormOperation(doc)
end
