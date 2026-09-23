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

The three `history_` fields are view state too: where Up and Down stand in the
history of the bottom form. `history_position` is 0 for the draft, and `k` for the
`k`-th form above the bottom one, counted from the newest. `history_draft` is what
the bottom form held when the navigation started, and `history_prefix` is the text
before the caret then. See [`RecallEvaluatorFormOperation`](@ref).

`parse_evaluated_forms` says whether an evaluation turns the code of its form into
a Julia document. It does so only when the document prints back as the code was
typed, less the blank space around it, so a comment or a person's own spacing is
never rewritten. See [`EvaluateSelectedFormOperation`](@ref).
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector = CellVector()
    follow_end::Bool = true
    history_position::Int = 0
    history_draft::String = ""
    history_prefix::String = ""
    parse_evaluated_forms::Bool = true
end
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(true),
                      Cell(0), Cell(""), Cell(""), Cell(true), Cell(nothing))

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

The form that was evaluated keeps its code as typed in `source`. When the
toplevel's `parse_evaluated_forms` is on, its code becomes a Julia document if
the document prints back as that code, less the blank space around it. The
evaluation runs the code as typed either way.

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

# The range the selection names in the code of the form it is in, `elements[i].
# form.value{s:e}`, or `nothing` when it names no range there.
function _find_selected_value_range(t::EvaluatorToplevel)
    path = t.selection
    path isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) == 5 && _is_field_step(steps[1], "elements") && _is_field_step(steps[3], "form") &&
     _is_field_step(steps[4], "value") && steps[5] isa RangeReferenceStep) || return nothing
    steps[5]
end

# The caret at `k` in the code of form `i`, `elements[i].form.value{k}`, rooted at
# the toplevel.
_make_form_caret_reference(i::Int, k::Int) =
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), _valpath(k))))

# The code of form `i` selected whole, `elements[i].form`, rooted at the toplevel.
_make_whole_form_reference(i::Int) =
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), EmptyReference())))

# Where Up and Down put the selection in form `i`: the caret at the start or the
# end of its text while the form is a string. A form that is a Julia document is
# selected whole, because a place in its code is a place in its projection, which
# a gesture of the toplevel does not see.
_make_form_start_reference(t::EvaluatorToplevel, i::Int) =
    t.elements[i].form isa PrimitiveString ? _make_form_caret_reference(i, 0) :
                                             _make_whole_form_reference(i)

function _make_form_end_reference(t::EvaluatorToplevel, i::Int)
    form = t.elements[i].form
    form isa PrimitiveString || return _make_whole_form_reference(i)
    _make_form_caret_reference(i, length(_get_form_source_text(form)))
end

# A key goes where the complete selection points, so a caret that an operation of
# the toplevel sets moves from the root. A toplevel that the complete selection
# does not pass through moves its own.
function _select_in_toplevel!(editor, t::EvaluatorToplevel, caret)
    _select_under!(editor, t, caret) && return nothing
    clear_selection!(t)
    set_selection!(t, caret)
    nothing
end

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
    # The fresh form is where the next key goes, so the view goes to the end, and
    # its history starts from its own empty draft.
    t.follow_end = true
    t.history_position = 0
    t.history_draft = ""
    t.history_prefix = ""
    _select_in_toplevel!(editor, t, _make_form_caret_reference(length(t.elements), 0))
    # The caret has left the evaluated form, so no selection names a place in the
    # string that the parse replaces.
    element.source = text
    t.parse_evaluated_forms && _parse_evaluated_form!(element)
    nothing
end

# The code of an evaluated form becomes a Julia document when the document prints
# back as the code, less the blank space around it. Otherwise the form keeps its
# string: code with a comment, with a spacing of its own, that does not parse, or
# that no loaded domain reads as Julia. A parser throws for a construct it does
# not support, and that is an answer here, not a fault.
function _parse_evaluated_form!(element::EvaluatorForm)
    element.form isa PrimitiveString || return nothing
    has_natural_parser(:jl) || return nothing
    code = strip(something(element.form.value, ""))
    parsed = try
        document = parse_natural_text(:jl, code)
        print_natural_text(document) == code ? document : nothing
    catch
        nothing
    end
    parsed === nothing || (element.form = parsed)
    nothing
