"""
    ConversationToSyntaxModule

ConversationDocument → SyntaxDocument projection. Producing a single syntax
tree (instead of nested widgets) lets the existing `SyntaxToText` +
`TextToGraphics` chain handle layout, wrapping, and cursor handling.

    ConversationConversation → SyntaxNode (one turn per line, indentation=1)
    ConversationTurn         → SyntaxNode("<role>: ", parts…, sep="\\n")
    ConversationPart         → dispatch on the part's `content`:
                                 * EvaluatorForm → "> code" over "= result"
                                 * everything else → a leaf of the content's text

This is the Stage-1 port: part content is rendered by *stringifying* it into a
syntax leaf (as the previous block-based projection did), not by recursing into
its own domain projection. Recursing content through its real projection chain
is the widget-presentation work (`ConversationToWidget`, later stages).
"""
module ConversationToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationTurn, ConversationPart
import ..EvaluatorModule: EvaluatorForm
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24,
                     font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: color_default,
                     color_solarized_blue, color_solarized_green,
                     color_solarized_magenta, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..PrinterContextModule: child_context

export ConversationConversationToSyntaxNode,
       ConversationTurnToSyntaxNode,
       ConversationPartToSyntaxNode,
       ConversationToSyntax

# ── Projection structs ────────────────────────────────────────────────────────

struct ConversationConversationToSyntaxNode <: Projection end
struct ConversationTurnToSyntaxNode         <: Projection end
struct ConversationPartToSyntaxNode         <: Projection end

# ── Style palette ──────────────────────────────────────────────────────────────

const _FONT      = font_ubuntu_monospace_regular_24
const _FONT_BOLD = font_ubuntu_monospace_bold_24
const _LABEL_COL = color_solarized_blue
const _TEXT_COL  = color_default
const _CODE_COL  = color_solarized_green
const _ERR_COL   = color_solarized_magenta
const _DIM_COL   = color_solarized_gray

_ts(s::AbstractString) = TextString(String(s), _FONT, _TEXT_COL)
_ts(s::AbstractString, font, color) = TextString(String(s), font, color)
_ts(f::Function) = TextString(f, _FONT, _TEXT_COL)
_ts(f::Function, font, color) = TextString(f, font, color)
_empty_ts() = TextString("", _FONT, _TEXT_COL)

# Flatten a TextText into a single rendered string.
function _text_to_string(t::TextText)
    io = IOBuffer()
    for span in t.elements
        hasproperty(span, :content) && print(io, span.content)
    end
    String(take!(io))
end
_text_to_string(s::AbstractString) = String(s)

# Stringify an arbitrary part content for the Stage-1 syntax rendering.
_content_to_string(t::TextText) = _text_to_string(t)
_content_to_string(d) = hasproperty(d, :name) ? String(d.name) : string(d)

# ── Top-level conversation: one turn per line ──────────────────────────────────

function projection_print(p::ConversationConversationToSyntaxNode,
                          recursion, c::ConversationConversation, ctx)
    children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, recursion, c.turns[i], ctx).output
        for i in eachindex(c.turns)
    ])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _empty_ts(),
                      children, 1, Cell(false), Cell(nothing))
    SimpleIoMap(p, c, node)
end

# ── Turn: "<role>: <part><part>…" ──────────────────────────────────────────────

function projection_print(p::ConversationTurnToSyntaxNode,
                          recursion, t::ConversationTurn, ctx)
    children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, recursion, t.parts[i], ctx).output
        for i in eachindex(t.parts)
    ])
    label = string(t.role, ":\n")
    node = SyntaxNode(_ts(label, _FONT_BOLD, _LABEL_COL),
                      _empty_ts(), _ts("\n"),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, t, node)
end

# ── Part: dispatch on content ──────────────────────────────────────────────────

function projection_print(p::ConversationPartToSyntaxNode,
                          recursion, part::ConversationPart, ctx)
    content = part.content
    if content isa EvaluatorForm
        return _eval_form_node(p, part, content)
    end
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> _content_to_string(part.content)))
    SimpleIoMap(p, part, leaf)
end

# An EvaluatorForm renders as "> code" over "= result" (or "! result" on error).
function _eval_form_node(p, part, ef::EvaluatorForm)
    code_leaf = SyntaxLeaf(_ts("> ", _FONT_BOLD, _LABEL_COL),
                           _empty_ts(),
                           _ts(() -> _content_to_string(ef.form), _FONT, _CODE_COL))
    result_color = ef.is_error ? _ERR_COL : _DIM_COL
    result_label = ef.is_error ? "! " : "= "
    result_leaf = SyntaxLeaf(_ts(result_label, _FONT_BOLD, result_color),
                             _empty_ts(),
                             _ts(() -> _content_to_string(ef.result), _FONT, result_color))
    children = CellVector(SyntaxDocument[code_leaf, result_leaf])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _ts("\n"),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, part, node)
end

# ── Reference mapping (v1: not wired) ──────────────────────────────────────────

for P in (ConversationConversationToSyntaxNode,
          ConversationTurnToSyntaxNode,
          ConversationPartToSyntaxNode)
    @eval map_reference_forward(::$P, iomap, ref)  = nothing
    @eval map_reference_backward(::$P, iomap, ref) = nothing
    @eval projection_read(::$P, iomap, op) = op
end

# ── Factory ────────────────────────────────────────────────────────────────────

"""
    ConversationToSyntax()

Type-dispatching projection over the conversation document types. Wrap in
`RecursiveProjection` at the call site.
"""
function ConversationToSyntax()
    TypeDispatchingProjection(
        ConversationConversation => ConversationConversationToSyntaxNode(),
        ConversationTurn         => ConversationTurnToSyntaxNode(),
        ConversationPart         => ConversationPartToSyntaxNode(),
    )
end

end # module
