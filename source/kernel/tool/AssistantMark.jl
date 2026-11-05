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
    collect_marked_api(; exclude = type -> false) -> Vector{ApiEntry}

The declaration that the marks of the loaded modules make: one entry for each
module that owns a marked name, with its marked names, in the form that
[`declare_api!`](@ref) takes. The entries are in the order of the names of their
modules.

A function is marked when the docstring of its generic function has
[`ASSISTANT_MARK`](@ref): a mark on the docstring of one method offers nothing,
because a model reads the docstring of the generic function. A type, a macro or a
constant is marked when any of its docstrings has the mark.

**A mark on a type also offers its subtypes**: every type that a loaded module
exports below a marked type. So one mark on the root type of a domain offers each
document type of the domain. A subtype for which `exclude` answers `true` stays
out, such as a placeholder that a domain makes for the editor and not for a model.

It reads the modules that are loaded when it runs. A package that loads later
offers its names to the next declaration.

Use it to declare what a model may write: `declare_api!(set, collect_marked_api())`.
"""
function collect_marked_api(; exclude = type -> false)
    marked = Dict{Module,Set{Symbol}}()
    roots = Type[]
    for documenting in Base.Docs.modules
        table = Base.Docs.meta(documenting; autoinit = false)
        table === nothing && continue
        for (binding, multidoc) in table
            name = _find_marked_name(binding, multidoc)
            name === nothing && continue
            push!(get!(Set{Symbol}, marked, binding.mod), name)
            value = getfield(binding.mod, name)
            value isa Type && push!(roots, value)
        end
    end
    isempty(roots) || _add_marked_subtypes!(marked, roots, exclude)
    owners = sort!(collect(keys(marked)); by = string)
    ApiEntry[ApiEntry(owner, sort!(collect(marked[owner]))) for owner in owners]
end

# Add to `marked` every type that a loaded module exports below one of `roots`, at
# the module that owns it, unless `exclude` refuses it. A name that `@document`
# writes beside a type and a name of the module's own business stay out, as they
# do from a search.
function _add_marked_subtypes!(marked, roots, exclude)
    for mod in _collect_loaded_modules(), name in names(mod)
        isdefined(mod, name) || continue
        value = try getfield(mod, name) catch; continue end
        value isa Type || continue
        (_is_private_name(name) || _is_schema_variant(mod, name, value)) && continue
        # The module that defines the name, which also holds for the public name of
        # a `@document` layout family, a `Union` of its layouts.
        (try which(mod, name) catch; nothing end) === mod || continue
        any(root -> value !== root && value <: root, roots) || continue
        exclude(value) && continue
        push!(get!(Set{Symbol}, marked, mod), name)
    end
    marked
end

# Every loaded module and each module that it defines inside it, apart from `Base`
# and `Core`, which define no subtype of a type that a package marks.
function _collect_loaded_modules()
    found = Module[]
    pending = Module[mod for mod in values(Base.loaded_modules) if !(mod in (Base, Core))]
    seen = Set{Module}()
    while !isempty(pending)
        mod = pop!(pending)
        mod in seen && continue
        push!(seen, mod)
        push!(found, mod)
        for name in names(mod; all = true)
            isdefined(mod, name) || continue
            inner = try getfield(mod, name) catch; continue end
            (inner isa Module && inner !== mod && parentmodule(inner) === mod) && push!(pending, inner)
        end
    end
    found
end

# The name that the docstrings of `binding` offer: the docstring of the generic
# function for a function, any docstring for the rest. A docstring of a layout of a
# `@document` family, such as `ACTaskExecution`, offers the name of the family,
# `TaskExecution`, which is what a model writes. `nothing` when they offer nothing,
# or when the value of the binding is gone.
function _find_marked_name(binding, multidoc)
    isdefined(binding.mod, binding.var) || return nothing
    value = getfield(binding.mod, binding.var)
    is_marked = if value isa Function && !startswith(String(binding.var), "@")
        generic = get(multidoc.docs, Union{}, nothing)
        generic !== nothing && has_assistant_mark(_render_doc(generic))
    else
        any(doc -> has_assistant_mark(_render_doc(doc)), values(multidoc.docs))
    end
    is_marked || return nothing
    something(_find_schema_family_name(binding.mod, binding.var, value), binding.var)
end
