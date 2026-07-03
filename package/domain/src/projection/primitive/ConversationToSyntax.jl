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
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationTurn, ConversationPart, ConversationThinking
import ..EvaluatorModule: EvaluatorForm
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_20,
                     font_ubuntu_monospace_bold_20, font_ubuntu_monospace_italic_20
import ..ColorModule: color_default,
                     color_solarized_blue, color_solarized_green,
                     color_solarized_magenta, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
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

const _FONT      = font_ubuntu_monospace_regular_20
const _FONT_BOLD = font_ubuntu_monospace_bold_20
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
        projection_printer_recurse(recursion, c.turns[i], ctx).output
        for i in eachindex(c.turns)
    ])
    node = SyntaxNode(children; indentation=1)
    SimpleIoMap(p, c, node)
end

# ── Turn: "<role>: <part><part>…" ──────────────────────────────────────────────

function projection_print(p::ConversationTurnToSyntaxNode,
                          recursion, t::ConversationTurn, ctx)
    children = CellVector(() -> SyntaxDocument[
        projection_printer_recurse(recursion, t.parts[i], ctx).output
        for i in eachindex(t.parts)
    ])
    label = string(t.role, ":\n")
    node = SyntaxNode(children;
                      open=_ts(label, _FONT_BOLD, _LABEL_COL),
                      sep=_ts("\n"))
    SimpleIoMap(p, t, node)
end

# ── Part: dispatch on content ──────────────────────────────────────────────────

function projection_print(p::ConversationPartToSyntaxNode,
                          recursion, part::ConversationPart, ctx)
    content = part.content
    if content isa EvaluatorForm
        return _eval_form_node(p, part, content)
    elseif content isa ConversationThinking
        return _thinking_node(p, part, content)
    end
    leaf = SyntaxLeaf(_ts(() -> _content_to_string(part.content)))
    SimpleIoMap(p, part, leaf)
end

# A thinking block renders as a dimmed/italic "∴ <reasoning>" (or, for a redacted
# block, "∴ [redacted]"), de-emphasised since reasoning is secondary prose.
const _FONT_ITALIC = font_ubuntu_monospace_italic_20
function _thinking_node(p, part, t::ConversationThinking)
    body() = t.redacted ? "[redacted thinking]" : _content_to_string(t.text)
    leaf = SyntaxLeaf(
        _ts(body, _FONT_ITALIC, _DIM_COL);
        open=_ts("∴ ", _FONT_BOLD, _DIM_COL))
    SimpleIoMap(p, part, leaf)
end

# An EvaluatorForm renders as "> code" over "= result" (or "! result" on error).
function _eval_form_node(p, part, ef::EvaluatorForm)
    code_leaf = SyntaxLeaf(
        _ts(() -> _content_to_string(ef.form), _FONT, _CODE_COL);
        open=_ts("> ", _FONT_BOLD, _LABEL_COL))
    result_color = ef.is_error ? _ERR_COL : _DIM_COL
    result_label = ef.is_error ? "! " : "= "
    result_leaf = SyntaxLeaf(
        _ts(() -> _content_to_string(ef.result), _FONT, result_color);
        open=_ts(result_label, _FONT_BOLD, result_color))
    children = CellVector(SyntaxDocument[code_leaf, result_leaf])
    node = SyntaxNode(children; sep=_ts("\n"))
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
