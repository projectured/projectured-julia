# Fragment of `ConversationModule`.
#
# The **user-message composer** (Stage 3b): editing a draft `ConversationDraft`
# part by part, growing it left-to-right and always ending on an active text
# typein. One projection (`ConversationComposerToWidget`) renders the draft to a
# stack of per-part widget cards and maps gestures to composer operations; the
# operations mutate the draft's parts in place. The draft is always a user message,
# so it renders without a role/avatar header.
#
# A part's `content` moves through these states as you edit:
#
# | state         | content type        | gesture in →                                    |
# |---------------|---------------------|-------------------------------------------------|
# | text typein   | `PrimitiveString`   | keys edit; SHIFT+ENTER newline; TAB/INSERT→chooser; ENTER→submit |
# | kind chooser  | `DocumentInsertion` | keys edit; ENTER commits keyword→insertion; ESC→typein |
# | julia source  | `JuliaInsertion`    | keys edit; SHIFT+ENTER newline; ENTER→`JuliaDocument`; ALT+ENTER→`EvaluatorForm`; ESC→typein |
# | quoted code   | `JuliaDocument`     | (committed)                                      |
# | eval form     | `EvaluatorForm`     | (committed)                                      |
#
# After any structured commit (`JuliaDocument` / `EvaluatorForm`) the composer
# appends a fresh active text typein, so the draft always ends in a typein.
# `TAB` / `INSERT` commits the current text typein (dropping it when blank) and appends a
# `DocumentInsertion` kind chooser. Typing a keyword (`julia`/`json`/`xml`/`text`)
# into the chooser does **not** auto-switch — ENTER commits it via the factory.
# `ESC` reverts a structured insertion back to an empty text typein.
# The composer names no source domain. Which kinds it offers, what each is
# called, and how a typed source becomes a document are all asked of two seams:
# `get_insertion_root` says a type is a domain's insertion, and `get_natural_format`
# / `parse_natural_text` say that domain's key and how to read its text.


# ═══════════════════════════════════════════════════════════════════════
# Active-part / cursor helpers
# ═══════════════════════════════════════════════════════════════════════

# The active part is always the last one; its content is what the gestures act
# on. An empty draft has no active part (`nothing`).
_active_part(d::ConversationDraft) =
    isempty(d.parts) ? nothing : d.parts[length(d.parts)]
_active_content(d::ConversationDraft) =
    (p = _active_part(d); p === nothing ? nothing : p.content)

# The editing-state contents all carry an editable `value` you can type into: the
# plain text part, the kind chooser, and any domain's insertion. `get_insertion_root`
# is what makes the last of those a question rather than a list — it answers a
# domain root for an insertion type and `Document` for everything else.
_is_editable(c) = c isa PrimitiveString || c isa DocumentInsertion ||
                  get_insertion_root(typeof(c)) !== Document
_is_editable(::Nothing) = false

_value(c) = something(c.value, "")

# Build a `value{k}` zero-width cursor selection path.
_valpath(k::Int) = ConcreteReference(FieldReferenceStep("value"),
                       ConcreteReference(RangeReferenceStep(k, k), EmptyReference()))

