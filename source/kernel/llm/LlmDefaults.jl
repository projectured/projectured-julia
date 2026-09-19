# Fragment of `LlmModule` — the fallback behaviours the provider contract
# supplies itself, for the generics a backend may leave unanswered. The
# contract is declared in `LlmInterface.jl`; the concrete providers live in
# opt-in packages.

# No meaning model, and the two readers of one say which backend has none.
has_meaning_model(::Llm) = false
get_meaning_model_name(llm::Llm) = error(_describe_missing_meaning_model(llm))
compute_meaning_vectors(llm::Llm, texts; purpose::Symbol = :document) =
    error(_describe_missing_meaning_model(llm))

_describe_missing_meaning_model(llm::Llm) =
    string(nameof(typeof(llm))) * " has no meaning model."

# The `Symbol` entries every caller uses; a provider package answers the `Val`.
make_llm(kind::Symbol; kwargs...) = make_llm(Val(kind); kwargs...)
default_llm_model(kind::Symbol) = default_llm_model(Val(kind))

# A kind nothing answered: say which packages are loaded rather than raise a
# bare `MethodError`.
make_llm(::Val{K}; kwargs...) where {K} = error(
    "No LLM backend registered for :$(K). Loaded backends: " *
    (isempty(get_llm_backend_names()) ? "none" :
     join(map(n -> ":" * String(n), get_llm_backend_names()), ", ")) *
    ". Load the opt-in package that provides :$(K).")

default_llm_model(::Val{K}) where {K} = error(
    "No LLM backend registered for :$(K); it has no default model.")
