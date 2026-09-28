# Fragment of `OperationModule` — the fallback behaviours the operation
# contract supplies itself. The contract is declared in
# `OperationInterface.jl`; the concrete operations live in `Operations.jl`
# and above.

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
# fails loudly), this one is *meant* to swallow: a reader that declines returns a
# raw gesture/event or `nothing`, and those flow all the way up to here, where
# "not an operation" simply means "nothing to apply".
function evaluate_operation(editor, op) end