# Read the cursor offset out of a content's selection, defaulting to end-of-value.
function _cursor(c)
    # Selections are canonical at rest: skip the TypeReferenceStep checkpoints before
    # reading the `value[range]` cursor structure.
    sel = getfield(c, :selection)[]
    if sel isa ConcreteReference && sel.head isa FieldReferenceStep && sel.head.name == "value"
        t = sel.tail
        if t isa ConcreteReference && t.head isa RangeReferenceStep
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
INSERT: commit the active text typein (→ `TextBlock`, dropped when blank) and
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
part to `TextBlock`, dropping a trailing blank typein.
"""
struct ComposerSubmitOperation <: Operation
    draft::ConversationDraft
end

# Every operation above names the DRAFT it acts on rather than a path into one,
# so there is nothing for a projection to re-root and nothing for one to place.
# They travel up the chain as they are — which is what lets a composer rendered
# inside a page reach the editor at all.
OperationModule.operation_travels_unchanged(::Union{
    ComposerInputOperation, ComposerBackspaceOperation, ComposerNewlineOperation,
    ComposerInsertPartOperation, ComposerCommitChooserOperation,
    ComposerCommitSourceOperation, ComposerEvaluateOperation,
    ComposerRevertOperation, ComposerSubmitOperation}) = true

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
            deleteat!(d.parts, length(d.parts))    # drop the blank typein
        else
            p.content = TextBlock(TextString(v))    # commit the prose
        end
    end
    ins = DocumentInsertion("")
    ins.selection = _valpath(0)
    push!(d.parts, ConversationPart(ins))
    nothing
end

# Kind keyword → the domain insertion the chooser grows into, resolved over the
# reflected candidates (exact name/alias or unambiguous prefix — `juli⏎` works),
# filtered to the kinds the composer can actually parse. Each is an editable
# insertion you then type a source into.
#
# The filter was a list of three. It is the question itself now: is this a
# domain's insertion, and can that domain read its own text? So the composer
# offers whatever domains a session loaded, and offering one it cannot commit is
# not expressible.
function _composer_kind(T)
    get_insertion_root(T) === Document && return false
    key = get_natural_format(T)
    key !== nothing && has_natural_parser(key)
end
function _composer_factory(name::AbstractString)
    T = resolve_insertion(Document, name)
    (T === nothing || !_composer_kind(T)) && return nothing
    make_insertion_document(T)
end

function evaluate_operation(editor, op::ComposerCommitChooserOperation)
    c = _active_content(op.draft)
    c isa DocumentInsertion || return nothing
    doc = _composer_factory(_value(c))
    doc === nothing && return nothing              # unknown/unsupported: keep editing
    _replace_active!(op.draft, doc)
end

# Parse a source insertion into its domain document, through the seam.
function _parse_source(c)
    get_insertion_root(typeof(c)) === Document && return nothing
    key = get_natural_format(typeof(c))
    key === nothing && return nothing
    _try_parse(text -> parse_natural_text(key, text), _value(c))
end
_parse_source(::Nothing) = nothing

function evaluate_operation(editor, op::ComposerCommitSourceOperation)
    doc = _parse_source(_active_content(op.draft))
    doc === nothing && return nothing              # unparseable: keep editing
    _replace_active!(op.draft, doc)
    push!(op.draft.parts, _new_typein())
    nothing
end

function evaluate_operation(editor, op::ComposerEvaluateOperation)
    c = _active_content(op.draft)
    # Running code is Julia's, so this one names a format rather than a domain:
    # it is the Julia kind that ALT+ENTER evaluates.
    get_natural_format(typeof(c)) === :jl || return nothing
    src = _value(c)
    isempty(strip(src)) && return nothing
    set = editor.tools
    output = try
        execute_julia_code(set, editor, src)
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    is_err = occursin("ERROR", output) || occursin("Error", output)
    # The executed source as a document, so it renders as Julia rather than as an
    # opaque leaf. A snippet that does not parse is kept as a string: it still
    # renders, and it still ran.
    form = something(_parse_source(c), PrimitiveString(src))
    # A Document return value (e.g. a live GraphicsCircle / SimulationTaskDocument)
    # is kept as the result so it renders live; otherwise the text repr.
    # `execute_julia_code` `println`s the result repr, so the captured output ends
    # in a newline — strip it so the result text doesn't render a trailing tofu box.
    val = get_last_evaluated_value(set)
    result = val isa Document ? val : make_evaluator_result_text(rstrip(output))
    _replace_active!(op.draft,
        EvaluatorForm(form; result = result, is_error = is_err))
    push!(op.draft.parts, _new_typein())
    nothing
end

function evaluate_operation(editor, op::ComposerRevertOperation)
    _replace_active!(op.draft, getfield(_new_typein(), :content)[])
end

"""
    finalize_draft!(draft) -> Bool

