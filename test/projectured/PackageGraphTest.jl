# The package dependency graph, checked statically from the Project.toml files.
#
# One package per domain only pays off while the edges stay honest. Nothing in
# Julia stops a domain from picking up a dependency it does not need — the
# `[deps]` entry is one line and everything keeps working — so the shape is
# asserted here instead of trusted.
#
# Two things are checked. The graph must be acyclic, which is what lets the
# packages be loaded, precompiled and reasoned about in an order. And each
# domain's declared domain dependencies must match the table below, so a new
# edge is a deliberate edit here rather than a side effect.

using Test

const _PACKAGE_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

# domain package -> the other domain packages it may depend on.
# An edge here is one domain holding or making another domain's documents: a
# state machine guard is a Julia expression, a catalog prints as SQL statements,
# and the code of a formula is a Julia tree or a math tree.
const DOMAIN_EDGES = Dict(
    "ProjecturedJSON"          => String[],
    "ProjecturedYAML"          => String[],
    "ProjecturedXML"           => String[],
    "ProjecturedMarkdown"      => String[],
    "ProjecturedRST"           => String[],
    "ProjecturedBook"          => String[],
    "ProjecturedMath"          => String[],
    "ProjecturedJulia"         => String[],
    "ProjecturedSQL"           => String[],
    "ProjecturedDatabase"      => String[],
    "ProjecturedGraph"         => String[],
    "ProjecturedChart"         => String[],
    "ProjecturedSequenceChart" => String[],
    "ProjecturedDBCatalog"     => ["ProjecturedSQL"],
    "ProjecturedFormula"       => ["ProjecturedJulia", "ProjecturedMath"],
    "ProjecturedFSM"           => ["ProjecturedGraph", "ProjecturedJulia"],
    "ProjecturedProcess"       => ["ProjecturedGraph", "ProjecturedJulia"],
    "ProjecturedPivot"         => ["ProjecturedChart"],
    "ProjecturedWorkflow"      => String[],
    "ProjecturedResearch"      => ["ProjecturedFormula", "ProjecturedGraph", "ProjecturedMarkdown", "ProjecturedMath"],
)

# The kernel is the one package every other package may reach. Below the
# domains are the platform and the two backends that need no outside library; a
# domain may depend on any of them, and none of them may depend on a domain.
const KERNEL = "ProjecturedKernel"

const BELOW_THE_DOMAINS = ["ProjecturedPlatform", "ProjecturedConsole", "ProjecturedPDF"]


"""
The leaves: a package nothing may depend on. `ProjecturedBench` is one because it
loads `ProjecturedExample` to measure it, and `ProjecturedBuild` is the package
of the binary `projectured`. `ProjecturedBuilder` is not here: it is a tool that
drives a build, not a package a session loads. The small package that a build
writes under `build/app/`, outside `package/`, is a leaf too.
"""
const _LEAVES = ("ProjecturedREPL", "ProjecturedBench", "ProjecturedBuild")

"""
The packages that a user loads and whose first window the workload of their
`@compile_ahead` runs, by the rules of `package-rules.md`.
"""
const _FIRST_WINDOW_PACKAGES = ("ProjecturedPlatform", "ProjecturedDataFrames", "ProjecturedSDL")

"""
    _has_natural_rows(name) -> Bool

Whether the slice of the package `name` calls a `register_natural_…!` function
or defines a method of `make_graphics_projection` for a type, so that every
first window builds rows of it. Such a package compiles them in the workload of
the `@compile_ahead` of its entry file, by the rules of `package-rules.md`.
"""
function _has_natural_rows(name)
    dir = _source_dir(name)
    dir === nothing && return false
    for (root, _dirs, files) in walkdir(dir), file in files
        endswith(file, ".jl") || continue
        text = read(joinpath(root, file), String)
        (occursin(r"(?m)^[^#\n]*\bregister_natural_\w+!\(", text) ||
         occursin(r"(?m)^make_graphics_projection\(::Type\{", text)) && return true
    end
    false
end

"""
    _has_workload_file(name) -> Bool

Whether the slice of the package `name` defines a method of `make_workload_file`,
the file of its format that the application window opens in a workload. Such a
package runs the gestures of that file in a `@compile_workload` of its entry
file, by the rules of `package-rules.md`.
"""
function _has_workload_file(name)
    dir = _source_dir(name)
    dir === nothing && return false
    for (root, _dirs, files) in walkdir(dir), file in files
        endswith(file, ".jl") || continue
        occursin(r"(?m)^make_workload_file\(::Type\{", read(joinpath(root, file), String)) &&
            return true
    end
    false
