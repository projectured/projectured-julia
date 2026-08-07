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

`wrap = :card` frames the embedded document in a titled, foldable
`WidgetCard`, so a page shows where the host stops and the embed
starts. The card is built here and lives only in the projected tree;
the document keeps its marker. A card is a widget, so this belongs in
a to-graphics table only. It costs one reference step — the card's
`content` — which both maps and the reader add on the way in and drop
on the way out.
"""
module EmbedToSyntaxModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: ComputedCellVector
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
import ..FontModule: font_ubuntu_monospace_regular_20, font_dejavu_monospace_regular_20
import ..ColorModule: color_solarized_gray
import ..GeometryModule: Point2D
import ..LayoutModule: HorizontalLayout
import ..OperationModule: ReplaceSelectionOperation, Operation
import ..WidgetModule: InvokeActionOperation, WidgetCard, WidgetLabel
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
    ReferenceStubToSyntax(; style, unforced, wrap, card_width)

Print a marker's value where the marker stands. A stub that has not
been forced (`resolve!`) prints its marker text instead — the same
fallback a failed marker gets, so a page never shows wrong content in
place of an embed.

`unforced` says in which domain that fallback is written, because this
rule sits in **two** dispatch tables: `:syntax` (a `SyntaxLeaf`, for
the to-syntax fabric) or `:prose` (a `TextBlock` handed back through
`recursion`, for a to-graphics table where a syntax node would be a
stranger). `style` is the marker text's style either way.

`wrap` frames the embedded document: `:none` prints it bare, `:card`
puts it in a titled, foldable [`WidgetCard`](@ref) so a reader can see
where the host page stops and the embedded document starts. A card is a
widget, so `:card` belongs in a to-graphics table only — a syntax tree
has no place for one. `card_width` is the card's width where no parent
allocates one.
"""
@projection struct ReferenceStubToSyntax
    style::ImmutableCell{DStyleText} =
        StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    unforced::Symbol = :syntax
    wrap::Symbol = :none
    card_width::Int = 480
end

function print_document(p::ReferenceStubToSyntax, recursion, stub::ReferenceStub, ctx)
    child_ctx = make_child_context(ctx, FieldReferenceStep("resolved"))
    # `stub.resolved` reads through the stub's reactive cell, so forcing the
    # embed invalidates these two cells and the value appears by itself.
    printed = _embed_printed(p, recursion, () -> stub.resolved,
                             () -> _embed_title(stub), child_ctx)
    output = ComputedCell(() -> begin
        iomap = printed[]
        iomap === nothing ?
            _unforced_output(p, recursion, marker_text(stub), ctx) : iomap.output
    end)
    EmbedIoMap(p, stub, output, printed)
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
            map_reference_forward(inner.projection, inner, _embed_into_wrapper(inner, rest))
        end
    end
end

function map_reference_backward(::ReferenceStubToSyntax, iomap::EmbedIoMap, reference)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    result = map_reference_backward(inner.projection, inner, reference)
    result = _embed_out_of_wrapper(inner, result)
    result === nothing && return nothing
    @reference ::ReferenceStub.resolved.^(result)
end

# ── FileDocumentToSyntax ───────────────────────────────────────────────────

"""
    FileDocumentToSyntax(; style, unforced, wrap, card_width)

Print a file document as its content — the file is a container for one
document, and the reader wants the document. A file with no content
prints its whole-file marker; `unforced` picks the domain that fallback
is written in, and `wrap` frames the content, as for
[`ReferenceStubToSyntax`](@ref).
"""
@projection struct FileDocumentToSyntax
    style::ImmutableCell{DStyleText} =
        StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    unforced::Symbol = :syntax
    wrap::Symbol = :none
    card_width::Int = 480
end

function print_document(p::FileDocumentToSyntax, recursion, file::FileDocument, ctx)
    child_ctx = make_child_context(ctx, FieldReferenceStep("content"))
    printed = _embed_printed(p, recursion, () -> content(file),
                             () -> String(filename(file)), child_ctx)
    output = ComputedCell(() -> begin
        iomap = printed[]
        iomap === nothing ?
            _unforced_output(p, recursion, file_marker_text(filename(file)), ctx) : iomap.output
    end)
    EmbedIoMap(p, file, output, printed)
end

