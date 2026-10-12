# The report of the test check of an audit: the exported names of a module that no
# test names. See SEALING.md, "The test check".
#
#     julia tool/survey-interface-tests.jl CellModule ReferenceModule
#     julia tool/survey-interface-tests.jl            # each module under source/kernel/
#
# For a domain, name the module under `source/domain/`, for example `JsonModule`. The
# package `ProjecturedJSON` gives out the names of that module when it loads, so the
# syntax tree of the package shows no `export`.
#
# A test names a name when the name occurs in the code of a file under `test/`. The
# script reads the syntax trees and loads no package, so a comment, a docstring and
# a `using` line do not count. A string macro counts by its literal:
# `reference_pattern"…"` names `@reference_pattern_str`. A name that the report does
# not list can still have a weak test, so the audit reads the tests that name it.

const ROOT = normpath(joinpath(@__DIR__, ".."))

# The heads whose names a test brings in or gives out, but does not use.
const SKIPPED_HEADS = (:using, :import, :export, :public)

# Every `.jl` file under `folder`, in a stable order.
function collect_julia_files(folder::AbstractString)
    files = String[]
    for (directory, _, names) in walkdir(folder), name in names
        endswith(name, ".jl") && push!(files, joinpath(directory, name))
    end
    sort!(files)
end

parse_julia_file(path::AbstractString) = Meta.parseall(read(path, String); filename = path)

# Add the exports of each module in `expression` to `exports`, and the file that
# defines the module to `files`. An `include` in the body of a module adds the
# exports of the included file to that module.
function collect_module_exports!(exports::Dict{Symbol,Set{Symbol}}, files::Dict{Symbol,String},
                                 expression, path::AbstractString, owner::Union{Symbol,Nothing})
    expression isa Expr || return
    if expression.head === :module
        name = expression.args[2]::Symbol
        get!(Set{Symbol}, exports, name)
        get!(files, name, path)
        collect_module_exports!(exports, files, expression.args[3], path, name)
    elseif expression.head === :export && owner !== nothing
        for argument in expression.args
            argument isa Symbol && push!(exports[owner], argument)
        end
    elseif expression.head === :call && owner !== nothing && expression.args[1] === :include &&
           length(expression.args) == 2 && expression.args[2] isa String
        included = normpath(joinpath(dirname(path), expression.args[2]))
        isfile(included) || return
        collect_module_exports!(exports, files, parse_julia_file(included), included, owner)
    else
        for argument in expression.args
            collect_module_exports!(exports, files, argument, path, owner)
        end
    end
end

# Add every name that the code of `expression` uses to `symbols`.
function collect_used_symbols!(symbols::Set{Symbol}, expression)
    if expression isa Symbol
        push!(symbols, expression)
    elseif expression isa QuoteNode
        collect_used_symbols!(symbols, expression.value)
    elseif expression isa GlobalRef
        push!(symbols, expression.name)
    elseif expression isa Expr && !(expression.head in SKIPPED_HEADS)
        for argument in expression.args
            collect_used_symbols!(symbols, argument)
        end
    end
    symbols
end

function print_interface_test_report(root::AbstractString, module_names::Vector{Symbol})
    exports = Dict{Symbol,Set{Symbol}}()
    files = Dict{Symbol,String}()
    sources = [joinpath(root, "source"); filter(isdir, joinpath.(root, "package", readdir(joinpath(root, "package")), "src"))]
    for folder in sources, path in collect_julia_files(folder)
        collect_module_exports!(exports, files, parse_julia_file(path), path, nothing)
    end
    tested = Set{Symbol}()
    for path in collect_julia_files(joinpath(root, "test"))
        collect_used_symbols!(tested, parse_julia_file(path))
    end
    if isempty(module_names)
        kernel = joinpath(root, "source", "kernel") * "/"
        module_names = sort!([name for (name, path) in files if startswith(path, kernel)])
    end
    total = 0
    for name in module_names
        if !haskey(exports, name)
            println(name, ": no module of this name under source/ or package/*/src")
            continue
        end
        untested = sort!([string(exported) for exported in exports[name] if !(exported in tested)])
        total += length(untested)
        println(name, "  ", relpath(files[name], root), "  ",
                length(exports[name]), " exported, ", length(untested), " that no test names")
        foreach(untested_name -> println("    ", untested_name), untested)
    end
    println(total, " exported names that no test names, in ", length(module_names), " modules")
end

print_interface_test_report(ROOT, Symbol.(ARGS))