Normalize a draft for submission: drop a trailing blank text typein and convert
every remaining `PrimitiveString` part to committed `TextBlock` prose. Returns
whether the draft still has any parts (i.e. is worth submitting).
"""
function finalize_draft!(d::ConversationDraft)
    p = _active_part(d)
    if p !== nothing && p.content isa PrimitiveString && isempty(strip(_value(p.content)))
        deleteat!(d.parts, length(d.parts))
    end
    for i in eachindex(d.parts)
        part = d.parts[i]
        part.content isa PrimitiveString &&
            (part.content = TextBlock(TextString(_value(part.content))))
    end
    !isempty(d.parts)
end

evaluate_operation(editor, op::ComposerSubmitOperation) = (finalize_draft!(op.draft); nothing)

"""
    make_conversation_draft() -> ConversationDraft

A fresh empty user draft (one active text typein) for the composer.
"""
make_conversation_draft() = ConversationDraft([_new_typein()])

"""
    reset_draft!(draft)

Reset a draft **in place** to a single empty text typein — used after its content
has been submitted. Mutating in place (rather than replacing the draft) keeps a
cached projection of the draft valid and reactive.
"""
function reset_draft!(d::ConversationDraft)
    getfield(d.parts, :elements)[] = Cell[Cell(_new_typein())]
    # The caret goes with it. A draft that was just submitted is the one the
    # reader is about to write in, and a caret left on the parts that are gone
    # is a cell nothing can be typed into — which is what made a notebook take
    # exactly one cell and then go deaf.
    getfield(d, :selection)[] =
        ConcreteReference(FieldReferenceStep("parts"),
            ConcreteReference(RangeReferenceStep(0, 1),
                ConcreteReference(FieldReferenceStep("content"), _valpath(0))))
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

const _FONT        = font_ubuntu_monospace_regular_20
const _PLACEHOLDER = "type here…"

# A zero-width cursor at offset `k` inside span `span` (1-based) of a body
# `TextBlock`, in the `.elements[span].content[k:k]` shape `TextToGraphics` reads
# to draw its genuine thin-line caret.
_caret_selection(span::Int, k::Int) =
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(span - 1, span),
            ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(RangeReferenceStep(k, k), EmptyReference()))))

# Install the reactive caret on `body`, tracking `content`'s cursor in `span`.
# `span_len` is the rendered length of that span so the cursor stays in range.
function _attach_caret!(body::TextBlock, content, span::Int, span_len)
    set_cell_function!(getfield(body, :selection),
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
    # The value span carries the live commitability colour (green = names a
    # type, red = dead end, neutral while empty) and is followed by the pale
    # completion hint span — the same feedback the syntax-leaf insertion shows.
    # font_color is driven by `set_cell_function!` below, so it must be a reactive Cell,
    # not the immutable default — pass it explicitly. font stays immutable (authored).
    value_span = TextString(ComputedCell(() -> _value(c)), _FONT, Cell(color_default),
                            nothing, nothing, nothing)
    set_cell_function!(getfield(value_span, :font_color), function ()
        state = name_completion(c).state
        state === :invalid ? color_solarized_red :
        state === :empty   ? color_default      : color_solarized_green
    end)
    body = TextBlock([
        TextString(_INS_PREFIX, _FONT, color_solarized_gray),
        value_span,
        TextString(() -> name_completion(c).hint, _FONT, color_completion_hint),
        TextString(_INS_SUFFIX, _FONT, color_solarized_gray),
    ])
    # While the value is empty, anchor the caret to the end of the (non-empty)
    # prefix span — `TextToGraphics` can't place a caret in a zero-width span, and
    # this lands at the same x (just after "Insert a new ").
    set_cell_function!(getfield(body, :selection), function ()
        v = _value(c)
        isempty(v) ? _caret_selection(1, length(_INS_PREFIX)) :
                     _caret_selection(2, clamp(_cursor(c), 0, length(v)))
    end)
    body
end

# Plain editable text (a `PrimitiveString` or a domain's insertion): one span, a pale
# placeholder while empty, caret in the single span.
function _editable_body(c)
    show() = (v = _value(c); isempty(v) ? _PLACEHOLDER : v)
    # reactive font_color (set below); font stays immutable.
    ts = TextString(ComputedCell(show), _FONT, Cell(color_default), nothing, nothing, nothing)
    set_cell_function!(getfield(ts, :font_color),
           () -> isempty(_value(c)) ? color_solarized_gray : color_default)
    _attach_caret!(TextBlock(ts), c, 1, () -> length(show()))
end

# ── Committed part body — recurse the real content document through the inner
# dispatch, so committed code renders as a parsed Julia document, prose as text,
# and an evaluation as its form stacked over its result.
_committed_body(c::EvaluatorForm) = VerticalLayout(Any[c.form, c.result]; gap = _GAP)
_committed_body(c) = c

# The composer draws the chrome the transcript draws, for the same reason: the
# content says what it is, so a frame is for the kinds it cannot say. Code and an
# evaluation get a muted panel with a one-line tag; everything else — the active
# typein, a committed paragraph, the kind chooser that already writes "Insert a
# new … here" over itself — gets a `:plain` card, which draws nothing.
#
# It stays a card even when it draws nothing. The caret travels the path
# `children[i].content.…`, and `content` is the card's own slot; a part that was
# not a card would drop that step and the maps below would stop finding it.
_part_chrome(content) =
    content isa EvaluatorForm ? (:muted, get_evaluation_kind_label(content)) :
    _is_code(content)         ? (:muted, _kind_label(content))     :
    (:plain, nothing)

function _part_card(content, active::Bool)
    variant, tag = _part_chrome(content)
    WidgetCard(Point2D(0, 0);
               title = tag === nothing ? nothing :
                       WidgetLabel(Point2D(0, 0), tag; text_style = _KIND_STYLE),
               content = (active && _is_editable(content)) ?
                         _editable_body(content) : _committed_body(content),
               variant = variant)
end

function print_document(p::ConversationComposerToWidget, recursion, d::ConversationDraft, ctx)
    # The draft is always a user message, so it renders as just its stack of part
    # cards — no role/avatar header card around them. Reactive part list: the last
    # part is the active typein (gets the caret). The thunk recomputes on
    # structural changes; per-part value/cursor edits re-render via the reactive
    # `TextString` thunks inside each card.
    # Every part card fills the width it is given and grows with what it holds,
    # the same as a turn's parts in the transcript.
    body = VerticalLayout(
        ComputedCellVector(() -> (n = length(d.parts);
                          Any[_part_card(d.parts[i].content, i == n) for i in 1:n])),
        Cell(:left), Cell(_GAP), Cell(Fill), Cell(Content), Cell(nothing))
    iomap = SimpleIoMap(p, d, body)
    # The caret, carried down. A key is routed by selection and stops at the
    # first container that has none, so the stack of part cards has to say which
    # card the caret is in — otherwise a composer rendered anywhere but the
    # assistant panel can be clicked into and never typed in.
    set_cell_function!(getfield(body, :selection),
                       () -> map_reference_forward(p, iomap, getfield(d, :selection)[]))
    iomap
end

# ── the caret, both ways ────────────────────────────────────────────────────
#
# `parts[i].content.value{k}` on the draft is `children[i].content.elements[s].content{k}`
# on the stack of cards: card `i` holds part `i`, its `content` slot holds the
# body, and the body is a `TextBlock` whose span `s` carries the editable value.
# Which span that is belongs to the body that was built — a plain typein has one
# and a kind chooser has its value in the second, after the "Insert a new "
# prefix — so it is asked for rather than assumed.
#
# This is what makes a click land where it was aimed. Answering `nothing` both
# ways and managing the cursor privately works only where something else catches
# the keys: the assistant panel does, a page does not, and a composer in a page
# would be clicked into and not typed in.

# Which span of the rendered body carries the editable value.
_caret_span(c::DocumentInsertion) = isempty(_value(c)) ? 1 : 2
_caret_span(::Any) = 1

# parts[i].content.value{k}  →  children[i].content.elements[s].content{k}
function map_reference_forward(::ConversationComposerToWidget, iomap, reference)
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "parts") || return nothing
    t = reference.tail
    t isa ConcreteReference && t.head isa RangeReferenceStep || return nothing
    i = t.head.start + 1
    d = iomap.input
    (1 <= i <= length(d.parts)) || return nothing
    rest = t.tail
    rest isa ConcreteReference || return nothing
    (rest.head isa FieldReferenceStep && rest.head.name == "content") || return nothing
    content = d.parts[i].content
    inner = rest.tail
    # An editable part carries its value in a span of the body this projection
    # built; a committed one carries the document itself, and its own projection
    # owns everything below the card.
    tail = if _is_editable(content) && i == length(d.parts)
        (inner isa ConcreteReference && inner.head isa FieldReferenceStep &&
         inner.head.name == "value") || return nothing
        k = inner.tail
        (k isa ConcreteReference && k.head isa RangeReferenceStep) || return nothing
        _caret_selection(_caret_span(content), k.head.stop)
    else
        inner
    end
    ConcreteReference(FieldReferenceStep("children"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("content"), tail)))
end

# children[i].content.elements[s].content{k}  →  parts[i].content.value{k}
function map_reference_backward(::ConversationComposerToWidget, iomap, reference)
    reference isa ConcreteReference || return EmptyReference()
    h = reference.head
    (h isa FieldReferenceStep && h.name == "children") || return EmptyReference()
    t = reference.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep) || return EmptyReference()
    i = t.head.start + 1
    d = iomap.input
    (1 <= i <= length(d.parts)) || return EmptyReference()
    rest = t.tail
    (rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
     rest.head.name == "content") || return EmptyReference()
    content = d.parts[i].content
    tail = if _is_editable(content) && i == length(d.parts)
        k = _text_caret_offset(rest.tail)
        # A click that found no offset still found the card, and the caret goes
        # to the end of what is written — which is where a reader who clicked
        # anywhere in an empty field expects it.
        _valpath(k === nothing ? length(_value(content)) : k)
    else
        rest.tail
    end
    ConcreteReference(FieldReferenceStep("parts"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("content"), tail)))
end

# The `{k}` of an `elements[s].content{k}` caret path, or `nothing` when the
# reference is not one.
function _text_caret_offset(reference)
    reference isa ConcreteReference || return nothing
    (reference.head isa FieldReferenceStep && reference.head.name == "elements") || return nothing
    span = reference.tail
    (span isa ConcreteReference && span.head isa RangeReferenceStep) || return nothing
    inner = span.tail
    (inner isa ConcreteReference && inner.head isa FieldReferenceStep &&
     inner.head.name == "content") || return nothing
    k = inner.tail
    (k isa ConcreteReference && k.head isa RangeReferenceStep) || return nothing
    k.head.stop
end

# ═══════════════════════════════════════════════════════════════════════
# Reader: gesture → composer operation, dispatched on the active part's state
# ═══════════════════════════════════════════════════════════════════════

"""
    read_composer_gesture(draft, event) -> Operation | nothing

