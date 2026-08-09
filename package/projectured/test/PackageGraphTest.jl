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

const _PACKAGE_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))

# domain package -> the other domain packages it may depend on.
# An edge here is one domain embedding another domain's content: a state
# machine guard is a Julia expression, a catalog query produces a SQL
# statement, the workbench opens documents of every kind.
const DOMAIN_EDGES = Dict(
    "ProjecturedJson"          => String[],
    "ProjecturedYaml"          => String[],
    "ProjecturedXml"           => String[],
    "ProjecturedMarkdown"      => String[],
    "ProjecturedRst"           => String[],
    "ProjecturedBook"          => String[],
    "ProjecturedMath"          => String[],
    "ProjecturedJulia"         => String[],
    "ProjecturedSql"           => String[],
    "ProjecturedDatabase"      => String[],
    "ProjecturedFileSystem"    => String[],
    "ProjecturedGraph"         => String[],
    "ProjecturedChart"         => String[],
    "ProjecturedSequenceChart" => String[],
    "ProjecturedDbCatalog"     => ["ProjecturedSql"],
    "ProjecturedFormula"       => ["ProjecturedJulia"],
    "ProjecturedFsm"           => ["ProjecturedGraph", "ProjecturedJulia"],
    "ProjecturedProcess"       => ["ProjecturedGraph", "ProjecturedJulia"],
    "ProjecturedConversation"  => ["ProjecturedJson", "ProjecturedJulia",
                                   "ProjecturedXml"],
    "ProjecturedWorkbench"     => ["ProjecturedConversation", "ProjecturedFileSystem",
                                   "ProjecturedJson", "ProjecturedJulia",
                                   "ProjecturedMarkdown", "ProjecturedXml",
                                   "ProjecturedYaml"],
)

const ENGINE = ["ProjecturedKernel", "ProjecturedBase", "ProjecturedVisual"]

"""
    _read_package_graph() -> Dict{String,Vector{String}}

Every `package/*/main` package, mapped to the `Projectured*` packages it
declares. Read from the `Project.toml` files, not from the loaded modules, so a
dependency that is declared but unused still shows up.
"""
function _read_package_graph()
    graph = Dict{String,Vector{String}}()
    for entry in sort(readdir(joinpath(_PACKAGE_ROOT, "package")))
        proj = joinpath(_PACKAGE_ROOT, "package", entry, "main", "Project.toml")
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

        @testset "each domain depends on all three engine packages" begin
            for name in sort(collect(keys(DOMAIN_EDGES)))
                haskey(graph, name) || continue
                for e in ENGINE
                    @test e in graph[name]
                end
            end
        end

        @testset "no engine package depends on a domain" begin
            for e in ENGINE
                haskey(graph, e) || continue
                for dep in graph[e]
                    @test !haskey(DOMAIN_EDGES, dep)
                end
            end
        end
    end
end
