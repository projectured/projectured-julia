# juliac trim probe -- a closed union against an open abstract type.
#
# The probe builds the same program N times, once for each way to give the
# argument its type. Every version has the same number of concrete types and the
# same number of `area` methods. Only the declared type of the container and of
# the argument changes.
#
# Two parts:
#   inspect  -- read the optimized intermediate representation of the whole call
#               graph that starts at `main`, and count the dynamic calls. A
#               dynamic call is what `juliac --trim` refuses to compile. Fast.
#   build    -- run juliac with `--trim=safe` and run the executable. Slow.
#
# Usage:
#   julia probe.jl inspect
#   julia probe.jl build <kind> <n>

const JULIAC = joinpath(Sys.BINDIR, "..", "share", "julia", "juliac", "juliac.jl")

const KINDS = [:union, :abstract, :seal_max_methods, :seal_storage, :seal_narrow, :seal_macro]

const SEALED_MACRO = raw"""
    # Declare an abstract type and every one of its subtypes at one place. The
    # macro emits the union alias `<Name>Sealed` and a `narrow` method that maps
    # the abstract type onto that union. The list can not drift, because the
    # macro reads it from the block that declares the structs.
    macro sealed(abstract_declaration, body)
        Meta.isexpr(abstract_declaration, :abstract) ||
            error("@sealed: the first argument must be `abstract type T end`")
        abstract_name = abstract_declaration.args[1]
        isa(abstract_name, Symbol) ||
            error("@sealed: the abstract type must have no type parameter")
        Meta.isexpr(body, :block) ||
            error("@sealed: the second argument must be a `begin ... end` block")
        concrete_names = Symbol[]
        for statement in body.args
            Meta.isexpr(statement, :struct) || continue
            signature = statement.args[2]
            Meta.isexpr(signature, :<:) ||
                error("@sealed: every struct must declare a supertype")
            name = signature.args[1]
            isa(name, Symbol) ||
                error("@sealed: a sealed struct must have no type parameter")
            push!(concrete_names, name)
        end
        isempty(concrete_names) && error("@sealed: the block declares no struct")
        union_name = Symbol(abstract_name, :Sealed)
        checks = [:(value isa $(esc(name)) && return value) for name in concrete_names]
        return quote
            $(esc(abstract_declaration))
            $(esc(body))
            const $(esc(union_name)) = Union{$(map(esc, concrete_names)...)}
            function $(esc(:narrow)) end
            @inline function $(esc(:narrow))(value::$(esc(abstract_name)))
                $(checks...)
                throw(ErrorException("the seal does not list this subtype"))
            end
        end
    end
"""

module_name(kind, n) = "Probe_$(kind)_$(n)"

"Return the text of a self contained juliac input for `kind` with `n` concrete types.
`entrypoint` adds the top level `main` that juliac needs. The inspection part
loads many variants into `Main`, so it must not define `main` many times."
function generate_source(kind::Symbol, n::Int; entrypoint::Bool = false)
    names = ["Shape$(i)" for i in 1:n]
    io = IOBuffer()
    println(io, "# kind = ", kind, ", concrete types = ", n)
    println(io, "module ", module_name(kind, n))
    println(io)

    if kind === :seal_macro
        println(io, SEALED_MACRO)
        println(io, "    @sealed abstract type Shape end begin")
        for name in names
            println(io, "        struct ", name, " <: Shape")
            println(io, "            x::Float64")
            println(io, "        end")
        end
        println(io, "    end")
    else
        if kind !== :union
            println(io, "    abstract type Shape end")
            println(io)
        end
        for name in names
            supertype = kind === :union ? "" : " <: Shape"
            println(io, "    struct ", name, supertype)
            println(io, "        x::Float64")
            println(io, "    end")
            println(io)
        end
        if kind === :union
            println(io, "    const Shape = Union{", join(names, ", "), "}")
        elseif kind === :seal_storage || kind === :seal_narrow
            println(io, "    const ShapeSealed = Union{", join(names, ", "), "}")
        end
    end
    println(io)

    if kind === :seal_narrow
        println(io, "    @inline function narrow(value::Shape)")
        for name in names
            println(io, "        value isa ", name, " && return value")
        end
        println(io, "        throw(ErrorException(\"the seal does not list this subtype\"))")
        println(io, "    end")
        println(io)
    end

    if kind === :seal_max_methods
        println(io, "    Base.Experimental.@max_methods ", n, " function area end")
        println(io)
    end

    for (i, name) in enumerate(names)
        println(io, "    area(shape::", name, ") = ", float(i), " * shape.x")
    end
    println(io)

    element = kind === :seal_storage ? "ShapeSealed" : "Shape"
    call = kind in (:seal_narrow, :seal_macro) ? "area(narrow(shape))" : "area(shape)"
    println(io, "    function total_area(shapes::Vector{", element, "})")
    println(io, "        total = 0.0")
    println(io, "        for shape in shapes")
    println(io, "            total += ", call)
    println(io, "        end")
    println(io, "        return total")
    println(io, "    end")
    println(io)
    println(io, "    function entry()")
    println(io, "        shapes = ", element, "[", join(["$(name)(1.0)" for name in names], ", "), "]")
    println(io, "        return unsafe_trunc(Cint, total_area(shapes))")
    println(io, "    end")
    println(io, "end")
    if entrypoint
        println(io)
        println(io, "# juliac needs a `@main` entry point in `Main`. Its return value")
        println(io, "# becomes the exit code of the executable.")
        println(io, "function (@main)(arguments::Vector{String})::Cint")
        println(io, "    return ", module_name(kind, n), ".entry()")
        println(io, "end")
    end
    return String(take!(io))
