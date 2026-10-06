# Fragment of `NavigatorModule` — the path view of the address: the steps of the
# address copy as syntax, one after the other, where a person types a path in
# place.
#
#     children[i]    step i: `.name`, `[i]`, or the buffer of a `ReferenceInsertion`
#
# A committed step is a value and holds no caret: a press in it selects the step,
# and a key on it turns the step into an insertion with its text and the key. An
# insertion holds the text of any number of steps until Enter reads the path.

"""
    make_navigator_address_projection(navigator; syntax_theme = nothing) -> Projection

The projection of the address copy of `navigator` to syntax: each step after the
other, `.name` for a field and `[i]` for an element, and a `ReferenceInsertion` as
a buffer that a person types into, with a hint that completes the name of a field
of the content of `navigator`. `syntax_theme` is a `SyntaxTheme`, scaled or not, or
`nothing` for the default styles.
"""
function make_navigator_address_projection(navigator::Navigator; syntax_theme = nothing)
    RecursiveProjection(TypeDispatchingProjection(
        NavigatorAddress => NavigatorAddressToSyntaxNode(),
        FieldReferenceStep => ReferenceStepToSyntaxLeaf(; style = get_syntax_style(syntax_theme, :typed_text)),
        RangeReferenceStep => ReferenceStepToSyntaxLeaf(; style = get_syntax_style(syntax_theme, :typed_text)),
        ReferenceInsertion => InsertionToSyntaxLeaf((insertion, text) -> nothing;
                                                    completion = insertion -> _complete_step(navigator, insertion),
                                                    cancel = insertion -> insertion,
                                                    placeholder = "type a path, such as .name or [2]",
                                                    theme = syntax_theme),
        Vector{Cell} => CopyingProjection()))
end

# The steps of a `NavigatorAddress` as one syntax node, with nothing between two
# steps.
@projection UntrackedCell struct NavigatorAddressToSyntaxNode end

@projection_template NavigatorAddressToSyntaxNode NavigatorAddress (prj, doc) ->
    SyntaxNode(collection(:steps))

"""
    ReferenceStepToSyntaxLeaf(; style)

A committed step of an address as a syntax leaf, `.name` or `[i]`, in `style`. A
step is a value, so any place in its text is the whole step. A key on the step
turns it into a `ReferenceInsertion` with the text of the step and the key, with
the caret at its end; Backspace removes the last character of the text.
"""
@projection UntrackedCell struct ReferenceStepToSyntaxLeaf
    style::StyleText = get_syntax_style(nothing, :typed_text)
end

print_document(p::ReferenceStepToSyntaxLeaf, recursion, step, ctx) =
    SimpleIoMap(p, step, SyntaxLeaf(TextString(_get_step_text(step), p.style)))

map_reference_forward(::ReferenceStepToSyntaxLeaf, iomap, reference) =
    reference isa EmptyReference ? EmptyReference(get_reference_node_type(iomap.output)) : nothing

map_reference_backward(::ReferenceStepToSyntaxLeaf, iomap, reference) =
    EmptyReference(get_reference_node_type(iomap.input))

function read_intent(p::ReferenceStepToSyntaxLeaf, iomap, operation::ReplaceStringRangeOperation)
    text = _get_step_text(iomap.input)
    _make_step_insertion_operation(isempty(operation.replacement) ? chop(text) : text * operation.replacement)
end

function read_intent(p::ReferenceStepToSyntaxLeaf, iomap, key::KeyPress)
    isprint(key.char) || return nothing
    _make_step_insertion_operation(_get_step_text(iomap.input) * key.text)
end

function read_intent(p::ReferenceStepToSyntaxLeaf, iomap, key::KeyDown)
    key.key === :backspace && !(key.modifiers.ctrl || key.modifiers.alt || key.modifiers.meta) ||
        return nothing
    _make_step_insertion_operation(chop(_get_step_text(iomap.input)))
end

# The replace of the step with an insertion of `text`, with the caret at its end.
function _make_step_insertion_operation(text::AbstractString)
    insertion = ReferenceInsertion(; value = String(text))
    n = length(insertion.value)
    replace_selection!(insertion, ConcreteReference(ReferenceInsertion, FieldReferenceStep("value"),
                                                    ConcreteReference(String, RangeReferenceStep(n, n),
                                                                      EmptyReference(Position))))
    make_replace_document_operation(EmptyReference(), insertion)
end

# The completion of the name of the last step of an insertion: the rest of the
# one field name of the node before it that starts with the typed name, or no
# hint when none or more than one does.
function _complete_step(navigator::Navigator, insertion::ReferenceInsertion)
    text = something(insertion.value, "")
    isempty(text) && return (state = :empty, hint = "", extension = "")
    m = match(r"^(.*)\.([^.\[\]]*)$", text)
    prefix_steps = _find_steps_before(navigator, insertion, m === nothing ? text : m.captures[1])
    prefix_steps === nothing && return (state = :invalid, hint = "", extension = "")
    m === nothing && return (state = :unambiguous, hint = "", extension = "")
    node = try_evaluate_reference(navigator.content, extend_reference(EmptyReference(), prefix_steps...),
                                  _NOT_REACHED)
    node === _NOT_REACHED && return (state = :invalid, hint = "", extension = "")
    typed = something(m.captures[2], "")
    names = String[String(name) for name in fieldnames(typeof(node))
                   if !is_view_state_field(name) && startswith(String(name), typed)]
    isempty(names) && return (state = :invalid, hint = "", extension = "")
    length(names) == 1 || return (state = :ambiguous, hint = "", extension = _common_prefix(names)[(length(typed) + 1):end])
    rest = names[1][(length(typed) + 1):end]
    (state = :unambiguous, hint = rest, extension = rest)
end

# The steps of the address copy before `insertion`, and the steps of `text`, or
# `nothing` when a text before it is no path.
function _find_steps_before(navigator::Navigator, insertion::ReferenceInsertion, text::AbstractString)
    steps = ReferenceStep[]
    for step in navigator.address_draft.steps
        step === insertion && break
        parsed = _parse_step_text(step)
        parsed === nothing && return nothing
        append!(steps, parsed)
    end
    parsed = _parse_path_steps(text)
    parsed === nothing ? nothing : vcat(steps, parsed)
end

_parse_step_text(step::Union{FieldReferenceStep, RangeReferenceStep}) = ReferenceStep[step]
_parse_step_text(step::ReferenceInsertion) = _parse_path_steps(something(step.value, ""))

# The steps of the text of a path, such as `.books[2]`, or `nothing` when it is no
# path: a field is `.` and a name, and an element is a number from 1 in brackets.
function _parse_path_steps(text::AbstractString)
    steps = ReferenceStep[]
    rest = text
    while !isempty(rest)
        m = match(r"^\.([^.\[\]]+)", rest)
        if m !== nothing
            push!(steps, FieldReferenceStep(String(m.captures[1])))
        else
            m = match(r"^\[([1-9][0-9]*)\]", rest)
            m === nothing && return nothing
            index = parse(Int, m.captures[1])
            push!(steps, RangeReferenceStep(index - 1, index))
        end
        rest = SubString(rest, ncodeunits(m.match) + 1)
    end
    steps
end

function _common_prefix(names::Vector{String})
    prefix = names[1]
    for name in names[2:end]
        while !startswith(name, prefix)
            prefix = prefix[1:prevind(prefix, lastindex(prefix))]
        end
    end
    prefix
end
