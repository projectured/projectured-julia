"""
    JsonToSyntaxModule

JSON → SyntaxDocument projection. Maps each JSON value type to a matching
syntax tree shape, preserving delimiter characters (quotes, braces, brackets)
as projection-introduced elements via ProjectionReference. The reader inverts
the mapping, routing tree-domain paths back to the correct JSON field, array
index, or ProjectionReference for delimiters.

Each value type is a `@projection_template` builder `(p, doc) -> output`; the
engine derives the printer and reference mappers from the built tree. Only the
JSON authoring readers (type-to-replace, `,` insert, Tab) and the structural
fallback stay hand-written.
"""
module JsonToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ReferenceModule: ConcreteReferencePath, PositionReference, ProjectionReference
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection, RuleIoMap
import ..PrinterContextModule: PrinterContext, child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonNullToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

# Fixed label, no editable value: no marker, so the selection maps straight through.
@projection_template JsonNullToSyntaxLeaf JsonNull (p, doc) ->
    SyntaxLeaf(TextString("null", p.style))

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonInsertionToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

# Fixed placeholder, like JsonNull.
@projection_template JsonInsertionToSyntaxLeaf JsonInsertion (p, doc) ->
    SyntaxLeaf(TextString("insert JSON here", p.style))

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonBoolToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
end

# bound(:value) makes the leaf text track JsonBool.value and share its selection
# cell, so .value{k} maps both ways.
@projection_template JsonBoolToSyntaxLeaf JsonBool (p, doc) ->
    SyntaxLeaf(bound(:value, Bool, TextString(() -> doc[] ? "true" : "false", p.style)))

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonNumberToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

# bound(:value); `retype` rewrites the value edit into a NumberReplaceRangeOperation
# so numeric parsing applies.
@projection_template JsonNumberToSyntaxLeaf JsonNumber (p, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     _hinted_text(() -> string(doc[]), () -> doc[] === nothing, "enter json number", p.style);
                     retype = NumberReplaceRangeOperation))

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonStringToSyntaxLeaf <: Projection
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
end

# bound(:value) for the string text. The `"` delimiters are selectable introduced
# text with no JSON pre-image, so a quote selection round-trips through this
# projection's own ProjectionReference.
@projection_template JsonStringToSyntaxLeaf JsonString (p, doc) ->
    SyntaxLeaf(bound(:value, String,
                     _hinted_text(() -> json_escape(doc[]), () -> isempty(doc[]), "enter json string", p.value));
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

@projection struct JsonArrayToSyntaxNode <: Projection
    delim::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    sep::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

# collection(:elements) recurses over doc.elements and records (.elements[i] ↔
# .children[i]). The [, ], and , positions are projection-introduced; the reader
# fallback below maps them to a flat text offset.
@projection_template JsonArrayToSyntaxNode JsonArray (p, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delim),
               close=TextString("]", p.delim),
               sep=TextString(", ", p.sep),
               indentation=1)

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

@projection struct JsonObjectToSyntaxNode <: Projection
    delim::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    sep::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
    key::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)
    colon::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

# collection(:entries) builds a per-entry pair node [key_leaf, value]: the key leaf
# is bound(:key) and `project(:value)` delegates the value subtree to its own
# projection. Structural positions ({, }, :, separators) map to a flat offset via
# the reader fallback below.
@projection_template JsonObjectToSyntaxNode JsonObject (p, doc) ->
    SyntaxNode(collection(:entries) do e
                   # Fixed-children template node: `_fixed_print` finds children via
                   # `isa Vector` to locate the `project(:value)` marker, so they must stay
                   # a raw Vector (not the CellVector the keyword `children` path produces).
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

# ── Reader: structural (projection-introduced) positions only ───────────────
#
# The JSON *authoring* command set (type-to-replace, `,`-insert, Tab) now lives on
# the document types as reified `@gestures` in `JsonModule` and reaches the JSON
# layer through the generic `document_read` fallback in `projection_read`. Only the
# structural flat-offset reader below stays here: brackets/braces/commas/colons
# have no JSON pre-image, so they are genuinely projection-specific.

# Structural positions (brackets/braces/comma/colon) have no JSON pre-image, so they
# round-trip as a flat character offset the text layer can navigate. Overrides the
# generic `RuleIoMap` ReplaceSelection reader for the node projections.
function projection_read(p::Union{JsonArrayToSyntaxNode, JsonObjectToSyntaxNode}, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

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

# A value leaf that shows a muted placeholder while the value is empty. Both text
# and colour are reactive, so the hint disappears the moment the user types.
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
