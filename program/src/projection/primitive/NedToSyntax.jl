"""
    NedToSyntaxModule

NED → SyntaxDocument projection. Maps NED document types to syntax tree
nodes for rendering as syntax-highlighted text.

Layout:
- `NedFile`            → SyntaxNode (children = package/imports/decls)
- `NedCompoundModule`  → SyntaxNode (open = "network Name {", children = sections)
- `NedSimpleModule`    → SyntaxNode (open = "simple Name {", children = params/gates)
- `NedChannel`         → SyntaxNode (open = "channel Name {", children = params)
- `NedParam`           → SyntaxLeaf (type name = value;)
- `NedGate`            → SyntaxLeaf (input name[];)
- `NedSubmodule`       → SyntaxNode (name: Type { ... })
- `NedConnection`      → SyntaxLeaf (src --> dest;)
- `NedConnectionGroup` → SyntaxNode (for ... { connections })
- `NedProperty`        → SyntaxLeaf (@name(...))
- `NedPackage`         → SyntaxLeaf (package name;)
- `NedImport`          → SyntaxLeaf (import spec;)
- `NedInsertion`       → SyntaxLeaf (placeholder)

Readers are deferred to a future step.
"""
module NedToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..NedModule: NedDocument, NedInsertion, NedExtends, NedInterfaceName, NedLoop, NedCondition,
                    NedLiteral, NedPropertyKey, NedProperty, NedPropertyDecl, NedParam, NedGate,
                    NedSubmodule, NedConnection, NedConnectionGroup,
                    NedSimpleModule, NedCompoundModule, NedModuleInterface, NedChannel, NedChannelInterface,
                    NedPackage, NedImport, NedFile
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_gray63,
                      color_solarized_blue, color_solarized_green, color_solarized_magenta,
                      color_solarized_cyan, color_solarized_yellow, color_solarized_gray,
                      color_solarized_red, color_solarized_orange, color_solarized_violet
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, skip_type_checkpoints,
                         ProjectionReference, ReferencePath, EmptyReferencePath, append_reference, head, tail
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export NedInsertionToSyntaxLeaf, NedPackageToSyntaxLeaf, NedImportToSyntaxLeaf,
       NedPropertyToSyntaxLeaf, NedParamToSyntaxLeaf, NedGateToSyntaxLeaf,
       NedSubmoduleToSyntaxNode, NedConnectionToSyntaxLeaf, NedConnectionGroupToSyntaxNode,
       NedSimpleModuleToSyntaxNode, NedCompoundModuleToSyntaxNode,
       NedModuleInterfaceToSyntaxNode, NedChannelToSyntaxNode, NedChannelInterfaceToSyntaxNode,
       NedFileToSyntaxNode, NedToSyntax

# ── Style defaults ────────────────────────────────────────────────────────

# Palette modeled on the Eclipse/OMNeT++ NED source editor (see reference
# screenshot): maroon bold keywords, black identifiers/values, green strings and
# `@property` annotations, gray comments. The cream editor background is shared
# across examples and is intentionally left unchanged.
const _kw_font  = font_ubuntu_monospace_bold_24
const _kw_color = StyleColor(127 / 255, 0 / 255, 85 / 255, 1.0)  # Eclipse keyword maroon
const _id_font  = font_ubuntu_monospace_regular_24
const _id_color = color_black
const _type_color = _kw_color            # parameter/gate types (double, bool, input …)
const _str_color  = color_solarized_blue # string constants
const _val_color  = color_black          # value expressions / non-string literals
const _op_color   = color_gray63         # operators / punctuation
const _prop_color = color_solarized_green # @property annotations
const _section_color = color_solarized_violet # body section labels (parameters:, gates: …)
const _comment_color = color_solarized_gray

# ── Helpers ───────────────────────────────────────────────────────────────

_empty_ts() = TextString("", _id_font, color_default)
_ts(text, font=_id_font, color=color_default) = TextString(text, font, color)
_kw(text) = TextString(text, _kw_font, _kw_color)
_section_kw(text) = TextString(text, _kw_font, _section_color)
_op(text) = TextString(text, _id_font, _op_color)

