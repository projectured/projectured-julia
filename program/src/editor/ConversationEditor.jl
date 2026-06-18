"""
    ConversationEditorModule

The **user-message composer** (Stage 3b): editing a draft `ConversationDraft`
part by part, growing it left-to-right and always ending on an active text
typein. One projection (`ConversationComposerToWidget`) renders the draft to a
stack of per-part widget cards and maps gestures to composer operations; the
operations mutate the draft's parts in place. The draft is always a user message,
so it renders without a role/avatar header.

A part's `content` moves through these states as you edit:

| state         | content type        | gesture in →                                    |
|---------------|---------------------|-------------------------------------------------|
| text typein   | `PrimitiveString`   | keys edit; SHIFT+ENTER newline; TAB/INSERT→chooser; ENTER→submit |
| kind chooser  | `DocumentInsertion` | keys edit; ENTER commits keyword→insertion; ESC→typein |
| julia source  | `JuliaInsertion`    | keys edit; SHIFT+ENTER newline; ENTER→`JuliaDocument`; ALT+ENTER→`EvaluatorForm`; ESC→typein |
| quoted code   | `JuliaDocument`     | (committed)                                      |
| eval form     | `EvaluatorForm`     | (committed)                                      |

After any structured commit (`JuliaDocument` / `EvaluatorForm`) the composer
appends a fresh active text typein, so the draft always ends in a typein.
`TAB` / `INSERT` commits the current text typein (dropping it when blank) and appends a
`DocumentInsertion` kind chooser. Typing a keyword (`julia`/`json`/`xml`/`text`)
into the chooser does **not** auto-switch — ENTER commits it via the factory.
`ESC` reverts a structured insertion back to an empty text typein.
"""
module ConversationEditorModule

import ..ReactiveModule: Cell, setfn!
import ..CollectionModule: CellVector
import ..OperationApiModule: Operation, evaluate_operation
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart, ConversationDraft
import ..EvaluatorModule: EvaluatorForm, result_text, eval_kind_label
import ..DocumentCoreModule: DocumentInsertion
import ..PrimitiveModule: PrimitiveString
import ..JuliaModule: JuliaDocument, JuliaInsertion, JuliaIdentifier
import ..JsonModule: JsonInsertion, JsonDocument
import ..XmlModule: XmlInsertion, XmlDocument
import ..TextModule: TextText, TextString
import ..JuliaParserModule: juliaparse
import ..JsonParserModule: jsonparse
import ..XmlParserModule: xmlparse
import ..McpModule: execute_julia_code
import ..WidgetModule: WidgetCard, WidgetAvatar, WidgetLabel, Point2D
import ..LayoutModule: VerticalLayout, HorizontalLayout
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: color_default, color_solarized_gray
import ..ReferenceModule: Reference, ConcreteReferencePath, FieldReference,
                          RangeReference, EmptyReferencePath
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
import ..IoMapModule: SimpleIoMap

export ConversationComposerToWidget, composer_read, finalize_draft!, new_draft, reset_draft!,
       SUBMIT_HANDLER,
       ComposerInputOperation, ComposerBackspaceOperation, ComposerNewlineOperation,
       ComposerInsertPartOperation, ComposerCommitChooserOperation,
       ComposerCommitSourceOperation, ComposerEvaluateOperation,
       ComposerRevertOperation, ComposerSubmitOperation

# ═══════════════════════════════════════════════════════════════════════
# Active-part / cursor helpers
# ═══════════════════════════════════════════════════════════════════════

# The active part is always the last one; its content is what the gestures act
# on. An empty draft has no active part (`nothing`).
_active_part(d::ConversationDraft) =
    isempty(d) ? nothing : d.parts[length(d)]
_active_content(d::ConversationDraft) =
    (p = _active_part(d); p === nothing ? nothing : p.content)

# The editing-state contents all carry an editable `value` you can type into.
_is_editable(c) = c isa PrimitiveString || c isa DocumentInsertion ||
                  c isa JuliaInsertion || c isa JsonInsertion || c isa XmlInsertion
_is_editable(::Nothing) = false

_value(c) = something(c.value, "")

# Build a `value{k}` zero-width cursor selection path.
_valpath(k::Int) = ConcreteReferencePath(FieldReference("value"),
                       ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))

# Read the cursor offset out of a content's selection, defaulting to end-of-value.
function _cursor(c)
    sel = getfield(c, :selection)[]
    if sel isa ConcreteReferencePath && sel.head isa FieldReference && sel.head.name == "value"
        t = sel.tail
        if t isa ConcreteReferencePath && t.head isa RangeReference
            return t.head.stop
        end
    end
    length(_value(c))
