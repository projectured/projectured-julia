# Cost of representing a colour four ways, to validate the selection-parameter design:
#   1. plain value struct (today's StyleColor)
#   2. @document, bare/default  (selection ImmutableCell{Reference}) — boxed
#   3. @document, NON-selectable (selection ImmutableCell{Nothing})  — isbits, inlines
#   4. @document, reactive selectable (Cell selection)               — editable + holds a path
#
# Run: julia --project=. bench/colorbench.jl
using Projectured
using Projectured: ImmutableCell, ReactiveCell, Cell

struct PlainColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

@document ImmutableCell struct DocColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

IC = ImmutableCell
row(name, T; isbits = isbitstype(T)) =
    println(rpad(name, 34), "value: isbits=", rpad(isbits, 6),
            isbits ? "sizeof=$(sizeof(T))  " : "(heap)      ",
            "  config cell ImmutableCell{it}: isbits=", isbitstype(IC{T}))

function main()
    println("="^92)
    println("Representing a colour — the render value and its ImmutableCell{…} config cell")
    println("="^92)

    # 1. plain value struct (status quo)
    row("plain struct", PlainColor)

    # 2. @document default (bare) — selection is ImmutableCell{Reference}, not isbits
    bare = DocColor(0.1, 0.2, 0.3, 1.0)
    row("@document default (IStyleColor)", typeof(bare))

    # 3. @document NON-selectable — selection typed Nothing (built via explicit cells)
    nonsel = DocColor(IC(0.1), IC(0.2), IC(0.3), IC(1.0), IC(nothing))
    row("@document non-selectable", typeof(nonsel))
    println("      reads: nonsel.red=", nonsel.red, "  nonsel.selection=", repr(nonsel.selection))

    # 4. @document reactive selectable — editable in place AND holds a selection path
    rsel = DocColor(Cell(0.1), Cell(0.2), Cell(0.3), Cell(1.0), Cell(nothing))
    rsel.red = 0.9
    rsel.selection = :a_path
    row("@document reactive selectable", typeof(rsel))
    println("      edited: rsel.red=", rsel.red, "  selectable: rsel.selection=", repr(rsel.selection))

    println("="^92)
    println("Takeaway: the NON-selectable @document colour is isbits/32B and its config cell inlines")
    println("— identical to the plain struct — while the SAME type also has a reactive, selectable,")
    println("editable form. One @document, the selection type parameter decides.")
    println("="^92)
end
main()
