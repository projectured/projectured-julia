"""
    ConversationToSyntaxModule

ConversationDocument → SyntaxDocument projection. Producing a single syntax
tree (instead of nested widgets) lets the existing `SyntaxToText` +
`TextToGraphics` chain handle layout: messages stack on their own lines via
`SyntaxNode` indentation, line wrapping is automatic, and selection /
cursor handling come along through the shared machinery.

    ConversationConversation      → SyntaxNode("", sep="", indentation=1)
                                      — one message per line.
    ConversationUserMessage       → SyntaxNode("user: ", body…)
    ConversationAssistantMessage  → SyntaxNode("assistant:\\n", blocks…, sep="\\n")
    ConversationCodeExecution     → SyntaxNode("<initiator>:\\n> ", code) over
                                      SyntaxNode("= ", result). Both flows
                                      (user ALT+ENTER and AI tool call)
                                      share one projection — only the
                                      `initiator` label differs.

    ConversationTextBlock         → SyntaxLeaf(text)
    ConversationCodeBlock         → SyntaxNode("```lang ", body)
    ConversationHeadingBlock      → SyntaxLeaf("# " * text)
    ConversationListBlock         → SyntaxNode("", items, sep="\\n", indentation=1)
"""
module ConversationToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationUserMessage, ConversationAssistantMessage,
                              ConversationCodeExecution,
                              ConversationTextBlock, ConversationCodeBlock,
                              ConversationHeadingBlock, ConversationListBlock
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
       ConversationUserMessageToSyntaxNode,
       ConversationAssistantMessageToSyntaxNode,
       ConversationCodeExecutionToSyntaxNode,
       ConversationTextBlockToSyntaxLeaf,
       ConversationCodeBlockToSyntaxNode,
       ConversationHeadingBlockToSyntaxLeaf,
       ConversationListBlockToSyntaxNode,
       ConversationToSyntax

# ── Projection structs ──────────────────────────────────────────────────────

struct ConversationConversationToSyntaxNode       <: Projection end
struct ConversationUserMessageToSyntaxNode        <: Projection end
struct ConversationAssistantMessageToSyntaxNode   <: Projection end
struct ConversationCodeExecutionToSyntaxNode      <: Projection end
struct ConversationTextBlockToSyntaxLeaf          <: Projection end
struct ConversationCodeBlockToSyntaxNode          <: Projection end
struct ConversationHeadingBlockToSyntaxLeaf       <: Projection end
struct ConversationListBlockToSyntaxNode          <: Projection end

# ── Style palette ──────────────────────────────────────────────────────────

const _FONT       = font_ubuntu_monospace_regular_24
const _FONT_BOLD  = font_ubuntu_monospace_bold_24
const _FONT_IT    = font_ubuntu_monospace_italic_24
const _LABEL_COL  = color_solarized_blue
const _TEXT_COL   = color_default
const _CODE_COL   = color_solarized_green
const _ERR_COL    = color_solarized_magenta
const _DIM_COL    = color_solarized_gray

_ts(s::AbstractString) = TextString(String(s), _FONT, _TEXT_COL)
_ts(s::AbstractString, font, color) = TextString(String(s), font, color)
# Thunked variants: the leaf re-reads the closure each frame, registering
# a dependency on whatever cells it touches. Use these for text whose
# content changes after `projection_print` (e.g. streaming SSE deltas
# that mutate a `ConversationTextBlock.text` in place).
_ts(f::Function) = TextString(f, _FONT, _TEXT_COL)
_ts(f::Function, font, color) = TextString(f, font, color)
_empty_ts() = TextString("", _FONT, _TEXT_COL)

# Flatten a TextText into a single rendered string (concatenates span content).
function _text_to_string(t::TextText)
    io = IOBuffer()
    for span in t.elements
        if hasproperty(span, :content)
            print(io, span.content)
        end
    end
    String(take!(io))
end
_text_to_string(s::AbstractString) = String(s)

# ── Top-level conversation: one message per line ───────────────────────────

function projection_print(p::ConversationConversationToSyntaxNode,
                          c::ConversationConversation, recursion, ctx)
    children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, c.messages[i], recursion, ctx).output
        for i in eachindex(c.messages)
    ])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _empty_ts(),
                      children, 1, Cell(false), Cell(nothing))
    SimpleIoMap(p, c, node)
end

# ── User message: "user: <body>" on one line ───────────────────────────────

