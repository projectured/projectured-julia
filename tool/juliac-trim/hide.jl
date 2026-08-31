# Can the limitation be hidden, so that domain code keeps the abstract type?
#
# One definition links the abstract type to the closed union:
#
#     sealed_union(::Type{Shape}) = Union{Shape1, ..., ShapeN}
#
# Everything else is derived from that link. Each variant below hides the
# derived step at a different place. Every variant uses six concrete types,
# which is over the `max_methods` limit of three, so the plain abstract type
# must fail.

const N = 6
const NAMES = ["Shape$(i)" for i in 1:N]

structs = join(["struct $name <: Shape\n    x::Float64\nend" for name in NAMES], "\n")
areas = join(["area(s::$name) = $(float(i)) * s.x" for (i, name) in enumerate(NAMES)], "\n")
values = join(["$name(1.0)" for name in NAMES], ", ")

const PREAMBLE = """
abstract type Shape end
$structs
$areas

# The link. This is the only place that lists the concrete types.
sealed_union(::Type{Shape}) = Union{$(join(NAMES, ", "))}
"""

const VARIANTS = Dict(
    # No hiding. The baseline that must fail.
    :plain => """
    $PREAMBLE
    function total_area(shapes::Vector{Shape})
        total = 0.0
        for shape in shapes
            total += area(shape)
        end
        return total
    end
    entry() = total_area(Shape[$values])
    """,

    # Hide it in one type assert. `narrow` reads the link, and inference folds
    # the link away because it is a constant method on a type.
    :assert => """
    $PREAMBLE
    @inline narrow(value::Shape) = value::sealed_union(Shape)
    function total_area(shapes::Vector{Shape})
        total = 0.0
        for shape in shapes
            total += area(narrow(shape))
        end
        return total
    end
    entry() = total_area(Shape[$values])
    """,

    # Hide it in the container. The domain code writes an ordinary loop and
    # never names the union.
    :container => """
    $PREAMBLE
    @inline narrow(value::Shape) = value::sealed_union(Shape)
    struct SealedVector{A} <: AbstractVector{A}
        data::Vector{A}
    end
    Base.size(v::SealedVector) = size(v.data)
    Base.IndexStyle(::Type{<:SealedVector}) = IndexLinear()
    Base.@propagate_inbounds Base.getindex(v::SealedVector, i::Int) = narrow(v.data[i])
    function total_area(shapes::SealedVector{Shape})
        total = 0.0
        for shape in shapes
            total += area(shape)
        end
        return total
    end
    entry() = total_area(SealedVector(Shape[$values]))
    """,

    # Hide it in a field accessor. The field keeps the abstract type.
    :field => """
    $PREAMBLE
    @inline narrow(value::Shape) = value::sealed_union(Shape)
    struct Cell
        shape::Shape
    end
    @inline shape(cell::Cell) = narrow(cell.shape)
    function total_area(cells::Vector{Cell})
        total = 0.0
        for cell in cells
            total += area(shape(cell))
        end
        return total
    end
    entry() = total_area(Cell[$(join(["Cell($name(1.0))" for name in NAMES], ", "))])
    """,

    # Derive `narrow` from the link at load time, with no list written twice.
    :derived => """
    $PREAMBLE
    function define_narrow(::Type{T}) where {T}
        checks = [:(value isa \$member && return value) for member in Base.uniontypes(sealed_union(T))]
        @eval @inline narrow(value::\$T) = begin
            \$(checks...)
            # The message must hold no interpolation. Trimming can not resolve
            # the string machinery that an interpolation pulls in.
            throw(ErrorException("the seal does not list this subtype"))
        end
    end
    define_narrow(Shape)
    function total_area(shapes::Vector{Shape})
        total = 0.0
        for shape in shapes
            total += area(narrow(shape))
        end
        return total
    end
    entry() = total_area(Shape[$values])
    """,
)

is_builtin_callee(c) = false
is_builtin_callee(c::Core.IntrinsicFunction) = true
is_builtin_callee(c::Core.Builtin) = true
is_builtin_callee(c::GlobalRef) =
    isdefined(c.mod, c.name) && is_builtin_callee(getglobal(c.mod, c.name))

method_instance(d::Core.MethodInstance) = d
method_instance(d::Core.CodeInstance) = method_instance(d.def)
method_instance(d) = nothing

function walk_calls!(targets, dynamic, node)
    isa(node, Expr) || return nothing
    if node.head === :invoke
        instance = method_instance(node.args[1])
        instance === nothing || push!(targets, instance.specTypes)
    elseif node.head === :call && !is_builtin_callee(node.args[1])
        push!(dynamic, string(node.args[1]))
    end
    for argument in node.args
        walk_calls!(targets, dynamic, argument)
    end
    return nothing
end

function dynamic_calls(entry)
    seen = Set{Any}()
    pending = Any[Tuple{typeof(entry)}]
    dynamic = String[]
    while !isempty(pending)
        signature = pop!(pending)
        signature in seen && continue
        push!(seen, signature)
        for (code_info, _) in Base.code_typed_by_type(signature; optimize = true)
            targets = Any[]
            for statement in code_info.code
                walk_calls!(targets, dynamic, statement)
            end
            append!(pending, targets)
        end
    end
    return dynamic
end

println()
println("hide the limitation: ", N, " concrete types, `max_methods` is 3")
println()
for name in [:plain, :assert, :container, :field, :derived]
    include_string(Main, "module Hide_$name\n" * VARIANTS[name] * "\nend")
    probe = Base.invokelatest(getglobal, Main, Symbol("Hide_$name"))
    entry = Base.invokelatest(getglobal, probe, :entry)
    result = Base.invokelatest(entry)
    dynamic = Base.invokelatest(dynamic_calls, entry)
    println(rpad(string(name), 12),
            isempty(dynamic) ? "no dynamic call" : "$(length(dynamic)) dynamic call(s)",
            "   entry() = ", result, " (expected ", div(N * (N + 1), 2), ")")
end
println()


# Build one variant for real with juliac. Usage: julia hide.jl build container
if !isempty(ARGS) && ARGS[1] == "build"
    name = Symbol(length(ARGS) >= 2 ? ARGS[2] : "container")
    directory = mktempdir()
    source_path = joinpath(directory, "hide.jl")
    exe_path = joinpath(directory, "hide")
    write(source_path, """
    module Hide_$name
    $(VARIANTS[name])
    end
    function (@main)(arguments::Vector{String})::Cint
        return unsafe_trunc(Cint, Hide_$name.entry())
    end
    """)
    juliac = joinpath(Sys.BINDIR, "..", "share", "julia", "juliac", "juliac.jl")
    command = `$(Base.julia_cmd()) --startup-file=no $juliac --output-exe $exe_path --experimental --trim=safe $source_path`
    output = IOBuffer()
    ok = success(pipeline(command; stdout = output, stderr = output))
    println("juliac --trim=safe on the ", name, " variant: ", ok ? "BUILT" : "FAILED")
    if ok
        code = run(ignorestatus(`$exe_path`)).exitcode
        println("  the executable returns ", code, " (expected ", div(N * (N + 1), 2), ")")
    else
        for line in Iterators.take(split(String(take!(output)), '\n'), 12)
            println("  ", line)
        end
    end
end