end

"The value that `main` must return: 1 + 2 + ... + n."
expected_result(n) = div(n * (n + 1), 2)

# --- part one: count the dynamic calls in the whole reachable call graph ------

is_builtin_callee(callee) = false
is_builtin_callee(callee::Core.IntrinsicFunction) = true
is_builtin_callee(callee::Core.Builtin) = true
function is_builtin_callee(callee::GlobalRef)
    isdefined(callee.mod, callee.name) || return false
    return is_builtin_callee(getglobal(callee.mod, callee.name))
end

method_instance(definition::Core.MethodInstance) = definition
method_instance(definition::Core.CodeInstance) = method_instance(definition.def)
method_instance(definition) = nothing

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

"Walk from the entry point through every `:invoke` and collect the dynamic calls."
function dynamic_calls(entry)
    seen = Set{Any}()
    pending = Any[Tuple{typeof(entry)}]
    dynamic = String[]
    while !isempty(pending)
        signature = pop!(pending)
        signature in seen && continue
        push!(seen, signature)
        results = Base.code_typed_by_type(signature; optimize = true)
        for (code_info, _) in results
            targets = Any[]
            for statement in code_info.code
                walk_calls!(targets, dynamic, statement)
            end
            append!(pending, targets)
        end
    end
    return dynamic, length(seen)
end

function inspect_all(sizes = 2:6)
    println()
    println("dynamic calls in the call graph of the entry point  (0 = --trim can succeed)")
    println()
    print(rpad("kind", 20))
    for n in sizes
        print(lpad("n=$n", 7))
    end
    println()
    println("-"^(20 + 7 * length(sizes)))
    for kind in KINDS
        print(rpad(string(kind), 20))
        for n in sizes
            source = generate_source(kind, n)
            path = joinpath(mktempdir(), "probe.jl")
            write(path, source)
            Base.include(Main, path)
            probe = Base.invokelatest(getglobal, Main, Symbol(module_name(kind, n)))
            entry = Base.invokelatest(getglobal, probe, :entry)
            result = Base.invokelatest(entry)
            @assert result == expected_result(n) "wrong result $result for $kind n=$n"
            dynamic, _ = Base.invokelatest(dynamic_calls, entry)
            print(lpad(isempty(dynamic) ? "." : string(length(dynamic)), 7))
        end
        println()
    end
    println()
    println("legend: `.` = no dynamic call, a number = that many dynamic calls")
    return nothing
end

# --- part two: run juliac with --trim=safe ------------------------------------

function build(kind::Symbol, n::Int; directory = mktempdir())
    source_path = joinpath(directory, "probe.jl")
    exe_path = joinpath(directory, "probe")
    write(source_path, generate_source(kind, n; entrypoint = true))
    command = `$(Base.julia_cmd()) --startup-file=no $JULIAC --output-exe $exe_path --experimental --trim=safe $source_path`
    output = IOBuffer()
    ok = success(pipeline(command; stdout = output, stderr = output))
    log = String(take!(output))
    println("=== ", kind, "  n=", n, "  juliac --trim=safe: ", ok ? "BUILT" : "FAILED")
    if ok
        code = run(ignorestatus(`$exe_path`)).exitcode
        expected = expected_result(n)
        println("    the executable returns ", code, " (expected ", expected, ") -> ",
                code == expected ? "correct" : "WRONG")
    else
        for line in Iterators.take(split(log, '\n'), 25)
            println("    ", line)
        end
    end
    return ok
end

# The cells that matter: three concrete types is under the `max_methods` limit,
# four is over it. Every seal is tested at four.
const MATRIX = [(:union, 4), (:abstract, 3), (:abstract, 4), (:abstract, 6),
                (:seal_max_methods, 4), (:seal_storage, 4),
                (:seal_narrow, 4), (:seal_macro, 4)]

function build_all()
    results = Tuple{Symbol,Int,Bool}[]
    for (kind, n) in MATRIX
        push!(results, (kind, n, build(kind, n)))
        flush(stdout)
    end
    println()
    println("juliac --trim=safe summary")
    for (kind, n, ok) in results
        println("  ", rpad("$kind n=$n", 26), ok ? "BUILT" : "FAILED")
    end
    return results
end

if !isempty(ARGS)
    if ARGS[1] == "inspect"
        inspect_all(length(ARGS) >= 3 ? (parse(Int, ARGS[2]):parse(Int, ARGS[3])) : 2:6)
    elseif ARGS[1] == "build"
        build(Symbol(ARGS[2]), parse(Int, ARGS[3]))
    elseif ARGS[1] == "build-all"
        build_all()
    elseif ARGS[1] == "source"
        print(generate_source(Symbol(ARGS[2]), parse(Int, ARGS[3]); entrypoint = true))
    else
        println("usage: julia probe.jl [inspect [lo hi] | build <kind> <n> | build-all | source <kind> <n>]")
    end
end