end

"""
    _is_main_package(name) -> Bool

A package that holds code, rather than a suite or an example gallery. `package/`
is flat, so the kind a directory used to encode is read from the name, and the
reserved suffixes are the whole of it.

A leaf and the build tool are included. They are code, they declare
dependencies, and the rules that do **not** apply to them say so themselves —
`_LEAVES` is what they test against. Excluding them here instead cost two
assertions in "every package declares exactly the packages it names", and a
guard that stops looking is the failure this whole move kept finding.
"""
_is_main_package(name) = !endswith(name, "Test") && !endswith(name, "Example")

"""
    _source_dir(name) -> Union{String,Nothing}

Where a package's source lives, or `nothing` when it has none — an umbrella and
a one-file package keep everything in the root file the package holds. It is the
common folder of the files under `source/` that the root file includes: the
folder of a slice, such as `source/domain/json`, or of a group, `source/platform`.
"""
function _source_dir(name)
    top = joinpath(_PACKAGE_ROOT, "package", name, "src", name * ".jl")
    isfile(top) || return nothing
    folders = [splitpath(dirname(normpath(joinpath(dirname(top), found.captures[1]))))
               for found in eachmatch(r"^include\(\"([^\"]*source/[^\"]+)\"\)"m,
                                      read(top, String))]
    isempty(folders) && return nothing
    depth = 0
    while all(parts -> length(parts) > depth && parts[depth + 1] == folders[1][depth + 1],
              folders)
        depth += 1
    end
    dir = joinpath(folders[1][1:depth]...)
    isdir(dir) ? dir : nothing
end

"""
    _read_package_graph() -> Dict{String,Vector{String}}

Every package that holds code, mapped to the `Projectured*` packages it
declares. Read from the `Project.toml` files, not from the loaded modules, so a
dependency that is declared but unused still shows up.
"""
function _read_package_graph()
    graph = Dict{String,Vector{String}}()
    for entry in sort(readdir(joinpath(_PACKAGE_ROOT, "package")))
        _is_main_package(entry) || continue
        proj = joinpath(_PACKAGE_ROOT, "package", entry, "Project.toml")
        isfile(proj) || continue
        text = read(proj, String)
        name = match(r"(?m)^name = \"([^\"]+)\"", text)
        name === nothing && continue
        deps = String[]
        in_deps = false
        for line in split(text, "\n")
            if startswith(line, "[")
                in_deps = line == "[deps]"
                continue
            end
            in_deps || continue
            m = match(r"^(Projectured\w*) = ", line)
            m === nothing || push!(deps, m.captures[1])
        end
        graph[name.captures[1]] = deps
    end
    graph
end

"""
    _read_all_packages() -> Dict{String,Vector{String}}

**Every** package in the tree, not only `package/*/main` — the example, test,
repl and executable packages included — mapped to the `Projectured*` packages it
declares. The leaf rules are about exactly those kinds, so they need a reader
that can see them.
"""
function _read_all_packages()
    packages = Dict{String,Vector{String}}()
    for (root, _dirs, files) in walkdir(joinpath(_PACKAGE_ROOT, "package"))
        "Project.toml" in files || continue
        text = read(joinpath(root, "Project.toml"), String)
        name = match(r"(?m)^name = \"([^\"]+)\"", text)
        name === nothing && continue
        deps = String[]
        in_deps = false
        for line in split(text, "\n")
            if startswith(line, "[")
                in_deps = line == "[deps]"
                continue
            end
            in_deps || continue
            m = match(r"^(Projectured\w*) = ", line)
            m === nothing || push!(deps, m.captures[1])
        end
        packages[name.captures[1]] = deps
    end
    packages
end


"""
    _named_packages(name) -> Set{String}

The `Projectured*` packages a package's own source names: the owner of every
`..XxxModule` reference, every `Package.XxxModule` path, and every
`using`/`import` line. A declared dependency the source never names is a
dependency the package does not have.
"""
function _named_packages(name)
    isempty(_MODULE_OWNER) && _build_module_owner()
    named = Set{String}()
    for dir in _MAIN_DIR[name], (root, _dirs, files) in walkdir(dir), f in files
        endswith(f, ".jl") || continue
        # A docstring may show a `using` line as an example, which is prose, not
        # a dependency.
        text = replace(read(joinpath(root, f), String), r"(?s)\"\"\".*?\"\"\"" => "")
        for m in eachmatch(r"\.\.(\w+Module)\b", text)
            owner = get(_MODULE_OWNER, m.captures[1], nothing)
            owner === nothing || owner == name || push!(named, owner)
        end
        for m in eachmatch(r"\b(Projectured\w*)\.\w+Module\b", text)
            m.captures[1] == name || push!(named, m.captures[1])
        end
        for m in eachmatch(r"(?m)^\s*(?:using|import) (Projectured\w*)", text)
            m.captures[1] == name || push!(named, m.captures[1])
        end
    end
    named
