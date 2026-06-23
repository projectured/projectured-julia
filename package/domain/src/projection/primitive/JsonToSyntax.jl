"""
    JsonToSyntaxModule

JSON → SyntaxDocument projection. Maps each JSON value type to a matching
syntax tree shape, preserving delimiter characters (quotes, braces, brackets)
as projection-introduced elements via ProjectionReference. The reader inverts
the mapping, routing tree-domain paths back to the correct JSON field, array
index, or ProjectionReference for delimiters.

Every value type is expressed as a `@projection_template` builder: an ordinary
`(p, doc) -> output` that constructs the real SyntaxLeaf/SyntaxNode, dropping a
`bound`/`project`/`collection` marker where special handling is needed. The
ProjectionTemplate engine walks the built tree, strips the markers, and derives
`projection_print` / `map_reference_forward` / `map_reference_backward` / the
value-edit reader. Only the JSON *authoring* readers (type-to-replace, `,`
insert, Tab) and the Syntax-specific structural fallback stay hand-written.
"""
module JsonToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference, evaluate_reference, skip_type_checkpoints
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection, RuleIoMap
import ..PrinterContextModule: PrinterContext, child_context
import ..OperationModule: ReplaceSelectionOperation, ReplaceDocumentOperation, CollectionInsertOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..KeyboardModule: KeyPress, KeyDown
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

struct JsonNullToSyntaxLeaf <: Projection
    style::StyleText
end
JsonNullToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)) = JsonNullToSyntaxLeaf(style)

# "null" is a projection-introduced label with no editable input value (no
# marker ⇒ opaque): the walk records no binding, so the default proj-unwrapping
# mappers apply and the output selection is the input selection mapped forward.
@projection_template JsonNullToSyntaxLeaf JsonNull (p, doc) ->
    SyntaxLeaf(TextString("null", p.style))

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonInsertionToSyntaxLeaf <: Projection
    style::StyleText
end
JsonInsertionToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) = JsonInsertionToSyntaxLeaf(style)

# Same rationale as JsonNull — "insert JSON here" is an opaque
# projection-introduced placeholder with no editable input value.
@projection_template JsonInsertionToSyntaxLeaf JsonInsertion (p, doc) ->
    SyntaxLeaf(TextString("insert JSON here", p.style))

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

struct JsonBoolToSyntaxLeaf <: Projection
    style::StyleText
end
JsonBoolToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)) = JsonBoolToSyntaxLeaf(style)

# Transparent value bound to JsonBool.value (Bool): the walk shares doc's
# selection cell with the leaf, so .value{k} identity-maps both ways. The `bound`
# marker in the value slot is stripped to its real TextString before the output
# leaves the printer.
@projection_template JsonBoolToSyntaxLeaf JsonBool (p, doc) ->
    SyntaxLeaf(bound(:value, Bool, TextString(() -> doc[] ? "true" : "false", p.style)))

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonNumberToSyntaxLeaf <: Projection
    style::StyleText
end
JsonNumberToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)) = JsonNumberToSyntaxLeaf(style)

# Transparent value bound to JsonNumber.value (Real). Editing the value rewires
# the StringReplaceRangeOperation into a NumberReplaceRangeOperation (the
# `retype` marker arg) so the evaluator's tryparse logic kicks in.
@projection_template JsonNumberToSyntaxLeaf JsonNumber (p, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     _hinted_text(() -> string(doc[]), () -> doc[] === nothing, "enter json number", p.style);
                     retype = NumberReplaceRangeOperation))

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonStringToSyntaxLeaf <: Projection
    quote_style::StyleText
    value::StyleText
end
JsonStringToSyntaxLeaf(; quote_style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow),
                         value=StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)) =
    JsonStringToSyntaxLeaf(quote_style, value)

