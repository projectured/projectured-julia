# Fragment of `AssistantModule` — the names that the loaded packages offer to
# the model of an assistant, and the sentence that tells the model about them.

# The entries, in the order of the registrations, in the form that
# `declare_api!` takes.
const _ASSISTANT_API = Any[]

# The sentences that the packages gave with their names, in the order of the
# registrations.
const _ASSISTANT_API_DESCRIPTIONS = String[]

"""
    register_assistant_api!(declaration; description = "") -> nothing

Offer the names of `declaration` to the model of an assistant. An entry is a
module, which offers every name it exports, or `module => (names...)`, which
offers those names; `declaration` is one entry or a vector of them, the form
that `declare_api!` takes, and an empty vector offers no name. A package calls
this from its `__init__`, so the names are offered exactly while the package is
loaded. An entry that is registered already is not added again.

`description` is what the system text of a window tells the model about these
names, such as how a graph is made of them, so the system text names a domain
only while the domain is loaded. A sentence that is registered already is not
added again.

A host takes the entries with [`get_registered_assistant_api`](@ref) and
declares them beside its own, so a domain that a session loads helps the model
read and change the documents of that domain, and it takes the sentences with
[`describe_registered_assistant_api`](@ref).
"""
function register_assistant_api!(declaration; description::AbstractString = "")
    entries = declaration isa AbstractVector ? declaration : Any[declaration]
    for entry in entries
        entry in _ASSISTANT_API || push!(_ASSISTANT_API, entry)
    end
    sentence = String(strip(description))
    isempty(sentence) || sentence in _ASSISTANT_API_DESCRIPTIONS ||
        push!(_ASSISTANT_API_DESCRIPTIONS, sentence)
    nothing
end

"""
    get_registered_assistant_api() -> Vector

Every entry that a loaded package registered with
[`register_assistant_api!`](@ref), in the order of the registrations.
"""
get_registered_assistant_api() = copy(_ASSISTANT_API)

"""
    describe_registered_assistant_api() -> String

The sentences that the loaded packages registered with their names, in the
order of the registrations, as one paragraph of the system text of a window.
Empty when no loaded package gave a sentence.
"""
describe_registered_assistant_api() = join(_ASSISTANT_API_DESCRIPTIONS, " ")