end

const _MODULE_OWNER = Dict{String,String}()
# Package => the folders its code lives in. There are three, and a package may
# have only the first: the directory that holds its root file, `source/`, where
# everything the root file includes lives, and `ext/`, which holds its package
# extensions. Scanning one of them is how a guard goes on passing while it covers
# nothing — the root file alone names almost no dependency.
const _MAIN_DIR = Dict{String,Vector{String}}()

"Fill `_MODULE_OWNER` (submodule => package) and `_MAIN_DIR` (package => folders)."
function _build_module_owner()
    for entry in sort(readdir(joinpath(_PACKAGE_ROOT, "package")))
        _is_main_package(entry) || continue
        dir = joinpath(_PACKAGE_ROOT, "package", entry)
        proj = joinpath(dir, "Project.toml")
        isfile(proj) || continue
        name = match(r"(?m)^name = \"([^\"]+)\"", read(proj, String)).captures[1]
        dirs = [joinpath(dir, "src")]
        source = _source_dir(name)
        source === nothing || push!(dirs, source)
        isdir(joinpath(dir, "ext")) && push!(dirs, joinpath(dir, "ext"))
        _MAIN_DIR[name] = dirs
        for d in dirs, (root, _dirs, files) in walkdir(d), f in files
            endswith(f, ".jl") || continue
            for m in eachmatch(r"(?m)^module\s+(\w+)\s*$", read(joinpath(root, f), String))
                m.captures[1] == name || (_MODULE_OWNER[m.captures[1]] = name)
            end
        end
    end
end