# ── Section-structured node infrastructure ────────────────────────────────
#
# Module-like NED types render their body as a two-level syntax tree: the node's
# children are *section* SyntaxNodes ("parameters:", "gates:", …), and each
# section node's children are the projected entries. The document has no section
# level — entries live directly in per-field CellVectors (`.params`, `.gates`,
# …). So whole-element selection paths cross two coordinate systems:
#
#   document  .params[i].<tail>   ⇄   syntax  .children[sec].children[i].<tail>
#   document  .params (∅)         ⇄   syntax  .children[sec] (∅)   (whole section)
#   document  ∅                   ⇄   syntax  ∅                    (whole node)
#
# `sec` is the section's index among the *non-empty* sections (empty sections are
# not rendered). The per-section IO maps store the field name and the entries'
# own IO maps so the entry tail can be delegated (School A).
abstract type NedSectionToSyntaxNode <: Projection end

# Build the per-section IO map structure: one NamedTuple (field, label, entries)
# per non-empty section, in render order. `sections` is a vector of
# (label::String, field::Symbol, cv::CellVector).
function _ned_section_iomaps(recursion, ctx, reference, sections)
    result = NamedTuple[]
    for (label, field, cv) in sections
        isempty(cv) && continue
        entry_ioms = Any[]
        for (i, child) in enumerate(cv)
            im = projection_printer_recurse(recursion, child,
                     child_context(ctx, _field_child_ref(reference, field, i)))
            push!(entry_ioms, im)
        end
        push!(result, (field=field, label=label, entries=entry_ioms))
    end
    result
end

# document → syntax. `secs` is the value of the section IO maps cell.
function _ned_section_forward(secs, reference)
    reference = skip_type_checkpoints(reference)
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference isa ConcreteReferencePath || return nothing
    h = head(reference)
    h isa FieldReference || return nothing
    field = Symbol(h.name)
    sec_i = findfirst(s -> s.field === field, secs)
    sec_i === nothing && return nothing
    rest = skip_type_checkpoints(tail(reference))
    rest isa EmptyReferencePath && return @reference ::SyntaxNode.children[sec_i]
    rest isa ConcreteReferencePath || return nothing
    h2 = head(rest)
    h2 isa RangeReference || return nothing
    entry_i = h2.stop                       # ElementReference(i) = Range(i-1, i)
    entries = secs[sec_i].entries
    1 <= entry_i <= length(entries) || return nothing
    child = entries[entry_i]
    entry_rest = skip_type_checkpoints(tail(rest))
    if entry_rest isa EmptyReferencePath
        return @reference ::SyntaxNode.children[sec_i].children[entry_i]
    end
    inner = map_reference_forward(child.projection, child, entry_rest)
    inner === nothing && return nothing
    @reference ::SyntaxNode.children[sec_i].children[entry_i].^(inner)
end

