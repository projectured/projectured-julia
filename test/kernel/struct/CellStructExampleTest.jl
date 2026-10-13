"""
The walkthrough of the struct layer: the REPL session that `print_cell_struct_example`
prints, line for line.
"""

using Test
using ProjecturedKernelExample: print_cell_struct_example

const _CELL_STRUCT_EXAMPLE_TEXT = """
# Type each line in a REPL after `using ProjecturedKernel.CellStructModule`.

# The cells come from the cell layer.
julia> using ProjecturedKernel.CellModule

# @cell_struct makes each field a cell. A read and a write look like those of a plain field.
julia> @cell_struct struct Point; x::Int; y::Int = 0; end

julia> point = Point(5, 1); point.x
5

julia> point.x = 6; point.x
6

# getfield answers the cell of a field.
julia> getfield(point, :x)
Cell(value, 6)

# A computation that reads a field follows its writes. A write of the same value changes nothing.
julia> total = Cell(@computation point.x + point.y); total[]
7

julia> point.y = 1; is_cell_valid(total)
true

julia> point.y = 4; total[]
10

# A cell given to the constructor is the cell of the field, so two structs share it.
julia> shared = Cell(10); near = Point(shared, 0); far = Point(shared, 1); shared[] = 20; (near.x, far.x)
(20, 20)

# A field holds a value, so a cell in a write throws.
julia> try near.x = Cell(1) catch exception; typeof(exception) end
ArgumentError

# A field with a default gives a keyword constructor, in which that field is optional.
julia> Point(x = 7).y
0

julia> try Point(y = 2) catch exception; typeof(exception) end
UndefKeywordError

# A kind before `struct` is the kind of each field whose type names no kind.
julia> @cell_struct ImmutableCell struct Label; text::String; tag::MutableCell{Symbol}; end

julia> label = Label("title", :plain); label.tag = :bold; label.tag
:bold

julia> try label.text = "other" catch exception; typeof(exception) end
MethodError

julia> get_cell_struct_kind(label)
ImmutableCell

# A type parameter binds from the argument whose value type it is. A typed cell gives the type of its value.
julia> @cell_struct ImmutableCell struct Box{A}; content::A; end

julia> typeof(Box(1)), typeof(Box{Real}(1)), typeof(Box(ImmutableCell{Int}(1)))
(Box{$(Int)}, Box{Real}, Box{$(Int)})

# A computation, and a Cell, which holds any value, give the parameter its declared bound.
julia> @cell_struct struct Amount{A<:Real}; value::A; end

julia> typeof(Amount(@computation 2.5)), typeof(Amount(Cell(3)))
(Amount{Real}, Amount{Real})

# A plan of a definition answers questions about its fields, for a macro of your own.
julia> plan = make_cell_struct_plan(:(struct Segment; left::Int; right::ImmutableCell{String} = ""; end)); plan.field_names
2-element Vector{Symbol}:
 :left
 :right

julia> get_cell_struct_field_kinds(plan), get_cell_struct_value_types(plan), get_cell_struct_required_count(plan)
(Any[ReactiveCell, ImmutableCell], Any[:Int, :String], 1)

julia> parameters = build_cell_struct_keyword_parameters(plan.field_names, plan.defaults); Base.remove_linenums!(build_cell_struct_keyword_constructor(:Segment, plan.field_names; parameters))
:(function Segment(; left, right = "")
      Segment(left, right)
  end)

# A macro of your own changes the plan, and the builders make the struct, here with one more field.
julia> macro labeled(definition); plan = make_cell_struct_plan(definition); add_cell_struct_field!(plan, :label; type = :String, default = "none"); esc(build_cell_struct_exprs(plan; source = __source__)); end
@labeled (macro with 1 method)

julia> @labeled struct Tagged; value::Int; end

julia> Tagged(value = 3).label
"none"

"""

function test_cell_struct_example()
@testset "Cell struct example" begin
    @test sprint(print_cell_struct_example) == _CELL_STRUCT_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call defines its structs again.
    @test sprint(print_cell_struct_example) == _CELL_STRUCT_EXAMPLE_TEXT
end
end
