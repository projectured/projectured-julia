# The walkthrough of the struct layer.

const _CELL_STRUCT_WALKTHROUGH = [
    "# The cells come from the cell layer.",
    "using ProjecturedKernel.CellModule",
    "# @cell_struct makes each field a cell. A read and a write look like those of a plain field.",
    "@cell_struct struct Point; x::Int; y::Int = 0; end",
    "point = Point(5, 1); point.x",
    "point.x = 6; point.x",
    "# getfield answers the cell of a field.",
    "getfield(point, :x)",
    "# A computation that reads a field follows its writes. A write of the same value changes nothing.",
    "total = Cell(@computation point.x + point.y); total[]",
    "point.y = 1; is_cell_valid(total)",
    "point.y = 4; total[]",
    "# A cell given to the constructor is the cell of the field, so two structs share it.",
    "shared = Cell(10); near = Point(shared, 0); far = Point(shared, 1); shared[] = 20; (near.x, far.x)",
    "# A field holds a value, so a cell in a write throws.",
    "try near.x = Cell(1) catch exception; typeof(exception) end",
    "# A field with a default gives a keyword constructor, in which that field is optional.",
    "Point(x = 7).y",
    "try Point(y = 2) catch exception; typeof(exception) end",
    "# A kind before `struct` is the kind of each field whose type names no kind.",
    "@cell_struct ImmutableCell struct Label; text::String; tag::MutableCell{Symbol}; end",
    "label = Label(\"title\", :plain); label.tag = :bold; label.tag",
    "try label.text = \"other\" catch exception; typeof(exception) end",
    "get_cell_struct_kind(label)",
    "# A type parameter binds from the argument whose value type it is. A typed cell gives the type of its value.",
    "@cell_struct ImmutableCell struct Box{A}; content::A; end",
    "typeof(Box(1)), typeof(Box{Real}(1)), typeof(Box(ImmutableCell{Int}(1)))",
    "# A computation, and a Cell, which holds any value, give the parameter its declared bound.",
    "@cell_struct struct Amount{A<:Real}; value::A; end",
    "typeof(Amount(@computation 2.5)), typeof(Amount(Cell(3)))",
    "# A plan of a definition answers questions about its fields, for a macro of your own.",
    "plan = make_cell_struct_plan(:(struct Segment; left::Int; right::ImmutableCell{String} = \"\"; end)); plan.field_names",
    "get_cell_struct_field_kinds(plan), get_cell_struct_value_types(plan), get_cell_struct_required_count(plan)",
    "parameters = build_cell_struct_keyword_parameters(plan.field_names, plan.defaults); Base.remove_linenums!(build_cell_struct_keyword_constructor(:Segment, plan.field_names; parameters))",
    "# A macro of your own changes the plan, and the builders make the struct, here with one more field.",
    "macro labeled(definition); plan = make_cell_struct_plan(definition); add_cell_struct_field!(plan, :label; type = :String, default = \"none\"); esc(build_cell_struct_exprs(plan; source = __source__)); end",
    "@labeled struct Tagged; value::Int; end",
    "Tagged(value = 3).label",
]

"""
    print_cell_struct_example(io::IO = stdout)

Print a REPL session that shows the struct layer: a struct of cells, a read and a
write of a field, the cell of a field, a computation that follows a field, a cell
that two structs share, a write of a cell that throws, the keyword constructor,
the kind of each field, type parameters and their bounds, a plan and the builders,
and a macro of your own that adds a field.

Each line runs as it prints, so the value under a line is the value that the line
gives. Each call defines its structs and its macro in a session of its own. To try
the lines, type them in a REPL after `using ProjecturedKernel.CellStructModule`.

# Example

    julia> using ProjecturedKernelExample

    julia> print_cell_struct_example()

See also the guide `kernel/struct`.
"""
print_cell_struct_example(io::IO = stdout) =
    _print_walkthrough(io, CellStructModule, _CELL_STRUCT_WALKTHROUGH)