end

# Set a content's value + place the cursor at `k`.
function _set_value!(c, v::AbstractString, k::Int)
    c.value = String(v)
    c.selection = _valpath(k)
    nothing
end

# A fresh active text typein (empty `PrimitiveString`, cursor at 0).
function _new_typein()
    ps = PrimitiveString("")
    ps.selection = _valpath(0)
    ConversationPart(ps)
end

# Replace the active part's content and drop the cursor at the value's end.
function _replace_active!(d::ConversationDraft, doc)
    p = _active_part(d)
    p === nothing && return nothing
    p.content = doc
    _is_editable(doc) && (doc.selection = _valpath(length(_value(doc))))
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Operations
# ═══════════════════════════════════════════════════════════════════════

"Insert printable `text` at the active content's cursor."
struct ComposerInputOperation <: Operation
    draft::ConversationDraft
    text::String
end

"Delete the character before the active content's cursor."
struct ComposerBackspaceOperation <: Operation
    draft::ConversationDraft
end

"Insert a newline at the active content's cursor (SHIFT+ENTER)."
struct ComposerNewlineOperation <: Operation
    draft::ConversationDraft
end

"""
INSERT: commit the active text typein (→ `TextText`, dropped when blank) and
append a `DocumentInsertion` kind chooser as the new active part.
"""
struct ComposerInsertPartOperation <: Operation
    draft::ConversationDraft
end

"""
ENTER in the kind chooser: if the value names a known kind, commit it to that
domain's insertion via the factory; otherwise a no-op (keep editing).
"""
struct ComposerCommitChooserOperation <: Operation
    draft::ConversationDraft
end

"""
ENTER in Julia source: parse the source into a `JuliaDocument`, then append a
fresh active text typein. No-op when the source does not parse.
"""
struct ComposerCommitSourceOperation <: Operation
    draft::ConversationDraft
end

"""
ALT+ENTER in Julia source: parse and evaluate the source into an `EvaluatorForm`
(code + result), then append a fresh active text typein.
"""
struct ComposerEvaluateOperation <: Operation
    draft::ConversationDraft
end

"ESC: revert the active structured insertion back to an empty text typein."
struct ComposerRevertOperation <: Operation
    draft::ConversationDraft
end

"""
ENTER in a text typein: finalize the draft — convert every `PrimitiveString`
part to `TextText`, dropping a trailing blank typein.
"""
struct ComposerSubmitOperation <: Operation
    draft::ConversationDraft
end

# ═══════════════════════════════════════════════════════════════════════
# evaluate_operation
# ═══════════════════════════════════════════════════════════════════════

function evaluate_operation(editor, op::ComposerInputOperation)
    c = _active_content(op.draft)
    _is_editable(c) || return nothing
    v = _value(c); k = clamp(_cursor(c), 0, length(v))
    _set_value!(c, first(v, k) * op.text * last(v, length(v) - k), k + length(op.text))
end

function evaluate_operation(editor, op::ComposerNewlineOperation)
    c = _active_content(op.draft)
    _is_editable(c) || return nothing
    v = _value(c); k = clamp(_cursor(c), 0, length(v))
    _set_value!(c, first(v, k) * "\n" * last(v, length(v) - k), k + 1)
end

function evaluate_operation(editor, op::ComposerBackspaceOperation)
    c = _active_content(op.draft)
    _is_editable(c) || return nothing
    v = _value(c); k = clamp(_cursor(c), 0, length(v))
    k == 0 && return nothing
    _set_value!(c, first(v, k - 1) * last(v, length(v) - k), k - 1)
end

function evaluate_operation(editor, op::ComposerInsertPartOperation)
    d = op.draft
    p = _active_part(d)
    if p !== nothing && p.content isa PrimitiveString
        v = _value(p.content)
        if isempty(strip(v))
            deleteat!(d.parts, length(d))          # drop the blank typein
        else
            p.content = TextText(TextString(v))    # commit the prose
        end
    end
    ins = DocumentInsertion("")
    ins.selection = _valpath(0)
    push!(d, ConversationPart(ins))
    nothing
end