# Transparent value bound to JsonString.value (String, identity lens — escaping
# deferred). The `"` delimiters are non-empty introduced text, so the walk records
# them as selectable delimiters: a cursor on them has no JSON pre-image, so the
# backward mapper wraps an .open/.close reference into this projection's own
# ProjectionReference (and forward unwraps it, so a quote selection round-trips
# under School-A delegation). The value-edit reader falls to the default.
@projection_template JsonStringToSyntaxLeaf JsonString (p, doc) ->
    SyntaxLeaf(bound(:value, String,
                     _hinted_text(() -> json_escape(doc[]), () -> isempty(doc[]), "enter json string", p.value));
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

struct JsonArrayToSyntaxNode <: Projection
    delim::StyleText
    sep::StyleText
end
JsonArrayToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray),
                        sep=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JsonArrayToSyntaxNode(delim, sep)

# Builder/walk node: the `collection(:elements)` marker in the children slot tells
# the engine to recurse over doc.elements (School A) and build the projected
# children. The walk records (.elements[i] ↔ .children[i]); the generic node
# mappers delegate each element's tail through the stored child iomap. Structural
# positions ([, ], ,) are projection-introduced: the reader fallback below maps
# them to the flat character offset the text layer can navigate.
@projection_template JsonArrayToSyntaxNode JsonArray (p, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delim),
               close=TextString("]", p.delim),
               sep=TextString(", ", p.sep),
               indentation=1)

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

struct JsonObjectToSyntaxNode <: Projection
    delim::StyleText
    sep::StyleText
    key::StyleText
    colon::StyleText
end
JsonObjectToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray),
                         sep=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray),
                         key=StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue),
                         colon=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JsonObjectToSyntaxNode(delim, sep, key, colon)

# Builder/walk node with a templated collection. `collection(:entries) do e … end`
# builds a per-entry pair node `[key_leaf, value]`:
#   - the key leaf carries `bound(:key, String, …)` → the walk records a KeySlot, so
#     `.entries[i].key{k}` ↔ `.children[i].children[1].value{k}` and the whole key ↔
#     the whole key leaf;
#   - `project(:value)` delegates the value subtree to its own projection (School A),
#     so `.entries[i].value.<tail>` ↔ `.children[i].children[2].<tail>`.
# Selection is wired by the engine: the pair node uses the entry's selection cell
# so set_selection! propagates into it, and `_fixed_print` auto-lenses the key
# cursor `.key{k}` → the key leaf's `.value{k}` (KeySlot cursor wiring). Structural
# positions ({, }, :, separators) are projection-introduced and map to a flat offset
# via the reader fallback below.
@projection_template JsonObjectToSyntaxNode JsonObject (p, doc) ->
    SyntaxNode(collection(:entries) do e
                   # The pair node is a *fixed-children template node*: the engine's
                   # `_fixed_print` locates its children with `isa Vector` and walks them
                   # to find the `project(:value)` marker, so the children must stay a raw
                   # Vector. The keyword `children` path normalizes to a CellVector, which
                   # the walk would not recognise — hence the positional form is kept here.
                   SyntaxNode(TextString("", p.delim.font, color_default),
                              TextString("", p.delim.font, color_default),
                              TextString(": ", p.colon),
                              [ SyntaxLeaf(bound(:key, String, _hinted_text(() -> json_escape(e.key), () -> isempty(e.key), "enter key", p.key));
                                           open=TextString("\"", p.key),
                                           close=TextString("\"", p.key)),
                                project(:value) ],
                              0, false, getfield(e, :selection))
               end;
               open=TextString("{", p.delim),
               close=TextString("}", p.delim),
               sep=TextString(", ", p.sep),
               indentation=1)

# ── Reader: the JSON authoring command set ──────────────────────────────────
#
# These mirror the Lisp `json/read-command` and the array/object/object-entry
# readers (json-to-syntax.lisp:424-628). They run only when a *raw* key gesture
# reaches the JSON layer — i.e. the cursor is on a whole JSON value (structural
# mode), not a character cursor inside a string/number. A character cursor is
# consumed downstream by TextToGraphics (which emits a StringReplaceRangeOperation
# the typein path threads back up), so the gating Lisp does with
# `(not (typep printer-input 'json/number))` falls out for free; we still guard
# the digit case explicitly to match.
#
# Only the *root* JSON projection's reader runs for a gesture (TypeDispatching
# dispatches on the root document's type), so each method reads its own
# `iomap.input.selection` — a full path from the root — and emits an operation
# whose path is relative to the root. This is why every JSON projection carries
# the type-to-replace command: any of them can be the whole document.

