# Hand-written target expansion for the two-layout `@document`, to validate the
# design before touching the macro. Models:  @document struct Point; x::Int; y::Int; end
import ProjecturedKernel as PK
const AbstractCell  = PK.CellModule.AbstractCell
const Cell          = PK.CellModule.Cell            # ReactiveCell{Any}
const ImmutableCell = PK.CellModule.ImmutableCell
const Reference     = PK.ReferenceModule.Reference
const Document      = PK.DocumentModule.Document
using Test

# ── 1. Family: the bare name is an ABSTRACT type; every variant subtypes it ──
abstract type Point <: Document end

# ── 2. Cells layout (immutable parametric struct): IPoint (isbits) / RPoint (reactive) ──
struct PointC{X<:AbstractCell, Y<:AbstractCell, S<:AbstractCell} <: Point
    x::X
    y::Y
    selection::S
end
Base.getproperty(o::PointC, n::Symbol)      = getfield(o, n)[]
Base.setproperty!(o::PointC, n::Symbol, v)  = (getfield(o, n)[] = v)
const RPoint = PointC{Cell, Cell, Cell}                                    # reactive node-doc
const IPoint = PointC{ImmutableCell{Int}, ImmutableCell{Int}, ImmutableCell{Nothing}}  # isbits value-doc
RPoint(x, y) = PointC(Cell(x), Cell(y), Cell(nothing))
IPoint(x, y) = PointC(ImmutableCell(x), ImmutableCell(y), ImmutableCell(nothing))

# ── 3. Mutable layout (native mutable struct, raw fields): MPoint = plain mutable struct ──
mutable struct PointM <: Point
    x::Int
    y::Int
    selection::Union{Nothing, Reference}
end
const MPoint = PointM
MPoint(x, y) = PointM(x, y, nothing)
# NOTE: no getproperty override → `mp.x` is a direct getfield, `mp.x = v` a direct setfield!

# ── 4. Family identity (replaces the type-wrapper test across two layouts) ──
document_family(::Type{<:Point}) = Point
same_family(a, b) = document_family(typeof(a)) === document_family(typeof(b))

# ── 5. A minimal field-by-field sync (mutable/any source → reactive shadow) ──
function sync_fields!(shadow, source)
    @assert same_family(shadow, source)
    for f in (:x, :y)
        setproperty!(shadow, f, getproperty(source, f))   # reads raw from M, unwraps from C
    end
    shadow
end

# baseline: a hand-written plain mutable struct with the same fields
mutable struct Plain; x::Int; y::Int; selection::Union{Nothing, Reference}; end
Plain(x, y) = Plain(x, y, nothing)

@testset "two-layout @document target" begin
    @testset "native MPoint == plain mutable struct (alloc + access)" begin
        f_m(n)     = (s=0; for i in 1:n; p=PointM(i,i,nothing); p.x += 1; s+=p.x end; s)
        f_plain(n) = (s=0; for i in 1:n; p=Plain(i,i,nothing);  p.x += 1; s+=p.x end; s)
        f_m(3); f_plain(3); GC.gc()
        am = @allocated f_m(100_000); ap = @allocated f_plain(100_000)
        println("  MPoint alloc=$am  Plain alloc=$ap  (ratio ", round(am/ap; digits=3), ")")
        @test am == ap                      # byte-for-byte identical to a hand-written mutable struct
        @test !isbitstype(PointM)           # mutable ⇒ reference type
    end

    @testset "isbits IPoint (immutable layout, value-doc)" begin
        @test isbitstype(IPoint)                       # inlines into parents/arrays
        @test sizeof(IPoint) == 16                     # x(8) + y(8) + selection ImmutableCell{Nothing}(0)
        @test isbitstype(eltype([IPoint(1,2), IPoint(3,4)]))  # a Vector stores them inline
    end

    @testset "family dispatch — Point matches all variants" begin
        variants = Any[IPoint(1,2), RPoint(1,2), MPoint(1,2)]
        @test all(v -> v isa Point, variants)
        @test count(v -> v isa PointM, variants) == 1     # can still target one variant
        @test all(v -> v isa Document, variants)
    end

    @testset "family identity across layouts" begin
        @test same_family(RPoint(1,2), MPoint(3,4))       # reactive ↔ mutable: same document
        @test same_family(IPoint(1,2), MPoint(3,4))
    end

    @testset "sync mutable → reactive (the omnetpp bridge)" begin
        ui  = RPoint(0, 0)                                 # editor's reactive tree
        sim = MPoint(0, 0)                                 # simulator's mutable state
        sim.x = 9; sim.y = 7                               # sim mutates (direct setfield!)
        sync_fields!(ui, sim)                              # copy into reactive shadow
        @test ui.x == 9 && ui.y == 7                       # reactive cells updated
        @test getfield(ui, :x) isa Cell                    # ui stays reactive
        sim.x = 42; sync_fields!(ui, sim)
        @test ui.x == 42
    end
end
