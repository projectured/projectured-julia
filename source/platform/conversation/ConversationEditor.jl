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
# | text typein   | `PrimitiveString`   | text keys edit; SHIFT+ENTER newline; TAB/INSERT→chooser; ENTER→submit |
# | kind chooser  | `DocumentInsertion` | text keys edit; ENTER commits keyword→insertion; ESC→typein |
# | julia source  | `JuliaInsertion`    | text keys edit; SHIFT+ENTER newline; ENTER→`JuliaDocument`; ALT+ENTER→`EvaluatorForm`; ESC→typein |
# | quoted code   | `JuliaDocument`     | (committed)                                      |
# | eval form     | `EvaluatorForm`     | (committed)                                      |
#
# After any structured commit (`JuliaDocument` / `EvaluatorForm`) the composer
# appends a fresh active text typein, so the draft always ends in a typein.
# `TAB` / `INSERT` commits the current text typein (dropping it when blank) and appends a
# `DocumentInsertion` kind chooser. Typing a keyword (`julia`/`json`/`xml`/`text`)
# into the chooser does **not** auto-switch — ENTER commits it via the factory.
# `ESC` reverts a structured insertion back to an empty text typein.
# The text keys — typing, Backspace, Delete, the arrows and their Shift twins —
# are the text domain's. The active part's body is a text layer, a key reaches it
# through the cards because each card follows the draft's selection, and its
# edits come back through the maps below as edits of the draft's value. The
# composer's own table holds only the keys that mean something to a composer.
#
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

# ── One selection ───────────────────────────────────────────────────────────
#
# A composer operation names its draft rather than a path, and it moves the
# caret in the active part's own cell. In an editor the complete selection has to
# move with it, because a key goes where the complete selection points.

"""
    sync_draft_selection!(editor, draft) -> Nothing

Put the editor's complete selection on the caret of `draft`'s active part, or on
the active part's content when it takes no text. The path to the draft is the
one the complete selection already passes through. When the complete selection
does not pass through `draft`, the draft keeps the caret as a dormant selection,
and the complete selection stays where it is. With no editor, nothing changes.

A composer operation calls it after it edits the draft, and so does a host that
replaces the draft's parts, such as the assistant after a submit.
"""
function sync_draft_selection!(editor, draft::ConversationDraft)
    tail = make_draft_caret_reference(draft)
    tail === nothing && return nothing
    _select_under!(editor, draft, tail) || _keep_dormant_caret!(editor, draft, tail)
    nothing
end

# Off the live path the draft keeps its caret dormant. The caret is written live
# from the root, and the live selection is written back at once. At that second
# write the kernel keeps the branch it leaves, because the draft keeps a dormant
# selection, so the draft and every keeper above it name the new caret. An editor
# with no live selection, or a draft that its document does not hold, keeps what
# it has.
function _keep_dormant_caret!(editor, draft, tail)
    root = (editor !== nothing && hasproperty(editor, :document)) ? editor.document : nothing
    root === nothing && return nothing
    live = get_selection(root)
    live isa Reference || return nothing
    live = copy_reference(live)
    found = search_references(root, node -> node === draft; descend = _is_draft_search_step)
    isempty(found) && return nothing
    replace_selection!(root, concat_references(first(found), tail))
    replace_selection!(root, live)
    nothing
end

# A search for a draft enters documents and collections only, so it does not find
# the draft through an operation that a history records.
_is_draft_search_step(parent, child) = child isa Document || is_element_collection(child)

# Put the editor's complete selection on `tail` inside `node`: the steps of the
# complete selection that lead to `node`, then `tail`. The old selection is
# cleared first, so no node on its path still shows it. Answers whether the
# selection moved, which it does not with no editor, or with a complete selection
# that does not pass through `node`.
function _select_under!(editor, node, tail)
    root = (editor !== nothing && hasproperty(editor, :document)) ? editor.document : nothing
    root === nothing && return false
    path = root.selection
    path isa Reference || return false
    prefix = _find_selection_prefix(root, path, node)
    prefix === nothing && return false
    clear_selection!(root)
    set_selection!(root, _from_steps(prefix, tail))
    true
end

