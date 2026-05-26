"""
    JsonToSyntaxModule

JSON → SyntaxDocument projection. Maps each JSON value type to a matching
syntax tree shape, preserving delimiter characters (quotes, braces, brackets)
as projection-introduced elements via ProjectionReference. The reader inverts
the mapping, routing tree-domain paths back to the correct JSON field, array
index, or ProjectionReference for delimiters.
"""
module JsonToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, entries
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export JsonInsertionToSyntaxLeaf, JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf, JsonNumberToSyntaxLeaf,
       JsonStringToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonToSyntax

# ── JsonNullToSyntaxLeaf ─────────────────────────────────────────────────────

struct JsonNullToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonNullToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) = JsonNullToSyntaxLeaf(font, color)

function projection_print(p::JsonNullToSyntaxLeaf, j::JsonNull, recursion, reference)
    output_selection = Cell(() -> map_reference_forward(p, nothing, j.selection))
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString("null", p.font, p.color), output_selection))
end

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) = JsonInsertionToSyntaxLeaf(font, color)

function projection_print(p::JsonInsertionToSyntaxLeaf, j::JsonInsertion, recursion, reference)
    output_selection = Cell(() -> map_reference_forward(p, nothing, j.selection))
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString("insert JSON here", p.font, p.color), output_selection))
end

# ── JsonBoolToSyntaxLeaf ─────────────────────────────────────────────────────

struct JsonBoolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonBoolToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_yellow) = JsonBoolToSyntaxLeaf(font, color)

function map_reference_forward(::JsonBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::JsonBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

# Selection mapping (JsonBool → SyntaxLeaf, open="" close=""):
# j.selection is shared directly with the leaf (same Cell).
#   .value[k]     →  .value[k]   identity; shared cell
#   anything else →  reader rejects (returns nothing)
function projection_print(p::JsonBoolToSyntaxLeaf, j::JsonBool, recursion, reference)
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> j[] ? "true" : "false", p.font, p.color), getfield(j, :selection)))
end

function projection_read(::JsonBoolToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op                                         # value[k] → value[k]
end

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonNumberToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonNumberToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) = JsonNumberToSyntaxLeaf(font, color)

function map_reference_forward(::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

# Selection mapping (JsonNumber → SyntaxLeaf, open="" close=""):
# j.selection is shared directly with the leaf (same Cell).
#   .value[k]     →  .value[k]   identity; shared cell
#   anything else →  reader rejects (returns nothing)
function projection_print(p::JsonNumberToSyntaxLeaf, j::JsonNumber, recursion, reference)
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> string(j[]), p.font, p.color), getfield(j, :selection)))
end