# Kind keyword → the domain insertion the chooser grows into. Each is an editable
# insertion you then type a source into (and, later, drive structurally — e.g. a
# `JsonInsertion` turning into a `JsonArray` on `[`). Julia additionally parses +
# evaluates today; JSON/XML source parsing lands with the Stage-5 parsers.
function _composer_factory(name::AbstractString)
    n = lowercase(strip(name))
    n == "julia" ? JuliaInsertion("") :
    n == "json"  ? JsonInsertion()    :
    n == "xml"   ? XmlInsertion()     : nothing
end

function evaluate_operation(editor, op::ComposerCommitChooserOperation)
    c = _active_content(op.draft)
    c isa DocumentInsertion || return nothing
    doc = _composer_factory(_value(c))
    doc === nothing && return nothing              # unknown/unsupported: keep editing
    _replace_active!(op.draft, doc)
end

# Parse a source insertion into its domain document, by insertion type.
_parse_source(c::JuliaInsertion) = _try_parse(juliaparse, _value(c))
_parse_source(c::JsonInsertion)  = _try_parse(jsonparse, _value(c))
_parse_source(c::XmlInsertion)   = _try_parse(xmlparse, _value(c))
_parse_source(_) = nothing

function evaluate_operation(editor, op::ComposerCommitSourceOperation)
    doc = _parse_source(_active_content(op.draft))
    doc === nothing && return nothing              # unparseable: keep editing
    _replace_active!(op.draft, doc)
    push!(op.draft, _new_typein())
    nothing
end

function evaluate_operation(editor, op::ComposerEvaluateOperation)
    c = _active_content(op.draft)
    c isa JuliaInsertion || return nothing
    src = _value(c)
    isempty(strip(src)) && return nothing
    output = try
        execute_julia_code(editor, src)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_err = occursin("ERROR", output) || occursin("Error", output)
    form = something(_try_parse(juliaparse, src), JuliaIdentifier(src))
    # `execute_julia_code` `println`s the result repr, so the captured output ends
    # in a newline — strip it so the result text doesn't render a trailing tofu box.
    _replace_active!(op.draft,
        EvaluatorForm(form; result = result_text(rstrip(output)), is_error = is_err))
    push!(op.draft, _new_typein())
    nothing
end

function evaluate_operation(editor, op::ComposerRevertOperation)
    _replace_active!(op.draft, getfield(_new_typein(), :content)[])
end

"""
    finalize_draft!(draft) -> Bool

Normalize a draft for submission: drop a trailing blank text typein and convert
every remaining `PrimitiveString` part to committed `TextText` prose. Returns
whether the draft still has any parts (i.e. is worth submitting).
"""
function finalize_draft!(d::ConversationDraft)
    p = _active_part(d)
    if p !== nothing && p.content isa PrimitiveString && isempty(strip(_value(p.content)))
        deleteat!(d.parts, length(d))
    end
    for i in eachindex(d.parts)
        part = d.parts[i]
        part.content isa PrimitiveString &&
            (part.content = TextText(TextString(_value(part.content))))
    end
    !isempty(d)
end

evaluate_operation(editor, op::ComposerSubmitOperation) = (finalize_draft!(op.draft); nothing)

"""
    new_draft() -> ConversationDraft

A fresh empty user draft (one active text typein) for the composer.
"""
new_draft() = ConversationDraft([_new_typein()])

"""
    reset_draft!(draft)

Reset a draft **in place** to a single empty text typein — used after its content
has been submitted. Mutating in place (rather than replacing the draft) keeps a
cached projection of the draft valid and reactive.
"""
function reset_draft!(d::ConversationDraft)
    getfield(d.parts, :elements)[] = Cell[Cell(_new_typein())]
    d
end

# Parse source with `f`, guarding empty / invalid input (returns `nothing`).
function _try_parse(f, src::AbstractString)
    isempty(strip(src)) && return nothing
    try
        f(src)
    catch
        nothing
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Printer: draft turn → a chat-bubble WidgetCard of per-part cards
# ═══════════════════════════════════════════════════════════════════════

"""
    ConversationComposerToWidget()

The composer projection for a `ConversationDraft`. Self-contained: the printer
renders the draft as a `VerticalLayout` of per-part `WidgetCard`s (no role/avatar
header — the draft is always a user message), and the reader maps every gesture
to a composer operation by dispatching on the **active** (last) part's state. Use
as the root projection, chained through the widget→graphics pipeline (wrap in
`RecursiveProjection`).
"""
struct ConversationComposerToWidget <: Projection end

const _PART_WIDTH  = 720
const _AVATAR_SIZE = 22
const _GAP         = 6

