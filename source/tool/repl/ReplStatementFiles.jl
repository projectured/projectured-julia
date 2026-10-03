# Fragment of `ReplModule` — the statement files of the packages of this
# repository: the recordings that this repository makes, which package keeps
# which line of a recording, and the files that AutoPrecompile reads.
#
# A package keeps its statements in `package/<Name>/precompile/<recording>.txt`,
# one signature on each line, so that AutoPrecompile finds them in the folder of
# the package, and the release copies them with it.

# The folder of this repository, and the folder of its packages.
const _REPOSITORY = normpath(joinpath(@__DIR__, "..", "..", ".."))
const _PACKAGE_FOLDER = joinpath(_REPOSITORY, "package")

# The folder of a package that holds its statement files.
const _STATEMENT_FOLDER = "precompile"

"""
    PRECOMPILE_RECORDINGS

The recordings of this repository by name: the driver that each one runs, and the
environment that it runs in.

- `"examples"` drives every example of `ProjecturedExample` in a real window, in
  `environment/all`.
- `"readme-data-frame"` does what the README of the release repository tells a
  user to write, `display_in_editor` of a data frame, and sends its window a
  few gestures, in `environment/readme-data-frame`, which holds the packages of
  the README and nothing else.
"""
const PRECOMPILE_RECORDINGS = Dict(
    "examples" => (driver = joinpath(_REPOSITORY, "tool", "precompile", "recording-driver.jl"),
                   project = joinpath(_REPOSITORY, "environment", "all")),
    "readme-data-frame" =>
        (driver = joinpath(_REPOSITORY, "tool", "precompile", "readme-data-frame.jl"),
         project = joinpath(_REPOSITORY, "environment", "readme-data-frame")))

# Each package of this repository, with the packages of this repository that it
# depends on, directly or through others, as the `[deps]` of their `Project.toml`
# files say.
function _collect_package_dependencies()
    direct = Dict{String,Vector{String}}()
    for name in readdir(_PACKAGE_FOLDER)
        project = joinpath(_PACKAGE_FOLDER, name, "Project.toml")
        isfile(project) || continue
        direct[name] = collect(keys(get(TOML.parsefile(project), "deps", Dict())))
    end
    dependencies = Dict{String,Set{String}}()
    function visit(name)
        haskey(dependencies, name) && return dependencies[name]
        found = dependencies[name] = Set{String}()
        for dependency in direct[name]
            haskey(direct, dependency) || continue
            push!(found, dependency)
            union!(found, visit(dependency))
        end
        found
    end
    foreach(visit, keys(direct))
    dependencies
end

# The first name of each dotted name in the signature `line`: the modules that it
# names. A line that does not parse names none.
function _collect_statement_roots(line::AbstractString)
    roots = Set{String}()
    function visit(x)
        x isa Expr || return
        if x.head === :.
            first = x
            while first isa Expr
                first = first.args[1]
            end
            first isa Symbol && push!(roots, String(first))
        else
            foreach(visit, x.args)
        end
    end
    visit(try Meta.parse(line) catch; nothing end)
    roots
end

"""
    split_precompile_statements(statements; dependencies) -> Dict{String,Vector{String}}

The lines of one recording, by the package that keeps them, each list sorted.

A line goes to each package of this repository that it names and that no other
package that it names depends on: a line of the JSON domain goes to
`ProjecturedJSON`, and a line that names only the platform and the kernel goes to
`ProjecturedPlatform`. A line that names no package of this repository goes to the
packages of the recording, the ones that its lines name, that no other package
of the recording depends on. AutoPrecompile reads the file of a package only when
the package is loaded, so such a line applies only when the session loads what
the recording loaded.
"""
function split_precompile_statements(statements;
                                     dependencies = _collect_package_dependencies())
    # The named packages that no other named package depends on.
    select_tops(names) =
        [name for name in names if !any(other -> other != name && name in dependencies[other], names)]
    named = [filter(root -> haskey(dependencies, root), _collect_statement_roots(line))
             for line in statements]
    recording_tops = select_tops(reduce(union!, named; init = Set{String}()))
    files = Dict{String,Vector{String}}()
    for (line, names) in zip(statements, named)
        for owner in (isempty(names) ? recording_tops : select_tops(names))
            push!(get!(files, owner, String[]), line)
        end
    end
    foreach(sort!, values(files))
    files
end

"""
    write_precompile_statement_files(recording, statements) -> Vector{String}

Write the lines of the recording named `recording` into the statement files
`package/<Name>/precompile/<recording>.txt` of the packages that keep them, as
[`split_precompile_statements`](@ref) splits them, and remove the file of the
recording from each package that keeps none of its lines now. Answers the paths
that it wrote.
"""
function write_precompile_statement_files(recording::AbstractString, statements)
    files = split_precompile_statements(statements)
    file_name = recording * ".txt"
    for name in readdir(_PACKAGE_FOLDER)
        path = joinpath(_PACKAGE_FOLDER, name, _STATEMENT_FOLDER, file_name)
        isfile(path) && !haskey(files, name) && rm(path)
    end
    paths = String[]
    for (owner, lines) in sort!(collect(files); by = first)
        path = joinpath(mkpath(joinpath(_PACKAGE_FOLDER, owner, _STATEMENT_FOLDER)), file_name)
        open(path, "w") do io
            println(io, "# The recording \"$recording\" of this repository, written by")
            println(io, "# ProjecturedREPL.record_precompile_statements. Record it again; do not edit it.")
            foreach(line -> println(io, line), lines)
        end
        push!(paths, path)
    end
    paths
end

# The statement folders of the packages of this repository, and the statement
# files in them.
function _collect_statement_folders()
    folders = [joinpath(_PACKAGE_FOLDER, name, _STATEMENT_FOLDER) for name in sort!(readdir(_PACKAGE_FOLDER))]
    filter!(isdir, folders)
end

_collect_statement_files() =
    [joinpath(folder, file) for folder in _collect_statement_folders()
     for file in sort!(readdir(folder)) if endswith(file, ".txt")]

"""
    PRECOMPILE_STATEMENTS

Each line of each statement file of the packages of this repository, once and
sorted: what the leaf replays at the level `:recorded`. It is read while the leaf
precompiles, and each file and each statement folder is a dependency of the
build, so a changed, added or removed file builds the leaf again.
"""
const PRECOMPILE_STATEMENTS = let
    lines = Set{String}()
    foreach(include_dependency, _collect_statement_folders())
    for file in _collect_statement_files()
        include_dependency(file)
        for line in eachline(file)
            line = strip(line)
            (isempty(line) || startswith(line, '#')) || push!(lines, String(line))
        end
    end
    sort!(collect(lines))
end
