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
import ..ProjectionApiModule: projection_print, projection_printer_recurse, map_reference_forward, Projection
import ..ProjectionModule: var"@projection"
import ..JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrinterContextModule: PrinterContext, child_context
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonNullToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

@projection_template JsonNullToSyntaxLeaf JsonNull (p, doc) ->
    SyntaxLeaf(TextString("null", p.style))

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonInsertionToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonInsertionToSyntaxLeaf JsonInsertion (p, doc) ->
    SyntaxLeaf(TextString("insert JSON here", p.style))

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonBoolToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
end

@projection_template JsonBoolToSyntaxLeaf JsonBool (p, doc) ->
    SyntaxLeaf(bound(:value, Bool, TextString(() -> doc[] ? "true" : "false", p.style)))

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonNumberToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

@projection_template JsonNumberToSyntaxLeaf JsonNumber (p, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     _hinted_text(() -> string(doc[]), () -> doc[] === nothing, "enter json number", p.style);
                     retype = NumberReplaceRangeOperation))

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonStringToSyntaxLeaf <: Projection
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
end

@projection_template JsonStringToSyntaxLeaf JsonString (p, doc) ->
    SyntaxLeaf(bound(:value, String,
                     _hinted_text(() -> json_escape(doc[]), () -> isempty(doc[]), "enter json string", p.value_style));
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

@projection struct JsonArrayToSyntaxNode <: Projection
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonArrayToSyntaxNode JsonArray (p, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delimiter_style),
               close=TextString("]", p.delimiter_style),
               sep=TextString(", ", p.separator_style),
               indentation=1)

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

@projection struct JsonObjectToSyntaxNode <: Projection
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
    key_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)
    colon_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonObjectToSyntaxNode JsonObject (p, doc) ->
    SyntaxNode(collection(:entries) do e
                   SyntaxNode(TextString("", p.delimiter_style),
                              TextString("", p.delimiter_style),
                              TextString(": ", p.colon_style),
                              [ SyntaxLeaf(bound(:key, String, _hinted_text(() -> json_escape(e.key), () -> isempty(e.key), "enter key", p.key_style));
                                           open=TextString("\"", p.key_style),
                                           close=TextString("\"", p.key_style)),
                                project(:value) ],
                              0, false, getfield(e, :selection))
               end;
               open=TextString("{", p.delimiter_style),
               close=TextString("}", p.delimiter_style),
               sep=TextString(", ", p.separator_style),
               indentation=1)

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