# Per-part glyph/label, covering both editing states and committed content.
_kind_glyph(::PrimitiveString)   = "✎"
_kind_glyph(::DocumentInsertion) = "+"
_kind_glyph(::JuliaInsertion)    = "λ"
_kind_glyph(::JuliaDocument)     = "λ"
_kind_glyph(::EvaluatorForm)     = "="
_kind_glyph(::TextText)          = "¶"
_kind_glyph(::JsonDocument)      = "{}"   # JsonInsertion and committed JSON
_kind_glyph(::XmlDocument)       = "<>"   # XmlInsertion and committed XML
_kind_glyph(_)                   = "?"

_kind_label(::JsonDocument)      = "json"
_kind_label(::XmlDocument)       = "xml"
_kind_label(::PrimitiveString)   = "text"
_kind_label(::DocumentInsertion) = "insert"
_kind_label(::JuliaInsertion)    = "julia"
_kind_label(::JuliaDocument)     = "julia"
_kind_label(f::EvaluatorForm)    = eval_kind_label(f)
_kind_label(::TextText)          = "text"
_kind_label(_)                   = "doc"

# A header row: a small avatar glyph followed by a label.
_header(glyph::AbstractString, label::AbstractString) =
    HorizontalLayout(Any[
        WidgetAvatar(Point2D(0, 0), String(glyph); size = _AVATAR_SIZE),
        WidgetLabel(Point2D(0, 0), String(label)),
    ]; vertical_align = :center, gap = 8)

const _FONT        = font_ubuntu_monospace_regular_24
const _PLACEHOLDER = "type here…"

# A zero-width cursor at offset `k` inside span `span` (1-based) of a body
# `TextText`, in the `.elements[span].content[k:k]` shape `TextToGraphics` reads
# to draw its genuine thin-line caret.
_caret_selection(span::Int, k::Int) =
    ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(span - 1, span),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))))

# Install the reactive caret on `body`, tracking `content`'s cursor in `span`.
# `span_len` is the rendered length of that span so the cursor stays in range.
function _attach_caret!(body::TextText, content, span::Int, span_len)
    setfn!(getfield(body, :selection),
           () -> _caret_selection(span, clamp(_cursor(content), 0, span_len())))
    body
end

# ── Editable (active) part body — its value plus the real selection-driven caret.
# Safe to carry a text selection: the enclosing turn `WidgetCard` reader drops
# coordless key events, so the text layer never hijacks the composer's keys.

# A `DocumentInsertion` keeps its "Insert a new <value> here" decoration: static
# gray prefix/suffix spans around the editable value span, caret in the value.
const _INS_PREFIX = "Insert a new "
const _INS_SUFFIX = " here"
function _editable_body(c::DocumentInsertion)
    body = TextText([
        TextString(_INS_PREFIX, _FONT, color_solarized_gray),
        TextString(() -> _value(c), _FONT, color_default),
        TextString(_INS_SUFFIX, _FONT, color_solarized_gray),
    ])
    # While the value is empty, anchor the caret to the end of the (non-empty)
    # prefix span — `TextToGraphics` can't place a caret in a zero-width span, and
    # this lands at the same x (just after "Insert a new ").
    setfn!(getfield(body, :selection), function ()
        v = _value(c)
        isempty(v) ? _caret_selection(1, length(_INS_PREFIX)) :
                     _caret_selection(2, clamp(_cursor(c), 0, length(v)))
    end)
    body
end

# Plain editable text (`PrimitiveString` / `JuliaInsertion`): one span, a pale
# placeholder while empty, caret in the single span.
function _editable_body(c)
    show() = (v = _value(c); isempty(v) ? _PLACEHOLDER : v)
    ts = TextString(show, _FONT, color_default)
    setfn!(getfield(ts, :font_color),
           () -> isempty(_value(c)) ? color_solarized_gray : color_default)
    _attach_caret!(TextText(ts), c, 1, () -> length(show()))
end

# ── Committed part body — recurse the real content document through the inner
# dispatch, so committed code renders as a parsed Julia document, prose as text,
# and an evaluation as its form stacked over its result.
_committed_body(c::EvaluatorForm) = VerticalLayout(Any[c.form, c.result]; gap = _GAP)
_committed_body(c) = c

_part_card(content, active::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _header(_kind_glyph(content), _kind_label(content)),
               content = (active && _is_editable(content)) ?
                         _editable_body(content) : _committed_body(content),
               width = _PART_WIDTH)