"""
    make_draft_caret_reference(draft) -> Reference or nothing

The selection of `draft`'s active part, rooted at the draft: the caret of its
value, `parts[n].content.value{k}`, or `parts[n].content` when the part takes no
text. `nothing` for a draft with no part.
"""
function make_draft_caret_reference(draft::ConversationDraft)
    n = length(draft.parts)
    n == 0 && return nothing
    content = _active_content(draft)
    ConcreteReference(FieldReferenceStep("parts"),
        ConcreteReference(RangeReferenceStep(n - 1, n),
            ConcreteReference(FieldReferenceStep("content"),
                _is_editable(content) ? _valpath(_cursor(content)) : EmptyReference())))
end

# The steps of `path` that lead from `root` to `target`, or `nothing` when the
# path does not pass through it.
function _find_selection_prefix(root, path, target)
    steps = get_reference_steps(strip_reference_types(path))
    root === target && return Any[]
    for k in 1:length(steps)
        node = try_evaluate_reference(root, _from_steps(steps[1:k]), nothing)
        node === target && return steps[1:k]
    end
    nothing
end

# The value range that the draft's own selection names on its active part, or
# `nothing`.
function _find_draft_value_range(d::ConversationDraft)
    path = get_stored_selection(d)
    path isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    n = length(d.parts)
    (length(steps) == 5 && steps[1] == FieldReferenceStep("parts") &&
     steps[2] == RangeReferenceStep(n - 1, n) && steps[3] == FieldReferenceStep("content") &&
     steps[4] == FieldReferenceStep("value") && steps[5] isa RangeReferenceStep) || return nothing
    (steps[5].start, steps[5].stop)
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
OperationModule.is_self_contained_operation(::Union{
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
    sync_draft_selection!(editor, op.draft)
end

function evaluate_operation(editor, op::ComposerNewlineOperation)
    c = _active_content(op.draft)
    _is_editable(c) || return nothing
    v = _value(c); k = clamp(_cursor(c), 0, length(v))
    _set_value!(c, first(v, k) * "\n" * last(v, length(v) - k), k + 1)
    sync_draft_selection!(editor, op.draft)
end

function evaluate_operation(editor, op::ComposerBackspaceOperation)
    c = _active_content(op.draft)
    _is_editable(c) || return nothing
    v = _value(c); k = clamp(_cursor(c), 0, length(v))
    k == 0 && return nothing
    _set_value!(c, first(v, k - 1) * last(v, length(v) - k), k - 1)
    sync_draft_selection!(editor, op.draft)
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
    sync_draft_selection!(editor, d)
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
    sync_draft_selection!(editor, op.draft)
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
    sync_draft_selection!(editor, op.draft)
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
        execute_julia_code!(set, editor, src; describe_value = describe_value_for_person)
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
    # `execute_julia_code!` `println`s the result repr, so the captured output ends
    # in a newline — strip it so the result text doesn't render a trailing tofu box.
    val = get_last_evaluated_value(set)
    result = val isa Document ? val : make_evaluator_result_text(rstrip(output))
    _replace_active!(op.draft,
        EvaluatorForm(form; result = result, is_error = is_err))
    push!(op.draft.parts, _new_typein())
    sync_draft_selection!(editor, op.draft)
end

function evaluate_operation(editor, op::ComposerRevertOperation)
    _replace_active!(op.draft, getfield(_new_typein(), :content)[])
    sync_draft_selection!(editor, op.draft)
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
            (part.content = _prose_document(_value(part.content)))
    end
    !isempty(d.parts)
end

# A committed paragraph is a markdown document when a markdown parser is loaded,
# so a typed message draws in the font and with the wrapping of a reply. With no
# parser it stays a text block, which is what an environment without the markdown
# package can draw. The model receives the source either way.
function _prose_document(text::AbstractString)
    has_natural_parser(:md) || return TextBlock(TextString(String(text)))
    try
        parse_natural_text(:md, String(text))
    catch
        TextBlock(TextString(String(text)))
    end
end

function evaluate_operation(editor, op::ComposerSubmitOperation)
    finalize_draft!(op.draft)
    sync_draft_selection!(editor, op.draft)
end

"""
    make_conversation_draft() -> ConversationDraft

A fresh empty user draft (one active text typein) for the composer.
"""
make_conversation_draft() = ConversationDraft([_new_typein()])

"""
    reset_draft!(draft)

Reset a draft **in place** to a single empty text typein — used after its content
has been submitted. Mutating in place (rather than replacing the draft) keeps a
cached projection of the draft valid and reactive. The parts it takes out hold no
selection afterwards, because they go to the transcript.
"""
function reset_draft!(d::ConversationDraft)
    # The parts leave the draft for the transcript, where no caret belongs.
    foreach(clear_selection!, collect(d.parts))
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
@projection UntrackedCell struct ConversationComposerToWidget
    part_gap::Int = get_conversation_style(nothing, :part_gap)
    code_font::StyleFont = get_conversation_style(nothing, :code_font)
    kind_text::StyleText = get_conversation_style(nothing, :kind_text)
    section_text::StyleText = get_conversation_style(nothing, :section_text)
    error_text::StyleText = get_conversation_style(nothing, :error_text)
    section_gap::Int = get_conversation_style(nothing, :section_gap)
    section_padding::Inset = get_conversation_style(nothing, :section_indent)
    plain_color::StyleColor = get_conversation_style(nothing, :plain_color)
    placeholder_color::StyleColor = get_conversation_style(nothing, :placeholder_color)
    valid_color::StyleColor = get_conversation_style(nothing, :valid_color)
    invalid_color::StyleColor = get_conversation_style(nothing, :invalid_color)
    completion_hint_color::StyleColor = get_conversation_style(nothing, :completion_hint_color)
end

"""
    make_conversation_composer_projection(; theme = nothing) -> ConversationComposerToWidget

The composer, with the font, the gaps and the colors of `theme`: a
`ConversationTheme`, scaled or not, or the default values for `nothing`.
"""
function make_conversation_composer_projection(; theme = nothing)
    get_style(name) = get_conversation_style(theme, name)
    ConversationComposerToWidget(; part_gap = get_style(:part_gap), code_font = get_style(:code_font),
                                 kind_text = get_style(:kind_text), section_text = get_style(:section_text),
                                 error_text = get_style(:error_text), section_gap = get_style(:section_gap),
                                 section_padding = get_style(:section_indent),
                                 plain_color = get_style(:plain_color),
                                 placeholder_color = get_style(:placeholder_color),
                                 valid_color = get_style(:valid_color),
                                 invalid_color = get_style(:invalid_color),
                                 completion_hint_color = get_style(:completion_hint_color))
end

const _PLACEHOLDER = "type here…"

# A range at offsets `s..e` inside span `span` (1-based) of a body `TextBlock`, in
# the `.elements[span].content{s:e}` shape `TextToGraphics` reads. `s == e` is its
# thin-line caret.
_body_range_selection(span::Int, s::Int, e::Int) =
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(span - 1, span),
            ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(RangeReferenceStep(s, e), EmptyReference()))))

