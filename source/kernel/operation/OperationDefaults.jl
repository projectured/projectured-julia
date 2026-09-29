# Fragment of `OperationModule` — the fallbacks that the contract supplies itself.

# Nothing to apply: a frame with no operation still evaluates.
function evaluate_operation(editor, op::Nothing) end

# Catch-all: silently ignore anything that is not an Operation. Unlike the device
# I/O generics (which deliberately omit a catch-all so an unimplemented backend
# fails loudly), this one is *meant* to swallow. A reader that declines returns
# `nothing`, which the method above takes. This method takes any other value that
# is not an `Operation`, so a stray value does no harm.
function evaluate_operation(editor, op) end

# Catch-all: an object that caches no projection has nothing to drop; one that
# does overrides this to clear its cache. Lets an operation ask without naming a
# concrete editor type.
invalidate_projection!(editor) = nothing
