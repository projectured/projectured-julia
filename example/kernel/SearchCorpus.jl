# Fragment of `ProjecturedKernelExample` — the corpus of a whole application: every
# module of the packages it loads, declared so that a search sees each name once.
#
# A window declares about a hundred names, and an application reaches several
# thousand. A measurement of a search is decided at the second size, so this
# gathers the modules of the loaded packages and declares all of them.
# `plan/done/a-classifier-ranks-the-search.md` says which numbers it serves.

"""
    collect_package_modules(prefixes; excluded_suffixes = ("Example", "Test", "Bench"))
        -> Vector{Module}

Every module of the loaded packages whose name starts with one of `prefixes`,
with every module inside it. A package whose name ends with one of
`excluded_suffixes` is left out, because an example, a test or a benchmark is not
the surface of the application. The modules are in the order of their full names,
so the corpus is the same on every run.
"""
function collect_package_modules(prefixes; excluded_suffixes = ("Example", "Test", "Bench"))
    found = Module[]
    seen = Set{Module}()
    function visit(mod::Module)
        mod in seen && return
        push!(seen, mod)
        push!(found, mod)
        for name in names(mod; all = true)
            (isdefined(mod, name) && !Base.isdeprecated(mod, name)) || continue
            value = getfield(mod, name)
            value isa Module && value !== mod && parentmodule(value) === mod && visit(value)
        end
    end
    for (key, mod) in collect(Base.loaded_modules)
        any(prefix -> startswith(key.name, prefix), prefixes) || continue
        any(suffix -> endswith(key.name, suffix), excluded_suffixes) && continue
        visit(mod)
    end
    sort!(found; by = mod -> join(fullname(mod), '.'))
end

"""
    make_corpus_declaration(modules) -> (declaration, dropped)

A declaration of `modules` that gives each name once, as a `module => names` pair
per module. A name is given by the module that owns its binding when that module
exports it, and else by the first module that exports it, so a package that
re-exports the names of others does not take them. A name that a module exports
with another binding than the one already given is dropped, because a
declaration refuses a word that means two things; `dropped` counts those.
"""
function make_corpus_declaration(modules)
    # The module that gives each name, its binding, and whether it owns it.
    given = Dict{Symbol,Tuple{Module,Any,Bool}}()
    dropped = 0
    for mod in modules, name in names(mod)
        name === nameof(mod) && continue
        isdefined(mod, name) || continue
        value = getfield(mod, name)
        owned = Base.binding_module(mod, name) === mod
        previous = get(given, name, nothing)
        if previous === nothing
            given[name] = (mod, value, owned)
        elseif previous[2] === value
            owned && !previous[3] && (given[name] = (mod, value, owned))
        else
            dropped += 1
        end
    end
    kept = Dict{Module,Vector{Symbol}}()
    for (name, (mod, _, _)) in given
        push!(get!(() -> Symbol[], kept, mod), name)
    end
    declaration = Any[mod => Tuple(sort(get(kept, mod, Symbol[]))) for mod in modules]
    declaration, dropped
end

"""
    make_corpus_tool_set(modules) -> (set, dropped)

A `ToolSet` that declares `modules` with [`make_corpus_declaration`](@ref), and
the count of the names it dropped.
"""
function make_corpus_tool_set(modules)
    declaration, dropped = make_corpus_declaration(modules)
    set = ToolSet()
    declare_api!(set, declaration)
    set, dropped
end

"""
    describe_search_corpus(set; io = stdout) -> Dict

Print how many entries the index of `set` holds, by kind and by the package of
their module, and answer the counts by kind.
"""
function describe_search_corpus(set::ToolSet; io::IO = stdout)
    entries = ToolModule._api_index(set.api)
    kinds = Dict{String,Int}()
    packages = Dict{String,Int}()
    modules = Dict(String(nameof(entry.module_)) => entry.module_ for entry in set.api)
    for entry in entries
        kinds[entry.kind] = get(kinds, entry.kind, 0) + 1
        home = get(modules, first(split(entry.qualname, '.')), nothing)
        package = home === nothing ? "?" : String(nameof(Base.moduleroot(home)))
        packages[package] = get(packages, package, 0) + 1
    end
    println(io, length(entries), " entries: ",
            join([string(count, " ", kind) for (kind, count) in sort(collect(kinds))], ", "))
    for (package, count) in sort(collect(packages); by = pair -> -last(pair))
        println(io, "  ", rpad(package, 40), count)
    end
    kinds
end
