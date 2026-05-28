"""
    ConversationToSyntaxModule

ConversationDocument → SyntaxDocument projection. Producing a single syntax
tree (instead of nested widgets) lets the existing `SyntaxToText` +
`TextToGraphics` chain handle layout: messages stack on their own lines via
`SyntaxNode` indentation, line wrapping is automatic, and selection /
cursor handling come along through the shared machinery.

    ConversationConversation       → SyntaxNode("", sep="", indentation=1)
                                       — one message per line.
    ConversationUserMessage        → SyntaxNode("user: ", body…)
    ConversationAssistantMessage   → SyntaxNode("assistant: ", blocks…)
    ConversationToolUseMessage     → SyntaxLeaf("[tool_use …]")
    ConversationToolResultMessage  → SyntaxNode("[tool_result] ", body)
    ConversationJuliaInputMessage  → SyntaxNode("> ", code)  (Julia)
    ConversationJuliaResultMessage → SyntaxNode("= ", output)

    ConversationTextBlock          → SyntaxLeaf(text)
    ConversationCodeBlock          → SyntaxNode("```lang ", body)
    ConversationHeadingBlock       → SyntaxLeaf("# " * text)
    ConversationListBlock          → SyntaxNode("", items, sep="\\n", indentation=1)
    ConversationToolUseBlock       → SyntaxLeaf("[tool_use …]")
"""
module ConversationToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationUserMessage, ConversationAssistantMessage,
                              ConversationToolUseMessage, ConversationToolResultMessage,
                              ConversationJuliaInputMessage, ConversationJuliaResultMessage,
                              ConversationTextBlock, ConversationCodeBlock,
                              ConversationHeadingBlock, ConversationListBlock,
                              ConversationToolUseBlock
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24,
                     font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: color_default,
                     color_solarized_blue, color_solarized_green,
                     color_solarized_magenta, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap

export ConversationConversationToSyntaxNode,
       ConversationUserMessageToSyntaxNode,
       ConversationAssistantMessageToSyntaxNode,
       ConversationToolUseMessageToSyntaxLeaf,
       ConversationToolResultMessageToSyntaxNode,
       ConversationJuliaInputMessageToSyntaxNode,
       ConversationJuliaResultMessageToSyntaxNode,
       ConversationTextBlockToSyntaxLeaf,
       ConversationCodeBlockToSyntaxNode,
       ConversationHeadingBlockToSyntaxLeaf,
       ConversationListBlockToSyntaxNode,
       ConversationToolUseBlockToSyntaxLeaf,
       ConversationToSyntax

# ── Projection structs ──────────────────────────────────────────────────────

struct ConversationConversationToSyntaxNode       <: Projection end
struct ConversationUserMessageToSyntaxNode        <: Projection end
struct ConversationAssistantMessageToSyntaxNode   <: Projection end
struct ConversationToolUseMessageToSyntaxLeaf     <: Projection end
struct ConversationToolResultMessageToSyntaxNode  <: Projection end
struct ConversationJuliaInputMessageToSyntaxNode  <: Projection end
struct ConversationJuliaResultMessageToSyntaxNode <: Projection end
struct ConversationTextBlockToSyntaxLeaf          <: Projection end
struct ConversationCodeBlockToSyntaxNode          <: Projection end
struct ConversationHeadingBlockToSyntaxLeaf       <: Projection end
struct ConversationListBlockToSyntaxNode          <: Projection end
struct ConversationToolUseBlockToSyntaxLeaf       <: Projection end

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
                          c::ConversationConversation, recursion, reference)
    children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, c.messages[i], recursion, reference).output
        for i in eachindex(c.messages)
    ])
    node = SyntaxNode(_empty_ts(), _empty_ts(), _empty_ts(),
                      children, 1, Cell(false), Cell(nothing))
    SimpleIoMap(p, c, node)
end

# ── User message: "user: <body>" on one line ───────────────────────────────

function projection_print(p::ConversationUserMessageToSyntaxNode,
                          m::ConversationUserMessage, recursion, reference)
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
                          m::ConversationAssistantMessage, recursion, reference)
    block_children = CellVector(() -> SyntaxDocument[
        projection_print(recursion, m.blocks[i], recursion, reference).output
        for i in eachindex(m.blocks)
    ])
    node = SyntaxNode(_ts("assistant: ", _FONT_BOLD, _LABEL_COL),
                      _empty_ts(), _empty_ts(),
                      block_children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Tool use / result messages ─────────────────────────────────────────────

function projection_print(p::ConversationToolUseMessageToSyntaxLeaf,
                          m::ConversationToolUseMessage, recursion, reference)
    # The same tool call already renders in the preceding assistant message's
    # blocks (via ConversationToolUseBlockToSyntaxLeaf). This standalone
    # message only carries live status — show it while the call is in flight,
    # render empty once done so the conversation stays clean.
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> m.status === :done ? "" :
                                m.status === :running ? "  (running…)" :
                                string("  (", m.status, ")"),
                          _FONT_IT, _DIM_COL))
    SimpleIoMap(p, m, leaf)
end