# syntax → document. `secs` is the value of the section IO maps cell.
function _ned_section_backward(secs, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{s:_}.rest... => begin
            sec_i = s + 1
            1 <= sec_i <= length(secs) || return nothing
            sec = secs[sec_i]
            field_ref = FieldReference(String(sec.field))
            rest isa EmptyReferencePath && return ConcreteReferencePath(field_ref, EmptyReferencePath())
            @reference_case rest begin
                children{e:_}.inner... => begin
                    entry_i = e + 1
                    1 <= entry_i <= length(sec.entries) || return nothing
                    child = sec.entries[entry_i]
                    translated = inner isa EmptyReferencePath ? EmptyReferencePath() :
                                 map_reference_backward(child.projection, child, inner)
                    translated === nothing && return nothing
                    ConcreteReferencePath(field_ref,
                        ConcreteReferencePath(ElementReference(entry_i), translated))
                end
            end
        end
    end
end

# Build a section-structured node's IO map. `open_ts`/`close_ts` are the
# heading/closing TextStrings, `collapsed` the fold-state cell.
function _ned_section_print(p, recursion, m, ctx, open_ts, close_ts, collapsed, sections)
    reference = ctx.reference
    section_iomaps = Cell(() -> _ned_section_iomaps(recursion, ctx, reference, sections))

    sel = Cell(() -> begin
        path = skip_type_checkpoints(m.selection)
        path isa ConcreteReferencePath && head(path) isa ProjectionReference && return m.selection
        _ned_section_forward(section_iomaps[], m.selection)
    end)

    children_cv = CellVector(() -> SyntaxDocument[
        SyntaxNode(_section_kw(s.label), _empty_ts(), _empty_ts(),
                   SyntaxDocument[im.output for im in s.entries]; indentation=1)
        for s in section_iomaps[]])

    output = SyntaxNode(open_ts, close_ts, _empty_ts(), children_cv, 1, collapsed, sel)
    ChildrenIoMap(p, m, output, section_iomaps)
end

# Shared reference mapping / readers for every section-structured node.
map_reference_forward(p::NedSectionToSyntaxNode, iomap::ChildrenIoMap, reference) =
    _ned_section_forward(iomap.child_iomaps[], reference)

map_reference_backward(p::NedSectionToSyntaxNode, iomap::ChildrenIoMap, reference) =
    _ned_section_backward(iomap.child_iomaps[], reference)

function projection_read(p::NedSectionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::NedSectionToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── Inline token-node infrastructure (param / gate / property) ─────────────
#
# These NED entries render on one line but mix several token colors (type, name,
# @property, string literal). A SyntaxLeaf carries one color per run, so each is
# instead projected to an *inline* SyntaxNode (indentation 0 ⇒ children rendered
# end-to-end, no newlines) whose children are one colored SyntaxLeaf per token.
# By convention the editable name token is always child index 2 (after a
# possibly-empty prefix token holding the type), so the `.name` selection maps to
# `children[2].value` no matter which other tokens are present — keeping the
# whole-element and text-cursor mappings (and thus navigation/editing) intact.
# Tokens other than the name are decorative; selecting one falls through to the
# enclosing file's flat-position fallback.
abstract type NedInlineToNode <: Projection end

_token(text, color, font=_id_font) = SyntaxLeaf(TextString(text, font, color))

# A non-string literal inside a property key keeps the value color; a quoted
# literal is a string constant.
function _literal_token(lit)
    text = lit.text !== nothing ? string(lit.text) : (lit.value !== nothing ? string(lit.value) : "")
    _token(text, startswith(text, "\"") ? _str_color : _val_color)
end

_value_token(v) = (s = string(v); _token(s, startswith(s, "\"") ? _str_color : _val_color))

# Token leaves for a `@property` annotation: "@" + name in property color, the
# parenthesised key list with string constants in string color. When this
# property is a standalone entry the name lands at child index 2 (the "@" is
# child 1); when embedded in a param's token list the leading " " offsets it, so
# only the param's own name (its child 2) stays editable.
function _property_token_leaves(prop)
    leaves = SyntaxDocument[_token("@", _prop_color), _token(prop.name, _prop_color)]
    prop.index !== nothing && push!(leaves, _token("[" * string(prop.index) * "]", _op_color))
    if !isempty(prop.keys)
        push!(leaves, _token("(", _op_color))
        for (i, key) in enumerate(prop.keys)
            i > 1 && push!(leaves, _token(";", _op_color))
            key.name !== nothing && push!(leaves, _token(string(key.name) * "=", _op_color))
            for (j, lit) in enumerate(key.literals)
                j > 1 && push!(leaves, _token(",", _op_color))
                push!(leaves, _literal_token(lit))
            end
        end
        push!(leaves, _token(")", _op_color))
    end
    leaves
end

function _param_token_leaves(param)
    prefix = ""
    param.is_volatile && (prefix *= "volatile ")
    param.type !== nothing && (prefix *= string(param.type) * " ")
    leaves = SyntaxDocument[_token(prefix, _type_color), _token(param.name, _id_color)]
    for prop in param.properties
        push!(leaves, _token(" ", _op_color))
        append!(leaves, _property_token_leaves(prop))
    end
    if param.value !== nothing
        if param.is_default
            push!(leaves, _token(" = default(", _op_color))
            push!(leaves, _value_token(param.value))
            push!(leaves, _token(")", _op_color))
        else
            push!(leaves, _token(" = ", _op_color))
            push!(leaves, _value_token(param.value))
        end
    end
    leaves
end

function _gate_token_leaves(gate)
    prefix = gate.type !== nothing ? string(gate.type) * " " : ""
    leaves = SyntaxDocument[_token(prefix, _type_color), _token(gate.name, _id_color)]
    if gate.is_vector
        push!(leaves, _token("[" * (gate.vector_size !== nothing ? string(gate.vector_size) : "") * "]", _op_color))
    end
    leaves
end

# Build the inline node carrying `input`'s selection. `leaves_fn` yields the
# token leaves (name at index 2); `close` is the trailing ";" delimiter.
function _ned_inline_node(p, input, leaves_fn, close)
    sel = Cell(() -> begin
        path = skip_type_checkpoints(input.selection)
        path isa ConcreteReferencePath && head(path) isa ProjectionReference && return input.selection
        @reference_case input.selection begin
            ∅ => @reference ::SyntaxNode
            name.rest...  => @reference ::SyntaxNode.children[2].value::TextString.^(rest)
            value.rest... => @reference ::SyntaxNode.children[2].value::TextString.^(rest)
        end
    end)
    output = SyntaxNode(_empty_ts(), close, _empty_ts(),
                        CellVector(leaves_fn), 0, Cell(false), sel)
    SimpleIoMap(p, input, output)
end

map_reference_forward(::NedInlineToNode, iomap, reference) =
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        name.rest...  => @reference ::SyntaxNode.children[2].value::TextString.^(rest)
        value.rest... => @reference ::SyntaxNode.children[2].value::TextString.^(rest)
    end

map_reference_backward(::NedInlineToNode, iomap, reference) =
    @reference_case reference begin
        ∅ => @reference()
        ::SyntaxNode.children{1:_}.rest... => begin
            rest isa EmptyReferencePath && return @reference name
            @reference_case rest begin
                value.vrest... => @reference name.^(vrest)
            end
        end
    end

function projection_read(p::NedInlineToNode, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedInlineToNode, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── NedInsertionToSyntaxLeaf ─────────────────────────────────────────────

struct NedInsertionToSyntaxLeaf <: Projection end

map_reference_forward(::NedInsertionToSyntaxLeaf, iomap, reference) =
    skip_type_checkpoints(reference) isa EmptyReferencePath ? (@reference ::SyntaxLeaf) : nothing
map_reference_backward(::NedInsertionToSyntaxLeaf, iomap, reference) =
    skip_type_checkpoints(reference) isa EmptyReferencePath ? EmptyReferencePath() : nothing

function projection_read(p::NedInsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_print(p::NedInsertionToSyntaxLeaf, recursion, ins::NedInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, ins.selection))
    SimpleIoMap(p, ins, SyntaxLeaf(
        _empty_ts(), _empty_ts(),
        TextString("insert NED entry here", _id_font, _comment_color),
        output_selection))
end

# ── NedPackageToSyntaxLeaf ───────────────────────────────────────────────

struct NedPackageToSyntaxLeaf <: Projection end

function map_reference_forward(::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxLeaf
        ::NedPackage.name.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::NedPackage
        ::SyntaxLeaf.value.rest... => @reference ::NedPackage.name::String.^(rest)
    end
end

function projection_read(p::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedPackageToSyntaxLeaf, recursion, pkg::NedPackage, ctx)
    sel = Cell(() -> begin
        @reference_case pkg.selection begin
            ∅ => @reference ::SyntaxLeaf
            name.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    SimpleIoMap(p, pkg, SyntaxLeaf(
        _kw("\npackage "), _op(";"),
        TextString(() -> pkg.name, _id_font, _id_color),
        sel))
end

# ── NedImportToSyntaxLeaf ───────────────────────────────────────────────

struct NedImportToSyntaxLeaf <: Projection end

function map_reference_forward(::NedImportToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxLeaf
        ::NedImport.import_spec.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::NedImportToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::NedImport
        ::SyntaxLeaf.value.rest... => @reference ::NedImport.import_spec::String.^(rest)
    end
end

function projection_read(p::NedImportToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedImportToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedImportToSyntaxLeaf, recursion, imp::NedImport, ctx)
    sel = Cell(() -> begin
        @reference_case imp.selection begin
            ∅ => @reference ::SyntaxLeaf
            import_spec.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    SimpleIoMap(p, imp, SyntaxLeaf(
        _kw("\nimport "), _op(";"),
        TextString(() -> imp.import_spec, _id_font, _id_color),
        sel))
end

# ── NedPropertyToSyntaxLeaf ─────────────────────────────────────────────

struct NedPropertyToSyntaxLeaf <: NedInlineToNode end

function _format_property(prop::NedProperty)
    buf = IOBuffer()
    write(buf, "@", prop.name)
    if prop.index !== nothing
        write(buf, "[", string(prop.index), "]")
    end
    if !isempty(prop.keys)
        write(buf, "(")
        for (i, key) in enumerate(prop.keys)
            i > 1 && write(buf, ";")
            if key.name !== nothing
                write(buf, key.name, "=")
            end
            for (j, lit) in enumerate(key.literals)
                j > 1 && write(buf, ",")
                if lit.text !== nothing
                    write(buf, string(lit.text))
                elseif lit.value !== nothing
                    write(buf, string(lit.value))
                end
            end
        end
        write(buf, ")")
    end
    String(take!(buf))
end

projection_print(p::NedPropertyToSyntaxLeaf, recursion, prop::NedProperty, ctx) =
    _ned_inline_node(p, prop, () -> _property_token_leaves(prop), _op(";"))

# ── NedParamToSyntaxLeaf ─────────────────────────────────────────────────

struct NedParamToSyntaxLeaf <: NedInlineToNode end

function _format_param(param::NedParam)
    buf = IOBuffer()
    param.is_volatile && write(buf, "volatile ")
    param.type !== nothing && write(buf, string(param.type), " ")
    write(buf, param.name)
    for prop in param.properties
        write(buf, " ", _format_property(prop))
    end
    if param.value !== nothing
        if param.is_default
            write(buf, " = default(", string(param.value), ")")
        else
            write(buf, " = ", string(param.value))
        end
    end
    String(take!(buf))
end

projection_print(p::NedParamToSyntaxLeaf, recursion, param::NedParam, ctx) =
    _ned_inline_node(p, param, () -> _param_token_leaves(param), _op(";"))

# ── NedGateToSyntaxLeaf ──────────────────────────────────────────────────

struct NedGateToSyntaxLeaf <: NedInlineToNode end

function _format_gate(gate::NedGate)
    buf = IOBuffer()
    gate.type !== nothing && write(buf, string(gate.type), " ")
    write(buf, gate.name)
    if gate.is_vector
        write(buf, "[")
        gate.vector_size !== nothing && write(buf, string(gate.vector_size))
        write(buf, "]")
    end
    String(take!(buf))
end

projection_print(p::NedGateToSyntaxLeaf, recursion, gate::NedGate, ctx) =
    _ned_inline_node(p, gate, () -> _gate_token_leaves(gate), _op(";"))

# ── NedConnectionToSyntaxLeaf ────────────────────────────────────────────

struct NedConnectionToSyntaxLeaf <: Projection end

function _format_gate_spec(mod, mod_idx, gate, subg, gate_idx, gate_pp)
    buf = IOBuffer()
    if mod !== nothing
        write(buf, string(mod))
        mod_idx !== nothing && write(buf, "[", string(mod_idx), "]")
        write(buf, ".")
    end
    write(buf, string(gate))
    subg !== nothing && write(buf, "\$", string(subg))
    gate_idx !== nothing && write(buf, "[", string(gate_idx), "]")
    gate_pp && write(buf, "++")
    String(take!(buf))
end

function _format_connection(c::NedConnection)
    buf = IOBuffer()
    write(buf, _format_gate_spec(c.src_module, c.src_module_index,
                                  c.src_gate, c.src_gate_subg,
                                  c.src_gate_index, c.src_gate_plusplus))
    arrow = c.is_bidirectional ? " <--> " : (c.is_forward_arrow ? " --> " : " <-- ")
    if c.type !== nothing
        write(buf, arrow, string(c.type), arrow)
    elseif !isempty(c.params)
        write(buf, arrow, "{ ")
        for (i, p) in enumerate(c.params)
            i > 1 && write(buf, " ")
            if p isa NedParam
                write(buf, _format_param(p), ";")
            elseif p isa NedProperty
                write(buf, _format_property(p), ";")
            end
        end
        write(buf, " }", arrow)
    else
        write(buf, arrow)
    end
    write(buf, _format_gate_spec(c.dest_module, c.dest_module_index,
                                  c.dest_gate, c.dest_gate_subg,
                                  c.dest_gate_index, c.dest_gate_plusplus))
    for cond in c.conditions
        cond.condition !== nothing && write(buf, " if ", string(cond.condition))
    end
    String(take!(buf))
end

# A connection is rendered as one flat text leaf; only the whole element is
# independently selectable (its many sub-fields have no addressable cursor).
map_reference_forward(::NedConnectionToSyntaxLeaf, iomap::SimpleIoMap, reference) =
    skip_type_checkpoints(reference) isa EmptyReferencePath ? (@reference ::SyntaxLeaf) : nothing
map_reference_backward(::NedConnectionToSyntaxLeaf, iomap::SimpleIoMap, reference) =
    skip_type_checkpoints(reference) isa EmptyReferencePath ? EmptyReferencePath() : nothing

function projection_read(p::NedConnectionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_print(p::NedConnectionToSyntaxLeaf, recursion, conn::NedConnection, ctx)
    sel = Cell(() -> skip_type_checkpoints(conn.selection) isa EmptyReferencePath ? (@reference ::SyntaxLeaf) : nothing)
    SimpleIoMap(p, conn, SyntaxLeaf(
        _empty_ts(), _op(";"),
        TextString(() -> _format_connection(conn), _id_font, _val_color),
        sel))
end

# ── NedConnectionGroupToSyntaxNode ───────────────────────────────────────

struct NedConnectionGroupToSyntaxNode <: Projection end

function _format_loop_header(group::NedConnectionGroup)
    buf = IOBuffer()
    for (i, loop) in enumerate(group.loops)
        i > 1 && write(buf, ", ")
        write(buf, "for ", loop.param_name, "=")
        loop.from_value !== nothing && write(buf, string(loop.from_value))
        write(buf, "..")
        loop.to_value !== nothing && write(buf, string(loop.to_value))
    end
    for cond in group.conditions
        !isempty(buf.data) && write(buf, ", ")
        write(buf, "if ")
        cond.condition !== nothing && write(buf, string(cond.condition))
    end
    String(take!(buf))
end

function map_reference_forward(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        ::NedConnectionGroup.connections{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::NedConnectionGroup
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = rest isa EmptyReferencePath ? EmptyReferencePath() :
                         map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference ::NedConnectionGroup.connections[child_i].^(translated)
        end
    end
end

function projection_read(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedConnectionGroupToSyntaxNode, recursion, group::NedConnectionGroup, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, conn,
                                   child_context(ctx, @reference ^(reference).connections[i]))
                               for (i, conn) in enumerate(group.connections)])

    sel = Cell(() -> begin
        path = skip_type_checkpoints(group.selection)
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return group.selection
        @reference_case path begin
            ∅ => @reference()
            connections{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    output = SyntaxNode(
        TextString(() -> _format_loop_header(group), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    ChildrenIoMap(p, group, output, child_iomaps)
end

# ── Section heading helpers ───────────────────────────────────────────────

function _module_heading(keyword::AbstractString, m, has_extends::Bool=true)
    buf = IOBuffer()
    write(buf, "\n\n", keyword, " ", m.name)
    if has_extends && m.extends !== nothing
        write(buf, " extends ", m.extends.name)
    end
    if hasproperty(m, :interface_names) && !isempty(m.interface_names)
        write(buf, " like ")
        for (i, iface) in enumerate(m.interface_names)
            i > 1 && write(buf, ", ")
            write(buf, iface.name)
        end
    end
    write(buf, " {")
    String(take!(buf))
end

function _interface_heading(keyword::AbstractString, m)
    buf = IOBuffer()
    write(buf, "\n\n", keyword, " ", m.name)
    if !isempty(m.extends_list)
        write(buf, " extends ")
        for (i, e) in enumerate(m.extends_list)
            i > 1 && write(buf, ", ")
            write(buf, e.name)
        end
    end
    write(buf, " {")
    String(take!(buf))
end

# ── Generic body projection helper ───────────────────────────────────────

# Build a reference path like `reference.field_name[i]` dynamically.
# The @reference macro cannot interpolate dynamic field names (Symbols).
function _field_child_ref(reference, field_name::Symbol, i::Int)
    append_reference(reference, FieldReference(String(field_name)), ElementReference(i))
end

# ── NedSimpleModuleToSyntaxNode ──────────────────────────────────────────

struct NedSimpleModuleToSyntaxNode <: NedSectionToSyntaxNode end

function projection_print(p::NedSimpleModuleToSyntaxNode, recursion, m::NedSimpleModule, ctx)
    sections = [("parameters:", :params, m.params), ("gates:", :gates, m.gates)]
    _ned_section_print(p, recursion, m, ctx,
        TextString(() -> _module_heading("simple", m), _kw_font, _kw_color),
        _op("}"), Cell(false), sections)
end

# ── NedCompoundModuleToSyntaxNode ────────────────────────────────────────

struct NedCompoundModuleToSyntaxNode <: NedSectionToSyntaxNode end

function projection_print(p::NedCompoundModuleToSyntaxNode, recursion, m::NedCompoundModule, ctx)
    sections = [
        ("parameters:", :params, m.params),
        ("gates:", :gates, m.gates),
        ("types:", :types, m.types),
        ("submodules:", :submodules, m.submodules),
        ("connections:", :connections, m.connections),
    ]
    _ned_section_print(p, recursion, m, ctx,
        TextString(() -> _module_heading("network", m), _kw_font, _kw_color),
        _op("}"), m.collapsed, sections)
end

# ── NedModuleInterfaceToSyntaxNode ───────────────────────────────────────

struct NedModuleInterfaceToSyntaxNode <: NedSectionToSyntaxNode end

function projection_print(p::NedModuleInterfaceToSyntaxNode, recursion, m::NedModuleInterface, ctx)
    sections = [("parameters:", :params, m.params), ("gates:", :gates, m.gates)]
    _ned_section_print(p, recursion, m, ctx,
        TextString(() -> _interface_heading("moduleinterface", m), _kw_font, _kw_color),
        _op("}"), Cell(false), sections)
end

# ── NedChannelToSyntaxNode ───────────────────────────────────────────────

struct NedChannelToSyntaxNode <: NedSectionToSyntaxNode end

function projection_print(p::NedChannelToSyntaxNode, recursion, ch::NedChannel, ctx)
    sections = [("parameters:", :params, ch.params)]
    _ned_section_print(p, recursion, ch, ctx,
        TextString(() -> _module_heading("channel", ch), _kw_font, _kw_color),
        _op("}"), Cell(false), sections)
end

# ── NedChannelInterfaceToSyntaxNode ──────────────────────────────────────

struct NedChannelInterfaceToSyntaxNode <: NedSectionToSyntaxNode end

function projection_print(p::NedChannelInterfaceToSyntaxNode, recursion, ci::NedChannelInterface, ctx)
    sections = [("parameters:", :params, ci.params)]
    _ned_section_print(p, recursion, ci, ctx,
        TextString(() -> _interface_heading("channelinterface", ci), _kw_font, _kw_color),
        _op("}"), Cell(false), sections)
end

# ── NedSubmoduleToSyntaxNode ─────────────────────────────────────────────

struct NedSubmoduleToSyntaxNode <: NedSectionToSyntaxNode end

function _format_submodule_heading(s::NedSubmodule)
    buf = IOBuffer()
    write(buf, s.name)
    s.vector_size !== nothing && write(buf, "[", string(s.vector_size), "]")
    write(buf, ": ")
    if s.like_type !== nothing
        write(buf, "<")
        s.like_expr !== nothing && write(buf, string(s.like_expr))
        write(buf, "> like ", string(s.like_type))
    elseif s.type !== nothing
        write(buf, string(s.type))
    end
    if isempty(s.params) && isempty(s.gates)
        write(buf, ";")
    else
        write(buf, " {")
    end
    String(take!(buf))
end

function projection_print(p::NedSubmoduleToSyntaxNode, recursion, sub::NedSubmodule, ctx)
    sections = [("parameters:", :params, sub.params), ("gates:", :gates, sub.gates)]
    _ned_section_print(p, recursion, sub, ctx,
        TextString(() -> _format_submodule_heading(sub), _id_font, _id_color),
        TextString(() -> (isempty(sub.params) && isempty(sub.gates)) ? "" : "}", _id_font, _op_color),
        Cell(false), sections)
end

# ── NedFileToSyntaxNode ──────────────────────────────────────────────────

struct NedFileToSyntaxNode <: Projection end

function map_reference_forward(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        ::NedFile.children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = rest isa EmptyReferencePath ? EmptyReferencePath() :
                    map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::NedFile
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = rest isa EmptyReferencePath ? EmptyReferencePath() :
                         map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference ::NedFile.children[child_i].^(translated)
        end
    end
end

function projection_read(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedFileToSyntaxNode, recursion, f::NedFile, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, child,
                                   child_context(ctx, @reference ^(reference).children[i]))
                               for (i, child) in enumerate(f)])

    sel = Cell(() -> begin
        path = skip_type_checkpoints(f.selection)
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return f.selection
        @reference_case path begin
            ∅ => @reference()
            children{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    # Inline (indentation 0): top-level declarations are not indented. Each one
    # carries its own leading newline(s) — the module headings begin with "\n\n"
    # and the package/import leaves with "\n\n" — so they sit flush at column 0
    # (and each module's closing "}" dedents to column 0 as well).
    output = SyntaxNode(
        _empty_ts(), _empty_ts(), _empty_ts(),
        children_cv, 0, Cell(false), sel)
    ChildrenIoMap(p, f, output, child_iomaps)
end

# ── Compound convenience constructor ─────────────────────────────────────

function NedToSyntax()
    TypeDispatchingProjection(
        NedInsertion       => NedInsertionToSyntaxLeaf(),
        NedPackage         => NedPackageToSyntaxLeaf(),
        NedImport          => NedImportToSyntaxLeaf(),
        NedProperty        => NedPropertyToSyntaxLeaf(),
        NedParam           => NedParamToSyntaxLeaf(),
        NedGate            => NedGateToSyntaxLeaf(),
        NedSubmodule       => NedSubmoduleToSyntaxNode(),
        NedConnection      => NedConnectionToSyntaxLeaf(),
        NedConnectionGroup => NedConnectionGroupToSyntaxNode(),
        NedSimpleModule    => NedSimpleModuleToSyntaxNode(),
        NedCompoundModule  => NedCompoundModuleToSyntaxNode(),
        NedModuleInterface => NedModuleInterfaceToSyntaxNode(),
        NedChannel         => NedChannelToSyntaxNode(),
        NedChannelInterface => NedChannelInterfaceToSyntaxNode(),
        NedFile            => NedFileToSyntaxNode(),
    )
end

end # module