function projection_print(p::ConversationComposerToWidget, recursion, d::ConversationDraft, ctx)
    # The draft is always a user message, so it renders as just its stack of part
    # cards — no role/avatar header card around them. Reactive part list: the last
    # part is the active typein (gets the caret). The thunk recomputes on
    # structural changes; per-part value/cursor edits re-render via the reactive
    # `TextString` thunks inside each card.
    body = VerticalLayout(
        CellVector(() -> (n = length(d.parts);
                          Any[_part_card(d.parts[i].content, i == n) for i in 1:n])),
        Cell(:left), Cell(_GAP), Cell(nothing))
    SimpleIoMap(p, d, body)
end

# The composer manages its own selection; nothing is forwarded to the widget
# layers (so they never hijack key events for a mapped cursor).
map_reference_forward(::ConversationComposerToWidget, iomap, ref)  = nothing
map_reference_backward(::ConversationComposerToWidget, iomap, ref) = nothing

# ═══════════════════════════════════════════════════════════════════════
# Reader: gesture → composer operation, dispatched on the active part's state
# ═══════════════════════════════════════════════════════════════════════

"""
    composer_read(draft, event) -> Operation | nothing

Map a key gesture to a composer operation on `draft`, dispatching on the active
(last) part's state. Shared by the composer projection and the live assistant
panel (which routes its input keys to the draft). `ENTER` on a plain text typein
yields a `ComposerSubmitOperation`; the panel intercepts that to submit the draft
into the conversation instead of merely normalizing it.
"""
function composer_read(draft::ConversationDraft, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    _is_editable(_active_content(draft)) || return nothing
    ComposerInputOperation(draft, String(evt.text))
end

function composer_read(draft::ConversationDraft, evt::KeyDown)
    c = _active_content(draft)
    if c isa PrimitiveString
        return @event_case evt begin
            KeyDown(:return; shift) => ComposerNewlineOperation(draft)
            KeyDown(:return)        => ComposerSubmitOperation(draft)
            KeyDown(:tab)           => ComposerInsertPartOperation(draft)
            KeyDown(:insert)        => ComposerInsertPartOperation(draft)
            KeyDown(:backspace)     => ComposerBackspaceOperation(draft)
        end
    elseif c isa DocumentInsertion
        return @event_case evt begin
            KeyDown(:return)    => ComposerCommitChooserOperation(draft)
            KeyDown(:escape)    => ComposerRevertOperation(draft)
            KeyDown(:backspace) => ComposerBackspaceOperation(draft)
        end
    elseif c isa JuliaInsertion
        return @event_case evt begin
            KeyDown(:return; alt)   => ComposerEvaluateOperation(draft)
            KeyDown(:return; shift) => ComposerNewlineOperation(draft)
            KeyDown(:return)        => ComposerCommitSourceOperation(draft)
            KeyDown(:escape)        => ComposerRevertOperation(draft)
            KeyDown(:backspace)     => ComposerBackspaceOperation(draft)
        end
    elseif c isa JsonInsertion || c isa XmlInsertion
        # Editable source insertion: ENTER parses it into a JsonDocument/XmlElement
        # (no-op while it doesn't parse). Structural key-driven insertion (`[` →
        # JsonArray, …) is still future work.
        return @event_case evt begin
            KeyDown(:return; shift) => ComposerNewlineOperation(draft)
            KeyDown(:return)        => ComposerCommitSourceOperation(draft)
            KeyDown(:escape)        => ComposerRevertOperation(draft)
            KeyDown(:backspace)     => ComposerBackspaceOperation(draft)
        end
    end
    nothing
end

composer_read(::Any, ::Any) = nothing

# Hook for turning the composer's `ComposerSubmitOperation` into a host-specific
# submit operation. The live assistant panel registers `a -> SubmitDraftTurnOperation(a)`
# here (it can't be referenced directly — module order: the composer loads first).
const SUBMIT_HANDLER = Ref{Any}(nothing)

projection_read(::ConversationComposerToWidget, iomap::SimpleIoMap, evt::KeyPress) =
    composer_read(iomap.input, evt)

function projection_read(::ConversationComposerToWidget, iomap::SimpleIoMap, evt::KeyDown)
    d = iomap.input                       # ConversationDraft
    op = composer_read(d, evt)
    # When the draft belongs to an assistant, ENTER's `ComposerSubmitOperation`
    # (which only normalizes the draft) becomes the host's submit op (push + stream).
    if op isa ComposerSubmitOperation && d.assistant !== nothing && SUBMIT_HANDLER[] !== nothing
        return SUBMIT_HANDLER[](d.assistant)
    end
    op
end

end # module
