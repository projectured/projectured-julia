# Does the closed union still work when its members are not isbits?
# An isbits union array stores a type tag next to each element, so the split can
# happen in code generation. A union of mutable structs is a pointer array, so
# the split must happen in inference, where `max_union_splitting` applies.
for n in [2, 3, 4, 5, 6, 8]
    for kind in [:union, :abstract]
        names = ["Shape$i" for i in 1:n]
        head = kind === :union ? "" : "abstract type Shape end\n"
        supertype = kind === :union ? "" : " <: Shape"
        structs = join(["mutable struct $name$supertype\n    x::Float64\nend" for name in names], "\n")
        alias = kind === :union ? "const Shape = Union{$(join(names, ", "))}\n" : ""
        areas = join(["area(s::$name) = $(float(i)) * s.x" for (i, name) in enumerate(names)], "\n")
        source = """
        module M_$(kind)_$(n)
        $head$structs
        $alias$areas
        function total_area(shapes::Vector{Shape})
            total = 0.0
            for shape in shapes
                total += area(shape)
            end
            return total
        end
        entry() = total_area(Shape[$(join(["$name(1.0)" for name in names], ", "))])
        end
        """
        include_string(Main, source)
        probe = Base.invokelatest(getglobal, Main, Symbol("M_$(kind)_$(n)"))
        element = Base.invokelatest(getglobal, probe, :Shape)
        total = Base.invokelatest(getglobal, probe, :total_area)
        code_info, _ = only(Base.invokelatest(code_typed, total, (Vector{element},)))
        dynamic = count(s -> Meta.isexpr(s, :call) && string(s.args[1]) == "$(probe).area", code_info.code)
        println(rpad(string(kind), 10), " n=", n, "  dynamic area calls: ", dynamic)
    end
end