# ── Editable (active) part body — its value, drawn with the draft's selection.

# A `DocumentInsertion` keeps its "Insert a new <value> here" decoration: static
# gray prefix/suffix spans around the editable value span, caret in the value.
const _INS_PREFIX = "Insert a new "
const _INS_SUFFIX = " here"

# Which span of the rendered body carries the editable value.
_value_span(::DocumentInsertion) = 2
_value_span(::Any) = 1

function _editable_body(p, c::DocumentInsertion)
    # The value span carries the live commitability colour (green = names a
    # type, red = dead end, neutral while empty) and is followed by the pale
    # completion hint span — the same feedback the syntax-leaf insertion shows.
    # font_color is driven by `set_cell_computation!` below, so it must be a reactive
    # Cell, not the immutable default — pass it explicitly. font stays immutable
    # (authored).
    value_span = TextString(Cell(@computation _value(c)), p.code_font, Cell(p.plain_color),
                            nothing, nothing, nothing, nothing)
    set_cell_computation!(getfield(value_span, :font_color), function ()
        state = name_completion(c).state
        state === :invalid ? p.invalid_color :
        state === :empty   ? p.plain_color  : p.valid_color
    end)
    TextBlock([
        TextString(_INS_PREFIX, p.code_font, p.placeholder_color),
        value_span,
        TextString(() -> name_completion(c).hint, p.code_font, p.completion_hint_color),
        TextString(_INS_SUFFIX, p.code_font, p.placeholder_color),
    ])
end

# Plain editable text (a `PrimitiveString` or a domain's insertion): one span, and
# a pale placeholder while empty.
function _editable_body(p, c)
    show() = (v = _value(c); isempty(v) ? _PLACEHOLDER : v)
    # reactive font_color (set below); font stays immutable.
    ts = TextString(Cell(Computation(show)), p.code_font, Cell(p.plain_color), nothing, nothing, nothing, nothing)
    set_cell_computation!(getfield(ts, :font_color),
           () -> isempty(_value(c)) ? p.placeholder_color : p.plain_color)
    TextBlock(ts)
