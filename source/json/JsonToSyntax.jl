# Fragment of `JsonModule` — the projection from a JSON document to a syntax
# tree. A null, a bool, a number and a string become a leaf. An array and an
# object become a node that carries its brackets or its braces and its comma
# separators.

@projection struct JsonNullToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JsonNullToSyntaxLeaf JsonNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# The shared typed-name insertion buffer, constrained to the JSON candidates
# (prefix-free: `string` → `JsonString`), with the live completion hint and
# commitability colouring. The `"`/`[`/`{`/digit type-to-replace gestures on a
# whole-selected insertion keep working: the leaf's char editing declines
# without a value cursor, so those keys fall through to `@gestures JsonDocument`.

JsonInsertionToSyntaxLeaf() = DomainInsertionToSyntaxLeaf(JsonDocument)

@projection struct JsonBoolToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
end

# `bound` editing can transiently clear the value (the reactive `value` cell is
# type-erased, so a mid-edit read may leave it non-`Bool`); render that state through
# `make_hinted_text` so the `doc.value ? …` thunk is never evaluated on a non-`Bool` — the
# same guard `JsonNumberToSyntaxLeaf` relies on for its `nothing` state.
@projection_template JsonBoolToSyntaxLeaf JsonBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool,
                     make_hinted_text(() -> doc.value ? "true" : "false",
                                 () -> !(doc.value isa Bool), "enter json bool", prj.style)))

@projection struct JsonNumberToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JsonNumberToSyntaxLeaf JsonNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     make_hinted_text(() -> string(doc.value), () -> doc.value === nothing, "enter json number", prj.style);
                     retype = ReplaceNumberRangeOperation))

@projection struct JsonStringToSyntaxLeaf
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JsonStringToSyntaxLeaf JsonString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     make_hinted_text(() -> json_escape(doc.value), () -> isempty(doc.value), "enter json string", prj.value_style));
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

@projection struct JsonArrayToSyntaxNode
    delimiter_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JsonArrayToSyntaxNode JsonArray (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# One `"key": value` member. The object delegates each entry here rather than
# inlining it, so a bare `JsonObjectEntry` also projects on its own.

@projection struct JsonObjectEntryToSyntaxNode
    key_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    colon_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JsonObjectEntryToSyntaxNode JsonObjectEntry (prj, e) ->
    SyntaxNode(TextString("", prj.colon_style),
               TextString("", prj.colon_style),
               TextString(": ", prj.colon_style),
               [ SyntaxLeaf(bound(:key, String, make_hinted_text(() -> json_escape(e.key), () -> isempty(e.key), "enter key", prj.key_style));
                            open=TextString("\"", prj.key_style),
                            close=TextString("\"", prj.key_style)),
                 project(:value) ],
               0, false, getfield(e, :selection))

@projection struct JsonObjectToSyntaxNode
    delimiter_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JsonObjectToSyntaxNode JsonObject (prj, doc) ->
    SyntaxNode(collection(:entries);
               open=TextString("{", prj.delimiter_style),
               close=TextString("}", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# The projection of the whole domain: one rule per document type.

function JsonToSyntax()
    TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(),
        JsonBool        => JsonBoolToSyntaxLeaf(),
        JsonNumber      => JsonNumberToSyntaxLeaf(),
        JsonString      => JsonStringToSyntaxLeaf(),
        JsonArray       => JsonArrayToSyntaxNode(),
        JsonObject      => JsonObjectToSyntaxNode(),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(),
        JsonNothing     => InsertionNothingToSyntaxLeaf(),
        JsonObjectEntry => JsonObjectEntryToSyntaxNode(),
        Vector{Cell}    => CopyingProjection(),
    )
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

# The document an empty `.json` starts from.
make_document_seed(::Val{:json}) = JsonInsertion()
