# Fragment of `OperationModule` — the fallbacks that the contract supplies itself.

# Nothing to apply: a frame with no operation still evaluates.
function evaluate_operation(editor, op::Nothing) end

# An operation collects only when its type says so. A wrapper, such as the mark
# of view state, collects when what it holds collects, and a join keeps the
# wrapper of the inner operation.
is_collecting_operation(operation) = false
is_collecting_operation(operation::WrappingOperation) =
    is_collecting_operation(get_wrapped_operation(operation))
join_collected_operations(inner::WrappingOperation, outer) =
    rewrap_operation(inner, join_collected_operations(get_wrapped_operation(inner), outer))
join_collected_operations(inner, outer::WrappingOperation) =
    join_collected_operations(inner, get_wrapped_operation(outer))
join_collected_operations(inner::WrappingOperation, outer::WrappingOperation) =
    rewrap_operation(inner, join_collected_operations(get_wrapped_operation(inner),
                                                      get_wrapped_operation(outer)))

# Catch-all: silently ignore anything that is not an Operation. Unlike the device
# I/O generics (which deliberately omit a catch-all so an unimplemented backend
# fails loudly), this one is *meant* to swallow. A reader that declines returns
# `nothing`, which the method above takes. This method takes any other value that
# is not an `Operation`, so a stray value does no harm.
function evaluate_operation(editor, op) end

# A copy with one field replaced, built by the constructor that takes every field.
function with_object_field(object, name::Symbol, value)
    T = typeof(object)
    hasfield(T, name) || throw(ArgumentError("$(T) has no field $(name)"))
    T((field == name ? value : getfield(object, field) for field in fieldnames(T))...)
end

with_object_field(object::NamedTuple, name::Symbol, value) =
    merge(object, NamedTuple{(name,)}((value,)))

# Catch-all: an object that caches no projection has nothing to drop; one that
# does overrides this to clear its cache. Lets an operation ask without naming a
# concrete editor type.
invalidate_projection!(editor) = nothing