function projection_print(p::ConversationToolResultMessageToSyntaxNode,
                          m::ConversationToolResultMessage, recursion, reference)
    color = m.is_error ? _ERR_COL : _DIM_COL
    body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                           _ts(() -> _text_to_string(m.content), _FONT, color))
    children = CellVector(SyntaxDocument[body_leaf])
    label = m.is_error ? "! " : "= "
    node = SyntaxNode(_ts(label, _FONT_BOLD, color),
                      _empty_ts(), _empty_ts(),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Julia input/result messages ────────────────────────────────────────────

function projection_print(p::ConversationJuliaInputMessageToSyntaxNode,
                          m::ConversationJuliaInputMessage, recursion, reference)
    body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                           _ts(() -> hasproperty(m.code, :name) ?
                                       String(m.code.name) : string(m.code),
                               _FONT, _CODE_COL))
    children = CellVector(SyntaxDocument[body_leaf])
    node = SyntaxNode(_ts("> ", _FONT_BOLD, _LABEL_COL),
                      _empty_ts(), _empty_ts(),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

function projection_print(p::ConversationJuliaResultMessageToSyntaxNode,
                          m::ConversationJuliaResultMessage, recursion, reference)
    color = m.is_error ? _ERR_COL : _TEXT_COL
    body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                           _ts(() -> _text_to_string(m.output), _FONT, color))
    children = CellVector(SyntaxDocument[body_leaf])
    node = SyntaxNode(_ts("= ", _FONT_BOLD, _DIM_COL),
                      _empty_ts(), _empty_ts(),
                      children, 0, Cell(false), Cell(nothing))
    SimpleIoMap(p, m, node)
end

# ── Blocks ─────────────────────────────────────────────────────────────────

function projection_print(p::ConversationTextBlockToSyntaxLeaf,
                          b::ConversationTextBlock, recursion, reference)
    # Thunked: SSE deltas mutate `b.text` in place via
    # `_append_text_delta!`; we need to re-read on every frame so tokens
    # appear character-by-character.
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> _text_to_string(b.text)))
    SimpleIoMap(p, b, leaf)
end

function projection_print(p::ConversationCodeBlockToSyntaxNode,
                          b::ConversationCodeBlock, recursion, reference)
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
                          b::ConversationHeadingBlock, recursion, reference)
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> string(repeat("#", b.level), " ",
                                       _text_to_string(b.text)),
                          _FONT_BOLD, _TEXT_COL))
    SimpleIoMap(p, b, leaf)
end

function projection_print(p::ConversationListBlockToSyntaxNode,
                          b::ConversationListBlock, recursion, reference)
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

function projection_print(p::ConversationToolUseBlockToSyntaxLeaf,
                          b::ConversationToolUseBlock, recursion, reference)
    # For `execute_julia_code` tool calls, render the code with the same
    # "> <code>" prefix and green color the manual ALT+ENTER variant uses
    # (ConversationJuliaInputMessage). This makes AI-initiated and manual
    # Julia evals look the same in the conversation, paired with the
    # "= <result>" line the tool result message produces.
    if b.name == "execute_julia_code"
        body_leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                               _ts(() -> begin
                                       input = b.input
                                       input isa AbstractDict && haskey(input, "code") ?
                                           String(input["code"]) : ""
                                   end,
                                   _FONT, _CODE_COL))
        children = CellVector(SyntaxDocument[body_leaf])
        node = SyntaxNode(_ts("> ", _FONT_BOLD, _LABEL_COL),
                          _empty_ts(), _empty_ts(),
                          children, 0, Cell(false), Cell(nothing))
        return SimpleIoMap(p, b, node)
    end

    # Other tools: surface the call inline, dropping the opaque tool_use id.
    leaf = SyntaxLeaf(_ts("tool: ", _FONT_BOLD, _LABEL_COL),
                      _empty_ts(),
                      _ts(() -> string(b.name, "  ", _format_tool_input(b.name, b.input)),
                          _FONT_IT, _DIM_COL))
    SimpleIoMap(p, b, leaf)
end

# Format a tool's input for inline display. Surfaces the salient argument
# for tools we know about; otherwise prints a compact summary of the dict.
function _format_tool_input(name::AbstractString, input)
    input isa AbstractDict || return string(input)
    if name == "execute_julia_code" && haskey(input, "code")
        return String(input["code"])
    elseif name == "read_resource" && haskey(input, "uri")
        return String(input["uri"])
    else
        parts = String[]
        for (k, v) in input
            push!(parts, string(k, "=", v))
        end
        return join(parts, " ")
    end
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
          ConversationToolUseMessageToSyntaxLeaf,
          ConversationToolResultMessageToSyntaxNode,
          ConversationJuliaInputMessageToSyntaxNode,
          ConversationJuliaResultMessageToSyntaxNode,
          ConversationTextBlockToSyntaxLeaf,
          ConversationCodeBlockToSyntaxNode,
          ConversationHeadingBlockToSyntaxLeaf,
          ConversationListBlockToSyntaxNode,
          ConversationToolUseBlockToSyntaxLeaf)
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
        ConversationToolUseMessage      => ConversationToolUseMessageToSyntaxLeaf(),
        ConversationToolResultMessage   => ConversationToolResultMessageToSyntaxNode(),
        ConversationJuliaInputMessage   => ConversationJuliaInputMessageToSyntaxNode(),
        ConversationJuliaResultMessage  => ConversationJuliaResultMessageToSyntaxNode(),
        ConversationTextBlock           => ConversationTextBlockToSyntaxLeaf(),
        ConversationCodeBlock           => ConversationCodeBlockToSyntaxNode(),
        ConversationHeadingBlock        => ConversationHeadingBlockToSyntaxLeaf(),
        ConversationListBlock           => ConversationListBlockToSyntaxNode(),
        ConversationToolUseBlock        => ConversationToolUseBlockToSyntaxLeaf(),
    )
end

end # module
