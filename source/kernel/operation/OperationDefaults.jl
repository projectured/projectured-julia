# Fragment of `OperationModule` — the fallback behaviours the operation
# contract supplies itself. The contract is declared in
# `OperationInterface.jl`; the concrete operations live in `Operations.jl`
# and above.

# Nothing to apply: a frame with no operation still evaluates.
function evaluate_operation(editor, op::Nothing) end

# Catch-all: silently ignore anything that is not an Operation. Unlike the device
# I/O generics (which deliberately omit a catch-all so an unimplemented backend
# fails loudly), this one is *meant* to swallow: a reader that declines returns a
# raw gesture/event or `nothing`, and those flow all the way up to here, where
# "not an operation" simply means "nothing to apply".
function evaluate_operation(editor, op) end