function projection_print(p::ConversationUserMessageToSyntaxNode,
                          m::ConversationUserMessage, recursion, ctx)
    body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                           _ts(() -> _text_to_string(m.text)))
    children = CellVector(SyntaxDocument[body_leaf])
    node = SyntaxNode(_ts("user: ", _FONT_BOLD, _LABEL_COL),
                      _empty_ts(), _empty_ts(),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Assistant message: "assistant: <block><block>…" ────────────────────────
# Blocks are joined inline. If a block produces multi-line content, the
# SyntaxNode's own indentation handles wrapping at the SyntaxToText layer.

function projection_print(p::ConversationAssistantMessageToSyntaxNode,
                          m::ConversationAssistantMessage, recursion, ctx)
    block_children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, m.blocks[i], recursion, ctx).output
        for i in eachindex(m.blocks)
    ])
    # `assistant:` on its own line, blocks stacked below separated by newlines
    # — matches the layout of `user:\n> code\n= result` for code execution.
    node = SyntaxNode(_ts("assistant:\n", _FONT_BOLD, _LABEL_COL),
                      _empty_ts(), _ts("\n"),
                      block_children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Code execution (unified for user ALT+ENTER and AI tool call) ──────────
#
# Renders as a two-child SyntaxNode laid out across three lines:
#
#       <initiator>:
#       > <code>
#       = <result>
#
# `initiator` carries which side ran it (`:user` or `:assistant`).
function projection_print(p::ConversationCodeExecutionToSyntaxNode,
                          m::ConversationCodeExecution, recursion, ctx)
    label_prefix = () -> string(m.initiator === :assistant ? "assistant" : "user",
                                ":\n> ")
    code_leaf = SyntaxLeaf(_ts(label_prefix, _FONT_BOLD, _LABEL_COL),
                           _empty_ts(),
                           _ts(() -> m.code, _FONT, _CODE_COL))
    result_color = m.is_error ? _ERR_COL : _DIM_COL
    result_label = m.is_error ? "! " : "= "
    result_leaf = SyntaxLeaf(_ts(result_label, _FONT_BOLD, result_color),
                             _empty_ts(),
                             _ts(() -> m.result, _FONT, result_color))
    children = CellVector(SyntaxDocument[code_leaf, result_leaf])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _ts("\n"),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Blocks ─────────────────────────────────────────────────────────────────

function projection_print(p::ConversationTextBlockToSyntaxLeaf,
                          b::ConversationTextBlock, recursion, ctx)
    # Thunked: SSE deltas mutate `b.text` in place via
    # `_append_text_delta!`; we need to re-read on every frame so tokens
    # appear character-by-character.
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> _text_to_string(b.text)))
    SimpleIoMap(p, b, leaf)
end

function projection_print(p::ConversationCodeBlockToSyntaxNode,
                          b::ConversationCodeBlock, recursion, ctx)
    body_thunk = () -> begin
        body = b.body
        if body isa TextText
            _text_to_string(body)
        elseif hasproperty(body, :name)
            String(body.name)
        else
            string(body)
        end
    end
    body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                           _ts(body_thunk, _FONT, _CODE_COL))
    children = CellVector(SyntaxDocument[body_leaf])
    node = SyntaxNode(_ts(string("```", b.language, " "), _FONT_IT, _DIM_COL),
                      _ts("```", _FONT_IT, _DIM_COL),
                      _empty_ts(),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, b, node)
end

function projection_print(p::ConversationHeadingBlockToSyntaxLeaf,
                          b::ConversationHeadingBlock, recursion, ctx)
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> string(repeat("#", b.level), " ",
                                       _text_to_string(b.text)),
                          _FONT_BOLD, _TEXT_COL))
    SimpleIoMap(p, b, leaf)
end

function projection_print(p::ConversationListBlockToSyntaxNode,
                          b::ConversationListBlock, recursion, ctx)
    items = CellVector(() -> SyntaxDocument[
        # Capture `item` per iteration; the leaf thunk reads it lazily so
        # an item-text mutation refreshes without rebuilding the list.
        let item = b.items[i]
            SyntaxLeaf(_ts("- ", _FONT, _DIM_COL), _empty_ts(),
                       _ts(() -> _text_to_string(item)))
        end
        for i in eachindex(b.items)
    ])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _empty_ts(),
                      items, 1, Cell(false), Cell(nothing))
    SimpleIoMap(p, b, node)
end

# ── Reference mapping (v1: not yet wired) ──────────────────────────────────
# `projection_read` intentionally falls through to the generic
# `Projection`-default (in common/Projection.jl), which returns `nothing`
# for non-ReplaceSelectionOperation and applies `map_reference_backward`
# otherwise. Since the backward mapping below returns `nothing`, selection
# events silently no-op — preferable to forwarding a SyntaxDocument-domain
# path into a ConversationDocument-expecting consumer.

for P in (ConversationConversationToSyntaxNode,
          ConversationUserMessageToSyntaxNode,
          ConversationAssistantMessageToSyntaxNode,
          ConversationCodeExecutionToSyntaxNode,
          ConversationTextBlockToSyntaxLeaf,
          ConversationCodeBlockToSyntaxNode,
          ConversationHeadingBlockToSyntaxLeaf,
          ConversationListBlockToSyntaxNode)
    @eval map_reference_forward(::$P, iomap, ref)  = nothing
    @eval map_reference_backward(::$P, iomap, ref) = nothing
end

# ── Factory ────────────────────────────────────────────────────────────────

"""
    ConversationToSyntax()

Type-dispatching projection covering every concrete conversation document
type. Wrap in `RecursiveProjection` at the call site so child messages
and blocks are projected through the same dispatch table.
"""
function ConversationToSyntax()
    TypeDispatchingProjection(
        ConversationConversation        => ConversationConversationToSyntaxNode(),
        ConversationUserMessage         => ConversationUserMessageToSyntaxNode(),
        ConversationAssistantMessage    => ConversationAssistantMessageToSyntaxNode(),
        ConversationCodeExecution       => ConversationCodeExecutionToSyntaxNode(),
        ConversationTextBlock           => ConversationTextBlockToSyntaxLeaf(),
        ConversationCodeBlock           => ConversationCodeBlockToSyntaxNode(),
        ConversationHeadingBlock        => ConversationHeadingBlockToSyntaxLeaf(),
        ConversationListBlock           => ConversationListBlockToSyntaxNode(),
    )
end

end # module
