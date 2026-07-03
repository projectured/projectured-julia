"""
    TextToStringModule

TextText → String projection. Flattens a sequence of styled text spans into
a plain Julia String by concatenating each span's content. TextString spans
contribute their content verbatim; TextNewline spans contribute a newline
character; all other span types are ignored.
"""
module TextToStringModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..ReactiveModule: Cell
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, EmptyReferencePath, append_reference
import ..PrinterContextModule: child_context
export TextTextToString, TextStringToString, TextNewlineToString, TextToString

# ── TextStringToString ───────────────────────────────────────────────────────

struct TextStringToString <: Projection end

function map_reference_forward(::TextStringToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextStringToString, iomap, reference)
    return nothing
end

function projection_print(p::TextStringToString, recursion, ts::TextString, ctx)
    SimpleIoMap(p, ts, Cell(() -> ts.content::AbstractString))
end

function projection_read(::TextStringToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── TextNewlineToString ───────────────────────────────────────────────────────

struct TextNewlineToString <: Projection end

function map_reference_forward(::TextNewlineToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextNewlineToString, iomap, reference)
    return nothing
end

function projection_print(p::TextNewlineToString, recursion, tn::TextNewline, ctx)
    SimpleIoMap(p, tn, Cell("\n"))
end

function projection_read(::TextNewlineToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── TextTextToString ───────────────────────────────────────────────────────

struct TextTextToString <: Projection end

function map_reference_forward(::TextTextToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextTextToString, iomap, reference)
    return nothing
end

# Projection print: builds one child IoMap per element via recursion, then
# combines their output cells into a single reactive Cell{String}.
function projection_print(proj::TextTextToString, recursion, text::TextText, ctx)
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, elem,
                                   child_context(ctx, FieldReference("elements"), ElementReference(i)))
                               for (i, elem) in enumerate(text.elements)])
    output = Cell(() -> begin
        buf = IOBuffer()
        for iomap in child_iomaps[]
            s = iomap.output[]
            s isa AbstractString && print(buf, s)
        end
        String(take!(buf))
    end)
    SimpleIoMap(proj, text, output)
end

function projection_read(::TextTextToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── Compound convenience constructor ────────────────────────────────────────

function TextToString()
    TypeDispatchingProjection(
        TextString  => TextStringToString(),
        TextNewline => TextNewlineToString(),
        TextText    => TextTextToString(),
    )
end

end # module
