# The report of the test check and the guide check of an audit: the exported names
# of a module that no test names, and the ones that the guide of the layer does not
# name. See SEALING.md, "The test check" and "The guide check".
#
#     julia tool/survey-interface.jl CellModule ReferenceModule
#     julia tool/survey-interface.jl            # each module under source/kernel/
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
#
# The guide of a kernel layer is `documentation/package/kernel/<layer>.md`, and the
# guide of another slice is `documentation/package/<group>/<slice>/<slice>.md`. A
# guide names a name when the name occurs in its text. A guide does not have to show
# an example of each name, so the audit reads the examples of the guide too.

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

# The guide of the layer or the slice that `file` belongs to, as a path relative to
# `root`, and whether it exists. A module file at the top of `source/<group>/` belongs
# to no layer, and the answer is `nothing`.
function find_guide_path(root::AbstractString, file::AbstractString)
    parts = splitpath(relpath(file, root))
    (length(parts) >= 4 && parts[1] == "source") || return nothing
    group, folder = parts[2], parts[3]
    flat = joinpath("documentation", "package", group, folder * ".md")
    nested = joinpath("documentation", "package", group, folder, folder * ".md")
    path = group == "kernel" ? flat : nested
    (path, isfile(joinpath(root, path)))
end

# Whether the text of a guide names `name`. A string macro is named by its literal.
function is_named_in_guide(text::AbstractString, name::Symbol)
    word = string(name)
    if startswith(word, "@") && endswith(word, "_str")
        return occursin(word[2:end-4] * "\"", text)
    end
    occursin(Regex("(?<![A-Za-z0-9_@])" * escape_string_for_regex(word) * "(?![A-Za-z0-9_!])"), text)
end

escape_string_for_regex(word::AbstractString) =
    replace(word, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")

function print_interface_report(root::AbstractString, module_names::Vector{Symbol})
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
    untested_total = 0
    unnamed_total = 0
    for name in module_names
        if !haskey(exports, name)
            println(name, ": no module of this name under source/ or package/*/src")
            continue
        end
        names = sort!(collect(exports[name]))
        untested = [exported for exported in names if !(exported in tested)]
        untested_total += length(untested)
        println(name, "  ", relpath(files[name], root), "  ", length(names), " exported")
        isempty(untested) || println("    no test: ", join(untested, ", "))
        guide = find_guide_path(root, files[name])
        if guide === nothing
            println("    no layer, so no guide")
        elseif !guide[2]
            println("    no guide: ", guide[1])
        else
            text = read(joinpath(root, guide[1]), String)
            unnamed = [exported for exported in names if !is_named_in_guide(text, exported)]
            unnamed_total += length(unnamed)
            isempty(unnamed) || println("    not in ", guide[1], ": ", join(unnamed, ", "))
        end
    end
    println(untested_total, " exported names that no test names, and ", unnamed_total,
            " that a guide does not name, in ", length(module_names), " modules")
end

print_interface_report(ROOT, Symbol.(ARGS))
