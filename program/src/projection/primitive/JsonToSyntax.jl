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
import ..JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection, copying_field_iomap
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: PrinterContext, child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
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

# Selection mapping (JsonNull → SyntaxLeaf): "null" is a projection-introduced
# label with no editable input value, so a cursor on it has no input pre-image.
# The default map_reference_forward (proj-unwrapping) is therefore the correct
# mapper here — a value cursor arrives wrapped as proj(p, .value{k}) and is
# unwrapped to .value{k} for the leaf. Unlike Bool/Number/String the input and
# output selection formats differ (proj-wrapped vs. bare), so the shared-cell
# shortcut does not apply. The default mapper ignores the iomap, so it is passed
# as nothing.
function projection_print(p::JsonNullToSyntaxLeaf, recursion, j::JsonNull, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, j.selection))
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString("null", p.font, p.color), output_selection))
end

# ── JsonInsertionToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) = JsonInsertionToSyntaxLeaf(font, color)

# Selection mapping (JsonInsertion → SyntaxLeaf): same rationale as JsonNull —
# "insert JSON here" is a projection-introduced placeholder with no editable
# input value, so the default proj-unwrapping forward mapper is correct and the
# shared-cell shortcut does not apply. The real iomap is threaded canonically.
function projection_print(p::JsonInsertionToSyntaxLeaf, recursion, j::JsonInsertion, ctx)
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
        ∅ => @reference()
        value{s:e} => @reference value{s:e}
    end
end

function map_reference_backward(::JsonBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        value{s:e} => @reference value{s:e}
    end
end

# Selection mapping (JsonBool → SyntaxLeaf, open="" close=""):
# j.selection is shared directly with the leaf (same Cell), so .value{k}
# identity-maps on both sides with no wiring. Selection reads are handled by
# the default projection_read, which routes the path through the identity
# map_reference_backward above — no bespoke reader is needed.
function projection_print(p::JsonBoolToSyntaxLeaf, recursion, j::JsonBool, ctx)
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> j[] ? "true" : "false", p.font, p.color), getfield(j, :selection)))
end

# ── JsonNumberToSyntaxLeaf ───────────────────────────────────────────────────

struct JsonNumberToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JsonNumberToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) = JsonNumberToSyntaxLeaf(font, color)

function map_reference_forward(::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        value{s:e} => @reference value{s:e}
    end
end

function map_reference_backward(::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        value{s:e} => @reference value{s:e}
    end
end

# Selection mapping (JsonNumber → SyntaxLeaf, open="" close=""):
# j.selection is shared directly with the leaf (same Cell), so .value{k}
# identity-maps on both sides. Selection reads use the default projection_read
# (routed through the identity map_reference_backward); only the value-editing
# path below needs a bespoke reader.
function projection_print(p::JsonNumberToSyntaxLeaf, recursion, j::JsonNumber, ctx)
    SimpleIoMap(p, j, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> string(j[]), p.font, p.color), getfield(j, :selection)))
end

# Editing into a JsonNumber's value rewires the string operation as a
# NumberReplaceRangeOperation so the evaluator's tryparse logic kicks in. The
# reference is re-targeted through map_reference_backward (identity for .value)
# so the path mapping stays in one place; the retype is the documented
# "convert to a different operation" move.
function projection_read(p::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    NumberReplaceRangeOperation(new_ref, op.replacement)
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

# The forward mapper is the inverse of map_reference_backward below: .value
# passes through, and this projection's own ProjectionReference step (wrapping a
# projection-introduced quote position) is unwrapped back to the output quote
# reference. The unwrap matters once a parent delegates here under School A — a
# quote selection on a nested string round-trips as proj(p, open) → open.
function map_reference_forward(p::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), inner) => inner
        value{s:e} => @reference value{s:e}
    end
end

