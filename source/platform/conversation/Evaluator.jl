# Fragment of `ConversationModule` — the evaluator document types: the abstract
# `EvaluatorDocument` and the form that carries a source, its result and the
# tool call that produced it.

abstract type EvaluatorDocument <: Document end

# ── EvaluatorForm ────────────────────────────────────────────────────────────

"""
    EvaluatorForm(form; source, result, output, is_error, tool_use_id, tool_name, input,
                  form_collapsed, result_collapsed)

A code form paired with its evaluation result. `form` is the code document
(a `JuliaDocument`); `result` is the result document: a `TextBlock`, a live
value that is a document, or a document of the result's own format, such as a
Markdown page.

`source` is the text the call was made with, **kept as it arrived**. The form is
the *projection* of that text, and a projection is not reversible in general: a
snippet that does not parse is held as a `PrimitiveString`, whose stringification
is its constructor repr, and a snippet that does parse becomes an AST whose
printing is the printer's idea of the code rather than the caller's. Either way a
caller that needs the original — a conversation replayed into a model's history —
must not re-derive it from the document. It reads `source`.

Empty `source` means the caller kept none, and a reader falls back to the form.

`output` is the text the tool answered, **kept as it arrived**, for the same
reason: `result` is a document made from that text, such as a Markdown page, and
the page printed back is not the text the tool wrote. Empty `output` means the
result is not made from a text, or the caller kept none, and a reader falls back
to the result.

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
    output::String
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
              output::AbstractString = "",
              input::AbstractDict = Dict{String,Any}(),
              form_collapsed::Bool = false,
              result_collapsed::Bool = is_error) =
    EvaluatorForm(Cell(form), Cell(result), Cell(is_error),
                  Cell(String(tool_use_id)), Cell(String(tool_name)),
                  Cell(String(source)), Cell(String(output)), Cell(Dict{String,Any}(input)),
                  Cell(form_collapsed), Cell(result_collapsed), Cell(nothing))

# ── The file form ────────────────────────────────────────────────────────────

# A `.pred` file writes the input of a tool call as its notation holds it: a JSON
# object as a group of `(key, value)` pairs in the order of their keys, an array
# as a vector, and a string, a number, a bool and `nothing` as they are. A key of
# an input can be any text, so a mapping of names can not hold it.
pred_arguments(f::EvaluatorForm) = (), Pair{Symbol,Any}[
    :form             => f.form,
    :result           => _make_file_result(f),
    :is_error         => f.is_error,
    :tool_use_id      => f.tool_use_id,
    :tool_name        => f.tool_name,
    :source           => f.source,
    :output           => f.output,
    :input            => _make_file_json(f.input),
    :form_collapsed   => f.form_collapsed,
    :result_collapsed => f.result_collapsed,
]

# The result as a file writes it. A result that the notation of a file can not
# write, such as a live document of the session that an evaluation returned, is
# written as the text of the tool.
function _make_file_result(f::EvaluatorForm)
    result = f.result
    try
        print_pred_text(result)
        result
    catch exception
        exception isa FileCutException || rethrow()
        make_evaluator_result_text(f.output)
    end
end

function make_pred_document(::Type{<:EvaluatorForm}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    form = pop!(values, :form)
    input = _read_file_json(pop!(values, :input, ()))
    EvaluatorForm(form; input, values...)
end

_make_file_json(value::AbstractDict) =
    Tuple((String(key), _make_file_json(item)) for (key, item) in sort!(collect(value); by = first))
_make_file_json(value::AbstractVector) = Any[_make_file_json(item) for item in value]
_make_file_json(value) = value

_read_file_json(value::Tuple) = Dict{String,Any}(String(first(pair)) => _read_file_json(last(pair)) for pair in value)
_read_file_json(value::AbstractVector) = Any[_read_file_json(item) for item in value]
_read_file_json(value) = value

# ── The duplicate ────────────────────────────────────────────────────────────

# The forms of an evaluator are what a person typed, and the folds are how they
# read them, so the duplicate of an evaluator is a copy of its forms. It
# evaluates in the namespace of its window, as every evaluator there does.
has_document_duplicate(::EvaluatorDocument) = true

# A result is what an evaluation answered, and it can be live: a list that
# computes, or a widget that holds a function. The duplicate of a form shares
# its result, and an evaluation in the duplicate puts a new result there.
copy_document(policy::DuplicatePolicy, form::EvaluatorForm) =
    copy_document_fields(policy, form; result = form.result)

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
`k`-th entry of the history, counted from the newest; a form that holds an object
is no entry, because it has no text. `history_draft` is what
the bottom form held when the navigation started, and `history_prefix` is the text
before the caret then. See [`RecallEvaluatorFormOperation`](@ref).

`parse_evaluated_forms` says whether an evaluation turns the code of its form into
a Julia document. It does so only when the document prints back as the same
tokens on the same lines as the code that was typed, so only the spaces between
them can change, and a comment is never lost. See
[`EvaluateSelectedFormOperation`](@ref).

`type_structured_forms` says whether a fresh form is a hole of the Julia domain,
typed into as the Julia domain types, instead of a string. A structured form can
hold a pasted object. Enter still evaluates the whole form, and commits the hole
as part of that.
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector = CellVector()
    follow_end::Bool = true
    history_position::Int = 0
    history_draft::String = ""
    history_prefix::String = ""
    parse_evaluated_forms::Bool = true
    type_structured_forms::Bool = false
end
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(true),
                      Cell(0), Cell(""), Cell(""), Cell(true), Cell(false), Cell(nothing))

set_cell_computation!(t::EvaluatorToplevel, f::Function) =
    (set_cell_computation!(getfield(t.elements, :elements), () -> Cell[Cell(x) for x in f()]); t)

# A person points at the part that holds an evaluation, or at the evaluation's
# form or result, never at the evaluation between them: the Alt + arrow walk
# passes through it.
is_selection_walk_stop(::EvaluatorForm) = false

get_document_title(::EvaluatorToplevel) = "Evaluator"
get_insertion_aliases(::Type{EvaluatorToplevel}) = ["repl", "evaluator"]

# A fresh loop: one empty form, caret at the start of its (empty) source, ready
# to type into at once.
@insertion EvaluatorToplevel =
    @selected EvaluatorToplevel([EvaluatorForm(PrimitiveString(""))]) elements[1].form.value{0}

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
the document prints back as the same tokens on the same lines as that code,
whatever the spaces between them. The evaluation runs the code as typed either
way.

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
OperationModule.is_self_contained_operation(::EvaluateSelectedFormOperation) = true

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

# The source text a form carries: what was typed, while the form is still text,
# a `PrimitiveString` or a Julia hole; the printer's rendering of it otherwise, a
# form already committed to a parsed document, evaluated again. The print of a
# hole would add its completion hint, so a hole gives its own text.
_get_form_source_text(form::PrimitiveString) = something(form.value, "")
_get_form_source_text(form::Document) =
    _is_julia_hole(form) ? something(form.value, "") : print_natural_text(form)

# A form whose code is still typed text: the `PrimitiveString` of a string form,
# or the hole a structured form starts as. Both keep their text in `value`.
_is_text_form(form) = form isa PrimitiveString || _is_julia_hole(form)

# Whether the code of a form holds an object that a person pasted into it: a node
# that is neither Julia nor a list of nodes, or the whole code. The label of an
# object is not code, so such a form has no text that runs, and the history
# skips it.
_holds_object(form) = !_is_text_form(form) && !isempty(search_documents(form, _is_object))
_is_object(node) = node isa Document && !is_element_collection(node) &&
                   get_natural_format(typeof(node)) !== :jl

# The insertion of the Julia domain, known by what it is and not by its name,
# because this package does not depend on that domain.
_is_julia_hole(form) = _is_julia_hole_type(typeof(form))
_is_julia_hole_type(T) = get_insertion_root(T) !== Document && get_natural_format(T) === :jl

# The code of a fresh form: a hole of the Julia domain when the toplevel types
# structured forms and that domain is loaded, and an empty string otherwise.
function _make_fresh_code(t::EvaluatorToplevel)
    t.type_structured_forms || return PrimitiveString("")
    T = resolve_insertion(Document, "julia")
    (T === nothing || !_is_julia_hole_type(T)) && return PrimitiveString("")
    make_insertion_document(T)
end

_make_fresh_form(t::EvaluatorToplevel) = EvaluatorForm(_make_fresh_code(t))

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
    _is_text_form(t.elements[i].form) ? _make_form_caret_reference(i, 0) :
                                        _make_whole_form_reference(i)

function _make_form_end_reference(t::EvaluatorToplevel, i::Int)
    form = t.elements[i].form
    _is_text_form(form) || return _make_whole_form_reference(i)
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
    code = element.form
    # A form that holds an object has no text that runs: it runs as an `Expr`
    # that holds the object itself, and so does any other form that is already
    # a document, whose print is its text.
    by_expression = !_is_text_form(code) && has_natural_expression(:jl)
    text = _holds_object(code) ? "" : _get_form_source_text(code)
    !by_expression && isempty(strip(text)) && return nothing
    # A form that ends with `;` runs, and what its code prints shows, but its
    # value does not, as in the Julia REPL.
    hides_value = _ends_with_semicolon(text)
    describe_value = hides_value ? (_ -> "") : describe_value_for_person
    set = _get_evaluator_tool_set(editor)
    output = try
        by_expression ?
            execute_julia_expression!(set, editor, make_natural_expression(:jl, code);
                                      describe_value = describe_value) :
            execute_julia_code!(set, editor, text; describe_value = describe_value)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    # The next evaluation binds `editor` again, so the namespace holds none.
    set.scratch === nothing || Core.eval(set.scratch, :(editor = nothing))
    is_err = occursin("ERROR", output) || occursin("Error", output)
    # A `Document` return value is kept as the result so it renders live;
    # otherwise the printed output, exactly as the composer's own evaluate does.
    val = get_last_evaluated_value(set)
    result = hides_value && !is_err ? _make_hidden_value_result(output) :
             val isa Document ? val :
             _is_silent_nothing(val, output) ? _make_nothing_result() :
             make_evaluator_result_text(rstrip(output))
    element.result = result
    element.is_error = is_err
    push!(t.elements, _make_fresh_form(t))
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
    # A hole of a structured form commits as part of its evaluation, whatever the
    # toplevel says of parsing a string form.
    (t.parse_evaluated_forms || _is_julia_hole(element.form)) && _parse_evaluated_form!(element)
    nothing
end

# The tool answers "Done." for a `nothing` that printed nothing, which is a word
# for a model. The evaluator shows the value itself: the `nothing` of the Julia
# notation, drawn by the Julia domain when one is loaded.
_is_silent_nothing(value, output) = value === nothing && strip(output) == "Done."

# The result of a form whose value is hidden: what its code printed, or no result
# row at all when it printed nothing.
_make_hidden_value_result(output) =
    strip(output) == "Done." ? TextBlock() : make_evaluator_result_text(rstrip(output))

function _make_nothing_result()
    has_natural_parser(:jl) || return make_evaluator_result_text("nothing")
    try
        parse_natural_text(:jl, "nothing")
    catch
        make_evaluator_result_text("nothing")
    end
end

"""
    find_form_document(code) -> document or nothing

