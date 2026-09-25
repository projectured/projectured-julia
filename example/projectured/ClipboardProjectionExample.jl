# ── OS-clipboard converters for the JSON clipboard example ──────────────────────
# These bridge the JSON domain and the OS clipboard's plain text. `to_text`
# serializes a copied sub-document to JSON source (mirrored out on Ctrl+C/X/N);
# `from_text` parses OS-clipboard text back into a JSON document (the Ctrl+V
# fallback when the internal slice is empty). Both are handed to
# ClipboardSliceToAnyProjection; with them unset the clipboard stays OS-inert.

# JSON-escape a string into a quoted literal.
function _json_escape(s::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for c in s
        if     c == '"';  print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif c < '\x20'; print(io, "\\u", lpad(string(UInt(c), base=16), 4, '0'))
        else   print(io, c)
        end
    end
    print(io, '"')
    String(take!(io))
end

# Serialize a JSON document to compact JSON source. Returns `nothing` for shapes
# that have no JSON rendering (e.g. a bare JsonInsertion), so the OS mirror declines.
_json_to_text(d::JsonNull)        = "null"
_json_to_text(d::JsonBool)        = d.value ? "true" : "false"
_json_to_text(d::JsonNumber)      = d.value === nothing ? "null" : string(d.value)
_json_to_text(d::JsonString)      = _json_escape(d.value)
_json_to_text(d::JsonArray)       = "[" * join((_json_to_text(d[i]) for i in 1:length(d)), ", ") * "]"
_json_to_text(d::JsonObjectEntry) = _json_escape(d.key) * ": " * _json_to_text(d.value)
_json_to_text(d::JsonObject)      = "{" * join((_json_to_text(d.entries[i]) for i in 1:length(d.entries)), ", ") * "}"
_json_to_text(d)                  = nothing

# Parse OS-clipboard text into a JSON document. Valid JSON parses via `parse_json`;
# anything else (plain external text) becomes a JsonString so paste still works.
function _json_from_text(text)
    s = strip(text)
    isempty(s) && return nothing
    try
        return parse_json(s)
    catch
        return JsonString(String(text))
    end
end

# Projects a ClipboardSlice down to graphics. The clipboard projection sits at the
# top of the recursion: it recurses into the wrapped JSON `content` (or, once a
# slice is stored and the view is toggled, into the stored `slice`), and the same
# dispatcher turns that JSON into a syntax tree. SyntaxToText then TextToGraphics
# finish the pipeline, exactly as the plain JSON example does.
#
# Gestures owned by the clipboard projection (the rest fall through to JSON):
#   Ctrl+/        toggle between showing the wrapped content and the stored slice
#   Ctrl+C        copy the selected sub-document into the slice (deep copy) + mirror to OS
#   Ctrl+X        cut the selected sub-document into the slice + mirror to OS
#   Ctrl+N        note: store the live selected object in the slice (no copy) + mirror to OS
#   Ctrl+V        paste the stored slice (or, if empty, the OS clipboard) over the selection
#   Ctrl+Shift+V  paste a fresh deep copy of the stored slice
function make_clipboard_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            ClipboardSlice  => ClipboardSliceToAnyProjection(; to_text=_json_to_text, from_text=_json_from_text),
            JsonNull        => JsonNullToSyntaxLeaf(),
            JsonBool        => JsonBoolToSyntaxLeaf(),
            JsonNumber      => JsonNumberToSyntaxLeaf(),
            JsonString      => JsonStringToSyntaxLeaf(),
            JsonArray       => JsonArrayToSyntaxNode(),
            JsonObject      => JsonObjectToSyntaxNode(),
            JsonInsertion   => JsonInsertionToSyntaxLeaf(),
            JsonObjectEntry => CopyingProjection(),
            Vector{Cell}    => CopyingProjection(),
        )),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
