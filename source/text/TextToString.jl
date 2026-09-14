# ──────────────────────────────────────────────────────────────────────────
# Folded in from TextToString.jl.
#
# TextBlock → String projection. Flattens a sequence of styled text spans into
# a plain Julia String by concatenating each span's content. TextString spans
# contribute their content verbatim; TextNewline spans contribute a newline
# character; a TextLine contributes its indentation and its own spans, and the
# enclosing block emits the break it implies (a separator: `n` lines, `n-1`
# breaks). All other span types are ignored.
# ── TextStringToString ───────────────────────────────────────────────────────

struct TextStringToString <: Projection end

function map_reference_forward(::TextStringToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextStringToString, iomap, reference)
    return nothing
end

function print_document(p::TextStringToString, recursion, ts::TextString, ctx)
    SimpleIoMap(p, ts, ComputedCell(() -> ts.content::AbstractString))
end

function read_intent(::TextStringToString, iomap::SimpleIoMap, op)
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

function print_document(p::TextNewlineToString, recursion, tn::TextNewline, ctx)
    SimpleIoMap(p, tn, Cell("\n"))
end

function read_intent(::TextNewlineToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── TextLineToString ──────────────────────────────────────────────────────────

struct TextLineToString <: Projection end

function map_reference_forward(::TextLineToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextLineToString, iomap, reference)
    return nothing
end

# A line contributes its indentation and its spans — but *not* its break: that is
# a separator between elements, so the enclosing block emits it (see
# `get_flat_offsets`, the same rule).
function print_document(proj::TextLineToString, recursion, line::TextLine, ctx)
    child_iomaps = ComputedCell(() -> [print_child(recursion, elem,
                                   make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(line.elements)])
    output = ComputedCell(() -> begin
        buf = IOBuffer()
        print(buf, ' '^line.indentation)
        for iomap in child_iomaps[]
            s = iomap.output
            s isa AbstractString && print(buf, s)
        end
        String(take!(buf))
    end)
    SimpleIoMap(proj, line, output)
end

function read_intent(::TextLineToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── TextBlockToString ───────────────────────────────────────────────────────

struct TextBlockToString <: Projection end

function map_reference_forward(::TextBlockToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextBlockToString, iomap, reference)
    return nothing
end

# Projection print: builds one child IoMap per element via recursion, then
# combines their output cells into a single reactive Cell{String}.
function print_document(proj::TextBlockToString, recursion, text::TextBlock, ctx)
    child_iomaps = ComputedCell(() -> [print_child(recursion, elem,
                                   make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(text.elements)])
    output = ComputedCell(() -> begin
        buf = IOBuffer()
        elements = text.elements
        for (i, iomap) in enumerate(child_iomaps[])
            # The break a TextLine implies, emitted between elements.
            (i > 1 && elements[i] isa TextLine) && print(buf, '\n')
            s = iomap.output
            s isa AbstractString && print(buf, s)
        end
        String(take!(buf))
    end)
    SimpleIoMap(proj, text, output)
end

function read_intent(::TextBlockToString, iomap::SimpleIoMap, op)
    return nothing
end

# ── Compound convenience constructor ────────────────────────────────────────

function TextToString()
    TypeDispatchingProjection(
        TextString  => TextStringToString(),
        TextNewline => TextNewlineToString(),
        TextLine    => TextLineToString(),
        TextBlock   => TextBlockToString(),
    )
end
