# Quantify the cost of promoting StyleColor from a plain value struct to @document.
# Compares construction + field-read + a color_interpolate-style op, and the size of
# an ImmutableCell{StyleColor} field (concrete-inlined vs boxed-abstract).
#
# Run: julia --project=. colorbench.jl
using Projectured
using Projectured: ReactiveCell, ImmutableCell, MutableCell, Cell

# ── the CURRENT form: a plain immutable value struct (like today's StyleColor) ──
struct PlainColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

# ── the PROPOSED form: @document with ImmutableCell defaults ──
@document ImmutableCell struct DocColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

lerp(x, y, t) = x + (y - x) * t
interp_plain(a::PlainColor, b::PlainColor, t) =
    PlainColor(lerp(a.red,b.red,t), lerp(a.green,b.green,t), lerp(a.blue,b.blue,t), lerp(a.alpha,b.alpha,t))
interp_doc(a, b, t) =
    DocColor(lerp(a.red,b.red,t), lerp(a.green,b.green,t), lerp(a.blue,b.blue,t), lerp(a.alpha,b.alpha,t))

const SINK = Ref(0.0)
function bestns(f, reps; trials=7)
    f(); best = Inf
    for _ in 1:trials
        t = @elapsed for _ in 1:reps; f(); end
        best = min(best, t)
    end
    best / reps * 1e9
end

function main()
    p1 = PlainColor(0.1,0.2,0.3,1.0); p2 = PlainColor(0.9,0.8,0.7,1.0)
    d1 = DocColor(0.1,0.2,0.3,1.0);   d2 = DocColor(0.9,0.8,0.7,1.0)

    println("="^64)
    println("StyleColor: plain value struct  vs  @document ImmutableCell")
    println("="^64)
    # construction
    cp = bestns(() -> (SINK[] += PlainColor(0.5,0.5,0.5,1.0).red), 200_000)
    cd = bestns(() -> (SINK[] += DocColor(0.5,0.5,0.5,1.0).red),   200_000)
    println("construct+read .red   plain=$(round(cp;digits=2)) ns   doc=$(round(cd;digits=2)) ns   x$(round(cd/cp;digits=1))")
    # interpolate (read 8 fields, compute, construct new)
    ip = bestns(() -> (SINK[] += interp_plain(p1,p2,0.5).red), 100_000)
    id = bestns(() -> (SINK[] += interp_doc(d1,d2,0.5).red),   100_000)
    println("color_interpolate     plain=$(round(ip;digits=2)) ns   doc=$(round(id;digits=2)) ns   x$(round(id/ip;digits=1))")
    # field read only
    rp = bestns(() -> (SINK[] += p1.red), 1_000_000)
    rd = bestns(() -> (SINK[] += d1.red), 1_000_000)
    println("read .red only        plain=$(round(rp;digits=2)) ns   doc=$(round(rd;digits=2)) ns   x$(round(rd/rp;digits=1))")

    # allocation of one construction
    ap = @allocated PlainColor(0.5,0.5,0.5,1.0)
    ad = @allocated DocColor(0.5,0.5,0.5,1.0)
    println("bytes / construction  plain=$ap   doc=$ad")

    # the config-cell concern: ImmutableCell{StyleColor} inlined vs boxed
    println("\nImmutableCell{value-type} field size (the Phase 2/3 config cell):")
    println("  ImmutableCell{PlainColor} isbits? ", isbitstype(ImmutableCell{PlainColor}),
            "   sizeof=", sizeof(ImmutableCell{PlainColor}))
    # DocColor is a UnionAll; ImmutableCell{DocColor} holds a boxed doc
    println("  ImmutableCell{DocColor}  concrete? ", isconcretetype(ImmutableCell{DocColor}),
            "   (DocColor is a UnionAll: ", DocColor isa UnionAll, ")")
    println("="^64)
end
main()
