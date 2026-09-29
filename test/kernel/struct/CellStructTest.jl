"""
`@cell_struct`, called directly: the constructor that wraps each value in a cell,
the property methods, the keyword constructor, the kinds and the type parameters.
The tests need only the cell layer and the struct layer.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule

# Bare and typed fields: each field is a cell.
@cell_struct struct CsPlain
    a
    b::Int
end

# Fields with a default: a keyword constructor with optional and required keywords.
@cell_struct struct CsDefaults
    x
    y::Float64 = 1.5
end

# A written supertype stays.
abstract type CsBase end
@cell_struct struct CsSub <: CsBase
    v
end

# A leading kind, and a field that names its own kind.
@cell_struct ImmutableCell struct CsImmutable
    a::Int
    b::MutableCell{Int}
    c
end

# Type parameters: one that binds from an argument, one with a bound and a default,
# one that binds from no argument, and one in an immutable field.
@cell_struct struct CsBox{A}
    content::A
end
@cell_struct struct CsBounded{A<:Real}
    content::A
    count::Int = 1
end
@cell_struct struct CsList{A}
    items::Vector{A}
end
@cell_struct ImmutableCell struct CsTyped{A}
    content::A
end

# A `mutable struct`, and a field that names the mutable kind with no value type.
@cell_struct mutable struct CsMutable
    a
    m::MutableCell
end

function test_cell_struct()
@testset "CellStruct" begin

@testset "auto-wrapping constructor" begin
    p = CsPlain(1, 2)
    @test getfield(p, :a) isa Cell
    @test getfield(p, :b) isa Cell
    @test p.a == 1
    @test p.b == 2

    # A `Cell` argument is the cell of the field, so two structs can share it.
    c = Cell(7)
    q = CsPlain(c, 2)
    @test getfield(q, :a) === c
    @test q.a == 7

    # A cell of another type does not fit a reactive field, so the field never
    # holds a cell as its value.
    @test_throws MethodError CsPlain(ImmutableCell{Int}(1), 2)
    @test_throws MethodError CsPlain(ReactiveCell{Int}(1), 2)
end

@testset "transparent read/write through the cells" begin
    p = CsPlain(1, 2)
    p.a = 10
    @test p.a == 10
    @test getfield(p, :a)[] == 10

    # A computation that reads the field depends on its cell.
    d = Cell(@computation p.a + 1)
    @test d[] == 11
    p.a = 20
    @test d[] == 21
end

@testset "keyword constructor from declared defaults" begin
    k = CsDefaults(x = 3)
    @test k.x == 3
    @test k.y == 1.5
    k2 = CsDefaults(x = 1, y = 2.0)
    @test k2.y == 2.0
    # a field without a default is a required keyword
    @test_throws UndefKeywordError CsDefaults(y = 2.0)
    # the positional constructor stays
    k3 = CsDefaults(5, 6.0)
    @test k3.x == 5
    @test k3.y == 6.0
end

@testset "explicit supertype is preserved" begin
    s = CsSub(1)
    @test s isa CsBase
    @test s.v == 1
end

@testset "a leading kind and a field that names its kind" begin
    x = CsImmutable(1, 2, 3)
    @test getfield(x, :a) isa ImmutableCell{Int}
    @test getfield(x, :b) isa MutableCell{Int}
    @test getfield(x, :c) isa ImmutableCell{Any}
    x.b = 5
    @test x.b == 5

    # A cell of the type of the field is the cell of the field.
    shared = MutableCell{Int}(9)
    @test getfield(CsImmutable(1, shared, 3), :b) === shared
    # A cell of another type does not fit the field.
    @test_throws MethodError CsImmutable(1, ImmutableCell{Int}(2), 3)
end

@testset "a mutable field rejects a written Computation" begin
    x = CsMutable(1, 0)
    @test getfield(x, :m) isa MutableCell{Any}
    @test_throws ArgumentError x.m = @computation 1
    @test x.m === 0
end

@testset "the kind of a struct of cells" begin
    @test get_cell_struct_kind(CsPlain(1, 2)) === ReactiveCell
    # Only the first field counts, and the second field of `CsImmutable` is mutable.
    @test get_cell_struct_kind(CsImmutable(1, 2, 3)) === ImmutableCell
    @test get_cell_struct_kind((1, 2)) === nothing      # the first field is not a cell
    @test get_cell_struct_kind(nothing) === nothing     # no field
end

@testset "type parameters" begin
    box = CsBox(1)
    @test box isa CsBox{Int}
    @test box.content == 1
    @test CsBox{Real}(1) isa CsBox{Real}
    # A cell gives the type of its value, and a `Cell` holds any value.
    @test CsBox(Cell(1)) isa CsBox{Any}

    @test CsBounded(2.0, 3) isa CsBounded{Float64}
    @test CsBounded(content = 2).count == 1
    @test_throws TypeError CsBounded("text", 1)

    @test CsList{Int}([1, 2]).items == [1, 2]
    @test_throws MethodError CsList([1, 2])

    typed = CsTyped(1)
    @test typed isa CsTyped{Int}
    @test getfield(typed, :content) isa ImmutableCell{Int}
end

@testset "the macro needs no name in scope" begin
    scope = Module(:CsScope)
    Core.eval(scope, :(import ProjecturedKernel.CellStructModule: @cell_struct))
    Core.eval(scope, :(@cell_struct struct S; a; b::Int = 2; end))
    @test Core.eval(scope, :(S(a = 1).b)) == 2
end

@testset "the argument parse" begin
    definition = :(struct T; a; end)
    @test parse_cell_struct_macro_arguments((definition,)) == (ReactiveCell, definition)
    @test parse_cell_struct_macro_arguments((:ImmutableCell, definition))[1] ===
          ImmutableCell
    @test parse_cell_struct_macro_arguments((:MutableCell, definition))[1] === MutableCell
    @test parse_cell_struct_macro_arguments((:Cell, definition))[1] === ReactiveCell
    @test_throws ArgumentError parse_cell_struct_macro_arguments((:Int, definition))
    @test_throws ArgumentError parse_cell_struct_macro_arguments(
        (:ImmutableCell, :x, definition))
end

@testset "the type of a field and the type that an argument gives" begin
    @test build_cell_struct_field_type(ReactiveCell, :Int) === Cell
    @test build_cell_struct_field_type(ImmutableCell, :Int) ==
          Expr(:curly, ImmutableCell, :Int)
    @test get_cell_struct_argument_type(1) === Int
    @test get_cell_struct_argument_type(ImmutableCell{Int}(1)) === Int
    @test get_cell_struct_argument_type(Cell(1)) === Any
end

end
end
