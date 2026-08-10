"""
`@document`'s **emitted constructor surface** — Rule Y (positional defaults) and
Rule C (single-`CellVector` element sugar).

These rules are the subtlest part of the macro and were, until the plan/emitter
split, untestable except by declaring a struct and seeing whether a call happened
to work. They are tested here by counting and calling the *methods* the macro
emits, which is the macro's actual public contract.

The `CellVector` cases use a **test-local stand-in**: Rule C detects its collection
field by matching the declared type's *symbol*, so the real `CellVector` (which
lives in `base`, above the kernel) need not be in scope for the macro to fire — and
the kernel test package cannot see it. That the rule works on a look-alike is not a
loophole in the test; it is the wart the rule is built on, and is documented as such
on `_emit_collection_ctors`.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule: Reference

# A stand-in for base's CellVector: Rule C keys off the *name*, and the emitted
# `CellVector(items)` call has to resolve to something. `<: Document` (not
# `<: AbstractVector`) mirrors the real one, which is what makes the raw and
# bracketed Rule C forms non-overlapping.
struct CellVector <: Document
    items::Vector{Any}
end
CellVector(items::AbstractVector) = CellVector(collect(Any, items))
Base.:(==)(a::CellVector, b::CellVector) = a.items == b.items

# ── Rule Y ────────────────────────────────────────────────────────────────
@document struct DmRuleY
    a::Int
    b::Int
    c::String = "c"
    d::Bool   = false
end

# ── Rule C: the collection is the sole content, everything else defaults ──
@document struct DmSoleVector
    items::CellVector = CellVector([])
end

# ── Rule C: the collection sits beside a *required* sibling ───────────────
@document struct DmVectorWithSibling
    callee::Int
    args::CellVector
end

# ── No collection: Rule C must stay silent ────────────────────────────────
@document struct DmNoVector
    a::Int
    b::String = "b"
end

# ── The layout list: this schema emits the cell layout and no native one ──
@document [C] struct DmCellOnly
    a::Int = 0
end

# ── A preset: `@document` with a fixed layout list, named once ────────────
@document_preset dm_cell_document [C]

@dm_cell_document struct DmViaPreset
    a::Int = 0
end

# A preset passes its own arguments through, so a field-kind marker still works.
@dm_cell_document ImmutableCell struct DmPresetKinded
    a::Int = 0
end

# How many methods of `T` take exactly `n` positional arguments, of which the one
# in `slot` is an `AbstractVector`? Rule C's bracketed form for a struct whose
# collection sits at field `slot` has exactly this shape, and the duplicate-method
# bug shows up as a count of 2.
_bracketed_ctors(T, n, slot) =
    count(methods(T)) do m
        m.sig isa DataType || return false
        params = m.sig.parameters
        length(params) == n + 1 && params[slot + 1] === AbstractVector
    end

function test_document_macro()
@testset "DocumentMacro" begin

@testset "Rule Y fills a trailing run of defaults, positionally" begin
    # `selection` is injected last and always defaulted, so it joins the run: a
    # document's own fields keep the arity they would have had without it.
    @test DmRuleY(1, 2).c == "c"
    @test DmRuleY(1, 2).d == false
    @test DmRuleY(1, 2).selection === nothing
    @test DmRuleY(1, 2, "z").d == false
    @test DmRuleY(1, 2, "z", true).d == true

    # Rule Y never emits a zero-argument form. That signature belongs to the keyword
    # constructor, which this struct also has (it declared defaults of its own) —
    # so `DmRuleY()` reaches *it*, and complains about the required keywords rather
    # than about there being no method. That is the collision Rule Y's
    # `cell_struct_required_count ≥ 1` gate exists to avoid.
    @test DmRuleY(a = 1, b = 2).c == "c"
    @test_throws UndefKeywordError DmRuleY()
end

@testset "Rule C wraps a raw Vector into the collection" begin
    # Without Rule C the auto-wrapping inner ctor would store Cell(Vector) — a cell
    # wrapping a plain Vector — instead of a CellVector.
    @test DmSoleVector([1, 2]).items == CellVector([1, 2])

    # Beside a required sibling, the bracketed form accompanies the Rule Y arity.
    d = DmVectorWithSibling(7, [1, 2])
    @test d.callee == 7
    @test d.args == CellVector([1, 2])
    @test d.selection === nothing
end

@testset "an already-built collection reaches the variadic, and is nested" begin
    # Passing a real collection to a sole-collection document does NOT pass it
    # through: a CellVector is a `Document`, not an `AbstractVector`, so the call
    # lands on Rule C's variadic `T(items::Document...)` and becomes a one-element
    # collection *containing* it. Surprising, and long-standing — pinned here so a
    # future change to Rule C's tail cannot alter it silently.
    @test DmSoleVector(CellVector([1, 2])).items == CellVector([CellVector([1, 2])])
    # To wrap an existing collection, name the selection too and take the inner ctor.
    @test DmSoleVector(CellVector([1, 2]), nothing).items == CellVector([1, 2])
end

@testset "Rule C emits its bracketed form exactly ONCE" begin
    # Regression. When every field defaults (cell_struct_required_count == 0) the element-sugar
    # tail emits `T(::AbstractVector)`; when a field is required, the *companion* to
    # Rule Y's arity-k form emits that same signature. Emitting both would silently
    # redefine the method. No behavioural test would ever catch it — the duplicate
    # does exactly what the original does — so it is asserted structurally.
    @test _bracketed_ctors(DmSoleVector,        1, 1) == 1   # T(items::AbstractVector)
    @test _bracketed_ctors(DmVectorWithSibling, 2, 2) == 1   # T(callee, args::AbstractVector)
end

@testset "Rule C stays silent without a collection field" begin
    @test _bracketed_ctors(DmNoVector, 1, 1) == 0
    @test DmNoVector(1).b == "b"          # Rule Y still applies
end

@testset "the kind aliases and their typed ctors are emitted" begin
    @test RDmRuleY === DmRuleY{Cell, Cell, Cell, Cell, Cell}

    # The typed kind ctors take the *full* arity — `selection` included. They are
    # the machinery's constructors (copy_document builds through them), not sugar,
    # so they fill nothing in: Rule Y is emitted for the bare name only.
    @test IDmRuleY(1, 2, "z", true, nothing) isa IDmRuleY
    @test MDmRuleY(1, 2, "z", true, nothing) isa MDmRuleY
    @test IDmRuleY(1, 2, "z", true, nothing).a == 1
    # The kind aliases do get the keyword ctor, which does fill defaults in.
    @test IDmRuleY(a = 1, b = 2).c == "c"
end

@testset "the layout registry answers for every variant" begin
    # The point of the registry: a caller asks for a layout instead of naming one.
    # Both accessors are keyed on the family, so either variant answers the same.
    @test document_cell_type(DmRuleY(1, 2))       === DmRuleY
    @test document_cell_type(DmRuleYMut(1, 2))    === DmRuleY
    @test document_native_type(DmRuleY(1, 2))     === DmRuleYMut
    @test document_native_type(DmRuleYMut(1, 2))  === DmRuleYMut
    # The type-taking form, which is what the copy walk uses.
    @test document_cell_type(DmRuleYMut)          === DmRuleY
    @test document_native_type(typeof(DmRuleY(1, 2))) === DmRuleYMut

    # A hand-written document is its own cell layout and has no native one, so a
    # copy of one rebuilds exactly what it was.
    @test document_cell_type(CellVector([]))   === CellVector
    @test document_native_type(CellVector([])) === nothing
end

@testset "the layout list says which layouts a schema emits" begin
    # The default list is what a declaration always emitted.
    @test document_native_type(DmRuleY(1, 2)) === DmRuleYMut

    # `[C]` emits no native layout at all, and the default accessor says so.
    @test !isdefined(@__MODULE__, :DmCellOnlyMut)
    @test document_native_type(DmCellOnly(a = 1)) === nothing
    @test document_cell_type(DmCellOnly(a = 1)) === DmCellOnly
    # The cell layout is untouched by the list, so the schema still copies.
    @test copy_document(ReactiveCell, DmCellOnly(a = 1)) isa DmCellOnly

    # A code names a layout and nothing else, and a schema needs its cell layout.
    @test_throws LoadError @eval @document [X] struct DmBadCode
        a::Int = 0
    end
    @test_throws LoadError @eval @document [M] struct DmNoCellLayout
        a::Int = 0
    end
    # The immutable native layout has no caller yet, so it is refused by name
    # rather than emitted and left unused.
    @test_throws LoadError @eval @document [C, I] struct DmImmutableNative
        a::Int = 0
    end
end

@testset "a preset is @document with a fixed layout list" begin
    @test document_native_type(DmViaPreset(a = 1)) === nothing
    @test document_cell_type(DmViaPreset(a = 1)) === DmViaPreset
    # The marker reached the expansion through the preset.
    @test getfield(DmPresetKinded(a = 1), :a) isa ImmutableCell{Int}
    @test document_native_type(DmPresetKinded(a = 1)) === nothing
end

@testset "an explicit `selection` field overrides the injected default" begin
    # A value-document types its selection `Nothing` (non-selectable) instead of the
    # injected `Reference`, so the bare ctor builds an isbits form.
    @eval @document ImmutableCell struct DmValueSel
        x::Float64
        selection::ImmutableCell{Nothing}
    end
    @test @eval(getfield(DmValueSel(1.0), :selection)) isa ImmutableCell{Nothing}
    @test @eval(isbitstype(typeof(DmValueSel(1.0))))
    # An explicit `selection` field must be declared last.
    @test_throws LoadError @eval @document struct DmMisplacedSel
        selection::ImmutableCell{Nothing}
        y::Int
    end
end

end
end
