# Fragment of `ToolModule` — the mark that offers a name to a model, and the
# declaration that the marks of the loaded modules make.

"""
    ASSISTANT_MARK

The line that offers a name to the model of an assistant: `For the assistant.`,
on a line of its own in the docstring of the name. A function carries it in the
docstring of its generic function, `function name end`. A type, a macro or a
constant carries it in its own docstring.

The mark is read by reflection, so the docstring that tells a model what a name
does is also what offers the name. No list beside the code says it again.
"""
const ASSISTANT_MARK = "For the assistant."

"""
    has_assistant_mark(docstring) -> Bool

Whether `docstring` holds [`ASSISTANT_MARK`](@ref) on a line of its own.
"""
has_assistant_mark(docstring::AbstractString) =
    any(line -> strip(line) == ASSISTANT_MARK, eachsplit(docstring, '\n'))

"""
    collect_marked_api() -> Vector{ApiEntry}

The declaration that the marks of the loaded modules make: one entry for each
module that owns a marked name, with its marked names, in the form that
[`declare_api!`](@ref) takes. The entries are in the order of the names of their
modules.

A function is marked when the docstring of its generic function has
[`ASSISTANT_MARK`](@ref): a mark on the docstring of one method offers nothing,
because a model reads the docstring of the generic function. A type, a macro or a
constant is marked when any of its docstrings has the mark.

It reads the modules that are loaded when it runs. A package that loads later
offers its names to the next declaration.

Use it to declare what a model may write: `declare_api!(set, collect_marked_api())`.
"""
function collect_marked_api()
    marked = Dict{Module,Set{Symbol}}()
    for documenting in Base.Docs.modules
        table = Base.Docs.meta(documenting; autoinit = false)
        table === nothing && continue
        for (binding, multidoc) in table
            _is_marked_binding(binding, multidoc) || continue
            push!(get!(Set{Symbol}, marked, binding.mod), binding.var)
        end
    end
    owners = sort!(collect(keys(marked)); by = string)
    ApiEntry[ApiEntry(owner, sort!(collect(marked[owner]))) for owner in owners]
end

# Whether the docstrings of `binding` offer it: the docstring of the generic
# function for a function, any docstring for the rest. A binding whose value is
# gone offers nothing, and neither does a name that `@document` writes beside a
# type, which shares the docstring of the type.
function _is_marked_binding(binding, multidoc)
    isdefined(binding.mod, binding.var) || return false
    value = getfield(binding.mod, binding.var)
    _is_schema_variant(binding.mod, binding.var, value) && return false
    if value isa Function && !startswith(String(binding.var), "@")
        generic = get(multidoc.docs, Union{}, nothing)
        return generic !== nothing && has_assistant_mark(_render_doc(generic))
    end
    any(doc -> has_assistant_mark(_render_doc(doc)), values(multidoc.docs))
end