Map a key gesture to a composer operation on `draft`, dispatching on the active
(last) part's state. Shared by the composer projection and the live assistant
panel (which routes its input keys to the draft). `ENTER` on a plain text typein
yields a `ComposerSubmitOperation`; the panel intercepts that to submit the draft
into the conversation instead of merely normalizing it.
"""
# The composer's gesture table, reified as `GestureBinding`s and dispatched on the
# **active** (last) part's mode, so the very set that fires (`read_composer_gesture`, shared
# with the assistant panel) is the set the gesture-help window shows
# (`get_projection_gesture_bindings`) — fire == show. Char insert + Backspace are shared by every
# editable mode; the Return / Shift+Return / Alt+Return / Tab / Esc meaning is
# mode-specific. ModifierKeys are matched as the old `@event_case` did: `[:shift]`/`[:alt]`
# are exact, a bare key (`mods=nothing`) matches any modifiers, and the exact-modifier
# rows precede the bare one so Shift/Alt+Return win over plain Return (first match).
function _composer_bindings(draft::ConversationDraft)
    insert = GestureBinding(KeyPressPattern(nothing),
        (d, e) -> ComposerInputOperation(d, String(e.text)),
        (d, sel) -> true, "Insert character", "composer")
    backspace = GestureBinding(KeyDownPattern(:backspace, nothing, nothing),
        (d, e) -> ComposerBackspaceOperation(d),
        (d, sel) -> true, "Delete backward", "composer")
    newline = GestureBinding(KeyDownPattern(:return, [:shift], nothing),
        (d, e) -> ComposerNewlineOperation(d),
        (d, sel) -> true, "New line", "composer")
    revert = GestureBinding(KeyDownPattern(:escape, nothing, nothing),
        (d, e) -> ComposerRevertOperation(d),
        (d, sel) -> true, "Cancel", "composer")
    c = _active_content(draft)
    if c isa PrimitiveString
        GestureBinding[
            newline,
            GestureBinding(KeyDownPattern(:return, nothing, nothing),
                (d, e) -> ComposerSubmitOperation(d),
                (d, sel) -> true, "Submit", "composer"),
            GestureBinding(KeyDownPattern(:tab, nothing, nothing),
                (d, e) -> ComposerInsertPartOperation(d),
                (d, sel) -> true, "Add a structured part", "composer"),
            GestureBinding(KeyDownPattern(:insert, nothing, nothing),
                (d, e) -> ComposerInsertPartOperation(d),
                (d, sel) -> true, "Add a structured part", "composer"),
            backspace, insert,
        ]
    elseif c isa DocumentInsertion
        GestureBinding[
            GestureBinding(KeyDownPattern(:return, nothing, nothing),
                (d, e) -> ComposerCommitChooserOperation(d),
                (d, sel) -> true, "Choose insertion kind", "composer"),
            revert, backspace, insert,
        ]
    elseif get_natural_format(typeof(c)) === :jl
        # Julia source: ENTER commits it, and ALT+ENTER runs it. Running is
        # Julia's alone, which is why this arm names the format.
        GestureBinding[
            GestureBinding(KeyDownPattern(:return, [:alt], nothing),
                (d, e) -> ComposerEvaluateOperation(d),
                (d, sel) -> true, "Evaluate", "composer"),
            newline,
            GestureBinding(KeyDownPattern(:return, nothing, nothing),
                (d, e) -> ComposerCommitSourceOperation(d),
                (d, sel) -> true, "Commit source", "composer"),
            revert, backspace, insert,
        ]
    elseif get_insertion_root(typeof(c)) !== Document
        # Any other domain's source insertion: ENTER parses it into that domain's
        # document, and does nothing while it does not parse. Structural
        # key-driven insertion (`[` → JsonArray, …) is still future work.
        GestureBinding[
            newline,
            GestureBinding(KeyDownPattern(:return, nothing, nothing),
                (d, e) -> ComposerCommitSourceOperation(d),
                (d, sel) -> true, "Commit source", "composer"),
            revert, backspace, insert,
        ]
    else
        GestureBinding[]
    end
end

# Fire the first binding whose pattern matches (and precondition holds). Shared by the
# composer projection and the live assistant panel (both route input keys to the draft);
# a non-`ConversationDraft` first argument has no composer gestures. The draft carries
# no selection of its own, so the precondition gets `nothing` for one.
read_composer_gesture(draft::ConversationDraft, evt) =
    fire_gesture_bindings(_composer_bindings(draft), draft, nothing, evt)

read_composer_gesture(::Any, ::Any) = nothing

"""
    make_submit_operation(host) -> Operation or nothing