function map_reference_forward(::FileDocumentToSyntax, iomap::EmbedIoMap, reference)
    @reference_case reference begin
        ::FileDocument.content.rest... => begin
            inner = iomap.inner_iomap
            inner === nothing && return nothing
            map_reference_forward(inner.projection, inner, _embed_into_wrapper(inner, rest))
        end
    end
end

function map_reference_backward(::FileDocumentToSyntax, iomap::EmbedIoMap, reference)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    result = map_reference_backward(inner.projection, inner, reference)
    result = _embed_out_of_wrapper(inner, result)
    result === nothing && return nothing
    @reference ::FileDocument.content.^(result)
end

# ── The card wrapper ───────────────────────────────────────────────────────
#
# `wrap = :card` prints a WidgetCard whose body is the embedded document, so the
# page shows where the embed starts and stops and the reader can fold it away.
# The card is NOT part of the document: it is built by this projection and lives
# only in the projected tree. That is why the embedded document's printer context
# keeps the embed's own step (`resolved` / `content`) — the card adds no document
# step, and adds none to the context either.

const _CARD_EXPANDED  = "▾"
const _CARD_COLLAPSED = "▸"
# SDL falls back between no fonts, and Ubuntu Mono has neither chevron.
const _CARD_TITLE_STYLE = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)

# The printed IO map of what stands where the marker stands: the embedded value
# itself, or the card that frames it. Two cells, so the card is rebuilt only when
# the value changes, and the value's own re-prints do not churn the card.
function _embed_printed(p, recursion, value_of, title_of, child_ctx)
    wrapped = ComputedCell(() -> begin
        value = value_of()
        value === nothing && return nothing
        _embed_wraps(p, value) ? _embed_card(p, value, title_of()) : value
    end)
    ComputedCell(() -> begin
        document = wrapped[]
        document === nothing ? nothing : print_child(recursion, document, child_ctx)
    end)
end

# A value that frames itself is left alone: a marker naming a whole file
# evaluates to a `FileDocument`, whose own rule gives it a card titled by the file
# name. Wrapping here as well would draw a card inside a card, titled twice.
_embed_wraps(p, value) =
    p.wrap === :card && !(value isa FileDocument) && !(value isa ReferenceStub)

# A titled, foldable card around one embedded document. The header is a reactive
# layout reading `card.collapsed` (the chevron), which is what makes a header
# click re-render without a re-print; `_card_build` drops the body itself.
function _embed_card(p, value, title::AbstractString)
    selection = ComputedCell(() -> begin
        inner = _document_selection(value)
        inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
    end)
    card = WidgetCard(Cell(Point2D(0, 0)), Cell(nothing), Cell(nothing), Cell(value),
                      Cell(nothing), Cell(Int(p.card_width)), Cell(0),
                      Cell(true), Cell(false), selection)
    card.title = HorizontalLayout(ComputedCellVector(() -> Any[
        WidgetLabel(Point2D(0, 0),
                    (card.collapsed ? _CARD_COLLAPSED : _CARD_EXPANDED) * " " * title;
                    text_style = _CARD_TITLE_STYLE)
    ]), Cell(:top), Cell(0), Cell(nothing))
    card
end

# Where the caret sits inside the embedded document, if it sits there at all. A
# value that is not a document node (a bare string a marker evaluated to) has no
# selection to read.
_document_selection(value) =
    hasproperty(value, :selection) ? getfield(value, :selection)[] : nothing

# The title a card wears. A header should say what the embed IS, not how it was
# addressed, so a marker gives up its last name: `definition(file("steps.jl"),
# "packet_queue_step")` is titled `packet_queue_step`. A marker that names
# nothing keeps its own text, which is always true if not always short.
function _embed_title(stub::ReferenceStub)
    text = marker_text(stub)
    last_name = nothing
    for match in eachmatch(r"\"([^\"]*)\"", text)
        name = match.captures[1]
        isempty(name) || (last_name = name)
    end
    last_name === nothing ? text : last_name
end

# Whether a card really stands between this embed and its document. Asked of the
# printed child rather than of the projection, because a value that frames itself
# is left unwrapped (see `_embed_wraps`).
_embed_carded(inner) = inner !== nothing && inner.input isa WidgetCard

# A path into the embedded document, as the printed child addresses it. The card's
# body hangs off `content`; without a card the child IS the document.
_embed_into_wrapper(inner, rest) =
    _embed_carded(inner) ? ConcreteReference(FieldReferenceStep("content"), rest) : rest

