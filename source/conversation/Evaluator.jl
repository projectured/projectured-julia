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

`follow_end` is view state: whether the view of the toplevel keeps its last form
in view. A person who scrolls away from the end turns it off, and scrolling back
to the end or an evaluation turns it on again.
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector = CellVector()
    follow_end::Bool = true
end
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(true), Cell(nothing))

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

ENTER on an [`EvaluatorToplevel`](@ref): evaluate the [`EvaluatorForm`](@ref)
the caret sits in, the same evaluation [`ComposerEvaluateOperation`](@ref) runs
for the composer's draft, and open a fresh empty form after it so a person can
keep typing at once. The complete selection moves to the fresh form, so the form
that was evaluated shows no caret.

Declines — leaves the toplevel untouched — when the caret names no element, or
that element's source is blank. Both are checked here, at evaluation time, not
at read time: the gesture always fires and lets the operation decide, exactly
as the composer's own evaluate does.
"""
struct EvaluateSelectedFormOperation <: Operation
    toplevel::EvaluatorToplevel
end

# It names the toplevel it evaluates, not a path into one, so there is nothing
# for a projection to re-root. It travels up the chain as it is, which is what
# lets an evaluator in a pane tab reach the editor.
OperationModule.operation_travels_unchanged(::EvaluateSelectedFormOperation) = true

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

# ── The namespace of the evaluator ───────────────────────────────────────────
#
# A person types into the evaluator, and the assistant does not, so it evaluates
# as a Julia REPL does: in a namespace that no API limits. Every name that
# `Projectured` exports is in scope, and `using` loads what the environment
# declares. The assistant's `execute_julia_code` keeps the API its host declares
# on `editor.tools`.
#
# The namespace belongs to the tools of the editor, so the evaluators of one
# window are one session, as the windows of one Julia process share `Main`, and
# a name one form binds is defined in the next. It shares the observers of those
# tools, so a host still hears what an evaluation made. The table is weak, and
# the namespace lets go of `editor` after each evaluation, so an editor that is
# gone takes its namespace with it.
const _EVALUATOR_TOOL_SETS = Ref{Any}(nothing)

function _get_evaluator_tool_set(editor)
    tools = hasproperty(editor, :tools) ? editor.tools : nothing
    tools isa ToolSet || return ToolSet()
    sets = _EVALUATOR_TOOL_SETS[]
    sets === nothing && (sets = _EVALUATOR_TOOL_SETS[] = WeakKeyDict{ToolSet,ToolSet}())
    get!(sets, tools) do
        set = ToolSet()
        set.observers = tools.observers
        set
    end
end

function evaluate_operation(editor, op::EvaluateSelectedFormOperation)
    t = op.toplevel
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    element = t.elements[i]
    text = _get_form_source_text(element.form)
    isempty(strip(text)) && return nothing
    set = _get_evaluator_tool_set(editor)
    output = try
        execute_julia_code(set, editor, text)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    # The next evaluation binds `editor` again, so the namespace holds none.
    set.scratch === nothing || Core.eval(set.scratch, :(editor = nothing))
    is_err = occursin("ERROR", output) || occursin("Error", output)
    # A `Document` return value is kept as the result so it renders live;
    # otherwise the printed output, exactly as the composer's own evaluate does.
    val = get_last_evaluated_value(set)
    result = val isa Document ? val : make_evaluator_result_text(rstrip(output))
    element.result = result
    element.is_error = is_err
    push!(t.elements, EvaluatorForm(PrimitiveString("")))
    # The fresh form is where the next key goes, so the view goes to the end.
    t.follow_end = true
    n = length(t.elements)
    caret = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(n - 1, n),
            ConcreteReference(FieldReferenceStep("form"), _valpath(0))))
    # A key goes where the complete selection points, so the selection moves
    # from the root. A toplevel that the complete selection does not pass
    # through moves its own.
    if !_select_under!(editor, t, caret)
        clear_selection!(t)
        set_selection!(t, caret)
    end
    nothing
end

# SHIFT+ENTER: a line break at the caret of the form the caret is in, the same
# edit a typed character makes. `nothing` when the selection is not in the text
# of a form.
function _make_form_newline_operation(t::EvaluatorToplevel)
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    t.elements[i].form isa PrimitiveString || return nothing
    steps = get_reference_steps(strip_reference_types(t.selection))
    (length(steps) == 5 && _is_field_step(steps[3], "form") &&
     _is_field_step(steps[4], "value") && steps[5] isa RangeReferenceStep) || return nothing
    ReplaceStringRangeOperation(t.selection, "\n")
end

@gestures EvaluatorToplevel begin
    KeyDown(:return;) => "Evaluate" => EvaluateSelectedFormOperation(doc)
    KeyDown(:return; shift) => "Insert a line break" => _make_form_newline_operation(doc)
end