end

# The body's selection for the value range `s..e` of the active part `c`. While a
# kind chooser's value is empty, the caret sits at the end of the prefix span:
# `TextToGraphics` can not place a caret in a zero-width span, and this lands at
# the same x, just after "Insert a new ".
function _body_selection(c, s::Int, e::Int)
    (c isa DocumentInsertion && isempty(_value(c))) &&
        return _body_range_selection(1, length(_INS_PREFIX), length(_INS_PREFIX))
    n = length(_value(c))
    _body_range_selection(_value_span(c), clamp(s, 0, n), clamp(e, 0, n))
end

# A widget that follows the draft's paths (the selection, the mouse target). Each
# path cell holds the draft's path mapped forward, less the `lead` steps that lead
# to the widget, and nothing when the image does not pass through it. `dormant`
# keeps a dormant selection, which a text layer draws pale; a card routes keys by
# its selection, so it follows only a live one.
function _follow_draft!(widget, d::ConversationDraft, p, iomap_ref::Ref, lead::Vector;
                        dormant::Bool)
    function image_of(path)
        image = map_reference_forward(p, iomap_ref[], path)
        image isa Reference || return nothing
        steps = get_reference_steps(strip_reference_types(image))
        length(steps) >= length(lead) || return nothing
        all(k -> steps[k] == lead[k], eachindex(lead)) || return nothing
        _from_steps(steps[(length(lead) + 1):end])
    end
    set_output_path_computations!(widget, d, image_of; dormant)
    widget
end

# ── Committed part body — recurse the real content document through the inner
# dispatch, so committed code renders as a parsed Julia document, prose as text,
# and an evaluation as its form stacked over its result.
_committed_body(p, c::EvaluatorForm) = _eval_sections(p, c, nothing)
_committed_body(p, c) = c

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

function _make_draft_part_card(p, d::ConversationDraft, iomap_ref::Ref, i::Int, content, active::Bool)
    variant, tag = _part_chrome(content)
    editable = active && _is_editable(content)
    lead = Any[FieldReferenceStep("children"), RangeReferenceStep(i - 1, i)]
    body = editable ?
        _follow_draft!(_editable_body(p, content), d, p, iomap_ref,
                       vcat(lead, FieldReferenceStep("content")); dormant = true) :
        _committed_body(p, content)
    card = WidgetCard(;
                      title = tag === nothing ? nothing :
                              WidgetLabel(tag; text_style = p.kind_text),
                      content = body,
                      variant = variant)
    # A card passes a key to its content only while it holds a selection.
    editable ? _follow_draft!(card, d, p, iomap_ref, lead; dormant = false) : card
end

function print_document(p::ConversationComposerToWidget, recursion, d::ConversationDraft, ctx)
    # The draft is always a user message, so it renders as just its stack of part
    # cards — no role/avatar header card around them. Reactive part list: the last
    # part is the active typein. The thunk recomputes on structural changes;
    # per-part value edits re-render via the reactive `TextString` thunks inside
    # each card, and the caret via the selection cells that follow the draft.
    # Every part card fills the width it is given and grows with what it holds,
    # the same as a turn's parts in the transcript.
    iomap_ref = Ref{Any}(nothing)
    body = VerticalLayout(
        CellVector(@computation((n = length(d.parts);
                          Any[_make_draft_part_card(p, d, iomap_ref, i, d.parts[i].content, i == n) for i in 1:n]))),
        Cell(:left), Cell(p.part_gap), Cell(Fill), Cell(Content), Cell(nothing))
    iomap = SimpleIoMap(p, d, body)
    iomap_ref[] = iomap
    # The paths, carried down. A key is routed by selection and stops at the first
    # container that has none, so the stack of part cards, the active card and its
    # body each say where the draft's selection is; the body follows only a live
    # one.
    set_output_path_computations!(body, d, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    iomap
end

# ── the selection, both ways ────────────────────────────────────────────────
#
# `parts[i].content.value{s:e}` on the draft is
# `children[i].content.elements[k].content{s:e}` on the stack of cards: card `i`
# holds part `i`, its `content` slot holds the body, and span `k` of the body
# carries the editable value. A place in the body comes back as a flat range,
# which a click and a motion key make, or as the span range an edit is lowered to.
# A caret in the chooser's prefix is the start of the value, and a caret after the
# value is its end. A range with an end outside the value maps to nothing, so a
# key that would make one declines.
#
# This is what makes a click land where it was aimed, and a key act where the
# selection is.

# parts[i].content.value{s:e}  →  children[i].content.elements[k].content{s:e}
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
        _body_selection(content, k.head.start, k.head.stop)
    else
        inner
    end
    ConcreteReference(FieldReferenceStep("children"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("content"), tail)))
