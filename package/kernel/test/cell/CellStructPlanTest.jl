"""
`CellStructPlan` — the shared parse a transparent-cell struct macro does before it can
emit anything, and the generic constructor builder (Rule Y) written against it.

These are the pieces `@cell_struct` and `@document` both consume. Before the plan
existed neither could be exercised on its own: the only way to test "does Rule Y
fill a trailing run of defaults correctly" was to declare a struct, construct one,
and infer the answer from whether it worked. Here the plan and each builder are
called directly, on ASTs.

Exercised entirely from ProjecturedKernel's cell layer — no document vocabulary in
scope, which is itself part of the contract: none of this is document-specific.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule

# An emitted `f(a) = g(a)` carries a `LineNumberNode` inside its body, and so does
# the literal we compare it against — from a different line. Strip both.
_bare(ex) = Base.remove_linenums!(deepcopy(ex))
_bare(exs::AbstractVector) = [_bare(e) for e in exs]

function test_struct_plan()
@testset "CellStructPlan" begin

@testset "parses the three field forms" begin
    plan = cell_struct_plan(:(struct P
        a                       # bare
        b::Int                  # typed
        c::String = "x"         # typed + default
        d = 7                   # bare + default
    end))

    @test plan.name == :P
    @test plan.supertype === nothing
    @test plan.field_names == [:a, :b, :c, :d]
    @test plan.field_types == [nothing, :Int, :String, nothing]
    @test plan.defaults[:c] == "x"
    @test plan.defaults[:d] == 7
    @test !haskey(plan.defaults, :a)
    @test plan.n_declared == 4
    @test plan.n_programmer_defaults == 2

    # An untyped field's value type reads as `Any`.
    @test cell_struct_value_types(plan) == [:Any, :Int, :String, :Any]
end

@testset "records the supertype when written" begin
    @test cell_struct_plan(:(struct Q <: Sup; a; end)).supertype === :Sup
end

@testset "the default is stripped out of the body" begin
    # A `struct` cannot carry `f = v`; the plan takes the default and the body
    # keeps only the declaration.
    plan = cell_struct_plan(:(struct R; a::Int = 1; end))
    retype_cell_struct_fields!(plan, [:Cell])
    body = plan.structdef.args[3]
    fields = filter(e -> e isa Expr, body.args)
    @test fields == [:(a::Cell)]        # not `a::Cell = 1`
end

@testset "retype_cell_struct_fields! rewrites in place, keeping line info" begin
    plan = cell_struct_plan(:(struct S; a::Int; b; end))
    before = count(e -> e isa LineNumberNode, plan.structdef.args[3].args)
    retype_cell_struct_fields!(plan, [:C1, :C2])
    body = plan.structdef.args[3]
    @test filter(e -> e isa Expr, body.args) == [:(a::C1), :(b::C2)]
    # The LineNumberNodes are what give a field its source location in errors and
    # docs; rebuilding the body instead of overwriting slots would drop them.
    @test count(e -> e isa LineNumberNode, body.args) == before
end

@testset "add_cell_struct_field! appends, and does not count as a programmer default" begin
    plan = cell_struct_plan(:(struct T; a::Int; end))
    add_cell_struct_field!(plan, :selection, :(Union{Nothing, Reference}), :nothing)

    @test plan.field_names == [:a, :selection]
    @test plan.defaults[:selection] === :nothing
    # The injected field is defaulted, but it is not the *programmer's* default —
    # that distinction is what gates the keyword constructors.
    @test plan.n_programmer_defaults == 0
    @test plan.n_declared == 1
    # It lands in the body too, so retyping reaches it.
    retype_cell_struct_fields!(plan, [:C1, :C2])
    @test filter(e -> e isa Expr, plan.structdef.args[3].args) ==
          [:(a::C1), :(selection::C2)]
end

@testset "required / trailing-default split" begin
    split(ex) = (p = cell_struct_plan(ex); (cell_struct_required_count(p), cell_struct_trailing_default_count(p)))

    @test split(:(struct A1; a; b; end))                  == (2, 0)   # none default
    @test split(:(struct A2; a; b = 1; end))              == (1, 1)   # trailing run of 1
    @test split(:(struct A3; a = 1; b = 2; end))          == (0, 2)   # all default
    @test split(:(struct A4; a; b = 1; c; end))           == (3, 0)   # gap: `c` is required,
                                                                      # so the run is empty
    @test split(:(struct A5; a; b; c = 1; d = 2; end))    == (2, 2)
end

@testset "Rule Y: positional ctors filling a trailing run of defaults" begin
    plan = cell_struct_plan(:(struct Y1; a; b; c = 1; d = 2; end))
    ctors = cell_struct_positional_ctors(plan, :Y1)

    # cell_struct_required_count is 2, n is 4, so arities 2 and 3 — never the full arity (the
    # inner ctor owns that) and never zero.
    @test length(ctors) == 2
    @test _bare(ctors[1]) == _bare(:(Y1(a, b)    = Y1(a, b, 1, 2)))
    @test _bare(ctors[2]) == _bare(:(Y1(a, b, c) = Y1(a, b, c, 2)))
end

@testset "Rule Y emits nothing when every field defaults" begin
    # cell_struct_required_count == 0 would mean a zero-argument `Y2()`, which is the keyword
    # constructor's signature. Rule Y stays out of its way.
    plan = cell_struct_plan(:(struct Y2; a = 1; b = 2; end))
    @test isempty(cell_struct_positional_ctors(plan, :Y2))
end

@testset "Rule Y emits nothing when no field defaults" begin
    plan = cell_struct_plan(:(struct Y3; a; b; end))
    @test isempty(cell_struct_positional_ctors(plan, :Y3))
end

@testset "each_arity hook interleaves a companion, and inherits the gate" begin
    plan = cell_struct_plan(:(struct Y4; a; b; c = 1; end))
    ctors = cell_struct_positional_ctors(plan, :Y4; each_arity = k -> (:(companion($k)),))

    # The companion follows *its* arity's constructor, not the whole run.
    @test _bare(ctors) == _bare([:(Y4(a, b) = Y4(a, b, 1)), :(companion(2))])

    # And when Rule Y is gated off, the hook never fires — which is the point of
    # routing a companion through it rather than re-deriving `cell_struct_required_count ≥ 1`.
    allgone = cell_struct_plan(:(struct Y5; a = 1; end))
    @test isempty(cell_struct_positional_ctors(allgone, :Y5;
                                               each_arity = k -> (:(companion($k)),)))
end

end
end