# The quote characters are projection-introduced and have no JSON-domain
# pre-image, so an .open/.close output reference crosses into the output domain
# here: it is wrapped in this projection's own ProjectionReference step (the
# late-as-possible crossing described in the map_reference_backward docstring).
# map_reference_forward unwraps the same step, so the path round-trips. A
# .value reference passes through unchanged (identity character offsets, exact
# when no escape sequences precede the position).
function map_reference_backward(p::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        value{s:e} => @reference value{s:e}
        open{s:e}  => ConcreteReferencePath(ProjectionReference(p, reference))
        close{s:e} => ConcreteReferencePath(ProjectionReference(p, reference))
    end
end

# Selection mapping (JsonString → SyntaxLeaf, open='"' close='"'):
# j.selection is shared directly with the leaf (same Cell). Selection reads use
# the default projection_read, which routes the output path through
# map_reference_backward above — .value passes through; the surrounding quotes
# wrap into a ProjectionReference. Only value editing needs a bespoke reader.
function projection_print(p::JsonStringToSyntaxLeaf, recursion, j::JsonString, ctx)
    SimpleIoMap(p, j, SyntaxLeaf(
        TextString("\"", p.quote_font, p.quote_color),
        TextString("\"", p.quote_font, p.quote_color),
        TextString(() -> json_escape(j[]), p.value_font, p.value_color),
        getfield(j, :selection)))
end

# Editing into a JsonString's value is an identity translation — the syntax
# leaf's value content is `json_escape(j[])`, so character offsets agree as
# long as no escape sequences precede position k. The reference is re-targeted
# through map_reference_backward (identity for .value) to keep the path mapping
# in one place. Escape-aware mapping is deferred (same caveat as
# `map_reference_*`).
function projection_read(p::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
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

# Selection mapping (School A): peel the one step this projection owns
# (.elements[i] ↔ .children[i]) and delegate the remaining tail to element i's
# own projection through the stored child IO map, so the recursion follows
# whatever projection actually ran rather than re-walking JSON value types.
# A `proj(p, …)` head is this projection's own introduced output (a bracket,
# comma, or flattened structural offset); forward keeps it wrapped so the
# SyntaxNode renderer can interpret the embedded output position.
function map_reference_forward(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        elements{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference elements[child_i].^(inner)
        end
    end
end

# Selection mapping (JsonArray → SyntaxNode, children = projected elements):
#   .elements[i]  →  .children[i]
# child_iomaps holds the projected iomap for every element (shared between the
# children cell and the selection cell so projection_print is called once). The
# output selection is wired canonically by mapping j.selection forward through
# this projection's own map_reference_forward (School A — delegating the tail
# through child_iomaps), the single definition reused on both sides. The
# not-yet-built iomap is supplied via the deferred-iomap trick (iomap_cell), as
# in CopyingProjection.
function projection_print(p::JsonArrayToSyntaxNode, recursion, j::JsonArray, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_print(recursion, recursion, x,
                                   child_context(ctx, @reference ^(reference).elements[i]))
                               for (i, x) in enumerate(j)])
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = j.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        TextString("[", p.delim_font, p.delim_color),
        TextString("]", p.delim_font, p.delim_color),
        TextString(", ", p.sep_font, p.sep_color),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        1,
        Cell(false),
        sel)
    iomap = ChildrenIoMap(p, j, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# A structural output position ([, ], ,) has no JSON pre-image, so it is
# represented by the coarse `proj(p, {flat})` shortcut — a single flattened
# character offset wrapped in this projection's step. The fine-grained
# `matched_input_prefix + proj(p, unmatched_output_suffix)` form (see the
# map_reference_backward docstring) is deliberately not used here: the
# individual delimiters are not separately addressable by any current feature,
# so the flat offset is sufficient and round-trips via `_syntax_to_flat`.
function projection_read(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, op::Union{StringReplaceRangeOperation, NumberReplaceRangeOperation})
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    typeof(op)(new_ref, op.replacement)
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

# Selection mapping (School A). Each entry's output is a pair node whose
# children are [key_leaf (index 1), value_subtree (index 2)]:
#   .entries[i].key[k]      →  .children[i].children[1].value[k]
#   .entries[i].value.<tail> →  .children[i].children[2].<value-mapped tail>
# The key leaf is projection-introduced (its content has no document child IO
# map), so the key mapping is a fixed structural rewrite. The value tail is
# delegated through the stored per-entry value IO map, so the recursion follows
# whatever projection actually ran. A `proj(p, …)` head is this projection's own
# introduced output ({, }, :, separators, flattened offset) and passes through.
function map_reference_forward(p::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        entries{s:e}.rest... => begin
            pair_i = s + 1
            vioms = iomap.child_iomaps[]
            1 <= pair_i <= length(vioms) || return nothing
            # Whole entry: .entries[j]∅ → .children[j]∅
            rest isa EmptyReferencePath && return @reference children[pair_i]
            @reference_case rest begin
                key.inner... => begin
                    # Whole key: .entries[j].key∅ → .children[j].children[1]∅
                    inner isa EmptyReferencePath && return @reference children[pair_i].children[1]
                    @reference children[pair_i].children[1].value.^(inner)
                end
                value.inner... => begin
                    child = vioms[pair_i]
                    child === nothing && return nothing
                    translated = map_reference_forward(child.projection, child, inner)
                    translated === nothing && return nothing
                    @reference children[pair_i].children[2].^(translated)
                end
            end
        end
    end
end

function map_reference_backward(p::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{s:e}.rest... => begin
            pair_i = s + 1
            vioms = iomap.child_iomaps[]
            1 <= pair_i <= length(vioms) || return nothing
            # Whole pair node: .children[j]∅ → .entries[j]∅
            rest isa EmptyReferencePath && return @reference entries[pair_i]
            @reference_case rest begin
                children{s2:e2}.leaf_path... => begin
                    child_of_pair = s2 + 1
                    if child_of_pair == 1
                        # Whole key leaf: .children[j].children[1]∅ → .entries[j].key∅
                        leaf_path isa EmptyReferencePath && return @reference entries[pair_i].key
                        @reference_case leaf_path begin
                            value.char_path... => @reference entries[pair_i].key.^(char_path)
                        end
                    elseif child_of_pair == 2
                        child = vioms[pair_i]
                        child === nothing && return nothing
                        translated = map_reference_backward(child.projection, child, leaf_path)
                        translated === nothing && return nothing
                        @reference entries[pair_i].value.^(translated)
                    else
                        nothing
                    end
                end
            end
        end
    end
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
# The reference maps use School A (delegating each value tail through the stored
# per-entry value IO map), so the result is a ChildrenIoMap carrying those maps.
function projection_print(p::JsonObjectToSyntaxNode, recursion, j::JsonObject, ctx)
    reference = ctx.reference
    # Use recursion projection to access entries field
    entries_ref = @reference ^(reference).entries
    entries_iomap = projection_print(recursion, recursion, j.entries.elements, child_context(ctx, entries_ref))
    projected_entries = entries_iomap.output

    # School-A delegation handle: the per-entry value IO map. Each entry is
    # projected by a CopyingProjection (JsonObjectEntry has one Document field,
    # `value`), so its value subtree's IO map is reachable through the stored
    # entries IO map — the same projection that produced the rendered values, so
    # the mappers can never drift from what was printed. The key leaf and the
    # structural delimiters are projection-introduced and have no child IO map;
    # those stay as explicit structural rewrites in the mappers below.
    value_iomaps = Cell(() -> Any[copying_field_iomap(em, "value") for em in entries_iomap.children])

    sel = Cell(() -> begin
        path = j.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            ∅ => @reference()
            entries.rest... => rest isa ConcreteReferencePath ? (@reference children.^(rest)) : nothing
        end
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
    ChildrenIoMap(p, j, node, value_iomaps)
end

# Structural positions ({, }, ,, :) use the same coarse `proj(p, {flat})`
# shortcut as JsonArrayToSyntaxNode above (deliberately not the fine-grained
# form — see that reader's note).
function projection_read(p::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::JsonObjectToSyntaxNode, iomap::ChildrenIoMap, op::Union{StringReplaceRangeOperation, NumberReplaceRangeOperation})
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    typeof(op)(new_ref, op.replacement)
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
        sel isa ConcreteReferencePath && sel.head isa ProjectionReference && return sel
        @reference_case sel begin
            key.rest... => @reference value.^(rest)
        end
    end)
end

end # module
