# Cost of representing a colour four ways, to validate the selection-parameter design:
#   1. plain value struct (today's StyleColor)
#   2. @document, bare/default  (selection ImmutableCell{Reference}) — boxed
#   3. @document, NON-selectable (selection ImmutableCell{Nothing})  — isbits, inlines
#   4. @document, reactive selectable (Cell selection)               — editable + holds a path
#
# The declarations are module-level on purpose: @document defines a struct, so it
# cannot live inside the benchmark function.

struct PlainColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

@document ImmutableCell struct DocColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
end

const IC = ImmutableCell

_row(io, name, T; isbits = isbitstype(T)) =
    println(io, rpad(name, 34), "value: isbits=", rpad(isbits, 6),
            isbits ? "sizeof=$(sizeof(T))  " : "(heap)      ",
            "  config cell ImmutableCell{it}: isbits=", isbitstype(IC{T}))

"""
    colorbench(; io = stdout) -> NamedTuple

Print what a colour costs in each of four representations — plain struct, bare
`@document`, non-selectable `@document`, and reactive selectable `@document` —
alongside whether its `ImmutableCell{…}` config cell inlines. Returns the four
types so a caller can measure them further.

The point being measured: the non-selectable `@document` colour is isbits and the
same size as the plain struct, while the *same type* also has a reactive,
selectable, editable form. One `@document`; the selection type parameter decides.
"""
function colorbench(; io::IO = stdout)
    println(io, "="^92)
    println(io, "Representing a colour — the render value and its ImmutableCell{…} config cell")
    println(io, "="^92)

    # 1. plain value struct (status quo)
    _row(io, "plain struct", PlainColor)

    # 2. @document default (bare) — selection is ImmutableCell{Reference}, not isbits
    bare = DocColor(0.1, 0.2, 0.3, 1.0)
    _row(io, "@document default (IStyleColor)", typeof(bare))

    # 3. @document NON-selectable — selection typed Nothing (built via explicit cells)
    nonsel = DocColor(IC(0.1), IC(0.2), IC(0.3), IC(1.0), IC(nothing))
    _row(io, "@document non-selectable", typeof(nonsel))
    println(io, "      reads: nonsel.red=", nonsel.red, "  nonsel.selection=", repr(nonsel.selection))

    # 4. @document reactive selectable — editable in place AND holds a selection path
    rsel = DocColor(Cell(0.1), Cell(0.2), Cell(0.3), Cell(1.0), Cell(nothing))
    rsel.red = 0.9
    rsel.selection = :a_path
    _row(io, "@document reactive selectable", typeof(rsel))
    println(io, "      edited: rsel.red=", rsel.red, "  selectable: rsel.selection=", repr(rsel.selection))

    println(io, "="^92)
    println(io, "Takeaway: the NON-selectable @document colour is isbits/32B and its config cell inlines")
    println(io, "— identical to the plain struct — while the SAME type also has a reactive, selectable,")
    println(io, "editable form. One @document, the selection type parameter decides.")
    println(io, "="^92)

    return (; plain = PlainColor, bare = typeof(bare),
              nonselectable = typeof(nonsel), reactive = typeof(rsel))
end
