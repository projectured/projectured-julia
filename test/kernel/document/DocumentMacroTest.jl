"""
`@document`'s **emitted constructor surface** — Rule Y (positional defaults) and
Rule C (single-collection element sugar).

These rules are the subtlest part of the macro. They are tested here by counting
and calling the *methods* the macro emits, which is the macro's actual public
contract.

The Rule C cases use a **test-local collection**, `DmCollection`. Rule C finds a
collection field through `is_collection_field_type(::Val{name})`, keyed on the
declared type's *symbol*, and this file registers `Val{:DmCollection}` before its
first `@document`. The real `CellVector` lives in the collection package above the
kernel, and the kernel test package does not load it.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule: Reference, EmptyReference

# The collection of the Rule C cases. The emitted `DmCollection(items)` call wraps
# a raw vector with it. `<: Document` (not `<: AbstractVector`) mirrors the real
# `CellVector`, which is what makes the raw and bracketed Rule C forms
# non-overlapping. The macro asks `is_collection_field_type` at expansion, so the
# registration comes before the first `@document` that declares the type.
struct DmCollection <: Document
    items::Vector{Any}
end
DmCollection(items::AbstractVector) = DmCollection(collect(Any, items))
Base.:(==)(a::DmCollection, b::DmCollection) = a.items == b.items
DocumentModule.is_collection_field_type(::Val{:DmCollection}) = true

# ── Rule Y ────────────────────────────────────────────────────────────────
@document struct DmRuleY
    a::Int
    b::Int
    c::String = "c"
    d::Bool   = false
end

# ── Rule C: the collection is the sole content, everything else defaults ──
@document struct DmSoleVector
    items::DmCollection = DmCollection([])
end

# ── Rule C: the collection sits beside a *required* sibling ───────────────
@document struct DmVectorWithSibling
    callee::Int
    args::DmCollection
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

# ── The bare name: one schema per binding ─────────────────────────────────
# `DC` binds it to the concrete default spelling, which is what a value document
# stored by value in a configuration cell wants.
@document ImmutableCell [DC] struct DmValue
    a::Int
    b::Int = 7
    selection::ImmutableCell{Nothing}
end

# `DC` with no default: the schema has no keyword form.
@document ImmutableCell [DC] struct DmValueRequired
    a::Int
    b::Int
end

# `M` first binds it to the mutable native struct — the object a simulator mutates.
"""
    DmNative(a)

A schema whose bare name is the mutable native struct.
"""
@document [M, C] struct DmNative
    a::Int
end

# A field that names another schema: the native layout holds the native child, and
# the cell layout holds any layout of the family of the child.
@document [M, C] struct DmNativeOwner
    child::DmNative
end

# The same with a schema that has a parameter: the bare name is a `UnionAll`.
@document [M, C] struct DmParametricNative{A}
    a::A
end

@document struct DmParametricOwner
    child::DmParametricNative
end

# A value that can not show itself, for the text of a refused write.
struct DmUnshowable end
Base.show(io::IO, ::DmUnshowable) = error("DmUnshowable can not show itself")

# `I` first binds it to the immutable native struct — a value a hot path copies
# rather than mutates. `selection::Nothing` is written out for the same reason it
# is on a value document: the injected union is over heap types, and one of them
# in the struct is what would stop it being isbits.
"""
    DmImmutableNative(a)

