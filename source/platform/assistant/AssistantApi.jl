# Fragment of `AssistantModule` — the sentences that the loaded packages give the
# model of an assistant about their domains, and the names of the foreign packages
# that an adapter offers.

# The entries, in the order of the registrations, each as an `ApiEntry`.
const _ASSISTANT_API = ApiEntry[]

# The sentences that the packages gave, in the order of the registrations.
const _ASSISTANT_API_DESCRIPTIONS = String[]

"""
    register_assistant_api!(declaration; description = "") -> nothing

Give the model of an assistant a sentence about a domain, and the names of a
foreign package. A package gives the `description` that the system text of a window
says about its domain, such as how a graph is made of its names, so the system
text names a domain only while the domain is loaded. An adapter gives
`declaration`, the names of a foreign package such as `DataFrames`, whose
docstrings no mark can reach. An entry is a module, which offers every name it
exports, or `module => (names...)`, which offers those names; `declaration` is
one entry or a vector of them, the form that `declare_api!` takes, and an empty
vector offers no name. A name of the editor's own packages is not registered: the
line `For the assistant.` in its docstring offers it. A package calls this from
its `__init__`, so the sentence and the names are offered exactly while the
package is loaded. An entry or a sentence that is registered already is not added
again.

A host takes the entries with [`get_registered_assistant_api`](@ref) and
declares them beside the marked names, and it takes the sentences with
[`describe_registered_assistant_api`](@ref).
"""
function register_assistant_api!(declaration; description::AbstractString = "")
    entries = declaration isa AbstractVector ? declaration : Any[declaration]
    for entry in entries
        stored = _make_registered_entry(entry)
        stored in _ASSISTANT_API || push!(_ASSISTANT_API, stored)
    end
    sentence = String(strip(description))
    isempty(sentence) || sentence in _ASSISTANT_API_DESCRIPTIONS ||
        push!(_ASSISTANT_API_DESCRIPTIONS, sentence)
    nothing
end

# An entry as the registry keeps it: a module offers every name it exports, and a
# pair offers the names it gives.
_make_registered_entry(entry::ApiEntry) = entry
_make_registered_entry(mod::Module) = ApiEntry(mod, nothing)
_make_registered_entry(pair::Pair{Module}) = ApiEntry(first(pair), last(pair))

"""
    get_registered_assistant_api() -> Vector{ApiEntry}

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