end

# ── RecallEvaluatorFormOperation ────────────────────────────────────────────

"""
    RecallEvaluatorFormOperation(toplevel, direction)

UP or DOWN in the bottom form of an [`EvaluatorToplevel`](@ref): show the code of
an older form (`direction = :older`) or of a newer one (`:newer`) in the bottom
form, as the history of a Julia REPL does, with the caret at its end.

The history is the forms above the bottom one, newest first, each with the code
it holds, also one whose evaluation failed. Only an entry that starts with the
prefix is shown, and never one that is the text shown now, so a key always
changes something. The prefix is the text before the caret when the navigation
starts, and what the bottom form held then is the draft: Down past the newest
entry shows the draft again. A person who edits a recalled code starts a new
navigation from that text.

Declines when the caret is not in the text of the bottom form, or when the
direction has no entry left.
"""
struct RecallEvaluatorFormOperation <: Operation
    toplevel::EvaluatorToplevel
    direction::Symbol
end

# It names the toplevel it acts on, not a path into one, so it travels up the
# chain as it is.
OperationModule.operation_travels_unchanged(::RecallEvaluatorFormOperation) = true

function evaluate_operation(editor, op::RecallEvaluatorFormOperation)
    t = op.toplevel
    n = length(t.elements)
    form = t.elements[n].form
    form isa PrimitiveString || return nothing
    range = _find_selected_value_range(t)
    (range === nothing || _find_selected_form_index(t) != n) && return nothing
    shown = something(form.value, "")
    entries = String[_get_form_source_text(t.elements[k].form) for k in (n - 1):-1:1]
    position = t.history_position
    # A navigation starts from the draft, and again when a person edited what a
    # recall showed.
    if position == 0 || position > length(entries) || entries[position] != shown
        t.history_draft = shown
        t.history_prefix = first(shown, range.start)
        position = 0
    end
    is_match(k) = startswith(entries[k], t.history_prefix) && entries[k] != shown
    target = op.direction === :older ?
        findfirst(k -> k > position && is_match(k), eachindex(entries)) :
        findlast(k -> k < position && is_match(k), eachindex(entries))
    target === nothing && (op.direction === :older || position == 0) && return nothing
    text = target === nothing ? t.history_draft : entries[target]
    t.history_position = something(target, 0)
    form.value = text
    _select_in_toplevel!(editor, t, _make_form_caret_reference(n, length(text)))
    nothing
end

# SHIFT+ENTER: a line break at the caret of the form the caret is in, the same
# edit a typed character makes. `nothing` when the selection is not in the text
# of a form.
function _make_form_newline_operation(t::EvaluatorToplevel)
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    t.elements[i].form isa PrimitiveString || return nothing
    _find_selected_value_range(t) === nothing && return nothing
    ReplaceStringRangeOperation(t.selection, "\n")
end

# UP, which reaches the toplevel only from the first line of the code, because the
# text layer moves the caret up a line where there is one. In the bottom form it
# recalls an older form. In a form above, the selection goes to the end of the
# form above that one, so a recall never overwrites code that was evaluated.
function _make_up_operation(t::EvaluatorToplevel)
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    i == length(t.elements) && return RecallEvaluatorFormOperation(t, :older)
    i == 1 && return nothing
    ReplaceSelectionOperation(_make_form_end_reference(t, i - 1))
end

# DOWN, which reaches the toplevel only from the last line of the code. In the
# bottom form it recalls a newer form, or the draft. In a form above, the
# selection goes to the start of the form below.
function _make_down_operation(t::EvaluatorToplevel)
    i = _find_selected_form_index(t)
    i === nothing && return nothing
    i == length(t.elements) && return RecallEvaluatorFormOperation(t, :newer)
    ReplaceSelectionOperation(_make_form_start_reference(t, i + 1))
end

@gestures EvaluatorToplevel begin
    KeyDown(:return;) => "Evaluate" => EvaluateSelectedFormOperation(doc)
    KeyDown(:return; shift) => "Insert a line break" => _make_form_newline_operation(doc)
    KeyDown(:up;) => "Recall an older form, or go to the form above" => _make_up_operation(doc)
    KeyDown(:down;) => "Recall a newer form, or go to the form below" => _make_down_operation(doc)
end