"""
    test_package_graph()

The package dependency graph is acyclic, and every domain package declares
exactly the domain edges the table above allows.
"""
function test_package_graph()
    @testset "package dependency graph" begin
        graph = _read_package_graph()

        @testset "every domain package is present" begin
            for name in keys(DOMAIN_EDGES)
                @test haskey(graph, name)
            end
        end

        @testset "the graph is acyclic" begin
            # A depth-first walk that reports the cycle it closes rather than
            # only that one exists — the name of the offending edge is what a
            # reader needs.
            state = Dict{String,Symbol}()   # :open while on the stack, :done after
            cycles = String[]
            function visit(node, stack)
                get(state, node, :new) === :done && return
                if get(state, node, :new) === :open
                    at = findfirst(==(node), stack)
                    push!(cycles, join(vcat(stack[at:end], node), " -> "))
                    return
                end
                state[node] = :open
                for dep in get(graph, node, String[])
                    haskey(graph, dep) && visit(dep, vcat(stack, node))
                end
                state[node] = :done
            end
            for node in sort(collect(keys(graph)))
                visit(node, String[])
            end
            isempty(cycles) || println(stderr, "\nDependency cycles:\n  ",
                                       join(cycles, "\n  "))
            @test isempty(cycles)
        end

        @testset "each domain declares the edges the table allows" begin
            for (name, allowed) in sort(collect(DOMAIN_EDGES))
                haskey(graph, name) || continue
                actual = sort(filter(d -> haskey(DOMAIN_EDGES, d), graph[name]))
                if actual != sort(allowed)
                    println(stderr, "\n$name declares $actual, table says $(sort(allowed))")
                end
                @test actual == sort(allowed)
            end
        end

        @testset "each domain depends on the kernel" begin
            for name in sort(collect(keys(DOMAIN_EDGES)))
                haskey(graph, name) || continue
                @test KERNEL in graph[name]
            end
        end

        @testset "no package below the domains depends on a domain" begin
            for e in vcat([KERNEL], BELOW_THE_DOMAINS)
                haskey(graph, e) || continue
                for dep in graph[e]
                    haskey(DOMAIN_EDGES, dep) &&
                        println(stderr, "\n$e depends on the domain $dep")
                    @test !haskey(DOMAIN_EDGES, dep)
                end
            end
        end

        @testset "every package declares exactly the packages it names" begin
            for (name, declared) in sort(collect(graph))
                named = _named_packages(name)
                extra = setdiff(Set(declared), named)
                missed = setdiff(named, Set(declared))
                isempty(extra) &&
                    isempty(missed) || println(stderr,
                        "\n$name declares $(sort(collect(extra))) it never names, " *
                        "and names $(sort(collect(missed))) it never declares")
                @test isempty(extra)
                @test isempty(missed)
            end
        end

        # ── The leaf rules ──────────────────────────────────────────────────
        #
        # A package image is built with exactly that package's dependencies
        # present, so compiled code survives only in a package nothing depends
        # on and nothing loads after. These rules keep that true, and they are
        # asserted rather than described because the cost of breaking one is
        # invisible: it shows up as a slow first paint, not as a failure.
        # See plan/pending/package-convention-repl-leaves.md.

        packages = _read_all_packages()

        @testset "nothing depends on a leaf" begin
            for (name, deps) in sort(collect(packages))
                for leaf in _LEAVES
                    leaf in deps &&
                        println(stderr, "\n$name depends on the leaf $leaf")
                    @test !(leaf in deps)
                end
            end
        end

        @testset "an example package is a dependency only of a leaf, an example or a test" begin
            for (name, deps) in sort(collect(packages))
                (endswith(name, "Example") || endswith(name, "Test")) && continue
                name in _LEAVES && continue
                examples = sort(filter(d -> endswith(d, "Example"), deps))
                isempty(examples) ||
                    println(stderr, "\n$name depends on the example package(s) $examples")
                @test isempty(examples)
            end
        end

        @testset "a package compiles ahead only with @compile_ahead, once, in its entry file" begin
            offenders = String[]
            # Both trees: a package is a name and an include list, and the
            # list it names lives under `source/`.
            for area in ("package", "source"),
                (root, _dirs, files) in walkdir(joinpath(_PACKAGE_ROOT, area))
                # The mechanism itself shows the call in its documentation.
                occursin(joinpath("source", "tool", "precompile"), root) && continue
                for file in files
                    endswith(file, ".jl") || continue
                    path = joinpath(root, file)
                    text = read(path, String)
                    # A call, not a mention: the macro at the head of a line.
                    # Prose about it, and this test's own message, must not count.
                    occursin(r"(?m)^\s*@compile_workload\b", text) &&
                        push!(offenders, relpath(path, _PACKAGE_ROOT) * ": @compile_workload")
                    calls = count(r"(?m)^\s*@compile_ahead\b", text)
                    calls == 0 && continue
                    name = basename(dirname(dirname(path)))
                    is_entry = area == "package" && file == "$name.jl" &&
                               basename(dirname(path)) == "src"
                    (is_entry && calls == 1) ||
                        push!(offenders, relpath(path, _PACKAGE_ROOT) * ": @compile_ahead $calls times")
                    is_entry && !("ProjecturedPrecompile" in get(packages, name, String[])) &&
                        push!(offenders, relpath(path, _PACKAGE_ROOT) * ": no ProjecturedPrecompile in [deps]")
                end
            end
            isempty(offenders) ||
                println(stderr, "\na compile ahead outside the one call of an entry file:\n  ",
                        join(offenders, "\n  "))
            @test isempty(offenders)
        end

        @testset "a package with natural rows compiles them in its entry file" begin
            missing_workload = String[]
            for name in sort(collect(keys(packages)))
                (name in _LEAVES || name in _FIRST_WINDOW_PACKAGES) && continue
                _has_natural_rows(name) || continue
                entry = read(joinpath(_PACKAGE_ROOT, "package", name, "src", "$name.jl"), String)
                (occursin(r"(?m)^\s*@compile_ahead\b", entry) &&
                 occursin(r"(?m)^\s*run_natural_rows_workload\(\w+\)$", entry)) ||
                    push!(missing_workload, name)
            end
            isempty(missing_workload) ||
                println(stderr, "\nno `run_natural_rows_workload(…)` in the `@compile_ahead` of the entry file of:\n  ",
                        join(missing_workload, "\n  "))
            @test isempty(missing_workload)
        end

        @testset "a package with a file of a workload runs its gestures in its entry file" begin
            missing_workload = String[]
            for name in sort(collect(keys(packages)))
                (name in _LEAVES || name in _FIRST_WINDOW_PACKAGES) && continue
                _has_workload_file(name) || continue
                entry = read(joinpath(_PACKAGE_ROOT, "package", name, "src", "$name.jl"), String)
                (occursin(r"(?m)^\s*@compile_ahead\b", entry) &&
                 occursin(r"(?m)^\s*run_file_workload\(\w+\.\w+\)$", entry)) ||
                    push!(missing_workload, name)
            end
            isempty(missing_workload) ||
                println(stderr, "\nno `run_file_workload(…)` in the `@compile_ahead` of the entry file of:\n  ",
                        join(missing_workload, "\n  "))
            @test isempty(missing_workload)
        end
    end
end
