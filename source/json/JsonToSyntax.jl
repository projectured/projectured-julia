"""
    JsonToSyntaxModule

JSON → SyntaxDocument projection. Maps each JSON value type to a matching
syntax tree shape: null, bool, number, and string become leaves; arrays and
objects become nodes that carry their quote, bracket, and brace delimiters and
comma separators.
"""
module JsonToSyntaxModule

import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: print_document, Projection
import ..ProjectionModule: var"@projection"
import ..JsonModule: JsonDocument, JsonNothing, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..SerializationModule: FileDocument, ReferenceStub, format_marker_text, format_file_marker_text, get_filename
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString, make_hinted_text
import ..StyleModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..StyleModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: ReplaceNumberRangeOperation
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonObjectEntryToSyntaxNode,
       ReferenceStubToJsonSyntaxLeaf, EmbeddedFileDocumentToJsonSyntaxLeaf,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct JsonNullToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JsonNullToSyntaxLeaf JsonNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────
#
# The shared typed-name insertion buffer, constrained to the JSON candidates
# (prefix-free: `string` → `JsonString`), with the live completion hint and
# commitability colouring. The `"`/`[`/`{`/digit type-to-replace gestures on a
# whole-selected insertion keep working: the leaf's char editing declines
# without a value cursor, so those keys fall through to `@gestures JsonDocument`.

JsonInsertionToSyntaxLeaf() = DomainInsertionToSyntaxLeaf(JsonDocument)

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

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

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonNumberToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JsonNumberToSyntaxLeaf JsonNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     make_hinted_text(() -> string(doc.value), () -> doc.value === nothing, "enter json number", prj.style);
                     retype = ReplaceNumberRangeOperation))

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JsonStringToSyntaxLeaf
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JsonStringToSyntaxLeaf JsonString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     make_hinted_text(() -> json_escape(doc.value), () -> isempty(doc.value), "enter json string", prj.value_style));
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

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

# ── JsonObjectEntryToSyntaxNode ──────────────────────────────────────────────
# One `"key": value` member. The object delegates each entry here (School A) rather
# than inlining, so a bare `JsonObjectEntry` also projects on its own.

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

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

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
        JsonNothing     => InsertionNothingToSyntaxLeaf(),
        JsonObjectEntry => JsonObjectEntryToSyntaxNode(),
        # A cross-file reference — either as a resolved-later stub or as
        # an embedded FileDocument child — renders as a marker string
        # (`"<<file(\"path\")>>"`), so print_natural_text emits the right
        # thing without a pre-save AST mutation.
        ReferenceStub   => ReferenceStubToJsonSyntaxLeaf(),
        FileDocument    => EmbeddedFileDocumentToJsonSyntaxLeaf(),
        Vector{Cell}    => CopyingProjection(),
    )
end

# ── ReferenceStubToJsonSyntaxLeaf ────────────────────────────────────────────
# A ReferenceStub sitting in a JSON AST slot renders as the marker
# string `"<<file(\"path\")>>"` — a JsonString-shaped SyntaxLeaf with the
# same quote-then-value-then-quote structure JsonStringToSyntaxLeaf produces.

@projection struct ReferenceStubToJsonSyntaxLeaf
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template ReferenceStubToJsonSyntaxLeaf ReferenceStub (prj, stub) ->
    SyntaxLeaf(TextString(_stub_marker_body(stub), prj.value_style);
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

_stub_marker_body(stub::ReferenceStub) = json_escape(format_marker_text(stub))

# ── EmbeddedFileDocumentToJsonSyntaxLeaf ─────────────────────────────────────
# A FileDocument embedded directly in a JSON AST (as opposed to referenced
# through a ReferenceStub) renders as the same marker string — the
# embedded child gets its own file on save, and the parent's serialised
# form only holds the reference.

@projection struct EmbeddedFileDocumentToJsonSyntaxLeaf
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template EmbeddedFileDocumentToJsonSyntaxLeaf FileDocument (prj, file) ->
    SyntaxLeaf(TextString(_embedded_marker_body(file), prj.value_style);
               open=TextString("\"", prj.quote_style),
               close=TextString("\"", prj.quote_style))

_embedded_marker_body(file::FileDocument) = json_escape(format_file_marker_text(get_filename(file)))

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

# ── Natural-format registration ─────────────────────────────────────────────
# JSON's seams for import_document / export_document / read+write_document_file.
import ..JsonParserModule: parse_json
import ..FileFormatModule: make_document_seed
make_document_seed(::Val{:json}) = JsonInsertion()

# ── What this domain's natural notation is ──────────────────────────────────
# One statement: the rung it starts at and how to build it, the format it is
# written in, the extension that names the format back, and how to read that text
# in again. Runtime state, so `__init__` rather than a top-level call.
import ..NaturalModule: register_natural_domain!
import ..JsonModule: JsonDocument

function __init__()
    register_natural_domain!(JsonDocument;
                             rung      = :syntax,
                             make      = () -> JsonToSyntax(),
                             format    = :json,
                             extension = ".json",
                             parse     = parse_json)
end

end # module