function projection_read(::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op                                         # value[k] → value[k]
end

# ── JsonStringToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonStringToSyntaxLeaf <: Projection
    quote_font::StyleFont
    quote_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
end
JsonStringToSyntaxLeaf(; quote_font=font_ubuntu_monospace_regular_24, quote_color=color_solarized_yellow,
                         value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_green) =
    JsonStringToSyntaxLeaf(quote_font, quote_color, value_font, value_color)

function map_reference_forward(::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

# Selection mapping (JsonString → SyntaxLeaf, open='"' close='"'):
# j.selection is shared directly with the leaf (same Cell).
#   .value[k]  →  .value[k]
#       character k of the raw string maps to character k of the escaped
#       content (exact when no escape sequences precede position k)
# The surrounding quote characters are projection-introduced; there is no
# input selection that maps to .open[k] or .close[k].
function projection_print(p::JsonStringToSyntaxLeaf, j::JsonString, recursion, reference)
    SimpleIoMap(p, j, SyntaxLeaf(
        TextString("\"", p.quote_font, p.quote_color),
        TextString("\"", p.quote_font, p.quote_color),
        TextString(() -> json_escape(j[]), p.value_font, p.value_color),
        getfield(j, :selection)))
end

function projection_read(p::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    if h.name == "value"
        return op                                     # value[k] → value[k]
    else
        return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))  # open/close quote → PS
    end
end

# ── JsonArrayToSyntaxNode ────────────────────────────────────────────────────

struct JsonArrayToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
    sep_font::StyleFont
    sep_color::StyleColor
end
JsonArrayToSyntaxNode(; delim_font=font_ubuntu_monospace_bold_24, delim_color=color_solarized_gray,
                        sep_font=font_ubuntu_monospace_regular_24,       sep_color=color_solarized_gray) =
    JsonArrayToSyntaxNode(delim_font, delim_color, sep_font, sep_color)

function map_reference_forward(::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_json_path(iomap.input::JsonArray, reference)
end

function map_reference_backward(::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_json_path(iomap.input::JsonArray, reference)
end

# Selection mapping (JsonArray → SyntaxNode, children = projected elements):
#   .elements[i]  →  .children[i]
# child_iomaps holds the projected iomap for every element (shared between
# the children cell and the selection cell so projection_print is called once).
# sel strips .elements + [i] from j.selection, reads the SyntaxDocument-
# domain selection from child_iomaps[i+1].output.selection[], and prepends
# [i] to produce the SyntaxNode-domain path.  Structural positions ([, ], ,)
# fall back to nothing (no cursor on structural characters here).
function projection_print(p::JsonArrayToSyntaxNode, j::JsonArray, recursion, reference)
    child_iomaps = Cell(() -> [projection_print(recursion, x, recursion,
                                   append_reference(reference, FieldReference("elements"), ElementReference(i)))
                               for (i, x) in enumerate(j)])
    sel = Cell(() -> begin
        path = j.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference && h.name == "elements"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            iomaps = child_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            return ConcreteReferencePath(FieldReference("children"), ConcreteReferencePath(ElementReference(child_i), child_sel))
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)
    node = SyntaxNode(
        TextString("[", p.delim_font, p.delim_color),
        TextString("]", p.delim_font, p.delim_color),
        TextString(", ", p.sep_font, p.sep_color),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        1,
        Cell(false),
        sel)
    ChildrenIoMap(p, j, node, child_iomaps)
end

function projection_read(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _translate_json_path(iomap.input::JsonArray, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── JsonObjectToSyntaxNode ───────────────────────────────────────────────────

struct JsonObjectToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
    sep_font::StyleFont
    sep_color::StyleColor
    key_font::StyleFont
    key_color::StyleColor
    colon_font::StyleFont
    colon_color::StyleColor
end
JsonObjectToSyntaxNode(; delim_font=font_ubuntu_monospace_bold_24, delim_color=color_solarized_gray,
                         sep_font=font_ubuntu_monospace_regular_24,       sep_color=color_solarized_gray,
                         key_font=font_ubuntu_monospace_regular_24,       key_color=color_solarized_blue,
                         colon_font=font_ubuntu_monospace_regular_24,     colon_color=color_solarized_gray) =
    JsonObjectToSyntaxNode(delim_font, delim_color, sep_font, sep_color,
                           key_font, key_color, colon_font, colon_color)

function map_reference_forward(::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_json_path(iomap.input::JsonObject, reference)
end

function map_reference_backward(::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_json_path(iomap.input::JsonObject, reference)
end

# Selection mapping (JsonObject → SyntaxNode,
#   children = per-entry pair nodes,
#   each pair's children = [key_leaf (index 1), value_subtree (index 2)]):
#   .entries[i].key[k]  →  .children[i].children[1].value[k]
#   .entries[i].value   →  .children[i].children[2]
# sel strips the .entries wrapper from j.selection so that
# SyntaxNode.set_selection! receives [i] and routes into pair_node[i].
# pair_node uses e.selection so set_selection! propagates entry_sel into
# it; _entry_key_sel(e.selection) then maps .key[k] → .value[k] for the
# key leaf.  Structural positions ({, }, ,, :) fall back to ProjectionReference.
function projection_print(p::JsonObjectToSyntaxNode, j::JsonObject, recursion, reference)
    # Use recursion projection to access entries field
    entries_ref = append_reference(reference, FieldReference("entries"))
    entries_iomap = projection_print(recursion, j.entries.elements, recursion, entries_ref)
    projected_entries = entries_iomap.output
    
    sel = Cell(() -> begin
        path = j.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference && h.name == "entries"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            return ConcreteReferencePath(FieldReference("children"), rest)
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)
    node = SyntaxNode(
        TextString("{", p.delim_font, p.delim_color),
        TextString("}", p.delim_font, p.delim_color),
        TextString(", ", p.sep_font, p.sep_color),
        CellVector(() -> begin
            SyntaxDocument[
                SyntaxNode(
                    TextString("", p.delim_font, color_default),
                    TextString("", p.delim_font, color_default),
                    TextString(": ", p.colon_font, p.colon_color),
                    CellVector(Cell[
                        Cell(SyntaxLeaf(
                            TextString("\"", p.key_font, p.key_color),
                            TextString("\"", p.key_font, p.key_color),
                            TextString(json_escape(e.key), p.key_font, p.key_color),
                            _entry_key_sel(getfield(e, :selection)))),
                        getfield(e, :value)
                    ]),
                    0,
                    Cell(false),
                    getfield(e, :selection))
                for (i, e) in enumerate(projected_entries)
            ]
        end),
        1,
        Cell(false),
        sel)
    ChildrenIoMap(p, j, node, Cell(nothing))
end

function projection_read(p::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _translate_json_path(iomap.input::JsonObject, op.path)
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

# The key SyntaxLeaf reads entry.selection[], which stores paths like
# CP(.key, [k]) when the cursor is in the key. The leaf's
# _leaf_cursor expects CP(.value, [k]), so we remap "key" → "value".
function _entry_key_sel(entry_sel::Cell)
    Cell(() -> begin
        sel = entry_sel[]
        sel isa ConcreteReferencePath || return nothing
        h = sel.head
        if h isa FieldReference && h.name == "key"
            ConcreteReferencePath(FieldReference("value"), sel.tail)
        elseif h isa ProjectionReference
            sel
        else
            nothing
        end
    end)
end

# Maps a SyntaxDocument-domain selection path back to the JSON-domain path.
# The SyntaxDocument for a JsonObject outer node has children that are pair
# SyntaxNodes; each pair's children are [key_leaf (idx 0), value (idx 1)].
# Returns the translated ReferencePath, or nothing if the position is structural.

function _translate_json_path(v::JsonNull, path::ReferencePath)
    return nothing
end

function _translate_json_path(v::Union{JsonBool, JsonNumber, JsonString}, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return path
end

function _translate_json_path(v::JsonArray, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "children" || return nothing
    rest0 = path.tail
    rest0 isa ConcreteReferencePath || return nothing
    h2 = rest0.head
    h2 isa RangeReference || return nothing
    child_i = h2.start + 1
    1 <= child_i <= length(v) || return nothing
    child = v[child_i]
    rest = rest0.tail
    translated = _translate_json_path(child, rest)
    translated === nothing && return nothing
    return ConcreteReferencePath(FieldReference("elements"),
               ConcreteReferencePath(ElementReference(child_i), translated))
end

function _translate_json_path(v::JsonObject, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    h1 isa FieldReference && h1.name == "children" || return nothing
    rest0 = path.tail
    rest0 isa ConcreteReferencePath || return nothing
    hp = rest0.head
    hp isa RangeReference || return nothing
    pair_i = hp.start + 1
    rest1 = rest0.tail
    rest1 isa ConcreteReferencePath || return nothing
    h2 = rest1.head
    h2 isa FieldReference || return nothing
    rest2 = rest1.tail
    rest2 isa ConcreteReferencePath || return nothing
    h3 = rest2.head
    h3 isa RangeReference || return nothing
    child_of_pair = h3.start + 1
    es = entries(v)
    pair_i <= length(es) || return nothing
    entry = es[pair_i]
    leaf_path = rest2.tail
    if child_of_pair == 1
        leaf_path isa ConcreteReferencePath || return nothing
        lh = leaf_path.head
        lh isa FieldReference && lh.name == "value" || return nothing
        char_path = leaf_path.tail
        return ConcreteReferencePath(FieldReference("entries"),
                   ConcreteReferencePath(ElementReference(pair_i),
                       ConcreteReferencePath(FieldReference("key"), char_path)))
    elseif child_of_pair == 2
        translated = _translate_json_path(entry.value, leaf_path)
        translated === nothing && return nothing
        return ConcreteReferencePath(FieldReference("entries"),
                   ConcreteReferencePath(ElementReference(pair_i),
                       ConcreteReferencePath(FieldReference("value"), translated)))
    end
    return nothing
end

function _translate_json_path(v, path)
    return nothing
end

# Maps a JSON-domain selection path forward to the SyntaxDocument-domain path.
# This is the inverse of _translate_json_path.

function _forward_json_path(v::JsonNull, path::ReferencePath)
    return nothing
end

function _forward_json_path(v::Union{JsonBool, JsonNumber, JsonString}, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return path
end

function _forward_json_path(v::JsonArray, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "elements" || return nothing
    rest = path.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_i = h2.start + 1
    1 <= child_i <= length(v) || return nothing
    child = v[child_i]
    inner = _forward_json_path(child, rest.tail)
    inner === nothing && return nothing
    return ConcreteReferencePath(FieldReference("children"), ConcreteReferencePath(ElementReference(child_i), inner))
end

function _forward_json_path(v::JsonObject, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    h1 isa FieldReference && h1.name == "entries" || return nothing
    rest1 = path.tail
    rest1 isa ConcreteReferencePath || return nothing
    h2 = rest1.head
    h2 isa RangeReference || return nothing
    pair_i = h2.start + 1
    es = entries(v)
    pair_i > length(es) && return nothing
    entry = es[pair_i]
    rest2 = rest1.tail
    rest2 isa ConcreteReferencePath || return nothing
    h3 = rest2.head
    h3 isa FieldReference || return nothing
    inner = rest2.tail
    if h3.name == "key"
        return ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(ElementReference(pair_i),
                       ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(1),
                               ConcreteReferencePath(FieldReference("value"), inner)))))
    elseif h3.name == "value"
        translated = _forward_json_path(entry.value, inner)
        translated === nothing && return nothing
        return ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(ElementReference(pair_i),
                       ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(2), translated))))
    end
    return nothing
end

end # module
