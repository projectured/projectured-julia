"""
    JsonToSyntaxModule

JSON → SyntaxDocument projection. Maps each JSON value type to a matching
syntax tree shape: null, bool, number, and string become leaves; arrays and
objects become nodes that carry their quote, bracket, and brace delimiters and
comma separators.
"""
module JsonToSyntaxModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, Projection
import ..ProjectionModule: var"@projection"
import ..JsonModule: JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..TextModule: TextString, hinted_text
import ..FontModule: font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: NumberReplaceRangeOperation
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonNullToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

@projection_template JsonNullToSyntaxLeaf JsonNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonInsertionToSyntaxLeaf JsonInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert JSON here", prj.style))

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonBoolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
end

@projection_template JsonBoolToSyntaxLeaf JsonBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool, TextString(() -> doc[] ? "true" : "false", prj.style)))

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonNumberToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

@projection_template JsonNumberToSyntaxLeaf JsonNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     hinted_text(() -> string(doc[]), () -> doc[] === nothing, "enter json number", prj.style);
                     retype = NumberReplaceRangeOperation))

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonStringToSyntaxLeaf
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
end

@projection_template JsonStringToSyntaxLeaf JsonString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     hinted_text(() -> json_escape(doc[]), () -> isempty(doc[]), "enter json string", prj.value_style));
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

@projection struct JsonArrayToSyntaxNode
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonArrayToSyntaxNode JsonArray (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

@projection struct JsonObjectToSyntaxNode
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
    key_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)
    colon_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

@projection_template JsonObjectToSyntaxNode JsonObject (prj, doc) ->
    SyntaxNode(collection(:entries) do e
                   SyntaxNode(TextString("", prj.delimiter_style),
                              TextString("", prj.delimiter_style),
                              TextString(": ", prj.colon_style),
                              [ SyntaxLeaf(bound(:key, String, hinted_text(() -> json_escape(e.key), () -> isempty(e.key), "enter key", prj.key_style));
                                           open=TextString("\"", prj.key_style),
                                           close=TextString("\"", prj.key_style)),
                                project(:value) ],
                              0, false, getfield(e, :selection))
               end;
               open=TextString("{", prj.delimiter_style),
               close=TextString("}", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
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
