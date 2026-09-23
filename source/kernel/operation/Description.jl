# Fragment of `OperationModule` — how an operation is written for a human. One
# line, short enough for a list: `select entries[1].value`, `set entries[2].key =
# "b"`, `compound(2): … + …`.
#
# It lives beside the operations it describes, because more than one thing shows
# a list of them: a log of what the person did, a history of what can be taken
# back, a listing of what is available.

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
describe_operation(operation::ReplaceViewStateOperation) = describe_operation(operation.operation)
describe_operation(::QuitEditorOperation) = "quit"
describe_operation(::SelectNextInsertionOperation) = "select next insertion"
describe_operation(::ToggleCollapseOperation) = "toggle collapse"
describe_operation(operation::ReplaceSelectionOperation) = "select " * _short_reference(operation.path)
describe_operation(operation::AdjustZoomOperation) = "zoom " * _delta(operation.delta)
describe_operation(operation::AdjustFontZoomOperation) = "font zoom " * _delta(operation.delta)

describe_operation(operation::ReplaceReferencedValueOperation) =
    string("set ", _short_reference(operation.reference), " = ", _short_value(operation.value))

describe_operation(operation::CompoundOperation) =
    string("compound(", length(operation.operations), "): ",
           join((describe_operation(member) for member in operation.operations), " + "))

function describe_operation(operation)
    name = _operation_name(operation)
    reference = operation_reference(operation)
    reference === nothing ? name : string(name, " ", _short_reference(reference))
end

# The type name without the `Operation` suffix — `StringReplaceRangeOperation`
# reads as `StringReplaceRange`.
function _operation_name(operation)
    name = string(nameof(typeof(operation)))
    endswith(name, "Operation") ? name[1:end - length("Operation")] : name
end

_delta(delta::Integer) = delta > 0 ? "in" : delta < 0 ? "out" : "reset"

# The type checkpoints of a folded reference say nothing to a human and eat the
# whole width, so the skeleton is what the log shows: `entries[1].value`.
_short_reference(reference::Reference) = _truncate(string(strip_reference_types(reference)), 60)
_short_reference(reference) = _truncate(string(reference), 60)

# A value that a human can read: a literal keeps its text, a document shows its
# type. A whole document printed into one line is noise.
_short_value(value::Union{AbstractString,Char,Symbol}) = _truncate(repr(value), 24)
_short_value(value::Union{Number,Bool,Nothing}) = string(value)
_short_value(value) = string(nameof(typeof(value)))

_truncate(text::AbstractString, limit::Integer) =
    length(text) <= limit ? String(text) : String(text[1:nextind(text, 0, limit - 1)]) * "…"

# A wrapper is what it holds: the wrapper is how a step is recorded, not what the
# step does.
describe_operation(operation::WrappingOperation) =
    describe_operation(get_wrapped_operation(operation))