end

# children[i].content.<a place in the body>  →  parts[i].content.value{s:e}
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
        body = _get_rendered_body(iomap, i)
        range = body === nothing ? :other : _map_body_to_value(content, body, rest.tail)
        range === nothing && return nothing
        # A click that found no offset still found the card, and the caret goes
        # to the end of what is written — which is where a reader who clicked
        # anywhere in an empty field expects it.
        n = length(_value(content))
        range === :other && (range = (n, n))
        ConcreteReference(FieldReferenceStep("value"),
            ConcreteReference(RangeReferenceStep(range[1], range[2]), EmptyReference()))
    else
        rest.tail
    end
    ConcreteReference(FieldReferenceStep("parts"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("content"), tail)))
end

# The body the stack of cards holds for part `i`, or `nothing`.
function _get_rendered_body(iomap, i::Int)
    children = iomap.output.children
    (1 <= i <= length(children)) || return nothing
    card = children[i]
    card isa WidgetCard || return nothing
    body = card.content
    body isa TextBlock ? body : nothing
end

# The value range of the active part `c` that a place in its `body` names:
# `(start, stop)`, `nothing` for a range that leaves the value, or `:other` for a
# reference that names no place in the text.
function _map_body_to_value(c, body::TextBlock, reference)
    r = strip_reference_types(reference)
    span = _value_span(c)
    n = length(_value(c))
    if r isa ConcreteReference && r.head isa TextRangeReferenceStep && r.tail isa EmptyReference
        base = get_flat_base(body, Int[span])
        base === nothing && return :other
        shown = length(body.elements[span].content::AbstractString)
        inside(f) = base <= f <= base + shown
        place(f) = f < base ? 0 : f > base + shown ? n : clamp(f - base, 0, n)
        s, e = r.head.start, r.head.stop
        s == e && return (place(s), place(s))
        (inside(s) && inside(e)) || return nothing
        return (clamp(s - base, 0, n), clamp(e - base, 0, n))
    end
    parsed = _parse_body_span_range(r)
    parsed === nothing && return :other
    k, a, b = parsed
    k == span && return (clamp(a, 0, n), clamp(b, 0, n))
    a == b || return nothing
    k < span ? (0, 0) : (n, n)
end

# The `(k, s, e)` of an `elements[k].content{s:e}` path, or `nothing` when the
# reference is not one.
function _parse_body_span_range(reference)
    reference isa ConcreteReference || return nothing
    (reference.head isa FieldReferenceStep && reference.head.name == "elements") || return nothing
    span = reference.tail
    (span isa ConcreteReference && span.head isa RangeReferenceStep) || return nothing
    inner = span.tail
    (inner isa ConcreteReference && inner.head isa FieldReferenceStep &&
     inner.head.name == "content") || return nothing
    range = inner.tail
    (range isa ConcreteReference && range.head isa RangeReferenceStep &&
     range.tail isa EmptyReference) || return nothing
    (span.head.stop, range.head.start, range.head.stop)
end

# ═══════════════════════════════════════════════════════════════════════
# Reader: gesture → composer operation, dispatched on the active part's state
# ═══════════════════════════════════════════════════════════════════════

