"""
`CellStructPlan` and the builders that read it, called on expressions: the parse of
a `struct` definition, the questions about its fields and its type parameters, and
the positional constructors. The tests need only the cell layer and the struct
layer.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule

# An emitted `f(a) = g(a)` has a `LineNumberNode` in its body, and so has the
# expression of the test, from another line. The helper removes both.
_bare(ex) = Base.remove_linenums!(deepcopy(ex))
_bare(exs::AbstractVector) = [_bare(e) for e in exs]

function test_cell_struct_plan()
@testset "CellStructPlan" begin

@testset "parses the four field forms" begin
    plan = make_cell_struct_plan(:(struct P
        a                       # bare
        b::Int                  # typed
        c::String = "x"         # typed + default
        d = 7                   # bare + default
    end))

    @test plan.name == :P
    @test plan.supertype === nothing
    @test isempty(plan.parameters)
    @test plan.field_names == [:a, :b, :c, :d]
    @test plan.field_types == [nothing, :Int, :String, nothing]
    @test plan.defaults[:c] == "x"
    @test plan.defaults[:d] == 7
    @test !haskey(plan.defaults, :a)
    @test plan.declared_field_count == 4
    @test plan.programmer_default_count == 2

    # An untyped field's value type reads as `Any`.
    @test get_cell_struct_value_types(plan) == [:Any, :Int, :String, :Any]
end

@testset "records the supertype when written" begin
    @test make_cell_struct_plan(:(struct Q <: Sup; a; end)).supertype === :Sup
end

@testset "a field docstring is not a field" begin
    plan = make_cell_struct_plan(:(struct D; "the width" width::Int; end))
    @test plan.field_names == [:width]
end

@testset "an inner constructor is an error" begin
    @test_throws ArgumentError make_cell_struct_plan(
        :(struct Q; a::Int; Q(x) = new(x); end))
    @test_throws ArgumentError make_cell_struct_plan(
        :(struct Q; a::Int; Q(x::T) where {T} = new(x); end))
    @test_throws ArgumentError make_cell_struct_plan(
        :(struct Q; a::Int; function Q(x) new(x) end; end))
    @test_throws ArgumentError make_cell_struct_plan(:(x = 1))
end

@testset "retype_cell_struct_fields! removes the default from the body" begin
    # A `struct` can not hold `f = v`. The plan holds the default, and the written
    # slot holds only the declaration.
    plan = make_cell_struct_plan(:(struct R; a::Int = 1; end))
    retype_cell_struct_fields!(plan, [:Cell])
    body = plan.definition.args[3]
    fields = filter(e -> e isa Expr, body.args)
    @test fields == [:(a::Cell)]        # not `a::Cell = 1`
end

@testset "retype_cell_struct_fields! rewrites in place, keeping line info" begin
    plan = make_cell_struct_plan(:(struct S; a::Int; b; end))
    before = count(e -> e isa LineNumberNode, plan.definition.args[3].args)
    retype_cell_struct_fields!(plan, [:C1, :C2])
    body = plan.definition.args[3]
    @test filter(e -> e isa Expr, body.args) == [:(a::C1), :(b::C2)]
    # The LineNumberNodes give a field its source line in errors and docstrings. A
    # body built again instead of written in place would lose them.
    @test count(e -> e isa LineNumberNode, body.args) == before
end

@testset "add_cell_struct_field! appends a field that is not a programmer default" begin
    plan = make_cell_struct_plan(:(struct T; a::Int; end))
    add_cell_struct_field!(plan, :selection; type = :(Union{Nothing, Reference}),
                           default = :nothing)

    @test plan.field_names == [:a, :selection]
    @test plan.defaults[:selection] === :nothing
    # The added field has a default, but the programmer did not write it.
    @test plan.programmer_default_count == 0
    @test plan.declared_field_count == 1
    # The field is in the body too, so the retype writes it.
    retype_cell_struct_fields!(plan, [:C1, :C2])
    @test filter(e -> e isa Expr, plan.definition.args[3].args) ==
          [:(a::C1), :(selection::C2)]
end

@testset "the kind of each field" begin
    plan = make_cell_struct_plan(:(struct K
        a
        b::Int
        c::ImmutableCell{Int}
        d::MutableCell
        e::Cell
    end))
    @test get_cell_struct_field_kinds(plan) ==
          [ReactiveCell, ReactiveCell, ImmutableCell, MutableCell, ReactiveCell]
    # The default applies only to a field whose type names no kind.
    @test get_cell_struct_field_kinds(plan; default = ImmutableCell) ==
          [ImmutableCell, ImmutableCell, ImmutableCell, MutableCell, ReactiveCell]
    @test get_cell_struct_value_types(plan) == [:Any, :Int, :Int, :Any, :Any]
end

@testset "the names and the slots of the type parameters" begin
    plan = make_cell_struct_plan(:(struct G{A, B<:Real, C>:Int, Int<:D<:Real}
        a::A
        b::ImmutableCell{B}
        c::Vector{C}
        d::D
    end))
    @test plan.parameters == Any[:A, :(B<:Real), :(C>:Int), :(Int<:D<:Real)]
    @test get_cell_struct_parameter_names(plan) == [:A, :B, :C, :D]
    # `C` is the value type of no field; it is only inside `Vector{C}`.
    @test find_cell_struct_parameter_slots(plan) === nothing

    bound = make_cell_struct_plan(:(struct H{A, B}; a::A; b::ImmutableCell{B}; c::B; end))
    @test find_cell_struct_parameter_slots(bound) == [1, 2]
    @test find_cell_struct_parameter_slots(make_cell_struct_plan(:(struct N; a; end))) ==
          Int[]
end

@testset "required / trailing-default split" begin
    split(ex) = (p = make_cell_struct_plan(ex);
                 (get_cell_struct_required_count(p),
                  get_cell_struct_trailing_default_count(p)))

    @test split(:(struct A1; a; b; end))               == (2, 0)   # none default
    @test split(:(struct A2; a; b = 1; end))           == (1, 1)   # trailing run of 1
    @test split(:(struct A3; a = 1; b = 2; end))       == (0, 2)   # all default
    # `c` is required, so the run of defaults at the end is empty.
    @test split(:(struct A4; a; b = 1; c; end))        == (3, 0)
    @test split(:(struct A5; a; b; c = 1; d = 2; end)) == (2, 2)
end

@testset "positional constructors that leave out a trailing run of defaults" begin
    plan = make_cell_struct_plan(:(struct Y1; a; b; c = 1; d = 2; end))
    ctors = build_cell_struct_positional_ctors(plan, :Y1)

    # Two fields are required and four exist, so the arities are 2 and 3. The inner
    # constructor has the full arity, and no arity is zero.
    @test length(ctors) == 2
    @test _bare(ctors[1]) == _bare(:(Y1(a, b)    = Y1(a, b, 1, 2)))
    @test _bare(ctors[2]) == _bare(:(Y1(a, b, c) = Y1(a, b, c, 2)))
end

@testset "no positional constructor when every field has a default" begin
    # An arity of zero has the signature of the keyword constructor.
    plan = make_cell_struct_plan(:(struct Y2; a = 1; b = 2; end))
    @test isempty(build_cell_struct_positional_ctors(plan, :Y2))
end

@testset "no positional constructor when no field has a default" begin
    plan = make_cell_struct_plan(:(struct Y3; a; b; end))
    @test isempty(build_cell_struct_positional_ctors(plan, :Y3))
end

@testset "each_arity adds expressions after the constructor of its arity" begin
    plan = make_cell_struct_plan(:(struct Y4; a; b; c = 1; end))
    ctors = build_cell_struct_positional_ctors(plan, :Y4;
                                               each_arity = k -> (:(companion($k)),))

    @test _bare(ctors) == _bare([:(Y4(a, b) = Y4(a, b, 1)), :(companion(2))])

    # Without a constructor, the function does not call `each_arity`.
    allgone = make_cell_struct_plan(:(struct Y5; a = 1; end))
    @test isempty(build_cell_struct_positional_ctors(allgone, :Y5;
                                               each_arity = k -> (:(companion($k)),)))
end

@testset "positional constructors name a parameter that binds from no argument" begin
    plan = make_cell_struct_plan(:(struct Y6{A<:Real}; a::Vector{A}; b = 1; end))
    @test _bare(build_cell_struct_positional_ctors(plan, :Y6)) ==
          _bare([:((Y6{A}(a) where A<:Real) = Y6{A}(a, 1))])

    # A parameter that binds from an argument needs no name in the constructor.
    plan = make_cell_struct_plan(:(struct Y7{A<:Real}; a::A; b = 1; end))
    @test _bare(build_cell_struct_positional_ctors(plan, :Y7)) ==
          _bare([:(Y7(a) = Y7(a, 1))])
end

end
end
