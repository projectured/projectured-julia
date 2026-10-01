# Fragment of `AssistantModule` — the names that the loaded packages offer to
# the model of an assistant.

# The entries, in the order of the registrations, in the form that
# `declare_api!` takes.
const _ASSISTANT_API = Any[]

"""
    register_assistant_api!(declaration) -> nothing

Offer the names of `declaration` to the model of an assistant. An entry is a
module, which offers every name it exports, or `module => (names...)`, which
offers those names; `declaration` is one entry or a vector of them, the form
that `declare_api!` takes. A package calls this from its `__init__`, so the
names are offered exactly while the package is loaded. An entry that is
registered already is not added again.

A host takes the entries with [`get_assistant_api`](@ref) and declares them
beside its own, so a domain that a session loads helps the model read and
change the documents of that domain.
"""
function register_assistant_api!(declaration)
    entries = declaration isa AbstractVector ? declaration : Any[declaration]
    for entry in entries
        entry in _ASSISTANT_API || push!(_ASSISTANT_API, entry)
    end
    nothing
end

"""
    get_assistant_api() -> Vector

Every entry that a loaded package registered with
[`register_assistant_api!`](@ref), in the order of the registrations.
"""
get_assistant_api() = copy(_ASSISTANT_API)