# Set a fresh replacement document's initial (self-relative) selection so the
# evaluator can drop the cursor inside it after the swap.
_sel!(doc, path) = (getfield(doc, :selection)[] = path; doc)

# A character cursor is a path ending in `…<value|key>{k}` — a RangeReference
# step preceded by the value/key field. A whole-element selection ends in ∅.
function _is_char_cursor(sel)
    prev = nothing
    cur = sel
    while cur isa ConcreteReferencePath
        if cur.tail isa EmptyReferencePath
            return cur.head isa RangeReference && prev isa FieldReference &&
                   (prev.name == "value" || prev.name == "key")
        end
        prev = cur.head
        cur = cur.tail
    end
    return false
end

# The `json/read-command` table: a printable key on a whole-element selection
# replaces the selected value with a freshly-built one whose cursor is pre-placed
# for continued authoring.
function _json_read_command(input, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    sel = getfield(input, :selection)[]
    sel === nothing && return nothing
    _is_char_cursor(sel) && return nothing
    target = try evaluate_reference(input, sel) catch; nothing end
    target === nothing && return nothing
    # A JsonObjectEntry is a key/value *wrapper*, not a replaceable JSON value —
    # swapping it for a scalar would corrupt the enclosing object (its printer
    # reads `entry.key`). The replaceable targets are values, array elements, and
    # the root. (Selection-state gating, plan §2.)
    target isa JsonObjectEntry && return nothing
    ch = evt.char
    newdoc = if ch == 'n'
        _sel!(JsonNull(), EmptyReferencePath())
    elseif ch == 'f'
        _sel!(JsonBool(false), EmptyReferencePath())
    elseif ch == 't'
        _sel!(JsonBool(true), EmptyReferencePath())
    elseif ch == '"'
        _sel!(JsonString(""), @reference value{0})
    elseif ch == '['
        _sel!(JsonArray([JsonInsertion()]), @reference elements[1])
    elseif ch == ':'
        _sel!(JsonObjectEntry("", JsonInsertion()), @reference key{0})
    elseif ch == '{'
        _sel!(JsonObject(() -> [JsonObjectEntry("", JsonInsertion())]), @reference entries[1].key{0})
    elseif isdigit(ch)
        # Don't reinvent a number the user is already editing — let the typein
        # path own it (Lisp `(not (typep printer-input 'json/number))`).
        target isa JsonNumber && return nothing
        _sel!(JsonNumber(parse(Int, string(ch))), @reference value{1})
    else
        return nothing
    end
    ReplaceDocumentOperation(sel, newdoc)
end

# Append a JsonInsertion to an array's elements and select it whole, ready to be
# type-to-replaced (Lisp json/array reader `,` / Insert, :550-569).
function _array_insert(input::JsonArray)
    n = length(input.elements)
    CollectionInsertOperation(@reference(elements), n, Any[JsonInsertion()],
                              @reference elements[n + 1])
end

# Append an empty entry to an object's entries and select its key for typing
# (Lisp json/object reader `,` / Insert, :607-626).
function _object_insert(input::JsonObject)
    n = length(input.entries)
    CollectionInsertOperation(@reference(entries), n,
                              Any[JsonObjectEntry("", JsonInsertion())],
                              @reference entries[n + 1].key{0})
end

# Tab moves the cursor from an entry's key to its value, selected whole so the
# next keystroke type-to-replaces it (Lisp json/object-entry reader, :587-600).
function _object_tab(input::JsonObject)
    sel = getfield(input, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        entries{s:e}.rest... => begin
            i = s + 1
            @reference_case rest begin
                key.inner... => ReplaceSelectionOperation(@reference entries[i].value)
            end
        end
    end
end

projection_read(p::JsonInsertionToSyntaxLeaf, iomap::RuleIoMap, evt::KeyPress) = _json_read_command(iomap.input, evt)
projection_read(p::JsonNullToSyntaxLeaf,      iomap::RuleIoMap, evt::KeyPress) = _json_read_command(iomap.input, evt)
projection_read(p::JsonBoolToSyntaxLeaf,      iomap::RuleIoMap, evt::KeyPress) = _json_read_command(iomap.input, evt)
projection_read(p::JsonNumberToSyntaxLeaf,    iomap::RuleIoMap, evt::KeyPress) = _json_read_command(iomap.input, evt)
projection_read(p::JsonStringToSyntaxLeaf,    iomap::RuleIoMap, evt::KeyPress) = _json_read_command(iomap.input, evt)

# Structural-position fallback for SyntaxNode output: a bracket/brace/comma/colon
# has no JSON pre-image, so it round-trips as the coarse `proj(p, {flat})` shortcut
# — a single flattened character offset the text layer can navigate. This is the
# Syntax→Text-specific counterpart of the engine's domain-neutral proj-wrap
# fallback, so it overrides the generic `RuleIoMap` ReplaceSelection reader for the
# JSON node projections (whose output feeds SyntaxToText).
function projection_read(p::Union{JsonArrayToSyntaxNode, JsonObjectToSyntaxNode}, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::JsonArrayToSyntaxNode, iomap::RuleIoMap, evt::KeyPress)
    evt.char == ',' && return _array_insert(iomap.input)
    _json_read_command(iomap.input, evt)
end

function projection_read(p::JsonObjectToSyntaxNode, iomap::RuleIoMap, evt::KeyPress)
    evt.char == ',' && return _object_insert(iomap.input)
    _json_read_command(iomap.input, evt)
end
# Tab moves key→value (§3.3). The Insert-key "generic insertion" variant of the
# Lisp readers is deferred: the shared TextToGraphics layer would have to route
# Insert inward for every domain, and doing so surfaces an unrelated typein bug
# in the XML element reader. `,` already provides structural insert here.
projection_read(p::JsonObjectToSyntaxNode, iomap::RuleIoMap, evt::KeyDown) =
    evt.key === :tab ? _object_tab(iomap.input) : nothing

# ── Compound convenience constructor ────────────────────────────────────────

function JsonToSyntax()
    TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(),
        JsonBool        => JsonBoolToSyntaxLeaf(),
        JsonNumber      => JsonNumberToSyntaxLeaf(),
        JsonString      => JsonStringToSyntaxLeaf(),
        JsonArray       => JsonArrayToSyntaxNode(),
        JsonObject      => JsonObjectToSyntaxNode(),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(),
        JsonObjectEntry => CopyingProjection(),
        Vector{Cell}    => CopyingProjection(),
    )
end

# ── Utility ──────────────────────────────────────────────────────────────────

# Render a value leaf, falling back to a muted placeholder hint when the value is
# empty (Lisp `text/make-default-text`). The hint is just an ordinary TextString —
# no special field — distinguished only by colour, and both content and colour
# recompute reactively with the value, so the hint vanishes the instant the user
# types. (Same shape JsonInsertion already uses for its "insert JSON here" hint.)
function _hinted_text(content_thunk, empty_thunk, placeholder::AbstractString, style::StyleText)
    TextString(
        Cell(() -> empty_thunk() ? placeholder : content_thunk()),
        Cell(style.font),
        Cell(() -> empty_thunk() ? color_solarized_gray : style.color),
        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
end

function json_escape(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        if ch == '"'       write(buf, "\\\"")
        elseif ch == '\\'  write(buf, "\\\\")
        elseif ch == '\n'  write(buf, "\\n")
        elseif ch == '\r'  write(buf, "\\r")
        elseif ch == '\t'  write(buf, "\\t")
        elseif ch == '\b'  write(buf, "\\b")
        elseif ch == '\f'  write(buf, "\\f")
        elseif codepoint(ch) < 0x20
            write(buf, "\\u", lpad(string(codepoint(ch); base=16), 4, '0'))
        else
            write(buf, ch)
        end
    end
    String(take!(buf))
end

end # module