The Julia document that the evaluator makes of `code` when it evaluates it as a
form, or `nothing` when the form keeps its string.

A form becomes a Julia document when the document prints back as the same tokens
on the same lines as the code; the spaces between them may change. Otherwise the
form keeps its string: code with a comment, code that the print would change in
another way (the juxtaposed product `2x` prints as `2 * x`), code that does not
parse, or code that no loaded domain reads as Julia. Use it to check the forms of
a script before they are typed.

# Example

    find_form_document("add!(WidgetLabel(\"Go\"))")    # a JuliaCall
    find_form_document("y = 2x + 1")                    # nothing
"""
function find_form_document(code::AbstractString)
    has_natural_parser(:jl) || return nothing
    text = strip(code)
    # A parser throws for a construct it does not support, and that is an answer
    # here, not a fault.
    try
        document = parse_natural_text(:jl, text)
        _has_same_tokens(print_natural_text(document), text) ? document : nothing
    catch
        nothing
    end
end

function _parse_evaluated_form!(element::EvaluatorForm)
    _is_text_form(element.form) || return nothing
    parsed = find_form_document(something(element.form.value, ""))
    parsed === nothing || (element.form = parsed)
    nothing
end

# Whether two pieces of Julia code are the same tokens on the same lines, apart
# from the spaces between the tokens. A space inside a string is part of the
# string's token, and a comment is a token of its own. A line break counts, so
# code of several statements, which the Julia notation prints as an indented
# block with an empty first and last line, keeps its string.
_has_same_tokens(code, other) = _collect_code_tokens(code) == _collect_code_tokens(other)

const _JuliaSyntax = Base.JuliaSyntax

# Whether the last token of the code, apart from a comment, is `;`: the rule by
# which the Julia REPL hides the value of a line.
function _ends_with_semicolon(code::AbstractString)
    tokens = filter(token -> token != "\n" && !startswith(token, "#"), _collect_code_tokens(code))
    !isempty(tokens) && last(tokens) == ";"
end

# The tokens of Julia code with the spaces left out, and one "\n" for each line
# break.
function _collect_code_tokens(code::AbstractString)
    text = String(code)
    tokens = String[]
    for token in _JuliaSyntax.tokenize(text)
        kind = _JuliaSyntax.kind(token)
        piece = _JuliaSyntax.untokenize(token, text)
        if kind == _JuliaSyntax.K"NewlineWs"
            append!(tokens, fill("\n", count(==('\n'), piece)))
        elseif kind != _JuliaSyntax.K"Whitespace"
            push!(tokens, piece)
        end
    end
    tokens
end

# ── ToggleEvaluatorOptionOperation ──────────────────────────────────────────

"""
    ToggleEvaluatorOptionOperation(toplevel, option)

