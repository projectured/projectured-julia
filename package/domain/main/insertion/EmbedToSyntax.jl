"""
    EmbedToSyntaxModule

The two rules that make a **cross-file embed** part of the shared
to-syntax fabric, so a document spliced into another one by a marker
renders as itself rather than as the marker's text:

- `ReferenceStubToSyntax` — a resolved [`ReferenceStub`](@ref) prints
  the value its marker evaluated to, through `recursion`, so the embed
  lands in whatever domain that value belongs to. An unforced stub
  prints its marker.
- `FileDocumentToSyntax` — a file document prints its content, so
  `<<file("child.json")>>` shows the JSON, not the `JsonFile` wrapper.

Both are **neutral about the host format**: they belong to the fabric
(`natural_to_syntax_dispatch`), which is what a document reaches when
it is rendered *for reading*. Each format keeps its own stub rule for
the other direction — `document_to_text` runs the domain projection
alone, whose table renders a stub as the marker in that format's
syntax (a `pred-ref` fence, a JSON string, a `pred_ref(…)` call), so
**saving is by marker and never by content**. One projection reads,
another writes; the split is what keeps the two invariants from
fighting.

Selection descends into an embed through `.resolved` — the stub's
field holding the evaluated value — which is a plain structural step
the walker and both reference maps carry like any other.

Both rules are domain-neutral in the direction that matters: they hand
the embedded value to `recursion`, so they work unchanged in the
to-syntax fabric and in a to-graphics dispatch table. Only the
*unforced* fallback has to know which table it is in (`unforced`).
"""
module EmbedToSyntaxModule

import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: Projection, print_document, print_child,
                              map_reference_forward, map_reference_backward, read_intent
import ..ProjectionModule: var"@projection"
import ..IoMapModule: IoMap, var"@iomap"
import ..PrinterContextModule: make_child_context
import ..ReferenceModule: FieldReferenceStep, EmptyReference, ConcreteReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..SyntaxModule: SyntaxLeaf
import ..TextModule: TextString, TextBlock
import ..StyleTextModule: StyleText, DStyleText
import ..FontModule: font_ubuntu_monospace_regular_20
import ..ColorModule: color_solarized_gray
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..FileProjectModule: FileDocument, ReferenceStub, marker_text, file_marker_text,
                            content, filename

export ReferenceStubToSyntax, FileDocumentToSyntax, EmbedIoMap

"""
    EmbedIoMap(projection, input, output, inner_iomap)

IoMap of an embed: `inner_iomap` is the embedded document's IoMap, or
`nothing` while the embed is unforced (the output is then the marker
leaf). Both cells are computed, so forcing the embed re-derives the
output in place rather than requiring a re-print.
"""
@iomap struct EmbedIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── ReferenceStubToSyntax ──────────────────────────────────────────────────

"""
    ReferenceStubToSyntax(; style, unforced)

Print a marker's value where the marker stands. A stub that has not
been forced (`resolve!`) prints its marker text instead — the same
fallback a failed marker gets, so a page never shows wrong content in
place of an embed.

`unforced` says in which domain that fallback is written, because this
rule sits in **two** dispatch tables: `:syntax` (a `SyntaxLeaf`, for
the to-syntax fabric) or `:prose` (a `TextBlock` handed back through
`recursion`, for a to-graphics table where a syntax node would be a
stranger). `style` is the marker text's style either way.
"""
@projection struct ReferenceStubToSyntax
    style::ImmutableCell{DStyleText} =
        StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    unforced::Symbol = :syntax
end

function print_document(p::ReferenceStubToSyntax, recursion, stub::ReferenceStub, ctx)
    child_ctx = make_child_context(ctx, FieldReferenceStep("resolved"))
    # `stub.resolved` reads through the stub's reactive cell, so forcing the
    # embed invalidates these two cells and the value appears by itself.
    inner = ComputedCell(() -> begin
        value = stub.resolved
        value === nothing ? nothing : print_child(recursion, value, child_ctx)
    end)
    output = ComputedCell(() -> begin
        iomap = inner[]
        iomap === nothing ?
            _unforced_output(p, recursion, marker_text(stub), ctx) : iomap.output
    end)
    EmbedIoMap(p, stub, output, inner)
end

# The marker's own text, in the domain this table speaks. `:prose` goes back
# through `recursion` so a to-graphics table renders it with its text chain
# rather than meeting a syntax node it has no rule for.
_unforced_output(p, recursion, text::AbstractString, ctx) =
    p.unforced === :prose ?
        print_child(recursion, TextBlock([TextString(text, p.style)]), ctx).output :
        SyntaxLeaf(TextString(text, p.style))

function map_reference_forward(::ReferenceStubToSyntax, iomap::EmbedIoMap, reference)
    @reference_case reference begin
        ::ReferenceStub.resolved.rest... => begin
            inner = iomap.inner_iomap
            inner === nothing && return nothing
            map_reference_forward(inner.projection, inner, rest)
        end
    end
end

function map_reference_backward(::ReferenceStubToSyntax, iomap::EmbedIoMap, reference)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    result = map_reference_backward(inner.projection, inner, reference)
    result === nothing && return nothing
    @reference ::ReferenceStub.resolved.^(result)
end

# ── FileDocumentToSyntax ───────────────────────────────────────────────────

"""
    FileDocumentToSyntax(; style, unforced)

Print a file document as its content — the file is a container for one
document, and the reader wants the document. A file with no content
prints its whole-file marker; `unforced` picks the domain that fallback
is written in, as for [`ReferenceStubToSyntax`](@ref).
"""
@projection struct FileDocumentToSyntax
    style::ImmutableCell{DStyleText} =
        StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    unforced::Symbol = :syntax
end

function print_document(p::FileDocumentToSyntax, recursion, file::FileDocument, ctx)
    child_ctx = make_child_context(ctx, FieldReferenceStep("content"))
    inner = ComputedCell(() -> begin
        value = content(file)
        value === nothing ? nothing : print_child(recursion, value, child_ctx)
    end)
    output = ComputedCell(() -> begin
        iomap = inner[]
        iomap === nothing ?
            _unforced_output(p, recursion, file_marker_text(filename(file)), ctx) : iomap.output
    end)
    EmbedIoMap(p, file, output, inner)
end

function map_reference_forward(::FileDocumentToSyntax, iomap::EmbedIoMap, reference)
    @reference_case reference begin
        ::FileDocument.content.rest... => begin
            inner = iomap.inner_iomap
            inner === nothing && return nothing
            map_reference_forward(inner.projection, inner, rest)
        end
    end
end

function map_reference_backward(::FileDocumentToSyntax, iomap::EmbedIoMap, reference)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    result = map_reference_backward(inner.projection, inner, reference)
    result === nothing && return nothing
    @reference ::FileDocument.content.^(result)
end

# ── Readers ────────────────────────────────────────────────────────────────
#
# An embed introduces no syntax of its own, so it has nothing to say about a
# gesture: it only re-roots what the embedded document's own reader produced.

for T in (:ReferenceStubToSyntax, :FileDocumentToSyntax)
    @eval function read_intent(p::$T, iomap::EmbedIoMap, op::ReplaceSelectionOperation)
        result = map_reference_backward(p, iomap, op.path)
        result === nothing ? nothing : ReplaceSelectionOperation(result)
    end
    @eval function read_intent(p::$T, iomap::EmbedIoMap, op::ReplaceStringRangeOperation)
        result = map_reference_backward(p, iomap, op.reference)
        result === nothing ? nothing : ReplaceStringRangeOperation(result, op.replacement)
    end
end

end # module EmbedToSyntaxModule
