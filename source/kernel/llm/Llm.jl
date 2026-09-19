# Fragment of `LlmModule` — what the layer itself does with the provider
# contract: the reflection opacity of a backend, the binding of a meaning
# model to a tool set, and the registry read off the factory's method table.

# A backend is configuration, not addressable document content (it may hold an API
# key or a large scripted payload) — opaque to the reflection walk, so
# `search_references` / `search_documents` never descend into it.
DocumentModule.is_walk_opaque(::Llm) = true

"""
    bind_meaning_model!(set::ToolSet, llm::Llm) -> set

Give `set` the meaning model of `llm`, so that its searches by description rank
by meaning, and start computing the vectors of what they look in.

A backend that has no meaning model leaves `set` as it is. A model that was bound
before goes on answering: the backend a chat talks to is not what decides how a
search ranks.
"""
function bind_meaning_model!(set::ToolSet, llm::Llm)
    has_meaning_model(llm) || return set
    compute = (texts, purpose) -> compute_meaning_vectors(llm, texts; purpose = purpose)
    set_meaning_model!(set, MeaningModel(get_meaning_model_name(llm), compute))
end

"""
    get_llm_backend_names() -> Vector{Symbol}

The backends whose packages are loaded, in alphabetical order. Read from the
method table of `make_llm`, so a backend counts as available exactly when it can
be built — there is nothing to register and nothing to forget to unregister.
"""
function get_llm_backend_names()
    out = Symbol[]
    for m in methods(make_llm)
        # The first argument type of a registered method is `Val{:name}`; the two
        # generic methods in `LlmDefaults.jl` take `Symbol` and `Val{K} where K`,
        # and neither is a backend.
        sig = m.sig
        sig isa UnionAll && continue
        length(sig.parameters) >= 2 || continue
        T = sig.parameters[2]
        T isa DataType && T <: Val || continue
        p = T.parameters[1]
        p isa Symbol && push!(out, p)
    end
    sort!(unique!(out))
end