# The composer's gesture table, reified as `GestureBinding`s and dispatched on the
# **active** (last) part's mode, so the very set that fires (`read_composer_gesture`, shared
# with the assistant card) is the set the gesture-help window shows
# (`get_projection_gesture_bindings`) — fire == show. The text keys are the text
# layer's; the Return / Shift+Return / Alt+Return / Tab / Esc meaning is
# mode-specific. ModifierKeys are matched as the old `@gesture_case` did: `[:shift]`/`[:alt]`
# are exact, a bare key (`mods=nothing`) matches any modifiers, and the exact-modifier
# rows precede the bare one so Shift/Alt+Return win over plain Return (first match).
function _composer_bindings(draft::ConversationDraft)
    newline = GestureBinding(KeyDownPattern(:return; modifiers = [:shift]),
                             (d, e) -> _make_newline_operation(d);
                             description = "New line", domain = "composer")
    revert = GestureBinding(KeyDownPattern(:escape),
                            (d, e) -> ComposerRevertOperation(d); description = "Cancel",
                            domain = "composer")
    c = _active_content(draft)
    if c isa PrimitiveString
        GestureBinding[
            newline,
            GestureBinding(KeyDownPattern(:return),
                           (d, e) -> ComposerSubmitOperation(d); description = "Submit",
                           domain = "composer"),
            GestureBinding(KeyDownPattern(:tab),
                           (d, e) -> ComposerInsertPartOperation(d);
                           description = "Add a structured part", domain = "composer"),
            GestureBinding(KeyDownPattern(:insert),
                           (d, e) -> ComposerInsertPartOperation(d);
                           description = "Add a structured part", domain = "composer"),
        ]
    elseif c isa DocumentInsertion
        GestureBinding[
            GestureBinding(KeyDownPattern(:return),
                           (d, e) -> ComposerCommitChooserOperation(d);
                           description = "Choose insertion kind", domain = "composer"),
            revert,
        ]
    elseif get_natural_format(typeof(c)) === :jl
        # Julia source: ENTER commits it, and ALT+ENTER runs it. Running is
        # Julia's alone, which is why this arm names the format.
        GestureBinding[
            GestureBinding(KeyDownPattern(:return; modifiers = [:alt]),
                           (d, e) -> ComposerEvaluateOperation(d);
                           description = "Evaluate", domain = "composer"),
            newline,
            GestureBinding(KeyDownPattern(:return),
                           (d, e) -> ComposerCommitSourceOperation(d);
                           description = "Commit source", domain = "composer"),
            revert,
        ]
    elseif get_insertion_root(typeof(c)) !== Document
        # Any other domain's source insertion: ENTER parses it into that domain's
        # document, and does nothing while it does not parse. Structural
        # key-driven insertion (`[` → JsonArray, …) is still future work.
        GestureBinding[
            newline,
            GestureBinding(KeyDownPattern(:return),
                           (d, e) -> ComposerCommitSourceOperation(d);
                           description = "Commit source", domain = "composer"),
            revert,
        ]
    else
        GestureBinding[]
    end
end

# SHIFT+ENTER: a line break over the draft's selected range, as an edit of the
# complete selection. The draft's own selection names the range; a draft that
# names none takes the caret of its active part.
function _make_newline_operation(d::ConversationDraft)
    c = _active_content(d)
    _is_editable(c) || return nothing
    range = _find_draft_value_range(d)
    s, e = range === nothing ? (_cursor(c), _cursor(c)) : range
    n = length(d.parts)
    ReplaceStringRangeOperation(
        ConcreteReference(FieldReferenceStep("parts"),
            ConcreteReference(RangeReferenceStep(n - 1, n),
                ConcreteReference(FieldReferenceStep("content"),
                    ConcreteReference(FieldReferenceStep("value"),
                        ConcreteReference(RangeReferenceStep(s, e), EmptyReference()))))),
        "\n")
end

# Fire the first binding whose pattern matches (and precondition holds). Shared by the
# composer projection and the live assistant panel (both route input keys to the draft);
# a non-`ConversationDraft` first argument has no composer gestures. The draft carries
# no selection of its own, so the precondition gets `nothing` for one.
"""
    read_composer_gesture(draft, event) -> Operation | nothing

Map a key gesture to a composer operation on `draft`, dispatching on the active
(last) part's state. Shared by the composer projection and the assistant card.
`ENTER` on a plain text typein yields a `ComposerSubmitOperation`; the assistant
intercepts that to submit the draft into the conversation instead of merely
normalizing it. The text keys are not here: the text layer of the active part
answers them.
"""
read_composer_gesture(draft::ConversationDraft, evt) =
    fire_gesture_bindings(_composer_bindings(draft), draft, evt; selection = nothing)

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

# A left press that reached this level found no text under it — a gap between the
# cards, the padding around one. The caret goes to the composer as a whole,
# which is a worse answer than an offset and a much better one than declining:
# a reader who clicks near the field still gets to type in it.
#
# A press that DID find text never arrives here. It is answered by the text
# layer under the card, and `map_reference_backward` turns that answer into the
# `parts[i].content.value{k}` the composer's own cursor reads.
function read_intent(::ConversationComposerToWidget, iomap::SimpleIoMap,
                     click::MouseClick)
    click.button === :left || return nothing
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