# The inverse: drop the step the card contributed. A path that does not come
# through the card's body — a header op — is not a path into the embedded
# document, and is refused rather than mis-rooted.
function _embed_out_of_wrapper(inner, reference)
    reference === nothing && return nothing
    _embed_carded(inner) || return reference
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    reference.tail
end

# ── Readers ────────────────────────────────────────────────────────────────
#
# An embed introduces no syntax of its own, so it has nothing to say about a
# gesture: it only re-roots what the embedded document's own reader produced.

# Where an embedded document hangs off its embed: the one step that turns a
# reference in the embedded document's domain into one in this embed's.
# Built step-by-step rather than with `@reference`: the operation an inner
# reader produced carries whatever node types it carries, and the macro refuses
# a tail it cannot type. Prepending one field step preserves the tail as it is.
_embed_step(::ReferenceStubToSyntax) = FieldReferenceStep("resolved")
_embed_step(::FileDocumentToSyntax)  = FieldReferenceStep("content")

# With a card in between, the path the inner reader answered already carries the
# card's own `content` step, because a card owns a reference step. Drop that one
# and put the embed's in its place. `nothing` when the path did not come through
# the card's body — a header op targets the card, not the document.
function _embed_reroot(p, iomap, r)
    path = _embed_out_of_wrapper(iomap.inner_iomap, r)
    path === nothing ? nothing : ConcreteReference(_embed_step(p), path)
end

for T in (:ReferenceStubToSyntax, :FileDocumentToSyntax)
    @eval function read_intent(p::$T, iomap::EmbedIoMap, op::ReplaceSelectionOperation)
        result = map_reference_backward(p, iomap, op.path)
        result === nothing ? nothing : ReplaceSelectionOperation(result)
    end
    @eval function read_intent(p::$T, iomap::EmbedIoMap, op::ReplaceStringRangeOperation)
        result = map_reference_backward(p, iomap, op.reference)
        result === nothing ? nothing : ReplaceStringRangeOperation(result, op.replacement)
    end
    # An event travels DOWN to the embedded document, and whatever its reader
    # answers comes back through the methods above.
    #
    # Without this an embed is a picture: the operation methods only re-root what
    # the embedded reader "produced", and nothing ever asked it to produce
    # anything, because the press stopped here. A live simulation card rendered
    # its buttons and none of them could be pressed.
    #
    # Dispatch keeps this from catching operations — `Operation` and the two
    # reference-carrying kinds are all more specific than an untyped argument —
    # so this only ever sees a gesture on its way in.
    # A control's activation names its own target and needs no re-rooting, but
    # the untyped event method below would hand it to the inner reader again, so
    # it is passed on explicitly. This projection sits between an embedded card's
    # controls and the editor: without it the button renders, takes the press,
    # answers, and the answer dies here.
    @eval read_intent(::$T, ::EmbedIoMap, op::InvokeActionOperation) = op
    @eval function read_intent(p::$T, iomap::EmbedIoMap, evt)
        inner = iomap.inner_iomap
        inner === nothing && return nothing
        op = read_intent(inner.projection, inner, evt)
        op === nothing && return nothing
        # Re-root only what carries a reference into the embedded document, and
        # name those types explicitly. Handing the result back to `read_intent`
        # for dispatch re-enters THIS method for any type without a specific one,
        # which is an infinite recursion — a mouse crossing the embed blew the
        # stack after 29k frames.
        # An operation the INNER reader produced is already in the embedded
        # document's own domain — it mapped it on the way out. Re-rooting it is
        # therefore prepending this embed's step, NOT running it back through
        # `map_reference_backward`, which expects a reference still in the
        # embed's OUTPUT domain and answers nothing for one that has already
        # been mapped. Doing that dropped every caret placed inside an embedded
        # card: clicking a parameter value did nothing at all.
        if op isa ReplaceSelectionOperation
            path = _embed_reroot(p, iomap, op.path)
            return path === nothing ? nothing : ReplaceSelectionOperation(path)
        elseif op isa ReplaceStringRangeOperation
            path = _embed_reroot(p, iomap, op.reference)
            return path === nothing ? nothing : ReplaceStringRangeOperation(path, op.replacement)
        end
        op   # anything else carries its own target and travels up unchanged
    end
end

end # module EmbedToSyntaxModule