What ENTER means for a draft that belongs to `host`. Declared here and answered
by the host, because the composer loads first and cannot name the operation its
host would build. A host adds a method by qualification, which is
`PAR-QUALIFIED-EXTENSION`:

    ConversationModule.make_submit_operation(a::Assistant) =
        SubmitDraftTurnOperation(a)

The default answers `nothing`, which means this host owns no submit of its own
and the composer keeps the operation it already has.
"""
function make_submit_operation end
make_submit_operation(::Any) = nothing

"""
    make_evaluate_operation(host) -> Operation or nothing

The same for ALT+ENTER. A standalone draft keeps the evaluated form as a part of
itself, which is all a composer alone can do; a draft that belongs to an
assistant wants the form and its result to leave the composer and become a turn,
so that the next cell starts empty and the transcript holds the work.

That is a notebook, and it is what `SubmitJuliaOperation` already did on the
older string input. The composer cannot do it itself — a conversation is not its
to push to — so the host answers.

Each host answers for its own type, so two hosts can mean two different things
at once. A single mutable hook could not: it held one answer for the whole
process, and the last writer won.
"""
function make_evaluate_operation end
make_evaluate_operation(::Any) = nothing

# A press that reached this level found no text under it — a gap between the
# cards, the padding around one. The caret goes to the composer as a whole,
# which is a worse answer than an offset and a much better one than declining:
# a reader who clicks near the field still gets to type in it.
#
# A press that DID find text never arrives here. It is answered by the text
# layer under the card, and `map_reference_backward` turns that answer into the
# `parts[i].content.value{k}` the composer's own cursor reads.
function read_intent(::ConversationComposerToWidget, iomap::SimpleIoMap, ::MousePress)
    d = iomap.input
    n = length(d.parts)
    n == 0 && return ReplaceSelectionOperation(EmptyReference())
    c = _active_content(d)
    tail = _is_editable(c) ? _valpath(length(_value(c))) : EmptyReference()
    ReplaceSelectionOperation(
        ConcreteReference(FieldReferenceStep("parts"),
            ConcreteReference(RangeReferenceStep(n - 1, n),
                ConcreteReference(FieldReferenceStep("content"), tail))))
end

read_intent(::ConversationComposerToWidget, iomap::SimpleIoMap, evt::KeyPress) =
    read_composer_gesture(iomap.input, evt)

read_intent(::ConversationComposerToWidget, iomap::SimpleIoMap, evt::KeyDown) =
    (d = iomap.input; resolve_composer_host_operation(d.assistant, read_composer_gesture(d, evt)))

"""
    resolve_composer_host_operation(assistant, op) -> op

What an operation means once the draft it came from has an owner. With no owner
(`assistant === nothing`) every operation stays as the composer made it; with
one, two are handed over — ENTER's submit (push and stream) and ALT+ENTER's
evaluate (evaluate and push). Both are the same shape: the composer says what
happened, and the host says what it means.

The owner is passed rather than read off the draft, because the two are not
always the same thing. A draft rendered on its own carries the back-link; a
draft rendered as half of an assistant panel is reached through that panel,
which knows the assistant whether or not the back-link was set.

Public because a projection that renders a draft in its own surround reads the
keys itself, and has to arrive at the same answer this one does.
"""
function resolve_composer_host_operation(assistant, op)
    assistant === nothing && return op
    if op isa ComposerSubmitOperation
        made = make_submit_operation(assistant)
        made === nothing || return made
    elseif op isa ComposerEvaluateOperation
        made = make_evaluate_operation(assistant)
        made === nothing || return made
    end
    op
end

# The show side of the very table the reader fires (fire == show): the help window
# enumerates exactly the composer gestures available for the draft's current mode.
get_projection_gesture_bindings(::ConversationComposerToWidget, iomap) =
    iomap.input isa ConversationDraft ? _composer_bindings(iomap.input) : GestureBinding[]