A schema whose bare name is the immutable native struct.
"""
@document ImmutableCell [I, C] struct DmImmutableNative
    a::Int
    selection::Nothing
end

# A schema with a parameter of the programmer's own, which IS a field's declared
# type. The kind constructors name that type, so they take the parameter at the
# call — `ICDmParametric{Int}(…)`. The bare name stays callable, because the
# schema's own inferring constructor binds the parameter from the argument.
@document struct DmParametric{A}
    value::A
end

# A schema whose parameter appears only INSIDE a field's type, the way
# `SequentialEngine{A}` holds an `EventHeap{A}`. Nothing binds it from an
# argument, so every generated constructor takes it at the call.
@document struct DmNested{A}
    box::Tuple{A}
end

# The same two shapes with a bound on the parameter. A `where` clause and a struct
# head take `A<:Real`, and a type application takes `A` alone.
@document struct DmBounded{A<:Real}
    value::A
end
@document struct DmBoundedNested{A<:Real}
    box::Tuple{A}
end

# A schema that declares its own `selection` field, as the last field.
@document ImmutableCell struct DmValueSel
    x::Float64
    selection::ImmutableCell{Nothing}
end

# A value whose `unwrap_selection` counts the calls that reach it.
struct DmUnwrapProbe end
const dm_unwrap_calls = Ref(0)
DocumentModule.unwrap_selection(value::DmUnwrapProbe) = (dm_unwrap_calls[] += 1; value)

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
    # `get_cell_struct_required_count ≥ 1` gate exists to avoid.
    @test DmRuleY(a = 1, b = 2).c == "c"
    @test_throws UndefKeywordError DmRuleY()
end

@testset "Rule C wraps a raw Vector into the collection" begin
    # Without Rule C the auto-wrapping inner ctor would store Cell(Vector) — a cell
    # wrapping a plain Vector — instead of a DmCollection.
    @test DmSoleVector([1, 2]).items == DmCollection([1, 2])

    # Beside a required sibling, the bracketed form accompanies the Rule Y arity.
    d = DmVectorWithSibling(7, [1, 2])
    @test d.callee == 7
    @test d.args == DmCollection([1, 2])
    @test d.selection === nothing
end

@testset "an already-built collection reaches the variadic, and is nested" begin
    # Passing a real collection to a sole-collection document does NOT pass it
    # through: a DmCollection is a `Document`, not an `AbstractVector`, so the call
    # lands on Rule C's variadic `T(items::Document...)` and becomes a one-element
    # collection *containing* it. This test pins it, so that a change of the tail
    # of Rule C can not alter it silently.
    @test DmSoleVector(DmCollection([1, 2])).items == DmCollection([DmCollection([1, 2])])
    # To wrap an existing collection, name the selection too and take the inner ctor.
    @test DmSoleVector(DmCollection([1, 2]), nothing).items == DmCollection([1, 2])
end

@testset "Rule C emits its bracketed form exactly ONCE" begin
    # Regression. When every field defaults (get_cell_struct_required_count == 0) the element-sugar
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
    @test RCDmRuleY === DmRuleY{Cell, Cell, Cell, Cell, Cell, Cell}

    # The typed kind ctors take the *full* arity — `selection` included — or every
    # field but the mouse target, which starts with `nothing`. They are the
    # machinery's constructors (copy_document builds through them), not sugar, so
    # they fill nothing else in: Rule Y is emitted for the bare name only.
    @test ICDmRuleY(1, 2, "z", true, nothing) isa ICDmRuleY
    @test MCDmRuleY(1, 2, "z", true, nothing) isa MCDmRuleY
    @test ICDmRuleY(1, 2, "z", true, nothing).a == 1
    # The kind aliases do get the keyword ctor, which does fill defaults in.
    @test ICDmRuleY(a = 1, b = 2).c == "c"
end

@testset "a schema with a parameter takes it in its kind ctors" begin
    # Without the parameter on the head, the body's `ImmutableCell{A}` names a
    # global no module has, and the call throws `UndefVarError: A`.
    node = ICDmParametric{Int}(3, nothing)
    @test node isa ICDmParametric{Int}
    @test node.value == 3
    @test getfield(node, :value) isa ImmutableCell{Int}
    @test MCDmParametric{Int}(3, nothing) isa MCDmParametric{Int}
    # The declared value types mention the parameter too, so that method takes
    # it from the type. Asked about the bare name, it answers `nothing`.
    types = DocumentModule._declared_value_types(DmParametric{Int})
    @test types isa Tuple && first(types) === Int
    @test DocumentModule._declared_value_types(DmParametric) === nothing
    # Rule Y fills the trailing defaults — here the injected `selection` — and
    # the bare name reaches it, because `value` binds the parameter.
    short = DmParametric(3)
    @test short.value == 3 && short.selection === nothing
end

@testset "a parameter no field's type is, is taken at every call" begin
    # Nothing binds `A` from an argument here, so the bare name is not callable
    # and each generated constructor carries the parameter: the kind ctors, and
    # Rule Y, which fills the injected `selection`.
    node = ICDmNested{Int}((3,), nothing)
    @test node isa ICDmNested{Int} && node.box === (3,)
    short = DmNested{Int}((3,))
    @test short.box === (3,) && short.selection === nothing
end

@testset "a bounded parameter works in every constructor" begin
    short = DmBounded(2.0)
    @test short isa DmBounded{Float64} && short.selection === nothing
    @test ICDmBounded{Int}(3, nothing).value == 3
    @test MDmBounded(2.0) isa MDmBounded{Float64}
    @test_throws TypeError DmBounded("text")
    nested = DmBoundedNested{Int}((3,))
    @test nested.box === (3,) && nested.selection === nothing
end

@testset "a copy keeps the parameters of a schema" begin
    # A cell of `Any` binds a parameter as `Any`, so the copy takes the parameters
    # from the type of the source, not from the values of its cells.
    @test copy_document(DmParametric(3)) isa DmParametric{Int}
    @test copy_document(ReactiveCell, DmParametric(3)) isa DmParametric{Int}
    @test copy_document(ReactiveCell, DmBounded(2.0)) isa DmBounded{Float64}
    @test copy_document(ReactiveCell, DmBounded(2.0)).value === 2.0
    # The kinded copy of a native source converts, and keeps the parameter.
    @test copy_document(ImmutableCell, MDmBounded(2.0)) isa ICDmBounded{Float64}
    @test copy_document(MDmBounded(2.0)) isa MDmBounded{Float64}
    # A parameter that no field binds is taken from the source, too.
    @test copy_document(DmNested{Int}((3,))) isa DmNested{Int}
    @test copy_document(ReactiveCell, DmNested{Int}((3,))).box === (3,)
end

@testset "a read calls unwrap_selection for the selection field only" begin
    # The read of a field of the reactive kind gets `Any`, so a call to
    # `unwrap_selection` there dispatches at run time on every read.
    node = DmParametric(DmUnwrapProbe())
    dm_unwrap_calls[] = 0
    @test node.value isa DmUnwrapProbe
    @test dm_unwrap_calls[] == 0
    getfield(node, :selection)[] = DmUnwrapProbe()
    @test node.selection isa DmUnwrapProbe
    @test dm_unwrap_calls[] == 1
end

@testset "the layout registry answers for every variant" begin
    # The point of the registry: a caller asks for a layout instead of naming one.
    # Both accessors are keyed on the family, so either variant answers the same.
    @test get_document_cell_type(DmRuleY(1, 2))       === DmRuleY
    @test get_document_cell_type(MDmRuleY(1, 2))    === DmRuleY
    @test get_document_native_type(DmRuleY(1, 2))     === MDmRuleY
    @test get_document_native_type(MDmRuleY(1, 2))  === MDmRuleY
    # The type-taking form, which is what the copy walk uses.
    @test get_document_cell_type(MDmRuleY)          === DmRuleY
    @test get_document_native_type(typeof(DmRuleY(1, 2))) === MDmRuleY

    # A hand-written document is its own cell layout and has no native one, so a
    # copy of one rebuilds exactly what it was.
    @test get_document_cell_type(DmCollection([]))   === DmCollection
    @test get_document_native_type(DmCollection([])) === nothing
end

@testset "the layout list says which layouts a schema emits" begin
    # The default list is what a declaration always emitted.
    @test get_document_native_type(DmRuleY(1, 2)) === MDmRuleY

    # `[C]` emits no native layout at all, and the default accessor says so.
    @test !isdefined(@__MODULE__, :MDmCellOnly)
    @test get_document_native_type(DmCellOnly(a = 1)) === nothing
    @test get_document_cell_type(DmCellOnly(a = 1)) === DmCellOnly
    # The cell layout is untouched by the list, so the schema still copies.
    @test copy_document(ReactiveCell, DmCellOnly(a = 1)) isa DmCellOnly

    # A code names a layout and nothing else, and a schema needs its cell layout.
    @test_throws LoadError @eval @document [X] struct DmBadCode
        a::Int = 0
    end
    @test_throws LoadError @eval @document [M] struct DmNoCellLayout
        a::Int = 0
    end
    # One schema has one native struct, so a list asking for both is refused.
    @test_throws LoadError @eval @document [C, M, I] struct DmTwoNatives
        a::Int = 0
    end
end

@testset "the immutable native layout is a plain immutable struct" begin
    # `I` emits the native struct that `M` does, and the only difference is the
    # one that matters to a value on a hot path: a `mutable struct` is never
    # isbits, however small its fields are.
    @test get_document_native_type(IDmImmutableNative) === IDmImmutableNative
    @test !ismutabletype(IDmImmutableNative)
    @test ismutabletype(MDmRuleY)
    @test isbitstype(IDmImmutableNative)

    # It is a document like any other: it carries the declared value types
    # directly, and it copies into any cell kind.
    value = DmImmutableNative(7)
    @test value.a === 7
    @test get_document_cell_type(value) === ACDmImmutableNative
    @test get_document_schema_name(value) === :DmImmutableNative
    @test copy_document(ReactiveCell, value) isa RCDmImmutableNative
    @test copy_document(ReactiveCell, value).a == 7
end

@testset "the first layout code says what the bare name is" begin
    # `C`, the default. The cell layout keeps the programmer's own name, so `show`
    # and `nameof` are unchanged, and the coded name works beside it.
    @test DmRuleY isa UnionAll
    @test ACDmRuleY === DmRuleY
    @test nameof(typeof(DmRuleY(1, 2))) === :DmRuleY

    # `DC`. The bare name is the concrete default spelling, so a field typed with
    # it inlines — which is the whole reason a value document asks for this.
    @test DmValue === DCDmValue
    @test isconcretetype(DmValue)
    @test isbitstype(DmValue)
    @test get_document_cell_type(DmValue(2)) === ACDmValue
    # A concrete parameterization has no constructor of its own, so the bare name
    # reaches the cell layout through the forwarding constructor. Rule Y, Rule C
    # and the keyword form all arrive there.
    @test DmValue(2) isa DmValue
    @test DmValue(2).b == 7
    @test DmValue(a = 3).b == 7
    # The forward takes keywords only for a schema that has a keyword form, so
    # `hasmethod` with keyword names answers what a keyword call does.
    @test hasmethod(DmValue, Tuple{}, (:a,))
    @test DmValueRequired(1, 2).b == 2
    @test !hasmethod(DmValueRequired, Tuple{}, (:a, :b))

    # `M` first. The bare name is the plain mutable struct: a field holds a value,
    # not a cell, and writing one is a `setfield!`.
    @test DmNative === MDmNative
    @test !(getfield(DmNative(4), :a) isa AbstractCell)
    @test (n = DmNative(4); n.a = 9; n.a) == 9
    @test get_document_cell_type(DmNative(4)) === ACDmNative
    # Both layouts still answer one family, and a shadow of the native one is a
    # cell document.
    @test DmNative(4) isa ADmNative
    @test ACDmNative(1, nothing) isa ADmNative
    @test copy_document(ReactiveCell, DmNative(4)) isa ACDmNative
end

@testset "a cell layout declares the family where a field names a native layout" begin
    @test fieldtype(MDmNativeOwner, :child) === MDmNative
    @test find_declared_field_type(ACDmNativeOwner, :child) === ADmNative
    # A kinded copy holds the cell layout of the child, which the check admits.
    for kind in (ReactiveCell, MutableCell, ImmutableCell)
        copied = copy_document(kind, DmNativeOwner(DmNative(4)))
        @test copied.child isa ACDmNative
        @test copied.child.a == 4
    end
    @test find_declared_field_type(DmParametricOwner, :child) === ADmParametricNative
    shadow = copy_document(ReactiveCell, DmParametricNative{Int}(5, nothing))
    @test DmParametricOwner(shadow).child === shadow
    # The text of a refused write names a value that can not show itself by its type.
    text = sprint(showerror, DeclaredTypeMismatchException(DmNativeOwner, :child, DmNative,
                                                          DmUnshowable()))
    @test endswith(text, ": a $(DmUnshowable)")
end

@testset "a docstring reaches the struct that the bare name names" begin
    # A lookup of the bare name reaches the binding of the type it names. When
    # that is the native struct, the native struct must carry the docstring, and
    # the cell layout keeps it for its coded name.
    documented = Base.Docs.meta(parentmodule(MDmNative))
    for name in (:MDmNative, :ACDmNative, :IDmImmutableNative, :ACDmImmutableNative)
        @test haskey(documented, Base.Docs.Binding(parentmodule(MDmNative), name))
    end
end

@testset "a preset is @document with a fixed layout list" begin
    @test get_document_native_type(DmViaPreset(a = 1)) === nothing
    @test get_document_cell_type(DmViaPreset(a = 1)) === DmViaPreset
    # The marker reached the expansion through the preset.
    @test getfield(DmPresetKinded(a = 1), :a) isa ImmutableCell{Int}
    @test get_document_native_type(DmPresetKinded(a = 1)) === nothing
end

@testset "an explicit `selection` field overrides the injected default" begin
    # A value-document types its selection `Nothing` (non-selectable) instead of the
    # injected `Reference`, so the bare ctor builds an isbits form.
    @test getfield(DmValueSel(1.0), :selection) isa ImmutableCell{Nothing}
    @test isbitstype(typeof(DmValueSel(1.0)))
    # An explicit `selection` field must be declared last.
    @test_throws LoadError @eval @document struct DmMisplacedSel
        selection::ImmutableCell{Nothing}
        y::Int
    end
end

@testset "a document that the editor holds has a mouse target, a native object none" begin
    d = DmRuleY(1, 2)
    @test d.mouse_target === nothing
    @test fieldnames(typeof(d))[end-1:end] == (:selection, :mouse_target)
    @test is_view_state_field(:mouse_target) && is_view_state_field(:selection)
    @test !is_view_state_field(:a) && !is_view_state_field(1)
    d.mouse_target = EmptyReference()
    @test d.mouse_target == EmptyReference()
    # The native layout and a value document, which declares its own selection,
    # have none.
    @test :mouse_target in fieldnames(ACDmNative)
    @test :mouse_target ∉ fieldnames(typeof(DmNative(1)))
    @test :mouse_target ∉ fieldnames(typeof(DmValue(1)))
    @test isbitstype(typeof(DmValue(1)))
    # A call that passes every field but the mouse target works, with a required
    # field (Rule Y) and with none.
    @test DmRuleY(1, 2, "c", false, nothing).mouse_target === nothing
    @test DmSoleVector(DmCollection([1, 2]), nothing).items == DmCollection([1, 2])
    @test ICDmRuleY(1, 2, "z", true, nothing).mouse_target === nothing
    # A copy starts with no mouse target, and `show` leaves it out.
    @test copy_document(PlainCopyPolicy(), d).mouse_target === nothing
    @test !occursin("EmptyReference", sprint(show, d))
end

end
end