Turn one option of an [`EvaluatorToplevel`](@ref) on or off: `option` is
`:parse_evaluated_forms` or `:type_structured_forms`. A check box above the
forms and a rule of the command palette both make it.

`:type_structured_forms` also changes the bottom form, where the next key goes,
and keeps its text: a string becomes a Julia hole, and a hole or a parsed form
becomes a string. The evaluated forms keep their shape.
`:parse_evaluated_forms` changes only the evaluations that come after it.
"""
struct ToggleEvaluatorOptionOperation <: Operation
    toplevel::EvaluatorToplevel
    option::Symbol
end

# It names the toplevel it changes, not a path into one, so it travels up the
# chain as it is.
OperationModule.is_self_contained_operation(::ToggleEvaluatorOptionOperation) = true

function evaluate_operation(editor, op::ToggleEvaluatorOptionOperation)
    t = op.toplevel
    if op.option === :parse_evaluated_forms
        t.parse_evaluated_forms = !(t.parse_evaluated_forms === true)
    elseif op.option === :type_structured_forms
        t.type_structured_forms = !(t.type_structured_forms === true)
        _change_bottom_form_kind!(editor, t)
    else
        error("ToggleEvaluatorOptionOperation: unknown option $(op.option)")
    end
    nothing
end

# The bottom form becomes the kind a fresh form has now, with the text it had. A
# caret in it keeps its place; a selection anywhere else stays where it is.
function _change_bottom_form_kind!(editor, t::EvaluatorToplevel)
    n = length(t.elements)
    element = t.elements[n]
    # An object stays as it is: it has no text to keep.
    _holds_object(element.form) && return nothing
    fresh = _make_fresh_code(t)
    typeof(fresh) === typeof(element.form) && return nothing
    text = _get_form_source_text(element.form)
    in_form = _find_selected_form_index(t) == n
    range = in_form ? _find_selected_value_range(t) : nothing
    # The selection leaves the old form before it goes, so no selection names a
    # place in a document that is no longer there.
    in_form && _select_in_toplevel!(editor, t, _make_whole_form_reference(n))
    fresh.value = text
    element.form = fresh
    in_form || return nothing
    k = range === nothing ? length(text) : min(range.stop, length(text))
    _select_in_toplevel!(editor, t, _make_form_caret_reference(n, k))
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
OperationModule.is_self_contained_operation(::RecallEvaluatorFormOperation) = true

function evaluate_operation(editor, op::RecallEvaluatorFormOperation)
    t = op.toplevel
    n = length(t.elements)
    form = t.elements[n].form
    _is_text_form(form) || return nothing
    range = _find_selected_value_range(t)
    (range === nothing || _find_selected_form_index(t) != n) && return nothing
    shown = something(form.value, "")
    entries = String[_get_form_source_text(t.elements[k].form) for k in (n - 1):-1:1
                     if !_holds_object(t.elements[k].form)]
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
    _is_text_form(t.elements[i].form) || return nothing
    _find_selected_value_range(t) === nothing && return nothing
    ReplaceStringRangeOperation(t.selection, "\n")
end

# ENTER, when the selection is in the code of a form, `elements[i].form…`. The rule
# claims the key over what an inner layer made of it, because the hole of a
# structured form commits on Enter; so it answers nothing anywhere else, and a
# result that reads Enter keeps it.
function _make_evaluate_operation(t::EvaluatorToplevel)
    _find_selected_form_index(t) === nothing && return nothing
    steps = get_reference_steps(strip_reference_types(t.selection))
    (length(steps) >= 3 && _is_field_step(steps[3], "form")) || return nothing
    EvaluateSelectedFormOperation(t)
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
    override(KeyDown(:return;)) => "Evaluate" => _make_evaluate_operation(doc)
    KeyDown(:return; shift) => "Insert a line break" => _make_form_newline_operation(doc)
    KeyDown(:up;) => "Recall an older form, or go to the form above" => _make_up_operation(doc)
    KeyDown(:down;) => "Recall a newer form, or go to the form below" => _make_down_operation(doc)
    nothing => "Parse evaluated forms" =>
        ToggleEvaluatorOptionOperation(doc, :parse_evaluated_forms)
    nothing => "Type structured forms" =>
        ToggleEvaluatorOptionOperation(doc, :type_structured_forms)
end
