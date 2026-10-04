# Fragment of `JsonModule` — the projection from a JSON document to a syntax
# tree. A null, a bool, a number and a string become a leaf. An array and an
# object become a node that carries its brackets or its braces and its comma
# separators.

@projection UntrackedCell struct JsonNullToSyntaxLeaf
    style::StyleText = get_json_style(nothing, :null_text)
end

@projection_template JsonNullToSyntaxLeaf JsonNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# The shared typed-name insertion buffer, constrained to the JSON candidates
# (prefix-free: `string` → `JsonString`), with the live completion hint and
# commitability colouring. The `"`/`[`/`{`/digit type-to-replace gestures on a
# whole-selected insertion keep working: the leaf's char editing declines
# without a value cursor, so those keys fall through to `@gestures JsonDocument`.

JsonInsertionToSyntaxLeaf(; theme = nothing) =
    DomainInsertionToSyntaxLeaf(JsonDocument; placeholder = "enter json value", theme)

@projection UntrackedCell struct JsonBoolToSyntaxLeaf
    style::StyleText = get_json_style(nothing, :bool_text)
end

# `bound` editing can transiently clear the value (the reactive `value` cell is
# type-erased, so a mid-edit read may leave it non-`Bool`); render that state through
# `make_hinted_text` so the `doc.value ? …` thunk is never evaluated on a non-`Bool` — the
# same guard `JsonNumberToSyntaxLeaf` relies on for its `nothing` state.
@projection_template JsonBoolToSyntaxLeaf JsonBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool,
                     make_hinted_text(() -> doc.value ? "true" : "false";
                                      empty_thunk = () -> !(doc.value isa Bool),
                                      placeholder = "enter json bool",
                                      style = prj.style)))

@projection UntrackedCell struct JsonNumberToSyntaxLeaf
    style::StyleText = get_json_style(nothing, :number_text)
end

@projection_template JsonNumberToSyntaxLeaf JsonNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     make_hinted_text(() -> string(doc.value);
                                      empty_thunk = () -> doc.value === nothing,
                                      placeholder = "enter json number",
                                      style = prj.style);
                     retype = ReplaceNumberRangeOperation))

@projection UntrackedCell struct JsonStringToSyntaxLeaf
    quote_style::StyleText = get_json_style(nothing, :quote_text)
    value_style::StyleText = get_json_style(nothing, :string_text)
end

@projection_template JsonStringToSyntaxLeaf JsonString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     make_hinted_text(() -> json_escape(doc.value);
                                      empty_thunk = () -> isempty(doc.value),
                                      placeholder = "enter json string",
                                      style = prj.value_style));
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

@projection UntrackedCell struct JsonArrayToSyntaxNode
    delimiter_style::StyleText = get_json_style(nothing, :delimiter_text)
    separator_style::StyleText = get_json_style(nothing, :separator_text)
end

@projection_template JsonArrayToSyntaxNode JsonArray (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# One `"key": value` member. The object delegates each entry here rather than
# inlining it, so a bare `JsonObjectEntry` also projects on its own.

@projection UntrackedCell struct JsonObjectEntryToSyntaxNode
    key_style::StyleText = get_json_style(nothing, :key_text)
    colon_style::StyleText = get_json_style(nothing, :separator_text)
end

@projection_template JsonObjectEntryToSyntaxNode JsonObjectEntry (prj, e) ->
    SyntaxNode(TextString("", prj.colon_style),
               TextString("", prj.colon_style),
               TextString(": ", prj.colon_style),
               [ SyntaxLeaf(bound(:key, String, make_hinted_text(() -> json_escape(e.key);
                                                                 empty_thunk = () -> isempty(e.key),
                                                                 placeholder = "enter key",
                                                                 style = prj.key_style));
                            open=TextString("\"", prj.key_style),
                            close=TextString("\"", prj.key_style)),
                 project(:value) ],
               0, false, getfield(e, :selection))

@projection UntrackedCell struct JsonObjectToSyntaxNode
    delimiter_style::StyleText = get_json_style(nothing, :delimiter_text)
    separator_style::StyleText = get_json_style(nothing, :separator_text)
end

@projection_template JsonObjectToSyntaxNode JsonObject (prj, doc) ->
    SyntaxNode(collection(:entries);
               open=TextString("{", prj.delimiter_style),
               close=TextString("}", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# The projection of the whole domain: one rule per document type. The builder
# gives each projection its styles from `theme`, a `JsonTheme` scaled or not, or
# the default styles for `nothing`; `syntax_theme` styles the insertion and the
# empty placeholder, which are the syntax slice's.

function JsonToSyntax(; theme = nothing, syntax_theme = nothing)
    get_style(name) = get_json_style(theme, name)
    TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(; style = get_style(:null_text)),
        JsonBool        => JsonBoolToSyntaxLeaf(; style = get_style(:bool_text)),
        JsonNumber      => JsonNumberToSyntaxLeaf(; style = get_style(:number_text)),
        JsonString      => JsonStringToSyntaxLeaf(; quote_style = get_style(:quote_text),
                                                    value_style = get_style(:string_text)),
        JsonArray       => JsonArrayToSyntaxNode(; delimiter_style = get_style(:delimiter_text),
                                                   separator_style = get_style(:separator_text)),
        JsonObject      => JsonObjectToSyntaxNode(; delimiter_style = get_style(:delimiter_text),
                                                    separator_style = get_style(:separator_text)),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(; theme = syntax_theme),
        JsonNothing     => InsertionNothingToSyntaxLeaf(; theme = syntax_theme),
        JsonObjectEntry => JsonObjectEntryToSyntaxNode(; key_style = get_style(:key_text),
                                                         colon_style = get_style(:separator_text)),
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
