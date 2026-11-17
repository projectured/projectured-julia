# Fragment of `TextModule`.
#
# TextBlock → String projection. Flattens the lines of styled text spans into a
# plain Julia String. TextString spans contribute their content verbatim, a
# TextSpacing a space and an inline image (TextGraphics) U+FFFC; a TextLine
# contributes its indentation and its own spans, and the enclosing block emits the
# break it implies (a separator: `n` lines, `n-1` breaks). So the string
# of a text is its flat string (`get_flat_string`): an offset into the one is an
# offset into the other.
# ── TextStringToString ───────────────────────────────────────────────────────

struct TextStringToString <: Projection end

function map_reference_forward(::TextStringToString, iomap, reference)
    return nothing
end

function map_reference_backward(::TextStringToString, iomap, reference)
    return nothing
end

function print_document(p::TextStringToString, recursion, ts::TextString, ctx)
    SimpleIoMap(p, ts, Cell(@computation ts.content::AbstractString))
end

read_gesture(::TextStringToString, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::TextStringToString, iomap::SimpleIoMap, operation) = nothing

# ── TextSpacingToString ───────────────────────────────────────────────────────

struct TextSpacingToString <: Projection end

map_reference_forward(::TextSpacingToString, iomap, reference) = nothing
map_reference_backward(::TextSpacingToString, iomap, reference) = nothing

print_document(p::TextSpacingToString, recursion, spacing::TextSpacing, ctx) =
    SimpleIoMap(p, spacing, Cell(" "))

read_gesture(::TextSpacingToString, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::TextSpacingToString, iomap::SimpleIoMap, operation) = nothing

# ── TextGraphicsToString ──────────────────────────────────────────────────────

struct TextGraphicsToString <: Projection end

map_reference_forward(::TextGraphicsToString, iomap, reference) = nothing
map_reference_backward(::TextGraphicsToString, iomap, reference) = nothing

print_document(p::TextGraphicsToString, recursion, image::TextGraphics, ctx) =
    SimpleIoMap(p, image, Cell(string(OBJECT_REPLACEMENT_CHARACTER)))

read_gesture(::TextGraphicsToString, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::TextGraphicsToString, iomap::SimpleIoMap, operation) = nothing

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
    child_iomaps = Cell(@computation([print_child(recursion, elem,
                                  make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(line.elements)]))
    output = Cell(@computation begin
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

read_gesture(::TextLineToString, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::TextLineToString, iomap::SimpleIoMap, operation) = nothing

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
    child_iomaps = Cell(@computation([print_child(recursion, elem,
                                  make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(text.elements)]))
    output = Cell(@computation begin
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

read_gesture(::TextBlockToString, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::TextBlockToString, iomap::SimpleIoMap, operation) = nothing

# ── Compound convenience constructor ────────────────────────────────────────

function TextToString()
    TypeDispatchingProjection(
        TextString   => TextStringToString(),
        TextSpacing  => TextSpacingToString(),
        TextGraphics => TextGraphicsToString(),
        TextLine     => TextLineToString(),
        TextBlock    => TextBlockToString(),
    )
end
