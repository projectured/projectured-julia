# Fragment of `OperationModule` — how an operation is written for a human, in one line.

"""
    describe_operation(operation) -> String

How the operation is written for a human: `"select entries[1].value"`,
`"set entries[2].key = \\"b\\""`, `"compound(2): … + …"`.

An operation type that this module does not name falls back to its type name
without the `Operation` suffix, followed by the reference that
`operation_reference` reports. A domain that adds an operation type therefore
needs no change here.
"""
describe_operation(::Nothing) = "no operation"
describe_operation(::DoNothingOperation) = "do nothing"
describe_operation(::InvalidateProjectionOperation) = "print the view again"
describe_operation(::QuitEditorOperation) = "quit"
describe_operation(operation::SetTimerOperation) =
    "set the timer " * string(operation.name)
describe_operation(::SelectNextInsertionOperation) = "select next insertion"
describe_operation(::ToggleCollapseOperation) = "toggle collapse"
describe_operation(operation::ReplaceSelectionOperation) =
    "select " * _short_reference(operation.path)
describe_operation(operation::ReplaceMouseTargetOperation) =
    "point at " * _short_reference(operation.path)

describe_operation(operation::ReplaceReferencedValueOperation) =
    string("set ", _short_reference(operation.reference), " = ",
           _short_value(operation.value))

describe_operation(operation::CompoundOperation) =
    string("compound(", length(operation.operations), "): ",
           join((describe_operation(member) for member in operation.operations), " + "))

function describe_operation(operation)
    name = _operation_name(operation)
    reference = operation_reference(operation)
    reference === nothing ? name : string(name, " ", _short_reference(reference))
end

# The type name without the `Operation` suffix — `ReplaceSelectionOperation`
# reads as `ReplaceSelection`.
function _operation_name(operation)
    name = string(nameof(typeof(operation)))
    endswith(name, "Operation") ? name[1:end - length("Operation")] : name
end

"""
    describe_operation(operation, root) -> String

`describe_operation(operation)`, with each reference written as
[`describe_reference`](@ref) writes it from `root`, the document the references of
`operation` start at: `set items.json › [2].price = 12` in place of the whole
path from the root.
"""
describe_operation(operation, root) =
    with(() -> describe_operation(operation), _DESCRIBED_ROOT => root)

"""
    describe_reference(reference, root) -> String

How `reference` is written for a human, from `root`, the document it starts at:
the title of the deepest document on it that has one, then `›` and the rest of the
path from the document that the titled document edits, as
[`get_edited_field`](@ref) names it. `items.json › [2].price` names a field of the
document a file holds, whatever layers hold the file. A reference with no titled
document on it is written whole.
"""
function describe_reference(reference::Reference, root)
    titled = _find_titled_reference(root, reference)
    titled === nothing || return titled
    _write_reference(reference)
end

# The document that the references of the operation being described start at, or
# `nothing` when the description writes each reference whole.
const _DESCRIBED_ROOT = ScopedValue{Any}(nothing)

# The type checkpoints of a folded reference say nothing to a human and eat the
# whole width, so the skeleton is what the log shows: `entries[1].value`. The
# compact form keeps a step short that would print its whole content.
function _short_reference(reference::Reference)
    root = _DESCRIBED_ROOT[]
    root === nothing ? _write_reference(reference) : describe_reference(reference, root)
end
_short_reference(reference) = _truncate(string(reference), 60)

_write_reference(reference::Reference) =
    _truncate(sprint(show, strip_reference_types(reference);
                     context = :compact => true), 60)

# `title › rest` for the deepest document on `reference` that has a title, where
# `rest` starts at the document that titled document edits; `nothing` when no
# document on it has a title, or when the reference leaves the tree.
function _find_titled_reference(root, reference::Reference)
    steps = get_reference_steps(strip_reference_types(reference))
    nodes = Any[root]
    for step in steps
        node = try
            evaluate_reference_step(step, nodes[end])
        catch
            break
        end
        push!(nodes, node)
    end
    depth = findlast(node -> _get_title_text(node) !== nothing, nodes)
    depth === nothing && return nothing
    title = _get_title_text(nodes[depth])
    # Past the layers the titled document keeps its document in: a file and its history.
    while depth <= length(steps) && depth < length(nodes)
        field = get_edited_field(nodes[depth])
        step = steps[depth]
        (field !== nothing && step isa FieldReferenceStep &&
         step.name == String(field)) || break
        depth += 1
    end
    rest = steps[depth:end]
    isempty(rest) && return title
    title * " › " * _write_reference(extend_reference(EmptyReference(), rest...))
end

# The title a document gives itself, as text, or `nothing` when it gives none.
function _get_title_text(node)
    node isa Document || return nothing
    title = try
        get_document_title(node)
    catch
        nothing
    end
    title === nothing && return nothing
    value = title isa Document && hasproperty(title, :value) ? title.value : title
    text = strip(string(value))
    isempty(text) ? nothing : String(text)
end

# A value that a human can read: a literal keeps its text, a document shows its
# type. A whole document printed into one line is noise.
_short_value(value::Union{AbstractString,Char,Symbol}) = _truncate(repr(value), 24)
_short_value(value::Union{Number,Bool,Nothing}) = string(value)
_short_value(value) = string(nameof(typeof(value)))

_truncate(text::AbstractString, limit::Integer) =
    length(text) <= limit ? String(text) :
        String(text[1:nextind(text, 0, limit - 1)]) * "…"

# A wrapper is what it holds: the wrapper is how a step is recorded, not what the
# step does.
describe_operation(operation::WrappingOperation) =
    describe_operation(get_wrapped_operation(operation))
